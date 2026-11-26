import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FamilyTreeCore

struct PersonEditor: View {
    @ObservedObject var store: FamilyStore
    let request: PersonEditRequest
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RelativePersonDraft
    @State private var photo: Attachment?
    @State private var photoError: String?
    @State private var saveError: String?

    init(store: FamilyStore, request: PersonEditRequest) {
        self.store = store; self.request = request
        _draft = State(initialValue: RelativePersonDraft(person: request.person, isNew: request.isNew,
            relativeID: request.relativeID, role: request.creationRole, in: store.project))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Group {
                    if let photo, let image = NSImage(data: photo.data) {
                        Image(nsImage: image).resizable().scaledToFill().frame(width: 56, height: 56).clipShape(Circle())
                    } else { PersonAvatar(person: draft.person, project: store.project, size: 56) }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(editorTitle).font(.system(size: 20, weight: .semibold, design: .rounded))
                    Button("Выбрать фотографию…", action: choosePhoto).buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(Palette.accent)
                }
                Spacer()
            }.padding(24)
            Divider()
            Form {
                if request.isNew, let relative = store.project.person(request.relativeID) {
                    Section("Родство · \(relative.fullName)") {
                        Picker("Кем приходится", selection: Binding(get: { draft.role }, set: {
                            draft.setRole($0, in: store.project); saveError = nil
                        })) {
                            ForEach(RelativeCreationRole.allCases) { Text($0.title).tag($0) }
                        }
                        .accessibilityIdentifier("relativeRole")

                        if draft.hasParentChoice {
                            Picker(draft.role == .adoptedChild ? "Второй приёмный родитель" : "Второй родитель",
                                   selection: Binding(get: { draft.secondParentID }, set: {
                                draft.setSecondParent($0, in: store.project); saveError = nil
                            })) {
                                Text("Не указывать").tag(nil as UUID?)
                                ForEach(secondParentCandidates) { Text($0.fullName).tag(Optional($0.id)) }
                            }
                            .accessibilityIdentifier("secondParent")
                            Text(Set(store.project.partners(of: relative.id).map(\.id)).count > 1
                                 ? "В дереве несколько партнёров. Выберите второго родителя этого ребёнка или оставьте одного."
                                 : "Проверьте второго родителя: можно выбрать другого человека или оставить только одного.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if draft.role == .sibling {
                            if availableParents.isEmpty {
                                Text("Сначала добавьте хотя бы одного родителя в карточку этого человека — через него можно связать брата или сестру.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                ForEach(availableParents) { parent in
                                    Toggle(isOn: Binding(get: { draft.sharedParentIDs.contains(parent.id) }, set: {
                                        draft.setSharedParent(parent.id, selected: $0, in: store.project); saveError = nil
                                    })) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(parent.fullName)
                                            Text(parentDescription(parent.id)).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Text("Отметьте общих родителей. Можно оставить одного — для брата или сестры по маме либо папе.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if draft.role == .parent || draft.role == .adoptiveParent, !availableParents.isEmpty {
                            Text("Уже указаны родители: " + availableParents.map(\.fullName).joined(separator: ", ") + ". Новая карточка добавит ещё одного родителя.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if draft.role != .child && draft.role != .sibling {
                            Text(relationshipHint).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Имя") {
                    Picker("Пол", selection: Binding(get: { draft.person.gender }, set: {
                        draft.setGender($0, in: store.project); saveError = nil
                    })) {
                        ForEach(Gender.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("personGender")
                    TextField("Основная фамилия", text: nameBinding(.familyName))
                        .help("Эта фамилия отображается на дереве и в списке людей.")
                    TextField("Имя", text: nameBinding(.givenName))
                    TextField("Отчество", text: nameBinding(.patronymic))
                    if draft.showsMaidenName {
                        TextField("Девичья фамилия", text: $draft.person.maidenName)
                            .help("Показывается в подробной карточке. По ней тоже можно найти человека.")
                    }
                    if request.isNew, request.relativeID != nil {
                        Text(nameHint).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let plan = draft.creationPlan {
                    Section("Семейные связи") {
                        if let error = connectionError {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(connectionRows) { row in
                                let link = row.link
                                let otherID = link.fromID == draft.person.id ? link.toID : link.fromID
                                if let person = store.project.person(otherID) {
                                    LabeledContent(linkTitle(link, person: person)) {
                                        Text(person.fullName).multilineTextAlignment(.trailing)
                                    }
                                }
                            }
                            if plan.role == .child || plan.role == .adoptedChild || plan.role == .sibling {
                                Text("Родство с бабушками, дедушками и остальной семьёй определится через выбранных родителей.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Жизнь") {
                    TextField("Дата рождения", text: $draft.person.birthDate, prompt: Text("14.06.1988 или около 1900"))
                    TextField("Место рождения", text: $draft.person.birthPlace)
                    TextField("Профессия", text: $draft.person.occupation)
                    Toggle("Человека уже нет в живых", isOn: $draft.person.isDeceased)
                    if draft.person.isDeceased {
                        TextField("Дата ухода из жизни", text: $draft.person.deathDate, prompt: Text("Можно указать только год"))
                    }
                }
                Section("Биография и воспоминания") {
                    TextEditor(text: $draft.person.biography).font(.system(size: 13)).frame(minHeight: 80)
                    Text("Можно записать воспоминания, источник сведений или то, что ещё предстоит узнать.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if let photoError { Text(photoError).font(.caption).foregroundStyle(.red) }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden)
            Divider()
            HStack {
                Text(saveError ?? "Подсказки можно изменить. Неизвестные сведения оставьте пустыми.")
                    .font(.system(size: 10)).foregroundStyle(saveError == nil ? Color.secondary : .red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.isNew ? "Добавить" : "Сохранить", action: save)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }.padding(20)
        }
        .frame(width: 640, height: 740).background(Palette.canvas).tint(Palette.accent)
        .onChange(of: store.project) { _, _ in draft.refreshSuggestions(in: store.project) }
    }

    private var editorTitle: String {
        guard request.isNew else { return "Карточка человека" }
        guard request.relativeID != nil else { return "Новый человек в вашей истории" }
        switch draft.role {
        case .child: return "Добавить ребёнка"
        case .parent: return "Добавить родителя"
        case .sibling: return "Добавить брата или сестру"
        case .partner: return "Добавить супруга или партнёра"
        case .adoptiveParent: return "Добавить приёмного родителя"
        case .adoptedChild: return "Добавить приёмного ребёнка"
        }
    }

    private var secondParentCandidates: [Person] {
        let partners = Set(store.project.partners(of: request.relativeID ?? UUID()).map(\.id))
        return store.project.people.filter { $0.id != request.relativeID && $0.id != draft.person.id }.sorted {
            if partners.contains($0.id) != partners.contains($1.id) { return partners.contains($0.id) }
            return $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
        }
    }

    private var availableParents: [Person] {
        guard let relativeID = request.relativeID else { return [] }
        let ids = Set(RelativeCreationPlan.availableParentLinks(relativeTo: relativeID, in: store.project).map(\.fromID))
        return store.project.people.filter { ids.contains($0.id) }
            .sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
    }

    private func parentDescription(_ id: UUID) -> String {
        let links = store.project.relationships.filter { $0.fromID == id && $0.toID == request.relativeID && $0.kind.isParent }
        return Set(links.map(\.kind)) == [.adoptiveParent] ? "Общий приёмный родитель" : "Общий родитель"
    }

    private var relationshipHint: String {
        switch draft.role {
        case .child: return "Ребёнок будет связан с указанными родителями."
        case .parent: return "Родитель также появится в истории детей и внуков этого человека."
        case .sibling: return "Родство братьев и сестёр определяется через общих родителей."
        case .partner: return "Создастся связь супругов / партнёров. Родительство для уже имеющихся детей задаётся отдельно."
        case .adoptiveParent, .adoptedChild: return "Будет сохранена приёмная связь; биологические родители останутся на своих местах."
        }
    }

    private var nameHint: String {
        if draft.role == .child || draft.role == .sibling {
            if let father = draft.suggestedFather(in: store.project) {
                let givenName = RelativeNameSuggestions.splitGivenNames(father.givenName)?.givenName ?? father.givenName
                if draft.person.gender == .unspecified { return "Укажите пол, чтобы предложить отчество от имени «\(givenName)»." }
                if let suggestion = RelativeNameSuggestions.patronymic(fatherGivenName: father.givenName, childGender: draft.person.gender) {
                    return "От имени «\(givenName)» — \(suggestion). Проверьте фамилию и отчество."
                }
            }
            return "Если отец неизвестен или имя не распознано, отчество можно вписать вручную."
        }
        if draft.role == .parent { return "Фамилия и имя отца могут быть предложены по карточке ребёнка. Проверьте их перед сохранением." }
        return "Фамилию и отчество укажите по сведениям о самом человеке."
    }

    private func nameBinding(_ field: RelativePersonDraft.NameField) -> Binding<String> {
        Binding(get: {
            switch field {
            case .familyName: return draft.person.familyName
            case .givenName: return draft.person.givenName
            case .patronymic: return draft.person.patronymic
            }
        }, set: { draft.setName($0, field: field); saveError = nil })
    }

    private func plannedRelationships() throws -> [Relationship] {
        guard let plan = draft.creationPlan else { return [] }
        var staged = store.project
        if staged.person(draft.person.id) == nil { staged.people.append(draft.person) }
        return try plan.plannedRelationships(for: draft.person.id, in: staged)
    }
    private struct ConnectionRow: Identifiable {
        let link: Relationship
        var id: String { "\(link.kind.rawValue):\(link.fromID):\(link.toID)" }
    }
    private var connectionRows: [ConnectionRow] { ((try? plannedRelationships()) ?? []).map { ConnectionRow(link: $0) } }
    private var connectionError: String? {
        do { _ = try plannedRelationships(); return nil }
        catch { return error.localizedDescription }
    }
    private var canSave: Bool {
        !(draft.person.givenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && draft.person.familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && connectionError == nil
    }

    private func linkTitle(_ link: Relationship, person: Person) -> String {
        if link.kind == .partner { return "Супруг / партнёр" }
        if link.fromID == draft.person.id { return "Ребёнок" }
        if link.kind == .adoptiveParent { return "Приёмный родитель" }
        return person.gender == .male ? "Папа" : person.gender == .female ? "Мама" : "Родитель"
    }

    private func save() {
        var person = draft.personForSaving
        person.givenName = person.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        person.familyName = person.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        person.patronymic = person.patronymic.trimmingCharacters(in: .whitespacesAndNewlines)
        person.maidenName = person.maidenName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !person.isDeceased { person.deathDate = "" }
        if store.savePerson(person, creationPlan: draft.creationPlan, photo: photo) { dismiss() }
        else { saveError = store.errorMessage; store.errorMessage = nil }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 15 * 1024 * 1024 else { throw AppError.message("Фотография больше 15 МБ. Выберите изображение меньшего размера.") }
            let data = try Data(contentsOf: url)
            guard NSImage(data: data) != nil else { throw AppError.message("Не удалось прочитать изображение.") }
            photo = Attachment(personID: draft.person.id, filename: url.lastPathComponent,
                               mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/jpeg", data: data)
            photoError = nil
        } catch { photoError = error.localizedDescription }
    }
}

struct EventEditor: View {
    @ObservedObject var store: FamilyStore
    let request: EventEditRequest
    @Environment(\.dismiss) private var dismiss
    @State private var event: FamilyEvent

    init(store: FamilyStore, request: EventEditRequest) {
        self.store = store; self.request = request
        _event = State(initialValue: request.event)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Событие в истории семьи").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(store.project.person(event.personID)?.fullName ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(25)
            Form {
                Picker("Человек", selection: $event.personID) {
                    ForEach(store.project.people) { Text($0.fullName).tag($0.id) }
                }
                Picker("Событие", selection: $event.kind) { ForEach(EventKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                TextField("Название", text: $event.title, prompt: Text(event.kind.title))
                TextField("Дата", text: $event.date, prompt: Text("Дата, год или приблизительный период"))
                TextField("Место", text: $event.place)
                Section("История и источники") { TextEditor(text: $event.notes).frame(height: 85) }
            }.formStyle(.grouped)
            Divider()
            HStack {
                if store.project.events.contains(where: { $0.id == event.id }) {
                    Button("Удалить событие", role: .destructive) {
                        store.deleteEvent(event); dismiss()
                    }
                }
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") {
                    if event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { event.title = event.kind.title }
                    store.saveEvent(event); dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 530, height: 560).background(Palette.canvas).tint(Palette.accent)
    }
}

struct RelationshipEditor: View {
    @ObservedObject var store: FamilyStore
    @Environment(\.dismiss) private var dismiss
    @State private var relativeID: UUID?
    @State private var role: RelativeRole = .parent
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Соединить семейные истории").font(.system(size: 22, weight: .semibold, design: .rounded))
            if let person = store.selectedPerson {
                Text("Добавить связь для \(person.fullName)").foregroundStyle(.secondary)
                Picker("Человек", selection: $relativeID) {
                    Text("Выберите человека").tag(nil as UUID?)
                    ForEach(store.project.people.filter { $0.id != person.id }) { Text($0.fullName).tag(Optional($0.id)) }
                }
                Picker("Кем приходится", selection: $role) {
                    ForEach(RelativeRole.allCases) { Text($0.title).tag($0) }
                }
                Text("Выбранный человек будет указан как «\(role.title.lowercased())» для \(person.shortName).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
                HStack {
                    Spacer()
                    Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Добавить связь") {
                        guard let relativeID else { return }
                        let relationship = role.relationship(newPersonID: relativeID, relativeID: person.id)
                        do {
                            try ProjectValidation.validateRelationship(relationship, in: store.project)
                            store.mutate { $0.relationships.append(relationship) }
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).disabled(relativeID == nil).keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Сначала выберите человека на дереве.")
                Button("Закрыть") { dismiss() }
            }
        }.padding(28).frame(width: 510).tint(Palette.accent)
    }
}

struct ProjectNameEditor: View {
    @ObservedObject var store: FamilyStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Название вашей истории").font(.system(size: 22, weight: .semibold, design: .rounded))
            TextField("Например, Семья Волковых", text: $title).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { store.mutate { $0.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }; dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 430).onAppear { title = TreeLibrary.displayTitle(store.project.title) }.tint(Palette.accent)
    }
}
