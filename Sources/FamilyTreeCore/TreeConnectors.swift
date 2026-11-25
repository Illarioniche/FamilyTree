import Foundation

public struct TreeConnectorPoint: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum TreeConnectorKind: String, Equatable, Sendable {
    case partner, parent, adoptiveParent
}

public struct TreeConnectorStroke: Identifiable, Equatable, Sendable {
    public var id: String
    public var points: [TreeConnectorPoint]
    public var kind: TreeConnectorKind
    public var personIDs: [UUID]
    public var isDashed: Bool { kind == .adoptiveParent }
}

public struct TreeConnectorJunction: Identifiable, Equatable, Sendable {
    public var id: String
    public var point: TreeConnectorPoint
    public var personIDs: [UUID]
}

public struct TreeConnectorResult: Equatable, Sendable {
    public var strokes: [TreeConnectorStroke]
    public var junctions: [TreeConnectorJunction]
}

/// Presentation geometry only: the original, individually typed relationships
/// remain in the project. A family bus represents an exact set of parents, never
/// an entire partnership component (which may contain several distinct unions).
public enum TreeConnectors {
    public static func make(layout: TreeLayoutResult) -> TreeConnectorResult {
        var nodes: [UUID: TreeLayoutNode] = [:]
        for node in layout.nodes where node.x.isFinite && node.y.isFinite {
            if nodes[node.id] == nil { nodes[node.id] = node }
        }
        let orderedNodes = nodes.values.sorted { $0.id.uuidString < $1.id.uuidString }
        let router = Router(nodes: orderedNodes)
        var strokes: [TreeConnectorStroke] = [], junctions: [TreeConnectorJunction] = []
        var activeFamily: String?
        var painted: [String: [ClosedRange<Double>]] = [:]
        func add(_ id: String, _ points: [TreeConnectorPoint], _ kind: TreeConnectorKind, _ people: [UUID]) {
            let clean = compact(points)
            guard clean.count > 1 else { return }
            guard let family = activeFamily else {
                strokes.append(TreeConnectorStroke(id: id, points: clean, kind: kind, personIDs: people))
                return
            }
            // Detours for several child rows can rejoin an existing part of the
            // same family trunk. Paint that part once. Never merge different
            // families or different relationship styles, even if they cross.
            var pieces: [[TreeConnectorPoint]] = [], current: [TreeConnectorPoint] = []
            for (a, b) in zip(clean, clean.dropFirst()) {
                let vertical = near(a.x, b.x)
                let av = vertical ? a.y : a.x, bv = vertical ? b.y : b.x
                let low = min(av, bv), high = max(av, bv)
                let track = "\(family):\(kind.rawValue):\(vertical ? "v" : "h"):\(vertical ? a.x : a.y)"
                var cursor = low, spans: [ClosedRange<Double>] = []
                for range in (painted[track] ?? []).sorted(by: { $0.lowerBound < $1.lowerBound }) {
                    guard range.upperBound > cursor, range.lowerBound < high else { continue }
                    if range.lowerBound > cursor { spans.append(cursor...min(range.lowerBound, high)) }
                    cursor = max(cursor, range.upperBound)
                    if cursor >= high { break }
                }
                if cursor < high { spans.append(cursor...high) }
                painted[track, default: []].append(low...high)
                if av > bv { spans.reverse() }
                for span in spans {
                    let from = av < bv ? span.lowerBound : span.upperBound
                    let to = av < bv ? span.upperBound : span.lowerBound
                    let p = vertical ? point(a.x, from) : point(from, a.y)
                    let q = vertical ? point(a.x, to) : point(to, a.y)
                    if current.last == p { current.append(q) }
                    else { if current.count > 1 { pieces.append(compact(current)) }; current = [p, q] }
                }
            }
            if current.count > 1 { pieces.append(compact(current)) }
            for (index, piece) in pieces.enumerated() {
                strokes.append(TreeConnectorStroke(id: index == 0 ? id : "\(id):piece:\(index)", points: piece, kind: kind, personIDs: people))
            }
        }
        let edges = layout.connections.filter { $0.fromID != $0.toID && nodes[$0.fromID] != nil && nodes[$0.toID] != nil }
        let partnerKeys = Set(edges.filter { $0.kind == .partner }.map { pairKey($0.fromID, $0.toID) })
        let partners = partnerKeys.sorted()
        var partnerJunctions: [String: TreeConnectorPoint] = [:]
        for (index, key) in partners.enumerated() {
            let ids = key.split(separator: ":").compactMap { UUID(uuidString: String($0)) }
            guard ids.count == 2, let a = nodes[ids[0]], let b = nodes[ids[1]] else { continue }
            let left = a.x < b.x ? a : b, right = a.x < b.x ? b : a
            let start = point(left.x + TreeLayout.cardWidth / 2, left.y)
            let end = point(right.x - TreeLayout.cardWidth / 2, right.y)
            if near(left.y, right.y), end.x > start.x, router.clear(start, end) {
                add("partner:\(key)", [start, end], .partner, ids)
                partnerJunctions[key] = point((start.x + end.x) / 2, start.y)
            } else {
                // A third card between partners must not get a line through it.
                let start = point(a.x + (a.x < b.x ? 28 : -28), a.y - TreeLayout.cardHeight / 2)
                let end = point(b.x + (b.x < a.x ? 28 : -28), b.y - TreeLayout.cardHeight / 2)
                let y = min(start.y, end.y) - 16 - Double(index % 3) * 7
                let first = point(start.x, y), last = point(end.x, y)
                let path = router.route(start, first) + router.route(first, last).dropFirst() + router.route(last, end).dropFirst()
                add("partner:\(key)", path, .partner, ids)
            }
        }

        var parentsByChild: [UUID: Set<Parent>] = [:]
        for edge in edges where edge.kind.isParent {
            parentsByChild[edge.toID, default: []].insert(Parent(id: edge.fromID, adopted: edge.kind == .adoptiveParent))
        }
        var families: [String: Family] = [:]
        for child in parentsByChild.keys.sorted(by: uuidOrder) {
            let parents = (parentsByChild[child] ?? []).sorted { $0.key < $1.key }
            let key = parents.map(\.key).joined(separator: ",")
            if families[key] == nil { families[key] = Family(parents: parents, children: []) }
            families[key]?.children.append(child)
        }
        let familyKeys = families.keys.sorted()
        // Separate attachment ports for different unions and typed parent sets.
        var memberships: [UUID: [String]] = [:]
        var pairMemberships: [String: [String]] = [:]
        for key in familyKeys {
            guard let family = families[key] else { continue }
            for parent in Set(family.parents.map(\.id)) { memberships[parent, default: []].append(key) }
            if family.parents.count == 2, family.parents[0].id != family.parents[1].id {
                pairMemberships[pairKey(family.parents[0].id, family.parents[1].id), default: []].append(key)
            }
        }
        var childTracks: [Double: [Track]] = [:], parentTracks: [Double: [Track]] = [:]
        for key in familyKeys {
            guard let family = families[key] else { continue }
            let parents = family.parents.compactMap { nodes[$0.id] }
            let children = family.children.compactMap { nodes[$0] }
            guard let firstX = parents.map(\.x).min(), let lastX = parents.map(\.x).max(),
                  let parentY = parents.map(\.y).max() else { continue }
            if parents.count > 1 { parentTracks[parentY, default: []].append(Track(key: key, left: firstX - 45, right: lastX + 45)) }
            for (y, row) in Dictionary(grouping: children, by: \.y) {
                let left = min(firstX - 45, row.map(\.x).min() ?? firstX)
                let right = max(lastX + 45, row.map(\.x).max() ?? lastX)
                childTracks[y, default: []].append(Track(key: key, left: left, right: right))
            }
        }
        let childLanes = trackOffsets(childTracks), parentLanes = trackOffsets(parentTracks)
        for key in familyKeys {
            guard let family = families[key] else { continue }
            let parents = family.parents.compactMap { parent in nodes[parent.id].map { (parent, $0) } }
            let children = family.children.compactMap { nodes[$0] }
            guard !parents.isEmpty, !children.isEmpty else { continue }
            let id = "family:\(key)"
            activeFamily = id
            let people = Array(Set(family.parents.map(\.id) + family.children)).sorted(by: uuidOrder)
            let homogeneous = Set(family.parents.map(\.adopted)).count == 1
            let kind: TreeConnectorKind = homogeneous && family.parents[0].adopted ? .adoptiveParent : .parent
            let source: TreeConnectorPoint
            let pair = parents.count == 2 ? pairKey(parents[0].0.id, parents[1].0.id) : ""
            if homogeneous, let partnerPoint = partnerJunctions[pair] {
                // The familiar marriage-bar junction: one descent for both parents.
                let keys = pairMemberships[pair] ?? [key]
                let index = keys.firstIndex(of: key) ?? 0
                let offset = centeredOffset(index, count: keys.count, spacing: 5, limit: 8)
                source = point(partnerPoint.x + offset, partnerPoint.y)
            } else if parents.count == 1 {
                let parent = parents[0].1
                let keys = memberships[parent.id] ?? [key]
                let offset = centeredOffset(keys.firstIndex(of: key) ?? 0, count: keys.count, spacing: 14, limit: 45)
                source = point(parent.x + offset, parent.y + TreeLayout.cardHeight / 2)
            } else {
                // Co-parenting does not imply partnership. Mixed biological and
                // adoptive inputs retain their own line styles before this bus.
                let parentY = parents.map { $0.1.y }.max() ?? 0
                let y = parentY + TreeLayout.cardHeight / 2 + 15 + (parentLanes[parentY]?[key] ?? 0)
                let ports = parents.map { parent, node -> (Parent, TreeConnectorPoint) in
                    let keys = memberships[parent.id] ?? [key]
                    let offset = centeredOffset(keys.firstIndex(of: key) ?? 0, count: keys.count, spacing: 14, limit: 45)
                    return (parent, point(node.x + offset, node.y + TreeLayout.cardHeight / 2))
                }
                let minX = ports.map { $0.1.x }.min() ?? 0, maxX = ports.map { $0.1.x }.max() ?? 0
                source = point((minX + maxX) / 2, y)
                for (parent, port) in ports {
                    add("\(id):input:\(parent.key)", router.route(port, point(port.x, y)), parent.adopted ? .adoptiveParent : .parent, people)
                }
                add("\(id):parents", router.route(point(minX, y), point(maxX, y)), kind, people)
            }
            junctions.append(TreeConnectorJunction(id: "\(id):junction", point: source, personIDs: people))
            let rows = Dictionary(grouping: children, by: \.y)
            var previous = source
            // Even unusual imports with children on several rows share a trunk;
            // each row gets its own sibling bar, in traversal order from parents.
            let rowOrder = rows.keys.sorted { a, b in
                let da = abs(a - source.y), db = abs(b - source.y)
                return near(da, db) ? a < b : da < db
            }
            for (rowIndex, rowY) in rowOrder.enumerated() {
                let row = (rows[rowY] ?? []).sorted { $0.x == $1.x ? uuidOrder($0.id, $1.id) : $0.x < $1.x }
                guard let first = row.first, let last = row.last else { continue }
                let y = rowY - TreeLayout.cardHeight / 2 - 22 - (childLanes[rowY]?[key] ?? 0)
                let junction = point(source.x, y)
                let rowID = "\(id):row:\(rowIndex)"
                add("\(rowID):trunk", router.route(previous, junction), kind, people)
                add("\(rowID):children", router.route(point(min(first.x, junction.x), y), point(max(last.x, junction.x), y)), kind, people)
                for child in row {
                    add("\(rowID):child:\(child.id.uuidString)", router.route(point(child.x, y), point(child.x, child.y - TreeLayout.cardHeight / 2)), kind, people)
                }
                previous = junction
            }
        }
        return TreeConnectorResult(strokes: strokes, junctions: junctions)
    }

