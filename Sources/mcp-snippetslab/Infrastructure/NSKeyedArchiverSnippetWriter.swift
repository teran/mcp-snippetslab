import Foundation

// MARK: - Key constants for NSKeyedArchiver (used for writing)

public enum SnippetsLabKey {
    public static let snippetTitle = "com.renfei.SnippetsLab.Key.SnippetTitle"
    public static let snippetUUID = "com.renfei.SnippetsLab.Key.SnippetUUID"
    public static let snippetParts = "com.renfei.SnippetsLab.Key.SnippetParts"
    public static let snippetFolderUUID = "com.renfei.SnippetsLab.Key.SnippetFolderUUID"
    public static let snippetTagUUIDs = "com.renfei.SnippetsLab.Key.SnippetTagUUIDs"
    public static let snippetDateCreated = "com.renfei.SnippetsLab.Key.SnippetDateCreated"
    public static let snippetDateModified = "com.renfei.SnippetsLab.Key.SnippetDateModified"
    public static let snippetDateDeleted = "com.renfei.SnippetsLab.Key.DateDeleted"
    public static let pinned = "com.renfei.SnippetsLab.Key.Pinned"
    public static let locked = "com.renfei.SnippetsLab.Key.Locked"

    public static let partTitle = "com.renfei.SnippetsLab.Key.SnippetPartTitle"
    public static let partContent = "com.renfei.SnippetsLab.Key.SnippetPartContent"
    public static let partUUID = "com.renfei.SnippetsLab.Key.SnippetPartUUID"
    public static let partLanguage = "com.renfei.SnippetsLab.Key.SnippetPartLanguage"
    public static let partNote = "com.renfei.SnippetsLab.Key.SnippetPartNote"
    public static let partNoteAttributes = "com.renfei.SnippetsLab.Key.SnippetPartNotesAttributes"
    public static let partAttachments = "com.renfei.SnippetsLab.Key.SnippetPartAttachments"
    public static let partDateCreated = "com.renfei.SnippetsLab.Key.SnippetPartDateCreated"
    public static let partDateModified = "com.renfei.SnippetsLab.Key.SnippetPartDateModified"
    public static let partSnippetUUID = "com.renfei.SnippetsLab.Key.SnippetPartSnippetUUID"
}

/// Creates new snippets in the live SnippetsLab iCloud library
/// using Foundation's NSKeyedArchiver.
///
/// Two initialization modes:
/// - **Default (no args)**: writes to the live iCloud library at
///   `~/Library/Mobile Documents/iCloud~com~renfei~SnippetsLab/main.snippetslablibrary/Database/Snippets/`
/// - **Custom `snippetsDir`**: writes `.data` files directly to the given directory.
///   The parent directory must already exist.
public final class NSKeyedArchiverSnippetWriter: Sendable {

    public enum Error: Swift.Error, LocalizedError, Equatable {
        /// The library directory does not exist at the given path.
        case libraryNotWritable(String)
    }

    private let snippetsDir: String
    private let libraryPath: String?

