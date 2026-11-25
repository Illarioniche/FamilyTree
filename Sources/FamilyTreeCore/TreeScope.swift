import Foundation

public enum TreeScopeMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case close, relatives, all

    public var id: Self { self }
    public var title: String {
        switch self {
        case .close: return "Близкие"
        case .relatives: return "Родственники"
        case .all: return "Всё дерево"
        }
    }
}

public struct TreeScopeResult: Equatable, Sendable {
    /// A presentation-only projection; do not save it over the original project.
    public let project: FamilyProject
    public let focusID: UUID?
    /// Number of unique immediate relatives outside this projection for each visible person.
    /// Zero counts are omitted.
    public let hiddenRelativeCounts: [UUID: Int]
    public let totalPeopleCount: Int
}

/// Selects a branch without modifying the underlying family document.
///
/// Close includes parents, partners, children, siblings and grandparents of the
/// focus. Both biological and adoptive parent links count, including half siblings.
/// Relatives adds connecting ancestors through great-grandparents and their
/// branches down to the focus generation: aunts/uncles, grandparent siblings,
/// first cousins and second cousins. Partners' families are not traversed.
/// All includes disconnected people. No mode imposes a node-count limit.
public enum TreeScope {
    public static func make(
        project: FamilyProject,
        focusID requestedFocus: UUID?,
        mode: TreeScopeMode = .close
    ) -> TreeScopeResult {
        var seen = Set<UUID>()
        let people = project.people.filter { seen.insert($0.id).inserted }
        let ids = Set(people.map(\.id))
        let focusID = requestedFocus.flatMap { ids.contains($0) ? $0 : nil }
            ?? project.rootPersonID.flatMap { ids.contains($0) ? $0 : nil }
            ?? people.first?.id

        let validRelationships = project.relationships.filter {
            $0.fromID != $0.toID && ids.contains($0.fromID) && ids.contains($0.toID)
        }
        var neighbors: [UUID: Set<UUID>] = [:]
        var parents: [UUID: Set<UUID>] = [:]
        var children: [UUID: Set<UUID>] = [:]
        var partners: [UUID: Set<UUID>] = [:]
        for relationship in validRelationships {
            neighbors[relationship.fromID, default: []].insert(relationship.toID)
            neighbors[relationship.toID, default: []].insert(relationship.fromID)
            if relationship.kind.isParent {
                children[relationship.fromID, default: []].insert(relationship.toID)
                parents[relationship.toID, default: []].insert(relationship.fromID)
            } else {
                partners[relationship.fromID, default: []].insert(relationship.toID)
                partners[relationship.toID, default: []].insert(relationship.fromID)
            }
        }

        var visible: Set<UUID> = []
        if mode == .all {
            visible = ids
        } else if let focusID {
            visible = [focusID]
            visible.formUnion(parents[focusID, default: []])
            visible.formUnion(partners[focusID, default: []])
            visible.formUnion(children[focusID, default: []])
            for parentID in parents[focusID, default: []] {
                visible.formUnion(children[parentID, default: []])
                visible.formUnion(parents[parentID, default: []])
            }
            if mode == .relatives {
                // The same ancestor can occur at different generations. Keep
                // every bounded path length so a closer role does not hide a
                // cousin reached through another branch of the family.
                var ancestors: Set<UUID> = [focusID]
                for distance in 1...3 {
                    var next = Set<UUID>()
                    for ancestorID in ancestors { next.formUnion(parents[ancestorID, default: []]) }
                    next.remove(focusID)
                    guard !next.isEmpty else { break }
                    for ancestorID in next {
                        visible.formUnion(distances(from: ancestorID, adjacency: children, maximum: distance).keys)
                    }
                    ancestors = next
                }
            }
        }

        var scoped = project
        scoped.people = people.filter { visible.contains($0.id) }
        scoped.relationships = validRelationships.filter {
            visible.contains($0.fromID) && visible.contains($0.toID)
        }
        scoped.events = project.events.filter { visible.contains($0.personID) }
        scoped.attachments = project.attachments.filter { visible.contains($0.personID) }
        if let root = scoped.rootPersonID, !visible.contains(root) { scoped.rootPersonID = nil }
        let attachmentOwners = scoped.attachments.reduce(into: [UUID: UUID]()) { result, attachment in
            if result[attachment.id] == nil { result[attachment.id] = attachment.personID }
        }
        for index in scoped.people.indices {
            if let photoID = scoped.people[index].photoID,
               attachmentOwners[photoID] != scoped.people[index].id {
                scoped.people[index].photoID = nil
            }
        }

        var hidden: [UUID: Int] = [:]
        for personID in visible {
            let count = neighbors[personID, default: []].subtracting(visible).count
            if count > 0 { hidden[personID] = count }
        }
        return TreeScopeResult(
            project: scoped,
            focusID: focusID,
            hiddenRelativeCounts: hidden,
            totalPeopleCount: people.count
        )
    }

    /// Descendant traversal records shortest distances and terminates on cycles.
    /// The ancestor traversal above separately preserves every depth up to three.
    private static func distances(
        from start: UUID,
        adjacency: [UUID: Set<UUID>],
        maximum: Int
    ) -> [UUID: Int] {
        var result = [start: 0]
        var frontier: Set<UUID> = [start]
        guard maximum > 0 else { return result }
        for distance in 1...maximum {
            var next = Set<UUID>()
            for personID in frontier {
                for neighborID in adjacency[personID, default: []] where result[neighborID] == nil {
                    result[neighborID] = distance
                    next.insert(neighborID)
                }
            }
            guard !next.isEmpty else { break }
            frontier = next
        }
        return result
    }
}
