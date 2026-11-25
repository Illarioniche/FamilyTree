import AppKit
import Combine
import FamilyTreeCore
import UniformTypeIdentifiers

enum LibrarySection: String, CaseIterable, Identifiable {
    case tree, people, timeline, archive
    var id: Self { self }
    var title: String {
        switch self { case .tree: return "Семейное дерево"; case .people: return "Люди"; case .timeline: return "Хроника"; case .archive: return "Семейный архив" }
    }
    var symbol: String {
        switch self { case .tree: return "point.3.connected.trianglepath.dotted"; case .people: return "person.2"; case .timeline: return "clock"; case .archive: return "photo.on.rectangle.angled" }
    }
}

enum RelativeRole: String, CaseIterable, Identifiable {
    case parent, child, partner, adoptiveParent
    var id: Self { self }
    var title: String {
        switch self { case .parent: return "Родитель"; case .child: return "Ребёнок"; case .partner: return "Партнёр"; case .adoptiveParent: return "Приёмный родитель" }
    }
    func relationship(newPersonID: UUID, relativeID: UUID) -> Relationship {
        Relationship(fromID: self == .child ? relativeID : newPersonID,
                     toID: self == .child ? newPersonID : relativeID,
                     kind: self == .partner ? .partner : (self == .adoptiveParent ? .adoptiveParent : .parent))
    }
}

struct PersonEditRequest: Identifiable {
    let id = UUID()
    var person: Person
    var isNew: Bool
    var relativeID: UUID?
}

struct EventEditRequest: Identifiable {
    let id = UUID()
    var event: FamilyEvent
}

struct TreeCreationRequest: Identifiable {
    let id = UUID()
    var project: FamilyProject
    var warnings: [String]
    var isImport: Bool
}

@MainActor
final class FamilyStore: ObservableObject {
    @Published private(set) var project: FamilyProject
    @Published var selection: UUID?
    @Published var section: LibrarySection = .tree
    @Published var query = ""
    @Published var showingTreeLibrary = true
    @Published private(set) var savedTrees: [TreeLibraryEntry] = []
    @Published var treeCreation: TreeCreationRequest?
    @Published private(set) var fileURL: URL?
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var isExample = true
    @Published private(set) var lastSavedAt: Date?
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var infoMessage: String?
    @Published var personEditor: PersonEditRequest?
    @Published var eventEditor: EventEditRequest?
    @Published var showingRelationshipEditor = false
    @Published var showingProjectName = false
    @Published var showingSurnameReview = false
    @Published var showingHomePersonPicker = false
    @Published var peopleSearchRequest = 0
    @Published private(set) var homeFocusRequest = 0
    @Published private(set) var undoStack: [FamilyProject] = []
    @Published private(set) var redoStack: [FamilyProject] = []
    private let isPreview: Bool
    private let library: TreeLibrary
    private let libraryDirectoryURL: URL
    private var registeredTreeURLs: [URL]
    private static let registeredTreesKey = "registeredTreePaths"

