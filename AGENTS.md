# AGENTS.md — Instructions for AI agents working on mcp-snippetslab

## Language
All prompts, code, commit messages, and documentation are in English unless the user specifies otherwise.

## Project Structure

```
Sources/mcp-snippetslab/
├── main.swift                                    — Composition Root (wiring only)
├── Application/
│   ├── MCPServerConfiguration.swift              — MCP tool/resource handler registration
│   └── Logger.swift                              — file-based logger (L01/L02/L08/L09)
├── Domain/
│   ├── Entity/
│   │   ├── Snippet.swift
│   │   ├── Folder.swift
│   │   └── Tag.swift
│   └── Repository/
│       └── SnippetRepository.swift               — Protocol
├── Generated/
│   └── BuildMetadata.swift                       — build metadata (B02)
└── Infrastructure/
    └── BackupSnippetRepository.swift             — Read from backup library.json
```

## Architecture

Clean Architecture / DDD — **read-only** server:

- **Domain layer** has NO dependencies on Foundation or MCP framework
- **Infrastructure** implements Domain protocols; Foundation dependencies are allowed here
- **Application** bridges MCP framework handlers to Domain (+ logging)
- **main.swift** is the composition root — only wiring, no logic

## Conventions

- Run `make lint` (`swiftlint --strict`) before committing — 0 violations required
- Run `make test` (`swift test`) before committing — all tests must pass
- Run `make coverage` and `make thread-sanitize` locally when changing core logic
- Commit messages: conventional commits (`feat:`, `fix:`, `refactor:`, `docs:`, `ci:`, `test:`)
- Do NOT modify `.swiftlint.yml` or `opencode.json` without explicit user request
- CI binds to `make` targets (R07/N31) — do not add language-specific commands to workflows

## Tests / TDD

- **Workflow (T01):** all fixes/features are done TDD-style — @qa writes tests with an
  isolated context, @developer writes the implementation with an isolated context.
- **Count:** 47 tests across 7 suites
- `BackupSnippetRepositoryTests` — 12 tests
- `MCPToolHandlerTests` — 13 tests (create_snippet removed)
- `CodableRoundTripTests` — 7 tests
- `ResourceHandlerTests` — 5 tests
- `ToolRegistryTests` — 6 tests (M04/S03/S08/S09)
- `OutputSanitizationTests` — 3 tests (S09/N23)
- `SymlinkEscapeTests` — 1 test (S04/N03)

## Changes from the Grill (July 2026)

The following improvements were made after a full repository audit:

1. **Domain layer**: Removed `import Foundation` from all domain entities (`Snippet`, `Folder`, `Tag`, `SnippetRepository` protocol) — uses only Swift standard library types now
2. **JSON DRY**: Extracted `encodeJSON<T>` helper — replaces 12 repetitive JSONEncoder blocks with a single function call
3. **Consistent handler signatures**: All 5 tool handlers now accept `(repository: SnippetRepository, args: [String: Value])`
4. **Made read-only**: Removed `NSKeyedArchiverSnippetWriter`, `CompositeSnippetRepository`, and `create_snippet` tool — writing `.data` files crashes SnippetsLab because it expects custom ObjC classes
5. **README**: AI-generated content disclaimer, proper badges, SnippetsLab MCP confirmation, architecture diagram, corrected MCP client config example
6. **CI/Release workflows**: Cleaned up (removed `opencode.json` references from release), proper macOS-only binary packaging

## Changes (this conformance pass)

1. **Tool metadata (M04/S09):** every tool declares Annotations (read-only, idempotent,
   closed-world), an `outputSchema`, and returns `structuredContent` plus sanitized text
   (ANSI/control sequences stripped, S09/N23).
2. **Strict inputSchema (S08):** `additionalProperties:false` on all tools; `limit` is a
   bounded integer (1–1000).
3. **Logging (L01–L09/B05):** file-based `Logger` enabled by `LOG_LEVEL`, startup banner,
   per-request access log with `request_id`. Wired in `main.swift`.
4. **Build metadata (B02):** `BuildMetadata` derived from env / git instead of hard-coded
   `1.0.0`.
5. **Filesystem scoping (S04/N03):** symlink-escape guard around the backups directory.
6. **Build-system interface (R07/N31):** added `Makefile`; CI bound to `make` targets.
7. **CI hard gates (C01–C03):** coverage ≥ 95%, muter, gitleaks, Thread Sanitizer,
   osv-scanner.
8. **Tests:** removed 2 tautological `ResourceHandlerTests`; added ToolRegistry,
   OutputSanitization and SymlinkEscape suites (47 tests / 7 suites).

## Key Constraints

1. **Read-only** — the server never writes to the SnippetsLab library
2. Reading from backup `library.json` (clean JSON, always available, ~hourly freshness)
3. SnippetsLab uses custom ObjC classes (SLSnippet) — NSKeyedUnarchiver cannot decode them without the app, even with `requiresSecureCoding = false`
4. `FileManager` is non-Sendable — use `nonisolated(unsafe)` with clear comments
5. **Startup**: `main.swift` must call `await server.waitUntilCompleted()` after `try await server.start(…)` or the process exits immediately. `signal(SIGPIPE, SIG_IGN)` is required at the top of `main.swift` to prevent crashes on broken pipes.
6. **Tool inputSchema**: Every property in a tool's `inputSchema` MUST be a JSON Schema object with `type` and `description` fields — e.g. `.object(["type": .string("string"), "description": .string("...")])`. Plain `.string("...")` values produce invalid JSON Schema that clients like opencode reject with "failed to get tools".
7. **Tool metadata**: every tool MUST declare Annotations (readOnly/destructive/idempotent/
   openWorld hints) and an `outputSchema`; text output MUST be ANSI/control-sanitized.
8. **Logging**: never log to stdout (it is the MCP transport); write to `LOG_FILENAME` only
   when `LOG_LEVEL` is set; never log secrets (L05).

## MCP SDK

- `github.com/modelcontextprotocol/swift-sdk` v0.12.1
- `Server` is an actor; handler registration requires `await server.withMethodHandler(...)`
- `Tool` supports `title`, `annotations`, `outputSchema`; `CallTool.Result` supports
  `structuredContent` (this SDK version has no per-tool `instructions` field — use
  detailed `description` + server-level `instructions`)
- Commands communicate via `StdioTransport`
- See SPEC.md for tool/resource specifications
