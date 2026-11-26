import SwiftUI
import AppKit
import FamilyTreeCore

@main
enum EntryPoint {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            PreviewRenderer.render(to: CommandLine.arguments[index + 1])
            return
        }
        if CommandLine.arguments.contains("--check-store") {
            StoreChecks.run()
            return
        }
        RodnyeApplication.main()
    }
}

struct RodnyeApplication: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var appDelegate
    @StateObject private var store = FamilyStore()

    var body: some Scene {
        Window("FamilyTree", id: "main") {
            ContentView(store: store)
                .background(WindowLifecycle(store: store, appDelegate: appDelegate))
                .onAppear { appDelegate.store = store }
        }
        .defaultSize(width: 1400, height: 880)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Мои деревья", action: store.showLibrary).keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                Button("Новое дерево…", action: store.newProject).keyboardShortcut("n")
                Button("Открыть дерево…", action: store.openProject).keyboardShortcut("o")
                Divider()
                Button("Сохранить", action: { _ = store.save() }).keyboardShortcut("s").disabled(store.showingTreeLibrary)
                Button("Сохранить как…", action: { _ = store.saveAs() }).keyboardShortcut("s", modifiers: [.command, .shift]).disabled(store.showingTreeLibrary)
                Divider()
                Button("Импортировать дерево…", action: store.importTree)
                Button("Экспортировать GEDCOM…", action: store.exportGEDCOM).disabled(store.project.people.isEmpty || store.showingTreeLibrary)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Отменить изменение", action: store.undo).keyboardShortcut("z").disabled(store.undoStack.isEmpty || store.showingTreeLibrary)
                Button("Повторить изменение", action: store.redo).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(store.redoStack.isEmpty || store.showingTreeLibrary)
            }
            CommandGroup(after: .textEditing) {
                Button("Найти человека", action: store.focusPeopleSearch).keyboardShortcut("f")
                    .disabled(store.showingTreeLibrary)
            }
            CommandMenu("Семья") {
                Button("Кто я в этом дереве…") { store.showingHomePersonPicker = true }
                    .disabled(store.project.people.isEmpty || store.showingTreeLibrary)
                Button("К началу дерева", action: store.goToHomePerson)
                    .disabled(store.project.person(store.project.rootPersonID) == nil || store.showingTreeLibrary)
                Divider()
                Button("Добавить человека…") { store.addPerson() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(store.showingTreeLibrary)
                Button("Добавить родственника…") { if let id = store.selection { store.addPerson(relativeTo: id) } }.disabled(store.selection == nil || store.showingTreeLibrary)
                Button("Добавить связь…") { store.showingRelationshipEditor = true }.disabled(store.project.people.count < 2 || store.showingTreeLibrary)
                Button("Добавить событие…") { if let id = store.selection { store.eventEditor = .init(event: FamilyEvent(personID: id)) } }.disabled(store.selection == nil || store.showingTreeLibrary)
                Divider()
                Button("Разделить фамилии после импорта…") { store.showingSurnameReview = true }
                    .disabled(store.surnameRepairSuggestions.isEmpty || store.showingTreeLibrary)
                Button("Переименовать дерево…") { store.showingProjectName = true }.disabled(store.showingTreeLibrary)
                Button("Показать файл в Finder", action: store.revealFile).disabled(store.fileURL == nil || store.showingTreeLibrary)
            }
            CommandGroup(replacing: .help) {
                Button("Открыть пример дерева", action: store.showExample)
                Button("О локальном хранении") {
                    store.infoMessage = "Дерево хранится в выбранном вами файле .familytree вместе с фотографиями и документами. После каждого изменения файл сохраняется автоматически. Предыдущая версия находится рядом с расширением .backup.\n\nДля переноса полной истории скопируйте .familytree. Для обмена с другими программами используйте GEDCOM: вложения в него не входят.\n\nПриложение не использует аккаунт, сервер или интернет. Если вы сами выбрали синхронизируемую папку, её копированием управляет ваша облачная программа."
                }
            }
        }
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var store: FamilyStore? {
        didSet {
            if let store, let pendingOpen {
                self.pendingOpen = nil
                DispatchQueue.main.async { store.openProject(at: pendingOpen) }
            }
        }
    }
    var alreadyConfirmedClose = false
    private var pendingOpen: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let store, let pendingOpen { self.pendingOpen = nil; store.openProject(at: pendingOpen) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        alreadyConfirmedClose || (store?.confirmLeaving() ?? true) ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let store { store.openProject(at: url) } else { pendingOpen = url }
    }
}

