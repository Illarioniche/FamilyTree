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
            print("Store integration: \(assertions) checks passed (autosave, media, dates, undo/redo, backup, invalid relation, save failure/retry).")
        } catch {
            fputs("Store integration FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !condition() { throw AppError.message(message) }
    }
}
