import CodexTouchBarCore
import Foundation

/// Reports Claude Code sessions that are currently active.
///
/// Claude Code has no app server to query, but it appends to a JSONL
/// transcript per session under ~/.claude/projects. A file whose modification
/// time is recent is a session doing work right now, and its first user
/// message is the title that identifies it.
final class ClaudeActivityMonitor {
    var onTasks: (([TaskSnapshot]) -> Void)?

    /// Matches CodexActivityMonitor: a session is "live" while its transcript
    /// has been written to within this window.
    private let activityWindow: TimeInterval = 2 * 60

    private let queue = DispatchQueue(label: "com.whitney.CodexTouchBar.claude-activity", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var stopped = false
    private var firstSeen: [String: Date] = [:]
    /// Titles are parsed once per session: the first user message never
    /// changes, and re-reading a long transcript every 2s would be wasteful.
    private var titleCache: [String: String] = [:]

    private static var projectsDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    func start() {
        queue.async { [weak self] in
            guard let self, timer == nil else { return }
            stopped = false
            let timer = DispatchSource.makeTimerSource(queue: queue)
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
            titleCache.removeAll()
        }
    }

    deinit { stop() }

    private func refresh() {
        guard !stopped else { return }
        let now = Date()
        let cutoff = now.addingTimeInterval(-activityWindow)
        var liveIDs = Set<String>()
        var tasks: [TaskSnapshot] = []

        for transcript in Self.recentTranscripts(since: cutoff) {
            let sessionID = transcript.url.deletingPathExtension().lastPathComponent
            liveIDs.insert(sessionID)
            let startedAt = firstSeen[sessionID] ?? transcript.modifiedAt
            firstSeen[sessionID] = startedAt

            let title: String
            if let cached = titleCache[sessionID] {
                title = cached
            } else {
                title = CodexActivityMonitor.displayTitle(
                    from: Self.meaningfulLines(of: Self.firstUserMessage(in: transcript.url) ?? ""),
                    fallback: "Claude 任务"
                )
                titleCache[sessionID] = title
            }

            tasks.append(TaskSnapshot(
                sessionID: sessionID,
                title: title,
                workspaceName: Self.workspaceName(for: transcript.url),
                phase: .thinking,
                toolName: nil,
                startedAt: min(startedAt, now),
                updatedAt: transcript.modifiedAt
            ))
        }

        firstSeen = firstSeen.filter { liveIDs.contains($0.key) }
        titleCache = titleCache.filter { liveIDs.contains($0.key) }
        let ordered = tasks.sorted { $0.updatedAt > $1.updatedAt }
        DispatchQueue.main.async { [weak self] in self?.onTasks?(ordered) }
    }

    private struct Transcript {
        let url: URL
        let modifiedAt: Date
    }

    private static func recentTranscripts(since cutoff: Date) -> [Transcript] {
        let manager = FileManager.default
        guard let projects = try? manager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [Transcript] = []
        for project in projects {
            guard let files = try? manager.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate, modified >= cutoff else { continue }
                found.append(Transcript(url: file, modifiedAt: modified))
            }
        }
        return found
    }

    /// The directory name encodes the project path, e.g. "-Users-whitney-Downloads".
    private static func workspaceName(for transcript: URL) -> String {
        let encoded = transcript.deletingLastPathComponent().lastPathComponent
        let last = encoded.split(separator: "-").last.map(String.init) ?? ""
        return last.isEmpty ? "Claude" : last
    }

    /// Drops leading lines that only name a file or directory. A prompt often
    /// opens with a bare path before the actual request, and a path makes a
    /// useless title — every session in the same project would look alike.
    private static func meaningfulLines(of message: String) -> String {
        let lines = message
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let kept = lines.drop { line in
            line.isEmpty || isPathOnly(line)
        }
        return kept.isEmpty ? message : kept.joined(separator: "\n")
    }

    private static func isPathOnly(_ line: String) -> Bool {
        let unquoted = line.trimmingCharacters(in: CharacterSet(charactersIn: "'\"`"))
        guard unquoted.hasPrefix("/") || unquoted.hasPrefix("~/") else { return false }
        // A path used as a label has no spaces after it; a sentence mentioning
        // a path keeps going, so only treat the bare form as skippable.
        return !unquoted.contains(" ") || unquoted.split(separator: "/").count > 2
    }

    /// Returns the text of the first user message, which serves as the title.
    /// Reads line by line and stops at the first match so a large transcript is
    /// never loaded whole.
    private static func firstUserMessage(in url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var buffer = Data()
        // A title lives near the start; cap the scan so a huge transcript
        // cannot stall the 2s refresh.
        let limit = 512 * 1024
        while buffer.count < limit {
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            buffer.append(chunk)
            if let text = extractFirstUserText(from: buffer) { return text }
        }
        return extractFirstUserText(from: buffer)
    }

    private static func extractFirstUserText(from data: Data) -> String? {
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "user",
                  let message = object["message"] as? [String: Any]
            else { continue }
            if let text = message["content"] as? String, !text.isEmpty { return text }
            if let blocks = message["content"] as? [[String: Any]] {
                let text = blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
                if !text.isEmpty { return text }
            }
        }
        return nil
    }
}
