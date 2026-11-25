import SwiftUI
import FamilyTreeCore

struct ContentView: View {
    @ObservedObject var store: FamilyStore
    var initialTreeMode: TreeScopeMode? = nil
    @State private var sidebarVisible: Bool
    @State private var inspectorVisible: Bool

    init(store: FamilyStore, initialTreeMode: TreeScopeMode? = nil,
         initiallyShowSidebar: Bool = true, initiallyShowInspector: Bool = true) {
        self.store = store
        self.initialTreeMode = initialTreeMode
        _sidebarVisible = State(initialValue: initiallyShowSidebar)
        _inspectorVisible = State(initialValue: initiallyShowInspector)
    }

    var body: some View {
        Group {
            if store.showingTreeLibrary { TreeLibraryView(store: store) }
            else { workspace }
        }
        .tint(Palette.accent)
        .frame(minWidth: inspectorVisible ? 1050 : 750, minHeight: 650)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if !store.showingTreeLibrary {
                    Button(action: store.showLibrary) { Label("Мои деревья", systemImage: "square.grid.2x2") }
                        .help("Переключиться на другое дерево")
                    Button { sidebarVisible.toggle() } label: {
                        Label(sidebarVisible ? "Скрыть левую панель" : "Показать левую панель", systemImage: "sidebar.left")
                    }
                    .help(sidebarVisible ? "Скрыть левую панель" : "Показать левую панель")
                    .accessibilityIdentifier("toggleLeftSidebar")
                }
            }
            if !store.showingTreeLibrary {
                if #available(macOS 26.0, *) {
                    // A hidden window title no longer separates navigation and actions.
                    ToolbarSpacer(.flexible, placement: .automatic)
                } else {
                    ToolbarItem(placement: .principal) { Spacer(minLength: 0) }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if !store.showingTreeLibrary {
                    Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(store.undoStack.isEmpty).help("Отменить изменение · ⌘Z")
                    Menu {
                        Button("Создать дерево…", action: store.newProject)
                        Button("Открыть дерево…", action: store.openProject)
                        Divider()
                        Button("Сохранить", action: { _ = store.save() })
                        Button("Сохранить как…", action: { _ = store.saveAs() })
                        Button("Переименовать дерево…") { store.showingProjectName = true }
                        Button("Кто я в этом дереве…") { store.showingHomePersonPicker = true }
                            .disabled(store.project.people.isEmpty)
                        Divider()
                        Button("Импортировать дерево…", action: store.importTree)
                        Button("Экспортировать GEDCOM…", action: store.exportGEDCOM)
                        Button("Разделить фамилии после импорта…") { store.showingSurnameReview = true }
                            .disabled(store.surnameRepairSuggestions.isEmpty)
                        Button("Показать файл в Finder", action: store.revealFile).disabled(store.fileURL == nil)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .help("Действия с деревом")
                    Button { inspectorVisible.toggle() } label: { Image(systemName: "sidebar.right") }
                        .help("Показать или скрыть карточку")
                    Button { store.addPerson() } label: { Label("Добавить человека", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(Palette.accent)
                }
            }
        }
        .sheet(item: $store.treeCreation) { request in TreeCreationView(store: store, request: request) }
        .sheet(item: $store.personEditor) { request in PersonEditor(store: store, request: request) }
        .sheet(item: $store.eventEditor) { request in EventEditor(store: store, request: request) }
        .sheet(isPresented: $store.showingRelationshipEditor) { RelationshipEditor(store: store) }
        .sheet(isPresented: $store.showingProjectName) { ProjectNameEditor(store: store) }
        .sheet(isPresented: $store.showingSurnameReview) { SurnameReviewView(store: store) }
        .sheet(isPresented: $store.showingHomePersonPicker) { HomePersonPicker(store: store) }
        .alert("Не удалось выполнить действие", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("Понятно") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .alert("Импорт дерева", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("Понятно") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
        .alert("FamilyTree", isPresented: Binding(get: { store.infoMessage != nil }, set: { if !$0 { store.infoMessage = nil } })) {
            Button("Понятно") { store.infoMessage = nil }
        } message: { Text(store.infoMessage ?? "") }
        .onChange(of: store.query) { _, value in if !value.isEmpty { store.section = .people } }
    }

    private var workspace: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView(store: store).frame(width: 216)
                Divider()
            }
            VStack(spacing: 0) {
                contentHeader
                Divider().opacity(0.6)
                if !store.surnameRepairSuggestions.isEmpty { surnameReviewBanner }
                sectionContent
                if store.isExample { exampleBanner }
                statusBar
            }
            .frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
            if inspectorVisible && !store.project.people.isEmpty {
                Divider()
                PersonInspector(store: store).frame(width: 304)
            }
        }
    }

