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
            try checkRelativeCreation(in: directory)
            try checkTreeDeletion(in: directory)
            print("Store integration: \(assertions) checks passed (autosave, media, dates, undo/redo, backup, surname repair, default centre, search navigation, tree library, tree deletion, relative creation, invalid relation, save failure/retry).")
        } catch {
            fputs("Store integration FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func checkRelativeCreation(in directory: URL) throws {
        let document = directory.appendingPathComponent("Добавление-родственников.familytree")
        let father = Person(givenName: "Илья", familyName: "Примеров", gender: .male)
        let mother = Person(givenName: "Анна", familyName: "Примерова", gender: .female)
        let paternalGrandfather = Person(givenName: "Павел", familyName: "Примеров", gender: .male)
        let paternalGrandmother = Person(givenName: "Вера", familyName: "Примерова", gender: .female)
        let maternalGrandfather = Person(givenName: "Борис", familyName: "Тестов", gender: .male)
        let maternalGrandmother = Person(givenName: "Нина", familyName: "Тестова", gender: .female)
        let previousChild = Person(givenName: "Сергей", familyName: "Примеров", gender: .male)
        let original = FamilyProject(title: "Связи Примеровых", rootPersonID: father.id,
                                     people: [father, mother, paternalGrandfather, paternalGrandmother,
                                              maternalGrandfather, maternalGrandmother, previousChild],
                                     relationships: [
            Relationship(fromID: father.id, toID: mother.id, kind: .partner),
            Relationship(fromID: paternalGrandfather.id, toID: father.id, kind: .parent),
            Relationship(fromID: paternalGrandmother.id, toID: father.id, kind: .parent),
            Relationship(fromID: maternalGrandfather.id, toID: mother.id, kind: .parent),
            Relationship(fromID: maternalGrandmother.id, toID: mother.id, kind: .parent),
            Relationship(fromID: father.id, toID: previousChild.id, kind: .parent)
        ])
        try ProjectDatabase.save(original, to: document)
        let store = FamilyStore(preview: true)
        store.replaceProject(try ProjectDatabase.load(from: document), url: document)
        let child = Person(givenName: "Михаил", patronymic: "Ильич", familyName: "Примеров", gender: .male)
        let photo = Attachment(personID: child.id, filename: "child.png", mimeType: "image/png", data: Data([137, 80, 78, 71, 5, 9]))
        let plan = RelativeCreationPlan(role: .child, relativeID: father.id, secondParentID: mother.id)
        try require(store.savePerson(child, creationPlan: plan, photo: photo),
                    "Saving a new child with two selected parents and photo should succeed")
        try require(store.undoStack.count == 1 && !store.hasUnsavedChanges && store.selection == child.id,
                    "Person, both links and photo must be one saved undo step with the new card selected")
        var saved = try ProjectDatabase.load(from: document)
        try require(Set(saved.parents(of: child.id).map(\.id)) == Set([father.id, mother.id]),
                    "Both explicitly selected parents must survive reopening")
        try require(saved.relationships.count == original.relationships.count + 2,
                    "Adding a child must not persist redundant grandparent or sibling links")
        try require(saved.person(child.id)?.photoID == photo.id && saved.attachments.first(where: { $0.id == photo.id }) == photo,
                    "The child photo and its association must be saved with the new family links")
        let close = TreeScope.make(project: saved, focusID: child.id, mode: .close)
        try require(Set(close.project.people.map(\.id)) == Set(original.people.map(\.id) + [child.id]),
                    "The reopened child must see both parents, all four grandparents and the existing half sibling")
        try require(saved.parents(of: previousChild.id).map(\.id) == [father.id],
                    "Adding another child must not assign a new parent to existing children")

        let created = store.project
        store.undo()
        try require(store.project.people == original.people && store.project.relationships == original.relationships && store.project.attachments.isEmpty,
                    "One undo must remove the child, both parent links and its photo together")
        saved = try ProjectDatabase.load(from: document)
        try require(saved.people == original.people && saved.relationships == original.relationships && saved.attachments.isEmpty,
                    "Undo of relative creation must persist the complete previous family")
        store.redo()
        saved = try ProjectDatabase.load(from: document)
        try require(saved.people == created.people && saved.relationships == created.relationships && saved.attachments == created.attachments,
                    "One redo must restore and persist the complete relative creation")
        let undoAfterCreate = store.undoStack.count
        let bytesAfterCreate = try Data(contentsOf: document)
        try require(store.savePerson(child, creationPlan: plan, photo: photo),
                    "Repeating the same successful save should be harmless")
        try require(store.project.people.count == created.people.count && store.project.relationships == created.relationships && store.project.attachments == created.attachments,
                    "Repeated save must not duplicate the person, links or photo")
        try require(store.undoStack.count == undoAfterCreate && (try Data(contentsOf: document)) == bytesAfterCreate,
                    "An unchanged repeated save must not add history or rewrite the document")

        // Keep a redo entry while testing rejection: neither history direction may change.
        store.undo()
        store.selection = mother.id
        let beforeInvalid = store.project
        let undoBeforeInvalid = store.undoStack
        let redoBeforeInvalid = store.redoStack
        let selectionBeforeInvalid = store.selection
        let fileBeforeInvalid = try Data(contentsOf: document)
        let backupURL = URL(fileURLWithPath: document.path + ".backup")
        let backupBeforeInvalid = try Data(contentsOf: backupURL)
        let invalidChild = Person(givenName: "Несохранённый ребёнок")
        let invalidPhoto = Attachment(personID: invalidChild.id, filename: "invalid-child.png", mimeType: "image/png", data: Data([1, 2, 3]))
        let invalidPlan = RelativeCreationPlan(role: .child, relativeID: father.id, secondParentID: UUID())
        try require(!store.savePerson(invalidChild, creationPlan: invalidPlan, photo: invalidPhoto),
                    "A missing second parent must reject the complete relative save")
        try require(store.errorMessage != nil && store.project == beforeInvalid && !store.hasUnsavedChanges,
                    "Rejected relative creation must leave no person, links, attachment or dirty state")
        try require(store.undoStack == undoBeforeInvalid && store.redoStack == redoBeforeInvalid && store.selection == selectionBeforeInvalid,
                    "Rejected relative creation must preserve undo, redo and selection")
        try require((try Data(contentsOf: document)) == fileBeforeInvalid && (try Data(contentsOf: backupURL)) == backupBeforeInvalid,
                    "Rejected relative creation must preserve both the document and its backup byte-for-byte")
        store.errorMessage = nil
        store.redo()

        var newPartner = Person(givenName: "Ольга", familyName: "Иванова", maidenName: "Сидорова", gender: .female)
        let beforePartner = store.project.relationships
        try require(store.savePerson(newPartner, creationPlan: .init(role: .partner, relativeID: father.id), photo: nil),
                    "A new partner should be saved through the same relative-creation transaction")
        try require(store.project.relationships.count == beforePartner.count + 1 && store.project.children(of: newPartner.id).isEmpty,
                    "A new partner must not automatically become parent of the anchor's existing children")
        try require(Set(store.project.parents(of: child.id).map(\.id)) == Set([father.id, mother.id]) && store.project.parents(of: previousChild.id).map(\.id) == [father.id],
                    "Creating a partnership must preserve the existing children's parent sets")
        let halfSibling = Person(givenName: "Мария", familyName: "Примерова", gender: .female)
        try require(store.savePerson(halfSibling, creationPlan: .init(role: .sibling, relativeID: child.id, sharedParentIDs: [mother.id]), photo: nil),
                    "Creating a sibling with one explicitly selected shared parent should succeed")
        saved = try ProjectDatabase.load(from: document)
        try require(saved.parents(of: halfSibling.id).map(\.id) == [mother.id],
                    "The sibling must share only the selected parent after reopening")
        let siblingClose = TreeScope.make(project: saved, focusID: halfSibling.id, mode: .close)
        try require(siblingClose.project.person(child.id) != nil && siblingClose.project.person(previousChild.id) == nil,
                    "Half-sibling scope must follow actual shared parents without inventing additional sibling links")

        let adoptedChild = Person(givenName: "Алексей", familyName: "Примеров", gender: .male)
        try require(store.savePerson(adoptedChild, creationPlan: .init(role: .adoptedChild, relativeID: father.id, secondParentID: mother.id), photo: nil),
                    "An adopted child can be created with two explicitly selected adoptive parents")
        saved = try ProjectDatabase.load(from: document)
        let adoptiveLinks = saved.relationships.filter { $0.toID == adoptedChild.id && $0.kind.isParent }
        try require(adoptiveLinks.count == 2 && adoptiveLinks.allSatisfy { $0.kind == .adoptiveParent },
                    "Both adoptive links must retain their kind after autosave and reopening")

        newPartner.gender = .male
        let beforeEditLinks = store.project.relationships
        try require(store.savePerson(newPartner, creationPlan: nil, photo: nil),
                    "Editing an existing person's gender must remain valid")
        saved = try ProjectDatabase.load(from: document)
        try require(saved.person(newPartner.id)?.gender == .male && saved.person(newPartner.id)?.maidenName == "Сидорова",
                    "Hiding the maiden-name field for a man must not erase a previously saved surname")
        try require(saved.relationships == beforeEditLinks,
                    "An ordinary person edit must not infer or rewrite family connections")
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

    private static func checkTreeDeletion(in directory: URL) throws {
        let manager = FileManager.default
        let base = directory.appendingPathComponent("DeletionChecks", isDirectory: true)
        let libraryURL = base.appendingPathComponent("Library", isDirectory: true)
        let trashURL = base.appendingPathComponent("TestTrash", isDirectory: true)
        try manager.createDirectory(at: trashURL, withIntermediateDirectories: true)
        var moved: [URL] = []
        let store = FamilyStore(preview: true, libraryDirectoryURL: libraryURL, trashItem: { source in
            try manager.moveItem(at: source, to: trashURL.appendingPathComponent(source.lastPathComponent))
            moved.append(source)
        })
        let library = TreeLibrary(directoryURL: libraryURL)
        let person = Person(givenName: "Анна", familyName: "Проверкина")
        let attachment = Attachment(personID: person.id, filename: "note.txt", mimeType: "text/plain", data: Data("Семейная запись".utf8))
        let first = FamilyProject(title: "Для удаления", rootPersonID: person.id, people: [person], attachments: [attachment])
        let firstURL = try library.create(first)
        store.openProject(at: firstURL)
        store.mutate { $0.title = "Последняя редакция" }
        guard let firstEntry = store.savedTrees.first(where: { $0.url == firstURL }) else { throw AppError.message("Expected deletion candidate") }
        let backupURL = URL(fileURLWithPath: firstURL.path + ".backup")
        let savedBytes = try Data(contentsOf: firstURL)
        let backupBytes = try Data(contentsOf: backupURL)
        store.personEditor = PersonEditRequest(person: person, isNew: false)
        store.eventEditor = EventEditRequest(event: FamilyEvent(personID: person.id, kind: .birth, date: "2000"))
        store.showingRelationshipEditor = true
        store.showingProjectName = true
        store.showingHomePersonPicker = true
        store.showingSurnameReview = true
        store.newProject()
        store.query = "Анна"
        try require(store.canTrashTree(firstEntry) && !store.canForgetTree(firstEntry), "Managed trees should expose Trash, not removal from the external list")
        try require(store.deleteTree(firstEntry), "Confirmed deletion should move the active managed tree to the injected Trash")
        try require(moved == [firstURL, backupURL], "The document must be trashed before its automatic backup")
        try require(!manager.fileExists(atPath: firstURL.path) && !manager.fileExists(atPath: backupURL.path), "Deleted document and backup must disappear from their original locations")
        try require(try Data(contentsOf: trashURL.appendingPathComponent(firstURL.lastPathComponent)) == savedBytes, "Trash must preserve the complete document bytes, including attachments")
        try require(try Data(contentsOf: trashURL.appendingPathComponent(backupURL.lastPathComponent)) == backupBytes, "Trash must preserve the previous automatic backup bytes")
        try require(store.fileURL == nil && store.project.people.isEmpty && store.project.attachments.isEmpty && store.selection == nil && !store.hasUnsavedChanges && store.showingTreeLibrary && store.lastSavedAt == nil,
                    "Deleting the active tree must close its in-memory session and return to an empty library")
        try require(store.undoStack.isEmpty && store.redoStack.isEmpty && store.personEditor == nil && store.eventEditor == nil && store.treeCreation == nil && !store.showingRelationshipEditor && !store.showingProjectName && !store.showingHomePersonPicker && !store.showingSurnameReview && store.query.isEmpty,
                    "Deletion must clear history, pending editors, dialogs and search tied to the removed document")
        store.undo(); store.redo()
        store.mutate { $0.title = "Другое дерево" }
        try require(!manager.fileExists(atPath: firstURL.path) && store.fileURL == nil, "Undo, redo and subsequent edits must not resurrect the deleted file")
        store.refreshLibrary()
        try require(store.savedTrees.isEmpty, "A refresh must not rediscover the deleted tree or its backup")

        let inactiveURL = try library.create(FamilyProject(title: "Неактивное"))
        let activeURL = try library.create(FamilyProject(title: "Активное"))
        store.replaceProject(try ProjectDatabase.load(from: activeURL), url: activeURL)
        store.mutate { $0.title = "С изменениями" }
        store.showLibrary()
        guard let inactive = store.savedTrees.first(where: { $0.url == inactiveURL }) else { throw AppError.message("Expected inactive deletion candidate") }
        let activeBefore = store.project
        let historyBefore = store.undoStack
        let activeBytes = try Data(contentsOf: activeURL)
        try require(store.deleteTree(inactive), "Deleting an inactive managed tree should succeed")
        try require(store.project == activeBefore && store.fileURL == activeURL && store.undoStack == historyBefore && (try Data(contentsOf: activeURL)) == activeBytes,
                    "Deleting another tree must preserve the active document, its bytes and undo history")
        let fresh = FamilyStore(preview: true, libraryDirectoryURL: libraryURL)
        try require(fresh.savedTrees.map(\.url) == [activeURL], "Reopening an isolated library should list only remaining managed documents")

        let externalURL = base.appendingPathComponent("External.familytree")
        try ProjectDatabase.save(FamilyProject(title: "Внешнее"), to: externalURL)
        store.openProject(at: externalURL)
        guard let external = store.savedTrees.first(where: { $0.url == externalURL }) else { throw AppError.message("Expected external deletion candidate") }
        try require(store.deleteTree(external), "Registered external documents can also be moved to Trash")
        store.refreshLibrary()
        try require(!store.savedTrees.contains(where: { $0.id == external.id }) && !manager.fileExists(atPath: externalURL.path), "Trashing an external tree must unregister it rather than leave an unavailable entry")
        let unrelatedURL = base.appendingPathComponent("NotRegistered.familytree")
        try ProjectDatabase.save(FamilyProject(title: "Постороннее"), to: unrelatedURL)
        let unrelated = TreeLibraryEntry(url: unrelatedURL, title: "Постороннее", peopleCount: 0, modifiedAt: Date())
        let movedBefore = moved.count
        try require(!store.canTrashTree(unrelated) && !store.deleteTree(unrelated) && moved.count == movedBefore && manager.fileExists(atPath: unrelatedURL.path),
                    "An arbitrary file not in this library must never reach the Trash handler")

        let failedURL = try library.create(FamilyProject(title: "Ошибка удаления"))
        let failed = FamilyStore(preview: true, libraryDirectoryURL: libraryURL, trashItem: { _ in throw AppError.message("Injected Trash failure") })
        failed.openProject(at: failedURL)
        failed.mutate { $0.title = "Нужно сохранить" }
        guard let failedEntry = failed.savedTrees.first(where: { $0.url == failedURL }) else { throw AppError.message("Expected failed deletion candidate") }
        let failedProject = failed.project
        let failedHistory = failed.undoStack
        let failedList = failed.savedTrees
        let failedBytes = try Data(contentsOf: failedURL)
        try require(!failed.deleteTree(failedEntry) && failed.errorMessage != nil, "Trash failure must be reported")
        try require(failed.project == failedProject && failed.fileURL == failedURL && failed.undoStack == failedHistory && failed.savedTrees == failedList && (try Data(contentsOf: failedURL)) == failedBytes,
                    "Trash failure must retain the active session, library, history and file")

        var saveTrashCalls = 0
        let dirty = FamilyStore(preview: true, libraryDirectoryURL: libraryURL, trashItem: { source in
            saveTrashCalls += 1
            try manager.moveItem(at: source, to: trashURL.appendingPathComponent(source.lastPathComponent))
        })
        dirty.openProject(at: failedURL)
        try Data("unrecognized document".utf8).write(to: failedURL, options: .atomic)
        dirty.mutate { $0.title = "Несохранённая редакция" }
        guard let dirtyEntry = dirty.savedTrees.first(where: { $0.url == failedURL }) else { throw AppError.message("Expected dirty deletion candidate") }
        try require(dirty.hasUnsavedChanges && !dirty.deleteTree(dirtyEntry) && saveTrashCalls == 0 && dirty.hasUnsavedChanges && dirty.project.title == "Несохранённая редакция",
                    "An unsaved active tree must not be trashed when its latest changes cannot be saved")
        try failedBytes.write(to: failedURL, options: .atomic)
        try require(dirty.deleteTree(dirtyEntry) && !dirty.hasUnsavedChanges, "Once saving works, deleting a dirty tree should save its latest state before trashing")
        try require(try ProjectDatabase.load(from: trashURL.appendingPathComponent(failedURL.lastPathComponent)).title == "Несохранённая редакция",
                    "Restoring a deleted dirty tree from Trash must recover the latest in-memory changes")

        let partialURL = try library.create(FamilyProject(title: "Копия недоступна"))
        let partial = FamilyStore(preview: true, libraryDirectoryURL: libraryURL, trashItem: { source in
            if source.pathExtension == "backup" { throw AppError.message("Injected backup failure") }
            try manager.moveItem(at: source, to: trashURL.appendingPathComponent(source.lastPathComponent))
        })
        partial.openProject(at: partialURL)
        partial.mutate { $0.title = "Есть резервная копия" }
        guard let partialEntry = partial.savedTrees.first(where: { $0.url == partialURL }) else { throw AppError.message("Expected backup failure candidate") }
        try require(partial.deleteTree(partialEntry) && partial.fileURL == nil && partial.infoMessage != nil,
                    "If only the backup cannot be trashed, close the deleted document and explain the remaining backup")
        try require(manager.fileExists(atPath: partialURL.path + ".backup") && !manager.fileExists(atPath: partialURL.path), "Backup failure must preserve its bytes without recreating the removed main file")

        let missingURL = base.appendingPathComponent("Missing.familytree")
        try ProjectDatabase.save(FamilyProject(title: "Исчезнувшее"), to: missingURL)
        store.openProject(at: missingURL)
        let movedMissing = base.appendingPathComponent("Moved.familytree")
        try manager.moveItem(at: missingURL, to: movedMissing)
        store.refreshLibrary()
        guard let missing = store.savedTrees.first(where: { $0.url == missingURL }) else { throw AppError.message("Expected missing external entry") }
        let callsBeforeForget = moved.count
        try require(store.canForgetTree(missing) && !store.canTrashTree(missing) && store.forgetUnavailableTree(missing), "An unavailable external tree can be removed from the list without trashing a file")
        store.refreshLibrary()
        try require(!store.savedTrees.contains(where: { $0.id == missing.id }) && store.fileURL == nil && store.showingTreeLibrary && moved.count == callsBeforeForget && manager.fileExists(atPath: movedMissing.path),
                    "Forgetting an unavailable active tree must close the session, unregister it and leave relocated data alone")
        store.openProject(at: movedMissing)
        let corruptBytes = Data("damaged external document".utf8)
        try corruptBytes.write(to: movedMissing, options: .atomic)
        store.refreshLibrary()
        guard let corrupt = store.savedTrees.first(where: { $0.url == movedMissing }) else { throw AppError.message("Expected corrupt external entry") }
        store.mutate { $0.title = "Несохранённое" }
        try require(!store.forgetUnavailableTree(corrupt) && store.hasUnsavedChanges && store.fileURL == movedMissing, "Forgetting an unavailable active tree must not discard unsaved edits")
        store.replaceProject(FamilyProject(title: "Другая сессия"), url: nil)
        store.mutate { $0.title = "Несохранённая другая сессия" }
        let unsavedBeforeForget = store.project
        let unsavedHistoryBeforeForget = store.undoStack
        try require(store.canForgetTree(corrupt) && store.forgetUnavailableTree(corrupt) && (try Data(contentsOf: movedMissing)) == corruptBytes,
                    "Forgetting a corrupt inactive external tree must leave the original file untouched")
        try require(store.project == unsavedBeforeForget && store.undoStack == unsavedHistoryBeforeForget && store.hasUnsavedChanges,
                    "Removing another unavailable entry must preserve the current unsaved work and its undo history")

        // SQLite sidecars may hold committed or in-flight data that must stay beside
        // the main file. Even saving a dirty session is unsafe until they are closed.
        let journalURL = try library.create(FamilyProject(title: "Открытый журнал"))
        var journalTrashCalls = 0
        let journalStore = FamilyStore(preview: true, libraryDirectoryURL: libraryURL, trashItem: { _ in journalTrashCalls += 1 })
        journalStore.openProject(at: journalURL)
        let journalOriginal = try Data(contentsOf: journalURL)
        try Data("temporarily unrecognized".utf8).write(to: journalURL, options: .atomic)
        journalStore.mutate { $0.title = "Редакция в памяти" }
        try journalOriginal.write(to: journalURL, options: .atomic)
        guard let journalEntry = journalStore.savedTrees.first(where: { $0.url == journalURL }) else { throw AppError.message("Expected SQLite sidecar candidate") }
        let journalProject = journalStore.project
        let journalHistory = journalStore.undoStack
        for suffix in ["-wal", "-journal"] {
            let sidecar = URL(fileURLWithPath: journalURL.path + suffix)
            let marker = Data("Unprocessed SQLite sidecar \(suffix)".utf8)
            try marker.write(to: sidecar)
            try require(!journalStore.deleteTree(journalEntry) && journalTrashCalls == 0 && journalStore.hasUnsavedChanges && journalStore.project == journalProject && journalStore.undoStack == journalHistory && journalStore.fileURL == journalURL,
                        "A SQLite sidecar must block both saving and deletion without changing the active dirty session")
            try require((try Data(contentsOf: journalURL)) == journalOriginal && (try Data(contentsOf: sidecar)) == marker && journalStore.errorMessage?.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil,
                        "A blocked SQLite deletion must preserve document and sidecar bytes and explain the failure in Russian")
            try manager.removeItem(at: sidecar)
        }

        let backupJournalURL = try library.create(FamilyProject(title: "Журнал резервной копии"))
        var backupJournalMoves: [URL] = []
        let backupJournalStore = FamilyStore(preview: true, libraryDirectoryURL: libraryURL, trashItem: { source in
            try manager.moveItem(at: source, to: trashURL.appendingPathComponent(source.lastPathComponent))
            backupJournalMoves.append(source)
        })
        backupJournalStore.openProject(at: backupJournalURL)
        backupJournalStore.mutate { $0.title = "Основное дерево готово" }
        let guardedBackup = URL(fileURLWithPath: backupJournalURL.path + ".backup")
        let guardedBackupBytes = try Data(contentsOf: guardedBackup)
        let backupSidecar = URL(fileURLWithPath: guardedBackup.path + "-wal")
        let backupMarker = Data("Backup SQLite sidecar".utf8)
        try backupMarker.write(to: backupSidecar)
        guard let backupJournalEntry = backupJournalStore.savedTrees.first(where: { $0.url == backupJournalURL }) else { throw AppError.message("Expected backup sidecar candidate") }
        try require(backupJournalStore.deleteTree(backupJournalEntry) && backupJournalMoves == [backupJournalURL] && backupJournalStore.fileURL == nil && backupJournalStore.infoMessage != nil,
                    "An active backup sidecar should leave only that backup in place with a warning after the main tree is trashed")
        try require((try Data(contentsOf: guardedBackup)) == guardedBackupBytes && (try Data(contentsOf: backupSidecar)) == backupMarker,
                    "The backup and its SQLite sidecar must remain together and byte-for-byte intact")

        let directoryURL = base.appendingPathComponent("ReplacedByDirectory.familytree")
        try ProjectDatabase.save(FamilyProject(title: "Заменено папкой"), to: directoryURL)
        var directoryTrashCalls = 0
        let directoryStore = FamilyStore(preview: true, libraryDirectoryURL: libraryURL, trashItem: { _ in directoryTrashCalls += 1 })
        directoryStore.openProject(at: directoryURL)
        guard let directoryEntry = directoryStore.savedTrees.first(where: { $0.url == directoryURL }) else { throw AppError.message("Expected directory replacement candidate") }
        let heldDirectoryFile = base.appendingPathComponent("HeldDocument.familytree")
        try manager.moveItem(at: directoryURL, to: heldDirectoryFile)
        try manager.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        let directoryContent = directoryURL.appendingPathComponent("unrelated.txt")
        let directoryMarker = Data("Do not move this folder".utf8)
        try directoryMarker.write(to: directoryContent)
        try require(!directoryStore.canTrashTree(directoryEntry) && !directoryStore.deleteTree(directoryEntry) && directoryTrashCalls == 0 && directoryStore.fileURL == directoryURL && (try Data(contentsOf: directoryContent)) == directoryMarker,
                    "A document path replaced by a directory must never move that directory or its unrelated contents to Trash")

        let symlinkURL = try library.create(FamilyProject(title: "Ссылка вместо копии"))
        var symlinkMoves: [URL] = []
        let symlinkStore = FamilyStore(preview: true, libraryDirectoryURL: libraryURL, trashItem: { source in
            try manager.moveItem(at: source, to: trashURL.appendingPathComponent(source.lastPathComponent))
            symlinkMoves.append(source)
        })
        symlinkStore.openProject(at: symlinkURL)
        let backupLink = URL(fileURLWithPath: symlinkURL.path + ".backup")
        let linkTarget = base.appendingPathComponent("UnrelatedBackupTarget.txt")
        let targetBytes = Data("Do not follow this backup link".utf8)
        try targetBytes.write(to: linkTarget)
        try manager.createSymbolicLink(at: backupLink, withDestinationURL: linkTarget)
        guard let symlinkEntry = symlinkStore.savedTrees.first(where: { $0.url == symlinkURL }) else { throw AppError.message("Expected backup symlink candidate") }
        try require(symlinkStore.deleteTree(symlinkEntry) && symlinkMoves == [symlinkURL] && symlinkStore.infoMessage != nil && (try Data(contentsOf: linkTarget)) == targetBytes && (try backupLink.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true,
                    "A symbolic-link backup must remain untouched and never cause its unrelated target to be moved")

        let preview = FamilyStore(preview: true, libraryDirectoryURL: libraryURL)
        guard let previewEntry = preview.savedTrees.first else { throw AppError.message("Expected preview safeguard candidate") }
        let previewBytes = try Data(contentsOf: previewEntry.url)
        try require(!preview.deleteTree(previewEntry) && (try Data(contentsOf: previewEntry.url)) == previewBytes,
                    "Preview mode without an injected handler must never use the real macOS Trash")
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !condition() { throw AppError.message(message) }
    }
}
