import Foundation
import MCP

// MARK: - JSON Schema Helpers

/// Builds a JSON-Schema `string` property descriptor.
private func stringProperty(_ description: String) -> Value {
    .object([
        "type": .string("string"),
        "description": .string(description)
    ])
}

/// Builds a JSON-Schema `integer` property descriptor with bounds.
private func integerProperty(_ description: String, minimum: Int, maximum: Int) -> Value {
    .object([
        "type": .string("integer"),
        "description": .string(description),
        "minimum": .int(minimum),
        "maximum": .int(maximum)
    ])
}

// MARK: - Output Schemas (S09)

/// Output schema shared by the snippet-producing tools.
private let snippetOutputSchema: Value = .object([
    "type": .string("object"),
    "properties": .object([
        "title": stringProperty("Snippet title"),
        "uuid": stringProperty("Snippet UUID"),
        "folder": stringProperty("Folder UUID (optional)"),
        "tags": .object([
            "type": .string("array"),
            "items": stringProperty("Tag UUID")
        ]),
        "dateCreated": stringProperty("Creation date (optional)"),
        "dateModified": stringProperty("Modification date (optional)"),
        "dateDeleted": stringProperty("Deletion date (optional)"),
        "fragments": .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("object"),
                "properties": .object([
                    "title": stringProperty("Fragment title"),
                    "note": stringProperty("Fragment note"),
                    "content": stringProperty("Fragment content"),
                    "language": stringProperty("Syntax language"),
                    "uuid": stringProperty("Fragment UUID"),
                    "dateCreated": stringProperty("Creation date"),
                    "dateModified": stringProperty("Modification date")
                ])
            ])
        ])
    ])
])

private let snippetArrayOutputSchema: Value = .object([
    "type": .string("array"),
    "items": snippetOutputSchema
])

private let folderOutputSchema: Value = .object([
    "type": .string("array"),
    "items": .object([
        "type": .string("object"),
        "properties": .object([
            "title": stringProperty("Folder title"),
            "uuid": stringProperty("Folder UUID")
        ])
    ])
])

private let tagOutputSchema: Value = .object([
    "type": .string("array"),
    "items": .object([
        "type": .string("object"),
        "properties": .object([
            "title": stringProperty("Tag title"),
            "uuid": stringProperty("Tag UUID")
        ])
    ])
])

// MARK: - Output Sanitization (S09/N23)

/// Removes ANSI escape sequences and control characters (except tab/LF/CR) from
/// text before it is returned to the client, so a malicious snippet cannot inject
/// terminal-control output (S09/N23).
func sanitizeForText(_ string: String) -> String {
    var result = String()
    result.reserveCapacity(string.count)
    let scalars = Array(string.unicodeScalars)
    var i = 0
    let count = scalars.count

    while i < count {
        let value = scalars[i].value

        // Tab, LF, CR are preserved.
        if value == 0x09 || value == 0x0A || value == 0x0D {
            result.unicodeScalars.append(scalars[i])
            i += 1
            continue
        }

        // ESC: skip the full ANSI escape sequence.
        if value == 0x1B {
            i += 1
            guard i < count else { break }
            let next = scalars[i].value
            if next == 0x5B { // CSI "ESC ["
                i += 1
                while i < count {
                    let fv = scalars[i].value
                    i += 1
                    if fv >= 0x40 && fv <= 0x7E { break } // final byte
                }
            } else if next == 0x5D { // OSC "ESC ]" — until BEL or ST (ESC \)
                i += 1
                while i < count {
                    let ov = scalars[i].value
                    i += 1
                    if ov == 0x07 || ov == 0x1B { break }
                }
            } else {
                // Two-character escape (e.g. "ESC (").
                i += 1
            }
            continue
        }

        // Other control characters (0x00–0x1F except those kept above, 0x7F, CSI 0x9B).
        if value <= 0x1F || value == 0x7F || value == 0x9B {
            i += 1
            continue
        }

        result.unicodeScalars.append(scalars[i])
        i += 1
    }

    return result
}

