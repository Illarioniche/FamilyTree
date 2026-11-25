import XCTest
@testable import FamilyTreeCore

final class TreeLayoutTests: XCTestCase {
    func testPartnersShareGenerationAndChildrenAreBelowBothParents() throws {
        let a = Person(givenName: "Анна", birthDate: "1960")
        let b = Person(givenName: "Борис", birthDate: "1958")
        let c = Person(givenName: "Вера", birthDate: "1986")
        let d = Person(givenName: "Глеб", birthDate: "1989")
        let project = FamilyProject(people: [a, b, c, d], relationships: [
            Relationship(fromID: a.id, toID: b.id, kind: .partner),
            Relationship(fromID: a.id, toID: c.id, kind: .parent),
            Relationship(fromID: b.id, toID: c.id, kind: .parent),
            Relationship(fromID: a.id, toID: d.id, kind: .adoptiveParent)
        ])
        let result = TreeLayout.make(project: project)
        let aNode = try XCTUnwrap(result.node(a.id)), bNode = try XCTUnwrap(result.node(b.id))
        let cNode = try XCTUnwrap(result.node(c.id)), dNode = try XCTUnwrap(result.node(d.id))
        XCTAssertEqual(aNode.generation, bNode.generation)
        XCTAssertEqual(aNode.y, bNode.y)
        XCTAssertGreaterThan(cNode.y, aNode.y)
        XCTAssertGreaterThan(dNode.y, aNode.y)
        XCTAssertEqual(result.generationCount, 2)
        XCTAssertEqual(result.connections.count, 4)
        assertNoOverlaps(result)
    }

