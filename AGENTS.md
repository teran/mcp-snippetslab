# AGENTS.md — Instructions for AI agents working on mcp-snippetslab

## Language
All prompts, code, commit messages, and documentation are in English unless the user specifies otherwise.

## Project Structure

```
Sources/mcp-snippetslab/
├── main.swift                                    — Composition Root (wiring only)
├── Application/
│   └── MCPServerConfiguration.swift              — MCP tool/resource handler registration
├── Domain/
│   ├── Entity/
│   │   ├── Snippet.swift
│   │   ├── Folder.swift
│   │   └── Tag.swift
│   └── Repository/
│       └── SnippetRepository.swift               — Protocol
└── Infrastructure/
    └── BackupSnippetRepository.swift             — Read from backup library.json
```

## Architecture

Clean Architecture / DDD — **read-only** server:

- **Domain layer** has NO dependencies on Foundation or MCP framework
- **Infrastructure** implements Domain protocols; Foundation dependencies are allowed here
- **Application** bridges MCP framework handlers to Domain
- **main.swift** is the composition root — only wiring, no logic

## Conventions

- Run `swiftlint --strict` before committing — 0 violations required
- Run `swift test` before committing — all tests must pass
- Commit messages: conventional commits (`feat:`, `fix:`, `refactor:`, `docs:`, `ci:`, `test:`)
- Do NOT modify `.swiftlint.yml` or `opencode.json` without explicit user request

## Tests

- 39 tests across 4 suites
- `BackupSnippetRepositoryTests` — 12 tests
- `MCPToolHandlerTests` — 13 tests (create_snippet removed)
- `CodableRoundTripTests` — 7 tests
- `ResourceHandlerTests` — 7 tests

## Changes from the Grill (July 2026)

The following improvements were made after a full repository audit:

1. **Domain layer**: Removed `import Foundation` from all domain entities (`Snippet`, `Folder`, `Tag`, `SnippetRepository` protocol) — uses only Swift standard library types now
2. **JSON DRY**: Extracted `encodeJSON<T>` helper — replaces 12 repetitive JSONEncoder blocks with a single function call
3. **Consistent handler signatures**: All 5 tool handlers now accept `(repository: SnippetRepository, args: [String: Value])`
4. **Made read-only**: Removed `NSKeyedArchiverSnippetWriter`, `CompositeSnippetRepository`, and `create_snippet` tool — writing `.data` files crashes SnippetsLab because it expects custom ObjC classes
5. **README**: AI-generated content disclaimer, proper badges, SnippetsLab MCP confirmation, architecture diagram, corrected MCP client config example
6. **CI/Release workflows**: Cleaned up (removed `opencode.json` references from release), proper macOS-only binary packaging

## Key Constraints

1. **Read-only** — the server never writes to the SnippetsLab library
2. Reading from backup `library.json` (clean JSON, always available, ~hourly freshness)
3. SnippetsLab uses custom ObjC classes (SLSnippet) — NSKeyedUnarchiver cannot decode them without the app, even with `requiresSecureCoding = false`
4. `FileManager` is non-Sendable — use `nonisolated(unsafe)` with clear comments
5. **Startup**: `main.swift` must call `await server.waitUntilCompleted()` after `try await server.start(…)` or the process exits immediately. `signal(SIGPIPE, SIG_IGN)` is required at the top of `main.swift` to prevent crashes on broken pipes.
6. **Tool inputSchema**: Every property in a tool's `inputSchema` MUST be a JSON Schema object with `type` and `description` fields — e.g. `.object(["type": .string("string"), "description": .string("...")])`. Plain `.string("...")` values produce invalid JSON Schema that clients like opencode reject with "failed to get tools".

## MCP SDK

- `github.com/modelcontextprotocol/swift-sdk` v0.12.1
- `Server` is an actor; handler registration requires `await server.withMethodHandler(...)`
- Commands communicate via `StdioTransport`
- See SPEC.md for tool/resource specifications
