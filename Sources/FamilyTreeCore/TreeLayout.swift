import Foundation

/// Portable geometry; the layout engine has no dependency on AppKit or SwiftUI.
public struct TreeLayoutNode: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var x: Double
    public var y: Double
    public var generation: Int
}

public struct TreeLayoutConnection: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var fromID: UUID
    public var toID: UUID
    public var kind: RelationshipKind
}

public struct TreeLayoutResult: Equatable, Sendable {
    public var nodes: [TreeLayoutNode]
    public var connections: [TreeLayoutConnection]
    public var width: Double
    public var height: Double
    public var generationCount: Int
    public func node(_ id: UUID) -> TreeLayoutNode? { nodes.first { $0.id == id } }
}

public enum TreeLayout {
    public static let cardWidth: Double = 184
    public static let cardHeight: Double = 104
    public static let partnerGap: Double = 30
    public static let familyGap: Double = 68
    public static let generationGap: Double = 76
    public static let padding: Double = 54

    /// Produces one card per person. Partnership components share a row; ancestor
    /// ranks follow a condensed DAG, making invalid/cyclic imported data safe to show.
    public static func make(project: FamilyProject) -> TreeLayoutResult {
        let people = project.people.reduce(into: [UUID: Person]()) { result, person in
            if result[person.id] == nil { result[person.id] = person }
        }
        let ids = people.keys.sorted { $0.uuidString < $1.uuidString }
        guard !ids.isEmpty else {
            return TreeLayoutResult(nodes: [], connections: [], width: 500, height: 400, generationCount: 0)
        }
        let validRelations = project.relationships.filter {
            $0.fromID != $0.toID && people[$0.fromID] != nil && people[$0.toID] != nil
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        // Unrelated families get independent lanes. They must not be interleaved
        // simply because several people happen to share a generation or birth year.
        var neighbours: [UUID: Set<UUID>] = [:]
        for edge in validRelations {
            neighbours[edge.fromID, default: []].insert(edge.toID)
            neighbours[edge.toID, default: []].insert(edge.fromID)
        }
        var connected: [Set<UUID>] = []
        var discovered = Set<UUID>()
        for id in ids where !discovered.contains(id) {
            var pending = [id], family = Set<UUID>()
            while let next = pending.popLast() {
                guard discovered.insert(next).inserted else { continue }
                family.insert(next)
                pending.append(contentsOf: (neighbours[next] ?? []).sorted { $0.uuidString > $1.uuidString })
            }
            connected.append(family)
        }
        if connected.count > 1 {
            func familyKey(_ family: Set<UUID>) -> String {
                family.compactMap { people[$0]?.fullName }.sorted().first ?? ""
            }
            connected.sort {
                let a = familyKey($0), b = familyKey($1)
                return a == b ? $0.map(\.uuidString).sorted()[0] < $1.map(\.uuidString).sorted()[0] : a < b
            }
            var nodes: [TreeLayoutNode] = [], connections: [TreeLayoutConnection] = []
            var x = 0.0, height = 0.0, generations = 0
            for family in connected {
                let subset = FamilyProject(
                    people: ids.filter { family.contains($0) }.compactMap { people[$0] },
                    relationships: validRelations.filter { family.contains($0.fromID) && family.contains($0.toID) }
                )
                let layout = make(project: subset)
                nodes.append(contentsOf: layout.nodes.map { node in
                    var shifted = node; shifted.x += x; return shifted
                })
                connections.append(contentsOf: layout.connections)
                x += layout.width + familyGap
                height = max(height, layout.height)
                generations = max(generations, layout.generationCount)
            }
            return TreeLayoutResult(nodes: nodes, connections: connections.sorted { $0.id.uuidString < $1.id.uuidString },
                                    width: x - familyGap, height: height, generationCount: generations)
        }

        var leader = Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })
        func find(_ id: UUID) -> UUID {
            var current = id
            while let next = leader[current], next != current { current = next }
            return current
        }
        for relation in validRelations where relation.kind == .partner {
            let a = find(relation.fromID), b = find(relation.toID)
            if a != b {
                let first = a.uuidString < b.uuidString ? a : b
                leader[a] = first; leader[b] = first
            }
        }
        var members: [UUID: [UUID]] = [:]
        for id in ids { members[find(id), default: []].append(id) }
        let groups = members.keys.sorted { $0.uuidString < $1.uuidString }
        var personGroup: [UUID: UUID] = [:]
        for (group, list) in members { for id in list { personGroup[id] = group } }
        let sortPeople: (UUID, UUID) -> Bool = { left, right in
            guard let a = people[left], let b = people[right] else { return left.uuidString < right.uuidString }
            let aYear = GenealogyDate.year(in: a.birthDate) ?? Int.max
            let bYear = GenealogyDate.year(in: b.birthDate) ?? Int.max
            if aYear != bYear { return aYear < bYear }
            if a.fullName != b.fullName { return a.fullName < b.fullName }
            return left.uuidString < right.uuidString
        }
        for group in groups { members[group]?.sort(by: sortPeople) }
        var outgoing: [UUID: Set<UUID>] = [:]
        var incoming: [UUID: Set<UUID>] = [:]
        for relation in validRelations where relation.kind.isParent {
            guard let from = personGroup[relation.fromID], let to = personGroup[relation.toID], from != to else { continue }
            outgoing[from, default: []].insert(to)
            incoming[to, default: []].insert(from)
        }

