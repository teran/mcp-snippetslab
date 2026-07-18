# AGENTS.md — Instructions for AI agents working on mcp-snippetslab

## Language
All prompts, code, commit messages, and documentation are in English unless the user specifies otherwise.

## Project Structure

```
Sources/mcp-snippetslab/
├── main.swift                         — Composition Root
├── Application/
│   └── MCPServerConfiguration.swift   — MCP tool/resource handler registration
├── Domain/
│   ├── Entity/
│   │   ├── Snippet.swift
│   │   ├── Folder.swift
│   │   └── Tag.swift
│   └── Repository/
│       └── SnippetRepository.swift    — Protocol
└── Infrastructure/
    ├── BackupSnippetRepository.swift   — Read from backup library.json
    └── NSKeyedArchiverSnippetWriter.swift — Write via NSKeyedArchiver
```

## Architecture

Clean Architecture / DDD:

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

- 48 tests across 5 suites (as of initial refactoring)
- `SnippetsLabWriterTests` — 6 tests
- `SnippetsLabLibraryTests` — 12 tests
- `MCPToolHandlerTests` — 16 tests
- `CodableRoundTripTests` — 7 tests
- `ResourceHandlerTests` — 7 tests

## Key Constraints

1. Reading from backup `library.json` (clean JSON, always available, ~daily freshness)
2. Writing via NSKeyedArchiver to iCloud library (SnippetsLab monitors the directory)
3. SnippetsLab uses custom ObjC classes (SLSnippet) — NSKeyedUnarchiver cannot decode them without the app
4. `requiresSecureCoding = false` for both reading (fails gracefully) and writing
5. `FileManager` is non-Sendable — use `nonisolated(unsafe)` with clear comments
6. **Startup**: `main.swift` must call `await server.waitUntilCompleted()` after `try await server.start(…)` or the process exits immediately. `signal(SIGPIPE, SIG_IGN)` is required at the top of `main.swift` to prevent crashes on broken pipes.
7. **Tool inputSchema**: Every property in a tool's `inputSchema` MUST be a JSON Schema object with `type` and `description` fields — e.g. `.object(["type": .string("string"), "description": .string("...")])`. Plain `.string("...")` values produce invalid JSON Schema that clients like opencode reject with "failed to get tools".

## MCP SDK

- `github.com/modelcontextprotocol/swift-sdk` v0.12.1
- `Server` is an actor; handler registration requires `await server.withMethodHandler(...)`
- Commands communicate via `StdioTransport`
- See SPEC.md for tool/resource specifications
