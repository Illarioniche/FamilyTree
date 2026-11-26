import Foundation

/// Editable suggestions for new cards, not a change to existing names.
/// Restrict patronymics to known full names: a suffix alone cannot identify a
/// person's naming tradition, and reversing an arbitrary patronymic is unsafe.
public enum RelativeNameSuggestions {
    public static func patronymic(fatherGivenName: String, childGender: Gender) -> String? {
        let givenName = splitGivenNames(fatherGivenName)?.givenName ?? fatherGivenName
        guard childGender != .unspecified,
              let entry = patronymics.first(where: { key($0.name) == key(givenName) }) else { return nil }
        let suggestion = childGender == .male ? entry.son : entry.daughter
        // Keep the source's е/ё spelling where the derived name retains it.
        return givenName.lowercased().contains("ё")
            ? suggestion : suggestion.replacingOccurrences(of: "ё", with: "е")
    }

    /// Some GEDCOM exporters put an entire given name and patronymic in GIVN.
    /// Read that shape only when there are exactly two words and the second is
    /// a known patronymic. This projection never rewrites the imported record.
    /// The first word may be any single Cyrillic name, including a woman's name;
    /// generating a child's patronymic still requires a known male given name.
    public static func splitGivenNames(_ value: String) -> (givenName: String, patronymic: String)? {
        let parts = value.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2 else { return nil }
        let givenName = String(parts[0]), patronymic = String(parts[1])
        guard givenName.unicodeScalars.allSatisfy({
            CharacterSet.letters.contains($0) && (0x0400...0x04FF).contains($0.value)
        }) else { return nil }
        let candidate = key(patronymic)
        guard patronymics.contains(where: { key($0.son) == candidate || key($0.daughter) == candidate }) else { return nil }
        return (givenName, patronymic)
    }

    public static func fatherGivenName(childPatronymic: String) -> String? {
        let value = key(childPatronymic)
        guard !value.isEmpty else { return nil }
        let candidates = Set(patronymics.filter { key($0.son) == value || key($0.daughter) == value }.map(\.name))
        guard candidates.count == 1 else { return nil }
        return candidates.first
    }

    /// Keep unfamiliar and compound surnames intact. In particular, an ending
    /// -ина does not prove that the corresponding masculine surname ends in -ин.
    /// Unknown gender deliberately retains the relative's original spelling.
    public static func familyName(_ source: String, gender: Gender) -> String? {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard gender != .unspecified, value.count > 3,
              value.unicodeScalars.allSatisfy({ (0x0400...0x04FF).contains($0.value) }) else { return value }
        let lower = value.lowercased()
        if let pair = adjectiveSurnames.first(where: { key($0.male) == key(value) || key($0.female) == key(value) }) {
            return matchingCase(gender == .male ? pair.male : pair.female, source: value)
        }
        if gender == .female {
            if lower.hasSuffix("ский") || lower.hasSuffix("цкий") {
                return replacingSuffix(of: value, count: 2, with: "ая")
            }
            if ["ов", "ев", "ёв"].contains(where: lower.hasSuffix) || knownINSurnames.contains(key(value)) {
                return replacingSuffix(of: value, count: 0, with: "а")
            }
        } else {
            if lower.hasSuffix("ская") || lower.hasSuffix("цкая") {
                return replacingSuffix(of: value, count: 2, with: "ий")
            }
            if ["ова", "ева", "ёва"].contains(where: lower.hasSuffix) {
                return String(value.dropLast())
            }
            if lower.hasSuffix("а"), knownINSurnames.contains(key(String(value.dropLast()))) {
                return String(value.dropLast())
            }
        }
        return value
    }

