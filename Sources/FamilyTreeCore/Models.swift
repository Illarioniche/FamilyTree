import Foundation

public enum Gender: String, Codable, CaseIterable, Sendable {
    case male, female, unspecified
    public var title: String {
        switch self { case .male: return "Мужской"; case .female: return "Женский"; case .unspecified: return "Не указан" }
    }
}

public struct Person: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var givenName: String
    public var patronymic: String
    public var familyName: String
    public var maidenName: String
    public var gender: Gender
    public var birthDate: String
    public var deathDate: String
    public var isDeceased: Bool
    public var birthPlace: String
    public var occupation: String
    public var biography: String
    public var photoID: UUID?
    public var isFavorite: Bool

    public init(id: UUID = UUID(), givenName: String = "", patronymic: String = "", familyName: String = "", maidenName: String = "", gender: Gender = .unspecified, birthDate: String = "", deathDate: String = "", isDeceased: Bool = false, birthPlace: String = "", occupation: String = "", biography: String = "", photoID: UUID? = nil, isFavorite: Bool = false) {
        self.id = id; self.givenName = givenName; self.patronymic = patronymic
        self.familyName = familyName; self.maidenName = maidenName; self.gender = gender
        self.birthDate = birthDate; self.deathDate = deathDate; self.isDeceased = isDeceased
        self.birthPlace = birthPlace; self.occupation = occupation; self.biography = biography
        self.photoID = photoID; self.isFavorite = isFavorite
    }
    public var fullName: String {
        let value = [familyName, givenName, patronymic].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
        return value.isEmpty ? "Без имени" : value
    }
    public var shortName: String {
        let value = [familyName, givenName].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
        return value.isEmpty ? "Без имени" : value
    }
    public var initials: String {
        let parts = [givenName, familyName].filter { !$0.isEmpty }
        return parts.isEmpty ? "?" : parts.compactMap { $0.first.map(String.init) }.joined()
    }
    public var lifespan: String {
        let birth = GenealogyDate.display(birthDate)
        let death = GenealogyDate.display(deathDate)
        let hasBirth = !birth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasDeath = !death.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isDeceased || hasDeath { return "\(hasBirth ? birth : "?") — \(hasDeath ? death : "?")" }
        return hasBirth ? birth : "Даты не указаны"
    }
}

public enum RelationshipKind: String, Codable, CaseIterable, Sendable {
    case parent, adoptiveParent, partner
    public var title: String {
        switch self { case .parent: return "Родитель"; case .adoptiveParent: return "Приёмный родитель"; case .partner: return "Партнёр" }
    }
    public var isParent: Bool { self != .partner }
}

public struct Relationship: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var fromID: UUID
    public var toID: UUID
    public var kind: RelationshipKind
    public init(id: UUID = UUID(), fromID: UUID, toID: UUID, kind: RelationshipKind) {
        self.id = id; self.fromID = fromID; self.toID = toID; self.kind = kind
    }
}

public enum EventKind: String, Codable, CaseIterable, Sendable {
    case birth, marriage, residence, education, work, death, other
    public var title: String {
        switch self {
        case .birth: return "Рождение"; case .marriage: return "Свадьба"; case .residence: return "Переезд"
        case .education: return "Образование"; case .work: return "Работа"; case .death: return "Уход из жизни"; case .other: return "Событие"
        }
    }
    public var symbol: String {
        switch self {
        case .birth: return "sun.max"; case .marriage: return "heart"; case .residence: return "house"
        case .education: return "graduationcap"; case .work: return "briefcase"; case .death: return "leaf"; case .other: return "sparkles"
        }
    }
}

public struct FamilyEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var personID: UUID
    public var kind: EventKind
    public var title: String
    public var date: String
    public var place: String
    public var notes: String
    public init(id: UUID = UUID(), personID: UUID, kind: EventKind = .other, title: String = "", date: String = "", place: String = "", notes: String = "") {
        self.id = id; self.personID = personID; self.kind = kind; self.title = title
        self.date = date; self.place = place; self.notes = notes
    }
}

