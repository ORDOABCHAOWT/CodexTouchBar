import Foundation

public enum TaskPhase: String, Codable, CaseIterable, Sendable {
    case thinking
    case usingTool
    case waitingApproval
    case waitingInput
    case completed
    case failed
    case idle

    public var shortLabel: String {
        switch self {
        case .thinking: return "思考中"
        case .usingTool: return "运行工具"
        case .waitingApproval: return "等待批准"
        case .waitingInput: return "等待输入"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .idle: return "待命"
        }
    }
}

public enum ClaudeTaskStatus {
    private static let activeLabels = ["Running", "Working", "Responding", "Thinking", "Using the browser", "Using the computer", "Using a tool", "Tool", "Awaiting input", "Awaiting your input", "Awaiting answer", "Waiting", "Waiting for input", "Approval required", "Awaiting approval"]
    public static func phase(for raw: String?) -> TaskPhase? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "running", "working", "responding", "thinking": return .thinking
        case "using the browser", "using the computer", "using a tool", "tool": return .usingTool
        case "awaiting input", "awaiting your input", "awaiting answer", "waiting", "waiting for input": return .waitingInput
        case "approval required", "awaiting approval": return .waitingApproval
        default: return nil
        }
    }

    public static func phase(forRowLabel raw: String?, title: String) -> TaskPhase? {
        guard let row = activeRow(raw), row.title == title.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return row.phase
    }

    public static func activeRow(_ raw: String?) -> (title: String, phase: TaskPhase)? {
        guard let raw else { return nil }
        let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for status in activeLabels {
            guard label.count > status.count, label.lowercased().hasPrefix(status.lowercased() + " "),
                  let phase = phase(for: status) else { continue }
            let title = label.dropFirst(status.count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 160, !title.contains("\n") else { continue }
            return (title, phase)
        }
        return nil
    }
}

public enum TaskProvider: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
}

public enum TaskCategory: String, Codable, CaseIterable, Sendable {
    case chat
    case code
    case cowork
    case navigation
}

public struct TaskRoute: Equatable, Sendable {
    public let provider: TaskProvider
    public let identifier: String
    public let category: TaskCategory
    public let requiresAccessibility: Bool
    public let supported: Bool

    public init(provider: TaskProvider, identifier: String, category: TaskCategory = .code, supported: Bool = true, requiresAccessibility: Bool = false) {
        self.provider = provider
        self.identifier = identifier
        self.category = category
        self.requiresAccessibility = requiresAccessibility
        self.supported = supported
    }
}

public struct HookPacket: Codable, Equatable, Sendable {
    public let sessionID: String
    public let turnID: String?
    public let workspaceName: String
    public let eventName: String
    public let toolName: String?
    public let occurredAt: Date

    public init(
        sessionID: String,
        turnID: String?,
        workspaceName: String,
        eventName: String,
        toolName: String?,
        occurredAt: Date
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.workspaceName = workspaceName
        self.eventName = eventName
        self.toolName = toolName
        self.occurredAt = occurredAt
    }

    public var phase: TaskPhase? {
        switch eventName {
        case "UserPromptSubmit": return .thinking
        case "PreToolUse": return .usingTool
        case "PermissionRequest": return .waitingApproval
        case "PostToolUse", "PostCompact", "SubagentStop": return .thinking
        case "Stop": return .completed
        case "SessionStart": return .idle
        case "SessionEnd": return nil
        default: return .thinking
        }
    }
}

public struct TaskSnapshot: Equatable, Sendable {
    public var provider: TaskProvider
    public let sessionID: String
    public var title: String
    public var workspaceName: String
    public var category: TaskCategory
    public var route: TaskRoute
    public var phase: TaskPhase
    public var toolName: String?
    public var startedAt: Date
    public var updatedAt: Date

