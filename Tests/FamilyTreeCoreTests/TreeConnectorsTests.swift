import XCTest
@testable import FamilyTreeCore

final class TreeConnectorsTests: XCTestCase {
    func testCoupleAndThreeChildrenShareOneTrunkAndSiblingBar() throws {
        let nodes = [node(0, 283, 106), node(1, 497, 106), node(2, 140, 286), node(3, 390, 286), node(4, 640, 286)]
        let edges = [edge(0, 1, .partner)] + (2...4).flatMap { [edge(0, $0), edge(1, $0)] }
        let layout = layout(nodes, edges)
        let geometry = TreeConnectors.make(layout: layout)
        XCTAssertEqual(geometry.junctions.count, 1)
        XCTAssertEqual(geometry.junctions.first?.point, TreeConnectorPoint(x: 390, y: 106))
        XCTAssertEqual(geometry.strokes.filter { $0.id.hasSuffix(":trunk") }.count, 1)
        XCTAssertEqual(geometry.strokes.filter { $0.id.hasSuffix(":children") }.count, 1)
        XCTAssertEqual(geometry.strokes.filter { $0.id.contains(":child:") }.count, 3)
        XCTAssertEqual(geometry.strokes.count, 6, "One partner line + trunk + sibling bar + three drops replace six parent-child curves")
        XCTAssertEqual(layout.connections.count, 7, "Presentation grouping must not mutate stored relations")
        assertGeometry(geometry, avoids: nodes)
    }

    func testSingleParentHasOneTrunkForAllChildren() {
        let nodes = [node(0, 390, 106), node(1, 140, 286), node(2, 390, 286), node(3, 640, 286)]
        let geometry = TreeConnectors.make(layout: layout(nodes, [edge(0, 1), edge(0, 2), edge(0, 3)]))
        XCTAssertEqual(geometry.junctions.count, 1)
        XCTAssertEqual(geometry.junctions.first?.point, TreeConnectorPoint(x: 390, y: 158))
        XCTAssertEqual(geometry.strokes.filter { $0.id.hasSuffix(":trunk") }.count, 1)
        XCTAssertFalse(geometry.strokes.contains { $0.kind == .partner })
        assertGeometry(geometry, avoids: nodes)
    }

    func testDifferentUnionsOfSamePersonKeepSeparateFamilies() throws {
        let nodes = [node(0, 340, 106), node(1, 126, 106), node(2, 554, 106), node(3, 233, 286), node(4, 447, 286)]
        let geometry = TreeConnectors.make(layout: layout(nodes, [edge(0, 1, .partner), edge(0, 2, .partner),
            edge(0, 3), edge(1, 3), edge(0, 4), edge(2, 4)]))
        XCTAssertEqual(geometry.junctions.count, 2)
        XCTAssertEqual(Set(geometry.junctions.map(\.point)).count, 2)
        let first = try XCTUnwrap(geometry.strokes.first { $0.id.hasSuffix(":child:\(id(3).uuidString)") })
        XCTAssertEqual(Set(first.personIDs), Set([id(0), id(1), id(3)]))
        let second = try XCTUnwrap(geometry.strokes.first { $0.id.hasSuffix(":child:\(id(4).uuidString)") })
        XCTAssertEqual(Set(second.personIDs), Set([id(0), id(2), id(4)]))
        assertGeometry(geometry, avoids: nodes)
    }

    func testCoParentsWithoutPartnershipMeetBelowCards() throws {
        let nodes = [node(0, 230, 106), node(1, 550, 106), node(2, 390, 286)]
        let geometry = TreeConnectors.make(layout: layout(nodes, [edge(0, 2), edge(1, 2)]))
        XCTAssertFalse(geometry.strokes.contains { $0.kind == .partner })
        let junction = try XCTUnwrap(geometry.junctions.first)
        XCTAssertGreaterThan(junction.point.y, 158)
        XCTAssertEqual(geometry.strokes.filter { $0.id.contains(":input:") }.count, 2)
        XCTAssertEqual(geometry.strokes.filter { $0.id.hasSuffix(":parents") }.count, 1)
        assertGeometry(geometry, avoids: nodes)
    }

