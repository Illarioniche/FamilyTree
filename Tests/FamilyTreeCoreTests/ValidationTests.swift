import Foundation
import XCTest
@testable import FamilyTreeCore

final class ValidationTests: XCTestCase {
    private func family() -> FamilyProject {
        FamilyProject(people: [Person(givenName: "Анна"), Person(givenName: "Борис"), Person(givenName: "Вера"), Person(givenName: "Глеб")])
    }

    func testDemoIsDeterministicAndHasFourGenerations() throws {
        let project = FamilyProject.demo
        XCTAssertEqual(project, FamilyProject.demo)
        XCTAssertEqual(project.people.count, 12)
        XCTAssertEqual(project.person(project.rootPersonID)?.givenName, "Елена")
        XCTAssertEqual(project.person(project.rootPersonID)?.birthDate, "1988-06-12")
        XCTAssertNoThrow(try ProjectValidation.validate(project))
        let root = try XCTUnwrap(project.rootPersonID)
        XCTAssertEqual(project.parents(of: root).count, 2)
        XCTAssertEqual(project.children(of: root).count, 2)
        XCTAssertEqual(project.parents(of: project.parents(of: root)[0].id).count, 2)
    }

    func testRejectsSelfLinksAndMissingPeople() throws {
        let project = family()
        let id = project.people[0].id
        XCTAssertThrowsError(try ProjectValidation.validateRelationship(Relationship(fromID: id, toID: id, kind: .partner), in: project)) { error in
            XCTAssertEqual(error as? ProjectValidationError, .selfRelationship)
        }
        XCTAssertThrowsError(try ProjectValidation.validateRelationship(Relationship(fromID: id, toID: UUID(), kind: .parent), in: project)) { error in
            XCTAssertEqual(error as? ProjectValidationError, .missingPerson)
        }
    }

    func testRejectsReversedDuplicatePartnershipAndAllowsUpdatingExistingLink() throws {
        var project = family()
        let first = Relationship(fromID: project.people[0].id, toID: project.people[1].id, kind: .partner)
        project.relationships = [first]
        let duplicate = Relationship(fromID: first.toID, toID: first.fromID, kind: .partner)
        XCTAssertThrowsError(try ProjectValidation.validateRelationship(duplicate, in: project)) { error in
            XCTAssertEqual(error as? ProjectValidationError, .duplicateRelationship)
        }
        XCTAssertNoThrow(try ProjectValidation.validateRelationship(first, in: project))
        project.relationships.append(duplicate)
        XCTAssertThrowsError(try ProjectValidation.validate(project))
    }

    func testRejectsAncestryCycleAcrossBiologicalAndAdoptiveLinks() throws {
        var project = family()
        let ids = project.people.map(\.id)
        project.relationships = [Relationship(fromID: ids[0], toID: ids[1], kind: .parent), Relationship(fromID: ids[1], toID: ids[2], kind: .adoptiveParent)]
        let cycle = Relationship(fromID: ids[2], toID: ids[0], kind: .parent)
        XCTAssertThrowsError(try ProjectValidation.validateRelationship(cycle, in: project)) { error in
            XCTAssertEqual(error as? ProjectValidationError, .ancestryCycle)
        }
        project.relationships.append(cycle)
        XCTAssertThrowsError(try ProjectValidation.validate(project)) { error in
            XCTAssertEqual(error as? ProjectValidationError, .ancestryCycle)
        }
    }

    func testSharedAncestorsAndMultiplePartnershipsAreValid() throws {
        var project = family()
        let ids = project.people.map(\.id)
        project.relationships = [
            Relationship(fromID: ids[0], toID: ids[1], kind: .parent),
            Relationship(fromID: ids[0], toID: ids[2], kind: .parent),
            Relationship(fromID: ids[1], toID: ids[3], kind: .parent),
            Relationship(fromID: ids[2], toID: ids[3], kind: .adoptiveParent),
            Relationship(fromID: ids[0], toID: ids[1], kind: .partner),
            Relationship(fromID: ids[0], toID: ids[2], kind: .partner)
        ]
        XCTAssertNoThrow(try ProjectValidation.validate(project))
    }

    func testRejectsDuplicateIdentifiersAndMissingRoot() throws {
        var project = family()
        project.people.append(project.people[0])
        XCTAssertThrowsError(try ProjectValidation.validate(project)) { error in
            XCTAssertEqual(error as? ProjectValidationError, .duplicateIdentifier("Люди"))
        }
        project.people.removeLast()
        project.rootPersonID = UUID()
        XCTAssertThrowsError(try ProjectValidation.validate(project)) { error in
            XCTAssertEqual(error as? ProjectValidationError, .missingRoot)
        }
    }

    func testRejectsOrphanedEventsAndMismatchedPhotos() throws {
        var project = family()
        project.events = [FamilyEvent(personID: UUID(), title: "Потерянное событие")]
        XCTAssertThrowsError(try ProjectValidation.validate(project)) { error in
            XCTAssertEqual(error as? ProjectValidationError, .missingPerson)
        }
        project.events = []
        let image = Attachment(personID: project.people[0].id, filename: "photo.png", mimeType: "image/png", data: Data([1, 2, 3]))
        project.attachments = [image]
        project.people[1].photoID = image.id
        XCTAssertThrowsError(try ProjectValidation.validate(project)) { error in
            XCTAssertEqual(error as? ProjectValidationError, .invalidPhoto)
        }
    }
}
