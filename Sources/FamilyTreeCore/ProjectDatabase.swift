import Foundation
import CSQLite
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum ProjectDatabaseError: LocalizedError {
    case unrecognizedFormat
    case corruptData(String)
    case sqlite(String)
    case fileOperation(String)

    public var errorDescription: String? {
        switch self {
        case .unrecognizedFormat: return "Этот файл не является проектом семейного дерева. Исходный файл не изменён."
        case .corruptData(let detail): return "Данные проекта повреждены: \(detail)"
        case .sqlite(let detail): return "Не удалось прочитать или сохранить базу проекта: \(detail)"
        case .fileOperation(let detail): return "Не удалось сохранить файл проекта: \(detail)"
        }
    }
}

/// Lightweight library metadata. Opening the document still performs full validation.
public struct ProjectLibrarySummary: Equatable, Sendable {
    public let title: String
    public let peopleCount: Int
    public let modifiedAt: Date
}

/// A portable SQLite document. Attachments are embedded, so moving the file moves the entire tree.
public enum ProjectDatabase {
    private static let applicationID = 1_179_931_205 // ASCII "FTRE"

    /// Reads the document header and count without materializing attachment BLOBs.
    /// This is a listing summary, not a substitute for full validation on open/save.
    public static func librarySummary(from url: URL) throws -> ProjectLibrarySummary {
        let database = try Database(url: url, readOnly: true)
        guard try database.integer("PRAGMA application_id") == applicationID else {
            throw ProjectDatabaseError.unrecognizedFormat
        }
        let version = try database.integer("PRAGMA user_version")
        guard version == FamilyProject.currentFormatVersion else {
            throw ProjectValidationError.unsupportedVersion(version)
        }
        guard try database.integer("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN ('project', 'people', 'relationships', 'events', 'attachments')") == 5 else {
            throw ProjectDatabaseError.corruptData("отсутствуют таблицы проекта")
        }
        var summary: ProjectLibrarySummary?
        let peopleCount = try database.integer("SELECT COUNT(*) FROM people")
        try database.rows("SELECT id, title, modified_at, format_version FROM project") { row in
            guard summary == nil else { throw ProjectDatabaseError.corruptData("несколько заголовков проекта") }
            _ = try row.uuid(0)
            guard try row.integer(3) == version else { throw ProjectDatabaseError.corruptData("версии заголовка и базы не совпадают") }
            summary = ProjectLibrarySummary(title: try row.text(1), peopleCount: peopleCount,
                                            modifiedAt: Date(timeIntervalSinceReferenceDate: try row.real(2)))
        }
        guard let summary else { throw ProjectDatabaseError.corruptData("отсутствует заголовок проекта") }
        return summary
    }

