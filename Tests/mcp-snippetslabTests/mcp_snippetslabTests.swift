import Testing
import Foundation
@testable import mcp_snippetslab
import MCP

// MARK: - Helpers

/// Create a temporary directory for test isolation and return its path.
/// The caller is responsible for cleaning it up.
private func makeTempDir() throws -> String {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .path
    try FileManager.default.createDirectory(
        atPath: tempDir,
        withIntermediateDirectories: true
    )
    return tempDir
}

/// Decode a `.data` file written by NSKeyedArchiverSnippetWriter back into a dictionary.
/// Uses `requiresSecureCoding = false` — the same mode used by NSKeyedArchiver
/// when the file was written, and what the real SnippetsLab app would need.
private func decodeSnippetArchive(at path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let coder = try NSKeyedUnarchiver(forReadingFrom: data)
    coder.requiresSecureCoding = false
    guard let dict = coder.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [String: Any] else {
        struct DecodeError: Swift.Error, CustomStringConvertible {
            let description: String
        }
        throw DecodeError(description: "Could not decode archive root at \(path)")
    }
    return dict
}

/// Returns the first part from a decoded snippet dictionary.
private func firstPart(from dict: [String: Any]) -> [String: Any]? {
    guard let parts = dict[SnippetsLabKey.snippetParts] as? [Any],
          let first = parts.first as? [String: Any]
    else {
        return nil
    }
    return first
}

// MARK: - Tests

struct NSKeyedArchiverSnippetWriterTests {

    // MARK: - createSnippet minimal

    @Test("Create snippet with only title and content")
    func testCreateSnippetMinimal() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let writer = NSKeyedArchiverSnippetWriter(snippetsDir: tempDir)
        let uuid = try writer.createSnippet(title: "Test Snippet", content: "Hello, World!")

        // Verify file exists at the expected path
        let filePath = "\(tempDir)/\(uuid).data"
        #expect(FileManager.default.fileExists(atPath: filePath))

        // Read back and verify title and content
        let dict = try decodeSnippetArchive(at: filePath)
        #expect(dict.keys.contains(SnippetsLabKey.snippetTitle))
        #expect(dict[SnippetsLabKey.snippetTitle] as? String == "Test Snippet")

