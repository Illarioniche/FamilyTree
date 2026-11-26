import XCTest
@testable import FamilyTreeCore

final class RelativePersonDraftTests: XCTestCase {
    private func family() -> (FamilyProject, Person, Person, Person) {
        let father = Person(givenName: "Илья", patronymic: "Ираклиевич", familyName: "Белов", gender: .male)
        let mother = Person(givenName: "Анна", familyName: "Белова", maidenName: "Орлова", gender: .female)
        let child = Person(givenName: "Мария", patronymic: "Ильинична", familyName: "Белова", gender: .female)
        return (FamilyProject(people: [father, mother, child], relationships: [
            Relationship(fromID: father.id, toID: mother.id, kind: .partner),
            Relationship(fromID: father.id, toID: child.id, kind: .parent),
            Relationship(fromID: mother.id, toID: child.id, kind: .parent)
        ]), father, mother, child)
    }

    func testChildSuggestionsFollowGenderAndUniquePartnerWithoutInventingGivenName() {
        let (project, father, mother, _) = family()
        var draft = RelativePersonDraft(person: Person(), isNew: true, relativeID: father.id, in: project)
        XCTAssertEqual(draft.secondParentID, mother.id)
        XCTAssertEqual(draft.person.patronymic, "")
        draft.setGender(.male, in: project)
        XCTAssertEqual(draft.person.familyName, "Белов")
        XCTAssertEqual(draft.person.patronymic, "Ильич")
        XCTAssertFalse(draft.showsMaidenName)
        draft.setGender(.female, in: project)
        XCTAssertEqual(draft.person.familyName, "Белова")
        XCTAssertEqual(draft.person.patronymic, "Ильинична")
        XCTAssertEqual(draft.person.givenName, "")
        XCTAssertTrue(draft.showsMaidenName)
    }

    func testCombinedImportedGivenNamesSupplyChildAndParentSuggestionsWithoutChangingOriginal() {
        let father = Person(givenName: "Илья Ираклиевич", familyName: "Примеров", gender: .male)
        let project = FamilyProject(people: [father])
        var draft = RelativePersonDraft(person: Person(gender: .male), isNew: true, relativeID: father.id, in: project)
        XCTAssertEqual(draft.person.patronymic, "Ильич")
        draft.setGender(.female, in: project)
        XCTAssertEqual(draft.person.patronymic, "Ильинична")
        draft.setRole(.parent, in: project)
        draft.setGender(.male, in: project)
        XCTAssertEqual(draft.person.givenName, "Ираклий")
        XCTAssertEqual(project.person(father.id), father)

        let daughter = Person(givenName: "Елена Сергеевна", familyName: "Примерова", gender: .female)
        let otherProject = FamilyProject(people: [daughter])
        let parent = RelativePersonDraft(person: Person(gender: .male), isNew: true, relativeID: daughter.id, role: .parent, in: otherProject)
        XCTAssertEqual(parent.person.givenName, "Сергей")
        XCTAssertEqual(otherProject.person(daughter.id)?.givenName, "Елена Сергеевна")
    }

    func testManualNamesAndIntentionalEmptyValueSurviveContextChanges() {
        let (project, father, _, _) = family()
        var draft = RelativePersonDraft(person: Person(gender: .male), isNew: true, relativeID: father.id, in: project)
        draft.setName("Ким", field: .familyName)
        draft.setName("", field: .patronymic)
        draft.setName("Саша", field: .givenName)
        draft.setGender(.female, in: project)
        draft.setSecondParent(nil, in: project)
        draft.setRole(.partner, in: project)
        draft.setRole(.parent, in: project)
        draft.setGender(.male, in: project)
        XCTAssertEqual(draft.person.familyName, "Ким")
        XCTAssertEqual(draft.person.patronymic, "")
        XCTAssertEqual(draft.person.givenName, "Саша")
    }

    func testSelectingDifferentFatherChangesOnlyUntouchedSuggestions() {
        var (project, _, mother, _) = family()
        let secondFather = Person(givenName: "Сергей", familyName: "Петров", gender: .male)
        project.people.append(secondFather)
        var draft = RelativePersonDraft(person: Person(gender: .female), isNew: true, relativeID: mother.id, in: project)
        draft.setSecondParent(secondFather.id, in: project)
        XCTAssertEqual(draft.person.patronymic, "Сергеевна")
        XCTAssertEqual(draft.person.familyName, "Петрова")
        draft.setSecondParent(nil, in: project)
        XCTAssertEqual(draft.person.patronymic, "")
        XCTAssertEqual(draft.person.familyName, "Белова")
        draft.setRole(.parent, in: project)
        draft.setRole(.child, in: project)
        XCTAssertTrue(draft.secondParentID == nil, "An explicit single-parent choice must survive switching roles")
    }

