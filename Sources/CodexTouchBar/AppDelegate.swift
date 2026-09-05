import AppKit
import CodexTouchBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = StatusStore()
    private let socketServer = HookSocketServer()
    private let codexClient = CodexAppServerClient()
    private let activityMonitor = CodexActivityMonitor()
    private let touchBarController = TouchBarController()
    private var previewController: PreviewWindowController?
    private var statusItem: NSStatusItem?
    private var connectionMenuItem: NSMenuItem?

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
        activityMonitor.start()
        store.onChange?(store.snapshot)

        if CommandLine.arguments.contains("--preview") || !touchBarController.privateAPIAvailable {
            showPreviewWindow()
        }
        if CommandLine.arguments.contains("--demo") {
            installDemoTasks()
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
        if let snapshotPath = argumentValue(after: "--chrome-design-snapshot") {
            let preview = ensurePreviewController()
            preview.updateChromeTabs(Self.chromeDesignSamples)
            preview.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                try? self.previewController?.renderPNG(to: URL(fileURLWithPath: snapshotPath))
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        codexClient.stop()
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

    private static let chromeDesignSamples = [
        ChromeTabSnapshot(title: "YouTube 音乐", windowID: 1, tabID: 1, isActive: false),
        ChromeTabSnapshot(title: "GitHub 项目", windowID: 1, tabID: 2, isActive: false),
        ChromeTabSnapshot(title: "Google 搜索", windowID: 1, tabID: 3, isActive: false),
        ChromeTabSnapshot(title: "知乎问答", windowID: 1, tabID: 4, isActive: false),
        ChromeTabSnapshot(title: "哔哩哔哩", windowID: 1, tabID: 5, isActive: false),
        ChromeTabSnapshot(title: "Notion 文档", windowID: 1, tabID: 6, isActive: false),
        ChromeTabSnapshot(title: "Figma 设计", windowID: 1, tabID: 7, isActive: true),
        ChromeTabSnapshot(title: "OpenAI", windowID: 1, tabID: 8, isActive: false),
        ChromeTabSnapshot(title: "Apple", windowID: 1, tabID: 9, isActive: false),
        ChromeTabSnapshot(title: "Gmail", windowID: 1, tabID: 10, isActive: false),
        ChromeTabSnapshot(title: "微博热搜", windowID: 1, tabID: 11, isActive: false),
        ChromeTabSnapshot(title: "日历安排", windowID: 1, tabID: 12, isActive: false),
        ChromeTabSnapshot(title: "新闻阅读", windowID: 1, tabID: 13, isActive: false),
        ChromeTabSnapshot(title: "工作资料", windowID: 1, tabID: 14, isActive: false),
        ChromeTabSnapshot(title: "产品设计", windowID: 1, tabID: 15, isActive: false),
        ChromeTabSnapshot(title: "项目进度", windowID: 1, tabID: 16, isActive: false),
        ChromeTabSnapshot(title: "客户反馈", windowID: 1, tabID: 17, isActive: false),
        ChromeTabSnapshot(title: "数据报表", windowID: 1, tabID: 18, isActive: false),
        ChromeTabSnapshot(title: "旅行计划", windowID: 1, tabID: 19, isActive: false),
        ChromeTabSnapshot(title: "阅读清单", windowID: 1, tabID: 20, isActive: false),
    ]

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
