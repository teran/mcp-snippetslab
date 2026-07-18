# mcp-snippetslab — SPEC

## Overview

An MCP (Model Context Protocol) server that provides LLM agents with read/write access to SnippetsLab code snippet collections on macOS.

## Data Sources

### Reading (backup)
Primary source: automatic backups created by SnippetsLab at:
```
~/Library/Containers/com.renfei.SnippetsLab/Data/Library/Application Support/Backups/
<date>.snippetslab-backup/library.json
```
- Pure JSON, always available, auto-created ~daily
- Contains all snippets, folders, and tags inline

### Writing (live iCloud library)
Snippets are created as NSKeyedArchiver binary plist `.data` files directly in the iCloud library:
```
~/Library/Mobile Documents/iCloud~com~renfei~SnippetsLab/
    main.snippetslablibrary/Database/Snippets/<UUID>.data
```
SnippetsLab monitors this directory and picks up new files automatically.

## Tools (6)

| Tool | Description | Parameters |
|---|---|---|
| `list_snippets` | List snippets with optional filters | `folder_uuid`, `tag_uuid`, `limit` |
| `get_snippet` | Full snippet by UUID | `uuid` (required) |
| `search_snippets` | Full-text search (title + content) | `query` (required) |
| `create_snippet` | Create a new snippet | `title`, `content` (required); `language`, `folder_uuid`, `tag_uuids`, `note` |
| `list_folders` | List all folders | — |
| `list_tags` | List all tags | — |

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
│  │  │list_snip│ │get_snip │ │search    │ │create  │…│  │   │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬────┘  │   │
│  └───────┼────────────┼────────────┼────────────┼───────┘   │
│          ▼            ▼            ▼            ▼           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         SnippetRepository (protocol - Domain)         │   │
│  └──────────┬────────────────────────────────┬──────────┘   │
│             ▼                                ▼              │
│  ┌────────────────────┐      ┌──────────────────────────┐   │
│  │BackupSnippetRepo   │      │NSKeyedArchiverWriter     │   │
│  │(Infrastructure)    │      │(Infrastructure)          │   │
│  └────────────────────┘      └──────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Domain Model

- **Snippet** — `{title, uuid, folder, tags[], fragments[], dates}`
- **Fragment** — `{title, content, language, note, dates}`
- **Folder** — `{title, uuid}`
- **Tag** — `{title, uuid}`

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
