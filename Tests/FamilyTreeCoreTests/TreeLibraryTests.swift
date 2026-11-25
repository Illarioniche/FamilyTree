import Foundation
import XCTest
@testable import FamilyTreeCore

final class TreeLibraryTests: XCTestCase {
    private var directory: URL!
    private var libraryURL: URL { directory.appendingPathComponent("Библиотека", isDirectory: true) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("TreeLibraryTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testInitAndListingDoNotCreateMissingLibraryOrMissingExternalFiles() throws {
        let library = TreeLibrary(directoryURL: libraryURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.path))
        XCTAssertTrue(try library.entries().isEmpty)
        let missing = directory.appendingPathComponent("private-filename.familytree")
        let entries = try library.entries(additionalURLs: [missing])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Недоступное дерево")
        XCTAssertNotNil(entries.first?.issue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testCreateReopensCompleteProjectAndListsUnicodeTitleAndMetadata() throws {
        let library = TreeLibrary(directoryURL: libraryURL)
        var project = FamilyProject.demo
        project.id = UUID(); project.title = "Семья — საზღვარი 🌳"
        project.modifiedAt = Date(timeIntervalSinceReferenceDate: 812_345_678.1234567)
        let personID = try XCTUnwrap(project.rootPersonID)
        project.attachments = [Attachment(personID: personID, filename: "photo.jpg", mimeType: "image/jpeg", data: Data(repeating: 7, count: 1_024 * 1_024))]
        let url = try library.create(project)
        XCTAssertEqual(url.lastPathComponent, project.id.uuidString + ".familytree")
        XCTAssertEqual(try ProjectDatabase.load(from: url), project)
        let bytes = try Data(contentsOf: url)
        let entry = try XCTUnwrap(library.entries().first)
        XCTAssertEqual(entry.id, url.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertEqual(entry.title, project.title)
        XCTAssertEqual(entry.peopleCount, project.people.count)
        XCTAssertEqual(entry.modifiedAt, project.modifiedAt)
        XCTAssertEqual(entry.issue, nil)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: libraryURL.path), [url.lastPathComponent])
    }

    func testCreatingSameIDNeverOverwritesOriginalOrCreatesBackup() throws {
        let library = TreeLibrary(directoryURL: libraryURL)
        let original = FamilyProject(title: "Первое дерево")
        let url = try library.create(original)
        let bytes = try Data(contentsOf: url)
        var changed = original; changed.title = "Не должно заменить первое"
        XCTAssertThrowsError(try library.create(changed))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try ProjectDatabase.load(from: url), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + ".backup"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: libraryURL.path), [url.lastPathComponent])
    }

    func testExternalSourcesStayIntactAndCanonicalDuplicatesAppearOnce() throws {
        let external = directory.appendingPathComponent("Внешнее.familytree")
        let original = FamilyProject(title: "Внешняя семья")
        try ProjectDatabase.save(original, to: external)
        let bytes = try Data(contentsOf: external)
        let alias = directory.appendingPathComponent("alias.familytree")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: external)
        let library = TreeLibrary(directoryURL: libraryURL)
        let managed = try library.create(FamilyProject(title: "Внутренняя семья"))
        let entries = try library.entries(additionalURLs: [external, alias, external, managed])
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.id)), Set([external.path, managed.path]))
        XCTAssertEqual(try Data(contentsOf: external), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: external.path + ".backup"))
    }

    func testListUsesCurrentDocumentsAndIgnoresBackupsAndStagingFiles() throws {
        let library = TreeLibrary(directoryURL: libraryURL)
        var old = FamilyProject(title: "Первое")
        old.modifiedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let first = try library.create(old)
        var newer = FamilyProject(title: "Второе")
        newer.modifiedAt = Date(timeIntervalSinceReferenceDate: 2_000)
        let second = try library.create(newer)
        XCTAssertEqual(try library.entries().map(\.url), [second, first])
        old.title = "Переименовано снаружи"; old.modifiedAt = Date(timeIntervalSinceReferenceDate: 3_000)
        try ProjectDatabase.save(old, to: first)
        try Data("temporary".utf8).write(to: libraryURL.appendingPathComponent(".staging.familytree"))
        try Data("note".utf8).write(to: libraryURL.appendingPathComponent("readme.txt"))
        let entries = try library.entries()
        XCTAssertEqual(entries.map(\.url), [first, second])
        XCTAssertEqual(entries.first?.title, old.title)
        XCTAssertEqual(entries.count, 2)
    }

    func testUnavailableDocumentsDoNotHideHealthyTreesOrExposeFilenamesAsTitles() throws {
        let library = TreeLibrary(directoryURL: libraryURL)
        let healthy = try library.create(FamilyProject(title: "Наша семья"))
        let corrupt = libraryURL.appendingPathComponent("private-corrupt-name.familytree")
        let badBytes = Data("not sqlite".utf8)
        try badBytes.write(to: corrupt)
        let missing = directory.appendingPathComponent("private-missing-name.familytree")
        let entries = try library.entries(additionalURLs: [missing, corrupt])
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.first?.url, healthy)
        XCTAssertEqual(entries.filter { $0.issue != nil }.map(\.title), ["Недоступное дерево", "Недоступное дерево"])
        XCTAssertEqual(try Data(contentsOf: corrupt), badBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testInvalidProjectDoesNotCreateLibraryAndExistingDestinationIsPreserved() throws {
        let library = TreeLibrary(directoryURL: libraryURL)
        var invalid = FamilyProject(); invalid.rootPersonID = UUID()
        XCTAssertThrowsError(try library.create(invalid))
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.path))
        let valid = FamilyProject(title: "Новый")
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let destination = libraryURL.appendingPathComponent(valid.id.uuidString + ".familytree")
        let bytes = Data("unrelated file".utf8)
        try bytes.write(to: destination)
        XCTAssertThrowsError(try library.create(valid))
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }

    func testSummaryRejectsUnknownAndNewerFormatsWithoutWritingFiles() throws {
        let external = directory.appendingPathComponent("check.familytree")
        try ProjectDatabase.save(FamilyProject(title: "Дерево"), to: external)
        let original = try Data(contentsOf: external)
        var future = original
        future.replaceSubrange(60..<64, with: [0, 0, 3, 231])
        try future.write(to: external)
        XCTAssertThrowsError(try ProjectDatabase.librarySummary(from: external))
        let futureEntry = try XCTUnwrap(TreeLibrary(directoryURL: libraryURL).entries(additionalURLs: [external]).first)
        XCTAssertEqual(futureEntry.issue, ProjectValidationError.unsupportedVersion(999).localizedDescription)
        XCTAssertEqual(try Data(contentsOf: external), future)
        var unknown = original
        unknown.replaceSubrange(68..<72, with: [0, 0, 0, 0])
        try unknown.write(to: external)
        XCTAssertThrowsError(try ProjectDatabase.librarySummary(from: external))
        XCTAssertEqual(try Data(contentsOf: external), unknown)
        let truncated = Data(original.prefix(128))
        try truncated.write(to: external)
        XCTAssertThrowsError(try ProjectDatabase.librarySummary(from: external))
        XCTAssertEqual(try Data(contentsOf: external), truncated)
    }

    func testConcurrentCreateWithOneIDPublishesExactlyOneCompleteTree() throws {
        let library = TreeLibrary(directoryURL: libraryURL)
        let project = FamilyProject.demo
        let lock = NSLock()
        var successes: [URL] = []
        DispatchQueue.concurrentPerform(iterations: 4) { _ in
            if let url = try? library.create(project) {
                lock.lock(); successes.append(url); lock.unlock()
            }
        }
        XCTAssertEqual(successes.count, 1)
        let url = try XCTUnwrap(successes.first)
        XCTAssertEqual(try ProjectDatabase.load(from: url), project)
        XCTAssertEqual(try library.entries().count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: libraryURL.path), [url.lastPathComponent])
    }

    func testDisplayTitleHidesOnlyKnownFamytaleExportNames() {
        for title in ["", "  \n ", "famytale_123_2026-09-21T05_16_43.000Z", "FAMYTALE_123_2026-09-21T05:16:43.000Z.ged"] {
            XCTAssertEqual(TreeLibrary.displayTitle(title), "Моя семья")
        }
        for title in ["Моя родня", "famytale_123", "famytale_123_2026-09-21T05_16_43.000Z — копия", "myfile.ged", "Родословная 2026"] {
            XCTAssertEqual(TreeLibrary.displayTitle("  " + title + "  "), title)
        }
        let entry = TreeLibraryEntry(url: URL(fileURLWithPath: "/tmp/example.familytree"), title: "famytale_123_2026-09-21T05_16_43.000Z", peopleCount: 1, modifiedAt: .distantPast)
        XCTAssertEqual(entry.title, "Моя семья")
    }
}
