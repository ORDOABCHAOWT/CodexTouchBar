import Foundation

public enum HookPacketParser {
    public enum ParseError: Error, Equatable {
        case invalidJSON
        case missingSessionID
        case missingEventName
    }

    /// Decodes only the small display allowlist. Sensitive hook fields are never copied.
    public static func parse(data: Data, now: Date = Date()) throws -> HookPacket {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ParseError.invalidJSON
        }

        guard let sessionID = nonempty(object["session_id"] as? String) else {
            throw ParseError.missingSessionID
        }
        guard let eventName = nonempty(object["hook_event_name"] as? String) else {
            throw ParseError.missingEventName
        }

        let turnID = nonempty(object["turn_id"] as? String)
        let toolName = sanitizedToolName(object["tool_name"] as? String)
        let workspaceName = sanitizedWorkspaceName(object["cwd"] as? String)

        return HookPacket(
            sessionID: sessionID,
            turnID: turnID,
            workspaceName: workspaceName,
            eventName: eventName,
            toolName: toolName,
            occurredAt: now
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(160))
    }

    private static func sanitizedWorkspaceName(_ cwd: String?) -> String {
        guard let cwd = nonempty(cwd) else { return "Codex 任务" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        let cleaned = name.replacingOccurrences(of: "\n", with: " ")
        return cleaned.isEmpty ? "Codex 任务" : String(cleaned.prefix(42))
    }

    private static func sanitizedToolName(_ value: String?) -> String? {
        guard let value = nonempty(value) else { return nil }
        let leaf = value.split(separator: "_").last.map(String.init) ?? value
        return String(leaf.replacingOccurrences(of: "\n", with: " ").prefix(28))
    }
}
