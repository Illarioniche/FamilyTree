import SwiftUI
import AppKit
import FamilyTreeCore

private struct HistoryEntry: Identifiable {
    var id: String
    var person: Person
    var kind: EventKind
    var title: String
    var date: String
    var place: String
    var notes: String
    var event: FamilyEvent?
}

struct ChronicleView: View {
    @ObservedObject var store: FamilyStore
    @State private var selectedOnly = false
    private var entries: [HistoryEntry] {
        var result: [HistoryEntry] = []
        for person in store.project.people where !selectedOnly || person.id == store.selection {
            let personalEvents = store.project.events.filter { $0.personID == person.id }
            if !person.birthDate.isEmpty && !personalEvents.contains(where: { $0.kind == .birth }) {
                result.append(.init(id: "birth-\(person.id)", person: person, kind: .birth, title: "Рождение", date: person.birthDate, place: person.birthPlace, notes: "Начало новой истории"))
            }
            if person.isDeceased && !person.deathDate.isEmpty && !personalEvents.contains(where: { $0.kind == .death }) {
                result.append(.init(id: "death-\(person.id)", person: person, kind: .death, title: "Уход из жизни", date: person.deathDate, place: "", notes: "Сохраняя память"))
            }
            result.append(contentsOf: personalEvents.map {
                .init(id: $0.id.uuidString, person: person, kind: $0.kind,
                      title: $0.title.isEmpty ? $0.kind.title : $0.title, date: $0.date, place: $0.place, notes: $0.notes, event: $0)
            })
        }
        return result.sorted {
            let left = GenealogyDate.year(in: $0.date) ?? 9999
            let right = GenealogyDate.year(in: $1.date) ?? 9999
            return left == right ? $0.id < $1.id : left < right
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Выбранный человек", isOn: $selectedOnly).toggleStyle(.checkbox)
                    .disabled(store.selection == nil)
                Spacer()
                Button {
                    if let id = store.selection ?? store.project.people.first?.id {
                        store.eventEditor = .init(event: FamilyEvent(personID: id))
                    }
                } label: { Label("Добавить событие", systemImage: "plus") }
                .disabled(store.project.people.isEmpty).buttonStyle(.bordered)
            }.font(.system(size: 11)).padding(.horizontal, 28).padding(.vertical, 16)
            if entries.isEmpty {
                EmptyCollectionView(symbol: "clock", title: "Моменты, которые важны",
                                    subtitle: "Укажите даты в карточках людей или добавьте семейное событие.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            HStack(alignment: .top, spacing: 15) {
                                Text(GenealogyDate.year(in: entry.date).map(String.init) ?? "—")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary).frame(width: 48, alignment: .trailing).padding(.top, 18)
                                VStack(spacing: 0) {
                                    Image(systemName: entry.kind.symbol).font(.system(size: 13))
                                        .foregroundStyle(Palette.accent).frame(width: 32, height: 32)
                                        .background(Palette.accent.opacity(0.08), in: Circle())
                                    Rectangle().fill(Palette.accent.opacity(0.15)).frame(width: 1).frame(minHeight: 72)
                                }.padding(.top, 12)
                                Button {
                                    store.selection = entry.person.id
                                    if let event = entry.event { store.eventEditor = .init(event: event) }
                                    else { store.edit(entry.person) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(entry.title).font(.system(size: 14, weight: .medium))
                                            Spacer()
                                            Text(GenealogyDate.display(entry.date)).font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                        Text(entry.person.fullName).font(.system(size: 12)).foregroundStyle(Palette.accent)
                                        if !entry.place.isEmpty {
                                            Label(entry.place, systemImage: "mappin").font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                        if !entry.notes.isEmpty {
                                            Text(entry.notes).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3).lineSpacing(3)
                                        }
                                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
                                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.divider, lineWidth: 1))
                                }.buttonStyle(.plain).padding(.bottom, 14)
                            }
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 25)
                }
            }
        }
    }
}

struct ArchiveView: View {
    @ObservedObject var store: FamilyStore
    @State private var selectedOnly = false
    @State private var preview: Attachment?
    private var items: [Attachment] {
        store.project.attachments.filter { !selectedOnly || $0.personID == store.selection }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Выбранный человек", isOn: $selectedOnly).toggleStyle(.checkbox).disabled(store.selection == nil)
                Spacer()
                Button {
                    if let id = store.selection ?? store.project.people.first?.id { store.addAttachment(to: id) }
                } label: { Label("Добавить файлы", systemImage: "plus") }
                .disabled(store.project.people.isEmpty).buttonStyle(.bordered)
            }.font(.system(size: 11)).padding(.horizontal, 28).padding(.vertical, 16)
            if items.isEmpty {
                EmptyCollectionView(symbol: "photo.on.rectangle.angled", title: "У памяти есть свой дом",
                                    subtitle: "Семейные фотографии, письма и документы. Файлы хранятся внутри вашего дерева.",
                                    actionTitle: store.project.people.isEmpty ? "Добавить человека" : "Добавить файлы",
                                    action: {
                    if let id = store.selection ?? store.project.people.first?.id { store.addAttachment(to: id) }
                    else { store.addPerson() }
                })
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 15)], spacing: 15) {
                        ForEach(items) { item in
                            Button {
                                if item.isImage { preview = item } else { store.exportAttachment(item) }
                            } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Group {
                                        if item.isImage, let image = NSImage(data: item.data) {
                                            Image(nsImage: image).resizable().scaledToFill()
                                        } else {
                                            ZStack {
                                                Palette.accent.opacity(0.07)
                                                Image(systemName: "doc.text").font(.system(size: 37, weight: .ultraLight)).foregroundStyle(Palette.accent)
                                            }
                                        }
                                    }.frame(height: 145).frame(maxWidth: .infinity).clipped()
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.filename).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text(store.project.person(item.personID)?.shortName ?? "")
                                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }.padding(14)
                                }
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.divider, lineWidth: 1))
                            }
                            .buttonStyle(.plain).contextMenu {
                                Button("Сохранить файл…") { store.exportAttachment(item) }
                                Button("Открыть карточку человека") { store.selection = item.personID }
                                if item.isImage {
                                    Button("Сделать фотографией человека") {
                                        store.mutate { project in
                                            if let index = project.people.firstIndex(where: { $0.id == item.personID }) { project.people[index].photoID = item.id }
                                        }
                                    }
                                }
                                Divider()
                                Button("Удалить из архива", role: .destructive) {
                                    store.mutate { project in
                                        for index in project.people.indices where project.people[index].photoID == item.id { project.people[index].photoID = nil }
                                        project.attachments.removeAll { $0.id == item.id }
                                    }
                                }
                            }
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 28)
                }
            }
        }
        .sheet(item: $preview) { item in
            VStack(spacing: 15) {
                if let image = NSImage(data: item.data) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 800, maxHeight: 550) }
                HStack {
                    Text(item.filename).font(.system(size: 12))
                    Spacer()
                    Button("Сохранить файл…") { store.exportAttachment(item) }
                    Button("Закрыть") { preview = nil }.keyboardShortcut(.cancelAction)
                }
            }.padding(22).frame(minWidth: 500, minHeight: 300)
        }
    }
}