    public static func load(from url: URL) throws -> FamilyProject {
        let database = try Database(url: url, readOnly: true)
        guard try database.integer("PRAGMA application_id") == applicationID else {
            throw ProjectDatabaseError.unrecognizedFormat
        }
        let version = try database.integer("PRAGMA user_version")
        guard version == FamilyProject.currentFormatVersion else {
            throw ProjectValidationError.unsupportedVersion(version)
        }
        var integrity: [String] = []
        try database.rows("PRAGMA quick_check") { integrity.append(try $0.text(0)) }
        guard integrity == ["ok"] else { throw ProjectDatabaseError.corruptData("проверка целостности SQLite не пройдена") }

        var metadata: FamilyProject?
        try database.rows("SELECT id, title, created_at, modified_at, root_person_id, format_version FROM project") { row in
            guard metadata == nil else { throw ProjectDatabaseError.corruptData("несколько заголовков проекта") }
            var project = FamilyProject(id: try row.uuid(0), title: try row.text(1), rootPersonID: try row.optionalUUID(4))
            // Seconds since 2001-01-01 UTC preserve Swift Date exactly; the epoch is documented in FORMAT.md.
            project.createdAt = Date(timeIntervalSinceReferenceDate: try row.real(2))
            project.modifiedAt = Date(timeIntervalSinceReferenceDate: try row.real(3))
            project.formatVersion = try row.integer(5)
            guard project.formatVersion == version else { throw ProjectDatabaseError.corruptData("версии заголовка и базы не совпадают") }
            metadata = project
        }
        guard var project = metadata else { throw ProjectDatabaseError.corruptData("отсутствует заголовок проекта") }

        try database.rows("SELECT id, given_name, patronymic, family_name, maiden_name, gender, birth_date, death_date, is_deceased, birth_place, occupation, biography, photo_id, is_favorite FROM people ORDER BY sort_index") { row in
            guard let gender = Gender(rawValue: try row.text(5)) else { throw ProjectDatabaseError.corruptData("неизвестное значение пола") }
            project.people.append(Person(id: try row.uuid(0), givenName: try row.text(1), patronymic: try row.text(2), familyName: try row.text(3), maidenName: try row.text(4), gender: gender, birthDate: try row.text(6), deathDate: try row.text(7), isDeceased: try row.bool(8), birthPlace: try row.text(9), occupation: try row.text(10), biography: try row.text(11), photoID: try row.optionalUUID(12), isFavorite: try row.bool(13)))
        }
        try database.rows("SELECT id, from_id, to_id, kind FROM relationships ORDER BY sort_index") { row in
            guard let kind = RelationshipKind(rawValue: try row.text(3)) else { throw ProjectDatabaseError.corruptData("неизвестный вид связи") }
            project.relationships.append(Relationship(id: try row.uuid(0), fromID: try row.uuid(1), toID: try row.uuid(2), kind: kind))
        }
        try database.rows("SELECT id, person_id, kind, title, date, place, notes FROM events ORDER BY sort_index") { row in
            guard let kind = EventKind(rawValue: try row.text(2)) else { throw ProjectDatabaseError.corruptData("неизвестный вид события") }
            project.events.append(FamilyEvent(id: try row.uuid(0), personID: try row.uuid(1), kind: kind, title: try row.text(3), date: try row.text(4), place: try row.text(5), notes: try row.text(6)))
        }
        try database.rows("SELECT id, person_id, filename, mime_type, data, caption FROM attachments ORDER BY sort_index") { row in
            project.attachments.append(Attachment(id: try row.uuid(0), personID: try row.uuid(1), filename: try row.text(2), mimeType: try row.text(3), data: try row.blob(4), caption: try row.text(5)))
        }
        try ProjectValidation.validate(project)
        return project
    }

