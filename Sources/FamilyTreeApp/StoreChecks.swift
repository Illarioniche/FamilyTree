import Foundation
import FamilyTreeCore

/// An integration check for editing/autosave/undo. Uses an isolated temporary tree,
/// never the user's recent project, preferences, dialogs or application windows.
@MainActor
enum StoreChecks {
    private static var assertions = 0
    static func run() {
        assertions = 0
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RodnyeStoreCheck-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let document = directory.appendingPathComponent("Проверка.familytree")
            let empty = FamilyProject(title: "Проверка")
            try ProjectDatabase.save(empty, to: document)
            let store = FamilyStore(preview: true)
            store.replaceProject(empty, url: document)

            let parent = Person(givenName: "Родитель", familyName: "Тестовый")
            store.savePerson(parent, relativeID: nil, role: .parent, photo: nil)
            var child = Person(givenName: "Ребёнок", familyName: "Тестовый", birthDate: "2000")
            let photo = Attachment(personID: child.id, filename: "photo.png", mimeType: "image/png", data: Data([137, 80, 78, 71, 0, 255]))
            store.savePerson(child, relativeID: parent.id, role: .child, photo: photo)
            try require(!store.hasUnsavedChanges, "Autosave must clear dirty state")
            var reopened = try ProjectDatabase.load(from: document)
            try require(reopened.children(of: parent.id).map(\.id) == [child.id], "Parent-child relation must survive reopening")
            try require(reopened.attachments.first?.data == photo.data, "Photo bytes must survive autosave")
            try require(reopened.person(child.id)?.photoID == photo.id, "Photo association must survive autosave")

            let event = FamilyEvent(personID: child.id, kind: .birth, title: "Рождение", date: "2001", place: "Москва")
            store.saveEvent(event)
            try require(store.project.person(child.id)?.birthDate == "2001", "Birth event must update person")
            child = store.project.person(child.id)!
            child.birthDate = "около 2002"
            child.birthPlace = "Тверь"
            store.savePerson(child, relativeID: nil, role: .child, photo: nil)
            try require(store.project.events.first?.date == "около 2002", "Person date must update timeline")
            try require(store.project.events.first?.place == "Тверь", "Birth place must update timeline")

            store.undo()
            try require(store.project.person(child.id)?.birthDate == "2001", "Undo must restore date")
            reopened = try ProjectDatabase.load(from: document)
            try require(reopened.person(child.id)?.birthDate == "2001", "Undo must persist")
            store.redo()
            try require(store.project.person(child.id)?.birthDate == "около 2002", "Redo must restore edit")

            let beforeBackup = try Data(contentsOf: URL(fileURLWithPath: document.path + ".backup"))
            try require(store.save(), "Saving unchanged document should succeed")
            let afterBackup = try Data(contentsOf: URL(fileURLWithPath: document.path + ".backup"))
            try require(beforeBackup == afterBackup, "Saving unchanged document must preserve previous backup")

            let previous = store.project
            store.mutate { $0.relationships.append(Relationship(fromID: child.id, toID: parent.id, kind: .parent)) }
            try require(store.project == previous, "Invalid relationship must leave current state unchanged")
            try require(store.errorMessage != nil, "Invalid relationship must show error")
            store.errorMessage = nil

            // Replacing this isolated test document with invalid bytes simulates an external
            // file problem. Autosave must retain in-memory changes without replacing the file.
            let originalData = try Data(contentsOf: document)
            try Data("unrecognized file".utf8).write(to: document, options: .atomic)
            store.mutate { $0.title = "Несохранённое изменение" }
            try require(store.hasUnsavedChanges, "Failed save must remain dirty")
            try require(store.project.title == "Несохранённое изменение", "Failed save must retain in-memory changes")
            try require(try Data(contentsOf: document) == Data("unrecognized file".utf8), "Unknown external file must not be overwritten")
            try originalData.write(to: document, options: .atomic)
            try require(store.save(), "Save retry after recovery should succeed")
            try require(!store.hasUnsavedChanges, "Successful retry must clear dirty state")
            try require(try ProjectDatabase.load(from: document).title == "Несохранённое изменение", "Retry must persist retained edit")
            if let birthEvent = store.project.events.first(where: { $0.kind == .birth }) {
                store.deleteEvent(birthEvent)
                try require(store.project.person(child.id)?.birthDate == "", "Deleting birth event must clear the derived timeline date")
                try require(!store.project.events.contains { $0.id == birthEvent.id }, "Deleted birth event must stay removed")
            } else { throw AppError.message("Expected birth event for deletion check") }
            let deathEvent = FamilyEvent(personID: child.id, kind: .death, date: "2050")
            store.saveEvent(deathEvent)
            store.deleteEvent(deathEvent)
            try require(store.project.person(child.id)?.deathDate == "", "Deleting death event must clear its date")
            try require(store.project.person(child.id)?.isDeceased == true, "Deleting a date must not resurrect a person")
            try checkSurnameRepairs(in: directory)
            try checkHomePerson(in: directory)
            try checkTreeLibrary(in: directory)
            print("Store integration: \(assertions) checks passed (autosave, media, dates, undo/redo, backup, surname repair, default centre, search navigation, tree library, invalid relation, save failure/retry).")
        } catch {
            fputs("Store integration FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func checkSurnameRepairs(in directory: URL) throws {
        let document = directory.appendingPathComponent("Фамилии.familytree")
        let first = Person(givenName: "Анна", familyName: "Смирнова",
                           biography: "Первая заметка.\n\nДругое имя из GEDCOM: Петрова\n\nПоследняя заметка.")
        let second = Person(givenName: "Мария", familyName: "Белова",
                            biography: "Другое имя из GEDCOM: Соколова")
        let project = FamilyProject(rootPersonID: first.id, people: [first, second])
        try ProjectDatabase.save(project, to: document)
        let store = FamilyStore(preview: true)
        store.replaceProject(try ProjectDatabase.load(from: document), url: document)
        let originalBytes = try Data(contentsOf: document)
        let proposals = store.surnameRepairSuggestions
        try require(proposals.count == 2, "Both old imported surnames should be proposed")
        try require(store.project == project && store.undoStack.isEmpty && !store.hasUnsavedChanges,
                    "Opening a legacy document must not modify it or create undo history")
        try require(try Data(contentsOf: document) == originalBytes, "Preparing proposals must not write the document")

        store.applySurnameRepairs(proposals)
        try require(store.project.person(first.id)?.familyName == "Петрова", "The selected surname must become primary")
        try require(store.project.person(first.id)?.maidenName == "Смирнова", "The former primary surname must be retained")
        try require(store.project.person(first.id)?.biography == "Первая заметка.\n\nПоследняя заметка.",
                    "Only the generated processed paragraph may be removed")
        try require(store.project.person(second.id)?.familyName == "Соколова", "A batch should apply all selected proposals")
        try require(store.undoStack.count == 1 && !store.hasUnsavedChanges, "A saved batch must be one undo step")
        try require(try ProjectDatabase.load(from: document).people == store.project.people,
                    "Corrected surnames must survive reopening")
        let backupURL = URL(fileURLWithPath: document.path + ".backup")
        try require(try ProjectDatabase.load(from: backupURL).people == project.people,
                    "The backup must retain the complete pre-repair names")

        store.undo()
        try require(store.project.people == project.people, "Undo must restore both names and original biographies")
        try require(try ProjectDatabase.load(from: document).people == project.people, "Undo of surname repair must persist")
        store.redo()
        let repairedPeople = store.project.people
        try require(repairedPeople[0].familyName == "Петрова" && repairedPeople[1].familyName == "Соколова",
                    "Redo must reapply the entire surname batch")
        let undoCount = store.undoStack.count
        let bytesAfterRepair = try Data(contentsOf: document)
        store.applySurnameRepairs(proposals)
        try require(store.undoStack.count == undoCount && !store.hasUnsavedChanges,
                    "Reapplying stale proposals must not create history or dirty state")
        try require(try Data(contentsOf: document) == bytesAfterRepair, "Stale proposals must not save the document")

        // A save failure retains the corrected names in memory and preserves disk data.
        let retryDocument = directory.appendingPathComponent("Фамилии-повтор.familytree")
        try ProjectDatabase.save(project, to: retryDocument)
        let retryStore = FamilyStore(preview: true)
        retryStore.replaceProject(project, url: retryDocument)
        let validBytes = try Data(contentsOf: retryDocument)
        let invalidBytes = Data("unrecognized file".utf8)
        try invalidBytes.write(to: retryDocument, options: .atomic)
        retryStore.applySurnameRepairs(retryStore.surnameRepairSuggestions)
        try require(retryStore.hasUnsavedChanges && retryStore.errorMessage != nil,
                    "A failed surname repair save must remain dirty and report an error")
        try require(retryStore.project.people == repairedPeople, "A failed save must retain the reviewed surname changes")
        try require(try Data(contentsOf: retryDocument) == invalidBytes, "Repair must not replace an unrecognized file")
        try validBytes.write(to: retryDocument, options: .atomic)
        try require(retryStore.save(), "Surname repair should save after the external file problem is resolved")
        try require(try ProjectDatabase.load(from: retryDocument).people == repairedPeople,
                    "The successful retry must persist both surnames")
    }

    private static func checkHomePerson(in directory: URL) throws {
        let document = directory.appendingPathComponent("Центр.familytree")
        let first = Person(givenName: "Анна", familyName: "Тестовая")
        let second = Person(givenName: "Пётр", familyName: "Тестовый")
        let third = Person(givenName: "Мария", familyName: "Примерова")
        let original = FamilyProject(rootPersonID: first.id, people: [first, second, third])
        try ProjectDatabase.save(original, to: document)
        let store = FamilyStore(preview: true)
        store.replaceProject(try ProjectDatabase.load(from: document), url: document)
        try require(store.selection == first.id, "Opening a document should select its saved default centre")

        store.setRoot(second.id)
        try require(store.project.rootPersonID == second.id && store.selection == second.id && store.section == .tree,
                    "Choosing yourself should save and navigate to the chosen centre")
        try require(store.undoStack.count == 1 && !store.hasUnsavedChanges,
                    "Changing the default centre should be one saved undo step")
        try require(try ProjectDatabase.load(from: document).rootPersonID == second.id,
                    "The default centre must survive document reopening")
        try require(try ProjectDatabase.load(from: URL(fileURLWithPath: document.path + ".backup")).rootPersonID == first.id,
                    "The backup should retain the previous default centre")

        let savedProject = store.project
        let savedBytes = try Data(contentsOf: document)
        let historyCount = store.undoStack.count
        store.selection = third.id; store.section = .people
        try require(store.project == savedProject && store.undoStack.count == historyCount,
                    "Selecting another person must not replace the default centre or create history")
        let request = store.homeFocusRequest
        store.goToHomePerson()
        try require(store.selection == second.id && store.section == .tree && store.homeFocusRequest == request + 1,
                    "Going home must explicitly request the saved branch, even when its person was already selected")
        store.goToHomePerson()
        try require(store.homeFocusRequest == request + 2 && store.project == savedProject,
                    "Repeated home navigation must remain a view action")
        store.query = "Тестовый"
        let searchRequest = store.peopleSearchRequest
        store.focusPeopleSearch()
        try require(store.section == .people && store.peopleSearchRequest == searchRequest + 1 && store.query == "Тестовый",
                    "Search shortcut should focus the people search without clearing its query")
        try require(store.project == savedProject && store.undoStack.count == historyCount && !store.hasUnsavedChanges,
                    "Search and branch navigation must not change saved project data")
        try require(try Data(contentsOf: document) == savedBytes,
                    "Search and branch navigation must not write the document")

        let previousSelection = store.selection
        let previousSection = store.section
        let previousRequest = store.homeFocusRequest
        store.setRoot(UUID())
        try require(store.project == savedProject && store.selection == previousSelection && store.section == previousSection && store.homeFocusRequest == previousRequest,
                    "A missing person must not become the default or corrupt the current selection")
        store.setRoot(second.id)
        try require(store.undoStack.count == historyCount && !store.hasUnsavedChanges,
                    "Choosing the current default again should only navigate")
        try require(try Data(contentsOf: document) == savedBytes, "Rechoosing the same default must not save again")

        store.undo()
        try require(store.project.rootPersonID == first.id && (try ProjectDatabase.load(from: document)).rootPersonID == first.id,
                    "Undo should restore and persist the previous default centre")
        store.redo()
        try require(store.project.rootPersonID == second.id && (try ProjectDatabase.load(from: document)).rootPersonID == second.id,
                    "Redo should restore and persist the chosen default centre")
        let reopened = FamilyStore(preview: true)
        reopened.replaceProject(try ProjectDatabase.load(from: document), url: document)
        try require(reopened.selection == second.id && reopened.project.rootPersonID == second.id,
                    "Reopening after temporary navigation should start at the saved default")

        // Exercise the same model removal used by the confirmed delete action, without a dialog.
        reopened.mutate { $0.removePerson(second.id) }
        reopened.goToHomePerson()
        try require(reopened.project.rootPersonID == first.id && reopened.selection == first.id,
                    "Deleting the default should leave a valid fallback and home navigation")
        try require(try ProjectDatabase.load(from: document).rootPersonID == first.id,
                    "The fallback after deleting the default should persist")
        reopened.undo()
        try require(reopened.project.rootPersonID == second.id && reopened.project.person(second.id) != nil,
                    "Undoing deletion must restore the person and their default status")
        reopened.mutate { tree in
            for person in tree.people { tree.removePerson(person.id) }
        }
        let emptyRequest = reopened.homeFocusRequest
        reopened.goToHomePerson()
        try require(reopened.project.rootPersonID == nil && reopened.homeFocusRequest == emptyRequest,
                    "Home navigation on an empty tree must be harmless")
    }

    private static func checkTreeLibrary(in directory: URL) throws {
        let libraryURL = directory.appendingPathComponent("Library", isDirectory: true)
        let store = FamilyStore(preview: true, libraryDirectoryURL: libraryURL)
        try require(store.showingTreeLibrary && store.savedTrees.isEmpty && store.fileURL == nil,
                    "An isolated preview should start in its empty library without reading user preferences")
        let initial = store.project
        store.newProject()
        try require(store.treeCreation?.project.people.isEmpty == true && store.treeCreation?.project.title == "Моя семья" && store.treeCreation?.isImport == false,
                    "New-tree staging must contain an empty project with a human title")
        try require(store.project == initial && !FileManager.default.fileExists(atPath: libraryURL.path),
                    "Opening the creation form must not replace the current project or create a file")
        store.completeTreeCreation(title: "   ")
        try require(store.treeCreation != nil && store.project == initial && store.errorMessage != nil,
                    "An empty title must keep the request and active project untouched")
        store.errorMessage = nil
        store.completeTreeCreation(title: "  Семья Проверкиных  ")
        guard let firstURL = store.fileURL else { throw AppError.message("Expected a managed tree after creation") }
        let firstID = store.project.id
        try require(store.project.title == "Семья Проверкиных" && store.project.people.isEmpty && store.project.rootPersonID == nil,
                    "Creating a tree must use its trimmed title and no demo people")
        try require(!store.showingTreeLibrary && store.treeCreation == nil && store.personEditor == nil && !store.hasUnsavedChanges,
                    "Successful creation should open the saved empty tree without opening a person editor")
        try require(store.savedTrees.count == 1 && store.savedTrees.first?.title == "Семья Проверкиных" && store.savedTrees.first?.peopleCount == 0,
                    "The new tree should immediately appear in the library by project title")
        let person = Person(givenName: "Анна", familyName: "Проверкина")
        store.savePerson(person, relativeID: nil, role: .parent, photo: nil)
        store.mutate { $0.title = "Проверкины" }
        try require(store.savedTrees.first?.title == "Проверкины" && store.savedTrees.first?.peopleCount == 1,
                    "Autosave should update the active library entry without reopening the library")
        let firstSavedBytes = try Data(contentsOf: firstURL)
        store.newProject()
        store.completeTreeCreation(title: "Проверкины")
        guard let secondURL = store.fileURL else { throw AppError.message("Expected second managed tree") }
        try require(secondURL != firstURL && store.project.id != firstID && store.project.people.isEmpty && store.savedTrees.count == 2,
                    "Two trees with the same title must have independent documents and identities")
        try require(try Data(contentsOf: firstURL) == firstSavedBytes,
                    "Creating another tree must not rewrite the first tree")
        guard let firstEntry = store.savedTrees.first(where: { $0.url == firstURL.standardizedFileURL.resolvingSymlinksInPath() }) else {
            throw AppError.message("Expected first library entry")
        }
        store.openLibraryTree(firstEntry)
        try require(store.fileURL == firstURL && store.project.id == firstID && store.selection == person.id,
                    "Switching trees must load the selected document and its saved default person")
        let activeBeforeLibrary = store.project
        let selectedBeforeLibrary = store.selection
        store.showLibrary()
        try require(store.showingTreeLibrary && store.project == activeBeforeLibrary && store.selection == selectedBeforeLibrary,
                    "Showing the library must preserve the active project and selection")
        try require(try Data(contentsOf: firstURL) == firstSavedBytes,
                    "Showing the library must not save or rewrite the active document")

        let sourceURL = directory.appendingPathComponent("machine-export-name.familytree")
        var source = FamilyProject(title: "Родословная Примеровых", rootPersonID: person.id, people: [person])
        source.attachments = [Attachment(personID: person.id, filename: "note.txt", mimeType: "text/plain", data: Data("Вложение".utf8))]
        try ProjectDatabase.save(source, to: sourceURL)
        let sourceBytes = try Data(contentsOf: sourceURL)
        try require(store.prepareTreeImport(at: sourceURL), "A native tree should be available for import")
        try require(store.treeCreation?.project == source && store.treeCreation?.isImport == true && store.project == activeBeforeLibrary,
                    "Native import staging must preserve source content and the current document")
        store.completeTreeCreation(title: "Импортированная семья")
        try require(store.project.id != source.id && store.project.people == source.people && store.project.attachments == source.attachments && store.project.rootPersonID == source.rootPersonID,
                    "Import should create an independent project while preserving all people, attachments and default centre")
        try require(store.fileURL != sourceURL && store.savedTrees.count == 3 && (try Data(contentsOf: sourceURL)) == sourceBytes,
                    "Import should add a managed copy without touching or registering the source as another tree")

        guard let importedURL = store.fileURL,
              let importedEntry = store.savedTrees.first(where: { $0.url == importedURL.standardizedFileURL.resolvingSymlinksInPath() }) else {
            throw AppError.message("Expected imported library entry")
        }
        store.openLibraryTree(firstEntry)
        try require(store.project.id == firstID && store.project.rootPersonID == person.id && store.project.attachments.isEmpty,
                    "Switching away from an imported tree must restore the first tree without leaking attachments")
        store.openLibraryTree(importedEntry)
        try require(store.project.id != firstID && store.project.rootPersonID == source.rootPersonID && store.project.attachments == source.attachments,
                    "Switching back must restore the imported tree's own attachments and saved root")

        let gedcomURL = directory.appendingPathComponent("famytale_999_2026-11-25T05_16_43.ged")
        let gedcom = Data("0 HEAD\n1 SOUR FAMYTALE\n0 @I1@ INDI\n1 NAME Анна /Примерова/\n0 TRLR\n".utf8)
        try gedcom.write(to: gedcomURL)
        let previous = store.project
        try require(store.prepareTreeImport(at: gedcomURL), "GEDCOM import staging should succeed")
        try require(store.treeCreation?.project.title == "Моя семья" && store.treeCreation?.project.people.count == 1 && store.project == previous,
                    "GEDCOM import should suggest a human tree title without deriving it from its filename")
        store.completeTreeCreation(title: "Семья из GEDCOM")
        try require(store.project.title == "Семья из GEDCOM" && store.savedTrees.count == 4 && (try Data(contentsOf: gedcomURL)) == gedcom,
                    "Completing GEDCOM import must create a named managed tree and preserve the source")
        let validImportProject = store.project
        let invalidURL = directory.appendingPathComponent("invalid.ged")
        try Data("not GEDCOM".utf8).write(to: invalidURL)
        try require(!store.prepareTreeImport(at: invalidURL) && store.treeCreation == nil && store.project == validImportProject,
                    "Failed import must leave the active document and creation state unchanged")
        store.errorMessage = nil

        // Opening an existing external tree connects it in place; import makes a copy instead.
        store.openProject(at: sourceURL)
        try require(store.project.id == source.id && store.fileURL == sourceURL && store.savedTrees.count == 5,
                    "Opening an external tree must register it without moving or copying it")
        store.openProject(at: sourceURL.deletingLastPathComponent().appendingPathComponent(".").appendingPathComponent(sourceURL.lastPathComponent))
        store.showLibrary()
        try require(store.savedTrees.count == 5 && (try Data(contentsOf: sourceURL)) == sourceBytes,
                    "Opening the same external file through an equivalent path must not duplicate or change it")
        let externalEntry = TreeLibraryEntry(url: sourceURL, title: source.title, peopleCount: 1, modifiedAt: source.modifiedAt)
        let movedURL = directory.appendingPathComponent("source-temporarily-moved.familytree")
        try FileManager.default.moveItem(at: sourceURL, to: movedURL)
        store.showLibrary()
        try require(store.savedTrees.first(where: { $0.id == externalEntry.id })?.issue != nil,
                    "The library should retain unavailable external trees with an issue")
        let beforeFailedOpen = store.project
        store.openLibraryTree(externalEntry)
        try require(store.project == beforeFailedOpen && store.showingTreeLibrary && store.errorMessage != nil,
                    "A failed library switch must preserve the previous project and library view")
        try FileManager.default.moveItem(at: movedURL, to: sourceURL)

        // Preview confirmation refuses to discard unsaved changes and never opens system dialogs.
        let unsaved = FamilyStore(preview: true, libraryDirectoryURL: libraryURL)
        unsaved.mutate { $0.title = "Несохранённый пример" }
        let unsavedProject = unsaved.project
        unsaved.newProject()
        unsaved.completeTreeCreation(title: "Не должно создаться")
        try require(unsaved.project == unsavedProject && unsaved.treeCreation != nil && unsaved.hasUnsavedChanges,
                    "Cancelling leave confirmation must preserve an edited unsaved tree and the creation request")
        unsaved.openLibraryTree(firstEntry)
        try require(unsaved.project == unsavedProject && unsaved.fileURL == nil,
                    "A cancelled switch must not discard an edited unsaved tree")
        let blockedDirectory = directory.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blockedDirectory)
        let blocked = FamilyStore(preview: true, libraryDirectoryURL: blockedDirectory)
        let blockedPrevious = blocked.project
        blocked.newProject()
        blocked.completeTreeCreation(title: "Неудачное создание")
        try require(blocked.project == blockedPrevious && blocked.treeCreation != nil && blocked.fileURL == nil && blocked.errorMessage != nil,
                    "A failed library save must retain the previous project and staged creation")
        let reopened = FamilyStore(preview: true, libraryDirectoryURL: libraryURL)
        try require(reopened.savedTrees.count == 4 && reopened.showingTreeLibrary,
                    "A fresh isolated library should discover managed trees without reading real user preferences")
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !condition() { throw AppError.message(message) }
    }
}
