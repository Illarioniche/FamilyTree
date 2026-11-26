import Foundation

/// The relationship of a newly created person to the person whose card was opened.
/// These choices do not add new persisted relationship kinds to the document.
public enum RelativeCreationRole: String, CaseIterable, Identifiable, Sendable {
    case child, parent, sibling, partner, adoptiveParent, adoptedChild

    public var id: Self { self }
    public var title: String {
        switch self {
        case .child: return "Ребёнок"
        case .parent: return "Родитель"
        case .sibling: return "Брат или сестра"
        case .partner: return "Супруг или партнёр"
        case .adoptiveParent: return "Приёмный родитель"
        case .adoptedChild: return "Приёмный ребёнок"
        }
    }
}

public enum RelativeCreationError: LocalizedError, Equatable {
    case sameParents
    case missingSharedParents
    case unavailableSharedParent

    public var errorDescription: String? {
        switch self {
        case .sameParents:
            return "Вторым родителем должен быть другой человек."
        case .missingSharedParents:
            return "Чтобы добавить брата или сестру, укажите хотя бы одного общего родителя."
        case .unavailableSharedParent:
            return "Выбранный общий родитель больше не связан с этой карточкой. Проверьте список родителей."
        }
    }
}

/// An explicit, unsaved description of the links to create with one new person.
/// Suggestions are resolved in the form, never silently during saving. Grandparents,
/// cousins and other extended kinship remain derived from the existing parent links.
public struct RelativeCreationPlan: Equatable, Sendable {
    public var role: RelativeCreationRole
    public var relativeID: UUID
    public var secondParentID: UUID?
    public var sharedParentIDs: Set<UUID>

    public init(role: RelativeCreationRole, relativeID: UUID,
                secondParentID: UUID? = nil, sharedParentIDs: Set<UUID> = []) {
        self.role = role
        self.relativeID = relativeID
        self.secondParentID = secondParentID
        self.sharedParentIDs = sharedParentIDs
    }

    /// A unique partner is a suggestion, not evidence that every child is theirs.
    /// The form must show this choice and allow clearing or changing it.
    public static func suggestedSecondParentID(relativeTo id: UUID, in project: FamilyProject) -> UUID? {
        guard project.person(id) != nil else { return nil }
        let partners = Set(project.partners(of: id).map(\.id).filter { $0 != id })
        return partners.count == 1 ? partners.first : nil
    }

    /// Parent links available for an explicit shared-parent choice. Preserve each
    /// biological/adoptive kind, including documents with more than two parents.
    public static func availableParentLinks(relativeTo id: UUID, in project: FamilyProject) -> [Relationship] {
        guard project.person(id) != nil else { return [] }
        var seen = Set<RelationshipKey>()
        return project.relationships.filter {
            $0.kind.isParent && $0.toID == id && $0.fromID != id && project.person($0.fromID) != nil
                && seen.insert(RelationshipKey($0)).inserted
        }
    }

    /// `project` must already contain the new person. Return only new direct links;
    /// the caller applies them, the person and any photo as one validated mutation.
    /// Unused choices from other roles are ignored, so switching roles cannot create
    /// a hidden partnership or attach a partner to the anchor's existing children.
    public func plannedRelationships(for newPersonID: UUID, in project: FamilyProject) throws -> [Relationship] {
        guard newPersonID != relativeID else { throw ProjectValidationError.selfRelationship }
        guard project.person(newPersonID) != nil, project.person(relativeID) != nil else {
            throw ProjectValidationError.missingPerson
        }

        let candidates: [Relationship]
        switch role {
        case .child, .adoptedChild:
            if secondParentID == relativeID { throw RelativeCreationError.sameParents }
            let kind: RelationshipKind = role == .child ? .parent : .adoptiveParent
            candidates = ([relativeID] + (secondParentID.map { [$0] } ?? [])).map {
                Relationship(fromID: $0, toID: newPersonID, kind: kind)
            }
        case .parent, .adoptiveParent:
            candidates = [Relationship(fromID: newPersonID, toID: relativeID,
                                       kind: role == .parent ? .parent : .adoptiveParent)]
        case .partner:
            candidates = [Relationship(fromID: newPersonID, toID: relativeID, kind: .partner)]
        case .sibling:
            guard !sharedParentIDs.isEmpty else { throw RelativeCreationError.missingSharedParents }
            let available = Self.availableParentLinks(relativeTo: relativeID, in: project)
            guard sharedParentIDs.isSubset(of: Set(available.map(\.fromID))) else {
                throw RelativeCreationError.unavailableSharedParent
            }
            candidates = available.filter { sharedParentIDs.contains($0.fromID) }.map {
                Relationship(fromID: $0.fromID, toID: newPersonID, kind: $0.kind)
            }
        }

        var result: [Relationship] = []
        var staged = project
        var seen = Set(project.relationships.map(RelationshipKey.init))
        for relationship in candidates {
            guard relationship.fromID != relationship.toID else { throw ProjectValidationError.selfRelationship }
            guard project.person(relationship.fromID) != nil, project.person(relationship.toID) != nil else {
                throw ProjectValidationError.missingPerson
            }
            guard seen.insert(RelationshipKey(relationship)).inserted else { continue }
            try ProjectValidation.validateRelationship(relationship, in: staged)
            staged.relationships.append(relationship)
            result.append(relationship)
        }
        return result
    }
}

private struct RelationshipKey: Hashable {
    let fromID: UUID
    let toID: UUID
    let kind: RelationshipKind

    init(_ relationship: Relationship) {
        if relationship.kind == .partner && relationship.fromID.uuidString > relationship.toID.uuidString {
            fromID = relationship.toID
            toID = relationship.fromID
        } else {
            fromID = relationship.fromID
            toID = relationship.toID
        }
        kind = relationship.kind
    }
}
