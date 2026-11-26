import Foundation

/// Form-only state. Suggestions are never written into an existing card and never
/// replace a name field the user has edited, including an intentionally empty one.
public struct RelativePersonDraft {
    public enum NameField: Hashable { case familyName, givenName, patronymic }

    public var person: Person
    public private(set) var role: RelativeCreationRole
    public let relativeID: UUID?
    public let isNew: Bool
    public private(set) var secondParentID: UUID?
    public private(set) var sharedParentIDs: Set<UUID>
    private var editedNames = Set<NameField>()

    public init(person: Person, isNew: Bool, relativeID: UUID? = nil,
                role: RelativeCreationRole = .child, in project: FamilyProject) {
        self.person = person
        self.isNew = isNew
        self.relativeID = relativeID
        self.role = role
        if !person.familyName.isEmpty { editedNames.insert(.familyName) }
        if !person.givenName.isEmpty { editedNames.insert(.givenName) }
        if !person.patronymic.isEmpty { editedNames.insert(.patronymic) }
        if let relativeID {
            secondParentID = RelativeCreationPlan.suggestedSecondParentID(relativeTo: relativeID, in: project)
            sharedParentIDs = Set(RelativeCreationPlan.availableParentLinks(relativeTo: relativeID, in: project).map(\.fromID))
        } else {
            secondParentID = nil
            sharedParentIDs = []
        }
        refreshSuggestions(in: project)
    }

    public var creationPlan: RelativeCreationPlan? {
        guard isNew, let relativeID else { return nil }
        return RelativeCreationPlan(role: role, relativeID: relativeID,
                                    secondParentID: secondParentID, sharedParentIDs: sharedParentIDs)
    }

    /// Keep a temporarily hidden value in the draft when switching gender back.
    /// Existing imported data is preserved; a new male card has no maiden surname.
    public var personForSaving: Person {
        var saved = person
        if isNew && saved.gender == .male { saved.maidenName = "" }
        return saved
    }

    public var showsMaidenName: Bool { person.gender != .male }
    public var hasParentChoice: Bool { role == .child || role == .adoptedChild }

    public mutating func setName(_ value: String, field: NameField) {
        editedNames.insert(field)
        switch field {
        case .familyName: person.familyName = value
        case .givenName: person.givenName = value
        case .patronymic: person.patronymic = value
        }
    }

    public mutating func setGender(_ gender: Gender, in project: FamilyProject) {
        person.gender = gender
        refreshSuggestions(in: project)
    }

    public mutating func setRole(_ role: RelativeCreationRole, in project: FamilyProject) {
        self.role = role
        refreshSuggestions(in: project)
    }

    public mutating func setSecondParent(_ id: UUID?, in project: FamilyProject) {
        secondParentID = id
        refreshSuggestions(in: project)
    }

    public mutating func setSharedParent(_ id: UUID, selected: Bool, in project: FamilyProject) {
        if selected { sharedParentIDs.insert(id) } else { sharedParentIDs.remove(id) }
        refreshSuggestions(in: project)
    }

    public func suggestedFather(in project: FamilyProject) -> Person? {
        guard isNew, let relativeID else { return nil }
        let ids: Set<UUID>
        switch role {
        case .child:
            ids = Set([relativeID] + (secondParentID.map { [$0] } ?? []))
        case .sibling:
            ids = Set(RelativeCreationPlan.availableParentLinks(relativeTo: relativeID, in: project)
                .filter { $0.kind == .parent && sharedParentIDs.contains($0.fromID) }.map(\.fromID))
        default: return nil
        }
        let fathers = ids.compactMap { project.person($0) }.filter { $0.gender == .male }
        return fathers.count == 1 ? fathers.first : nil
    }

    public mutating func refreshSuggestions(in project: FamilyProject) {
        guard isNew, let relative = project.person(relativeID) else { return }
        var familyName = ""
        var givenName = ""
        var patronymic = ""
        switch role {
        case .child:
            let source = suggestedFather(in: project)?.familyName ?? relative.familyName
            familyName = RelativeNameSuggestions.familyName(source, gender: person.gender) ?? ""
            if let father = suggestedFather(in: project) {
                patronymic = RelativeNameSuggestions.patronymic(fatherGivenName: father.givenName, childGender: person.gender) ?? ""
            }
        case .parent, .sibling:
            let source = relative.maidenName.isEmpty ? relative.familyName : relative.maidenName
            familyName = RelativeNameSuggestions.familyName(source, gender: person.gender) ?? ""
            if role == .parent, person.gender == .male {
                let recordedPatronymic = relative.patronymic.trimmingCharacters(in: .whitespacesAndNewlines)
                let source = recordedPatronymic.isEmpty
                    ? RelativeNameSuggestions.splitGivenNames(relative.givenName)?.patronymic ?? ""
                    : recordedPatronymic
                givenName = RelativeNameSuggestions.fatherGivenName(childPatronymic: source) ?? ""
            } else if role == .sibling, let father = suggestedFather(in: project) {
                patronymic = RelativeNameSuggestions.patronymic(fatherGivenName: father.givenName, childGender: person.gender) ?? ""
            }
        case .partner, .adoptiveParent, .adoptedChild:
            break
        }
        if !editedNames.contains(.familyName) { person.familyName = familyName }
        if !editedNames.contains(.givenName) { person.givenName = givenName }
        if !editedNames.contains(.patronymic) { person.patronymic = patronymic }
    }
}
