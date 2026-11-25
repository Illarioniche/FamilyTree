import Foundation
import XCTest
@testable import FamilyTreeCore

final class DatabaseTests: XCTestCase {
    private var directory: URL!
    private var document: URL { directory.appendingPathComponent("Семья.familytree") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FamilyTreeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testRoundTripPreservesAllFieldsOrderingAndEmbeddedAttachments() throws {
        var project = FamilyProject.demo
        let personID = try XCTUnwrap(project.rootPersonID)
        let photo = Attachment(personID: personID, filename: "Семья — 1988.png", mimeType: "image/png", data: Data([0, 137, 80, 255, 0, 10]), caption: "Подпись 🌳")
        let empty = Attachment(personID: personID, filename: "empty.txt", mimeType: "text/plain", data: Data())
        project.attachments = [photo, empty]
        let index = try XCTUnwrap(project.people.firstIndex { $0.id == personID })
        project.people[index].photoID = photo.id
        project.people[index].biography += "\nЦитата: 'дом'; встроенный ноль \0 и текст после него."
        project.createdAt = Date(timeIntervalSinceReferenceDate: 812_345_678.1234567)
        project.modifiedAt = Date(timeIntervalSinceReferenceDate: 812_345_680.9876543)

        try ProjectDatabase.save(project, to: document)

        XCTAssertEqual(try ProjectDatabase.load(from: document), project)
        XCTAssertEqual(try Data(contentsOf: document).prefix(16), Data("SQLite format 3\0".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [document.lastPathComponent])
    }

    func testEmptyProjectRoundTrip() throws {
        let project = FamilyProject(title: "Новое дерево")
        try ProjectDatabase.save(project, to: document)
        XCTAssertEqual(try ProjectDatabase.load(from: document), project)
    }

    func testEachSaveKeepsTheImmediatelyPreviousProject() throws {
        let first = FamilyProject.demo
        try ProjectDatabase.save(first, to: document)
        var second = first
        second.title = "Вторая версия"
        second.people[0].biography = "Исправленная биография"
        try ProjectDatabase.save(second, to: document)
        let backup = URL(fileURLWithPath: document.path + ".backup")
        XCTAssertEqual(try ProjectDatabase.load(from: document), second)
        XCTAssertEqual(try ProjectDatabase.load(from: backup), first)
        var third = second
        third.title = "Третья версия"
        try ProjectDatabase.save(third, to: document)
        XCTAssertEqual(try ProjectDatabase.load(from: backup), second)
        XCTAssertEqual(try ProjectDatabase.load(from: document), third)
    }

    func testFutureVersionIsRejectedAndNeverOverwritten() throws {
        try ProjectDatabase.save(.demo, to: document)
        var data = try Data(contentsOf: document)
        // SQLite's user_version is a big-endian 32-bit integer at header offset 60.
        data.replaceSubrange(60..<64, with: [0, 0, 3, 231]) // version 999
        try data.write(to: document)
        XCTAssertThrowsError(try ProjectDatabase.load(from: document)) { error in
            XCTAssertEqual(error as? ProjectValidationError, .unsupportedVersion(999))
        }
        XCTAssertThrowsError(try ProjectDatabase.save(.demo, to: document))
        XCTAssertEqual(try Data(contentsOf: document), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: document.path + ".backup"))
    }

    func testUnrelatedSQLiteFileIsNeverOverwritten() throws {
        try ProjectDatabase.save(.demo, to: document)
        var data = try Data(contentsOf: document)
        // application_id at offset 68 distinguishes our schema from unrelated SQLite files.
        data.replaceSubrange(68..<72, with: [0, 0, 0, 0])
        try data.write(to: document)
        XCTAssertThrowsError(try ProjectDatabase.load(from: document))
        XCTAssertThrowsError(try ProjectDatabase.save(.demo, to: document))
        XCTAssertEqual(try Data(contentsOf: document), data)
    }

    func testTruncatedDatabaseAndPlainTextAreRejectedWithoutChangingFiles() throws {
        try ProjectDatabase.save(.demo, to: document)
        let truncated = Data(try Data(contentsOf: document).prefix(128))
        try truncated.write(to: document)
        XCTAssertThrowsError(try ProjectDatabase.load(from: document))
        XCTAssertThrowsError(try ProjectDatabase.save(.demo, to: document))
        XCTAssertEqual(try Data(contentsOf: document), truncated)
        let text = Data("Это не база данных".utf8)
        try text.write(to: document)
        XCTAssertThrowsError(try ProjectDatabase.load(from: document))
        XCTAssertThrowsError(try ProjectDatabase.save(.demo, to: document))
        XCTAssertEqual(try Data(contentsOf: document), text)
    }

    func testFailedBackupLeavesOriginalSaveIntactAndRemovesStagingFiles() throws {
        let original = FamilyProject.demo
        try ProjectDatabase.save(original, to: document)
        let backup = URL(fileURLWithPath: document.path + ".backup", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        var edited = original
        edited.title = "Изменения, которые не удалось сохранить"
        XCTAssertThrowsError(try ProjectDatabase.save(edited, to: document))
        XCTAssertEqual(try ProjectDatabase.load(from: document), original)
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(Set(contents), Set([document.lastPathComponent, backup.lastPathComponent]))
    }

    func testInvalidProjectDoesNotTouchLastGoodSaveOrBackup() throws {
        let original = FamilyProject.demo
        try ProjectDatabase.save(original, to: document)
        var invalid = original
        invalid.relationships.append(Relationship(fromID: original.people[0].id, toID: original.people[0].id, kind: .parent))
        XCTAssertThrowsError(try ProjectDatabase.save(invalid, to: document))
        XCTAssertEqual(try ProjectDatabase.load(from: document), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: document.path + ".backup"))
    }
}