public struct Attachment: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var personID: UUID
    public var filename: String
    public var mimeType: String
    public var data: Data
    public var caption: String
    public init(id: UUID = UUID(), personID: UUID, filename: String, mimeType: String, data: Data, caption: String = "") {
        self.id = id; self.personID = personID; self.filename = filename
        self.mimeType = mimeType; self.data = data; self.caption = caption
    }
    public var isImage: Bool { mimeType.hasPrefix("image/") }
}

public struct FamilyProject: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    public var formatVersion: Int
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var rootPersonID: UUID?
    public var people: [Person]
    public var relationships: [Relationship]
    public var events: [FamilyEvent]
    public var attachments: [Attachment]
    public init(id: UUID = UUID(), title: String = "Моя семья", rootPersonID: UUID? = nil, people: [Person] = [], relationships: [Relationship] = [], events: [FamilyEvent] = [], attachments: [Attachment] = []) {
        self.formatVersion = Self.currentFormatVersion; self.id = id; self.title = title
        self.createdAt = Date(); self.modifiedAt = Date(); self.rootPersonID = rootPersonID
        self.people = people; self.relationships = relationships; self.events = events; self.attachments = attachments
    }
    public func person(_ id: UUID?) -> Person? { people.first { $0.id == id } }
    public func parents(of id: UUID) -> [Person] { relationships.filter { $0.kind.isParent && $0.toID == id }.compactMap { person($0.fromID) } }
    public func children(of id: UUID) -> [Person] { relationships.filter { $0.kind.isParent && $0.fromID == id }.compactMap { person($0.toID) } }
    public func partners(of id: UUID) -> [Person] { relationships.filter { $0.kind == .partner && ($0.fromID == id || $0.toID == id) }.compactMap { person($0.fromID == id ? $0.toID : $0.fromID) } }
    public mutating func removePerson(_ id: UUID) {
        people.removeAll { $0.id == id }; relationships.removeAll { $0.fromID == id || $0.toID == id }
        events.removeAll { $0.personID == id }; attachments.removeAll { $0.personID == id }
        if rootPersonID == id { rootPersonID = people.first?.id }
    }
}

/// Genealogical dates retain the original text, including uncertainty and incomplete dates.
public enum GenealogyDate {
    /// Formats only complete, valid dates for display. Incomplete dates, uncertainty,
    /// ranges and calendar-qualified dates remain exactly as entered; stored text
    /// and interchange/export formats are never modified by this projection.
    public static func display(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let date: (day: Int, month: Int, year: Int)?
        let iso = value.split(separator: "-", omittingEmptySubsequences: false)
        let dotted = value.split(separator: ".", omittingEmptySubsequences: false)
        let gedcom = value.split(whereSeparator: \.isWhitespace)
        if iso.count == 3, let year = number(iso[0], digits: 4...4),
           let month = number(iso[1], digits: 1...2), let day = number(iso[2], digits: 1...2) {
            date = (day, month, year)
        } else if dotted.count == 3, let day = number(dotted[0], digits: 1...2),
                  let month = number(dotted[1], digits: 1...2), let year = number(dotted[2], digits: 4...4) {
            date = (day, month, year)
        } else if gedcom.count == 3, let day = number(gedcom[0], digits: 1...2),
                  let month = months.firstIndex(of: gedcom[1].uppercased()),
                  let year = number(gedcom[2], digits: 1...4) {
            date = (day, month + 1, year)
        } else {
            date = nil
        }
        guard let date, (1...9999).contains(date.year), (1...12).contains(date.month) else { return text }
        let leap = date.year.isMultiple(of: 4) && (!date.year.isMultiple(of: 100) || date.year.isMultiple(of: 400))
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[date.month - 1]).contains(date.day) else { return text }
        return String(format: "%02d.%02d.%04d", date.day, date.month, date.year)
    }

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    private static func number(_ text: Substring, digits: ClosedRange<Int>) -> Int? {
        guard digits.contains(text.count), text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return Int(text)
    }

    public static func year(in text: String) -> Int? {
        let pattern = #"(?<!\d)\d{3,4}(?!\d)"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Int(text[range])
    }
}
