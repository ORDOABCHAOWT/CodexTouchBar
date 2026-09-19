import AppKit
import CodexTouchBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = StatusStore()
    private let socketServer = HookSocketServer()
    private let codexClient = CodexAppServerClient()
    private let claudeClient = ClaudeUsageClient()
    private let activityMonitor = CodexActivityMonitor()
    private let touchBarController = TouchBarController()
    private var previewController: PreviewWindowController?
    private var statusItem: NSStatusItem?
    private var connectionMenuItem: NSMenuItem?
    /// Set by the demo flags so a snapshot renders one provider deterministically.
    private var forcedProvider = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        bindData()

        do {
            try socketServer.start { [weak self] packet in
                Task { @MainActor in self?.store.accept(packet) }
            }
        } catch {
            store.setQuotaError("任务连接启动失败")
        }

        touchBarController.install()
        codexClient.start()
        claudeClient.start()
        activityMonitor.start()
        store.onChange?(store.snapshot)

        if CommandLine.arguments.contains("--preview") || !touchBarController.privateAPIAvailable {
            showPreviewWindow()
        }
        if CommandLine.arguments.contains("--demo") {
            installDemoTasks()
            forcedProvider = true
            store.setProvider(.codex)
        }
        // Renders the Claude layout without contacting the usage endpoint, so
        // the strip can be inspected offline.
        if CommandLine.arguments.contains("--demo-claude") {
            installDemoTasks()
            store.updateClaudeQuotas([
                QuotaWindow(kind: .fiveHour, usedPercent: 18, durationMinutes: 300, resetsAt: nil),
                QuotaWindow(kind: .weekly, usedPercent: 47, durationMinutes: 10_080, resetsAt: nil),
                QuotaWindow(kind: .weeklyOpus, usedPercent: 72, durationMinutes: 10_080, resetsAt: nil),
                QuotaWindow(kind: .weeklySonnet, usedPercent: 5, durationMinutes: 10_080, resetsAt: nil),
            ])
            forcedProvider = true
            store.setProvider(.claude)
        }
        if let snapshotPath = argumentValue(after: "--snapshot") {
            let preview = ensurePreviewController()
            preview.show()
            let delay = Double(argumentValue(after: "--snapshot-delay") ?? "8") ?? 8
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1, min(30, delay))) { [weak self] in
                guard let self else { return }
                try? self.previewController?.renderPNG(to: URL(fileURLWithPath: snapshotPath))
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        codexClient.stop()
        claudeClient.stop()
        activityMonitor.stop()
        socketServer.stop()
        touchBarController.uninstall()
    }

    private func bindData() {
        store.onChange = { [weak self] snapshot in
            self?.touchBarController.update(snapshot)
            self?.previewController?.update(snapshot)
        }
        codexClient.onQuotas = { [weak self] windows in self?.store.updateQuotas(windows) }
        codexClient.onThreadTitles = { [weak self] titles in self?.store.updateThreadTitles(titles) }
        codexClient.onError = { [weak self] message in self?.store.setQuotaError(message) }
        activityMonitor.onTasks = { [weak self] tasks in self?.store.updateDetectedTasks(tasks) }
        claudeClient.onQuotas = { [weak self] windows in self?.store.updateClaudeQuotas(windows) }
        claudeClient.onError = { [weak self] message in self?.store.setClaudeQuotaError(message) }
        touchBarController.onProviderChange = { [weak self] provider in
            guard let self, !forcedProvider else { return }
            store.setProvider(provider)
            // Refresh on switch so the numbers shown are current rather than
            // whatever the last poll left behind.
            if provider == .claude { claudeClient.refreshNow() }
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "CodexTouchBar")
        item.button?.toolTip = "CodexTouchBar"
        let menu = NSMenu()

        let preview = NSMenuItem(title: "显示界面预览", action: #selector(showPreview), keyEquivalent: "p")
        preview.target = self
        menu.addItem(preview)

        let present = NSMenuItem(title: "重新显示 Touch Bar", action: #selector(presentTouchBar), keyEquivalent: "t")
        present.target = self
        menu.addItem(present)
        menu.addItem(.separator())

        let connection = NSMenuItem(title: "", action: #selector(toggleConnection), keyEquivalent: "")
        connection.target = self
        menu.addItem(connection)
        connectionMenuItem = connection
        refreshConnectionMenuTitle()

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 CodexTouchBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func showPreview() {
        showPreviewWindow()
    }

    @objc private func presentTouchBar() {
        touchBarController.present()
    }

    @objc private func toggleConnection() {
        do {
            if HookConfiguration.isInstalled() {
                try HookConfiguration.uninstall()
            } else {
                try HookConfiguration.install(executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0])
            }
            refreshConnectionMenuTitle()
            showConnectionAlert(success: true, message: HookConfiguration.isInstalled()
                ? "Codex 状态连接已安装。新发生的任务活动会立即显示。"
                : "Codex 状态连接已移除。额度显示不受影响。")
        } catch {
            showConnectionAlert(success: false, message: error.localizedDescription)
        }
    }

    private func refreshConnectionMenuTitle() {
        connectionMenuItem?.title = HookConfiguration.isInstalled()
            ? "移除 Codex 状态连接"
            : "安装 Codex 状态连接"
    }

    private func showConnectionAlert(success: Bool, message: String) {
        let alert = NSAlert()
        alert.alertStyle = success ? .informational : .warning
        alert.messageText = success ? "CodexTouchBar" : "操作未完成"
        alert.informativeText = message
        alert.runModal()
    }

    private func installDemoTasks() {
        let now = Date()
        let samples = [
            HookPacket(sessionID: "demo-1", turnID: "turn-1", workspaceName: "CodexTouchBar", eventName: "PreToolUse", toolName: "swift", occurredAt: now.addingTimeInterval(-83)),
            HookPacket(sessionID: "demo-2", turnID: "turn-2", workspaceName: "图标优化", eventName: "PermissionRequest", toolName: nil, occurredAt: now.addingTimeInterval(-41)),
            HookPacket(sessionID: "demo-3", turnID: "turn-3", workspaceName: "安全检查", eventName: "UserPromptSubmit", toolName: nil, occurredAt: now.addingTimeInterval(-12)),
        ]
        samples.forEach(store.accept)
    }

    private func ensurePreviewController() -> PreviewWindowController {
        if let previewController { return previewController }
        let controller = PreviewWindowController()
        controller.update(store.snapshot)
        previewController = controller
        return controller
    }

    private func showPreviewWindow() {
        ensurePreviewController().show()
    }

    private func argumentValue(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag) else { return nil }
        let next = CommandLine.arguments.index(after: index)
        guard next < CommandLine.arguments.endIndex else { return nil }
        return CommandLine.arguments[next]
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
