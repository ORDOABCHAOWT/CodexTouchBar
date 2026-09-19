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
    public let sessionID: String
    public var title: String
    public var workspaceName: String
    public var phase: TaskPhase
    public var toolName: String?
    public var startedAt: Date
    public var updatedAt: Date

    public init(
        sessionID: String,
        title: String,
        workspaceName: String,
        phase: TaskPhase,
        toolName: String?,
        startedAt: Date,
        updatedAt: Date
    ) {
        self.sessionID = sessionID
        self.title = title
        self.workspaceName = workspaceName
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
    public var tasks: [TaskSnapshot]
    public var quotas: [QuotaWindow]
    public var quotaError: String?

    public init(tasks: [TaskSnapshot] = [], quotas: [QuotaWindow] = [], quotaError: String? = nil) {
        self.tasks = tasks
        self.quotas = quotas
        self.quotaError = quotaError
    }
}
