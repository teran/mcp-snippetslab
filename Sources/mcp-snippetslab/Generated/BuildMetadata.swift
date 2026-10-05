import Foundation

/// Build metadata for the server binary (B02).
///
/// Values are injected at build time via environment variables set by the
/// Makefile / release workflow (from git). When absent (e.g. a plain
/// `swift build`), safe dev defaults are used so the binary still builds.
enum BuildMetadata {

    static let appName = "mcp-snippetslab"

    /// Semantic version. Defaults to the git tag/describe when available,
    /// otherwise a dev placeholder.
    static var appVersion: String {
        env("APP_VERSION")
            ?? gitDescribe()
            ?? "0.0.0-dev"
    }

    static var appCommit: String {
        env("APP_COMMIT") ?? "unknown"
    }

    static var appTimestamp: String {
        env("APP_TIMESTAMP") ?? "unknown"
    }

    // MARK: - Helpers

    private static func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    private static func gitDescribe() -> String? {
        // Non-fatal best-effort: derive a version from the current git tag.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "describe", "--tags", "--abbrev=0"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let data = (process.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile(),
                  let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !version.isEmpty else {
                return nil
            }
            return version
        } catch {
            return nil
        }
    }
}
