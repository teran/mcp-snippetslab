import Foundation
import MCP

// MARK: - Tool Definitions

let allTools: [Tool] = [
    Tool(
        name: "list_snippets",
        description: "List all snippets with optional folder and tag filters",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "folder_uuid": .object([
                    "type": .string("string"),
                    "description": .string("Filter by folder UUID (optional)")
                ]),
                "tag_uuid": .object([
                    "type": .string("string"),
                    "description": .string("Filter by tag UUID (optional)")
                ]),
                "limit": .object([
                    "type": .string("string"),
                    "description": .string("Maximum number of results (default: 50)")
                ])
            ])
        ])
    ),
    Tool(
        name: "get_snippet",
        description: "Get full snippet content by UUID including all fragments",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "uuid": .object([
                    "type": .string("string"),
                    "description": .string("The snippet UUID (required)")
                ])
            ]),
            "required": .array([.string("uuid")])
        ])
    ),
    Tool(
        name: "search_snippets",
        description: "Full-text search across snippet titles and content",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Search query (required)")
                ])
            ]),
            "required": .array([.string("query")])
        ])
    ),
    Tool(
        name: "create_snippet",
        description: "Create a new snippet in the SnippetsLab library",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object([
                    "type": .string("string"),
                    "description": .string("Snippet title (required)")
                ]),
                "content": .object([
                    "type": .string("string"),
                    "description": .string("Snippet content / code (required)")
                ]),
                "language": .object([
                    "type": .string("string"),
                    "description": .string("Programming language (optional)")
                ]),
                "folder_uuid": .object([
                    "type": .string("string"),
                    "description": .string("Folder UUID (optional)")
                ]),
                "tag_uuids": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Tag UUIDs (optional)")
                ]),
                "note": .object([
                    "type": .string("string"),
                    "description": .string("Optional note for the fragment")
                ])
            ]),
            "required": .array([.string("title"), .string("content")])
        ])
    ),
    Tool(
        name: "list_folders",
        description: "List all folders in the SnippetsLab library",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:])
        ])
    ),
    Tool(
        name: "list_tags",
        description: "List all tags in the SnippetsLab library",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:])
        ])
    )
]

// MARK: - Tool Handlers

func handleListSnippets(repository: SnippetRepository, args: [String: Value]) async throws -> CallTool.Result {
    let summaries = try repository.readSnippetSummaries()

    let limit: Int
    if case .string(let limitStr) = args["limit"] {
        limit = Int(limitStr) ?? 50
    } else {
        limit = 50
    }

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

    let limited = Array(filtered.prefix(limit))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(limited)
    let jsonStr = String(data: json, encoding: .utf8) ?? "[]"

    return CallTool.Result(content: [
        .text(text: jsonStr, annotations: nil, _meta: nil)
    ])
}

func handleGetSnippet(repository: SnippetRepository, args: [String: Value]) async throws -> CallTool.Result {
    guard case .string(let uuid) = args["uuid"] else {
        throw MCPError.invalidParams("Missing required argument: uuid")
    }

    let snippet = try repository.readSnippet(uuid: uuid)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(snippet)
    let jsonStr = String(data: json, encoding: .utf8) ?? "{}"

    return CallTool.Result(content: [
        .text(text: jsonStr, annotations: nil, _meta: nil)
    ])
}

func handleSearchSnippets(repository: SnippetRepository, args: [String: Value]) async throws -> CallTool.Result {
    guard case .string(let query) = args["query"] else {
        throw MCPError.invalidParams("Missing required argument: query")
    }

    let results = try repository.searchSnippets(query: query)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(results)
    let jsonStr = String(data: json, encoding: .utf8) ?? "[]"

    return CallTool.Result(content: [
        .text(text: jsonStr, annotations: nil, _meta: nil)
    ])
}

