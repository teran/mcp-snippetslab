# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Per-tool MCP **Annotations** (read-only, non-destructive, idempotent, closed-world)
  and **`outputSchema`** for every tool (M04/S09).
- Tools now return `structuredContent` in addition to sanitized text output;
  ANSI/control escape sequences are stripped before returning (S09/N23).
- File-based **logger** (enabled when `LOG_LEVEL` is set; logs to `LOG_FILENAME`,
  chmod 600), startup **banner**, and a per-request **access log** with `request_id`
  correlation (B05/L01–L09).
- **Symlink-escape guard** for the backups directory (S04/N03).
- **Makefile** as the standard build-system interface (R07).
- CI gates: **coverage ≥ 95%**, **mutation testing** (muter), **secret scan**
  (gitleaks), **Thread Sanitizer**, and **dependency audit** (osv-scanner) (C01–C03).

### Changed
- Hardened `inputSchema`: `additionalProperties:false` and a bounded integer `limit`
  (1–1000) on `list_snippets` (S08).
- Build metadata (`APP_VERSION`/`APP_COMMIT`/`APP_TIMESTAMP`) now derived from the
  environment or the current git checkout instead of a hard-coded `1.0.0` (B02).
- `swift test` / `swift build` / `swiftlint` in CI now run via `make` targets.
- Removed two tautological tests; added tool-registry, output-sanitization and
  symlink-escape test suites (47 tests, 7 suites).
