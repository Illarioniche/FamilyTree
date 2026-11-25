import SwiftUI
import FamilyTreeCore

struct PersonInspector: View {
    @ObservedObject var store: FamilyStore

    var body: some View {
        if let person = store.selectedPerson {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heading(person)
                    facts(person)
                    if !person.biography.isEmpty {
                        VStack(alignment: .leading, spacing: 11) {
                            SectionCaption(title: "История человека")
                            Text(person.biography).font(.system(size: 12)).lineSpacing(5)
                                .foregroundStyle(.primary.opacity(0.8)).textSelection(.enabled)
                        }
                    }
                    family(person)
                    events(person)
                    attachments(person)
                }
                .padding(.horizontal, 23).padding(.top, 25).padding(.bottom, 30)
            }
            .background(Palette.surface)
        } else {
            EmptyCollectionView(symbol: "person.text.rectangle", title: "Каждая жизнь — история",
                                subtitle: "Выберите человека на дереве, чтобы увидеть его близких и события.")
                .background(Palette.surface)
        }
    }

    private func heading(_ person: Person) -> some View {
        VStack(spacing: 13) {
            HStack {
                SectionCaption(title: "Карточка человека")
                Spacer()
                SmallIconButton(symbol: person.isFavorite ? "star.fill" : "star", help: "Избранное") { store.toggleFavorite(person) }
                    .foregroundStyle(person.isFavorite ? .orange : .secondary)
                Menu {
                    Button("Это я — начинать дерево отсюда") { store.setRoot(person.id) }
                        .disabled(person.id == store.project.rootPersonID)
                    Button("Добавить связь с человеком") { store.showingRelationshipEditor = true }
                    Divider()
                    Button("Удалить человека…", role: .destructive) { store.deletePerson(person) }
                } label: { Image(systemName: "ellipsis").frame(width: 20) }
                    .menuStyle(.borderlessButton).fixedSize().help("Действия с человеком")
            }.padding(.bottom, 7)
            PersonAvatar(person: person, project: store.project, size: 80)
            VStack(spacing: 5) {
                Text(person.fullName)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                if !person.maidenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Девичья фамилия: \(person.maidenName)")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                Text(person.lifespan).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 2)
            }.multilineTextAlignment(.center)
            if person.id == store.project.rootPersonID {
                Label("Центр по умолчанию", systemImage: "house.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.accent).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Palette.accent.opacity(0.08), in: Capsule())
                    .help("При открытии этого файла дерево начинается с этой карточки.")
            } else {
                Button { store.setRoot(person.id) } label: {
                    Label("Это я", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 11, weight: .medium))
                }.buttonStyle(.bordered).controlSize(.small)
                    .help("Начинать дерево с этого человека. Выбор сохранится в файле дерева.")
            }
            HStack(spacing: 8) {
                Button { store.edit(person) } label: { Label("Изменить", systemImage: "pencil").frame(maxWidth: .infinity) }
                Button { store.addPerson(relativeTo: person.id) } label: { Image(systemName: "person.badge.plus") }
                    .help("Добавить родственника")
            }
            .buttonStyle(.bordered).controlSize(.regular).padding(.top, 4)
        }.frame(maxWidth: .infinity)
    }

    private func facts(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCaption(title: "О человеке")
            if !person.birthDate.isEmpty { fact("Рождение", value: GenealogyDate.display(person.birthDate), icon: "sun.max") }
            if person.isDeceased { fact("Уход из жизни", value: person.deathDate.isEmpty ? "Дата неизвестна" : GenealogyDate.display(person.deathDate), icon: "leaf") }
            if !person.birthPlace.isEmpty { fact("Место рождения", value: person.birthPlace, icon: "mappin.and.ellipse") }
            if !person.occupation.isEmpty { fact("Дело жизни", value: person.occupation, icon: "briefcase") }
            if person.birthDate.isEmpty && person.birthPlace.isEmpty && person.occupation.isEmpty && !person.isDeceased {
                Text("Добавьте даты, места и несколько слов о близком человеке.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 13))
    }

    private func fact(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Palette.accent).frame(width: 15).padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 11)).textSelection(.enabled)
            }
        }
    }

    private func family(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionCaption(title: "Близкие")
                Spacer()
                SmallIconButton(symbol: "link.badge.plus", help: "Связать с человеком из дерева") { store.showingRelationshipEditor = true }
            }
            let relatives = closeRelatives(of: person)
            if relatives.isEmpty {
                Text("Семейные связи пока не добавлены.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(relatives) { entry in
                Button { store.selection = entry.person.id } label: {
                    HStack(spacing: 10) {
                        PersonAvatar(person: entry.person, project: store.project, size: 33)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.person.shortName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Text(entry.titles.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    // Inferred siblings/grandparents have no direct edge to remove.
                    ForEach(entry.directRelationships) { relation in
                        Button(entry.directRelationships.count == 1 ? "Убрать связь" : "Убрать связь: \(relationTitle(relation, person: person, relative: entry.person))", role: .destructive) {
                            store.mutate { $0.relationships.removeAll { $0.id == relation.id } }
                        }
                    }
                }
            }
            Button { store.addPerson(relativeTo: person.id) } label: { Label("Добавить родственника", systemImage: "plus") }
                .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.accent).padding(.top, 4)
        }
    }

    private struct CloseRelative: Identifiable {
        var person: Person
        var titles: [String]
        var order: Int
        var directRelationships: [Relationship]
        var id: UUID { person.id }
    }

    private func closeRelatives(of person: Person) -> [CloseRelative] {
        var entries: [UUID: CloseRelative] = [:]
        func add(_ relative: Person, title: String, order: Int, relationship: Relationship? = nil) {
            guard relative.id != person.id else { return }
            var entry = entries[relative.id] ?? CloseRelative(person: relative, titles: [], order: order, directRelationships: [])
            if !entry.titles.contains(title) { entry.titles.append(title) }
            entry.order = min(entry.order, order)
            if let relationship, !entry.directRelationships.contains(where: { $0.id == relationship.id }) {
                entry.directRelationships.append(relationship)
            }
            entries[relative.id] = entry
        }

        for relation in store.project.relationships where relation.fromID == person.id || relation.toID == person.id {
            guard let relative = store.project.person(relation.fromID == person.id ? relation.toID : relation.fromID) else { continue }
            let order = relation.kind == .partner ? 1 : (relation.toID == person.id ? 0 : 2)
            add(relative, title: relationTitle(relation, person: person, relative: relative), order: order, relationship: relation)
        }
        // Both biological and adoptive parent links count. Using the same parent
        // also includes half siblings; a person appears only once in the list.
        for parent in store.project.parents(of: person.id) {
            for sibling in store.project.children(of: parent.id) {
                let title = sibling.gender == .female ? "Сестра" : sibling.gender == .male ? "Брат" : "Брат / сестра"
                add(sibling, title: title, order: 3)
            }
            for grandparent in store.project.parents(of: parent.id) {
                let title = grandparent.gender == .female ? "Бабушка" : grandparent.gender == .male ? "Дедушка" : "Бабушка / дедушка"
                add(grandparent, title: title, order: 4)
            }
        }
        return entries.values.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            let comparison = $0.person.fullName.localizedStandardCompare($1.person.fullName)
            return comparison == .orderedSame ? $0.id.uuidString < $1.id.uuidString : comparison == .orderedAscending
        }
    }

    private func relationTitle(_ relation: Relationship, person: Person, relative: Person) -> String {
        if relation.kind == .partner { return "Партнёр" }
        if relation.fromID == person.id {
            return relation.kind == .adoptiveParent ? "Приёмный ребёнок" : (relative.gender == .female ? "Дочь" : relative.gender == .male ? "Сын" : "Ребёнок")
        }
        return relation.kind == .adoptiveParent ? "Приёмный родитель" : (relative.gender == .female ? "Мама" : relative.gender == .male ? "Папа" : "Родитель")
    }

    private func events(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionCaption(title: "События жизни")
                Spacer()
                SmallIconButton(symbol: "plus", help: "Добавить событие") { store.eventEditor = .init(event: FamilyEvent(personID: person.id)) }
            }
            let events = store.project.events.filter { $0.personID == person.id }.sorted { (GenealogyDate.year(in: $0.date) ?? 9999) < (GenealogyDate.year(in: $1.date) ?? 9999) }
            if events.isEmpty { Text("Важные моменты этой истории появятся здесь.").font(.system(size: 11)).foregroundStyle(.secondary) }
            ForEach(events) { event in
                Button { store.eventEditor = .init(event: event) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: event.kind.symbol).font(.system(size: 12)).foregroundStyle(Palette.accent).frame(width: 20).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title.isEmpty ? event.kind.title : event.title).font(.system(size: 11, weight: .medium))
                            Text([GenealogyDate.display(event.date), event.place].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private func attachments(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionCaption(title: "Фотографии и документы")
                Spacer()
                SmallIconButton(symbol: "plus", help: "Добавить вложения") { store.addAttachment(to: person.id) }
            }
            let items = store.project.attachments.filter { $0.personID == person.id }
            if items.isEmpty {
                Button { store.addAttachment(to: person.id) } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 22, weight: .light))
                        Text("Сохранить частичку истории").font(.system(size: 10))
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 22)
                        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(.plain)
            } else {
                ForEach(items.prefix(4)) { item in
                    Button { store.exportAttachment(item) } label: {
                        Label(item.filename, systemImage: item.isImage ? "photo" : "doc.text")
                            .font(.system(size: 11)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).help("Сохранить вложение в отдельный файл")
                }
                if items.count > 4 {
                    Button("Все вложения (\(items.count))") { store.section = .archive }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent)
                }
            }
        }
    }
}
