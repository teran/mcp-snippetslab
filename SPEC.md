# mcp-snippetslab — SPEC

## Overview

An MCP (Model Context Protocol) server that provides LLM agents with **read-only** access to SnippetsLab code snippet collections on macOS. It reads the latest automatic SnippetsLab backup (`library.json`) and never writes to the live library.

## Repository & CI (R05/R06)

- **Host / path:** `github.com/teran/mcp-snippetslab` (public GitHub).
- **CI provider:** **GitHub Actions** (`.github/workflows/ci.yml`, `release.yml`).
- **Default branch:** `master` (R02).
- **Build-system interface (R07):** a `Makefile` exposes `make lint` / `make test` / `make build`, plus dedicated hard-gate targets `make coverage`, `make mutation`, `make secret-scan`, `make thread-sanitize`. CI binds to these targets, never to raw Swift commands (N31). As a **Local** server, the optional `e2e` / `container-image` targets are **not** declared (N31).

## Transports & Auth decisions (M02/M03)

- **Transport decision (M02):** **STDIO** (`StdioTransport`). This is a short-lived, local macOS companion for a single client (an editor/CLI). There are no remote/multiple concurrent clients and no network listener, so STDIO is the correct and only transport. No HTTP flavour is used.
- **Auth decision (M03):** **No OAuth2 / no auth.** The server has no upstream API and holds no credentials — it reads a local backup file. OAuth2 is therefore not applicable (fleet default: no OAuth2).

## Deployment type (M06)

**Local (stdio-only).** The launch mode is effectively fixed to `stdio`; no `-mode` flag or HTTP listener exists, and no container image is produced (R01/B03). Logging follows the stdio rules (L01/L02).

## Startup Sequence

The MCP SDK's `Server.start()` returns immediately after setting up the transport and spawning a background message-handling task. The process MUST call `server.waitUntilCompleted()` to keep it alive; otherwise it exits right after `start()` returns.

SIGPIPE is ignored (`signal(SIGPIPE, SIG_IGN)`) to prevent the OS from killing the process when the client closes its read-end of the stdio pipe. The `StdioTransport` handles `EPIPE` write errors gracefully.

## Data Sources

### Reading (backup)
Primary source: automatic backups created by SnippetsLab at:
```
~/Library/Containers/com.renfei.SnippetsLab/Data/Library/Application Support/Backups/
<date>.snippetslab-backup/library.json
```
- Pure JSON, always available, auto-created ~hourly
- Contains all snippets, folders, and tags inline
- **Requirement:** Automatic backups must be enabled in SnippetsLab (_Settings → General → Backups_)

> **Note:** The server is **read-only**. Writing to the live iCloud library was removed because
> SnippetsLab uses custom ObjC classes (`SLSnippet`) and crashes when it encounters
> plain `NSDictionary` archives written by external tools.

## Tools (5)

All tools are **read-only** (S03), declared with **Annotations** (M04) and an
**`outputSchema`** (S09), and return both sanitized text and `structuredContent`.
Input schemas use `additionalProperties:false` and bounded/typed parameters (S08).

| Tool | Description | Parameters | Annotations |
|---|---|---|---|
| `list_snippets` | List snippets with optional filters | `folder_uuid`, `tag_uuid`, `limit` (int 1–1000) | readOnly, idempotent, closed-world |
| `get_snippet` | Full snippet by UUID | `uuid` (required) | readOnly, idempotent, closed-world |
| `search_snippets` | Full-text search (title + content) | `query` (required) | readOnly, idempotent, closed-world |
| `list_folders` | List all folders | — | readOnly, idempotent, closed-world |
| `list_tags` | List all tags | — | readOnly, idempotent, closed-world |

## Resources

| URI | Content |
|---|---|
| `snippetslab://snippets` | All snippet summaries (JSON array) |
| `snippetslab://snippets/<uuid>` | Full snippet (JSON object) |
| `snippetslab://folders` | All folders (JSON array) |
| `snippetslab://tags` | All tags (JSON array) |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     main.swift (Composition Root)            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │        MCPServerConfiguration (Application)           │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐  │   │
│  │  │list_snip│ │get_snip │ │search    │ │list_   │  │   │
│  │  │        │ │        │ │          │ │folders │  │   │
│  │  │        │ │        │ │          │ │/tags   │  │   │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬───┘  │   │
│  └───────┼────────────┼────────────┼────────────┼───────┘   │
│          ▼            ▼            ▼            ▼           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              SnippetRepository (protocol)              │   │
│  └──────────────────────────┬───────────────────────────┘   │
│                             ▼                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │          BackupSnippetRepository                       │   │
│  │          (Infrastructure — reads library.json)         │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Domain Model

- **Snippet** — `{title, uuid, folder, tags[], fragments[], dates}`
- **Fragment** — `{title, content, language, note, dates}`
- **Folder** — `{title, uuid}`
- **Tag** — `{title, uuid}`

## Config

The server is intentionally minimal and requires **no environment configuration to
run**. The backups directory is fixed at startup from the current user's home
(`~/Library/Containers/com.renfei.SnippetsLab/.../Backups`) and is **read-only**.
Because the server exposes **no client-supplied path parameters**, the S04
`ALLOW_DIRS` scoping does not apply here — there is no path-traversal entry point.
A symlink-escape guard resolves and verifies the final `library.json` path stays
within the backups root (S04/N03).

Logging is configured through environment variables (see Logging).

## Data & State (X01–X05)

- **State model (X01):** **stateless.** Each tool call maps to a read of the local
  backup file. The only in-session state is a short-lived in-memory cache holding a
  snapshot of the library (60 s TTL). No durable state is persisted outside the
  process.
