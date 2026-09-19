import Foundation

/// Parses the payload returned by Claude's `/api/oauth/usage` endpoint.
///
/// The response reports utilization per window as a percentage already used,
/// which maps onto the same `QuotaWindow` model the Codex rate limits use.
public enum ClaudeUsageParser {
    public enum ParseError: Error, Equatable {
        case invalidResponse
        case missingWindows
    }

    /// The two windows the Touch Bar shows. Claude also reports per-model
    /// weekly allowances, which are deliberately not surfaced.
    private static let windowKeys: [(key: String, kind: QuotaKind)] = [
        ("five_hour", .fiveHour),
        ("seven_day", .weekly),
    ]

    public static func parseResponse(_ object: [String: Any]) throws -> RateLimitParseResult {
        // The payload has been seen both at the top level and wrapped in a
        // container, so accept either shape rather than guessing one.
        let root = (object["usage"] as? [String: Any]) ?? object
        guard !root.isEmpty else { throw ParseError.invalidResponse }

        var collected: [QuotaWindow] = []
        for (key, kind) in windowKeys {
            guard let raw = root[key] as? [String: Any] else { continue }
            guard let used = percent(raw["utilization"]) else { continue }
            collected.append(QuotaWindow(
                kind: kind,
                usedPercent: used,
                durationMinutes: kind == .fiveHour ? 300 : 10_080,
                resetsAt: resetDate(raw["resets_at"])
            ))
        }

        guard !collected.isEmpty else { throw ParseError.missingWindows }
        return RateLimitParseResult(windows: collected)
    }

    public static func parse(data: Data) throws -> RateLimitParseResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidResponse
        }
        return try parseResponse(object)
    }

    /// Utilization arrives as a percentage, but a fractional 0...1 ratio is
    /// also accepted so a value of 0.42 is never shown as 0%.
    private static func percent(_ value: Any?) -> Int? {
        let number: Double
        switch value {
        case let value as Int: number = Double(value)
        case let value as Double: number = value
        case let value as NSNumber: number = value.doubleValue
        case let value as String: guard let parsed = Double(value) else { return nil }; number = parsed
        default: return nil
        }
        guard number.isFinite, number >= 0 else { return nil }
        let scaled = number > 0 && number <= 1 ? number * 100 : number
        return Int(scaled.rounded())
    }

    /// `resets_at` may be an epoch timestamp or an ISO-8601 string.
    private static func resetDate(_ value: Any?) -> Date? {
        switch value {
        case let value as Int: return Date(timeIntervalSince1970: TimeInterval(value))
        case let value as Double: return Date(timeIntervalSince1970: value)
        case let value as NSNumber: return Date(timeIntervalSince1970: value.doubleValue)
        case let value as String:
            if let seconds = TimeInterval(value) { return Date(timeIntervalSince1970: seconds) }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        default: return nil
        }
    }
}
