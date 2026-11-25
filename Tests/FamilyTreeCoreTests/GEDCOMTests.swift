import XCTest
@testable import FamilyTreeCore

final class GEDCOMTests: XCTestCase {
    private func read(_ body: String, version: String = "5.5.1") throws -> GEDCOMImportResult {
        try GEDCOM.importData(Data(("0 HEAD\n1 GEDC\n2 VERS \(version)\n1 CHAR UTF-8\n" + body + "\n0 TRLR\n").utf8))
    }

    func testImportsCyrillicNamesDatesFamiliesAndMultilineNotes() throws {
        let result = try read("""
        0 @I1@ INDI
        1 NAME Алексей /Волков/
        2 GIVN Алексей
        2 SURN Волков
        1 SEX M
        1 BIRT
        2 DATE ABT 1900
        2 PLAC Казань
        1 NOTE Первая строка
        2 CONT Вторая
        2 CONC строка
        1 FAMS @F1@
        0 @I2@ INDI
        1 NAME Мария /Волкова/
        1 SEX F
        0 @I3@ INDI
        1 NAME Анна /Волкова/
        1 DEAT Y
        2 DATE 1984
        0 @F1@ FAM
        1 HUSB @I1@
        1 WIFE @I2@
        1 CHIL @I3@
        1 MARR
        2 DATE 1925
        2 PLAC Казань
        """)
        let father = try XCTUnwrap(result.project.people.first { $0.givenName == "Алексей" })
        let child = try XCTUnwrap(result.project.people.first { $0.givenName == "Анна" })
        XCTAssertEqual(father.familyName, "Волков")
        XCTAssertEqual(father.birthDate, "ABT 1900")
        XCTAssertEqual(father.birthPlace, "Казань")
        XCTAssertEqual(father.biography, "Первая строка\nВтораястрока")
        XCTAssertTrue(child.isDeceased)
        XCTAssertEqual(result.project.parents(of: child.id).count, 2)
        XCTAssertEqual(result.project.partners(of: father.id).count, 1)
        XCTAssertEqual(result.project.events.filter { $0.kind == .marriage }.count, 2)
    }

    func testFamytaleAdditionalNameIsPreservedWithoutGuessingSurnameRole() throws {
        let result = try read("""
        0 @I1@ INDI
        1 NAME Анна /Смирнова/
        2 GIVN Анна
        2 SURN Смирнова
        2 _MARNM Петрова
        1 NOTE Семейное воспоминание.
        """)
        let person = try XCTUnwrap(result.project.people.first)
        XCTAssertEqual(person.givenName, "Анна")
        XCTAssertEqual(person.familyName, "Смирнова")
        XCTAssertEqual(person.maidenName, "")
        XCTAssertEqual(person.biography, "Семейное воспоминание.\n\nДругое имя из GEDCOM: Петрова")
        XCTAssertTrue(result.warnings.contains { $0.contains("_MARNM") && $0.contains("сохранены") })
        XCTAssertFalse(result.warnings.contains { $0.contains("пропущены") && $0.contains("_MARNM") })
        let roundTrip = try GEDCOM.importData(GEDCOM.export(result.project))
        XCTAssertEqual(roundTrip.project.people.first?.biography, person.biography)
    }

    func testFamytaleRepeatedAdditionalNamesArePreservedOnce() throws {
        let result = try read("""
        0 @I1@ INDI
        1 NAME Анна /Смирнова/
        2 _MARNM Петрова
        2 _MARNM Петрова
        2 _MARNM
        """)
        XCTAssertEqual(result.project.people.first?.biography, "Другое имя из GEDCOM: Петрова")
        XCTAssertEqual(result.warnings.filter { $0.contains("_MARNM") }.count, 1)
    }

    func testSingleParentAndAdoptionFromPedigree() throws {
        let result = try read("""
        0 @I1@ INDI
        1 NAME Родитель
        0 @I2@ INDI
        1 NAME Ребёнок
        1 FAMC @F1@
        2 PEDI adopted
        0 @F1@ FAM
        1 WIFE @I1@
        1 CHIL @I2@
        """)
        XCTAssertEqual(result.project.relationships.count, 1)
        XCTAssertEqual(result.project.relationships.first?.kind, .adoptiveParent)
    }

