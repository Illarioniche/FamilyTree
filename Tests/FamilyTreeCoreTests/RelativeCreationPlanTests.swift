import Foundation
import XCTest
@testable import FamilyTreeCore

final class RelativeCreationPlanTests: XCTestCase {
    func testTwoParentsConnectNewChildToBothFamiliesWithoutRedundantAncestryEdges() throws {
        let people = makePeople(10)
        var project = FamilyProject(rootPersonID: people[8].id, people: people, relationships: [
            edge(people, 0, 4), edge(people, 1, 4), edge(people, 2, 5), edge(people, 3, 5),
            edge(people, 4, 5, .partner), edge(people, 4, 6), edge(people, 5, 6),
            edge(people, 0, 7), edge(people, 1, 7), edge(people, 7, 9)
        ])
        let original = project
        let plan = RelativeCreationPlan(role: .child, relativeID: people[4].id, secondParentID: people[5].id)
        let additions = try plan.plannedRelationships(for: people[8].id, in: project)
        XCTAssertEqual(project, original, "Planning must not mutate the family document.")
        XCTAssertEqual(additions.count, 2)
        XCTAssertEqual(Set(additions.map(\.fromID)), Set([people[4].id, people[5].id]))
        XCTAssertTrue(additions.allSatisfy { $0.toID == people[8].id && $0.kind == .parent })
        project.relationships.append(contentsOf: additions)
        XCTAssertNoThrow(try ProjectValidation.validate(project))

        let close = TreeScope.make(project: project, focusID: people[8].id, mode: .close)
        XCTAssertEqual(Set(close.project.people.map(\.id)), Set((0...6).map { people[$0].id } + [people[8].id]))
        let relatives = TreeScope.make(project: project, focusID: people[8].id, mode: .relatives)
        XCTAssertTrue(relatives.project.people.contains { $0.id == people[7].id })
        XCTAssertTrue(relatives.project.people.contains { $0.id == people[9].id })
        XCTAssertEqual(project.relationships.count, original.relationships.count + 2)
    }

    func testDefaultSecondParentRequiresExactlyOneDistinctExistingPartner() {
        let people = makePeople(3)
        var project = FamilyProject(people: people)
        XCTAssertEqual(RelativeCreationPlan.suggestedSecondParentID(relativeTo: people[0].id, in: project), nil)
        project.relationships = [edge(people, 1, 0, .partner)]
        XCTAssertEqual(RelativeCreationPlan.suggestedSecondParentID(relativeTo: people[0].id, in: project), people[1].id)
        project.relationships.append(edge(people, 0, 1, .partner))
        XCTAssertEqual(RelativeCreationPlan.suggestedSecondParentID(relativeTo: people[0].id, in: project), people[1].id)
        project.relationships.append(edge(people, 0, 2, .partner))
        XCTAssertEqual(RelativeCreationPlan.suggestedSecondParentID(relativeTo: people[0].id, in: project), nil)
        XCTAssertEqual(RelativeCreationPlan.suggestedSecondParentID(relativeTo: UUID(), in: project), nil)
    }

    func testClearingSecondParentKeepsSingleParentEvenWhenUniquePartnerExists() throws {
        let people = makePeople(3)
        let project = FamilyProject(people: people, relationships: [edge(people, 0, 1, .partner)])
        let additions = try RelativeCreationPlan(role: .child, relativeID: people[0].id)
            .plannedRelationships(for: people[2].id, in: project)
        XCTAssertEqual(additions.count, 1)
        XCTAssertEqual(additions.first?.fromID, people[0].id)
        XCTAssertEqual(additions.first?.toID, people[2].id)
    }

    func testExplicitSecondParentWorksAmongMultiplePartnersOrWithoutPartnership() throws {
        let people = makePeople(5)
        let project = FamilyProject(people: people, relationships: [
            edge(people, 0, 1, .partner), edge(people, 2, 0, .partner)
        ])
        for selected in [people[1].id, people[2].id, people[3].id] {
            let additions = try RelativeCreationPlan(role: .child, relativeID: people[0].id, secondParentID: selected)
                .plannedRelationships(for: people[4].id, in: project)
            XCTAssertEqual(Set(additions.map(\.fromID)), Set([people[0].id, selected]))
            XCTAssertTrue(additions.allSatisfy { $0.kind == .parent })
        }
    }

    func testAdoptedChildCreatesAdoptiveLinksForSelectedParents() throws {
        let people = makePeople(3)
        var project = FamilyProject(people: people)
        let additions = try RelativeCreationPlan(role: .adoptedChild, relativeID: people[0].id, secondParentID: people[1].id)
            .plannedRelationships(for: people[2].id, in: project)
        XCTAssertEqual(additions.count, 2)
        XCTAssertTrue(additions.allSatisfy { $0.kind == .adoptiveParent && $0.toID == people[2].id })
        project.relationships.append(contentsOf: additions)
        XCTAssertNoThrow(try ProjectValidation.validate(project))
    }

    func testSiblingUsesOnlyChosenParentsAndPreservesAdoptiveKind() throws {
        let people = makePeople(6)
        let project = FamilyProject(people: people, relationships: [
            edge(people, 0, 4), edge(people, 1, 4), edge(people, 2, 4, .adoptiveParent),
            edge(people, 3, 4, .adoptiveParent)
        ])
        let available = RelativeCreationPlan.availableParentLinks(relativeTo: people[4].id, in: project)
        XCTAssertEqual(available, project.relationships)
        let chosen = Set([people[0].id, people[2].id])
        let additions = try RelativeCreationPlan(role: .sibling, relativeID: people[4].id, sharedParentIDs: chosen)
            .plannedRelationships(for: people[5].id, in: project)
        XCTAssertEqual(additions.count, 2)
        XCTAssertEqual(Set(additions.map(\.fromID)), chosen)
        XCTAssertEqual(additions.first { $0.fromID == people[0].id }?.kind, .parent)
        XCTAssertEqual(additions.first { $0.fromID == people[2].id }?.kind, .adoptiveParent)
        XCTAssertTrue(additions.allSatisfy { $0.toID == people[5].id })
    }

