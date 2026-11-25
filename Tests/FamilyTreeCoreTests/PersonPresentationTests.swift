import XCTest
@testable import FamilyTreeCore

final class PersonPresentationTests: XCTestCase {
    func testNamesUseSurnameGivenNamePatronymicWithoutChangingStoredParts() {
        let person = Person(givenName: "Анна", patronymic: "Петровна", familyName: "Волкова")
        XCTAssertEqual(person.fullName, "Волкова Анна Петровна")
        XCTAssertEqual(person.shortName, "Волкова Анна")
        XCTAssertEqual(person.givenName, "Анна")
        XCTAssertEqual(person.patronymic, "Петровна")
        XCTAssertEqual(person.familyName, "Волкова")
        // GEDCOM often puts the given name and patronymic together in GIVN.
        let imported = Person(givenName: "Анна Петровна", familyName: "Волкова")
        XCTAssertEqual(imported.fullName, "Волкова Анна Петровна")
    }

    func testMissingNamePartsHaveNoExtraSpacesOrInventedSurname() {
        XCTAssertEqual(Person(givenName: "Анна", patronymic: "Петровна").fullName, "Анна Петровна")
        XCTAssertEqual(Person(familyName: "Волкова").fullName, "Волкова")
        XCTAssertEqual(Person(patronymic: "Петровна").fullName, "Петровна")
        XCTAssertEqual(Person().fullName, "Без имени")
        XCTAssertEqual(Person().shortName, "Без имени")
        let spaced = Person(givenName: " Анна ", patronymic: " ", familyName: " Волкова ")
        XCTAssertEqual(spaced.fullName, "Волкова Анна")
        XCTAssertEqual(spaced.givenName, " Анна ")
    }

    func testExactDatesAreNormalizedFromGEDCOMISOAndDottedForms() {
        for raw in ["1988-07-04", "1988-7-4", "4 JUL 1988", "04 jul 1988", "4.7.1988", "04.07.1988", "  4 JUL 1988  "] {
            XCTAssertEqual(GenealogyDate.display(raw), "04.07.1988")
        }
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        for (index, month) in months.enumerated() {
            XCTAssertEqual(GenealogyDate.display("3 \(month) 2001"), String(format: "03.%02d.2001", index + 1))
        }
        XCTAssertEqual(GenealogyDate.display("7 NOV 999"), "07.11.0999")
    }

    func testLeapYearsAndInvalidDatesDoNotInventValidDays() {
        XCTAssertEqual(GenealogyDate.display("29 FEB 2000"), "29.02.2000")
        XCTAssertEqual(GenealogyDate.display("2024-02-29"), "29.02.2024")
        for raw in ["29 FEB 1900", "2023-02-29", "31 APR 2000", "32.01.2000", "00.01.2000", "2000-00-01", "2000-13-01", "2000-01-00", "01.01.0000", "+1 JAN 2000"] {
            XCTAssertEqual(GenealogyDate.display(raw), raw)
        }
    }

    func testPartialApproximateAndFreeFormDatesArePreservedVerbatim() {
        for raw in ["", "1901", "JUN 1901", "06.1901", "1901-06", "ABT 4 JUL 1988", "BEF 1988", "BET 1988 AND 1990", "FROM 1 JAN 1901 TO 2 JAN 1902", "около 1901 года", "лето 1945", "4 июля 1988", "  неизвестно  ", "@#DJULIAN@ 4 JUL 1901", "1901/02", "04/07/1988", "04.07.88", "(4 JUL 1988)"] {
            XCTAssertEqual(GenealogyDate.display(raw), raw)
        }
    }

    func testLifespanShowsFullBirthAndDeathDatesAndRetainsUncertainty() {
        XCTAssertEqual(Person(birthDate: "4 JUL 1988").lifespan, "04.07.1988")
        XCTAssertEqual(Person(birthDate: "1988-07-04", deathDate: "9.2.2020", isDeceased: true).lifespan, "04.07.1988 — 09.02.2020")
        XCTAssertEqual(Person(birthDate: "около 1901 года", deathDate: "BEF 1988", isDeceased: true).lifespan, "около 1901 года — BEF 1988")
        XCTAssertEqual(Person(birthDate: "1901", deathDate: "4 JUL 1988", isDeceased: true).lifespan, "1901 — 04.07.1988")
        // A recorded death date must remain visible even if the flag is inconsistent.
        XCTAssertEqual(Person(birthDate: "1901", deathDate: "1988").lifespan, "1901 — 1988")
    }

    func testMissingLifeDatesUsePlaceholdersOnlyForAbsentValues() {
        XCTAssertEqual(Person().lifespan, "Даты не указаны")
        XCTAssertEqual(Person(birthDate: " ").lifespan, "Даты не указаны")
        XCTAssertEqual(Person(birthDate: "1901", isDeceased: true).lifespan, "1901 — ?")
        XCTAssertEqual(Person(deathDate: "1988", isDeceased: true).lifespan, "? — 1988")
        XCTAssertEqual(Person(isDeceased: true).lifespan, "? — ?")
        XCTAssertEqual(Person(birthDate: "неизвестно", deathDate: "после войны", isDeceased: true).lifespan, "неизвестно — после войны")
    }

    func testPresentationDoesNotChangeGEDCOMNameOrDateRoundTrip() throws {
        let person = Person(givenName: "Анна", patronymic: "Петровна", familyName: "Волкова", birthDate: "1988-07-04", deathDate: "после 2020 года", isDeceased: true)
        let project = FamilyProject(people: [person])
        let before = GEDCOM.export(project)
        _ = person.fullName
        _ = person.shortName
        _ = person.lifespan
        XCTAssertEqual(GEDCOM.export(project), before)
        let imported = try GEDCOM.importData(before)
        let restored = try XCTUnwrap(imported.project.people.first)
        XCTAssertEqual(restored.givenName, person.givenName)
        XCTAssertEqual(restored.patronymic, person.patronymic)
        XCTAssertEqual(restored.familyName, person.familyName)
        XCTAssertEqual(restored.birthDate, person.birthDate)
        XCTAssertEqual(restored.deathDate, person.deathDate)
    }
}
