import CodexTouchBarCore
import Foundation

@MainActor
final class StatusStore {
    var onChange: ((DashboardSnapshot) -> Void)?

    private(set) var snapshot = DashboardSnapshot() {
        didSet { onChange?(snapshot) }
    }
    private var hookTasksByID: [String: TaskSnapshot] = [:]
    private var detectedTasksByID: [String: TaskSnapshot] = [:]
    private var titlesByID: [String: String] = [:]
    private var cleanupTimer: Timer?

    init() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.removeExpiredTasks() }
        }
    }

    func accept(_ packet: HookPacket) {
        if packet.eventName == "SessionEnd" {
            hookTasksByID.removeValue(forKey: packet.sessionID)
            publish()
            return
        }
        guard let phase = packet.phase else { return }

        if phase == .idle, hookTasksByID[packet.sessionID] == nil {
            return
        }

        let prior = hookTasksByID[packet.sessionID]
        let title = titlesByID[packet.sessionID] ?? prior?.title ?? packet.workspaceName
        hookTasksByID[packet.sessionID] = TaskSnapshot(
            sessionID: packet.sessionID,
            title: title,
            workspaceName: packet.workspaceName,
            phase: phase,
            toolName: phase == .usingTool ? packet.toolName : nil,
            startedAt: prior?.startedAt ?? packet.occurredAt,
            updatedAt: packet.occurredAt
        )
        publish()
    }

    func updateDetectedTasks(_ tasks: [TaskSnapshot]) {
        detectedTasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.sessionID, $0) })
        publish()
    }

    func updateThreadTitles(_ titles: [String: String]) {
        titlesByID.merge(titles) { _, new in new }
        for (id, title) in titles where hookTasksByID[id] != nil {
            hookTasksByID[id]?.title = title
        }
        publish()
    }

    func updateQuotas(_ windows: [QuotaWindow]) {
        snapshot.quotas = windows
        snapshot.quotaError = nil
    }

    func setQuotaError(_ message: String) {
        snapshot.quotaError = message
    }

    private func removeExpiredTasks() {
        let now = Date()
        hookTasksByID = hookTasksByID.filter { _, task in
            if task.phase == .completed || task.phase == .failed {
                return now.timeIntervalSince(task.updatedAt) < 12
            }
            return now.timeIntervalSince(task.updatedAt) < 60 * 60 * 8
        }
        publish()
    }

    private func publish() {
        var merged = detectedTasksByID
        for (id, task) in hookTasksByID { merged[id] = task }
        snapshot.tasks = merged.values
            .sorted { lhs, rhs in
                let lhsTerminal = lhs.phase == .completed || lhs.phase == .failed
                let rhsTerminal = rhs.phase == .completed || rhs.phase == .failed
                if lhsTerminal != rhsTerminal { return !lhsTerminal }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(3)
            .map { $0 }
    }
}
