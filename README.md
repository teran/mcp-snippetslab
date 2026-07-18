# mcp-snippetslab

MCP server for [SnippetsLab](https://snippetslab.app/) — search, read, and create code snippets from your macOS snippet library.

## Requirements

- macOS (SnippetsLab is macOS/iOS only)
- Swift 6.3+
- SnippetsLab with a library at the default iCloud path

## Quick Start

```bash
swift build -c release
```

Add to your MCP client config:

```json
{
  "mcpServers": {
    "mcp-snippetslab": {
      "command": "/path/to/mcp-snippetslab/.build/release/mcp-snippetslab"
    }
  }
}
```

## Tools

| Tool | What it does |
|---|---|
| `list_snippets` | List snippets, filter by folder/tag |
| `get_snippet` | Get full snippet by UUID |
| `search_snippets` | Full-text search across titles and content |
| `create_snippet` | Create a new snippet |
| `list_folders` | List all folders |
| `list_tags` | List all tags |

## Resources

| URI | Returns |
|---|---|
| `snippetslab://snippets` | All snippets (JSON) |
| `snippetslab://snippets/<uuid>` | Single snippet (JSON) |
| `snippetslab://folders` | All folders (JSON) |
| `snippetslab://tags` | All tags (JSON) |

## Data Source

- **Reading**: automatic SnippetsLab backups at `~/Library/Containers/com.renfei.SnippetsLab/.../Backups/`
- **Writing**: NSKeyedArchiver binary plists written to the iCloud library bundle

## Development

```bash
swift build              # Build debug
swift build -c release   # Build release (used by MCP clients)
swift test               # Run tests (48 tests, 5 suites)
swiftlint --strict       # Lint (0 violations)
```

## Architecture

Clean Architecture / DDD layers:

- **Domain** — `Snippet`, `Fragment`, `Folder`, `Tag` entities + `SnippetRepository` protocol
- **Application** — MCP handler registration (`MCPServerConfiguration`)
- **Infrastructure** — `BackupSnippetRepository` (reads), `NSKeyedArchiverSnippetWriter` (writes)
- **Composition Root** — `main.swift` wires everything together

See [SPEC.md](SPEC.md) for full specification.
