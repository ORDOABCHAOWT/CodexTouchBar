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

private func checkProviderSelection() throws {
    let codexWindow = QuotaWindow(kind: .fiveHour, usedPercent: 10, durationMinutes: 300, resetsAt: nil)
    var snapshot = DashboardSnapshot(quotas: [codexWindow], quotaError: nil)

    try expect(snapshot.provider == .codex, "Codex must remain the default provider")
    try expect(snapshot.showsQuotas, "Codex must show quotas")
    try expect(snapshot.activeQuotas.map(\.kind) == [.fiveHour], "Codex quotas were not shown")

    // Quotas come from the Codex app server, so the Claude view shows tasks
    // only and must never present Codex's numbers as Claude's.
    snapshot.provider = .claude
    try expect(!snapshot.showsQuotas, "Claude must not show quota blocks")
    try expect(snapshot.activeQuotas.isEmpty, "Codex quotas leaked into the Claude view")

    snapshot.quotaError = "codex offline"
    try expect(snapshot.activeQuotaError == nil, "a Codex error leaked into the Claude view")
    snapshot.provider = .codex
    try expect(snapshot.activeQuotaError == "codex offline", "the Codex error was not surfaced")

    // The strip labels itself with the active assistant's name.
    try expect(UsageProvider.claude.label == "Claude", "Claude label is wrong")
    try expect(UsageProvider.codex.label == "Codex", "Codex label is wrong")
}


do {
    try checkHookAllowlist()
    try checkRateLimits()
    try checkProviderSelection()
    print("CodexTouchBarCoreChecks passed")
} catch {
    fputs("CodexTouchBarCoreChecks failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
