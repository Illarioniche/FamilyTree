import XCTest
@testable import FamilyTreeCore

final class LegacySurnameRepairTests: XCTestCase {
    func testExactGeneratedParagraphCreatesReadOnlyProposal() throws {
        let person = legacyPerson()
        let project = FamilyProject(people: [person])
        let before = project
        let proposals = LegacySurnameRepair.suggestions(in: project)
        let proposal = try XCTUnwrap(proposals.first)
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposal.personID, person.id)
        XCTAssertEqual(proposal.previousFamilyName, "Смирнова")
        XCTAssertEqual(proposal.proposedFamilyName, "Петрова")
        XCTAssertEqual(proposal.proposedMaidenName, "Смирнова")
        XCTAssertEqual(project, before)
    }

    func testSelectedRepairPreservesOtherPeopleAndEveryUnrelatedField() throws {
        var first = legacyPerson()
        first.biography = "  Первая заметка.\nПродолжение  \n\nДругое имя из GEDCOM: Петрова\n\n  Последняя заметка.  "
        let second = legacyPerson()
        let attachment = Attachment(personID: first.id, filename: "image.png", mimeType: "image/png", data: Data([1, 2, 3]))
        first.photoID = attachment.id
        first.birthDate = "около 1901"; first.occupation = "Учитель"; first.isFavorite = true
        let relationship = Relationship(fromID: first.id, toID: second.id, kind: .parent)
        let event = FamilyEvent(personID: first.id, title: "Событие", notes: "Источник")
        var project = FamilyProject(rootPersonID: first.id, people: [first, second], relationships: [relationship],
                                    events: [event], attachments: [attachment])
        let before = project
        let proposal = try XCTUnwrap(LegacySurnameRepair.suggestions(in: project).first)
        XCTAssertEqual(LegacySurnameRepair.apply([proposal], to: &project), 1)
        var expected = first
        expected.familyName = "Петрова"; expected.maidenName = "Смирнова"
        expected.biography = "  Первая заметка.\nПродолжение  \n\n  Последняя заметка.  "
        XCTAssertEqual(project.people, [expected, second])
        XCTAssertEqual(project.relationships, before.relationships)
        XCTAssertEqual(project.events, before.events)
        XCTAssertEqual(project.attachments, before.attachments)
        XCTAssertEqual(project.rootPersonID, before.rootPersonID)
        XCTAssertEqual(project.createdAt, before.createdAt)
        XCTAssertEqual(project.modifiedAt, before.modifiedAt)
    }

    func testStaleSurnameOrBiographyProposalsDoNotOverwriteEdits() throws {
        let person = legacyPerson()
        let original = FamilyProject(people: [person])
        let proposal = try XCTUnwrap(LegacySurnameRepair.suggestions(in: original).first)
        for field in 0..<3 {
            var project = original
            if field == 0 { project.people[0].familyName = "Новая" }
            if field == 1 { project.people[0].maidenName = "Уточнённая" }
            if field == 2 { project.people[0].biography += "\n\nНовая заметка" }
            let edited = project
            XCTAssertEqual(LegacySurnameRepair.apply([proposal], to: &project), 0)
            XCTAssertEqual(project, edited)
        }
        var removed = original
        removed.people.removeAll()
        XCTAssertEqual(LegacySurnameRepair.apply([proposal], to: &removed), 0)
    }

    func testSeveralNamesProseAndFullNamesAreNotGuessed() {
        for biography in [
            "Другое имя из GEDCOM: Петрова\n\nДругое имя из GEDCOM: Иванова",
            "Заметка: Другое имя из GEDCOM: Петрова",
            "Другое имя из GEDCOM: Петрова\nЭто часть рассказа",
            "Другое имя из GEDCOM: Анна Петрова",
            "Другое имя из GEDCOM: Анна /Петрова/",
            "Другое имя из GEDCOM: ",
            "Другое имя из GEDCOM: Петрова?"
        ] {
            var person = legacyPerson(); person.biography = biography
            XCTAssertTrue(LegacySurnameRepair.suggestions(in: FamilyProject(people: [person])).isEmpty)
        }
    }

    func testDuplicateExactGeneratedParagraphsAreHandledOnce() throws {
        var person = legacyPerson()
        person.biography = "Другое имя из GEDCOM: Петрова\n\nТекст.\n\nДругое имя из GEDCOM: Петрова"
        var project = FamilyProject(people: [person])
        let proposals = LegacySurnameRepair.suggestions(in: project)
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(LegacySurnameRepair.apply(proposals, to: &project), 1)
        XCTAssertEqual(project.people[0].biography, "Текст.")
    }

    func testExplicitMaidenNameAlreadyAppliedAndUnknownOriginalStayUntouched() {
        var maiden = legacyPerson(); maiden.maidenName = "Другая"
        var applied = legacyPerson(); applied.familyName = "Петрова"
        var sameCase = legacyPerson(); sameCase.familyName = "петрова"
        var unknown = legacyPerson(); unknown.familyName = ""
        let project = FamilyProject(people: [maiden, applied, sameCase, unknown])
        XCTAssertTrue(LegacySurnameRepair.suggestions(in: project).isEmpty)
    }

    func testHyphenatedApostropheAndUnicodeSurnamesAreAcceptedWithoutGenderGuessing() {
        for name in ["Смирнова-Петрова", "O’Neill", "D'Angelo", "García", "Γεωργίου"] {
            var person = legacyPerson()
            person.gender = .male
            person.biography = "Другое имя из GEDCOM: " + name
            let proposals = LegacySurnameRepair.suggestions(in: FamilyProject(people: [person]))
            XCTAssertEqual(proposals.first?.proposedFamilyName, name)
        }
    }

    func testRepeatApplicationIsIdempotentAndUnrelatedLaterEditsSurvive() throws {
        var project = FamilyProject(people: [legacyPerson()])
        let proposal = try XCTUnwrap(LegacySurnameRepair.suggestions(in: project).first)
        project.people[0].birthPlace = "Новый город"
        XCTAssertEqual(LegacySurnameRepair.apply([proposal, proposal], to: &project), 1)
        XCTAssertEqual(project.people[0].birthPlace, "Новый город")
        let repaired = project
        XCTAssertEqual(LegacySurnameRepair.apply([proposal], to: &project), 0)
        XCTAssertEqual(project, repaired)
        XCTAssertTrue(LegacySurnameRepair.suggestions(in: project).isEmpty)
    }

    private func legacyPerson() -> Person {
        Person(givenName: "Анна", patronymic: "Петровна", familyName: "Смирнова", gender: .female,
               biography: "Другое имя из GEDCOM: Петрова")
    }
}
