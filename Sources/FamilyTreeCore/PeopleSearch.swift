import Foundation

/// Searches words across the displayed and stored identity fields without
/// changing their spelling or the order of the supplied people.
public enum PeopleSearch {
    public static func filter(_ people: [Person], query: String) -> [Person] {
        let terms = normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return people }
        return people.filter { person in
            let fields = [person.fullName, person.maidenName, person.birthPlace,
                          person.birthDate, GenealogyDate.display(person.birthDate), person.occupation]
                .map(normalized)
            return terms.allSatisfy { term in fields.contains { $0.contains(term) } }
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
    }
}
