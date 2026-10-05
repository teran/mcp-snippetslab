import Foundation

/// Minimal file-based logger for the Local (stdio) MCP server.
///
/// Logging is driven by the environment, per L01/L02:
/// - In **stdio** mode (the default and only mode for a Local server), logging is
///   **enabled only when `LOG_LEVEL` is set**. When unset, the logger is disabled.
/// - Logs go to a **file** (`LOG_FILENAME`, chmod 600) — never to stdout, which is
///   the MCP transport channel (L01).
/// - `LOG_FORMAT=json` switches the format to JSON; the default is text (L04).
///
/// Secrets/tokens never appear in logs (L05) — this server holds none.
public final class Logger: @unchecked Sendable {

    public enum Level: Int, Comparable {
        case debug = 0, info = 1, warn = 2, error = 3

        init?(_ raw: String) {
            switch raw.lowercased() {
            case "debug": self = .debug
            case "info": self = .info
            case "warn", "warning": self = .warn
            case "error": self = .error
            default: return nil
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Format {
        case text, json
    }

    /// Whether logging is currently enabled (stdio: only when `LOG_LEVEL` is set).
    public let isEnabled: Bool

    private let level: Level
    private let format: Format
    private let fileHandle: FileHandle?
    private let lock = NSLock()

    /// Default log path for this server.
    public static var defaultFilename: String {
        let home = NSHomeDirectory()
        return "\(home)/Library/Logs/mcp-snippetslab.log"
    }

    /// Creates a logger from the environment. Returns `nil` when logging is disabled
    /// (L02: in stdio mode, enabled only when `LOG_LEVEL` is set).
    public init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let rawLevel = environment["LOG_LEVEL"], let level = Level(rawLevel) else {
            self.isEnabled = false
            self.level = .info
            self.format = .text
            self.fileHandle = nil
            return nil
        }

        self.isEnabled = true
        self.level = level
        self.format = (environment["LOG_FORMAT"]?.lowercased() == "json") ? .json : .text

        let filename = environment["LOG_FILENAME"] ?? Logger.defaultFilename
        let manager = FileManager.default

        // Create the file (append) and restrict permissions to 600 (L01/L03).
        if !manager.fileExists(atPath: filename) {
            manager.createFile(atPath: filename, contents: nil)
        }
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filename)

        self.fileHandle = FileHandle(forWritingAtPath: filename)
    }

    /// Emits the startup banner as the first log line (B05/L06) when enabled.
    public func banner(appName: String, version: String, commit: String, timestamp: String) {
        guard isEnabled else { return }
        log(.info, "Starting \(appName)/\(version) (commit: \(commit); built at \(timestamp))")
    }

    /// Logs a record if the level passes the configured threshold and logging is enabled.
    public func log(_ level: Level, _ message: String, requestID: String? = nil) {
        guard isEnabled, level >= self.level else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line: String
        switch format {
        case .json:
            var fields = [
                "\"time\":\"\(timestamp)\"",
                "\"level\":\"\(levelName(level))\"",
                "\"message\":\(jsonEscaped(message))"
            ]
            if let requestID { fields.append("\"request_id\":\"\(requestID)\"") }
            line = "{\(fields.joined(separator: ","))}"
        case .text:
            var lineBuilder = "\(timestamp) [\(levelName(level).uppercased())] \(message)"
            if let requestID { lineBuilder += " request_id=\(requestID)" }
            line = lineBuilder
        }

        lock.withLock {
            guard let data = (line + "\n").data(using: .utf8) else { return }
            _ = try? fileHandle?.seekToEnd()
            fileHandle?.write(data)
        }
    }

    // MARK: - Convenience

    public func debug(_ message: String, requestID: String? = nil) { log(.debug, message, requestID: requestID) }
    public func info(_ message: String, requestID: String? = nil) { log(.info, message, requestID: requestID) }
    public func warn(_ message: String, requestID: String? = nil) { log(.warn, message, requestID: requestID) }
    public func error(_ message: String, requestID: String? = nil) { log(.error, message, requestID: requestID) }

    // MARK: - Helpers

    private func levelName(_ level: Level) -> String {
        switch level {
        case .debug: return "debug"
        case .info: return "info"
        case .warn: return "warn"
        case .error: return "error"
        }
    }

    private func jsonEscaped(_ value: String) -> String {
        // Minimal JSON string escaping sufficient for log messages.
        var result = ""
        for char in value {
            switch char {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(char)
            }
        }
        return result
    }
}
