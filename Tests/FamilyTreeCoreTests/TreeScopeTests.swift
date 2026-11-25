import XCTest
@testable import FamilyTreeCore

final class TreeScopeTests: XCTestCase {
    func testModesHaveFixedKinshipNamesAndCloseIsDefault() {
        XCTAssertEqual(TreeScopeMode.allCases, [.close, .relatives, .all])
        XCTAssertEqual(TreeScopeMode.allCases.map(\.title), ["Близкие", "Родственники", "Всё дерево"])
        let fixture = family()
        XCTAssertEqual(
            TreeScope.make(project: fixture.project, focusID: fixture.people[0].id),
            TreeScope.make(project: fixture.project, focusID: fixture.people[0].id, mode: .close)
        )
    }

    func testCloseIncludesExactlyParentsPartnersChildrenSiblingsAndGrandparents() {
        let fixture = family()
        let result = TreeScope.make(project: fixture.project, focusID: fixture.people[0].id)
        XCTAssertEqual(indices(result, in: fixture.people), closeIndices)
        XCTAssertEqual(result.totalPeopleCount, fixture.people.count)
        // Half siblings and adoptive parents/children/grandparents count equally.
        for index in [3, 6, 8, 9, 14] {
            XCTAssertTrue(result.project.people.contains { $0.id == fixture.people[index].id })
        }
        // Spouse's family, grandchildren, nieces, aunts and other people's partners do not.
        for index in [15, 16, 17, 18, 19, 20, 22, 34, 41, 42] {
            XCTAssertFalse(result.project.people.contains { $0.id == fixture.people[index].id })
        }
    }

    func testRelativesIncludesAuntsGrandparentSiblingsAndFirstAndSecondCousins() {
        let fixture = family()
        let result = TreeScope.make(project: fixture.project, focusID: fixture.people[0].id, mode: .relatives)
        XCTAssertEqual(indices(result, in: fixture.people), relativeIndices)
        XCTAssertTrue(closeIndices.isSubset(of: indices(result, in: fixture.people)))
        // Aunts and first cousins on both sides and through adoptive ancestry.
        for index in [20, 21, 38, 39, 45, 46] {
            XCTAssertTrue(result.project.people.contains { $0.id == fixture.people[index].id })
        }
        // Grandparent's sibling, the connecting parent, second cousin, and common great-grandparent.
        for index in [23, 25, 26, 24] {
            XCTAssertTrue(result.project.people.contains { $0.id == fixture.people[index].id })
        }
        // The common great-great-grandparent and branch reaching a third cousin are outside this scope.
        for index in [27, 28, 29, 30, 31] {
            XCTAssertFalse(result.project.people.contains { $0.id == fixture.people[index].id })
        }
    }

    func testRelativesDoesNotExpandSpousesOrDescendantsPastFocusGeneration() {
        let fixture = family()
        let result = TreeScope.make(project: fixture.project, focusID: fixture.people[0].id, mode: .relatives)
        for index in [15, 16, 17, 18, 19, 22, 32, 33, 34, 35, 36, 41, 42] {
            XCTAssertFalse(result.project.people.contains { $0.id == fixture.people[index].id })
        }
        XCTAssertTrue(result.project.people.contains { $0.id == fixture.people[5].id })
        XCTAssertTrue(result.project.people.contains { $0.id == fixture.people[6].id })
    }

    func testSpouseFamilyMemberIsIncludedWhenIndependentlyRelatedToFocus() {
        var fixture = family()
        fixture.project.relationships.append(Relationship(fromID: fixture.people[1].id, toID: fixture.people[16].id, kind: .parent))
        fixture.project.relationships.append(Relationship(fromID: fixture.people[0].id, toID: fixture.people[17].id, kind: .adoptiveParent))
        let result = TreeScope.make(project: fixture.project, focusID: fixture.people[0].id)
        XCTAssertEqual(indices(result, in: fixture.people), closeIndices.union([16, 17]))
        XCTAssertFalse(result.project.people.contains { $0.id == fixture.people[15].id })
    }

