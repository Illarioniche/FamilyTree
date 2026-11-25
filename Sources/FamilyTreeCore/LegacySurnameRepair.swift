import Foundation

/// A reviewable proposal for documents created by the earlier importer.
/// Original field snapshots prevent a stale review from overwriting later edits.
public struct SurnameRepairSuggestion: Identifiable, Equatable, Sendable {
    public var id: UUID { personID }
    public let personID: UUID
    public let personName: String
    public let previousFamilyName: String
    public let proposedFamilyName: String
    public let proposedMaidenName: String
    fileprivate let previousMaidenName: String
    fileprivate let previousBiography: String
    fileprivate let resultingBiography: String
}

/// Old versions retained NAME/_MARNM only as generated biography paragraphs.
/// These are suggestions, never an automatic migration: callers must present
/// them for review and apply only the proposals the user has selected.
public enum LegacySurnameRepair {
    private static let prefix = "Другое имя из GEDCOM: "

    public static func suggestions(in project: FamilyProject) -> [SurnameRepairSuggestion] {
        project.people.compactMap { suggestion(for: $0) }
    }

    /// Changes only the two surname fields and the exact processed paragraphs.
    /// The store owns project metadata, undo/redo and saving.
    @discardableResult
    public static func apply(_ suggestions: [SurnameRepairSuggestion], to project: inout FamilyProject) -> Int {
        var applied = 0
        for suggestion in suggestions {
            guard let index = project.people.firstIndex(where: { $0.id == suggestion.personID }),
                  project.people[index].familyName == suggestion.previousFamilyName,
                  project.people[index].maidenName == suggestion.previousMaidenName,
                  project.people[index].biography == suggestion.previousBiography else { continue }
            project.people[index].familyName = suggestion.proposedFamilyName
            project.people[index].maidenName = suggestion.proposedMaidenName
            project.people[index].biography = suggestion.resultingBiography
            applied += 1
        }
        return applied
    }

    private static func suggestion(for person: Person) -> SurnameRepairSuggestion? {
        let originalSurname = person.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originalSurname.isEmpty,
              person.maidenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let paragraphs = person.biography.components(separatedBy: "\n\n")
        let importedParagraphs = paragraphs.filter { $0.hasPrefix(prefix) }
        guard !importedParagraphs.isEmpty else { return nil }
        let names = importedParagraphs.map { String($0.dropFirst(prefix.count)) }
        // The legacy importer emitted this exact standalone form. Do not guess
        // from prose, multiline notes, complete names or several surname variants.
        guard names.allSatisfy(isUnambiguousSurname), Set(names).count == 1,
              let surname = names.first,
              surname.caseInsensitiveCompare(originalSurname) != .orderedSame else { return nil }
        return SurnameRepairSuggestion(
            personID: person.id, personName: person.fullName,
            previousFamilyName: person.familyName,
            proposedFamilyName: surname, proposedMaidenName: originalSurname,
            previousMaidenName: person.maidenName, previousBiography: person.biography,
            resultingBiography: paragraphs.filter { !importedParagraphs.contains($0) }.joined(separator: "\n\n")
        )
    }

    private static func isUnambiguousSurname(_ value: String) -> Bool {
        guard !value.isEmpty, value.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return false }
        let punctuation: Set<Unicode.Scalar> = ["-", "'", "’", "ʼ", "‐", "‑"]
        return value.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0) || punctuation.contains($0)
        }
    }
}