    init(preview: Bool = false, libraryDirectoryURL: URL? = nil) {
        isPreview = preview
        let directory = libraryDirectoryURL ?? (preview
            ? FileManager.default.temporaryDirectory.appendingPathComponent("FamilyTreePreview-" + UUID().uuidString, isDirectory: true)
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FamilyTree/Trees", isDirectory: true))
        self.libraryDirectoryURL = directory.standardizedFileURL.resolvingSymlinksInPath()
        library = TreeLibrary(directoryURL: directory)
        registeredTreeURLs = preview ? [] : (UserDefaults.standard.stringArray(forKey: Self.registeredTreesKey) ?? []).map { URL(fileURLWithPath: $0) }
        project = .demo
        selection = project.rootPersonID
        if !preview, let path = UserDefaults.standard.string(forKey: "lastProjectPath") {
            let url = URL(fileURLWithPath: path)
            registerExternalTree(url)
            do {
                project = try ProjectDatabase.load(from: url)
                fileURL = url; selection = project.rootPersonID ?? project.people.first?.id
                isExample = false; lastSavedAt = project.modifiedAt
            } catch {
                // The library lists unavailable external documents with their issue.
                // Keep the previous document untouched and let the user choose another tree.
            }
        }
        refreshLibrary()
    }

    var selectedPerson: Person? { project.person(selection) }
    var surnameRepairSuggestions: [SurnameRepairSuggestion] { LegacySurnameRepair.suggestions(in: project) }

    func applySurnameRepairs(_ suggestions: [SurnameRepairSuggestion]) {
        mutate { _ = LegacySurnameRepair.apply(suggestions, to: &$0) }
    }
    var filteredPeople: [Person] {
        PeopleSearch.filter(project.people, query: query)
            .sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
    }
    var status: String {
        if hasUnsavedChanges { return "Есть несохранённые изменения" }
        if isExample { return "Пример · вымышленные данные" }
        return fileURL == nil ? "Выберите место для сохранения" : "Сохранено на этом Mac"
    }

    func mutate(_ update: (inout FamilyProject) -> Void) {
        var next = project
        update(&next)
        guard next != project else { return }
        do { try ProjectValidation.validate(next) }
        catch { errorMessage = error.localizedDescription; return }
        undoStack.append(project)
        if undoStack.count > 30 { undoStack.removeFirst() }
        redoStack.removeAll()
        next.modifiedAt = Date()
        project = next
        hasUnsavedChanges = true
        if fileURL != nil { _ = save() }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project); project = previous; project.modifiedAt = Date()
        if project.person(selection) == nil { selection = project.rootPersonID ?? project.people.first?.id }
        hasUnsavedChanges = true
        if fileURL != nil { _ = save() }
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project); project = next; project.modifiedAt = Date()
        if project.person(selection) == nil { selection = project.rootPersonID ?? project.people.first?.id }
        hasUnsavedChanges = true
        if fileURL != nil { _ = save() }
    }

    @discardableResult func save() -> Bool {
        guard let url = fileURL else { return saveAs() }
        guard hasUnsavedChanges else { return true }
        do {
            try ProjectDatabase.save(project, to: url)
            hasUnsavedChanges = false; lastSavedAt = Date(); isExample = false
            updateLibraryEntry(at: url)
            return true
        } catch { errorMessage = "Не удалось сохранить дерево. Изменения остаются в приложении.\n\n\(error.localizedDescription)"; return false }
    }

    @discardableResult func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.title = "Сохранить семейное дерево"
        panel.message = "Люди, связи, фотографии и документы сохранятся в одном файле."
        panel.allowedContentTypes = [.familyTree]
        panel.nameFieldStringValue = "\(project.title).familytree"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try ProjectDatabase.save(project, to: url)
            fileURL = url; hasUnsavedChanges = false; lastSavedAt = Date(); isExample = false
            remember(url)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func showLibrary() {
        refreshLibrary()
        showingTreeLibrary = true
    }

    func refreshLibrary() {
        do { savedTrees = try library.entries(additionalURLs: registeredTreeURLs) }
        catch { errorMessage = "Не удалось прочитать библиотеку деревьев.\n\n\(error.localizedDescription)" }
    }

    func newProject() {
        errorMessage = nil
        treeCreation = TreeCreationRequest(project: FamilyProject(title: "Моя семья"), warnings: [], isImport: false)
    }

    func completeTreeCreation(title: String) {
        guard let request = treeCreation else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { errorMessage = "Укажите название дерева."; return }
        guard confirmLeaving() else { return }
        var created = request.project
        created.id = UUID()
        created.title = title
        created.createdAt = Date(); created.modifiedAt = created.createdAt
        do {
            let url = try library.create(created)
            replaceProject(created, url: url)
            treeCreation = nil
        } catch { errorMessage = "Не удалось создать дерево.\n\n\(error.localizedDescription)" }
    }

    func openLibraryTree(_ entry: TreeLibraryEntry) {
        openProject(at: entry.url)
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Открыть семейное дерево"
        panel.allowedContentTypes = [.familyTree, .data]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        guard confirmLeaving() else { return }
        do { let opened = try ProjectDatabase.load(from: url); replaceProject(opened, url: url) }
        catch { errorMessage = "Дерево не открыто. Текущий проект не изменён.\n\n\(error.localizedDescription)" }
    }

    func replaceProject(_ new: FamilyProject, url: URL?) {
        project = new; fileURL = url; isExample = false; hasUnsavedChanges = url == nil
        selection = new.rootPersonID ?? new.people.first?.id
        section = .tree; query = ""; undoStack.removeAll(); redoStack.removeAll()
        showingSurnameReview = false; showingHomePersonPicker = false
        showingTreeLibrary = false; treeCreation = nil
        lastSavedAt = url == nil ? nil : new.modifiedAt
        if let url { remember(url) }
    }

    func showExample() {
        guard confirmLeaving() else { return }
        replaceProject(.demo, url: nil); isExample = true; hasUnsavedChanges = false
    }

    func confirmLeaving() -> Bool {
        guard hasUnsavedChanges else { return true }
        // Preview/check modes never show a dialog or silently discard an edited tree.
        guard !isPreview else { return false }
        let alert = NSAlert()
        alert.messageText = "Сохранить изменения в дереве?"
        alert.informativeText = "В дереве «\(project.title)» есть изменения, которые ещё не записаны в файл."
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Отмена")
        alert.addButton(withTitle: "Не сохранять")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    func importGEDCOM() { importTree() }

    func importTree() {
        let panel = NSOpenPanel()
        panel.title = "Импортировать дерево"
        panel.message = "Выберите GEDCOM или файл .familytree. В библиотеке появится отдельная копия."
        panel.allowedContentTypes = [.familyTree, UTType(filenameExtension: "ged") ?? .plainText, .plainText, .data]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = prepareTreeImport(at: url)
    }

    /// Shared by the file picker and isolated checks. Reading never replaces the active document.
    @discardableResult func prepareTreeImport(at url: URL) -> Bool {
        errorMessage = nil
        do {
            let imported: FamilyProject
            let warnings: [String]
            if url.pathExtension.lowercased() == "familytree" {
                imported = try ProjectDatabase.load(from: url)
                warnings = []
            } else {
                let result = try GEDCOM.importData(Data(contentsOf: url), title: "Моя семья")
                imported = result.project; warnings = result.warnings
            }
            try ProjectValidation.validate(imported)
            treeCreation = TreeCreationRequest(project: imported, warnings: warnings, isImport: true)
            return true
        } catch {
            errorMessage = "Импорт не выполнен.\n\n\(error.localizedDescription)"
            return false
        }
    }

    func exportGEDCOM() {
        let panel = NSSavePanel()
        panel.title = "Экспортировать GEDCOM"
        panel.message = "Формат для других генеалогических программ. Фото и документы не включаются. Полная копия дерева — файл .familytree."
        panel.allowedContentTypes = [UTType(filenameExtension: "ged") ?? .plainText]
        panel.nameFieldStringValue = "\(project.title).ged"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try GEDCOM.export(project).write(to: url, options: .atomic) }
        catch { errorMessage = error.localizedDescription }
    }

    func addPerson(relativeTo id: UUID? = nil) {
        personEditor = PersonEditRequest(person: Person(familyName: project.person(id)?.familyName ?? ""), isNew: true, relativeID: id)
    }
    func edit(_ person: Person) { personEditor = PersonEditRequest(person: person, isNew: false) }
    func savePerson(_ person: Person, relativeID: UUID?, role: RelativeRole, photo: Attachment?) {
        var savedPerson = person
        if let photo { savedPerson.photoID = photo.id }
        mutate { tree in
            if let index = tree.people.firstIndex(where: { $0.id == person.id }) { tree.people[index] = savedPerson }
            else { tree.people.append(savedPerson) }
            if tree.rootPersonID == nil { tree.rootPersonID = person.id }
            for index in tree.events.indices where tree.events[index].personID == person.id {
                if tree.events[index].kind == .birth {
                    tree.events[index].date = savedPerson.birthDate
                    tree.events[index].place = savedPerson.birthPlace
                }
                if tree.events[index].kind == .death { tree.events[index].date = savedPerson.deathDate }
            }
            if !savedPerson.isDeceased {
                tree.events.removeAll { $0.personID == person.id && $0.kind == .death }
            }
            if let relativeID { tree.relationships.append(role.relationship(newPersonID: person.id, relativeID: relativeID)) }
            if let photo {
                tree.attachments.removeAll { $0.id == photo.id }
                tree.attachments.append(photo)
            }
        }
        if project.person(person.id) != nil { selection = person.id }
    }
    func deletePerson(_ person: Person) {
        let alert = NSAlert()
        alert.messageText = "Удалить \(person.fullName)?"
        alert.informativeText = "Будут удалены карточка, её связи, события и вложения. Действие можно отменить через меню «Правка»."
        alert.addButton(withTitle: "Удалить"); alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        mutate { $0.removePerson(person.id) }
        selection = project.rootPersonID ?? project.people.first?.id
    }
    func toggleFavorite(_ person: Person) {
        mutate { tree in if let index = tree.people.firstIndex(where: { $0.id == person.id }) { tree.people[index].isFavorite.toggle() } }
    }
    /// The default centre belongs to the document; browsing another branch does not change it.
    func setRoot(_ id: UUID) {
        guard project.person(id) != nil else { return }
        mutate { $0.rootPersonID = id }
        guard project.rootPersonID == id else { return }
        goToHomePerson()
    }

    func goToHomePerson() {
        guard let id = project.rootPersonID, project.person(id) != nil else { return }
        selection = id; section = .tree
        homeFocusRequest += 1
    }

    func focusPeopleSearch() {
        section = .people
        peopleSearchRequest += 1
    }

    func saveEvent(_ event: FamilyEvent) {
        mutate { tree in
            if let index = tree.events.firstIndex(where: { $0.id == event.id }) { tree.events[index] = event }
            else { tree.events.append(event) }
            if let index = tree.people.firstIndex(where: { $0.id == event.personID }) {
                if event.kind == .birth {
                    tree.people[index].birthDate = event.date
                    tree.people[index].birthPlace = event.place
                } else if event.kind == .death {
                    tree.people[index].deathDate = event.date
                    tree.people[index].isDeceased = true
                }
            }
        }
    }

    func deleteEvent(_ event: FamilyEvent) {
        mutate { tree in
            tree.events.removeAll { $0.id == event.id }
            guard let index = tree.people.firstIndex(where: { $0.id == event.personID }) else { return }
            let replacement = tree.events.first { $0.personID == event.personID && $0.kind == event.kind }
            if event.kind == .birth {
                tree.people[index].birthDate = replacement?.date ?? ""
                if tree.people[index].birthPlace == event.place { tree.people[index].birthPlace = replacement?.place ?? "" }
            } else if event.kind == .death {
                // Removing a date does not imply that the person is alive.
                tree.people[index].deathDate = replacement?.date ?? ""
            }
        }
    }

    func addAttachment(to personID: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Добавить в семейный архив"
        panel.allowedContentTypes = [.image, .pdf, .plainText]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do {
            let added = try panel.urls.map { url -> Attachment in
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 30 * 1024 * 1024 else { throw AppError.message("«\(url.lastPathComponent)» больше 30 МБ. Выберите файл меньшего размера.") }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                return Attachment(personID: personID, filename: url.lastPathComponent, mimeType: mime, data: try Data(contentsOf: url))
            }
            mutate { $0.attachments.append(contentsOf: added) }
        } catch { errorMessage = error.localizedDescription }
    }

    func exportAttachment(_ attachment: Attachment) {
        let panel = NSSavePanel()
        panel.title = "Сохранить вложение"
        panel.nameFieldStringValue = URL(fileURLWithPath: attachment.filename).lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try attachment.data.write(to: url, options: .atomic) }
        catch { errorMessage = error.localizedDescription }
    }

    func revealFile() { if let fileURL { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) } }
    private func remember(_ url: URL) {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        registerExternalTree(canonical)
        updateLibraryEntry(at: canonical)
        guard !isPreview else { return }
        UserDefaults.standard.set(canonical.path, forKey: "lastProjectPath")
        NSDocumentController.shared.noteNewRecentDocumentURL(canonical)
    }

    private func registerExternalTree(_ url: URL) {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        guard canonical.deletingLastPathComponent() != libraryDirectoryURL else { return }
        if !registeredTreeURLs.contains(where: { $0.standardizedFileURL.resolvingSymlinksInPath() == canonical }) {
            registeredTreeURLs.append(canonical)
        }
        if !isPreview { UserDefaults.standard.set(registeredTreeURLs.map(\.path), forKey: Self.registeredTreesKey) }
    }

    /// Autosave only updates the active entry; a full directory scan is needed when opening the library.
    private func updateLibraryEntry(at url: URL) {
        let entry = TreeLibraryEntry(url: url, title: project.title, peopleCount: project.people.count, modifiedAt: project.modifiedAt)
        savedTrees.removeAll { $0.id == entry.id }
        savedTrees.append(entry)
        savedTrees.sort {
            $0.modifiedAt == $1.modifiedAt ? $0.id < $1.id : $0.modifiedAt > $1.modifiedAt
        }
    }

}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

extension UTType {
    static let familyTree = UTType(exportedAs: "local.rodnye.familytree", conformingTo: .data)
}