    func testAdoptionEventCanApplyToOneParent() throws {
        let result = try read("""
        0 @I1@ INDI
        1 NAME Первый
        0 @I2@ INDI
        1 NAME Второй
        0 @I3@ INDI
        1 NAME Ребёнок
        1 ADOP
        2 FAMC @F1@
        3 ADOP HUSB
        0 @F1@ FAM
        1 HUSB @I1@
        1 WIFE @I2@
        1 CHIL @I3@
        """)
        XCTAssertEqual(result.project.relationships.filter { $0.kind == .adoptiveParent }.count, 1)
        XCTAssertEqual(result.project.relationships.filter { $0.kind == .parent }.count, 1)
    }

    func testMultiplePartnersRemainSeparateFamilies() throws {
        let result = try read("""
        0 @I1@ INDI
        1 NAME Алексей
        0 @I2@ INDI
        1 NAME Анна
        0 @I3@ INDI
        1 NAME Мария
        0 @I4@ INDI
        1 NAME Дочь
        0 @F1@ FAM
        1 HUSB @I1@
        1 WIFE @I2@
        0 @F2@ FAM
        1 HUSB @I1@
        1 WIFE @I3@
        1 CHIL @I4@
        """)
        let father = result.project.people[0]
        let daughter = result.project.people[3]
        XCTAssertEqual(result.project.partners(of: father.id).count, 2)
        XCTAssertEqual(Set(result.project.parents(of: daughter.id).map(\.givenName)), ["Алексей", "Мария"])
    }

    func testRoundTripPreservesOwnNamesFreeDatesEventsAndParentKinds() throws {
        let parent = Person(givenName: "Анна", patronymic: "Петровна", familyName: "Волкова", maidenName: "Белова", gender: .female, birthDate: "около 1954 года", birthPlace: "Тверь", occupation: "Врач", biography: "Заметка с @адресом\nСледующая строка")
        let child = Person(givenName: "Елена", familyName: "Волкова", birthDate: "1988-07-14")
        let event = FamilyEvent(personID: parent.id, kind: .education, title: "Университет", date: "1971–1977", place: "Москва", notes: "Диплом")
        let project = FamilyProject(title: "Наш архив", rootPersonID: child.id, people: [parent, child], relationships: [Relationship(fromID: parent.id, toID: child.id, kind: .adoptiveParent)], events: [event])
        let data = GEDCOM.export(project)
        let decoded = try GEDCOM.importData(data).project
        XCTAssertEqual(decoded.title, project.title)
        XCTAssertEqual(decoded.rootPersonID, child.id)
        XCTAssertEqual(decoded.people, project.people)
        XCTAssertEqual(decoded.relationships.map(\.kind), [.adoptiveParent])
        XCTAssertEqual(decoded.events.first?.title, event.title)
        XCTAssertEqual(decoded.events.first?.date, event.date)
        XCTAssertEqual(decoded.events.first?.kind, event.kind)
        XCTAssertEqual(decoded.events.first?.notes, event.notes)
    }

    func testCoparentsDoNotInventPartnerRelationshipOnRoundTrip() throws {
        let a = Person(givenName: "А"), b = Person(givenName: "Б"), c = Person(givenName: "В")
        let project = FamilyProject(people: [a, b, c], relationships: [Relationship(fromID: a.id, toID: c.id, kind: .parent), Relationship(fromID: b.id, toID: c.id, kind: .parent)])
        let decoded = try GEDCOM.importData(GEDCOM.export(project)).project
        XCTAssertEqual(decoded.relationships.count, 2)
        XCTAssertTrue(decoded.relationships.allSatisfy { $0.kind == .parent })
    }

    func testUTF8BOMAndGEDCOM7SharedNotes() throws {
        let input = "\u{FEFF}0 HEAD\n1 GEDC\n2 VERS 7.0\n0 @I1@ INDI\n1 NAME Анна\n1 SNOTE @N1@\n0 @N1@ SNOTE Общая заметка\n1 CONT Вторая строка\n0 TRLR\n"
        let result = try GEDCOM.importData(Data(input.utf8))
        XCTAssertEqual(result.project.people.first?.biography, "Общая заметка\nВторая строка")
    }

