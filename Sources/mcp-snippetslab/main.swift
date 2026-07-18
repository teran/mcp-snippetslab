import Darwin
import Foundation
import MCP

// MARK: - Signal Handling

/// Ignore SIGPIPE to prevent the process from crashing when writing
/// to a broken pipe (e.g., the client disconnects unexpectedly).
/// The StdioTransport handles EPIPE errors gracefully.
signal(SIGPIPE, SIG_IGN)

// MARK: - Composite Repository

internal final class CompositeSnippetRepository: SnippetRepository {
    private let reader: BackupSnippetRepository
    private let writer: NSKeyedArchiverSnippetWriter

    init(reader: BackupSnippetRepository, writer: NSKeyedArchiverSnippetWriter) {
        self.reader = reader
        self.writer = writer
    }

    func readFolders() throws -> [Folder] {
        try reader.readFolders()
    }

    func readTags() throws -> [Tag] {
        try reader.readTags()
    }

    func readSnippetSummaries() throws -> [Snippet] {
        try reader.readSnippetSummaries()
    }

    func readSnippet(uuid: String) throws -> Snippet {
        try reader.readSnippet(uuid: uuid)
    }

    func searchSnippets(query: String) throws -> [Snippet] {
        try reader.searchSnippets(query: query)
    }

    func createSnippet(
        title: String,
        content: String,
        language: String?,
        folderUUID: String?,
        tagUUIDs: [String],
        note: String?
    ) throws -> String {
        try writer.createSnippet(
            title: title,
            content: content,
            language: language,
            folderUUID: folderUUID,
            tagUUIDs: tagUUIDs,
            note: note
        )
    }
}

// MARK: - Composition Root

let library = BackupSnippetRepository()
let writer = NSKeyedArchiverSnippetWriter()
let repository = CompositeSnippetRepository(reader: library, writer: writer)

let server = Server(
    name: "mcp-snippetslab",
    version: "1.0.0",
    title: "SnippetsLab MCP Server",
    instructions: """
        Provides access to SnippetsLab code snippet library.
        Supports searching, reading, and creating snippets.

        Snippets are organized into folders and can have tags and multiple fragments.
        Each fragment has content, language, and optional notes.

        Use snippetslab://snippets/<uuid> to reference individual snippets.
        """,
    capabilities: Server.Capabilities(
        resources: .init(listChanged: true),
        tools: .init(listChanged: true)
    )
)

await MCPServerConfiguration.configure(server: server, repository: repository)

// Start the server
try await server.start(transport: StdioTransport())

// Keep the process alive until the server shuts down
await server.waitUntilCompleted()
