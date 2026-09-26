import Foundation

public struct ClaudeRefreshPolicy: Sendable {
    public enum Reason: Sendable { case foreground, periodic, manual }
    public private(set) var lastAttempt: Date?
    public private(set) var lastSuccess: Date?
    public private(set) var failures = 0
    public private(set) var inFlight = false
    public init() {}
    public mutating func begin(_ reason: Reason, now: Date) -> Bool {
        guard !inFlight else { return false }
        if reason != .manual, let lastAttempt {
            let interval = reason == .foreground ? 30.0 : 60.0
            guard now.timeIntervalSince(lastAttempt) >= interval, now >= failureDeadline else { return false }
        }
        inFlight = true; lastAttempt = now; return true
    }
    public mutating func finish(success: Bool, now: Date) { inFlight = false; if success { failures = 0; lastSuccess = now } else { failures += 1 } }
    public var failureDeadline: Date { guard failures > 0, let lastAttempt else { return .distantPast }; return lastAttempt.addingTimeInterval(min(900, 60 * pow(2, Double(failures - 1)))) }
}