    func testMultiplePartnersRequireChoiceAndTwoFathersDoNotGuessPatronymic() {
        var (project, father, mother, _) = family()
        let other = Person(givenName: "Сергей", familyName: "Петров", gender: .male)
        project.people.append(other)
        project.relationships.append(Relationship(fromID: other.id, toID: mother.id, kind: .partner))
        var draft = RelativePersonDraft(person: Person(gender: .male), isNew: true, relativeID: mother.id, in: project)
        XCTAssertTrue(draft.secondParentID == nil)
        XCTAssertEqual(draft.person.patronymic, "")
        draft = RelativePersonDraft(person: Person(gender: .male), isNew: true, relativeID: father.id, in: project)
        draft.setSecondParent(other.id, in: project)
        XCTAssertTrue(draft.suggestedFather(in: project) == nil)
        XCTAssertEqual(draft.person.patronymic, "")
    }

    func testParentInferenceUsesKnownPatronymicAndClearsOnlyItsOwnSuggestion() {
        let (project, father, _, _) = family()
        var draft = RelativePersonDraft(person: Person(gender: .male), isNew: true, relativeID: father.id, role: .parent, in: project)
        XCTAssertEqual(draft.person.givenName, "Ираклий")
        XCTAssertEqual(draft.person.patronymic, "")
        draft.setGender(.female, in: project)
        XCTAssertEqual(draft.person.givenName, "")
        XCTAssertEqual(draft.person.familyName, "Белова")
    }

    func testHalfSiblingThroughMotherDoesNotInheritOtherFathersPatronymic() {
        let (project, father, mother, child) = family()
        var draft = RelativePersonDraft(person: Person(gender: .male), isNew: true, relativeID: child.id, role: .sibling, in: project)
        XCTAssertEqual(draft.sharedParentIDs, Set([father.id, mother.id]))
        XCTAssertEqual(draft.person.patronymic, "Ильич")
        draft.setSharedParent(father.id, selected: false, in: project)
        XCTAssertEqual(draft.person.patronymic, "")
        XCTAssertEqual(draft.creationPlan?.sharedParentIDs, Set([mother.id]))
    }

    func testSiblingAndParentPreferBirthSurnameAndAdoptionDoesNotGuessNames() {
        var (project, _, mother, _) = family()
        let grandfather = Person(givenName: "Павел", familyName: "Орлов", gender: .male)
        project.people.append(grandfather)
        project.relationships.append(Relationship(fromID: grandfather.id, toID: mother.id, kind: .parent))
        var draft = RelativePersonDraft(person: Person(gender: .male), isNew: true, relativeID: mother.id, role: .sibling, in: project)
        XCTAssertEqual(draft.person.familyName, "Орлов")
        XCTAssertEqual(draft.person.patronymic, "Павлович")
        for role in [RelativeCreationRole.partner, .adoptiveParent, .adoptedChild] {
            draft.setRole(role, in: project)
            XCTAssertEqual(draft.person.familyName, "")
            XCTAssertEqual(draft.person.patronymic, "")
        }
    }

    func testNewMaleCardDoesNotSaveHiddenMaidenNameButSwitchingBackRestoresDraftValue() {
        let (project, father, _, _) = family()
        var draft = RelativePersonDraft(person: Person(gender: .female), isNew: true, relativeID: father.id, in: project)
        draft.person.maidenName = "Орлова"
        draft.setGender(.male, in: project)
        XCTAssertFalse(draft.showsMaidenName)
        XCTAssertEqual(draft.personForSaving.maidenName, "")
        draft.setGender(.female, in: project)
        XCTAssertTrue(draft.showsMaidenName)
        XCTAssertEqual(draft.personForSaving.maidenName, "Орлова")
    }

    func testExistingCardNeverReceivesSuggestionsAndKeepsStoredMaidenNameWhenHidden() {
        let (project, father, _, _) = family()
        let existing = Person(givenName: "Александр", patronymic: "Неизвестно", familyName: "Ким", maidenName: "Ли", gender: .male)
        var draft = RelativePersonDraft(person: existing, isNew: false, relativeID: father.id, in: project)
        XCTAssertEqual(draft.person, existing)
        XCTAssertEqual(draft.personForSaving, existing)
        XCTAssertTrue(draft.creationPlan == nil)
        XCTAssertFalse(draft.showsMaidenName)
        draft.setGender(.female, in: project)
        draft.setGender(.male, in: project)
        XCTAssertEqual(draft.person, existing)
    }

    func testSuppliedNewCardNamesArePreservedAndUnrelatedCreationHasNoPlan() {
        let (project, father, _, _) = family()
        let person = Person(givenName: "Алекс", patronymic: "Вручную", familyName: "Ким", gender: .male)
        var draft = RelativePersonDraft(person: person, isNew: true, relativeID: father.id, in: project)
        draft.setGender(.female, in: project)
        XCTAssertEqual(draft.person.patronymic, "Вручную")
        XCTAssertEqual(draft.person.familyName, "Ким")
        let unrelated = RelativePersonDraft(person: Person(), isNew: true, in: project)
        XCTAssertTrue(unrelated.creationPlan == nil)
        XCTAssertEqual(unrelated.person.familyName, "")
        XCTAssertEqual(unrelated.person.patronymic, "")
    }
}