    func testUTF16BOM() throws {
        let input = "0 HEAD\n1 GEDC\n2 VERS 5.5.1\n1 CHAR UNICODE\n0 @I1@ INDI\n1 NAME Анна\n0 TRLR\n"
        let result = try GEDCOM.importData(try XCTUnwrap(input.data(using: .utf16)))
        XCTAssertEqual(result.project.people.first?.givenName, "Анна")
    }

    func testMediaAreNotLoadedAndUnsupportedTagsAreReported() throws {
        let result = try read("""
        0 @I1@ INDI
        1 NAME Анна
        1 OBJE
        2 FILE /etc/passwd
        1 SOUR @S1@
        1 _CUSTOM secret-value
        0 @S1@ SOUR
        1 TITL Архив
        """)
        XCTAssertTrue(result.project.attachments.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.contains("Внешние файлы") })
        XCTAssertTrue(result.warnings.contains { $0.contains("SOUR/REPO") })
        XCTAssertTrue(result.warnings.contains { $0.contains("_CUSTOM") })
    }

    func testRejectsMalformedStructureDuplicateAndDanglingReferences() {
        XCTAssertThrowsError(try GEDCOM.importData(Data("Hello, World".utf8)))
        XCTAssertThrowsError(try read("0 @I1@ INDI\n3 NAME Анна"))
        XCTAssertThrowsError(try read("0 @I1@ INDI\n1 NAME Анна\n0 @I1@ INDI\n1 NAME Иван"))
        XCTAssertThrowsError(try read("0 @I1@ INDI\n1 NAME Анна\n0 @F1@ FAM\n1 HUSB @MISSING@"))
        XCTAssertThrowsError(try read("0 @I1@ INDI\n1 NAME Анна\n1 FAMC @MISSING@"))
        XCTAssertThrowsError(try read(""))
    }

    func testRejectsAncestryCycle() {
        XCTAssertThrowsError(try read("""
        0 @I1@ INDI
        1 NAME Первый
        0 @I2@ INDI
        1 NAME Второй
        0 @F1@ FAM
        1 HUSB @I1@
        1 CHIL @I2@
        0 @F2@ FAM
        1 HUSB @I2@
        1 CHIL @I1@
        """))
    }


    func testUnknownDeathDateKeepsDeceasedStatus() throws {
        let result = try read("0 @I1@ INDI\n1 NAME Анна\n1 DEAT Y")
        XCTAssertEqual(result.project.people.first?.isDeceased, true)
        XCTAssertEqual(result.project.people.first?.deathDate, "")
        let again = try GEDCOM.importData(GEDCOM.export(result.project))
        XCTAssertEqual(again.project.people.first?.isDeceased, true)
        XCTAssertEqual(again.project.people.first?.deathDate, "")
    }

    func testBiologicalAndAdoptiveGroupsRoundTripIndependently() throws {
        let parent = Person(givenName: "Родитель"), child = Person(givenName: "Ребёнок")
        let project = FamilyProject(people: [parent, child], relationships: [
            Relationship(fromID: parent.id, toID: child.id, kind: .parent),
            Relationship(fromID: parent.id, toID: child.id, kind: .adoptiveParent)
        ])
        let decoded = try GEDCOM.importData(GEDCOM.export(project)).project
        XCTAssertEqual(Set(decoded.relationships.map(\.kind)), [.parent, .adoptiveParent])
        XCTAssertEqual(decoded.relationships.count, 2)
    }

    func testLongUnicodeNotesExportWithinLineLimitAndReadBack() throws {
        let note = String(repeating: "История семьи ", count: 80) + "\n" + String(repeating: "x", count: 179) + "@" + String(repeating: "@", count: 100) + "\n\nКонец."
        let person = Person(givenName: "Анна", biography: note)
        let data = GEDCOM.export(FamilyProject(people: [person]))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 255 })
        XCTAssertEqual(try GEDCOM.importData(data).project.people.first?.biography, note)
    }
}