    public static func save(_ project: FamilyProject, to url: URL) throws {
        try ProjectValidation.validate(project)
        let manager = FileManager.default
        let exists = manager.fileExists(atPath: url.path)
        // Never replace an unknown, newer or corrupt document, even with otherwise valid data.
        if exists { _ = try load(from: url) }
        let directory = url.deletingLastPathComponent()
        let staging = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).saving")
        let backupStaging = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).backup-saving")
        defer {
            try? manager.removeItem(at: staging)
            try? manager.removeItem(at: backupStaging)
        }
        try write(project, to: staging)
        // Verify the finished document before touching the previous save.
        _ = try load(from: staging)
        if exists {
            // SQLite backup also includes any committed data still present in an external WAL.
            try Database.copySnapshot(from: url, to: backupStaging)
            try atomicRename(backupStaging, to: URL(fileURLWithPath: url.path + ".backup"))
        }
        try atomicRename(staging, to: url)
        // Persist directory entries after the atomic replacement where the filesystem supports it.
        let descriptor = open(directory.path, O_RDONLY)
        if descriptor >= 0 { _ = fsync(descriptor); _ = close(descriptor) }
    }

    private static func atomicRename(_ source: URL, to destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else {
            throw ProjectDatabaseError.fileOperation(String(cString: strerror(errno)))
        }
    }

    private static func write(_ project: FamilyProject, to url: URL) throws {
        let database = try Database(url: url, readOnly: false)
        try database.execute("PRAGMA journal_mode = DELETE")
        try database.execute("PRAGMA synchronous = FULL")
        try database.execute("PRAGMA foreign_keys = ON")
        try database.execute("BEGIN IMMEDIATE")
        do {
            try database.execute("PRAGMA application_id = \(applicationID)")
            try database.execute("PRAGMA user_version = \(FamilyProject.currentFormatVersion)")
            try database.execute("""
                CREATE TABLE project (
                    singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                    id TEXT NOT NULL, title TEXT NOT NULL, created_at REAL NOT NULL, modified_at REAL NOT NULL,
                    root_person_id TEXT, format_version INTEGER NOT NULL
                );
                CREATE TABLE people (
                    id TEXT PRIMARY KEY NOT NULL, sort_index INTEGER NOT NULL UNIQUE,
                    given_name TEXT NOT NULL, patronymic TEXT NOT NULL, family_name TEXT NOT NULL, maiden_name TEXT NOT NULL,
                    gender TEXT NOT NULL, birth_date TEXT NOT NULL, death_date TEXT NOT NULL,
                    is_deceased INTEGER NOT NULL CHECK(is_deceased IN (0,1)), birth_place TEXT NOT NULL,
                    occupation TEXT NOT NULL, biography TEXT NOT NULL, photo_id TEXT,
                    is_favorite INTEGER NOT NULL CHECK(is_favorite IN (0,1))
                );
                CREATE TABLE relationships (
                    id TEXT PRIMARY KEY NOT NULL, sort_index INTEGER NOT NULL UNIQUE,
                    from_id TEXT NOT NULL REFERENCES people(id), to_id TEXT NOT NULL REFERENCES people(id),
                    kind TEXT NOT NULL, CHECK(from_id <> to_id), UNIQUE(from_id, to_id, kind)
                );
                CREATE TABLE events (
                    id TEXT PRIMARY KEY NOT NULL, sort_index INTEGER NOT NULL UNIQUE, person_id TEXT NOT NULL REFERENCES people(id),
                    kind TEXT NOT NULL, title TEXT NOT NULL, date TEXT NOT NULL, place TEXT NOT NULL, notes TEXT NOT NULL
                );
                CREATE TABLE attachments (
                    id TEXT PRIMARY KEY NOT NULL, sort_index INTEGER NOT NULL UNIQUE, person_id TEXT NOT NULL REFERENCES people(id),
                    filename TEXT NOT NULL, mime_type TEXT NOT NULL, data BLOB NOT NULL, caption TEXT NOT NULL
                );
                CREATE INDEX relationships_to_id ON relationships(to_id);
                CREATE INDEX events_person_id ON events(person_id);
                CREATE INDEX attachments_person_id ON attachments(person_id);
                """)
            try database.run("INSERT INTO project VALUES (1, ?, ?, ?, ?, ?, ?)", [.uuid(project.id), .text(project.title), .real(project.createdAt.timeIntervalSinceReferenceDate), .real(project.modifiedAt.timeIntervalSinceReferenceDate), .optionalUUID(project.rootPersonID), .integer(project.formatVersion)])
            for (index, person) in project.people.enumerated() {
                try database.run("INSERT INTO people VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [.uuid(person.id), .integer(index), .text(person.givenName), .text(person.patronymic), .text(person.familyName), .text(person.maidenName), .text(person.gender.rawValue), .text(person.birthDate), .text(person.deathDate), .bool(person.isDeceased), .text(person.birthPlace), .text(person.occupation), .text(person.biography), .optionalUUID(person.photoID), .bool(person.isFavorite)])
            }
            for (index, edge) in project.relationships.enumerated() {
                try database.run("INSERT INTO relationships VALUES (?, ?, ?, ?, ?)", [.uuid(edge.id), .integer(index), .uuid(edge.fromID), .uuid(edge.toID), .text(edge.kind.rawValue)])
            }
            for (index, event) in project.events.enumerated() {
                try database.run("INSERT INTO events VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [.uuid(event.id), .integer(index), .uuid(event.personID), .text(event.kind.rawValue), .text(event.title), .text(event.date), .text(event.place), .text(event.notes)])
            }
            for (index, attachment) in project.attachments.enumerated() {
                try database.run("INSERT INTO attachments VALUES (?, ?, ?, ?, ?, ?, ?)", [.uuid(attachment.id), .integer(index), .uuid(attachment.personID), .text(attachment.filename), .text(attachment.mimeType), .blob(attachment.data), .text(attachment.caption)])
            }
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }
}

private enum Value {
    case text(String), integer(Int), real(Double), blob(Data), null
    static func uuid(_ id: UUID) -> Value { .text(id.uuidString) }
    static func optionalUUID(_ id: UUID?) -> Value { id.map { .uuid($0) } ?? .null }
    static func bool(_ value: Bool) -> Value { .integer(value ? 1 : 0) }
}

private final class Database {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, readOnly: Bool) throws {
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(url.path, &handle, flags, nil)
        if status != SQLITE_OK {
            let error = failure()
            sqlite3_close(handle)
            handle = nil
            throw error
        }
        sqlite3_busy_timeout(handle, 3_000)
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    func integer(_ sql: String) throws -> Int {
        var result: Int?
        try rows(sql) { result = try $0.integer(0) }
        guard let result else { throw ProjectDatabaseError.corruptData("отсутствует значение метаданных") }
        return result
    }

    func run(_ sql: String, _ values: [Value]) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .text(let value):
                guard value.utf8.count <= Int(Int32.max) else { throw ProjectDatabaseError.corruptData("слишком длинный текст") }
                status = value.withCString { sqlite3_bind_text(statement, index, $0, Int32(value.utf8.count), transient) }
            case .integer(let value): status = sqlite3_bind_int64(statement, index, Int64(value))
            case .real(let value): status = sqlite3_bind_double(statement, index, value)
            case .blob(let value):
                guard value.count <= Int(Int32.max) else { throw ProjectDatabaseError.corruptData("вложение превышает допустимый размер") }
                if value.isEmpty {
                    // Binding a nil pointer would store SQL NULL, not an empty BLOB.
                    status = sqlite3_bind_zeroblob(statement, index, 0)
                } else {
                    status = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), transient) }
                }
            case .null: status = sqlite3_bind_null(statement, index)
            }
            guard status == SQLITE_OK else { throw failure() }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func rows(_ sql: String, body: (Row) throws -> Void) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return }
            guard status == SQLITE_ROW else { throw failure() }
            try body(Row(statement: statement))
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        return statement
    }

    private func failure() -> ProjectDatabaseError {
        .sqlite(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "не удалось открыть файл")
    }

    static func copySnapshot(from source: URL, to destination: URL) throws {
        let original = try Database(url: source, readOnly: true)
        let copy = try Database(url: destination, readOnly: false)
        try copy.execute("PRAGMA synchronous = FULL")
        guard let backup = sqlite3_backup_init(copy.handle, "main", original.handle, "main") else { throw copy.failure() }
        let status = sqlite3_backup_step(backup, -1)
        let finishStatus = sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE, finishStatus == SQLITE_OK else { throw copy.failure() }
    }
}