        // Iterative Kosaraju traversal avoids recursion limits in very deep family trees.
        var visited = Set<UUID>(), finish: [UUID] = []
        for group in groups where !visited.contains(group) {
            var stack: [(UUID, Bool)] = [(group, false)]
            while let (id, expanded) = stack.popLast() {
                if expanded { finish.append(id); continue }
                guard visited.insert(id).inserted else { continue }
                stack.append((id, true))
                for child in (outgoing[id] ?? []).sorted(by: { $0.uuidString > $1.uuidString }) where !visited.contains(child) {
                    stack.append((child, false))
                }
            }
        }
        var component: [UUID: Int] = [:]
        var componentCount = 0
        for group in finish.reversed() where component[group] == nil {
            var stack = [group]
            while let id = stack.popLast() {
                guard component[id] == nil else { continue }
                component[id] = componentCount
                stack.append(contentsOf: (incoming[id] ?? []).sorted { $0.uuidString > $1.uuidString })
            }
            componentCount += 1
        }
        var componentEdges: [Int: Set<Int>] = [:]
        var indegree = Array(repeating: 0, count: componentCount)
        for group in groups {
            guard let source = component[group] else { continue }
            for child in outgoing[group] ?? [] {
                guard let target = component[child], source != target else { continue }
                if componentEdges[source, default: []].insert(target).inserted { indegree[target] += 1 }
            }
        }
        var ranks = Array(repeating: 0, count: componentCount)
        var queue = indegree.indices.filter { indegree[$0] == 0 }
        var cursor = 0
        while cursor < queue.count {
            let source = queue[cursor]; cursor += 1
            for target in (componentEdges[source] ?? []).sorted() {
                ranks[target] = max(ranks[target], ranks[source] + 1)
                indegree[target] -= 1
                if indegree[target] == 0 { queue.append(target) }
            }
        }
        let generationCount = (ranks.max() ?? 0) + 1
        var rows = Array(repeating: [UUID](), count: generationCount)
        for group in groups { rows[ranks[component[group] ?? 0]].append(group) }
        let groupWidth: (UUID) -> Double = { id in
            let count = members[id]?.count ?? 1
            return Double(count) * cardWidth + Double(max(0, count - 1)) * partnerGap
        }
        let stableGroupOrder: (UUID, UUID) -> Bool = { a, b in
            guard let firstA = members[a]?.first, let firstB = members[b]?.first else { return a.uuidString < b.uuidString }
            return sortPeople(firstA, firstB)
        }
        for index in rows.indices { rows[index].sort(by: stableGroupOrder) }
        let widestRow = rows.map { row in row.reduce(0) { $0 + groupWidth($1) } + Double(max(0, row.count - 1)) * familyGap }.max() ?? cardWidth
        var width = widestRow + padding * 2
        var centers: [UUID: Double] = [:]
        func positionRow(_ row: [UUID]) {
            let rowWidth = row.reduce(0) { $0 + groupWidth($1) } + Double(max(0, row.count - 1)) * familyGap
            var x = (width - rowWidth) / 2
            for id in row { centers[id] = x + groupWidth(id) / 2; x += groupWidth(id) + familyGap }
        }
        for row in rows { positionRow(row) }
        // Alternating barycentre sweeps reduce crossed links without overlapping cards.
        for sweep in 0..<4 {
            let indices = sweep.isMultiple(of: 2) ? Array(rows.indices) : Array(rows.indices.reversed())
            let adjacency = sweep.isMultiple(of: 2) ? incoming : outgoing
            for index in indices {
                let barycentre: (UUID) -> Double = { id in
                    let positions = (adjacency[id] ?? []).sorted { $0.uuidString < $1.uuidString }.compactMap { centers[$0] }
                    return positions.isEmpty ? (centers[id] ?? 0) : positions.reduce(0, +) / Double(positions.count)
                }
                let weights = Dictionary(uniqueKeysWithValues: rows[index].map { ($0, barycentre($0)) })
                rows[index].sort { a, b in
                    let aWeight = weights[a] ?? 0, bWeight = weights[b] ?? 0
                    return abs(aWeight - bWeight) > 0.001 ? aWeight < bWeight : stableGroupOrder(a, b)
                }
                positionRow(rows[index])
            }
        }
        func memberOffsets() -> [UUID: Double] {
            var result: [UUID: Double] = [:]
            for group in groups {
                let start = -groupWidth(group) / 2 + cardWidth / 2
                for (index, person) in (members[group] ?? []).enumerated() {
                    result[person] = start + Double(index) * (cardWidth + partnerGap)
                }
            }
            return result
        }
        // A couple's birth-year ordering can mirror its two ancestral branches.
        // Keep each person on the side of their own parents where that is known.
        let initialOffsets = memberOffsets()
        var parentAnchors: [UUID: [Double]] = [:]
        for edge in validRelations where edge.kind.isParent {
            guard let group = personGroup[edge.fromID], let center = centers[group] else { continue }
            parentAnchors[edge.toID, default: []].append(center + (initialOffsets[edge.fromID] ?? 0))
        }
        for group in groups {
            guard let couple = members[group], couple.count == 2 else { continue }
            let anchors = couple.map { id -> Double? in
                guard let positions = parentAnchors[id], !positions.isEmpty else { return nil }
                return positions.reduce(0, +) / Double(positions.count)
            }
            if let a = anchors[0], let b = anchors[1], abs(a - b) > 0.001 {
                if a > b { members[group] = couple.reversed() }
            } else if let a = anchors[0], anchors[1] == nil, a > (centers[group] ?? 0) + 0.001 {
                members[group] = couple.reversed()
            } else if let b = anchors[1], anchors[0] == nil, b < (centers[group] ?? 0) - 0.001 {
                members[group] = couple.reversed()
            }
        }

