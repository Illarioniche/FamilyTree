import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FamilyTreeCore

struct PersonEditor: View {
    @ObservedObject var store: FamilyStore
    let request: PersonEditRequest
    @Environment(\.dismiss) private var dismiss
    @State private var person: Person
    @State private var role: RelativeRole = .child
    @State private var photo: Attachment?
    @State private var photoError: String?

    init(store: FamilyStore, request: PersonEditRequest) {
        self.store = store; self.request = request
        _person = State(initialValue: request.person)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Group {
                    if let photo, let image = NSImage(data: photo.data) {
                        Image(nsImage: image).resizable().scaledToFill().frame(width: 56, height: 56).clipShape(Circle())
                    } else { PersonAvatar(person: person, project: store.project, size: 56) }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(request.isNew ? "Новый человек в вашей истории" : "Карточка человека")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Button("Выбрать фотографию…", action: choosePhoto).buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(Palette.accent)
                }
                Spacer()
            }.padding(25)
            Divider()
            Form {
                if let id = request.relativeID, let relative = store.project.person(id) {
                    Section("Связь с \(relative.shortName)") {
                        Picker("Кем приходится", selection: $role) {
                            ForEach(RelativeRole.allCases) { Text($0.title).tag($0) }
                        }
                    }
                }
                Section("Имя") {
                    TextField("Фамилия", text: $person.familyName)
                    TextField("Имя", text: $person.givenName)
                    TextField("Отчество", text: $person.patronymic)
                    TextField("Девичья фамилия", text: $person.maidenName)
                    Picker("Пол", selection: $person.gender) { ForEach(Gender.allCases, id: \.self) { Text($0.title).tag($0) } }
                }
                Section("Жизнь") {
                    TextField("Дата рождения", text: $person.birthDate, prompt: Text("14.06.1988 или около 1900"))
                    TextField("Место рождения", text: $person.birthPlace)
                    TextField("Профессия", text: $person.occupation)
                    Toggle("Человека уже нет в живых", isOn: $person.isDeceased)
                    if person.isDeceased { TextField("Дата ухода из жизни", text: $person.deathDate, prompt: Text("Можно указать только год")) }
                }
                Section("Биография и воспоминания") {
                    TextEditor(text: $person.biography).font(.system(size: 13)).frame(minHeight: 80)
                    Text("Можно записать воспоминания, источник сведений или то, что ещё предстоит узнать.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if let photoError { Text(photoError).font(.caption).foregroundStyle(.red) }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden)
            Divider()
            HStack {
                Text("Неизвестные сведения можно оставить пустыми.").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.isNew ? "Добавить" : "Сохранить") {
                    person.givenName = person.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
                    person.familyName = person.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !person.isDeceased { person.deathDate = "" }
                    store.savePerson(person, relativeID: request.relativeID, role: role, photo: photo)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(person.givenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && person.familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(20)
        }
        .frame(width: 610, height: 715).background(Palette.canvas).tint(Palette.accent)
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
            photo = Attachment(personID: person.id, filename: url.lastPathComponent,
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
        }.padding(28).frame(width: 430).onAppear { title = store.project.title }.tint(Palette.accent)
    }
}