private struct Row {
    let statement: OpaquePointer

    func text(_ column: Int32) throws -> String {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              let pointer = sqlite3_column_text(statement, column) else { throw invalidColumn(column) }
        let bytes = UnsafeBufferPointer(start: pointer, count: Int(sqlite3_column_bytes(statement, column)))
        guard let value = String(bytes: bytes, encoding: .utf8) else { throw invalidColumn(column) }
        return value
    }
    func uuid(_ column: Int32) throws -> UUID {
        guard let value = UUID(uuidString: try text(column)) else { throw invalidColumn(column) }
        return value
    }
    func optionalUUID(_ column: Int32) throws -> UUID? {
        if sqlite3_column_type(statement, column) == SQLITE_NULL { return nil }
        return try uuid(column)
    }
    func integer(_ column: Int32) throws -> Int {
        guard sqlite3_column_type(statement, column) == SQLITE_INTEGER else { throw invalidColumn(column) }
        return Int(sqlite3_column_int64(statement, column))
    }
    func bool(_ column: Int32) throws -> Bool {
        let value = try integer(column)
        guard value == 0 || value == 1 else { throw invalidColumn(column) }
        return value == 1
    }
    func real(_ column: Int32) throws -> Double {
        let type = sqlite3_column_type(statement, column)
        guard type == SQLITE_FLOAT || type == SQLITE_INTEGER else { throw invalidColumn(column) }
        let value = sqlite3_column_double(statement, column)
        guard value.isFinite else { throw invalidColumn(column) }
        return value
    }
    func blob(_ column: Int32) throws -> Data {
        guard sqlite3_column_type(statement, column) == SQLITE_BLOB else { throw invalidColumn(column) }
        let count = Int(sqlite3_column_bytes(statement, column))
        if count == 0 { return Data() }
        guard let pointer = sqlite3_column_blob(statement, column) else { throw invalidColumn(column) }
        return Data(bytes: pointer, count: count)
    }
    private func invalidColumn(_ column: Int32) -> ProjectDatabaseError {
        .corruptData("недопустимое значение в поле \(String(cString: sqlite3_column_name(statement, column)))")
    }
}