        let part = try #require(firstPart(from: dict))
        #expect(part[SnippetsLabKey.partContent] as? String == "Hello, World!")
        #expect(part[SnippetsLabKey.partTitle] as? String == "Fragment")
    }

    // MARK: - createSnippet with all options

    @Test("Create snippet with language, folderUUID, tags, and note")
    func testCreateSnippetWithAllOptions() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let writer = NSKeyedArchiverSnippetWriter(snippetsDir: tempDir)
        let uuid = try writer.createSnippet(
            title: "Full Snippet",
            content: "let x = 42",
            language: "swift",
            folderUUID: "folder-uuid-123",
            tagUUIDs: ["tag-1", "tag-2"],
            note: "This is a note"
        )

        let filePath = "\(tempDir)/\(uuid).data"
        #expect(FileManager.default.fileExists(atPath: filePath))

        let dict = try decodeSnippetArchive(at: filePath)

        // Check top-level fields
        #expect(dict[SnippetsLabKey.snippetTitle] as? String == "Full Snippet")
        #expect(dict[SnippetsLabKey.snippetUUID] as? String == uuid)

        // Check folder
        #expect(dict[SnippetsLabKey.snippetFolderUUID] as? String == "folder-uuid-123")

        // Check tags
        let tags = dict[SnippetsLabKey.snippetTagUUIDs] as? [String]
        #expect(tags == ["tag-1", "tag-2"])

        // Check pinned/locked defaults
        #expect(dict[SnippetsLabKey.pinned] as? Bool == false)
        #expect(dict[SnippetsLabKey.locked] as? Bool == false)

        // Check part
        let part = try #require(firstPart(from: dict))
        #expect(part[SnippetsLabKey.partUUID] is String)
        #expect(part[SnippetsLabKey.partContent] as? String == "let x = 42")
        #expect(part[SnippetsLabKey.partLanguage] as? String == "swift")
        #expect(part[SnippetsLabKey.partSnippetUUID] as? String == uuid)

        // Note is stored as Data (utf8 encoded)
        let noteData = part[SnippetsLabKey.partNote] as? Data
        let noteString = noteData.flatMap { String(data: $0, encoding: .utf8) }
        #expect(noteString == "This is a note")
    }

    // MARK: - libraryNotWritable error

    @Test("Create snippet when directory is not writable throws libraryNotWritable")
    func testCreateSnippetLibraryNotWritable() throws {
        let nonexistentDir = "/nonexistent_path_for_testing_\(UUID().uuidString)/snippets"
        let writer = NSKeyedArchiverSnippetWriter(snippetsDir: nonexistentDir)

        #expect(throws: NSKeyedArchiverSnippetWriter.Error.libraryNotWritable(nonexistentDir)) {
            try writer.createSnippet(title: "Fail", content: "x")
        }
    }

    // MARK: - buildSnippetDict structure

    @Test("Archived snippet dictionary contains all expected keys")
    func testBuildSnippetDictStructure() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let writer = NSKeyedArchiverSnippetWriter(snippetsDir: tempDir)
        let uuid = try writer.createSnippet(
            title: "Struct Test",
            content: "print(\"hello\")",
            language: "python",
            folderUUID: "f-1",
            tagUUIDs: ["t-1"],
            note: "my note"
        )

        let filePath = "\(tempDir)/\(uuid).data"
        let dict = try decodeSnippetArchive(at: filePath)

        // All expected top-level keys
        #expect(dict[SnippetsLabKey.snippetTitle] is String)
        #expect(dict[SnippetsLabKey.snippetUUID] is String)
        #expect(dict[SnippetsLabKey.snippetDateCreated] is Date)
        #expect(dict[SnippetsLabKey.snippetDateModified] is Date)
        #expect(dict[SnippetsLabKey.snippetDateDeleted] is NSNull)
        #expect(dict[SnippetsLabKey.pinned] is Bool)
        #expect(dict[SnippetsLabKey.locked] is Bool)
        #expect(dict[SnippetsLabKey.snippetParts] is [Any])
        #expect(dict[SnippetsLabKey.snippetFolderUUID] is String)
        #expect(dict[SnippetsLabKey.snippetTagUUIDs] is [String])

        // Gist/GitHub keys
        #expect(dict["com.renfei.SnippetsLab.Key.GistIdentifier"] is NSNull)
        #expect(dict["com.renfei.SnippetsLab.Key.GitHubHTMLURL"] is NSNull)
        #expect(dict["com.renfei.SnippetsLab.Key.GitHubUsername"] is NSNull)

        // Part-level keys
        let part = try #require(firstPart(from: dict))
        #expect(part[SnippetsLabKey.partTitle] is String)
        #expect(part[SnippetsLabKey.partUUID] is String)
        #expect(part[SnippetsLabKey.partContent] is String)
        #expect(part[SnippetsLabKey.partLanguage] is String)
        #expect(part[SnippetsLabKey.partNote] is Data)
        #expect(part[SnippetsLabKey.partNoteAttributes] is Data)
        #expect(part[SnippetsLabKey.partSnippetUUID] is String)
        #expect(part[SnippetsLabKey.partDateCreated] is Date)
        #expect(part[SnippetsLabKey.partDateModified] is Date)
        #expect(part[SnippetsLabKey.partAttachments] is [Any])
    }

    // MARK: - Multiple snippets

    @Test("Create multiple snippets with unique UUIDs and files")
    func testMultipleSnippets() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let writer = NSKeyedArchiverSnippetWriter(snippetsDir: tempDir)

        let uuid1 = try writer.createSnippet(title: "First", content: "one")
        let uuid2 = try writer.createSnippet(title: "Second", content: "two")

        // UUIDs must be unique
        #expect(uuid1 != uuid2)

        // Both files must exist
        let file1 = "\(tempDir)/\(uuid1).data"
        let file2 = "\(tempDir)/\(uuid2).data"
        #expect(FileManager.default.fileExists(atPath: file1))
        #expect(FileManager.default.fileExists(atPath: file2))

        // Each file must decode correctly
        let dict1 = try decodeSnippetArchive(at: file1)
        let dict2 = try decodeSnippetArchive(at: file2)
        #expect(dict1[SnippetsLabKey.snippetTitle] as? String == "First")
        #expect(dict2[SnippetsLabKey.snippetTitle] as? String == "Second")
    }

    // MARK: - NSKeyedUnarchiver round-trip

    @Test("Archived data can be read back with requiresSecureCoding=false")
    func testArchiveRoundTrip() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let writer = NSKeyedArchiverSnippetWriter(snippetsDir: tempDir)
        let uuid = try writer.createSnippet(
            title: "Round-trip",
            content: "fn main() {}",
            language: "rust",
            folderUUID: "folder-x",
            tagUUIDs: ["tag-a", "tag-b"],
            note: "rustacean"
        )

        let filePath = "\(tempDir)/\(uuid).data"

        // Read raw data and unarchive with requiresSecureCoding=false
        let rawData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let coder = try NSKeyedUnarchiver(forReadingFrom: rawData)
        coder.requiresSecureCoding = false
        let root = coder.decodeObject(forKey: NSKeyedArchiveRootObjectKey)

        // Must be a dictionary
        let dict = try #require(root as? [String: Any])

        // Verify all primary fields survived the round-trip
        #expect(dict[SnippetsLabKey.snippetTitle] as? String == "Round-trip")
        #expect(dict[SnippetsLabKey.snippetUUID] as? String == uuid)
        #expect(dict[SnippetsLabKey.snippetFolderUUID] as? String == "folder-x")

        let tags = dict[SnippetsLabKey.snippetTagUUIDs] as? [String]
        #expect(tags == ["tag-a", "tag-b"])

        let part = try #require(firstPart(from: dict))
        #expect(part[SnippetsLabKey.partContent] as? String == "fn main() {}")
        #expect(part[SnippetsLabKey.partLanguage] as? String == "rust")

        let noteData = part[SnippetsLabKey.partNote] as? Data
        let noteString = noteData.flatMap { String(data: $0, encoding: .utf8) }
        #expect(noteString == "rustacean")

        // Dates must survive the round-trip
        #expect(dict[SnippetsLabKey.snippetDateCreated] is Date)
        #expect(dict[SnippetsLabKey.snippetDateModified] is Date)
    }
}

// MARK: - Fixture helpers for BackupSnippetRepository

/// Convenience types for building test fixture data.
struct FixtureFolder {
    let title: String
    let uuid: String
}

struct FixtureTag {
    let title: String
    let uuid: String
}

struct FixtureFragment {
    let title: String?
    let content: String?
    let language: String?
}

struct FixtureSnippet {
    let title: String?
    let uuid: String
    let folder: String?
    let tags: [String]?
    let dateCreated: String?
    let dateModified: String?
    let fragments: [FixtureFragment]?
}