/// Encodes a value to both a sanitized text representation (for readability) and a
/// structuredContent payload (S07/S09) conforming to the tool's `outputSchema`.
private func makeResult<T: Codable>(_ value: T) throws -> CallTool.Result {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    let text = sanitizeForText(String(data: data, encoding: .utf8) ?? "[]")
    let structured = try Value(value)
    return try CallTool.Result(
        content: [.text(text: text, annotations: nil, _meta: nil)],
        structuredContent: structured
    )
}

// MARK: - Argument helpers

/// Resolves the `limit` argument (accepts `.int` or a numeric `.string` for
/// backwards compatibility with earlier releases) and clamps it to `[1, max]`.
private func resolveLimit(_ args: [String: Value], default defaultValue: Int = 50, max maximum: Int = 1000) throws -> Int {
    guard let value = args["limit"] else { return defaultValue }

    let parsed: Int?
    switch value {
    case .int(let i):
        parsed = i
    case .string(let s):
        parsed = Int(s)
    default:
        parsed = nil
    }

    guard let parsed, parsed > 0 else {
        throw MCPError.invalidParams("limit must be a positive integer")
    }
    return min(parsed, maximum)
}

// MARK: - Tool Definitions (M04: annotations; S08: strict inputSchema; S09: outputSchema)

