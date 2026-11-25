import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct TreeLibraryEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let url: URL
    public let title: String
    public let peopleCount: Int
    public let modifiedAt: Date
    public let issue: String?

    public init(url: URL, title: String, peopleCount: Int, modifiedAt: Date, issue: String? = nil) {
        let canonical = url.isFileURL ? url.standardizedFileURL.resolvingSymlinksInPath() : url
        self.url = canonical
        self.id = canonical.isFileURL ? canonical.path : canonical.absoluteString
        self.title = TreeLibrary.displayTitle(title)
        self.peopleCount = peopleCount
        self.modifiedAt = modifiedAt
        self.issue = issue
    }
}

public enum TreeLibraryError: LocalizedError {
    case invalidLocation, unavailable, alreadyExists

    public var errorDescription: String? {
        switch self {
        case .invalidLocation: return "Для библиотеки нужна локальная папка."
        case .unavailable: return "Не удалось открыть папку библиотеки или создать в ней дерево. Проверьте доступ к папке."
        case .alreadyExists: return "Это дерево уже есть в библиотеке. Для отдельной копии создайте новое дерево."
        }
    }
}

/// Managed documents and explicitly remembered external documents form the library.
/// Listing is read-only; there is no index to become out of sync with the files.
public struct TreeLibrary: Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL.isFileURL ? directoryURL.standardizedFileURL.resolvingSymlinksInPath() : directoryURL
    }

    /// Hides only the known export-generated title. A user's title is never rewritten on disk.
    public static func displayTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Моя семья" }
        let generated = #"(?i)^famytale_\d+_\d{4}-\d{2}-\d{2}T[0-9:_.-]+Z(?:\.ged)?$"#
        return trimmed.range(of: generated, options: .regularExpression) == nil ? trimmed : "Моя семья"
    }

    public func entries(additionalURLs: [URL] = []) throws -> [TreeLibraryEntry] {
        guard directoryURL.isFileURL else { throw TreeLibraryError.invalidLocation }
        let manager = FileManager.default
        var urls = additionalURLs
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw TreeLibraryError.unavailable }
            do {
                urls += try manager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles])
                    .filter { $0.pathExtension.lowercased() == "familytree" }
            } catch { throw TreeLibraryError.unavailable }
        }
        var seen = Set<String>()
        return urls.compactMap { url -> TreeLibraryEntry? in
            let canonical = url.isFileURL ? url.standardizedFileURL.resolvingSymlinksInPath() : url
            let identifier = canonical.isFileURL ? canonical.path : canonical.absoluteString
            guard seen.insert(identifier).inserted else { return nil }
            guard canonical.isFileURL else {
                return TreeLibraryEntry(url: canonical, title: "Недоступное дерево", peopleCount: 0,
                                        modifiedAt: .distantPast, issue: "Ожидается локальный файл дерева.")
            }
            do {
                let summary = try ProjectDatabase.librarySummary(from: canonical)
                return TreeLibraryEntry(url: canonical, title: summary.title, peopleCount: summary.peopleCount,
                                        modifiedAt: summary.modifiedAt)
            } catch {
                let issue: String
                if !manager.fileExists(atPath: canonical.path) {
                    issue = "Дерево не найдено или к нему нет доступа."
                } else if let validation = error as? ProjectValidationError,
                          case .unsupportedVersion = validation {
                    issue = validation.localizedDescription
                } else {
                    issue = "Не удалось прочитать дерево. Возможно, оно повреждено или недоступно."
                }
                return TreeLibraryEntry(url: canonical, title: "Недоступное дерево", peopleCount: 0,
                                        modifiedAt: .distantPast, issue: issue)
            }
        }.sorted {
            if ($0.issue == nil) != ($1.issue == nil) { return $0.issue == nil }
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// Creates a complete document under its project UUID. Publishing with a hard
    /// link is atomic and fails if the target exists, including a concurrent create.
    /// The temporary directory is reserved with mkdtemp on the same filesystem.
    public func create(_ project: FamilyProject) throws -> URL {
        guard directoryURL.isFileURL else { throw TreeLibraryError.invalidLocation }
        try ProjectValidation.validate(project)
        let manager = FileManager.default
        do { try manager.createDirectory(at: directoryURL, withIntermediateDirectories: true) }
        catch { throw TreeLibraryError.unavailable }
        let destination = directoryURL.appendingPathComponent(project.id.uuidString + ".familytree")
        guard !manager.fileExists(atPath: destination.path) else { throw TreeLibraryError.alreadyExists }
        var template = Array(directoryURL.appendingPathComponent(".creating-XXXXXX").path.utf8CString)
        let temporaryPath = template.withUnsafeMutableBufferPointer { buffer -> String? in
            guard let path = mkdtemp(buffer.baseAddress!) else { return nil }
            return String(cString: path)
        }
        guard let temporaryPath else { throw TreeLibraryError.unavailable }
        let temporaryDirectory = URL(fileURLWithPath: temporaryPath, isDirectory: true)
        defer { try? manager.removeItem(at: temporaryDirectory) }
        let staged = temporaryDirectory.appendingPathComponent("document.familytree")
        try ProjectDatabase.save(project, to: staged)
        do { try manager.linkItem(at: staged, to: destination) }
        catch {
            if manager.fileExists(atPath: destination.path) { throw TreeLibraryError.alreadyExists }
            throw TreeLibraryError.unavailable
        }
        let descriptor = open(directoryURL.path, O_RDONLY)
        if descriptor >= 0 { _ = fsync(descriptor); _ = close(descriptor) }
        return destination
    }
}