    func testAdoptedAndBiologicalSiblingsKeepTypedFamilyGroups() throws {
        let nodes = [node(0, 283, 106), node(1, 497, 106), node(2, 200, 286), node(3, 450, 286), node(4, 700, 286)]
        let geometry = TreeConnectors.make(layout: layout(nodes, [edge(0, 1, .partner), edge(0, 2), edge(1, 2),
            edge(0, 3, .adoptiveParent), edge(1, 3, .adoptiveParent), edge(0, 4), edge(1, 4, .adoptiveParent)]))
        XCTAssertEqual(geometry.junctions.count, 3)
        let biological = try XCTUnwrap(geometry.strokes.first { $0.id.hasSuffix(":child:\(id(2).uuidString)") })
        let adopted = try XCTUnwrap(geometry.strokes.first { $0.id.hasSuffix(":child:\(id(3).uuidString)") })
        XCTAssertFalse(biological.isDashed)
        XCTAssertTrue(adopted.isDashed)
        XCTAssertFalse(biological.personIDs.contains(id(3)))
        XCTAssertFalse(adopted.personIDs.contains(id(2)))
        let mixedInputs = geometry.strokes.filter { $0.id.contains(":input:") && $0.personIDs.contains(id(4)) }
        XCTAssertEqual(mixedInputs.count, 2)
        XCTAssertEqual(mixedInputs.filter(\.isDashed).count, 1, "Only the adoptive parent's input is dashed in a mixed family")
        assertGeometry(geometry, avoids: nodes)
    }

    func testNonadjacentPartnersRouteAboveInterveningPerson() {
        let nodes = [node(0, 146, 106), node(1, 360, 106), node(2, 574, 106), node(3, 360, 286)]
        let geometry = TreeConnectors.make(layout: layout(nodes, [edge(0, 2, .partner), edge(0, 3), edge(2, 3)]))
        let partner = geometry.strokes.first { $0.kind == .partner }
        XCTAssertNotNil(partner)
        XCTAssertTrue(partner?.points.contains { $0.y < 54 } == true)
        assertGeometry(geometry, avoids: nodes)
    }

    func testSkippedGenerationsAndReverseSameRowLinksAvoidCards() {
        let nodes = [node(0, 146, 106), node(1, 146, 286), node(2, 146, 466), node(3, 398, 466)]
        let geometry = TreeConnectors.make(layout: layout(nodes, [edge(0, 2), edge(2, 0), edge(2, 3)]))
        XCTAssertEqual(geometry.junctions.count, 2)
        XCTAssertEqual(geometry.strokes.filter { $0.id.contains(":child:") }.count, 3)
        assertGeometry(geometry, avoids: nodes)
    }

    func testCoParentsOnDifferentRowsRouteAroundInterveningCards() {
        let nodes = [node(0, 146, 106), node(1, 398, 286), node(2, 146, 286), node(3, 272, 466)]
        let geometry = TreeConnectors.make(layout: layout(nodes, [edge(0, 3), edge(1, 3)]))
        XCTAssertEqual(geometry.junctions.count, 1)
        XCTAssertEqual(geometry.strokes.filter { $0.id.contains(":input:") }.count, 2)
        assertGeometry(geometry, avoids: nodes)
    }

    func testOverlappingSiblingBarsOfManyFamiliesUseSeparateTracks() {
        let parents = (0..<7).map { node($0, 146 + Double($0) * 252, 106) }
        let children = (0..<7).map { node($0 + 7, 146 + Double(6 - $0) * 252, 286) }
        let edges = (0..<7).map { edge($0, $0 + 7) }
        let geometry = TreeConnectors.make(layout: layout(parents + children, edges))
        let bars = geometry.strokes.filter { $0.id.hasSuffix(":children") }
        XCTAssertEqual(bars.count, 6, "The centrally aligned family needs only its straight descent")
        XCTAssertEqual(Set(bars.compactMap { $0.points.first?.y }).count, bars.count,
                       "Overlapping sibling buses must not merge after the fifth family")
        assertGeometry(geometry, avoids: parents + children)
    }