    private static func key(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    private static func matchingCase(_ value: String, source: String) -> String {
        if source == source.uppercased() { return value.uppercased() }
        if source == source.lowercased() { return value.lowercased() }
        return value
    }

    private static func replacingSuffix(of value: String, count: Int, with suffix: String) -> String {
        String(value.dropLast(count)) + (value == value.uppercased() ? suffix.uppercased() : suffix)
    }

    // Standard forms and exceptions follow the Russian names dictionary's
    // patronymic patterns: https://gramota.ru/biblioteka/slovari/slovar-russkih-imyon/ob-otchestvakh
    private struct Patronymic {
        let name: String
        let son: String
        let daughter: String
        init(_ name: String, _ son: String, _ daughter: String) {
            self.name = name; self.son = son; self.daughter = daughter
        }
    }

    private static let patronymics: [Patronymic] = {
        let regular = [
            "Александр", "Антон", "Артур", "Богдан", "Борис", "Вадим", "Валентин", "Виктор",
            "Владимир", "Владислав", "Вячеслав", "Герман", "Глеб", "Денис", "Егор", "Захар",
            "Иван", "Игнат", "Иосиф", "Кирилл", "Клим", "Константин", "Леонид", "Макар",
            "Максим", "Марк", "Мирон", "Михаил", "Назар", "Олег", "Платон",
            "Прохор", "Роберт", "Роман", "Ростислав", "Руслан", "Святослав", "Семён",
            "Станислав", "Степан", "Тарас", "Тимур", "Фёдор", "Филипп", "Эдуард", "Ярослав", "Артём"
        ].map { Patronymic($0, $0 + "ович", $0 + "овна") }
        return regular + [
            Patronymic("Алексей", "Алексеевич", "Алексеевна"),
            Patronymic("Анатолий", "Анатольевич", "Анатольевна"),
            Patronymic("Андрей", "Андреевич", "Андреевна"),
            Patronymic("Аркадий", "Аркадьевич", "Аркадьевна"),
            Patronymic("Арсений", "Арсеньевич", "Арсеньевна"),
            Patronymic("Артемий", "Артемьевич", "Артемьевна"),
            Patronymic("Валерий", "Валерьевич", "Валерьевна"),
            Patronymic("Василий", "Васильевич", "Васильевна"),
            Patronymic("Виталий", "Витальевич", "Витальевна"),
            Patronymic("Геннадий", "Геннадьевич", "Геннадьевна"),
            Patronymic("Георгий", "Георгиевич", "Георгиевна"),
            Patronymic("Григорий", "Григорьевич", "Григорьевна"),
            Patronymic("Даниил", "Даниилович", "Данииловна"),
            Patronymic("Данил", "Данилович", "Даниловна"),
            Patronymic("Данила", "Данилович", "Даниловна"),
            Patronymic("Дмитрий", "Дмитриевич", "Дмитриевна"),
            Patronymic("Евгений", "Евгеньевич", "Евгеньевна"),
            Patronymic("Игорь", "Игоревич", "Игоревна"),
            Patronymic("Илья", "Ильич", "Ильинична"),
            Patronymic("Ираклий", "Ираклиевич", "Ираклиевна"),
            Patronymic("Кузьма", "Кузьмич", "Кузьминична"),
            Patronymic("Лев", "Львович", "Львовна"),
            Patronymic("Лука", "Лукич", "Лукинична"),
            Patronymic("Матвей", "Матвеевич", "Матвеевна"),
            Patronymic("Никита", "Никитич", "Никитична"),
            Patronymic("Николай", "Николаевич", "Николаевна"),
            Patronymic("Павел", "Павлович", "Павловна"),
            Patronymic("Пётр", "Петрович", "Петровна"),
            Patronymic("Савва", "Саввич", "Саввична"),
            Patronymic("Сергей", "Сергеевич", "Сергеевна"),
            Patronymic("Тимофей", "Тимофеевич", "Тимофеевна"),
            Patronymic("Фома", "Фомич", "Фоминична"),
            Patronymic("Юрий", "Юрьевич", "Юрьевна"),
            Patronymic("Яков", "Яковлевич", "Яковлевна")
        ]
    }()

    private static let knownINSurnames: Set<String> = Set([
        "Пушкин", "Никитин", "Ильин", "Гагарин", "Лукин", "Фомин", "Мишин", "Рыбкин",
        "Калинин", "Кузьмин", "Савин", "Гришин", "Бунин", "Зайкин", "Ерёмин", "Зимин",
        "Зорин", "Злобин", "Субботин", "Бородин", "Блохин", "Брагин", "Галкин", "Бобин",
        "Дёмин", "Доронин", "Капустин", "Коровин", "Костин", "Кудрин", "Кулагин",
        "Митин", "Мухин", "Панин", "Плоткин", "Рогозин", "Сёмин", "Сидорин", "Сорокин",
        "Уткин", "Фокин", "Шишкин", "Щукин", "Юдин", "Яшин",
        "Птицын", "Синицын", "Курицын", "Лисицын", "Солженицын", "Спицын"
    ].map(key))

    private static let adjectiveSurnames: [(male: String, female: String)] = [
        ("Крамской", "Крамская"), ("Донской", "Донская"), ("Ланской", "Ланская"),
        ("Тверской", "Тверская"), ("Трубецкой", "Трубецкая"),
        ("Белый", "Белая"), ("Толстой", "Толстая"), ("Седой", "Седая"), ("Сухой", "Сухая")
    ]
}
