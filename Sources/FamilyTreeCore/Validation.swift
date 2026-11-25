import Foundation

public enum ProjectValidationError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case duplicateIdentifier(String)
    case missingPerson
    case selfRelationship
    case duplicateRelationship
    case ancestryCycle
    case missingRoot
    case invalidPhoto
    case invalidTimestamp

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Версия файла \(version) не поддерживается этим приложением."
        case .duplicateIdentifier(let collection): return "В разделе «\(collection)» повторяется идентификатор записи."
        case .missingPerson: return "Связь, событие или вложение ссылается на отсутствующего человека."
        case .selfRelationship: return "Нельзя связать человека с самим собой."
        case .duplicateRelationship: return "Такая семейная связь уже существует."
        case .ancestryCycle: return "Эта связь делает человека собственным предком."
        case .missingRoot: return "Главный человек дерева отсутствует в проекте."
        case .invalidPhoto: return "Фотография человека отсутствует или принадлежит другой карточке."
        case .invalidTimestamp: return "Время создания или изменения проекта повреждено."
        }
    }
}

public enum ProjectValidation {
    public static func validate(_ project: FamilyProject) throws {
        guard project.formatVersion == FamilyProject.currentFormatVersion else {
            throw ProjectValidationError.unsupportedVersion(project.formatVersion)
        }
        guard project.createdAt.timeIntervalSince1970.isFinite,
              project.modifiedAt.timeIntervalSince1970.isFinite else {
            throw ProjectValidationError.invalidTimestamp
        }
        try checkIdentifiers(project.people.map(\.id), collection: "Люди")
        try checkIdentifiers(project.relationships.map(\.id), collection: "Связи")
        try checkIdentifiers(project.events.map(\.id), collection: "События")
        try checkIdentifiers(project.attachments.map(\.id), collection: "Вложения")
        let people = Set(project.people.map(\.id))
        if let root = project.rootPersonID, !people.contains(root) { throw ProjectValidationError.missingRoot }
        if project.events.contains(where: { !people.contains($0.personID) }) ||
            project.attachments.contains(where: { !people.contains($0.personID) }) {
            throw ProjectValidationError.missingPerson
        }
        let attachments = Dictionary(uniqueKeysWithValues: project.attachments.map { ($0.id, $0) })
        for person in project.people {
            if let photoID = person.photoID, attachments[photoID]?.personID != person.id {
                throw ProjectValidationError.invalidPhoto
            }
        }
        var signatures = Set<String>()
        var descendants: [UUID: [UUID]] = [:]
        var incoming = Dictionary(uniqueKeysWithValues: people.map { ($0, 0) })
        for relationship in project.relationships {
            try validateEndpoints(relationship, people: people)
            guard signatures.insert(signature(relationship)).inserted else {
                throw ProjectValidationError.duplicateRelationship
            }
            if relationship.kind.isParent {
                descendants[relationship.fromID, default: []].append(relationship.toID)
                incoming[relationship.toID, default: 0] += 1
            }
        }
        // Kahn's algorithm avoids recursive stack growth for large imported trees.
        var queue = incoming.filter { $0.value == 0 }.map(\.key)
        var index = 0
        while index < queue.count {
            let personID = queue[index]
            index += 1
            for childID in descendants[personID, default: []] {
                incoming[childID, default: 0] -= 1
                if incoming[childID] == 0 { queue.append(childID) }
            }
        }
        guard queue.count == people.count else { throw ProjectValidationError.ancestryCycle }
    }

    /// Validates an insertion or replacement. An existing record with the same ID is replaced.
    public static func validateRelationship(_ relationship: Relationship, in project: FamilyProject) throws {
        try validateEndpoints(relationship, people: Set(project.people.map(\.id)))
        let others = project.relationships.filter { $0.id != relationship.id }
        guard !others.contains(where: { signature($0) == signature(relationship) }) else {
            throw ProjectValidationError.duplicateRelationship
        }
        guard relationship.kind.isParent else { return }
        var descendants: [UUID: [UUID]] = [:]
        for edge in others where edge.kind.isParent { descendants[edge.fromID, default: []].append(edge.toID) }
        var pending = [relationship.toID]
        var visited = Set<UUID>()
        while let personID = pending.popLast() {
            if personID == relationship.fromID { throw ProjectValidationError.ancestryCycle }
            if visited.insert(personID).inserted { pending.append(contentsOf: descendants[personID, default: []]) }
        }
    }

    private static func checkIdentifiers(_ identifiers: [UUID], collection: String) throws {
        guard Set(identifiers).count == identifiers.count else {
            throw ProjectValidationError.duplicateIdentifier(collection)
        }
    }

    private static func validateEndpoints(_ relationship: Relationship, people: Set<UUID>) throws {
        guard relationship.fromID != relationship.toID else { throw ProjectValidationError.selfRelationship }
        guard people.contains(relationship.fromID), people.contains(relationship.toID) else {
            throw ProjectValidationError.missingPerson
        }
    }

    private static func signature(_ relationship: Relationship) -> String {
        var ids = [relationship.fromID.uuidString, relationship.toID.uuidString]
        if relationship.kind == .partner { ids.sort() }
        return "\(relationship.kind.rawValue):\(ids[0]):\(ids[1])"
    }
}