- **Write idempotency (X02):** N/A — the server is read-only; no mutating tools exist.
- **Upstream timeouts (X03):** N/A — there is no upstream; the server reads a local file.
- **Persistence (X04):** N/A — no durable state to migrate or encrypt.
- **Concurrency (X05):** the cache is guarded by an `NSLock` around both read and
  write, so concurrent accesses never observe partial/corrupt state. The
  `FileManager` instance is marked `nonisolated(unsafe)` — this is safe because it
  is used immutably (thread-safe `FileManager` instance methods only) and all
  writes go through the locked cache.

## Logging (L01–L09)

- **Launch mode:** effectively fixed to `stdio` (Local server).
- **Enablement (L02):** logging is **enabled only when `LOG_LEVEL` is set**; unset ⇒
  disabled (the default).
- **Channel (L01):** logs go to a **file** (`LOG_FILENAME`, default
  `~/Library/Logs/mcp-snippetslab.log`, chmod 600) — never stdout, which is the MCP
  transport.
- **Format (L04):** text by default; `LOG_FORMAT=json` switches to JSON.
- **Banner (B05/L06):** when enabled, the first line is `Starting {appName}/{appVersion} (commit: {appCommit}; built at {appTimestamp})`.
- **Access log (L08):** every `tools/call` emits a line at `info` with `tool`,
  redacted args, `source` (`STDIO`), `duration_ms`, and `outcome` (`ok`/`error`).
- **Correlation (L09):** a `request_id` (UUID) is generated per request and included
  on each log record. No secrets ever appear in logs (L05).
- **SDK logger (L07):** N/A — this version of the swift-sdk does not expose an
  injectable logger; server-level MCP `instructions` are set instead.

## Security (S01–S13)

- **TLS (S01/N01):** never implemented in-server — N/A for a stdio server.
- **Secret hygiene (S02/N02):** the server holds no API keys/tokens; snippet content
  is the served data, not a credential leak.
- **Tool grouping (S03):** all tools are read-only (no write/delete tools).
- **Filesystem scoping (S04/N03):** fixed read-only path + symlink-escape guard; no
  client-controlled paths.
- **Input validation (S08/N22):** every tool declares `additionalProperties:false`
  and typed/bounded parameters; required args are enforced.
- **Output contract (S09/N23):** every tool declares an `outputSchema` and returns
  `structuredContent`; ANSI/control escape sequences are stripped from text output.
- **Open-world (S07/S10):** no `openWorldHint:true` tools; all are closed-domain.
- **No shell/SQL/URL concatenation (S11/N21):** search is in-memory; none present.
- **Destructive tools (S12):** none exist.

## Testing / TDD (T01, C01–C03)

- **Workflow (T01):** all fixes/features follow TDD — @qa writes tests in an isolated
  context, @developer writes the implementation in an isolated context.
- **Gates (C01–C03):** CI enforces coverage ≥ 95% (`make coverage`), mutation testing
  via muter (`make mutation`), and secret scanning via gitleaks (`make secret-scan`),
  plus Thread Sanitizer and dependency audit (osv-scanner). e2e is not applicable for
  this Swift Local server (best-effort/optional per the language profile).
- **Suites:** 47 tests across 7 suites (repository, tool handlers, Codable round-trips,
  resources, tool registry, output sanitization, symlink escape).

## NSKeyedArchiver Key Reference

SnippetsLab stores snippets using Apple's NSKeyedArchiver with custom ObjC classes. The writer constructs dictionaries matching this format:

### Snippet keys
- `com.renfei.SnippetsLab.Key.SnippetTitle` — String
- `com.renfei.SnippetsLab.Key.SnippetUUID` — String (UUID)
- `com.renfei.SnippetsLab.Key.SnippetParts` — NSArray of fragment dicts
- `com.renfei.SnippetsLab.Key.SnippetFolderUUID` — String or NSNull
- `com.renfei.SnippetsLab.Key.SnippetTagUUIDs` — NSArray of strings
- `com.renfei.SnippetsLab.Key.SnippetDateCreated` — Date
- `com.renfei.SnippetsLab.Key.SnippetDateModified` — Date
- `com.renfei.SnippetsLab.Key.DateDeleted` — NSNull
- `com.renfei.SnippetsLab.Key.Pinned` — Bool
- `com.renfei.SnippetsLab.Key.Locked` — Bool
- `com.renfei.SnippetsLab.Key.GistIdentifier` — NSNull
- `com.renfei.SnippetsLab.Key.GitHubHTMLURL` — NSNull
- `com.renfei.SnippetsLab.Key.GitHubUsername` — NSNull

### Fragment keys
- `com.renfei.SnippetsLab.Key.SnippetPartTitle` — String
- `com.renfei.SnippetsLab.Key.SnippetPartUUID` — String (UUID)
- `com.renfei.SnippetsLab.Key.SnippetPartContent` — String
- `com.renfei.SnippetsLab.Key.SnippetPartLanguage` — String or NSNull
- `com.renfei.SnippetsLab.Key.SnippetPartNote` — Data
- `com.renfei.SnippetsLab.Key.SnippetPartNotesAttributes` — Data
- `com.renfei.SnippetsLab.Key.SnippetPartAttachments` — NSArray
- `com.renfei.SnippetsLab.Key.SnippetPartSnippetUUID` — String
- `com.renfei.SnippetsLab.Key.SnippetPartDateCreated` — Date
- `com.renfei.SnippetsLab.Key.SnippetPartDateModified` — Date