    func testSiblingWithNoKnownOrChosenParentCannotCreateAnUnconnectedPerson() throws {
        let people = makePeople(3)
        var project = FamilyProject(people: people)
        XCTAssertEqual(RelativeCreationPlan.availableParentLinks(relativeTo: people[0].id, in: project), [])
        XCTAssertThrowsError(try RelativeCreationPlan(role: .sibling, relativeID: people[0].id)
            .plannedRelationships(for: people[1].id, in: project)) { error in
                XCTAssertEqual(error as? RelativeCreationError, .missingSharedParents)
            }
        project.relationships = [edge(people, 2, 0)]
        XCTAssertThrowsError(try RelativeCreationPlan(role: .sibling, relativeID: people[0].id)
            .plannedRelationships(for: people[1].id, in: project)) { error in
                XCTAssertEqual(error as? RelativeCreationError, .missingSharedParents)
            }
        XCTAssertThrowsError(try RelativeCreationPlan(role: .sibling, relativeID: people[0].id,
                                                    sharedParentIDs: [people[1].id])
            .plannedRelationships(for: people[1].id, in: project)) { error in
                XCTAssertEqual(error as? RelativeCreationError, .unavailableSharedParent)
            }
    }

    func testParentAndPartnerChoicesDoNotInventOtherFamilyLinks() throws {
        let people = makePeople(4)
        let project = FamilyProject(people: people, relationships: [edge(people, 0, 1), edge(people, 0, 2, .partner)])
        for role in [RelativeCreationRole.parent, .adoptiveParent, .partner] {
            let additions = try RelativeCreationPlan(role: role, relativeID: people[0].id,
                                                    secondParentID: people[2].id, sharedParentIDs: [people[2].id])
                .plannedRelationships(for: people[3].id, in: project)
            XCTAssertEqual(additions.count, 1)
            XCTAssertEqual(additions.first?.fromID, people[3].id)
            XCTAssertEqual(additions.first?.toID, people[0].id)
            XCTAssertEqual(additions.first?.kind, role == .partner ? .partner : (role == .parent ? .parent : .adoptiveParent))
        }
    }

    func testRejectsMissingEndpointsSelfLinksAndRepeatedParentSelection() throws {
        let people = makePeople(3)
        let project = FamilyProject(people: people)
        let missing = UUID()
        let invalidPlans: [(RelativeCreationPlan, UUID, ProjectValidationError)] = [
            (.init(role: .child, relativeID: missing), people[2].id, .missingPerson),
            (.init(role: .child, relativeID: people[0].id), missing, .missingPerson),
            (.init(role: .child, relativeID: people[0].id, secondParentID: missing), people[2].id, .missingPerson),
            (.init(role: .parent, relativeID: people[0].id), people[0].id, .selfRelationship),
            (.init(role: .child, relativeID: people[0].id, secondParentID: people[2].id), people[2].id, .selfRelationship)
        ]
        for (plan, newPersonID, expected) in invalidPlans {
            XCTAssertThrowsError(try plan.plannedRelationships(for: newPersonID, in: project)) { error in
                XCTAssertEqual(error as? ProjectValidationError, expected)
            }
        }
        XCTAssertThrowsError(try RelativeCreationPlan(role: .child, relativeID: people[0].id, secondParentID: people[0].id)
            .plannedRelationships(for: people[2].id, in: project)) { error in
                XCTAssertEqual(error as? RelativeCreationError, .sameParents)
            }
    }

    func testInvalidSecondParentCannotLeaveFirstLinkApplied() throws {
        let people = makePeople(3)
        let project = FamilyProject(people: people, relationships: [edge(people, 2, 1, .adoptiveParent)])
        let original = project
        let plan = RelativeCreationPlan(role: .child, relativeID: people[0].id, secondParentID: people[1].id)
        XCTAssertThrowsError(try plan.plannedRelationships(for: people[2].id, in: project)) { error in
            XCTAssertEqual(error as? ProjectValidationError, .ancestryCycle)
        }
        XCTAssertEqual(project, original)
    }

    func testExistingSameAndReversedPartnerLinksAreNotDuplicated() throws {
        let people = makePeople(4)
        var project = FamilyProject(people: people, relationships: [edge(people, 0, 2), edge(people, 0, 1, .partner)])
        let additions = try RelativeCreationPlan(role: .child, relativeID: people[0].id, secondParentID: people[1].id)
            .plannedRelationships(for: people[2].id, in: project)
        XCTAssertEqual(additions.count, 1)
        XCTAssertEqual(additions.first?.fromID, people[1].id)
        project.relationships.append(contentsOf: additions)
        XCTAssertEqual(try RelativeCreationPlan(role: .child, relativeID: people[0].id, secondParentID: people[1].id)
            .plannedRelationships(for: people[2].id, in: project), [])
        XCTAssertEqual(try RelativeCreationPlan(role: .partner, relativeID: people[0].id)
            .plannedRelationships(for: people[1].id, in: project), [])
        XCTAssertNoThrow(try ProjectValidation.validate(project))
    }

    private func makePeople(_ count: Int) -> [Person] {
        (0..<count).map { Person(givenName: "Человек \($0)") }
    }

    private func edge(_ people: [Person], _ from: Int, _ to: Int, _ kind: RelationshipKind = .parent) -> Relationship {
        Relationship(fromID: people[from].id, toID: people[to].id, kind: kind)
    }
}