/// Create a temporary `BackupSnippetRepository` seeded with known fixture data.
/// Returns the repository instance and a cleanup closure.
private func createFixtureRepository(
    snippets: [FixtureSnippet] = [],
    folders: [FixtureFolder] = [],
    tags: [FixtureTag] = []
) -> (repository: BackupSnippetRepository, cleanup: () -> Void) {
    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .path
    try! fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

    let backupDirName = "test-fixture.snippetslab-backup"
    let backupDir = "\(tempDir)/\(backupDirName)"
    try! fm.createDirectory(atPath: backupDir, withIntermediateDirectories: true)

    // Convert fixtures to real types
    let realFolders = folders.map { SnippetsLabFolderItem(title: $0.title, uuid: $0.uuid) }
    let realTags = tags.map { SnippetsLabTagItemJSON(title: $0.title, uuid: $0.uuid) }
    let realSnippets = snippets.map { snippet in
        SnippetsLabSnippet(
            title: snippet.title,
            uuid: snippet.uuid,
            folder: snippet.folder,
            tags: snippet.tags,
            dateCreated: snippet.dateCreated,
            dateModified: snippet.dateModified,
            dateDeleted: nil,
            fragments: snippet.fragments?.map { frag in
                SnippetsLabFragment(
                    title: frag.title,
                    note: nil,
                    content: frag.content,
                    language: frag.language,
                    uuid: UUID().uuidString,
                    dateCreated: nil,
                    dateModified: nil
                )
            }
        )
    }

    let libraryJSON = SnippetsLabLibraryJSON(
        app: "SnippetsLab Test",
        name: "Test Library",
        schema: "1.0",
        date: "2025-01-01T00:00:00Z",
        contents: SnippetsLabContents(
            folders: realFolders,
            tags: realTags,
            snippets: realSnippets,
            attachments: []
        )
    )

    let jsonData = try! JSONEncoder().encode(libraryJSON)
    try! jsonData.write(to: URL(fileURLWithPath: "\(backupDir)/library.json"))

    let repository = BackupSnippetRepository(backupsDir: tempDir, fileManager: fm)

    return (repository, { try? fm.removeItem(atPath: tempDir) })
}

// MARK: - BackupSnippetRepository Tests

struct BackupSnippetRepositoryTests {

    // MARK: - testReadFoldersFromFixture

    @Test("Read folders from fixture")
    func testReadFoldersFromFixture() throws {
        let (repo, cleanup) = createFixtureRepository(
            folders: [
                FixtureFolder(title: "Work", uuid: "folder-1"),
                FixtureFolder(title: "Personal", uuid: "folder-2")
            ]
        )
        defer { cleanup() }

        let folders = try repo.readFolders()

        #expect(folders.count == 2)
        #expect(folders[0].title == "Work")
        #expect(folders[0].uuid == "folder-1")
        #expect(folders[1].title == "Personal")
        #expect(folders[1].uuid == "folder-2")
    }

    // MARK: - testReadTagsFromFixture

    @Test("Read tags from fixture")
    func testReadTagsFromFixture() throws {
        let (repo, cleanup) = createFixtureRepository(
            tags: [
                FixtureTag(title: "swift", uuid: "tag-1"),
                FixtureTag(title: "go", uuid: "tag-2"),
                FixtureTag(title: "python", uuid: "tag-3")
            ]
        )
        defer { cleanup() }

        let tags = try repo.readTags()

        #expect(tags.count == 3)
        #expect(tags[0].title == "swift")
        #expect(tags[0].uuid == "tag-1")
        #expect(tags[1].title == "go")
        #expect(tags[1].uuid == "tag-2")
        #expect(tags[2].title == "python")
        #expect(tags[2].uuid == "tag-3")
    }

    // MARK: - testReadSnippetSummariesFromFixture

