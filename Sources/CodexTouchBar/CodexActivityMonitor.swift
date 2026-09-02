import CodexTouchBarCore
import Foundation
import TouchBarPrivateBridge

final class CodexActivityMonitor {
    var onTasks: (([TaskSnapshot]) -> Void)?

    // This is only a fallback for tasks that began before the app launched.
    // Live hook events carry Start/Stop state, so a short window avoids keeping
    // completed history on the Touch Bar.
    private let activityWindow: TimeInterval = 2 * 60

    private let queue = DispatchQueue(label: "com.whitney.CodexTouchBar.activity", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var firstSeen: [String: Date] = [:]
    private var stopped = false

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            self.stopped = false
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.refresh() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            timer?.cancel()
            timer = nil
            firstSeen.removeAll()
        }
    }

    deinit { stop() }

    private func refresh() {
        guard !stopped else { return }
        let rows = CTBReadRecentCodexActivity(activityWindow)
        let now = Date()
        var liveIDs = Set<String>()
        let tasks: [TaskSnapshot] = rows.compactMap { row in
            guard
                let id = row["id"] as? String,
                let updatedSeconds = (row["updatedAt"] as? NSNumber)?.doubleValue
            else { return nil }
            liveIDs.insert(id)
            let updatedAt = Date(timeIntervalSince1970: updatedSeconds)
            let startedAt = firstSeen[id] ?? updatedAt
            firstSeen[id] = startedAt
            let workspace = (row["workspace"] as? String).flatMap(Self.nonempty) ?? "Codex"
            let rawTitle = row["rawTitle"] as? String ?? ""
            return TaskSnapshot(
                sessionID: id,
                title: Self.displayTitle(from: rawTitle, fallback: workspace),
                workspaceName: workspace,
                phase: .thinking,
                toolName: nil,
                startedAt: min(startedAt, now),
                updatedAt: updatedAt
            )
        }
        firstSeen = firstSeen.filter { liveIDs.contains($0.key) }
        DispatchQueue.main.async { [weak self] in self?.onTasks?(tasks) }
    }

    static func displayTitle(from rawTitle: String, fallback: String) -> String {
        let lines = rawTitle
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var candidates = lines
        if let requestIndex = lines.firstIndex(where: { $0.lowercased() == "## my request:" }) {
            candidates = Array(lines.dropFirst(requestIndex + 1))
        }
        let ignoredPrefixes = ["# files mentioned", "## codex-", "distinguish instructions", "<image", "!["]
        let selected = candidates.first { line in
            guard !line.isEmpty else { return false }
            let lower = line.lowercased()
            return !ignoredPrefixes.contains(where: { lower.hasPrefix($0) })
        }
        let cleaned = (selected ?? fallback)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*`_- "))
            .replacingOccurrences(of: "\t", with: " ")
        // The Touch Bar button uses AppKit's tail truncation, so keep a useful
        // title in memory and let its actual width decide how much is visible.
        return String((nonempty(cleaned) ?? fallback).prefix(80))
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