    func testDuplicateRelationsAndReorderedInputProduceStableGeometry() {
        let nodes = [node(0, 283, 106), node(1, 497, 106), node(2, 390, 286)]
        let edges = [edge(0, 1, .partner), edge(0, 2), edge(1, 2)]
        let first = TreeConnectors.make(layout: layout(nodes, edges))
        let reordered = TreeConnectors.make(layout: layout(Array(nodes.reversed()), Array(edges.reversed())))
        XCTAssertEqual(first, reordered)
        let duplicates = TreeConnectors.make(layout: layout(nodes, edges + [edge(1, 0, .partner), edge(0, 2), edge(1, 2)]))
        XCTAssertEqual(first, duplicates)
        assertGeometry(duplicates, avoids: nodes)
    }

    func testDanglingSelfAndNonfiniteNodesDoNotProduceGeometry() {
        let nodes = [node(0, 146, 106), node(1, .nan, 286)]
        let geometry = TreeConnectors.make(layout: layout(nodes, [edge(0, 0), edge(0, 1), edge(0, 2)]))
        XCTAssertTrue(geometry.strokes.isEmpty)
        XCTAssertTrue(geometry.junctions.isEmpty)
        XCTAssertEqual(TreeConnectors.make(layout: layout([], [])), TreeConnectorResult(strokes: [], junctions: []))
    }

    private func id(_ index: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))! }
    private func node(_ index: Int, _ x: Double, _ y: Double) -> TreeLayoutNode {
        TreeLayoutNode(id: id(index), x: x, y: y, generation: Int(y / 180))
    }
    private func edge(_ from: Int, _ to: Int, _ kind: RelationshipKind = .parent) -> TreeLayoutConnection {
        TreeLayoutConnection(id: UUID(), fromID: id(from), toID: id(to), kind: kind)
    }
    private func layout(_ nodes: [TreeLayoutNode], _ edges: [TreeLayoutConnection]) -> TreeLayoutResult {
        TreeLayoutResult(nodes: nodes, connections: edges, width: 1000, height: 700, generationCount: 4)
    }
    private func assertGeometry(_ geometry: TreeConnectorResult, avoids nodes: [TreeLayoutNode], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(geometry.strokes.map(\.id)).count, geometry.strokes.count, file: file, line: line)
        var segments = Set<String>()
        for stroke in geometry.strokes {
            XCTAssertGreaterThanOrEqual(stroke.points.count, 2, file: file, line: line)
            for (a, b) in zip(stroke.points, stroke.points.dropFirst()) {
                XCTAssertTrue(a.x.isFinite && a.y.isFinite && b.x.isFinite && b.y.isFinite, file: file, line: line)
                XCTAssertTrue(a.x == b.x || a.y == b.y, "All segments must be orthogonal", file: file, line: line)
                XCTAssertFalse(a == b, "No zero-length segment", file: file, line: line)
                let key = ["\(a.x),\(a.y)", "\(b.x),\(b.y)"].sorted().joined(separator: ":")
                XCTAssertTrue(segments.insert(key).inserted, "No duplicated physical segment: \(key)", file: file, line: line)
                for node in nodes {
                    let left = node.x - TreeLayout.cardWidth / 2, right = node.x + TreeLayout.cardWidth / 2
                    let top = node.y - TreeLayout.cardHeight / 2, bottom = node.y + TreeLayout.cardHeight / 2
                    let through = a.x == b.x
                        ? a.x > left && a.x < right && max(a.y, b.y) > top && min(a.y, b.y) < bottom
                        : a.y > top && a.y < bottom && max(a.x, b.x) > left && min(a.x, b.x) < right
                    XCTAssertFalse(through, "A connector must not cross a card", file: file, line: line)
                }
            }
        }
    }
}