    @Test("Read snippet summaries sorted newest first")
    func testReadSnippetSummariesFromFixture() throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "Old", uuid: "s-1",
                    folder: nil, tags: nil,
                    dateCreated: "2024-01-01T00:00:00Z",
                    dateModified: "2024-01-01T00:00:00Z",
                    fragments: nil
                ),
                FixtureSnippet(
                    title: "New", uuid: "s-2",
                    folder: nil, tags: nil,
                    dateCreated: "2025-06-15T12:00:00Z",
                    dateModified: "2025-06-15T12:00:00Z",
                    fragments: nil
                ),
                FixtureSnippet(
                    title: "Middle", uuid: "s-3",
                    folder: nil, tags: nil,
                    dateCreated: "2024-06-01T00:00:00Z",
                    dateModified: "2024-06-01T00:00:00Z",
                    fragments: nil
                )
            ]
        )
        defer { cleanup() }

        let summaries = try repo.readSnippetSummaries()

        #expect(summaries.count == 3)
        // Must be sorted newest first by dateModified
        #expect(summaries[0].uuid == "s-2") // New
        #expect(summaries[1].uuid == "s-3") // Middle
        #expect(summaries[2].uuid == "s-1") // Old
    }

    // MARK: - testReadSnippetById

    @Test("Read snippet by known UUID")
    func testReadSnippetById() throws {
        let snippetUUID = "known-uuid-123"
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "My Snippet",
                    uuid: snippetUUID,
                    folder: "folder-a",
                    tags: ["tag-x", "tag-y"],
                    dateCreated: "2025-01-01T00:00:00Z",
                    dateModified: "2025-01-15T00:00:00Z",
                    fragments: [
                        FixtureFragment(
                            title: "Fragment 1",
                            content: "print('hello')",
                            language: "python"
                        )
                    ]
                )
            ]
        )
        defer { cleanup() }

        let snippet = try repo.readSnippet(uuid: snippetUUID)

        #expect(snippet.uuid == snippetUUID)
        #expect(snippet.title == "My Snippet")
        #expect(snippet.folder == "folder-a")
        #expect(snippet.tags == ["tag-x", "tag-y"])
        #expect(snippet.dateCreated == "2025-01-01T00:00:00Z")
        #expect(snippet.dateModified == "2025-01-15T00:00:00Z")
        #expect(snippet.fragments?.count == 1)
        #expect(snippet.fragments?.first?.content == "print('hello')")
        #expect(snippet.fragments?.first?.language == "python")
        #expect(snippet.fragments?.first?.title == "Fragment 1")
    }

    // MARK: - testReadSnippetNotFound

    @Test("Read snippet with non-existent UUID throws notFound")
    func testReadSnippetNotFound() throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "Exists", uuid: "exists-1",
                    folder: nil, tags: nil,
                    dateCreated: nil, dateModified: nil,
                    fragments: nil
                )
            ]
        )
        defer { cleanup() }

        #expect(throws: BackupSnippetRepository.Error.notFound("Snippet nonexistent-999 not found")) {
            try repo.readSnippet(uuid: "nonexistent-999")
        }
    }

    // MARK: - testSearchByTitle

    @Test("Search snippets by title substring")
    func testSearchByTitle() throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "Swift Networking", uuid: "s-1",
                    folder: nil, tags: nil,
                    dateCreated: "2025-01-01T00:00:00Z",
                    dateModified: "2025-01-10T00:00:00Z",
                    fragments: nil
                ),
                FixtureSnippet(
                    title: "Go HTTP Client", uuid: "s-2",
                    folder: nil, tags: nil,
                    dateCreated: "2025-02-01T00:00:00Z",
                    dateModified: "2025-02-10T00:00:00Z",
                    fragments: nil
                ),
                FixtureSnippet(
                    title: "Python Tests", uuid: "s-3",
                    folder: nil, tags: nil,
                    dateCreated: "2025-03-01T00:00:00Z",
                    dateModified: "2025-03-10T00:00:00Z",
                    fragments: nil
                )
            ]
        )
        defer { cleanup() }

        let results = try repo.searchSnippets(query: "networking")

        #expect(results.count == 1)
        #expect(results.first?.uuid == "s-1")
    }

    // MARK: - testSearchByContent

    @Test("Search snippets by content substring")
    func testSearchByContent() throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "Alpha", uuid: "s-1",
                    folder: nil, tags: nil,
                    dateCreated: nil, dateModified: "2025-01-01T00:00:00Z",
                    fragments: [
                        FixtureFragment(title: "Code", content: "func hello()", language: "swift")
                    ]
                ),
                FixtureSnippet(
                    title: "Beta", uuid: "s-2",
                    folder: nil, tags: nil,
                    dateCreated: nil, dateModified: "2025-02-01T00:00:00Z",
                    fragments: [
                        FixtureFragment(title: "Code", content: "console.log('world')", language: "js")
                    ]
                )
            ]
        )
        defer { cleanup() }

        let results = try repo.searchSnippets(query: "hello")

        #expect(results.count == 1)
        #expect(results.first?.uuid == "s-1")
    }

    // MARK: - testSearchNoMatch

    @Test("Search for non-existent text returns empty results")
    func testSearchNoMatch() throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "Only One", uuid: "s-1",
                    folder: nil, tags: nil,
                    dateCreated: nil, dateModified: "2025-01-01T00:00:00Z",
                    fragments: [
                        FixtureFragment(title: "Code", content: "specific content", language: nil)
                    ]
                )
            ]
        )
        defer { cleanup() }

        let results = try repo.searchSnippets(query: "nonexistent")

        #expect(results.isEmpty)
    }

    // MARK: - testSearchCaseInsensitive

    @Test("Search is case-insensitive")
    func testSearchCaseInsensitive() throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "Hello World", uuid: "s-1",
                    folder: nil, tags: nil,
                    dateCreated: nil, dateModified: "2025-01-01T00:00:00Z",
                    fragments: nil
                )
            ]
        )
        defer { cleanup() }

        // Search with different case
        let resultsLower = try repo.searchSnippets(query: "hello")
        let resultsUpper = try repo.searchSnippets(query: "HELLO")
        let resultsMixed = try repo.searchSnippets(query: "hElLo")

        #expect(resultsLower.count == 1)
        #expect(resultsUpper.count == 1)
        #expect(resultsMixed.count == 1)
        #expect(resultsLower.first?.uuid == "s-1")
        #expect(resultsUpper.first?.uuid == "s-1")
        #expect(resultsMixed.first?.uuid == "s-1")
    }

    // MARK: - testEmptyLibrary

    @Test("Empty library returns empty results")
    func testEmptyLibrary() throws {
        let (repo, cleanup) = createFixtureRepository()
        defer { cleanup() }

        let snippets = try repo.readSnippetSummaries()
        let folders = try repo.readFolders()
        let tags = try repo.readTags()

        #expect(snippets.isEmpty)
        #expect(folders.isEmpty)
        #expect(tags.isEmpty)
    }

    // MARK: - testLibraryNotFound

    @Test("Non-existent backups directory throws libraryNotFound")
    func testLibraryNotFound() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let repo = BackupSnippetRepository(backupsDir: tempDir, fileManager: .default)

        // Directory exists but contains no .snippetslab-backup subdirectories
        #expect(throws: BackupSnippetRepository.Error.libraryNotFound("No backups found in \(tempDir)")) {
            try repo.readSnippetSummaries()
        }
    }

    // MARK: - testDecodeFailure

    @Test("Corrupt library.json throws decodeFailed")
    func testDecodeFailure() throws {
        let fm = FileManager.default
        let tempDir = try makeTempDir()
        defer { try? fm.removeItem(atPath: tempDir) }

        // Create a .snippetslab-backup dir with corrupt JSON
        let backupDir = "\(tempDir)/corrupt.snippetslab-backup"
        try fm.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
        try "this is not valid json".write(
            to: URL(fileURLWithPath: "\(backupDir)/library.json"),
            atomically: true,
            encoding: .utf8
        )

        let repo = BackupSnippetRepository(backupsDir: tempDir, fileManager: fm)

        // The decode error is wrapped in BackupSnippetRepository.Error.decodeFailed
        #expect(throws: BackupSnippetRepository.Error.self) {
            try repo.readSnippetSummaries()
        }
    }
}

// MARK: - MCP Tool Handler Tests

struct MCPToolHandlerTests {

    // MARK: - handleListSnippets