    func testAllModeRetainsEntireValidProjectIncludingDisconnectedPeople() {
        let fixture = family()
        let result = TreeScope.make(project: fixture.project, focusID: fixture.people[0].id, mode: .all)
        XCTAssertEqual(result.project, fixture.project)
        XCTAssertEqual(result.project.people.count, fixture.people.count)
        XCTAssertEqual(result.hiddenRelativeCounts, [:])
        XCTAssertEqual(result.focusID, fixture.people[0].id)
    }

    func testInvalidFocusFallsBackToRootThenFirstAndHandlesEmptyProject() {
        var fixture = family()
        let unknown = UUID()
        let fromRoot = TreeScope.make(project: fixture.project, focusID: unknown)
        XCTAssertEqual(fromRoot.focusID, fixture.people[0].id)
        fixture.project.rootPersonID = unknown
        let fromFirst = TreeScope.make(project: fixture.project, focusID: nil)
        XCTAssertEqual(fromFirst.focusID, fixture.people[0].id)
        for mode in TreeScopeMode.allCases {
            let empty = TreeScope.make(project: FamilyProject(), focusID: unknown, mode: mode)
            XCTAssertEqual(empty.focusID, nil)
            XCTAssertEqual(empty.project.people, [])
            XCTAssertEqual(empty.totalPeopleCount, 0)
            XCTAssertEqual(empty.hiddenRelativeCounts, [:])
        }
    }

    func testIsolatedFocusDoesNotRevealUnrelatedFamiliesAndDoesNotChangeRoot() {
        let fixture = family()
        let original = fixture.project
        for mode in [TreeScopeMode.close, .relatives] {
            let result = TreeScope.make(project: original, focusID: fixture.people[36].id, mode: mode)
            XCTAssertEqual(result.project.people.map(\.id), [fixture.people[36].id])
            XCTAssertEqual(result.project.rootPersonID, nil)
            XCTAssertEqual(result.focusID, fixture.people[36].id)
            XCTAssertEqual(result.hiddenRelativeCounts, [:])
        }
        XCTAssertEqual(fixture.project, original)
        XCTAssertEqual(original.rootPersonID, fixture.people[0].id)
    }

    func testHiddenCountsDeduplicateRelationshipKindsAndIgnoreDanglingLinks() {
        var fixture = family()
        fixture.project.relationships.append(Relationship(fromID: fixture.people[10].id, toID: fixture.people[20].id, kind: .adoptiveParent))
        fixture.project.relationships.append(Relationship(fromID: fixture.people[10].id, toID: UUID(), kind: .parent))
        fixture.project.relationships.append(Relationship(fromID: fixture.people[10].id, toID: fixture.people[10].id, kind: .partner))
        let result = TreeScope.make(project: fixture.project, focusID: fixture.people[0].id)
        XCTAssertEqual(indices(result, in: fixture.people), closeIndices)
        XCTAssertEqual(result.hiddenRelativeCounts[fixture.people[0].id], nil)
        XCTAssertEqual(result.hiddenRelativeCounts[fixture.people[4].id], 2)
        XCTAssertEqual(result.hiddenRelativeCounts[fixture.people[5].id], 1)
        XCTAssertEqual(result.hiddenRelativeCounts[fixture.people[7].id], 2)
        XCTAssertEqual(result.hiddenRelativeCounts[fixture.people[10].id], 3)
        XCTAssertFalse(result.project.relationships.contains { $0.fromID == $0.toID })
        let visibleIDs = Set(result.project.people.map(\.id))
        XCTAssertTrue(result.project.relationships.allSatisfy { visibleIDs.contains($0.fromID) && visibleIDs.contains($0.toID) })
    }

