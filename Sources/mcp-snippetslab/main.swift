import Darwin
import Foundation
import MCP

// MARK: - Signal Handling

/// Ignore SIGPIPE to prevent the process from crashing when writing
/// to a broken pipe (e.g., the client disconnects unexpectedly).
/// The StdioTransport handles EPIPE errors gracefully.
signal(SIGPIPE, SIG_IGN)

// MARK: - Logging (B05/L06, L01/L02)

/// In stdio mode logging is enabled only when LOG_LEVEL is set (L02); logs go to a
/// file (LOG_FILENAME), never stdout (L01). When disabled, `logger` is nil.
let logger = Logger(environment: ProcessInfo.processInfo.environment)

if let logger, logger.isEnabled {
    logger.banner(
        appName: BuildMetadata.appName,
        version: BuildMetadata.appVersion,
        commit: BuildMetadata.appCommit,
        timestamp: BuildMetadata.appTimestamp
    )
}

// MARK: - Composition Root

let repository = BackupSnippetRepository()

let server = Server(
    name: BuildMetadata.appName,
    version: BuildMetadata.appVersion,
    title: "SnippetsLab MCP Server",
    instructions: """
        Provides read-only access to SnippetsLab code snippet library.
        Supports searching, reading snippets, and listing folders and tags.

        Snippets are organized into folders and can have tags and multiple fragments.
        Each fragment has content, language, and optional notes.

        All tools are read-only. Use snippetslab://snippets/<uuid> to reference individual snippets.
        """,
    capabilities: Server.Capabilities(
        resources: .init(listChanged: true),
        tools: .init(listChanged: true)
    )
)

await MCPServerConfiguration.configure(server: server, repository: repository, logger: logger)

// Start the server
try await server.start(transport: StdioTransport())

// Keep the process alive until the server shuts down
await server.waitUntilCompleted()
