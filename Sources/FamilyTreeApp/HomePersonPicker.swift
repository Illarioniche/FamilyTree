import SwiftUI
import FamilyTreeCore

struct HomePersonPicker: View {
    @ObservedObject var store: FamilyStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedID: UUID?
    @FocusState private var searchFocused: Bool

    init(store: FamilyStore) {
        self.store = store
        _selectedID = State(initialValue: store.project.rootPersonID)
    }

    private var matches: [Person] {
        PeopleSearch.filter(store.project.people, query: query)
            .sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Кто вы в этом дереве?")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Выберите свою карточку. При открытии этого файла дерево будет начинаться с неё. Другие ветви по-прежнему можно открывать от любого человека.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Имя, фамилия или девичья фамилия", text: $query)
                        .textFieldStyle(.plain).focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Очистить поиск")
                    }
                }.font(.system(size: 12)).padding(11)
                    .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            }.padding(24)
            Divider()
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(matches) { person in
                        Button { selectedID = person.id } label: {
                            HStack(spacing: 12) {
                                PersonAvatar(person: person, project: store.project, size: 38)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(person.fullName).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    Text(person.lifespan).font(.system(size: 11)).foregroundStyle(.secondary)
                                    if person.id == store.project.rootPersonID {
                                        Text("Сейчас — центр по умолчанию")
                                            .font(.system(size: 10)).foregroundStyle(Palette.accent)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: selectedID == person.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedID == person.id ? Palette.accent : .secondary)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedID == person.id ? Palette.accent.opacity(0.08) : Palette.surface,
                                            in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(selectedID == person.id ? .isSelected : [])
                    }
                    if matches.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 28)).foregroundStyle(.tertiary)
                            Text(store.project.people.isEmpty ? "Сначала добавьте людей в дерево" : "Никого не нашли")
                                .font(.system(size: 13, weight: .medium))
                            if !store.project.people.isEmpty {
                                Text("Попробуйте другую часть имени или фамилии.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 45)
                    }
                }.padding(16)
            }
            Divider()
            HStack(spacing: 12) {
                Text("Выбор сохранится в этом дереве.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Это я") {
                    if let selectedID { store.setRoot(selectedID) }
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(selectedID == nil || store.project.person(selectedID) == nil)
            }.padding(20)
        }.frame(width: 560, height: 600).background(Palette.canvas).tint(Palette.accent)
            .onAppear { searchFocused = true }
            .onChange(of: matches.map(\.id)) { _, ids in
                if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
            }
    }
}
