import Foundation

/// The allowlisted part of one Claude Code session registration
/// (`~/.claude/sessions/<pid>.json`). Claude Code keeps one such file per
/// running session; Claude Desktop's Code sessions record their sidebar title,
/// desktop session ID and live status there. Working directories, sockets,
/// log paths and peer data in the same file are never decoded.
public struct ClaudeSessionRecord: Equatable, Sendable {
    public let pid: Int32
    public let hostSessionID: String
    public let title: String?
    /// `nil` while the session is idle or reports an unknown status.
    public let phase: TaskPhase?
    public let statusChangedAt: Date?
    public let processStartedAt: Date?

    public init(pid: Int32, hostSessionID: String, title: String?, phase: TaskPhase?, statusChangedAt: Date?, processStartedAt: Date?) {
        self.pid = pid
        self.hostSessionID = hostSessionID
        self.title = title
        self.phase = phase
        self.statusChangedAt = statusChangedAt
        self.processStartedAt = processStartedAt
    }
}

public enum ClaudeSessionRegistry {
    public static let maximumFileSize = 64 * 1024

    public static func parse(_ data: Data) -> ClaudeSessionRecord? {
        guard data.count <= maximumFileSize,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["kind"] as? String == "interactive",
              object["entrypoint"] as? String == "claude-desktop",
              let pid = processID(object["pid"]),
              let hostSessionID = object["hostSessionId"] as? String,
              isDesktopSessionID(hostSessionID)
        else { return nil }
        return ClaudeSessionRecord(
            pid: pid,
            hostSessionID: hostSessionID,
            title: title(object["name"]),
            phase: phase(status: object["status"] as? String, waitingFor: object["waitingFor"] as? String),
            statusChangedAt: date(object["statusUpdatedAt"]),
            processStartedAt: processStart(object["procStart"] as? String)
        )
    }

    /// Claude Code reports `busy`, `shell`, `waiting` or `idle`.
    public static func phase(status: String?, waitingFor: String?) -> TaskPhase? {
        switch status {
        case "busy": return .thinking
        case "shell": return .usingTool
        case "waiting":
            // Tool approvals wait for "permission prompt"; questions and
            // dialogs wait for "input needed" or the dialog's own name.
            let reason = waitingFor?.lowercased() ?? ""
            return reason.contains("permission") || reason.contains("sandbox") ? .waitingApproval : .waitingInput
        default: return nil
        }
    }

    public static func isDesktopSessionID(_ value: String) -> Bool {
        value.hasPrefix("local_") && UUID(uuidString: String(value.dropFirst(6))) != nil
    }

    /// Claude Desktop's own "continue a Code session" entry point. The app
    /// resolves the session's current route itself.
    public static func deepLink(forDesktopSession id: String) -> URL? {
        guard isDesktopSessionID(id) else { return nil }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/continue"
        components.queryItems = [URLQueryItem(name: "session", value: id)]
        return components.url
    }

    private static func processID(_ value: Any?) -> Int32? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw.rounded() == raw, raw > 0, raw <= Double(Int32.max) else { return nil }
        return Int32(raw)
    }

    private static func title(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= 160, !text.contains(where: \.isNewline) else { return nil }
        return String(text.prefix(80))
    }

    private static func date(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw > 0 else { return nil }
        // Registry timestamps are epoch milliseconds.
        return Date(timeIntervalSince1970: raw > 2_000_000_000 ? raw / 1000 : raw)
    }

    private static let processStartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }()

    /// `procStart` is `ps -o lstart` output in UTC, e.g. "Sat Sep 26 06:48:54 2026".
    private static func processStart(_ value: String?) -> Date? {
        guard let value, value.count <= 64 else { return nil }
        let normalized = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return processStartFormatter.date(from: normalized)
    }
}