    func testProjectionPreservesOrderAndFiltersEventsAttachmentsAndPhotoReferences() throws {
        var fixture = family()
        let visiblePhoto = Attachment(personID: fixture.people[0].id, filename: "portrait.png", mimeType: "image/png", data: Data([1, 2, 3]))
        let hiddenPhoto = Attachment(personID: fixture.people[36].id, filename: "other.png", mimeType: "image/png", data: Data([4, 5, 6]))
        fixture.project.people[0].photoID = visiblePhoto.id
        fixture.project.people[36].photoID = hiddenPhoto.id
        fixture.project.attachments = [hiddenPhoto, visiblePhoto]
        fixture.project.events = [
            FamilyEvent(personID: fixture.people[36].id, title: "Скрытое событие"),
            FamilyEvent(personID: fixture.people[0].id, title: "Видимое событие")
        ]
        fixture.project.people.reverse()
        fixture.project.relationships.reverse()
        let original = fixture.project
        let visibleIDs = Set(closeIndices.map { fixture.people[$0].id })
        let result = TreeScope.make(project: original, focusID: fixture.people[0].id)
        XCTAssertEqual(result.project.people.map(\.id), original.people.filter { visibleIDs.contains($0.id) }.map(\.id))
        XCTAssertEqual(result.project.relationships, original.relationships.filter { visibleIDs.contains($0.fromID) && visibleIDs.contains($0.toID) })
        XCTAssertEqual(result.project.events.map(\.title), ["Видимое событие"])
        XCTAssertEqual(result.project.attachments, [visiblePhoto])
        XCTAssertEqual(result.project.person(fixture.people[0].id)?.photoID, visiblePhoto.id)
        XCTAssertEqual(result.project.createdAt, original.createdAt)
        XCTAssertEqual(result.project.modifiedAt, original.modifiedAt)
        XCTAssertEqual(fixture.project, original)
        XCTAssertNoThrow(try ProjectValidation.validate(result.project))
        XCTAssertEqual(TreeScope.make(project: original, focusID: fixture.people[0].id), result)

        let focusIndex = try XCTUnwrap(fixture.project.people.firstIndex { $0.id == fixture.people[0].id })
        fixture.project.people[focusIndex].photoID = hiddenPhoto.id
        let repairedPresentation = TreeScope.make(project: fixture.project, focusID: fixture.people[0].id)
        XCTAssertEqual(repairedPresentation.project.person(fixture.people[0].id)?.photoID, nil)
        XCTAssertEqual(fixture.project.people[focusIndex].photoID, hiddenPhoto.id)
    }

    func testCyclesTerminateAndRepeatedPeopleDoNotDuplicateMembership() {
        let people = (0..<8).map { Person(givenName: "Человек \($0)") }
        var links = (0..<7).map { Relationship(fromID: people[$0].id, toID: people[$0 + 1].id, kind: .parent) }
        links.append(Relationship(fromID: people[3].id, toID: people[0].id, kind: .parent))
        links.append(Relationship(fromID: people[3].id, toID: people[0].id, kind: .adoptiveParent))
        let project = FamilyProject(people: people + [people[0]], relationships: links)
        let close = TreeScope.make(project: project, focusID: people[0].id)
        XCTAssertEqual(indices(close, in: people), Set([0, 1, 2, 3, 4]))
        let relatives = TreeScope.make(project: project, focusID: people[0].id, mode: .relatives)
        XCTAssertEqual(indices(relatives, in: people), Set([0, 1, 2, 3, 4]))
        XCTAssertEqual(Set(relatives.project.people.map(\.id)).count, relatives.project.people.count)
        XCTAssertEqual(relatives.totalPeopleCount, 8)
    }

    func testRepeatedAncestorIncludesEveryPermittedKinshipRoleRegardlessOfRelationshipOrder() {
        let people = (0..<9).map { Person(givenName: "Человек \($0)") }
        // Person 3 is a grandparent via parent 7 and a great-grandparent via
        // parent 1 / grandparent 2. Person 6 is therefore a second cousin through
        // the longer line, even though the common ancestor also has a closer role.
        // Person 8 is a child of that cousin and remains outside the scope.
        let links: [(Int, Int)] = [(1, 0), (2, 1), (3, 2), (3, 7), (7, 0), (3, 4), (4, 5), (5, 6), (6, 8)]
        var project = FamilyProject(people: people, relationships: links.map {
            Relationship(fromID: people[$0.0].id, toID: people[$0.1].id, kind: .parent)
        })
        let result = TreeScope.make(project: project, focusID: people[0].id, mode: .relatives)
        XCTAssertEqual(indices(result, in: people), Set(0...7))
        project.relationships.reverse()
        XCTAssertEqual(indices(TreeScope.make(project: project, focusID: people[0].id, mode: .relatives), in: people), Set(0...7))
    }