private struct WindowLifecycle: NSViewRepresentable {
    let store: FamilyStore
    let appDelegate: ApplicationDelegate
    func makeCoordinator() -> Coordinator { Coordinator(store: store, appDelegate: appDelegate) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.original = window.delegate
                window.delegate = context.coordinator
                configure(window)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { configure(window) }
        }
    }
    private func configure(_ window: NSWindow) {
        window.minSize = NSSize(width: 1050, height: 700)
        window.title = "FamilyTree"
        // Keep the app name in window metadata without displaying a toolbar title.
        window.titleVisibility = .hidden
    }
    final class Coordinator: NSObject, NSWindowDelegate {
        let store: FamilyStore
        let appDelegate: ApplicationDelegate
        weak var original: NSWindowDelegate?
        init(store: FamilyStore, appDelegate: ApplicationDelegate) { self.store = store; self.appDelegate = appDelegate }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            let shouldClose = store.confirmLeaving()
            if shouldClose { appDelegate.alreadyConfirmedClose = true }
            return shouldClose
        }
        override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || (original?.responds(to: selector) ?? false) }
        override func forwardingTarget(for selector: Selector!) -> Any? { original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector) }
    }
}

@MainActor
enum PreviewRenderer {
    static func render(to path: String) {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let previewLibraryURL = FileManager.default.temporaryDirectory.appendingPathComponent("familytree-preview-" + UUID().uuidString, isDirectory: true)
        let store = FamilyStore(preview: true, libraryDirectoryURL: previewLibraryURL)
        defer { try? FileManager.default.removeItem(at: previewLibraryURL) }
        store.showingTreeLibrary = false
        // This diagnostic path reads a supplied file in memory only. It never
        // stores private fixtures in the repository or changes the recent project.
        if let index = CommandLine.arguments.firstIndex(of: "--gedcom"), CommandLine.arguments.count > index + 1 {
            do {
                let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                let imported = try GEDCOM.importData(Data(contentsOf: url), title: "Семейная история")
                store.replaceProject(imported.project, url: nil)
            } catch { fputs("GEDCOM preview failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        let surnameReview = CommandLine.arguments.contains("--surname-review")
        if (surnameReview || CommandLine.arguments.contains("--legacy-surnames")),
           !CommandLine.arguments.contains("--gedcom") {
            // Reconstruct three old-style records from fictional demo data only.
            var legacy = FamilyProject.demo
            for index in [1, 3, 5] {
                let mainSurname = legacy.people[index].familyName
                legacy.people[index].familyName = legacy.people[index].maidenName
                legacy.people[index].maidenName = ""
                legacy.people[index].biography += "\n\nДругое имя из GEDCOM: " + mainSurname
            }
            store.replaceProject(legacy, url: nil)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--focus-index"),
           CommandLine.arguments.count > index + 1,
           let personIndex = Int(CommandLine.arguments[index + 1]),
           store.project.people.indices.contains(personIndex) {
            store.selection = store.project.people[personIndex].id
        }
        if let index = CommandLine.arguments.firstIndex(of: "--home-index"),
           CommandLine.arguments.count > index + 1,
           let personIndex = Int(CommandLine.arguments[index + 1]),
           store.project.people.indices.contains(personIndex) {
            store.setRoot(store.project.people[personIndex].id)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--preview-title"), CommandLine.arguments.count > index + 1 {
            store.mutate { $0.title = CommandLine.arguments[index + 1] }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--query"), CommandLine.arguments.count > index + 1 {
            store.query = CommandLine.arguments[index + 1]
            store.section = .people
        }
        var requestedMode: TreeScopeMode?
        if let index = CommandLine.arguments.firstIndex(of: "--scope"), CommandLine.arguments.count > index + 1 {
            requestedMode = TreeScopeMode(rawValue: CommandLine.arguments[index + 1])
        }
        if CommandLine.arguments.contains("--people") { store.section = .people }
        if CommandLine.arguments.contains("--timeline") { store.section = .timeline }
        if CommandLine.arguments.contains("--archive") { store.section = .archive }
        if CommandLine.arguments.contains("--library-demo") {
            for title in ["Семья Волковых", "Мамина ветвь", "Новая история"] {
                store.newProject()
                if title != "Новая история" {
                    var draft = FamilyProject.demo
                    draft.title = title
                    store.treeCreation = TreeCreationRequest(project: draft, warnings: [], isImport: true)
                }
                store.completeTreeCreation(title: title)
            }
            store.showLibrary()
        }
        if CommandLine.arguments.contains("--library-empty") { store.showLibrary() }
        let creationPreview = CommandLine.arguments.contains("--tree-creation")
        if creationPreview { store.newProject() }
        var relativeRole: RelativeCreationRole?
        if let index = CommandLine.arguments.firstIndex(of: "--relative-editor"), CommandLine.arguments.count > index + 1 {
            relativeRole = RelativeCreationRole(rawValue: CommandLine.arguments[index + 1])
        }
        let editor = CommandLine.arguments.contains("--person-editor") || relativeRole != nil
        let empty = CommandLine.arguments.contains("--empty")
        if empty { store.replaceProject(FamilyProject(), url: nil) }
        let homePicker = CommandLine.arguments.contains("--home-picker")
        let size = creationPreview ? NSSize(width: 540, height: 340)
            : surnameReview ? NSSize(width: 680, height: 600)
            : homePicker ? NSSize(width: 560, height: 600)
            : editor ? NSSize(width: 640, height: 740)
            : NSSize(width: CommandLine.arguments.contains("--narrow") ? 1050 : 1440, height: 900)
        let view: AnyView
        if creationPreview, let request = store.treeCreation {
            view = AnyView(TreeCreationView(store: store, request: request))
        } else if surnameReview {
            view = AnyView(SurnameReviewView(store: store))
        } else if homePicker {
            view = AnyView(HomePersonPicker(store: store))
        } else if let relativeRole {
            var person = Person()
            if let index = CommandLine.arguments.firstIndex(of: "--editor-gender"), CommandLine.arguments.count > index + 1 {
                person.gender = Gender(rawValue: CommandLine.arguments[index + 1]) ?? .unspecified
            }
            view = AnyView(PersonEditor(store: store, request: PersonEditRequest(person: person, isNew: true,
                relativeID: store.selection, creationRole: relativeRole)))
        } else if editor {
            view = AnyView(PersonEditor(store: store, request: PersonEditRequest(person: store.selectedPerson ?? Person(), isNew: false)))
        } else {
            view = AnyView(ContentView(store: store, initialTreeMode: requestedMode,
                                       initiallyShowSidebar: !CommandLine.arguments.contains("--hide-left-sidebar"),
                                       initiallyShowInspector: !CommandLine.arguments.contains("--hide-right-sidebar")))
        }
        let content = view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, CommandLine.arguments.contains("--dark") ? .dark : .light)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fputs("Cannot render preview\n", stderr); exit(1) }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            print("Preview: \(path)")
        } catch { fputs("\(error)\n", stderr); exit(1) }
    }
}
