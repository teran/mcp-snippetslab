@preconcurrency import Foundation

// MARK: - JSON models for the backup library

public struct SnippetsLabLibraryJSON: Codable, Sendable {
    public let app: String
    public let name: String
    public let schema: String
    public let date: String
    public let contents: SnippetsLabContents
}

public struct SnippetsLabContents: Codable, Sendable {
    public let folders: [SnippetsLabFolderItem]
    public let tags: [SnippetsLabTagItemJSON]
    public let snippets: [SnippetsLabSnippet]
    public let attachments: [String]
}

public struct SnippetsLabFolderItem: Codable, Sendable, Identifiable {
    public let title: String
    public let uuid: String
    public var id: String { uuid }
}

public struct SnippetsLabTagItemJSON: Codable, Sendable, Identifiable {
    public let title: String
    public let uuid: String
    public var id: String { uuid }
}

public struct SnippetsLabSnippet: Codable, Sendable, Identifiable {
    public let title: String?
    public let uuid: String
    public let folder: String?
    public let tags: [String]?
    public let dateCreated: String?
    public let dateModified: String?
    public let dateDeleted: String?
    public let fragments: [SnippetsLabFragment]?

    public var id: String { uuid }
}

public struct SnippetsLabFragment: Codable, Sendable {
    public let title: String?
    public let note: String?
    public let content: String?
    public let language: String?
    public let uuid: String?
    public let dateCreated: String?
    public let dateModified: String?
}

// MARK: - Conversion helpers

extension SnippetsLabSnippet {
    func toSnippet() -> Snippet {
        Snippet(
            title: title,
            uuid: uuid,
            folder: folder,
            tags: tags,
            dateCreated: dateCreated,
            dateModified: dateModified,
            dateDeleted: dateDeleted,
            fragments: fragments?.map { $0.toFragment() }
        )
    }
}

extension SnippetsLabFragment {
    func toFragment() -> Fragment {
        Fragment(
            title: title,
            note: note,
            content: content,
            language: language,
            uuid: uuid,
            dateCreated: dateCreated,
            dateModified: dateModified
        )
    }
}

// MARK: - Thread-safe Cache

private final class Cache: @unchecked Sendable {
    private let lock = NSLock()
    private var data: SnippetsLabLibraryJSON?
    private var lastRefreshed: Date?

    func get(ttl: TimeInterval) -> SnippetsLabLibraryJSON? {
        lock.withLock {
            guard let data, let lastRefreshed else { return nil }
            guard Date().timeIntervalSince(lastRefreshed) < ttl else { return nil }
            return data
        }
    }

    func set(_ data: SnippetsLabLibraryJSON) {
        lock.withLock {
            self.data = data
            self.lastRefreshed = Date()
        }
    }
}

// MARK: - Backup Snippet Repository

/// Reads SnippetsLab data from the backup's library.json (pure JSON, always available).
public final class BackupSnippetRepository: SnippetRepository {

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case libraryNotFound(String)
        case decodeFailed(String)
        case notFound(String)

        public var errorDescription: String? {
            switch self {
            case .libraryNotFound(let path):
                return "SnippetsLab library not found at: \(path)"
            case .decodeFailed(let detail):
                return "Failed to decode SnippetsLab data: \(detail)"
            case .notFound(let detail):
                return "Not found: \(detail)"
            }
        }
    }

    private let backupsDir: String
    private let liveLibraryPath: String
    nonisolated(unsafe) private let fileManager: FileManager
    private let cache: Cache
    private let cacheTTL: TimeInterval

    public init(
        backupsDir: String? = nil,
        fileManager: FileManager = .default,
        cacheTTL: TimeInterval = 60
    ) {
        self.fileManager = fileManager
        self.backupsDir = backupsDir ?? Self._defaultBackupsDir(fileManager: fileManager)
        self.cacheTTL = cacheTTL
        self.cache = Cache()

        let home = fileManager.homeDirectoryForCurrentUser.path
        self.liveLibraryPath = "\(home)/Library/Mobile Documents/iCloud~com~renfei~SnippetsLab/main.snippetslablibrary"
    }

    private static func _defaultBackupsDir(fileManager: FileManager) -> String {
        let home = fileManager.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Containers/com.renfei.SnippetsLab/Data/Library/Application Support/Backups"
    }

    // MARK: - Backup-based reading

    /// Find the latest backup's library.json path
    private func latestLibraryPath() throws -> String {
        let contents = try fileManager.contentsOfDirectory(atPath: backupsDir)
        let backupDirs = contents.filter { $0.hasSuffix(".snippetslab-backup") }
            .sorted(by: >) // newest first

        guard let latest = backupDirs.first else {
            throw Error.libraryNotFound("No backups found in \(backupsDir)")
        }

        return "\(backupsDir)/\(latest)/library.json"
    }

    /// Read the full library from the latest backup (uses cache)
    private func readLibraryJSON() throws -> SnippetsLabLibraryJSON {
        if let cached = cache.get(ttl: cacheTTL) {
            return cached
        }

        let path = try latestLibraryPath()
        guard fileManager.fileExists(atPath: path) else {
            throw Error.libraryNotFound(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        let lib: SnippetsLabLibraryJSON
        do {
            lib = try decoder.decode(SnippetsLabLibraryJSON.self, from: data)
        } catch {
            throw Error.decodeFailed(error.localizedDescription)
        }
        cache.set(lib)
        return lib
    }

    // MARK: - SnippetRepository conformance

    public func readFolders() throws -> [Folder] {
        let lib = try readLibraryJSON()
        return lib.contents.folders.map { Folder(title: $0.title, uuid: $0.uuid) }
    }

    public func readTags() throws -> [Tag] {
        let lib = try readLibraryJSON()
        return lib.contents.tags.map { Tag(title: $0.title, uuid: $0.uuid) }
    }

    public func readSnippetSummaries() throws -> [Snippet] {
        let lib = try readLibraryJSON()
        return lib.contents.snippets
            .sorted { ($0.dateModified ?? "") > ($1.dateModified ?? "") }
            .map { $0.toSnippet() }
    }

    public func readSnippet(uuid: String) throws -> Snippet {
        let lib = try readLibraryJSON()
        guard let snippet = lib.contents.snippets.first(where: { $0.uuid == uuid }) else {
            throw Error.notFound("Snippet \(uuid) not found")
        }
        return snippet.toSnippet()
    }

    /// Search snippets by title or content.
    /// - Parameter query: Search string. An empty string returns all snippets unsorted.
    public func searchSnippets(query: String) throws -> [Snippet] {
        let lib = try readLibraryJSON()
        let snippets = lib.contents.snippets
        guard !query.isEmpty else {
            return snippets.map { $0.toSnippet() }
        }

        let lowerQuery = query.lowercased()
        let results = snippets.filter { s in
            // Search in title
            if let title = s.title?.lowercased(), title.contains(lowerQuery) {
                return true
            }
            // Search in content
            let allContent = s.fragments?
                .compactMap { $0.content }
                .joined(separator: " ")
                .lowercased() ?? ""
            return allContent.contains(lowerQuery)
        }
        return results
            .sorted { ($0.dateModified ?? "") > ($1.dateModified ?? "") }
            .map { $0.toSnippet() }
    }

    public func createSnippet(
        title: String,
        content: String,
        language: String?,
        folderUUID: String?,
        tagUUIDs: [String],
        note: String?
    ) throws -> String {
        throw Error.libraryNotFound("createSnippet is not supported by BackupSnippetRepository (read-only)")
    }
}