    public init(
        provider: TaskProvider = .codex,
        sessionID: String,
        title: String,
        workspaceName: String,
        category: TaskCategory = .code,
        route: TaskRoute? = nil,
        phase: TaskPhase,
        toolName: String?,
        startedAt: Date,
        updatedAt: Date
    ) {
        self.provider = provider
        self.sessionID = sessionID
        self.title = title
        self.workspaceName = workspaceName
        self.category = category
        self.route = route ?? TaskRoute(provider: provider, identifier: sessionID, category: category)
        self.phase = phase
        self.toolName = toolName
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

public enum QuotaKind: String, Codable, Sendable {
    case fiveHour
    case weekly
    case other

    public var label: String {
        switch self {
        case .fiveHour: return "5小时"
        case .weekly: return "本周"
        case .other: return "额度"
        }
    }
}

public struct QuotaWindow: Equatable, Sendable {
    public let kind: QuotaKind
    public let usedPercent: Int
    public let durationMinutes: Int?
    public let resetsAt: Date?

    public init(kind: QuotaKind, usedPercent: Int, durationMinutes: Int?, resetsAt: Date?) {
        self.kind = kind
        self.usedPercent = min(100, max(0, usedPercent))
        self.durationMinutes = durationMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Int { 100 - usedPercent }
}

public struct DashboardSnapshot: Equatable, Sendable {
    public var provider: TaskProvider
    public var tasks: [TaskSnapshot]
    public var quotas: [QuotaWindow]
    public var quotaError: String?
    public var refreshedAt: Date?
    public var refreshError: String?
    public var taskError: String?
    public var quotaSource: String?

    public init(provider: TaskProvider = .codex, tasks: [TaskSnapshot] = [], quotas: [QuotaWindow] = [], quotaError: String? = nil, refreshedAt: Date? = nil, refreshError: String? = nil, quotaSource: String? = nil, taskError: String? = nil) {
        self.provider = provider
        self.tasks = tasks
        self.quotas = quotas
        self.quotaError = quotaError
        self.refreshedAt = refreshedAt
        self.refreshError = refreshError
        self.quotaSource = quotaSource
        self.taskError = taskError
    }
}

public enum ClaudeUsageParser {
    public enum ParseError: Error, Equatable { case invalidResponse, missingUsage }
    public struct HistoryResult: Sendable {
        public let windows: [QuotaWindow]; public let sampledAt: Date; public let organization: String
    }
    public static func parsePlanUsage(_ object: [String: Any]) throws -> [QuotaWindow] { try parseHistory(object, now: Date()).windows }
    public static func parseHistory(_ object: [String: Any], now: Date) throws -> HistoryResult {
        guard let version = object["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 2,
              let samples = object["samples"] as? [[String: Any]], !samples.isEmpty else { throw ParseError.invalidResponse }
        let candidates: [(Date, String, [String: Any])] = samples.compactMap { sample in
            guard let rawT = sample["t"] as? NSNumber, CFGetTypeID(rawT) != CFBooleanGetTypeID(), rawT.doubleValue.isFinite else { return nil }
            let seconds = rawT.doubleValue / 1000; let date = Date(timeIntervalSince1970: seconds)
            guard seconds > 0, date <= now.addingTimeInterval(300), let org = sample["org"] as? String, org.range(of: #"^[A-Za-z0-9-]{1,120}$"#, options: .regularExpression) != nil, let usage = sample["u"] as? [String: Any] else { return nil }
            return (date, org, usage)
        }
        guard let chosen = candidates.max(by: { $0.0 < $1.0 }) else { throw ParseError.missingUsage }
        let usage = chosen.2
        func percent(_ key: String) -> Int? {
            guard let value = usage[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite, (0...100).contains(value.doubleValue) else { return nil }
            return Int(value.doubleValue.rounded())
        }
        guard let fiveHour = percent("fh"), let sevenDay = percent("sd") else { throw ParseError.missingUsage }
        return HistoryResult(windows: [
            QuotaWindow(kind: .fiveHour, usedPercent: fiveHour, durationMinutes: 300, resetsAt: nil),
            QuotaWindow(kind: .weekly, usedPercent: sevenDay, durationMinutes: 10_080, resetsAt: nil),
        ], sampledAt: chosen.0, organization: chosen.1)
    }

    public static func parseOAuthUsage(_ object: [String: Any]) throws -> [QuotaWindow] {
        func read(_ key: String, duration: Int) -> QuotaWindow? {
            guard let item = object[key] as? [String: Any],
                  let number = item["utilization"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let value = number.doubleValue
            guard value.isFinite, (0...100).contains(value) else { return nil }
            let reset = (item["resets_at"] as? String).flatMap { text -> Date? in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
            }
            return QuotaWindow(kind: duration == 300 ? .fiveHour : .weekly, usedPercent: Int(value.rounded()), durationMinutes: duration, resetsAt: reset)
        }
        let windows = [read("five_hour", duration: 300), read("seven_day", duration: 10_080)].compactMap { $0 }
        guard !windows.isEmpty else { throw ParseError.missingUsage }
        return windows
    }
}
