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

do {
    try checkHookAllowlist()
    try checkRateLimits()
    print("CodexTouchBarCoreChecks passed")
} catch {
    fputs("CodexTouchBarCoreChecks failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
