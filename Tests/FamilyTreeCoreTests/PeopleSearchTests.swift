import XCTest
@testable import FamilyTreeCore

final class PeopleSearchTests: XCTestCase {
    func testWordsMatchAcrossNamePartsInAnyOrderAndRequireEveryWord() {
        let people = [Person(givenName: "Анна", patronymic: "Петровна", familyName: "Волкова"),
                      Person(givenName: "Мария", patronymic: "Петровна", familyName: "Волкова")]
        for query in ["Анна Волкова", "волкова анна", "Петровна АННА", "  Анна\t Волк\n "] {
            XCTAssertEqual(PeopleSearch.filter(people, query: query), [people[0]])
        }
        XCTAssertTrue(PeopleSearch.filter(people, query: "Анна Мария").isEmpty)
        XCTAssertTrue(PeopleSearch.filter(people, query: "Анна несуществующий").isEmpty)
    }

    func testMaidenSurnameCanBeCombinedWithNamePlaceOrYear() {
        let person = Person(givenName: "Анна", familyName: "Волкова", maidenName: "Белова",
                            birthDate: "4 JUL 1988", birthPlace: "Нижний Новгород")
        for query in ["Белова", "Анна Белова", "Новгород Белова", "1988 Белова", "04.07.1988", "JUL 1988"] {
            XCTAssertEqual(PeopleSearch.filter([person], query: query), [person])
        }
        XCTAssertTrue(PeopleSearch.filter([person], query: "Белова 1999").isEmpty)
    }

    func testYoCaseAndDiacriticsDoNotPreventMatches() {
        let person = Person(givenName: "Алёна", familyName: "Семёнова", maidenName: "García")
        for query in ["алена", "СЕМЕНОВА", "garcia", "GARCÍA Алёна"] {
            XCTAssertEqual(PeopleSearch.filter([person], query: query), [person])
        }
    }

    func testPartialDatesAndExistingOccupationSearchRemainAvailable() {
        let person = Person(givenName: "Анна", birthDate: "около 1901 года", deathDate: "1972",
                            occupation: "Учитель музыки", biography: "Секретная заметка")
        for query in ["1901", "около", "учитель", "музыки 1901"] {
            XCTAssertEqual(PeopleSearch.filter([person], query: query), [person])
        }
        XCTAssertTrue(PeopleSearch.filter([person], query: "секретная").isEmpty)
        XCTAssertTrue(PeopleSearch.filter([person], query: "1972").isEmpty)
    }

    func testEmptySearchAndFilteringPreservePeopleFieldsAndInputOrder() {
        let people = [Person(givenName: "Яна", familyName: "Белова", maidenName: "Петрова"),
                      Person(givenName: "Анна", familyName: "Белова")]
        let before = people
        XCTAssertEqual(PeopleSearch.filter(people, query: ""), people)
        XCTAssertEqual(PeopleSearch.filter(people, query: " \n\t "), people)
        XCTAssertEqual(PeopleSearch.filter(people, query: "Белова"), people)
        XCTAssertEqual(people, before)
        XCTAssertTrue(PeopleSearch.filter([], query: "Анна").isEmpty)
    }
}