let allTools: [Tool] = [
    Tool(
        name: "list_snippets",
        title: "List snippets",
        description: """
            List all snippets with optional folder and tag filters. Returns snippet
            summaries (title, uuid, folder, tags, dates). Sorted by modification date
            newest first. Use get_snippet to fetch full content. Read-only.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "folder_uuid": stringProperty("Filter by folder UUID (optional)"),
                "tag_uuid": stringProperty("Filter by tag UUID (optional)"),
                "limit": integerProperty("Maximum number of results (default: 50)", minimum: 1, maximum: 1000)
            ])
        ]),
        annotations: .init(
            title: "List snippets",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        ),
        outputSchema: snippetArrayOutputSchema
    ),
    Tool(
        name: "get_snippet",
        title: "Get snippet",
        description: """
            Get the full snippet content by UUID, including all fragments (title,
            note, content, language). Throws if the UUID does not exist. Read-only.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "uuid": stringProperty("The snippet UUID (required)")
            ]),
            "required": .array([.string("uuid")])
        ]),
        annotations: .init(
            title: "Get snippet",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        ),
        outputSchema: snippetOutputSchema
    ),
    Tool(
        name: "search_snippets",
        title: "Search snippets",
        description: """
            Full-text search across snippet titles and content. Returns matching
            snippet summaries sorted by modification date. Read-only.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "query": stringProperty("Search query (required)")
            ]),
            "required": .array([.string("query")])
        ]),
        annotations: .init(
            title: "Search snippets",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        ),
        outputSchema: snippetArrayOutputSchema
    ),
    Tool(
        name: "list_folders",
        title: "List folders",
        description: "List all folders in the SnippetsLab library. Read-only.",
        inputSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([:])
        ]),
        annotations: .init(
            title: "List folders",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        ),
        outputSchema: folderOutputSchema
    ),
    Tool(
        name: "list_tags",
        title: "List tags",
        description: "List all tags in the SnippetsLab library. Read-only.",
        inputSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([:])
        ]),
        annotations: .init(
            title: "List tags",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        ),
        outputSchema: tagOutputSchema
    )
]

// MARK: - Tool Handlers (S03: all read-only; S08: validated; S09: structured output)

func handleListSnippets(repository: SnippetRepository, args: [String: Value]) async throws -> CallTool.Result {
    let summaries = try repository.readSnippetSummaries()

    let limit = try resolveLimit(args)
    let folderUUID: String?
    if case .string(let f) = args["folder_uuid"] { folderUUID = f } else { folderUUID = nil }
    let tagUUID: String?
    if case .string(let t) = args["tag_uuid"] { tagUUID = t } else { tagUUID = nil }

    var filtered = summaries
    if let folderUUID {
        filtered = filtered.filter { $0.folder == folderUUID }
    }
    if let tagUUID {
        filtered = filtered.filter { $0.tags?.contains(tagUUID) ?? false }
    }

    return try makeResult(Array(filtered.prefix(limit)))
}

func handleGetSnippet(repository: SnippetRepository, args: [String: Value]) async throws -> CallTool.Result {
    guard case .string(let uuid) = args["uuid"] else {
        throw MCPError.invalidParams("Missing required argument: uuid")
    }
    let snippet = try repository.readSnippet(uuid: uuid)
    return try makeResult(snippet)
}

func handleSearchSnippets(repository: SnippetRepository, args: [String: Value]) async throws -> CallTool.Result {
    guard case .string(let query) = args["query"] else {
        throw MCPError.invalidParams("Missing required argument: query")
    }
    let results = try repository.searchSnippets(query: query)
    return try makeResult(results)
}

func handleListFolders(repository: SnippetRepository, args: [String: Value]) async throws -> CallTool.Result {
    let folders = try repository.readFolders()
    return try makeResult(folders)
}

func handleListTags(repository: SnippetRepository, args: [String: Value]) async throws -> CallTool.Result {
    let tags = try repository.readTags()
    return try makeResult(tags)
}

// MARK: - Configuration

public enum MCPServerConfiguration {
    /// Configures the MCP server: registers resources and tool handlers, and wires
    /// the optional logger for the per-request access log (L08) with `request_id`
    /// correlation (L09).
    public static func configure(server: Server, repository: SnippetRepository, logger: Logger? = nil) async {
        // MARK: - Resources

        await server.withMethodHandler(ListResources.self) { _ in
            let snippets = (try? repository.readSnippetSummaries()) ?? []

            let resources: [Resource] = snippets.map { snippet in
                Resource(
                    name: snippet.title ?? "Untitled",
                    uri: "snippetslab://snippets/\(snippet.uuid)",
                    title: snippet.title ?? "Untitled",
                    description: "Snippet created \(snippet.dateCreated ?? "unknown")",
                    mimeType: "application/json"
                )
            }

            return .init(resources: resources)
        }

        await server.withMethodHandler(ReadResource.self) { params in
            let uri = params.uri
            let textResult: String
            let mime = "application/json"

            if uri.hasPrefix("snippetslab://snippets/") {
                let uuid = String(uri.dropFirst("snippetslab://snippets/".count))
                let snippet = try repository.readSnippet(uuid: uuid)
                textResult = try encodeJSON(snippet)
            } else if uri == "snippetslab://snippets" {
                textResult = try encodeJSON(try repository.readSnippetSummaries())
            } else if uri == "snippetslab://folders" {
                textResult = try encodeJSON(try repository.readFolders())
            } else if uri == "snippetslab://tags" {
                textResult = try encodeJSON(try repository.readTags())
            } else {
                throw MCPError.invalidParams("Unknown resource URI: \(uri)")
            }

            return .init(contents: [
                .text(sanitizeForText(textResult), uri: uri, mimeType: mime, _meta: nil)
            ])
        }

        // MARK: - Tools (access log: L08, request_id: L09)

        await server.withMethodHandler(CallTool.self) { params in
            let requestID = UUID().uuidString
            let start = Date()
            let toolName = params.name
            let args = params.arguments ?? [:]

            func logOutcome(_ outcome: String) {
                let durationMs = Int((Date().timeIntervalSince(start) * 1000).rounded())
                logger?.info(
                    "tool=\(toolName) source=STDIO outcome=\(outcome) duration_ms=\(durationMs)",
                    requestID: requestID
                )
            }

            do {
                let result: CallTool.Result
                switch toolName {
                case "list_snippets":
                    result = try await handleListSnippets(repository: repository, args: args)
                case "get_snippet":
                    result = try await handleGetSnippet(repository: repository, args: args)
                case "search_snippets":
                    result = try await handleSearchSnippets(repository: repository, args: args)
                case "list_folders":
                    result = try await handleListFolders(repository: repository, args: args)
                case "list_tags":
                    result = try await handleListTags(repository: repository, args: args)
                default:
                    throw MCPError.invalidParams("Unknown tool: \(toolName)")
                }
                logOutcome("ok")
                return result
            } catch {
                logOutcome("error")
                throw error
            }
        }

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: allTools)
        }
    }
}

// MARK: - JSON Encoding Helper (sanitized, for resource text output)

private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    return String(data: data, encoding: .utf8) ?? "[]"
}