    private var contentHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(TreeLibrary.displayTitle(store.project.title))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .help(TreeLibrary.displayTitle(store.project.title))
                Text(store.section.title).font(.system(size: 27, weight: .semibold, design: .rounded))
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "person.2").font(.system(size: 11))
                Text("\(store.project.people.count) человек").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary).padding(.horizontal, 11).padding(.vertical, 7)
            .background(.primary.opacity(0.04), in: Capsule())
        }
        .padding(.horizontal, 28).padding(.vertical, 25)
    }

    @ViewBuilder private var sectionContent: some View {
        switch store.section {
        case .tree:
            TreeCanvasView(project: store.project, selection: $store.selection,
                           onAddRelative: { store.addPerson(relativeTo: $0) }, initialMode: initialTreeMode,
                           onChooseHomePerson: { store.showingHomePersonPicker = true }, homeFocusRequest: store.homeFocusRequest,
                           onAddPerson: { store.addPerson() })
        case .people: PeopleView(store: store)
        case .timeline: ChronicleView(store: store)
        case .archive: ArchiveView(store: store)
        }
    }

    private var surnameReviewBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.text.rectangle").foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Основная и девичья фамилии").font(.system(size: 12, weight: .medium))
                Text("В старом импорте часть фамилий сохранилась в биографиях.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Проверить") { store.showingSurnameReview = true }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(Palette.accent.opacity(0.06))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.divider).frame(height: 1) }
    }

    private var exampleBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Знакомство с «FamilyTree»").font(.system(size: 11, weight: .semibold))
                Text("Это вымышленная семья. Здесь можно попробовать все функции.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button("Создать своё дерево", action: store.newProject)
                .font(.system(size: 11, weight: .medium)).buttonStyle(.bordered)
        }
        .padding(.horizontal, 17).padding(.vertical, 12)
        .background(Palette.accent.opacity(0.06))
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Image(systemName: store.hasUnsavedChanges ? "circle.fill" : "checkmark.shield")
                .font(.system(size: 10)).foregroundStyle(store.hasUnsavedChanges ? Color.orange : Palette.accent)
            Text(store.status).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            if store.hasUnsavedChanges {
                Button("Сохранить…") { _ = store.save() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.accent)
            } else if store.fileURL != nil {
                Button { store.revealFile() } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain).help("Показать файл дерева")
            }
        }
        .padding(.horizontal, 18).frame(height: 30)
        .background(Palette.surface.opacity(0.65))
    }
}

private struct SidebarView: View {
    @ObservedObject var store: FamilyStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "leaf.fill").font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white).frame(width: 39, height: 39)
                    .background(Palette.accent.gradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("FamilyTree").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(TreeLibrary.displayTitle(store.project.title)).font(.system(size: 9)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }.padding(.horizontal, 21).padding(.top, 25).padding(.bottom, 25)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Найти человека", text: $store.query)
                    .textFieldStyle(.plain).font(.system(size: 12))
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .padding(9).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 15).padding(.bottom, 26)

            SectionCaption(title: "В этом дереве").padding(.leading, 23).padding(.bottom, 10)
            VStack(spacing: 4) {
                ForEach(LibrarySection.allCases) { section in
                    Button { store.section = section; store.query = "" } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol).font(.system(size: 14)).frame(width: 20)
                            Text(section.title).font(.system(size: 12, weight: store.section == section ? .semibold : .regular))
                            Spacer(minLength: 0)
                            if section == .people {
                                Text("\(store.project.people.count)").font(.system(size: 10)).opacity(0.6)
                            }
                        }
                        .foregroundStyle(store.section == section ? Palette.accent : .primary.opacity(0.75))
                        .padding(.horizontal, 11).frame(height: 36)
                        .background(store.section == section ? Palette.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 12)

            if !store.project.people.filter(\.isFavorite).isEmpty {
                SectionCaption(title: "Избранные").padding(.leading, 23).padding(.top, 30).padding(.bottom, 12)
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(store.project.people.filter(\.isFavorite)) { person in
                            Button {
                                store.selection = person.id; store.section = .tree
                            } label: {
                                HStack(spacing: 9) {
                                    PersonAvatar(person: person, project: store.project, size: 25)
                                    Text(person.shortName).font(.system(size: 11)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.padding(.vertical, 5).padding(.horizontal, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 12)
                }.frame(maxHeight: 165)
            }
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 12) {
                Rectangle().fill(Palette.divider).frame(height: 1)
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "internaldrive").font(.system(size: 17, weight: .light)).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("История остаётся с вами").font(.system(size: 10, weight: .medium))
                        Text("Локально. Без аккаунта.\nДоступно без интернета.")
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                }
            }.padding(.horizontal, 20).padding(.bottom, 22)
        }
        .background(.regularMaterial)
    }
}
