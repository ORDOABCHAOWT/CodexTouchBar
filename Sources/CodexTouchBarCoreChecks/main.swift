import CodexTouchBarCore
import Foundation

private enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): return message }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

private func checkHookAllowlist() throws {
    let json: [String: Any] = [
        "session_id": "thr_secret",
        "turn_id": "turn_1",
        "hook_event_name": "PreToolUse",
        "cwd": "/Users/whitney/Secret Project",
        "tool_name": "mcp__server__browser",
        "transcript_path": "/secret/full/transcript.jsonl",
        "tool_input": ["command": "cat ~/.ssh/id_ed25519"],
        "tool_response": "private output",
        "model": "private-model",
        "permission_mode": "bypassPermissions",
    ]
    let data = try JSONSerialization.data(withJSONObject: json)
    let packet = try HookPacketParser.parse(data: data, now: Date(timeIntervalSince1970: 10))
    try expect(packet.workspaceName == "Secret Project", "workspace basename was not sanitized")
    try expect(packet.toolName == "browser", "tool display name was not sanitized")

    let text = String(decoding: try JSONEncoder().encode(packet), as: UTF8.self)
    for forbidden in ["transcript", "id_ed25519", "/Users/whitney", "private-model", "private output"] {
        try expect(!text.contains(forbidden), "sensitive field leaked into HookPacket: \(forbidden)")
    }
    try expect(packet.phase == .usingTool, "PreToolUse phase mapping failed")
}

private func checkRateLimits() throws {
    let response: [String: Any] = [
        "id": 2,
        "result": [
            "rateLimitsByLimitId": [
                "codex": [
                    "primary": ["usedPercent": 27, "windowDurationMins": 300, "resetsAt": 2_000_000_000],
                    "secondary": ["usedPercent": 61, "windowDurationMins": 10_080, "resetsAt": 2_000_100_000],
                ]
            ]
        ]
    ]
    let windows = try RateLimitParser.parseResponse(response).windows
    try expect(windows.map(\.kind) == [.fiveHour, .weekly], "quota windows were classified incorrectly")
    try expect(windows.map(\.remainingPercent) == [73, 39], "remaining quota calculation failed")

    let clamped: [String: Any] = [
        "result": ["rateLimits": ["primary": ["usedPercent": 140, "windowDurationMins": 300]]]
    ]
    let clampedWindow = try RateLimitParser.parseResponse(clamped).windows.first
    try expect(clampedWindow?.remainingPercent == 0, "quota clamp failed")
}

private func checkClaudeUsage() throws {
    let payload: [String: Any] = [
        "five_hour": ["utilization": 18, "resets_at": 2_000_000_000],
        "seven_day": ["utilization": 47, "resets_at": 2_000_100_000],
        "seven_day_opus": ["utilization": 72, "resets_at": 2_000_100_000],
        "seven_day_sonnet": ["utilization": 5, "resets_at": 2_000_100_000],
    ]
    let windows = try ClaudeUsageParser.parseResponse(payload).windows
    try expect(
        windows.map(\.kind) == [.fiveHour, .weekly, .weeklyOpus, .weeklySonnet],
        "Claude usage windows were classified incorrectly"
    )
    try expect(windows.map(\.remainingPercent) == [82, 53, 28, 95], "Claude remaining quota calculation failed")
    try expect(windows[0].resetsAt == Date(timeIntervalSince1970: 2_000_000_000), "Claude reset time was not parsed")

    // Plans without per-model allowances must still report the shared windows.
    let partial: [String: Any] = ["five_hour": ["utilization": 10], "seven_day": ["utilization": 20]]
    let partialWindows = try ClaudeUsageParser.parseResponse(partial).windows
    try expect(partialWindows.map(\.kind) == [.fiveHour, .weekly], "optional Claude windows were not skipped")

    // The payload is also accepted wrapped in a container.
    let wrapped: [String: Any] = ["usage": ["five_hour": ["utilization": 30]]]
    let wrappedWindow = try ClaudeUsageParser.parseResponse(wrapped).windows.first
    try expect(wrappedWindow?.remainingPercent == 70, "wrapped Claude payload was not parsed")

    // A 0...1 ratio must not be reported as 0%.
    let ratio: [String: Any] = ["five_hour": ["utilization": 0.42]]
    let ratioWindow = try ClaudeUsageParser.parseResponse(ratio).windows.first
    try expect(ratioWindow?.usedPercent == 42, "fractional utilization was not scaled")

    // ISO-8601 reset timestamps appear alongside epoch seconds.
    let iso: [String: Any] = ["five_hour": ["utilization": 10, "resets_at": "2033-05-18T03:33:20Z"]]
    let isoWindow = try ClaudeUsageParser.parseResponse(iso).windows.first
    try expect(isoWindow?.resetsAt != nil, "ISO-8601 reset time was not parsed")

    var threw = false
    do { _ = try ClaudeUsageParser.parseResponse(["unrelated": 1]) } catch { threw = true }
    try expect(threw, "a payload with no usage windows must fail")
}

private func checkProviderSelection() throws {
    let codexWindow = QuotaWindow(kind: .fiveHour, usedPercent: 10, durationMinutes: 300, resetsAt: nil)
    let claudeWindow = QuotaWindow(kind: .weeklyOpus, usedPercent: 60, durationMinutes: 10_080, resetsAt: nil)
    var snapshot = DashboardSnapshot(quotas: [codexWindow], claudeQuotas: [claudeWindow])

    try expect(snapshot.provider == .codex, "Codex must remain the default provider")
    try expect(snapshot.activeQuotas.map(\.kind) == [.fiveHour], "Codex quotas were not selected by default")

    snapshot.provider = .claude
    try expect(snapshot.activeQuotas.map(\.kind) == [.weeklyOpus], "Claude quotas were not selected when active")

    // An error from one provider must never surface under the other's label.
    snapshot.quotaError = "codex offline"
    try expect(snapshot.activeQuotaError == nil, "Codex error leaked into the Claude view")
    snapshot.claudeQuotaError = "claude offline"
    try expect(snapshot.activeQuotaError == "claude offline", "Claude error was not surfaced")
}


do {
    try checkHookAllowlist()
    try checkRateLimits()
    try checkClaudeUsage()
    try checkProviderSelection()
    print("CodexTouchBarCoreChecks passed")
} catch {
    fputs("CodexTouchBarCoreChecks failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