    func testLargeFamilyIsNotSilentlyTruncated() {
        let parent = Person(givenName: "Родитель")
        let children = (0..<180).map { Person(givenName: "Ребёнок \($0)") }
        let project = FamilyProject(people: [parent] + children, relationships: children.map {
            Relationship(fromID: parent.id, toID: $0.id, kind: .parent)
        })
        for mode in [TreeScopeMode.close, .relatives] {
            let result = TreeScope.make(project: project, focusID: parent.id, mode: mode)
            XCTAssertEqual(result.project.people.count, 181)
            XCTAssertEqual(result.project.relationships.count, 180)
            XCTAssertEqual(result.hiddenRelativeCounts, [:])
        }
    }

    private var closeIndices: Set<Int> { Set(0...14).union([40]) }
    private var relativeIndices: Set<Int> {
        closeIndices.union([20, 21, 23, 24, 25, 26, 37, 38, 39, 43, 44, 45, 46])
    }

    private func family() -> (project: FamilyProject, people: [Person]) {
        // Entirely fictional, with both sides of the family and adoptive ancestry.
        // 0 focus; 1...3 parents; 4 partner; 5...6 children; 7...9 siblings;
        // 10...14 grandparents; 15...17 partner's family; 18 grandchild; 19 niece;
        // 20 aunt; 21 first cousin; 22 aunt's partner; 23 grandparent's sibling;
        // 24 common great-grandparent; 25 connecting parent; 26 second cousin;
        // 27 common great-great-grandparent; 28...30 connecting branch; 31 third cousin;
        // 32...33 cousins' children; 34 grandparent's other partner; 35 their parent;
        // 36 disconnected; 37 another great-grandparent; 38 aunt; 39 first cousin;
        // 40 focus's other partner; 41 their parent; 42 sibling's partner;
        // 43...44 paternal/adoptive great-grandparents; 45 adoptive aunt; 46 their child.
        let people = (0..<47).map { Person(givenName: "Человек \($0)") }
        let links: [(Int, Int, RelationshipKind)] = [
            (1, 0, .parent), (2, 0, .parent), (3, 0, .adoptiveParent),
            (0, 4, .partner), (0, 5, .parent), (0, 6, .adoptiveParent),
            (1, 7, .parent), (2, 7, .parent), (1, 8, .parent), (3, 9, .adoptiveParent),
            (10, 1, .parent), (11, 1, .parent), (12, 2, .parent), (13, 2, .parent), (14, 3, .adoptiveParent),
            (15, 4, .parent), (15, 16, .parent), (4, 17, .parent), (5, 18, .parent), (7, 19, .parent),
            (10, 20, .parent), (11, 20, .parent), (20, 21, .parent), (20, 22, .partner),
            (24, 10, .parent), (24, 23, .parent), (23, 25, .parent), (25, 26, .parent),
            (27, 24, .parent), (27, 28, .parent), (28, 29, .parent), (29, 30, .parent), (30, 31, .parent),
            (21, 32, .parent), (26, 33, .parent), (10, 34, .partner), (35, 34, .parent),
            (37, 11, .parent), (12, 38, .parent), (38, 39, .parent), (40, 0, .partner),
            (41, 40, .parent), (7, 42, .partner), (43, 12, .parent),
            (44, 14, .parent), (14, 45, .adoptiveParent), (45, 46, .parent)
        ]
        let project = FamilyProject(rootPersonID: people[0].id, people: people, relationships: links.map {
            Relationship(fromID: people[$0.0].id, toID: people[$0.1].id, kind: $0.2)
        })
        return (project, people)
    }

    private func indices(_ result: TreeScopeResult, in people: [Person]) -> Set<Int> {
        Set(result.project.people.compactMap { person in people.firstIndex { $0.id == person.id } })
    }
}
