import CodexTouchBarCore
import Foundation

final class CodexAppServerClient {
    var onQuotas: (([QuotaWindow]) -> Void)?
    var onThreadTitles: (([String: String]) -> Void)?
    var onError: ((String) -> Void)?

    private enum RequestKind { case initialize, rateLimits, threadList }
    private let queue = DispatchQueue(label: "com.whitney.CodexTouchBar.app-server")
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var requestKinds: [Int: RequestKind] = [:]
    private var nextRequestID = 1
    private var timer: DispatchSourceTimer?
    private var isInitialized = false
    private var isStopped = false

    func start() {
        queue.async { [weak self] in
            self?.isStopped = false
            self?.launchIfNeeded()
        }
    }

    func stop() {
        queue.sync {
            isStopped = true
            timer?.cancel()
            timer = nil
            input?.closeFile()
            input = nil
            if let process, process.isRunning { process.terminate() }
            process = nil
        }
    }

    deinit { stop() }

    private func launchIfNeeded() {
        guard process?.isRunning != true else { return }
        guard let executable = findCodexExecutable() else {
            emitError("找不到 Codex App Server")
            return
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] _ in
            self?.queue.asyncAfter(deadline: .now() + 5) {
                guard self?.isStopped == false else { return }
                self?.launchIfNeeded()
            }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { _ in _ = stderrPipe.fileHandleForReading.availableData }

        do {
            try process.run()
            self.process = process
            input = stdinPipe.fileHandleForWriting
            isInitialized = false
            sendInitialize()
        } catch {
            emitError("无法启动 Codex App Server")
        }
    }

    private func sendInitialize() {
        let id = allocate(.initialize)
        send([
            "method": "initialize",
            "id": id,
            "params": [
                "clientInfo": [
                    "name": "codex_touch_bar",
                    "title": "Codex Touch Bar",
                    "version": "0.1.0",
                ],
                "capabilities": [
                    "experimentalApi": false,
                    "optOutNotificationMethods": [
                        "item/agentMessage/delta",
                        "item/reasoning/textDelta",
                        "item/commandExecution/outputDelta",
                    ],
                ],
            ],
        ])
        send(["method": "initialized", "params": [:]])
    }

    private func beginPolling() {
        guard !isInitialized else { return }
        isInitialized = true
        refresh()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        self.timer = timer
    }

    private func refresh() {
        let rateID = allocate(.rateLimits)
        send(["method": "account/rateLimits/read", "id": rateID, "params": [:]])
        let listID = allocate(.threadList)
        send([
            "method": "thread/list",
            "id": listID,
            "params": [
                "limit": 100,
                "sortKey": "updated_at",
                "sortDirection": "desc",
                "archived": false,
                "useStateDbOnly": true,
                "sourceKinds": ["appServer", "cli", "vscode"],
            ],
        ])
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer.prefix(upTo: newline)
            outputBuffer.removeSubrange(...newline)
            guard
                !line.isEmpty,
                let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }
            handle(object)
        }
    }

    private func handle(_ object: [String: Any]) {
        if let notification = RateLimitParser.parseUpdatedNotification(object) {
            emitQuotas(notification.windows)
            return
        }
        guard let id = (object["id"] as? NSNumber)?.intValue ?? object["id"] as? Int else { return }
        guard let kind = requestKinds.removeValue(forKey: id) else { return }
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Codex 接口返回错误"
            emitError(message)
            return
        }
        switch kind {
        case .initialize:
            beginPolling()
        case .rateLimits:
            do { emitQuotas(try RateLimitParser.parseResponse(object).windows) }
            catch { emitError("暂时无法读取额度") }
        case .threadList:
            emitThreadTitles(parseThreadTitles(object))
        }
    }

    private func parseThreadTitles(_ object: [String: Any]) -> [String: String] {
        guard
            let result = object["result"] as? [String: Any],
            let data = result["data"] as? [[String: Any]]
        else { return [:] }
        var titles: [String: String] = [:]
        for thread in data {
            guard let id = thread["id"] as? String else { continue }
            // title, preview, and firstUserMessage can all be derived from
            // request body content. Only an explicit thread name is safe to
            // use as a Touch Bar project label.
            let rawTitle = (thread["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let rawTitle, !rawTitle.isEmpty else { continue }
            titles[id] = CodexActivityMonitor.displayTitle(from: rawTitle, fallback: "Codex")
        }
        return titles
    }

    private func allocate(_ kind: RequestKind) -> Int {
        defer { nextRequestID += 1 }
        requestKinds[nextRequestID] = kind
        return nextRequestID
    }

    private func send(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object), let input else { return }
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        do { try input.write(contentsOf: data) }
        catch { emitError("Codex 数据连接已断开") }
    }

    private func emitQuotas(_ windows: [QuotaWindow]) {
        DispatchQueue.main.async { [weak self] in self?.onQuotas?(windows) }
    }

    private func emitThreadTitles(_ titles: [String: String]) {
        DispatchQueue.main.async { [weak self] in self?.onThreadTitles?(titles) }
    }

    private func emitError(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onError?(message) }
    }

    private func findCodexExecutable() -> URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }
}
