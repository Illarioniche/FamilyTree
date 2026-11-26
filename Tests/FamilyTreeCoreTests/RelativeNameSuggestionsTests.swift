import XCTest
@testable import FamilyTreeCore

final class RelativeNameSuggestionsTests: XCTestCase {
    func testRequestedIlyaAndIrakliFormsDoNotUseRegularSuffixes() {
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Илья", childGender: .male), "Ильич")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Илья", childGender: .female), "Ильинична")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Ираклий", childGender: .male), "Ираклиевич")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Ираклий", childGender: .female), "Ираклиевна")
        XCTAssertEqual(RelativeNameSuggestions.fatherGivenName(childPatronymic: "Ильинична"), "Илья")
        XCTAssertEqual(RelativeNameSuggestions.fatherGivenName(childPatronymic: "Ираклиевич"), "Ираклий")
    }

    func testCommonNamesAndStemChangesForBothChildGenders() {
        let cases = [
            ("Иван", "Иванович", "Ивановна"), ("Александр", "Александрович", "Александровна"),
            ("Дмитрий", "Дмитриевич", "Дмитриевна"), ("Сергей", "Сергеевич", "Сергеевна"),
            ("Алексей", "Алексеевич", "Алексеевна"), ("Николай", "Николаевич", "Николаевна"),
            ("Андрей", "Андреевич", "Андреевна"), ("Евгений", "Евгеньевич", "Евгеньевна"),
            ("Павел", "Павлович", "Павловна"), ("Пётр", "Петрович", "Петровна"),
            ("Лев", "Львович", "Львовна"), ("Яков", "Яковлевич", "Яковлевна"),
            ("Никита", "Никитич", "Никитична"), ("Кузьма", "Кузьмич", "Кузьминична"),
            ("Матвей", "Матвеевич", "Матвеевна"), ("Михаил", "Михаилович", "Михаиловна")
        ]
        for (name, son, daughter) in cases {
            XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: name, childGender: .male), son, name)
            XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: name, childGender: .female), daughter, name)
            XCTAssertEqual(RelativeNameSuggestions.fatherGivenName(childPatronymic: son), name, name)
            XCTAssertEqual(RelativeNameSuggestions.fatherGivenName(childPatronymic: daughter), name, name)
        }
    }

    func testUnknownGenderOrUnrecognizedFatherDoesNotInventPatronymic() {
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Илья", childGender: .unspecified), nil)
        for name in ["", " \n\t", "Саша", "Женя", "Гвтисавар", "John", "Илья Ираклиевич Пётр", "Иван-Пётр", "Неизвестен"] {
            XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: name, childGender: .male), nil, name)
            XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: name, childGender: .female), nil, name)
        }
    }

    func testYoSpellingCaseAndOuterWhitespaceAreHandledWithoutMatchingPartsOfNames() {
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "  иЛьЯ\n", childGender: .female), "Ильинична")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "ПЕТР", childGender: .male), "Петрович")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Семён", childGender: .male), "Семёнович")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Семен", childGender: .male), "Семенович")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Артём", childGender: .male), "Артёмович")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Артем", childGender: .male), "Артемович")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Артемий", childGender: .male), "Артемьевич")
    }

    func testFatherNameIsSuggestedOnlyForUniqueKnownPatronymic() {
        XCTAssertEqual(RelativeNameSuggestions.fatherGivenName(childPatronymic: "Данилович"), nil)
        XCTAssertEqual(RelativeNameSuggestions.fatherGivenName(childPatronymic: "Даниловна"), nil)
        XCTAssertEqual(RelativeNameSuggestions.fatherGivenName(childPatronymic: "Данииловна"), "Даниил")
        XCTAssertEqual(RelativeNameSuggestions.fatherGivenName(childPatronymic: "  иВаНоВнА \n"), "Иван")
        for value in ["", "Неизвестно", "Джонович", "сын Ивана", "Иванович Петрович", "Петров", "Семёнович?", "Гвтисаварович"] {
            XCTAssertEqual(RelativeNameSuggestions.fatherGivenName(childPatronymic: value), nil, value)
        }
    }

    func testSplitGivenNamesRecognizesMaleAndFemalePatronymicsWithoutRewritingSpelling() {
        let father = RelativeNameSuggestions.splitGivenNames("  иЛьЯ\tИраклиевич \n")
        XCTAssertEqual(father?.givenName, "иЛьЯ")
        XCTAssertEqual(father?.patronymic, "Ираклиевич")
        let mother = RelativeNameSuggestions.splitGivenNames("Елена Сергеевна")
        XCTAssertEqual(mother?.givenName, "Елена")
        XCTAssertEqual(mother?.patronymic, "Сергеевна")
        XCTAssertEqual(RelativeNameSuggestions.fatherGivenName(childPatronymic: mother?.patronymic ?? ""), "Сергей")
        // A known patronymic can be recognized even if its father's given name
        // has several possible spellings (Данил / Данила).
        XCTAssertEqual(RelativeNameSuggestions.splitGivenNames("Нана Даниловна")?.patronymic, "Даниловна")
        XCTAssertEqual(RelativeNameSuggestions.fatherGivenName(childPatronymic: "Даниловна"), nil)
    }

    func testSplitGivenNamesDoesNotGuessFromCompoundNamesOrUnknownPatronymics() {
        for value in ["", "Илья", "John Paul", "Иван Пётр", "Иван-Пётр Сергеевич", "Елена Анна Сергеевна",
                      "Илья Гвтисаварович", "Илья Иванов", "Елена Сергеевна?", "Елена1 Сергеевна", "Aнна Сергеевна"] {
            XCTAssertEqual(RelativeNameSuggestions.splitGivenNames(value)?.givenName, nil, value)
        }
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Елена Сергеевна", childGender: .male), nil)
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Гвтисавар Сергеевич", childGender: .male), nil)
    }

    func testPatronymicUsesOnlyRecognizedGivenNameAndItsYoSpelling() {
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Илья Ираклиевич", childGender: .male), "Ильич")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Илья Ираклиевич", childGender: .female), "Ильинична")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Илья Ираклиевич", childGender: .unspecified), nil)
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Семен Фёдорович", childGender: .male), "Семенович")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: "Семён Федорович", childGender: .female), "Семёновна")
    }

    func testGEDCOMCombinedGivnOffersChildPatronymicWithoutChangingImportedNames() throws {
        let data = Data("""
        0 HEAD
        1 SOUR FAMYTALE
        1 GEDC
        2 VERS 5.5.1
        1 CHAR UTF-8
        0 @I1@ INDI
        1 NAME Илья Ираклиевич /Волков/
        2 GIVN Илья Ираклиевич
        2 SURN Волков
        1 SEX M
        0 TRLR
        """.utf8)
        let result = try GEDCOM.importData(data)
        let person = try XCTUnwrap(result.project.people.first)
        XCTAssertEqual(person.givenName, "Илья Ираклиевич")
        XCTAssertEqual(person.patronymic, "")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: person.givenName, childGender: .male), "Ильич")
        XCTAssertEqual(RelativeNameSuggestions.patronymic(fatherGivenName: person.givenName, childGender: .female), "Ильинична")
        XCTAssertEqual(person.givenName, "Илья Ираклиевич")
        XCTAssertEqual(person.patronymic, "")
        let roundTrip = try GEDCOM.importData(GEDCOM.export(result.project))
        XCTAssertEqual(roundTrip.project.people.first?.givenName, person.givenName)
        XCTAssertEqual(roundTrip.project.people.first?.patronymic, person.patronymic)
    }

    func testStandardSurnameSuggestionsWorkInBothDirectionsAndKeepExistingGenderForm() {
        let cases = [("Иванов", "Иванова"), ("Сергеев", "Сергеева"), ("Королёв", "Королёва"),
                     ("Ильин", "Ильина"), ("Пушкин", "Пушкина"), ("Никитин", "Никитина"),
                     ("Лисицын", "Лисицына"), ("Достоевский", "Достоевская"), ("Заболоцкий", "Заболоцкая")]
        for (male, female) in cases {
            XCTAssertEqual(RelativeNameSuggestions.familyName(male, gender: .female), female)
            XCTAssertEqual(RelativeNameSuggestions.familyName(female, gender: .male), male)
            XCTAssertEqual(RelativeNameSuggestions.familyName(male, gender: .male), male)
            XCTAssertEqual(RelativeNameSuggestions.familyName(female, gender: .female), female)
        }
    }

    func testAdjectiveExceptionsDoNotTurnSkoyIntoSkiy() {
        for (male, female) in [("Донской", "Донская"), ("Крамской", "Крамская"), ("Трубецкой", "Трубецкая"),
                               ("Белый", "Белая"), ("Толстой", "Толстая"), ("Седой", "Седая")] {
            XCTAssertEqual(RelativeNameSuggestions.familyName(male, gender: .female), female)
            XCTAssertEqual(RelativeNameSuggestions.familyName(female, gender: .male), male)
        }
    }

    func testIndeclinableForeignCompoundAndAmbiguousSurnamesRemainIntact() {
        for name in ["Кобахидзе", "Булацашвили", "Шевченко", "Ким", "Кац", "Лев", "Блок", "Малина", "Смородина", "Жемчужина",
                     "Дарвин", "Чаплин", "Грин", "Корзина", "Родина", "Иванова-Петрова", "де Голль", "Smith", "O’Connor", "Блок/Иванов"] {
            XCTAssertEqual(RelativeNameSuggestions.familyName(name, gender: .male), name, name)
            XCTAssertEqual(RelativeNameSuggestions.familyName(name, gender: .female), name, name)
        }
    }

    func testSurnameSuggestionsPreserveCaseAndNeverGuessFromUnspecifiedGender() {
        XCTAssertEqual(RelativeNameSuggestions.familyName("ИВАНОВА", gender: .male), "ИВАНОВ")
        XCTAssertEqual(RelativeNameSuggestions.familyName("иванов", gender: .female), "иванова")
        XCTAssertEqual(RelativeNameSuggestions.familyName("ДОСТОЕВСКИЙ", gender: .female), "ДОСТОЕВСКАЯ")
        XCTAssertEqual(RelativeNameSuggestions.familyName("трубецкая", gender: .male), "трубецкой")
        XCTAssertEqual(RelativeNameSuggestions.familyName("  Иванова\n", gender: .unspecified), "Иванова")
        XCTAssertEqual(RelativeNameSuggestions.familyName("Кобахидзе", gender: .unspecified), "Кобахидзе")
        XCTAssertEqual(RelativeNameSuggestions.familyName("", gender: .male), nil)
        XCTAssertEqual(RelativeNameSuggestions.familyName(" \n\t ", gender: .female), nil)
    }
}