func handleCreateSnippet(repository: SnippetRepository, args: [String: Value]) async throws -> CallTool.Result {
    guard case .string(let title) = args["title"] else {
        throw MCPError.invalidParams("Missing required argument: title")
    }
    guard case .string(let content) = args["content"] else {
        throw MCPError.invalidParams("Missing required argument: content")
    }

    let language: String?
    if case .string(let lang) = args["language"] { language = lang } else { language = nil }

    let folderUUID: String?
    if case .string(let f) = args["folder_uuid"] { folderUUID = f } else { folderUUID = nil }

    let tagUUIDs: [String]
    if case .array(let tags) = args["tag_uuids"] {
        tagUUIDs = tags.compactMap { $0.stringValue }
    } else {
        tagUUIDs = []
    }

    let note: String?
    if case .string(let n) = args["note"] { note = n } else { note = nil }

    let uuid = try repository.createSnippet(
        title: title,
        content: content,
        language: language,
        folderUUID: folderUUID,
        tagUUIDs: tagUUIDs,
        note: note
    )

    let result: [String: String] = [
        "uuid": uuid,
        "title": title,
        "status": "created",
        "path": "snippetslab://snippets/\(uuid)"
    ]

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(result)
    let jsonStr = String(data: json, encoding: .utf8) ?? "{}"

    return CallTool.Result(content: [
        .text(text: jsonStr, annotations: nil, _meta: nil)
    ])
}

func handleListFolders(repository: SnippetRepository) async throws -> CallTool.Result {
    let folders = try repository.readFolders()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(folders)
    let jsonStr = String(data: json, encoding: .utf8) ?? "[]"

    return CallTool.Result(content: [
        .text(text: jsonStr, annotations: nil, _meta: nil)
    ])
}

func handleListTags(repository: SnippetRepository) async throws -> CallTool.Result {
    let tags = try repository.readTags()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(tags)
    let jsonStr = String(data: json, encoding: .utf8) ?? "[]"

    return CallTool.Result(content: [
        .text(text: jsonStr, annotations: nil, _meta: nil)
    ])
}

// MARK: - Configuration

public enum MCPServerConfiguration {
    public static func configure(server: Server, repository: SnippetRepository) async {
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

            if uri.hasPrefix("snippetslab://snippets/") {
                let uuid = String(uri.dropFirst("snippetslab://snippets/".count))
                let snippet = try repository.readSnippet(uuid: uuid)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let json = try encoder.encode(snippet)
                let jsonStr = String(data: json, encoding: .utf8) ?? "{}"

                return .init(contents: [
                    .text(jsonStr, uri: uri, mimeType: "application/json", _meta: nil)
                ])
            }

            if uri == "snippetslab://snippets" {
                let snippets = try repository.readSnippetSummaries()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let json = try encoder.encode(snippets)
                let jsonStr = String(data: json, encoding: .utf8) ?? "[]"

                return .init(contents: [
                    .text(jsonStr, uri: uri, mimeType: "application/json", _meta: nil)
                ])
            }

            if uri == "snippetslab://folders" {
                let folders = try repository.readFolders()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let json = try encoder.encode(folders)
                let jsonStr = String(data: json, encoding: .utf8) ?? "[]"

                return .init(contents: [
                    .text(jsonStr, uri: uri, mimeType: "application/json", _meta: nil)
                ])
            }

            if uri == "snippetslab://tags" {
                let tags = try repository.readTags()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let json = try encoder.encode(tags)
                let jsonStr = String(data: json, encoding: .utf8) ?? "[]"

                return .init(contents: [
                    .text(jsonStr, uri: uri, mimeType: "application/json", _meta: nil)
                ])
            }

            throw MCPError.invalidParams("Unknown resource URI: \(uri)")
        }

        // MARK: - Tools

        await server.withMethodHandler(CallTool.self) { params in
            let toolName = params.name
            let args = params.arguments ?? [:]

            switch toolName {
            case "list_snippets":
                return try await handleListSnippets(repository: repository, args: args)
            case "get_snippet":
                return try await handleGetSnippet(repository: repository, args: args)
            case "search_snippets":
                return try await handleSearchSnippets(repository: repository, args: args)
            case "create_snippet":
                return try await handleCreateSnippet(repository: repository, args: args)
            case "list_folders":
                return try await handleListFolders(repository: repository)
            case "list_tags":
                return try await handleListTags(repository: repository)
            default:
                throw MCPError.invalidParams("Unknown tool: \(toolName)")
            }
        }

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: allTools)
        }
    }
}