    private static var defaultLibraryPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Mobile Documents/iCloud~com~renfei~SnippetsLab/main.snippetslablibrary"
    }

    /// - Parameters:
    ///   - libraryPath: Path to the `.snippetslablibrary` bundle.
    ///     Used when `snippetsDir` is `nil`. Defaults to the live iCloud library.
    ///   - snippetsDir: Explicit path to a `Database/Snippets` directory.
    ///     When provided, `libraryPath` is ignored and files are written directly here.
    ///     The parent directory must already exist for validation to pass.
    public init(libraryPath: String? = nil, snippetsDir: String? = nil) {
        if let snippetsDir {
            self.snippetsDir = snippetsDir
            self.libraryPath = nil
        } else {
            let path = libraryPath ?? Self.defaultLibraryPath
            self.libraryPath = path
            self.snippetsDir = "\(path)/Database/Snippets"
        }
    }

    /// Create a new snippet in the iCloud library.
    /// Returns the generated UUID of the created snippet.
    @discardableResult
    public func createSnippet(
        title: String,
        content: String,
        language: String? = nil,
        folderUUID: String? = nil,
        tagUUIDs: [String] = [],
        note: String? = nil
    ) throws -> String {
        if let libraryPath {
            guard FileManager.default.fileExists(atPath: libraryPath) else {
                throw Error.libraryNotWritable(libraryPath)
            }
        } else {
            let parentDir = (snippetsDir as NSString).deletingLastPathComponent
            guard FileManager.default.fileExists(atPath: parentDir) else {
                throw Error.libraryNotWritable(snippetsDir)
            }
        }

        // Ensure snippets directory exists
        if !FileManager.default.fileExists(atPath: snippetsDir) {
            try FileManager.default.createDirectory(
                atPath: snippetsDir,
                withIntermediateDirectories: true
            )
        }

        let snippetUUID = UUID().uuidString
        let partUUID = UUID().uuidString
        let now = Date()

        // Build the snippet as an NSKeyedArchiver-compatible dictionary
        let snippet: NSDictionary = buildSnippetDict(
            title: title,
            uuid: snippetUUID,
            folderUUID: folderUUID,
            tagUUIDs: tagUUIDs,
            now: now,
            partUUID: partUUID,
            content: content,
            language: language,
            note: note
        )

        // Archive using NSKeyedArchiver
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: snippet,
            requiringSecureCoding: false
        )

        let outputPath = "\(snippetsDir)/\(snippetUUID).data"
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)

        return snippetUUID
    }

    // MARK: - Private

    private func buildSnippetDict(
        title: String,
        uuid: String,
        folderUUID: String?,
        tagUUIDs: [String],
        now: Date,
        partUUID: String,
        content: String,
        language: String?,
        note: String?
    ) -> NSDictionary {
        let part = createPartDict(
            title: "Fragment",
            content: content,
            language: language,
            note: note,
            partUUID: partUUID,
            snippetUUID: uuid,
            now: now
        )

        let tagArray = tagUUIDs.isEmpty
            ? NSArray()
            : tagUUIDs as NSArray

        let folderValue: Any = folderUUID.map { $0 as Any } ?? NSNull()

        return [
            SnippetsLabKey.snippetTitle: title,
            SnippetsLabKey.snippetUUID: uuid,
            SnippetsLabKey.snippetDateCreated: now,
            SnippetsLabKey.snippetDateModified: now,
            SnippetsLabKey.snippetDateDeleted: NSNull(),
            SnippetsLabKey.pinned: false,
            SnippetsLabKey.locked: false,
            SnippetsLabKey.snippetParts: [part] as NSArray,
            SnippetsLabKey.snippetFolderUUID: folderValue,
            SnippetsLabKey.snippetTagUUIDs: tagArray,
            "com.renfei.SnippetsLab.Key.GistIdentifier": NSNull(),
            "com.renfei.SnippetsLab.Key.GitHubHTMLURL": NSNull(),
            "com.renfei.SnippetsLab.Key.GitHubUsername": NSNull()
        ]
    }

    private func createPartDict(
        title: String,
        content: String,
        language: String?,
        note: String?,
        partUUID: String,
        snippetUUID: String,
        now: Date
    ) -> NSDictionary {
        let noteData = (note ?? "").data(using: .utf8) ?? Data()
        let emptyData = Data()

        return [
            SnippetsLabKey.partTitle: title,
            SnippetsLabKey.partUUID: partUUID,
            SnippetsLabKey.partContent: content,
            SnippetsLabKey.partLanguage: language.map { $0 as Any } ?? NSNull(),
            SnippetsLabKey.partNote: noteData,
            SnippetsLabKey.partNoteAttributes: emptyData,
            SnippetsLabKey.partSnippetUUID: snippetUUID,
            SnippetsLabKey.partDateCreated: now,
            SnippetsLabKey.partDateModified: now,
            SnippetsLabKey.partAttachments: NSArray()
        ]
    }
}
