import Foundation

public struct RateLimitParseResult: Equatable, Sendable {
    public let windows: [QuotaWindow]
    public init(windows: [QuotaWindow]) { self.windows = windows }
}

public enum RateLimitParser {
    public enum ParseError: Error, Equatable {
        case invalidResponse
        case missingRateLimits
    }

    public static func parseResponse(_ object: [String: Any]) throws -> RateLimitParseResult {
        guard let result = object["result"] as? [String: Any] else {
            throw ParseError.invalidResponse
        }

        var snapshots: [[String: Any]] = []
        if let byID = result["rateLimitsByLimitId"] as? [String: Any] {
            let preferredKeys = byID.keys.sorted { lhs, rhs in
                if lhs == "codex" { return true }
                if rhs == "codex" { return false }
                return lhs < rhs
            }
            for key in preferredKeys {
                if let snapshot = byID[key] as? [String: Any] {
                    snapshots.append(snapshot)
                }
            }
        }
        if snapshots.isEmpty, let snapshot = result["rateLimits"] as? [String: Any] {
            snapshots = [snapshot]
        }
        guard !snapshots.isEmpty else { throw ParseError.missingRateLimits }

        var collected: [QuotaWindow] = []
        for snapshot in snapshots {
            for key in ["primary", "secondary"] {
                guard let rawWindow = snapshot[key] as? [String: Any] else { continue }
                guard let used = integer(rawWindow["usedPercent"]) else { continue }
                let duration = integer(rawWindow["windowDurationMins"])
                let resetSeconds = integer(rawWindow["resetsAt"])
                let kind = classify(durationMinutes: duration)
                let window = QuotaWindow(
                    kind: kind,
                    usedPercent: used,
                    durationMinutes: duration,
                    resetsAt: resetSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                )
                if !collected.contains(where: { $0.kind == window.kind && $0.durationMinutes == window.durationMinutes }) {
                    collected.append(window)
                }
            }
            if collected.contains(where: { $0.kind == .fiveHour }) && collected.contains(where: { $0.kind == .weekly }) {
                break
            }
        }

        return RateLimitParseResult(windows: collected.sorted(by: quotaOrder))
    }

    public static func parseUpdatedNotification(_ object: [String: Any]) -> RateLimitParseResult? {
        guard
            object["method"] as? String == "account/rateLimits/updated",
            let params = object["params"] as? [String: Any],
            let snapshot = params["rateLimits"] as? [String: Any]
        else { return nil }

        let response: [String: Any] = ["result": ["rateLimits": snapshot]]
        return try? parseResponse(response)
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func classify(durationMinutes: Int?) -> QuotaKind {
        guard let durationMinutes else { return .other }
        if (240...360).contains(durationMinutes) { return .fiveHour }
        if (9_000...11_000).contains(durationMinutes) { return .weekly }
        return .other
    }

    private static func quotaOrder(_ lhs: QuotaWindow, _ rhs: QuotaWindow) -> Bool {
        func rank(_ kind: QuotaKind) -> Int {
            switch kind { case .fiveHour: return 0; case .weekly: return 1; case .other: return 2 }
        }
        return rank(lhs.kind) < rank(rhs.kind)
    }
}