    @Test("List snippets with no arguments returns default limit of 50")
    func testHandleListSnippetsNoArgs() async throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: (1...60).map { i in
                FixtureSnippet(
                    title: "Snippet \(i)",
                    uuid: "s-\(i)",
                    folder: nil, tags: nil,
                    dateCreated: nil,
                    dateModified: "2025-01-\(String(format: "%02d", (i % 30) + 1))T00:00:00Z",
                    fragments: nil
                )
            }
        )
        defer { cleanup() }

        let result = try await handleListSnippets(repository: repo, args: [:])

        let text = try extractText(from: result)
        let snippets = try JSONDecoder().decode([SnippetsLabSnippet].self, from: try #require(text.data(using: .utf8)))

        #expect(snippets.count == 50)
    }

    @Test("List snippets with folder_uuid filter")
    func testHandleListSnippetsWithFolderFilter() async throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "In Folder", uuid: "s-1",
                    folder: "folder-a", tags: nil,
                    dateCreated: nil, dateModified: "2025-01-01T00:00:00Z",
                    fragments: nil
                ),
                FixtureSnippet(
                    title: "Other Folder", uuid: "s-2",
                    folder: "folder-b", tags: nil,
                    dateCreated: nil, dateModified: "2025-01-02T00:00:00Z",
                    fragments: nil
                ),
                FixtureSnippet(
                    title: "No Folder", uuid: "s-3",
                    folder: nil, tags: nil,
                    dateCreated: nil, dateModified: "2025-01-03T00:00:00Z",
                    fragments: nil
                )
            ]
        )
        defer { cleanup() }

        let result = try await handleListSnippets(repository: repo, args: ["folder_uuid": .string("folder-a")])

        let text = try extractText(from: result)
        let snippets = try JSONDecoder().decode([SnippetsLabSnippet].self, from: try #require(text.data(using: .utf8)))

        #expect(snippets.count == 1)
        #expect(snippets.first?.uuid == "s-1")
    }

    @Test("List snippets with tag_uuid filter")
    func testHandleListSnippetsWithTagFilter() async throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "Swift", uuid: "s-1",
                    folder: nil, tags: ["tag-swift"],
                    dateCreated: nil, dateModified: "2025-01-01T00:00:00Z",
                    fragments: nil
                ),
                FixtureSnippet(
                    title: "Go", uuid: "s-2",
                    folder: nil, tags: ["tag-go"],
                    dateCreated: nil, dateModified: "2025-01-02T00:00:00Z",
                    fragments: nil
                ),
                FixtureSnippet(
                    title: "Both", uuid: "s-3",
                    folder: nil, tags: ["tag-swift", "tag-go"],
                    dateCreated: nil, dateModified: "2025-01-03T00:00:00Z",
                    fragments: nil
                )
            ]
        )
        defer { cleanup() }

        let result = try await handleListSnippets(repository: repo, args: ["tag_uuid": .string("tag-swift")])

        let text = try extractText(from: result)
        let snippets = try JSONDecoder().decode([SnippetsLabSnippet].self, from: try #require(text.data(using: .utf8)))

        #expect(snippets.count == 2)
        let uuids = Set(snippets.map(\.uuid))
        #expect(uuids == ["s-1", "s-3"])
    }

    @Test("List snippets with custom limit")
    func testHandleListSnippetsWithLimit() async throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: (1...10).map { i in
                FixtureSnippet(
                    title: "Snippet \(i)",
                    uuid: "s-\(i)",
                    folder: nil, tags: nil,
                    dateCreated: nil,
                    dateModified: "2025-01-\(String(format: "%02d", i))T00:00:00Z",
                    fragments: nil
                )
            }
        )
        defer { cleanup() }

        let result = try await handleListSnippets(repository: repo, args: ["limit": .string("3")])

        let text = try extractText(from: result)
        let snippets = try JSONDecoder().decode([SnippetsLabSnippet].self, from: try #require(text.data(using: .utf8)))

        #expect(snippets.count == 3)
    }

    @Test("List snippets with empty library returns empty array")
    func testHandleListSnippetsEmptyLibrary() async throws {
        let (repo, cleanup) = createFixtureRepository()
        defer { cleanup() }

        let result = try await handleListSnippets(repository: repo, args: [:])

        let text = try extractText(from: result)
        let data = try #require(text.data(using: .utf8))
        let snippets = try JSONDecoder().decode([SnippetsLabSnippet].self, from: data)
        #expect(snippets.isEmpty)
    }

    // MARK: - handleGetSnippet

    @Test("Get snippet with valid UUID returns snippet content")
    func testHandleGetSnippetValidUUID() async throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "Test Snippet",
                    uuid: "test-uuid-123",
                    folder: "folder-a",
                    tags: ["tag-1"],
                    dateCreated: "2025-01-01T00:00:00Z",
                    dateModified: "2025-01-15T00:00:00Z",
                    fragments: [
                        FixtureFragment(title: "Code", content: "let x = 1", language: "swift")
                    ]
                )
            ]
        )
        defer { cleanup() }

        let result = try await handleGetSnippet(repository: repo, args: ["uuid": .string("test-uuid-123")])

        let text = try extractText(from: result)
        let snippet = try JSONDecoder().decode(SnippetsLabSnippet.self, from: try #require(text.data(using: .utf8)))

        #expect(snippet.uuid == "test-uuid-123")
        #expect(snippet.title == "Test Snippet")
        #expect(snippet.folder == "folder-a")
        #expect(snippet.tags == ["tag-1"])
        #expect(snippet.fragments?.count == 1)
        #expect(snippet.fragments?.first?.content == "let x = 1")
    }

    @Test("Get snippet with missing UUID throws invalidParams")
    func testHandleGetSnippetMissingUUID() async {
        let (repo, cleanup) = createFixtureRepository()
        defer { cleanup() }

        await #expect(throws: MCPError.invalidParams("Missing required argument: uuid")) {
            try await handleGetSnippet(repository: repo, args: [:])
        }
    }

    // MARK: - handleSearchSnippets

    @Test("Search snippets with valid query returns matches")
    func testHandleSearchSnippetsValidQuery() async throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "Swift Networking", uuid: "s-1",
                    folder: nil, tags: nil,
                    dateCreated: nil, dateModified: "2025-01-01T00:00:00Z",
                    fragments: nil
                ),
                FixtureSnippet(
                    title: "Python HTTP", uuid: "s-2",
                    folder: nil, tags: nil,
                    dateCreated: nil, dateModified: "2025-01-02T00:00:00Z",
                    fragments: nil
                )
            ]
        )
        defer { cleanup() }

        let result = try await handleSearchSnippets(repository: repo, args: ["query": .string("networking")])

        let text = try extractText(from: result)
        let snippets = try JSONDecoder().decode([SnippetsLabSnippet].self, from: try #require(text.data(using: .utf8)))

        #expect(snippets.count == 1)
        #expect(snippets.first?.uuid == "s-1")
    }

    @Test("Search snippets with missing query throws invalidParams")
    func testHandleSearchSnippetsMissingQuery() async {
        let (repo, cleanup) = createFixtureRepository()
        defer { cleanup() }

        await #expect(throws: MCPError.invalidParams("Missing required argument: query")) {
            try await handleSearchSnippets(repository: repo, args: [:])
        }
    }

    // MARK: - handleCreateSnippet

    @Test("Create snippet with missing title throws invalidParams")
    func testHandleCreateSnippetMissingTitle() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let writer = NSKeyedArchiverSnippetWriter(snippetsDir: tempDir)
        let reader = BackupSnippetRepository(backupsDir: tempDir)
        let repo = CompositeSnippetRepository(reader: reader, writer: writer)

        await #expect(throws: MCPError.invalidParams("Missing required argument: title")) {
            try await handleCreateSnippet(repository: repo, args: ["content": .string("some content")])
        }
    }

    @Test("Create snippet with missing content throws invalidParams")
    func testHandleCreateSnippetMissingContent() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let writer = NSKeyedArchiverSnippetWriter(snippetsDir: tempDir)
        let reader = BackupSnippetRepository(backupsDir: tempDir)
        let repo = CompositeSnippetRepository(reader: reader, writer: writer)

        await #expect(throws: MCPError.invalidParams("Missing required argument: content")) {
            try await handleCreateSnippet(repository: repo, args: ["title": .string("my title")])
        }
    }

    @Test("Create snippet with valid args returns success result")
    func testHandleCreateSnippetValidArgs() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let writer = NSKeyedArchiverSnippetWriter(snippetsDir: tempDir)
        let reader = BackupSnippetRepository(backupsDir: tempDir)
        let repo = CompositeSnippetRepository(reader: reader, writer: writer)

        let result = try await handleCreateSnippet(
            repository: repo,
            args: [
                "title": .string("Test Snippet"),
                "content": .string("let x = 42"),
                "language": .string("swift"),
                "note": .string("my note")
            ]
        )

        // Decode the result content
        let text = try extractText(from: result)
        let decoded = try JSONDecoder().decode([String: String].self, from: try #require(text.data(using: .utf8)))

        #expect(decoded["status"] == "created")
        #expect(decoded["title"] == "Test Snippet")
        #expect(decoded["uuid"] != nil)
        #expect(decoded["path"] == "snippetslab://snippets/\(decoded["uuid"] ?? "")")

        // Verify the file was actually written
        let uuid = try #require(decoded["uuid"])
        let filePath = "\(tempDir)/\(uuid).data"
        #expect(FileManager.default.fileExists(atPath: filePath))
    }

    // MARK: - handleListFolders

    @Test("List folders returns all folders from library")
    func testHandleListFolders() async throws {
        let (repo, cleanup) = createFixtureRepository(
            folders: [
                FixtureFolder(title: "Work", uuid: "f-1"),
                FixtureFolder(title: "Personal", uuid: "f-2"),
                FixtureFolder(title: "Archive", uuid: "f-3")
            ]
        )
        defer { cleanup() }

        let result = try await handleListFolders(repository: repo, args: [:])

        let text = try extractText(from: result)
        let folders = try JSONDecoder().decode([SnippetsLabFolderItem].self, from: try #require(text.data(using: .utf8)))

        #expect(folders.count == 3)
        #expect(folders[0].title == "Work")
        #expect(folders[1].title == "Personal")
        #expect(folders[2].title == "Archive")
    }

    @Test("List folders with empty library returns empty array")
    func testHandleListFoldersEmpty() async throws {
        let (repo, cleanup) = createFixtureRepository()
        defer { cleanup() }

        let result = try await handleListFolders(repository: repo, args: [:])

        let text = try extractText(from: result)
        let data = try #require(text.data(using: .utf8))
        let folders = try JSONDecoder().decode([SnippetsLabFolderItem].self, from: data)
        #expect(folders.isEmpty)
    }

    // MARK: - handleListTags

    @Test("List tags returns all tags from library")
    func testHandleListTags() async throws {
        let (repo, cleanup) = createFixtureRepository(
            tags: [
                FixtureTag(title: "swift", uuid: "t-1"),
                FixtureTag(title: "go", uuid: "t-2")
            ]
        )
        defer { cleanup() }

        let result = try await handleListTags(repository: repo, args: [:])

        let text = try extractText(from: result)
        let tags = try JSONDecoder().decode([SnippetsLabTagItemJSON].self, from: try #require(text.data(using: .utf8)))

        #expect(tags.count == 2)
        #expect(tags[0].title == "swift")
        #expect(tags[1].title == "go")
    }

    @Test("List tags with empty library returns empty array")
    func testHandleListTagsEmpty() async throws {
        let (repo, cleanup) = createFixtureRepository()
        defer { cleanup() }

        let result = try await handleListTags(repository: repo, args: [:])

        let text = try extractText(from: result)
        let data = try #require(text.data(using: .utf8))
        let tags = try JSONDecoder().decode([SnippetsLabTagItemJSON].self, from: data)
        #expect(tags.isEmpty)
    }

    // MARK: - Helpers

    /// Extract the text content from a CallTool.Result.
    private func extractText(from result: CallTool.Result) throws -> String {
        guard let first = result.content.first else {
            throw TestError("Result has no content")
        }
        if case .text(let text, _, _) = first {
            return text
        }
        throw TestError("First content item is not text")
    }
}

private struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Codable Round-Trip Tests

struct CodableRoundTripTests {

    // MARK: - SnippetsLabLibraryJSON

    @Test("SnippetsLabLibraryJSON round-trips through Codable")
    func testSnippetsLabLibraryJSONRoundTrip() throws {
        let original = SnippetsLabLibraryJSON(
            app: "SnippetsLab",
            name: "My Library",
            schema: "1.0",
            date: "2025-06-01T12:00:00Z",
            contents: SnippetsLabContents(
                folders: [
                    SnippetsLabFolderItem(title: "Work", uuid: "f-1"),
                    SnippetsLabFolderItem(title: "Personal", uuid: "f-2")
                ],
                tags: [
                    SnippetsLabTagItemJSON(title: "swift", uuid: "t-1"),
                    SnippetsLabTagItemJSON(title: "go", uuid: "t-2")
                ],
                snippets: [],
                attachments: []
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SnippetsLabLibraryJSON.self, from: data)

        #expect(decoded.app == "SnippetsLab")
        #expect(decoded.name == "My Library")
        #expect(decoded.schema == "1.0")
        #expect(decoded.date == "2025-06-01T12:00:00Z")
        #expect(decoded.contents.folders.count == 2)
        #expect(decoded.contents.folders[0].title == "Work")
        #expect(decoded.contents.folders[1].uuid == "f-2")
        #expect(decoded.contents.tags.count == 2)
        #expect(decoded.contents.tags[0].title == "swift")
        #expect(decoded.contents.tags[1].uuid == "t-2")
        #expect(decoded.contents.snippets.isEmpty)
        #expect(decoded.contents.attachments.isEmpty)
    }

    // MARK: - SnippetsLabSnippet

    @Test("SnippetsLabSnippet with full data round-trips through Codable")
    func testSnippetsLabSnippetRoundTrip() throws {
        let original = SnippetsLabSnippet(
            title: "My Snippet",
            uuid: "abc-123",
            folder: "folder-uuid",
            tags: ["tag-1", "tag-2"],
            dateCreated: "2025-01-01T00:00:00Z",
            dateModified: "2025-06-15T12:00:00Z",
            dateDeleted: nil,
            fragments: [
                SnippetsLabFragment(
                    title: "Fragment 1",
                    note: "A note",
                    content: "print('hello')",
                    language: "python",
                    uuid: "frag-uuid-1",
                    dateCreated: "2025-01-01T00:00:00Z",
                    dateModified: "2025-06-15T12:00:00Z"
                ),
                SnippetsLabFragment(
                    title: "Fragment 2",
                    note: nil,
                    content: "console.log('world')",
                    language: "javascript",
                    uuid: "frag-uuid-2",
                    dateCreated: nil,
                    dateModified: nil
                )
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SnippetsLabSnippet.self, from: data)

        #expect(decoded.title == "My Snippet")
        #expect(decoded.uuid == "abc-123")
        #expect(decoded.folder == "folder-uuid")
        #expect(decoded.tags == ["tag-1", "tag-2"])
        #expect(decoded.dateCreated == "2025-01-01T00:00:00Z")
        #expect(decoded.dateModified == "2025-06-15T12:00:00Z")
        #expect(decoded.dateDeleted == nil)
        #expect(decoded.id == "abc-123")

        let fragments = try #require(decoded.fragments)
        #expect(fragments.count == 2)
        #expect(fragments[0].title == "Fragment 1")
        #expect(fragments[0].note == "A note")
        #expect(fragments[0].content == "print('hello')")
        #expect(fragments[0].language == "python")
        #expect(fragments[0].uuid == "frag-uuid-1")
        #expect(fragments[0].dateCreated == "2025-01-01T00:00:00Z")
        #expect(fragments[0].dateModified == "2025-06-15T12:00:00Z")
        #expect(fragments[1].title == "Fragment 2")
        #expect(fragments[1].note == nil)
        #expect(fragments[1].content == "console.log('world')")
        #expect(fragments[1].language == "javascript")
    }

    @Test("SnippetsLabSnippet with minimal fields round-trips through Codable")
    func testSnippetsLabSnippetMinimalRoundTrip() throws {
        let original = SnippetsLabSnippet(
            title: nil,
            uuid: "minimal-uuid",
            folder: nil,
            tags: nil,
            dateCreated: nil,
            dateModified: nil,
            dateDeleted: nil,
            fragments: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SnippetsLabSnippet.self, from: data)

        #expect(decoded.title == nil)
        #expect(decoded.uuid == "minimal-uuid")
        #expect(decoded.folder == nil)
        #expect(decoded.tags == nil)
        #expect(decoded.dateCreated == nil)
        #expect(decoded.dateModified == nil)
        #expect(decoded.dateDeleted == nil)
        #expect(decoded.fragments == nil)
    }

    // MARK: - SnippetsLabFragment

    @Test("SnippetsLabFragment with all fields round-trips through Codable")
    func testSnippetsLabFragmentRoundTrip() throws {
        let original = SnippetsLabFragment(
            title: "Main Code",
            note: "Important note",
            content: "func main() {}",
            language: "go",
            uuid: "part-uuid-1",
            dateCreated: "2025-03-01T00:00:00Z",
            dateModified: "2025-04-01T00:00:00Z"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SnippetsLabFragment.self, from: data)

        #expect(decoded.title == "Main Code")
        #expect(decoded.note == "Important note")
        #expect(decoded.content == "func main() {}")
        #expect(decoded.language == "go")
        #expect(decoded.uuid == "part-uuid-1")
        #expect(decoded.dateCreated == "2025-03-01T00:00:00Z")
        #expect(decoded.dateModified == "2025-04-01T00:00:00Z")
    }

    @Test("SnippetsLabFragment with nil fields round-trips through Codable")
    func testSnippetsLabFragmentNilRoundTrip() throws {
        let original = SnippetsLabFragment(
            title: nil,
            note: nil,
            content: nil,
            language: nil,
            uuid: nil,
            dateCreated: nil,
            dateModified: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SnippetsLabFragment.self, from: data)

        #expect(decoded.title == nil)
        #expect(decoded.note == nil)
        #expect(decoded.content == nil)
        #expect(decoded.language == nil)
        #expect(decoded.uuid == nil)
        #expect(decoded.dateCreated == nil)
        #expect(decoded.dateModified == nil)
    }

    // MARK: - SnippetsLabFolderItem

    @Test("SnippetsLabFolderItem round-trips through Codable")
    func testSnippetsLabFolderItemRoundTrip() throws {
        let original = SnippetsLabFolderItem(title: "Work Snippets", uuid: "folder-uuid-1")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SnippetsLabFolderItem.self, from: data)

        #expect(decoded.title == "Work Snippets")
        #expect(decoded.uuid == "folder-uuid-1")
        #expect(decoded.id == "folder-uuid-1")
    }

    // MARK: - SnippetsLabTagItemJSON

    @Test("SnippetsLabTagItemJSON round-trips through Codable")
    func testSnippetsLabTagItemJSONRoundTrip() throws {
        let original = SnippetsLabTagItemJSON(title: "swift", uuid: "tag-uuid-1")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SnippetsLabTagItemJSON.self, from: data)

        #expect(decoded.title == "swift")
        #expect(decoded.uuid == "tag-uuid-1")
        #expect(decoded.id == "tag-uuid-1")
    }
}

// MARK: - Resource Tests

struct ResourceHandlerTests {

    // MARK: - ListResources

    @Test("ListResources returns resources for each snippet")
    func testListResources() throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "First", uuid: "s-1", folder: nil, tags: nil,
                    dateCreated: "2025-01-01", dateModified: "2025-06-01", fragments: []
                )
            ]
        )
        defer { cleanup() }

        let handler = { (_: ListResources.Parameters) -> ListResources.Result in
            let snippets = (try? repo.readSnippetSummaries()) ?? []
            let resources = snippets.map { snippet in
                Resource(
                    name: snippet.title ?? "Untitled",
                    uri: "snippetslab://snippets/\(snippet.uuid)",
                    mimeType: "application/json"
                )
            }
            return ListResources.Result(resources: resources)
        }

        let result = handler(ListResources.Parameters())
        #expect(result.resources.count == 1)
        #expect(result.resources.first?.uri == "snippetslab://snippets/s-1")
    }

    // MARK: - ReadResource

    @Test("ReadResource by snippet UUID returns snippet JSON")
    func testReadResourceSnippetByUUID() throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(
                    title: "Test", uuid: "s-1", folder: nil, tags: nil,
                    dateCreated: "2025-01-01", dateModified: "2025-06-01",
                    fragments: [FixtureFragment(title: "Fragment", content: "code", language: "swift")]
                )
            ]
        )
        defer { cleanup() }

        let snippet = try repo.readSnippet(uuid: "s-1")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(snippet)
        let jsonStr = String(data: json, encoding: .utf8) ?? "{}"

        #expect(jsonStr.contains("Test"))
        #expect(jsonStr.contains("s-1"))
    }

    @Test("ReadResource for snippets list returns JSON array")
    func testReadResourceSnippetsList() throws {
        let (repo, cleanup) = createFixtureRepository(
            snippets: [
                FixtureSnippet(title: "A", uuid: "s-1", folder: nil, tags: nil, dateCreated: nil, dateModified: nil, fragments: []),
                FixtureSnippet(title: "B", uuid: "s-2", folder: nil, tags: nil, dateCreated: nil, dateModified: nil, fragments: [])
            ]
        )
        defer { cleanup() }

        let snippets = try repo.readSnippetSummaries()
        #expect(snippets.count == 2)
    }

    @Test("ReadResource for folders returns JSON array")
    func testReadResourceFolders() throws {
        let (repo, cleanup) = createFixtureRepository(
            folders: [FixtureFolder(title: "Work", uuid: "f-1")]
        )
        defer { cleanup() }

        let folders = try repo.readFolders()
        #expect(folders.count == 1)
        #expect(folders.first?.title == "Work")
    }

    @Test("ReadResource for tags returns JSON array")
    func testReadResourceTags() throws {
        let (repo, cleanup) = createFixtureRepository(
            tags: [FixtureTag(title: "swift", uuid: "t-1")]
        )
        defer { cleanup() }

        let tags = try repo.readTags()
        #expect(tags.count == 1)
        #expect(tags.first?.title == "swift")
    }

    @Test("ReadResource with unknown URI throws")
    func testReadResourceUnknownURI() throws {
        #expect(throws: MCPError.invalidParams("Unknown resource URI: snippetslab://unknown")) {
            throw MCPError.invalidParams("Unknown resource URI: snippetslab://unknown")
        }
    }

    @Test("CallTool with unknown name throws")
    func testCallToolUnknownName() throws {
        #expect(throws: MCPError.invalidParams("Unknown tool: nonexistent")) {
            throw MCPError.invalidParams("Unknown tool: nonexistent")
        }
    }
}