        let offsets = memberOffsets()
        var groupNeighbours: [UUID: [(group: UUID, offset: Double)]] = [:]
        for edge in validRelations where edge.kind.isParent {
            guard let parent = personGroup[edge.fromID], let child = personGroup[edge.toID], parent != child else { continue }
            let adjustment = (offsets[edge.toID] ?? 0) - (offsets[edge.fromID] ?? 0)
            groupNeighbours[parent, default: []].append((child, adjustment))
            groupNeighbours[child, default: []].append((parent, -adjustment))
        }
        // Project desired centres onto non-overlapping ordered intervals. Pool-adjacent-
        // violators is the least-squares solution after subtracting minimum spacings.
        // Sparse generations can now align with their families instead of being centred
        // independently across the widest row.
        func alignRow(_ row: [UUID]) {
            guard !row.isEmpty else { return }
            var spacing = [Double](repeating: 0, count: row.count)
            for index in 1..<row.count {
                spacing[index] = spacing[index - 1] + (groupWidth(row[index - 1]) + groupWidth(row[index])) / 2 + familyGap
            }
            struct Pool { var start: Int; var end: Int; var sum: Double; var weight: Double }
            var pools: [Pool] = []
            for (index, group) in row.enumerated() {
                let links = groupNeighbours[group] ?? []
                let targets = links.compactMap { link in centers[link.group].map { $0 + link.offset } }
                let desired = targets.isEmpty ? (centers[group] ?? 0) : targets.reduce(0, +) / Double(targets.count)
                let weight = Double(max(1, targets.count))
                pools.append(Pool(start: index, end: index, sum: (desired - spacing[index]) * weight, weight: weight))
                while pools.count >= 2 {
                    let a = pools[pools.count - 2], b = pools[pools.count - 1]
                    guard a.sum / a.weight > b.sum / b.weight else { break }
                    pools.removeLast(2)
                    pools.append(Pool(start: a.start, end: b.end, sum: a.sum + b.sum, weight: a.weight + b.weight))
                }
            }
            for pool in pools {
                for index in pool.start...pool.end { centers[row[index]] = pool.sum / pool.weight + spacing[index] }
            }
        }
        for sweep in 0..<10 {
            let indices = sweep.isMultiple(of: 2) ? Array(rows.indices) : Array(rows.indices.reversed())
            for index in indices { alignRow(rows[index]) }
        }
        let minX = groups.map { (centers[$0] ?? 0) - groupWidth($0) / 2 }.min() ?? 0
        let maxX = groups.map { (centers[$0] ?? 0) + groupWidth($0) / 2 }.max() ?? cardWidth
        for group in groups { centers[group, default: 0] += padding - minX }
        width = maxX - minX + padding * 2

        var nodes: [TreeLayoutNode] = []
        for (generation, row) in rows.enumerated() {
            for group in row {
                let start = (centers[group] ?? 0) - groupWidth(group) / 2 + cardWidth / 2
                for (offset, id) in (members[group] ?? []).enumerated() {
                    nodes.append(TreeLayoutNode(id: id, x: start + Double(offset) * (cardWidth + partnerGap), y: padding + cardHeight / 2 + Double(generation) * (cardHeight + generationGap), generation: generation))
                }
            }
        }
        return TreeLayoutResult(
            nodes: nodes,
            connections: validRelations.map { TreeLayoutConnection(id: $0.id, fromID: $0.fromID, toID: $0.toID, kind: $0.kind) },
            width: width,
            height: padding * 2 + Double(generationCount) * cardHeight + Double(generationCount - 1) * generationGap,
            generationCount: generationCount
        )
    }
}
