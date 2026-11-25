import SwiftUI
import FamilyTreeCore

struct PeopleView: View {
    @ObservedObject var store: FamilyStore
    @State private var favoritesOnly = false
    @FocusState private var searchFocused: Bool

    private var hasQuery: Bool { !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var people: [Person] { store.filteredPeople.filter { !favoritesOnly || $0.isFavorite } }

    var body: some View {
        VStack(spacing: 0) {
            searchTools
            if store.project.people.isEmpty {
                EmptyCollectionView(symbol: "person.2", title: "Пока никого нет",
                                    subtitle: "Добавьте первого человека, чтобы начать семейную историю.",
                                    actionTitle: "Добавить человека", action: { store.addPerson() })
            } else if people.isEmpty {
                EmptyCollectionView(symbol: "magnifyingglass", title: hasQuery ? "Никого не нашли" : "В избранном пока никого нет",
                                    subtitle: hasQuery
                                        ? "Попробуйте другую фамилию, часть имени или сбросьте фильтры."
                                        : "Отметьте человека звёздочкой в его карточке, чтобы быстро находить его здесь.",
                                    actionTitle: hasQuery ? "Сбросить поиск и фильтры" : "Показать всех",
                                    action: resetSearch)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(people) { person in
                            personCard(person)
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 28)
                }
            }
        }
        .onAppear { if store.peopleSearchRequest > 0 { searchFocused = true } }
        .onChange(of: store.peopleSearchRequest) { _, _ in searchFocused = true }
    }

    private var searchTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Имя, фамилия или девичья фамилия", text: $store.query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("Поиск людей")
                if !store.query.isEmpty {
                    Button {
                        store.query = ""; searchFocused = true
                    } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Очистить поиск").accessibilityLabel("Очистить поиск людей")
                } else if !searchFocused {
                    Text("⌘F").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 12)).padding(.horizontal, 12).frame(height: 36)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(searchFocused ? Palette.accent : Palette.divider,
                                                          lineWidth: searchFocused ? 1.5 : 1))
            Text("Также можно искать по месту рождения, году и занятию.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Text("Найдено: \(people.count) из \(store.project.people.count)")
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 4)
                Toggle("Избранные", isOn: $favoritesOnly).toggleStyle(.checkbox).font(.system(size: 11))
            }.padding(.top, 2)
        }
        .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 18)
    }

    private func resetSearch() {
        store.query = ""; favoritesOnly = false; searchFocused = true
    }

    private func personCard(_ person: Person) -> some View {
        Button { store.selection = person.id } label: {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    PersonAvatar(person: person, project: store.project, size: 47)
                    Spacer()
                    if person.isFavorite {
                        Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.orange.opacity(0.7))
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(person.fullName).font(.system(size: 14, weight: .medium)).lineLimit(2)
                    Text(person.lifespan).font(.system(size: 11)).foregroundStyle(.secondary)
                    if !person.birthPlace.isEmpty {
                        Label(person.birthPlace, systemImage: "mappin").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading).padding(19)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(store.selection == person.id ? Palette.accent : Palette.divider,
                                                             lineWidth: store.selection == person.id ? 1.5 : 1))
        }
        .buttonStyle(.plain).contextMenu {
            Button("Редактировать") { store.edit(person) }
            Button("Показать на дереве") { store.selection = person.id; store.section = .tree }
            Button("Добавить родственника") { store.addPerson(relativeTo: person.id) }
        }
    }
}