    private struct Track { var key: String; var left: Double; var right: Double }
    private static func trackOffsets(_ rows: [Double: [Track]]) -> [Double: [String: Double]] {
        var result: [Double: [String: Double]] = [:]
        for (y, tracks) in rows {
            var occupied: [[Track]] = [], assignments: [String: Int] = [:]
            for track in tracks.sorted(by: { $0.key < $1.key }) {
                let lane = occupied.firstIndex { existing in
                    existing.allSatisfy { $0.right + 6 < track.left || track.right + 6 < $0.left }
                } ?? occupied.count
                if lane == occupied.count { occupied.append([]) }
                occupied[lane].append(track); assignments[track.key] = lane
            }
            // Child bars and parent buses occupy distinct parts of the gap.
            // Compress the spacing on crowded rows instead of reusing a track
            // and making unrelated families appear to share the same bus.
            let spacing = min(4, 12 / Double(max(1, occupied.count - 1)))
            result[y] = assignments.mapValues { Double($0) * spacing }
        }
        return result
    }
    private struct Parent: Hashable {
        var id: UUID
        var adopted: Bool
        var key: String { "\(id.uuidString):\(adopted ? "adoptive" : "parent")" }
    }
    private struct Family { var parents: [Parent]; var children: [UUID] }
    private static func uuidOrder(_ a: UUID, _ b: UUID) -> Bool { a.uuidString < b.uuidString }
    private static func pairKey(_ a: UUID, _ b: UUID) -> String { [a.uuidString, b.uuidString].sorted().joined(separator: ":") }
    private static func point(_ x: Double, _ y: Double) -> TreeConnectorPoint { TreeConnectorPoint(x: x, y: y) }
    private static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }
    private static func centeredOffset(_ index: Int, count: Int, spacing: Double, limit: Double) -> Double {
        guard count > 1 else { return 0 }
        let step = min(spacing, limit * 2 / Double(count - 1))
        return (Double(index) - Double(count - 1) / 2) * step
    }
    private static func compact(_ points: [TreeConnectorPoint]) -> [TreeConnectorPoint] {
        var result: [TreeConnectorPoint] = []
        for p in points {
            if result.last == p { continue }
            if result.count >= 2 {
                let a = result[result.count - 2], b = result[result.count - 1]
                if (near(a.x, b.x) && near(b.x, p.x) && (b.y - a.y) * (p.y - b.y) >= 0)
                    || (near(a.y, b.y) && near(b.y, p.y) && (b.x - a.x) * (p.x - b.x) >= 0) { result.removeLast() }
            }
            result.append(p)
        }
        return result
    }

    /// Small orthogonal router. Normal families use straight tracks in the row
    /// gap. Generation skips, cycles and nonadjacent partners take clear detours.
    private struct Router {
        struct Rect { var left: Double; var right: Double; var top: Double; var bottom: Double }
        var rects: [Rect]
        var xs: [Double]
        var ys: [Double]
        var clearRows: [Double]
        init(nodes: [TreeLayoutNode]) {
            rects = nodes.map { Rect(left: $0.x - TreeLayout.cardWidth / 2, right: $0.x + TreeLayout.cardWidth / 2,
                                    top: $0.y - TreeLayout.cardHeight / 2, bottom: $0.y + TreeLayout.cardHeight / 2) }
            xs = Array(Set(rects.flatMap { [$0.left - 12, $0.right + 12] })).sorted()
            ys = Array(Set(rects.flatMap { [$0.top - 12, $0.bottom + 12] })).sorted()
            let bounds = rects
            clearRows = ys.filter { y in !bounds.contains { y > $0.top && y < $0.bottom } }
        }
        func clear(_ a: TreeConnectorPoint, _ b: TreeConnectorPoint) -> Bool {
            if a == b { return true }
            if near(a.x, b.x) {
                return !rects.contains { a.x > $0.left + 0.001 && a.x < $0.right - 0.001
                    && max(a.y, b.y) > $0.top + 0.001 && min(a.y, b.y) < $0.bottom - 0.001 }
            }
            if near(a.y, b.y) {
                return !rects.contains { a.y > $0.top + 0.001 && a.y < $0.bottom - 0.001
                    && max(a.x, b.x) > $0.left + 0.001 && min(a.x, b.x) < $0.right - 0.001 }
            }
            return false
        }
        func route(_ start: TreeConnectorPoint, _ end: TreeConnectorPoint) -> [TreeConnectorPoint] {
            if start == end { return [start] }
            if clear(start, end) { return [start, end] }
            var best: [TreeConnectorPoint] = [], bestCost = Double.infinity
            func consider(_ raw: [TreeConnectorPoint]) {
                let path = compact(raw)
                let distance = zip(path, path.dropFirst()).reduce(0.0) { $0 + abs($1.0.x - $1.1.x) + abs($1.0.y - $1.1.y) }
                let cost = distance + Double(max(0, path.count - 2)) * 10
                guard cost < bestCost, zip(path, path.dropFirst()).allSatisfy({ clear($0.0, $0.1) }) else { return }
                best = path; bestCost = cost
            }
            consider([start, point(start.x, end.y), end])
            consider([start, point(end.x, start.y), end])
            for y in ys.sorted(by: { abs($0 - start.y) + abs($0 - end.y) < abs($1 - start.y) + abs($1 - end.y) }) {
                if abs(start.y - y) + abs(end.y - y) + abs(start.x - end.x) + 20 >= bestCost { continue }
                consider([start, point(start.x, y), point(end.x, y), end])
            }
            for x in xs.sorted(by: { abs($0 - start.x) + abs($0 - end.x) < abs($1 - start.x) + abs($1 - end.x) }) {
                if abs(start.x - x) + abs(end.x - x) + abs(start.y - end.y) + 20 >= bestCost { continue }
                consider([start, point(x, start.y), point(x, end.y), end])
            }
            if !best.isEmpty { return best }
            // Every row has a clear surrounding margin in TreeLayout. Routing
            // along the outer margin also handles backwards/same-row parentage.
            let startRows = clearRows.filter { clear(start, point(start.x, $0)) }
            let endRows = clearRows.filter { clear(end, point(end.x, $0)) }
            if let left = xs.first, let right = xs.last {
                for sy in startRows { for ey in endRows { for x in [left, right] {
                    consider([start, point(start.x, sy), point(x, sy), point(x, ey), point(end.x, ey), end])
                } } }
            }
            // Overlapping manually supplied cards can make a legal route
            // impossible. Omitting that stroke is safer than crossing a card.
            return best
        }
    }
}