    func testLayoutIsStableWhenInputCollectionsAreReordered() {
        let people = (0..<12).map { Person(givenName: "Человек \($0)", birthDate: "\(1940 + $0 * 4)") }
        let relations = [
            Relationship(fromID: people[0].id, toID: people[1].id, kind: .partner),
            Relationship(fromID: people[0].id, toID: people[3].id, kind: .parent),
            Relationship(fromID: people[1].id, toID: people[3].id, kind: .parent),
            Relationship(fromID: people[2].id, toID: people[4].id, kind: .parent),
            Relationship(fromID: people[3].id, toID: people[4].id, kind: .partner),
            Relationship(fromID: people[4].id, toID: people[8].id, kind: .parent),
            Relationship(fromID: people[5].id, toID: people[6].id, kind: .partner),
            Relationship(fromID: people[5].id, toID: people[7].id, kind: .partner),
            Relationship(fromID: people[6].id, toID: people[9].id, kind: .parent),
            Relationship(fromID: people[7].id, toID: people[10].id, kind: .parent)
        ]
        let first = FamilyProject(people: people, relationships: relations)
        let reordered = FamilyProject(people: people.reversed(), relationships: relations.reversed())
        let a = TreeLayout.make(project: first), b = TreeLayout.make(project: reordered)
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set(a.nodes.map(\.id)), Set(people.map(\.id)))
        assertNoOverlaps(a)
    }

    func testMultiplePartnershipsAndDisconnectedPeopleAppearOnce() throws {
        let people = (0..<8).map { Person(givenName: "Родственник \($0)") }
        let project = FamilyProject(people: people, relationships: [
            Relationship(fromID: people[0].id, toID: people[1].id, kind: .partner),
            Relationship(fromID: people[0].id, toID: people[2].id, kind: .partner),
            Relationship(fromID: people[0].id, toID: people[3].id, kind: .parent),
            Relationship(fromID: people[1].id, toID: people[3].id, kind: .parent),
            Relationship(fromID: people[0].id, toID: people[4].id, kind: .parent),
            Relationship(fromID: people[2].id, toID: people[4].id, kind: .parent),
            Relationship(fromID: people[5].id, toID: people[6].id, kind: .parent)
        ])
        let result = TreeLayout.make(project: project)
        XCTAssertEqual(result.nodes.count, people.count)
        XCTAssertEqual(Set(result.nodes.map(\.id)).count, people.count)
        XCTAssertNotNil(result.node(people[7].id))
        XCTAssertEqual(result.node(people[0].id)?.y, result.node(people[2].id)?.y)
        assertNoOverlaps(result)
    }

    func testSharedAncestorDoesNotDuplicatePerson() throws {
        let people = (0..<6).map { Person(givenName: "Предок \($0)") }
        let project = FamilyProject(people: people, relationships: [
            Relationship(fromID: people[0].id, toID: people[1].id, kind: .parent),
            Relationship(fromID: people[0].id, toID: people[2].id, kind: .parent),
            Relationship(fromID: people[1].id, toID: people[3].id, kind: .parent),
            Relationship(fromID: people[2].id, toID: people[4].id, kind: .parent),
            Relationship(fromID: people[3].id, toID: people[4].id, kind: .partner),
            Relationship(fromID: people[3].id, toID: people[5].id, kind: .parent),
            Relationship(fromID: people[4].id, toID: people[5].id, kind: .parent)
        ])
        let result = TreeLayout.make(project: project)
        XCTAssertEqual(result.nodes.filter { $0.id == people[0].id }.count, 1)
        XCTAssertEqual(result.generationCount, 4)
        assertNoOverlaps(result)
    }

    func testMalformedCyclesAndDanglingLinksRemainFinite() {
        let people = (0..<4).map { Person(givenName: "Человек \($0)") }
        let project = FamilyProject(people: people + [people[0]], relationships: [
            Relationship(fromID: people[0].id, toID: people[1].id, kind: .parent),
            Relationship(fromID: people[1].id, toID: people[2].id, kind: .parent),
            Relationship(fromID: people[2].id, toID: people[0].id, kind: .parent),
            Relationship(fromID: people[2].id, toID: people[3].id, kind: .parent),
            Relationship(fromID: people[3].id, toID: UUID(), kind: .parent),
            Relationship(fromID: people[0].id, toID: people[0].id, kind: .partner)
        ])
        let result = TreeLayout.make(project: project)
        XCTAssertEqual(result.nodes.count, people.count)
        XCTAssertEqual(result.connections.count, 4)
        XCTAssertTrue(result.width.isFinite && result.height.isFinite)
        XCTAssertGreaterThan(result.height, 0)
        XCTAssertEqual(result.generationCount, 2)
        assertNoOverlaps(result)
    }

    func testEmptyTreeAndDeepAncestry() {
        let empty = TreeLayout.make(project: FamilyProject())
        XCTAssertEqual(empty.generationCount, 0)
        XCTAssertTrue(empty.nodes.isEmpty)
        let people = (0..<500).map { Person(givenName: "\($0)") }
        let relations = (1..<people.count).map { Relationship(fromID: people[$0 - 1].id, toID: people[$0].id, kind: .parent) }
        let result = TreeLayout.make(project: FamilyProject(people: people, relationships: relations))
        XCTAssertEqual(result.generationCount, people.count)
        XCTAssertEqual(result.nodes.count, people.count)
        XCTAssertEqual(result.nodes.last?.generation, people.count - 1)
    }

    func testCoupleOrderFollowsTheirParentsInsteadOfBirthYears() throws {
        let leftParent = Person(givenName: "Левая ветвь", birthDate: "1940")
        let rightParent = Person(givenName: "Правая ветвь", birthDate: "1945")
        let leftChild = Person(givenName: "Младший супруг", birthDate: "1985")
        let rightChild = Person(givenName: "Старший супруг", birthDate: "1980")
        let tree = FamilyProject(people: [leftParent, rightParent, leftChild, rightChild], relationships: [
            Relationship(fromID: leftParent.id, toID: leftChild.id, kind: .parent),
            Relationship(fromID: rightParent.id, toID: rightChild.id, kind: .parent),
            Relationship(fromID: leftChild.id, toID: rightChild.id, kind: .partner)
        ])
        let layout = TreeLayout.make(project: tree)
        let parentDifference = try XCTUnwrap(layout.node(leftParent.id)).x - XCTUnwrap(layout.node(rightParent.id)).x
        let childDifference = try XCTUnwrap(layout.node(leftChild.id)).x - XCTUnwrap(layout.node(rightChild.id)).x
        XCTAssertGreaterThan(parentDifference * childDifference, 0, "The two ancestral links must not cross just because spouses have different birth years")
        assertNoOverlaps(layout)
    }

    func testDisconnectedFamiliesHaveSeparateHorizontalLanes() throws {
        let a = (0..<3).map { Person(givenName: "Семья А \($0)", birthDate: "\(1940 + $0 * 25)") }
        let b = (0..<3).map { Person(givenName: "Семья Б \($0)", birthDate: "\(1945 + $0 * 20)") }
        let tree = FamilyProject(people: [a[0], b[0], b[1], a[1], a[2], b[2]], relationships: [
            Relationship(fromID: a[0].id, toID: a[1].id, kind: .parent),
            Relationship(fromID: a[1].id, toID: a[2].id, kind: .parent),
            Relationship(fromID: b[0].id, toID: b[1].id, kind: .parent),
            Relationship(fromID: b[1].id, toID: b[2].id, kind: .parent)
        ])
        let layout = TreeLayout.make(project: tree)
        let aPositions = a.compactMap { layout.node($0.id)?.x }
        let bPositions = b.compactMap { layout.node($0.id)?.x }
        XCTAssertEqual(Set(aPositions).count, 1, "A simple ancestor chain should be vertical")
        XCTAssertEqual(Set(bPositions).count, 1)
        let aRight = try XCTUnwrap(aPositions.max()) + TreeLayout.cardWidth / 2
        let bLeft = try XCTUnwrap(bPositions.min()) - TreeLayout.cardWidth / 2
        XCTAssertGreaterThan(bLeft - aRight, TreeLayout.familyGap)
        assertNoOverlaps(layout)
        var reordered = tree
        reordered.people.reverse(); reordered.relationships.reverse()
        XCTAssertEqual(layout, TreeLayout.make(project: reordered))
    }

    private func assertNoOverlaps(_ result: TreeLayoutResult, file: StaticString = #filePath, line: UInt = #line) {
        for (index, node) in result.nodes.enumerated() {
            XCTAssertGreaterThanOrEqual(node.x - TreeLayout.cardWidth / 2, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(node.y - TreeLayout.cardHeight / 2, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(node.x + TreeLayout.cardWidth / 2, result.width, file: file, line: line)
            XCTAssertLessThanOrEqual(node.y + TreeLayout.cardHeight / 2, result.height, file: file, line: line)
            for other in result.nodes.dropFirst(index + 1) {
                let overlaps = abs(node.x - other.x) < TreeLayout.cardWidth && abs(node.y - other.y) < TreeLayout.cardHeight
                XCTAssertFalse(overlaps, "Cards \(node.id) and \(other.id) overlap", file: file, line: line)
            }
        }
    }
}
