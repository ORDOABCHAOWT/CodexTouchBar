import AppKit
import CodexTouchBarCore
import TouchBarPrivateBridge

@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    private let trayIdentifier = NSTouchBarItem.Identifier("com.whitney.CodexTouchBar.control-strip")
    private let dashboardIdentifier = NSTouchBarItem.Identifier("com.whitney.CodexTouchBar.dashboard")
    private let dashboardView = DashboardStripView(frame: .zero)
    private let touchBar = NSTouchBar()
    private var trayItem: NSCustomTouchBarItem?
    private var workspaceObserver: NSObjectProtocol?
    private var isInstalled = false
    private let codexBundleIdentifiers: Set<String> = ["com.openai.codex", "com.openai.chatgpt"]
    private let chromeBundleIdentifier = "com.google.Chrome"
    private var chromeRefreshTimer: Timer?

    private(set) var privateAPIAvailable = false

    override init() {
        super.init()
        dashboardView.onTaskSelected = { sessionID in
            _ = ThreadNavigator.open(sessionID: sessionID)
        }
        dashboardView.onChromeTabSelected = { windowID, index in
            _ = ChromeTabController.activate(windowID: windowID, tabIndex: index)
        }
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [dashboardIdentifier]
        touchBar.principalItemIdentifier = dashboardIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateForFrontmostApplication()
            }
        }
    }

    func install() {
        privateAPIAvailable = CTBPrivateTouchBarAvailable()
        guard privateAPIAvailable else { return }

        CTBSetSystemModalShowsCloseBox(false)
        let item = NSCustomTouchBarItem(identifier: trayIdentifier)
        let image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Codex Touch Bar")
        let button = NSButton(image: image ?? NSImage(), target: self, action: #selector(present))
        button.bezelColor = NSColor.systemTeal.withAlphaComponent(0.75)
        item.view = button
        trayItem = item
        if CTBAddSystemTrayItem(item) {
            isInstalled = true
            updateForFrontmostApplication()
        }
    }

    func uninstall() {
        isInstalled = false
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        CTBDismissSystemModalTouchBar(touchBar)
        CTBSetControlStripPresence(trayIdentifier.rawValue, false)
        if let trayItem { CTBRemoveSystemTrayItem(trayItem) }
        trayItem = nil
        chromeRefreshTimer?.invalidate(); chromeRefreshTimer = nil
    }

    func update(_ snapshot: DashboardSnapshot) {
        dashboardView.update(snapshot: snapshot)
    }

    @objc func present() {
        guard privateAPIAvailable, isInstalled, isSupportedFrontmost else { return }
        CTBSetControlStripPresence(trayIdentifier.rawValue, true)
        _ = CTBPresentSystemModalTouchBar(touchBar, trayIdentifier.rawValue)
    }

    private var isCodexFrontmost: Bool {
        guard let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return codexBundleIdentifiers.contains(bundleIdentifier)
    }

    private var isChromeFrontmost: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == chromeBundleIdentifier }
    private var isSupportedFrontmost: Bool { isCodexFrontmost || isChromeFrontmost }

    private func updateForFrontmostApplication() {
        guard privateAPIAvailable, isInstalled else { return }
        if isCodexFrontmost {
            chromeRefreshTimer?.invalidate(); chromeRefreshTimer = nil
            dashboardView.showCodex()
            present()
        } else if isChromeFrontmost {
            refreshChromeTabs()
            chromeRefreshTimer?.invalidate()
            chromeRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshChromeTabs() }
            }
            CTBSetControlStripPresence(trayIdentifier.rawValue, true)
            _ = CTBPresentSystemModalTouchBar(touchBar, trayIdentifier.rawValue)
        } else {
            chromeRefreshTimer?.invalidate(); chromeRefreshTimer = nil
            CTBDismissSystemModalTouchBar(touchBar)
            CTBSetControlStripPresence(trayIdentifier.rawValue, false)
        }
    }

    private func refreshChromeTabs() {
        guard isChromeFrontmost else { return }
        guard let tabs = ChromeTabController.frontWindowTabs() else {
            dashboardView.updateChromeTabs([], statusText: "Chrome · 请允许自动化控制")
            return
        }
        dashboardView.updateChromeTabs(tabs)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == dashboardIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: dashboardIdentifier)
        item.view = dashboardView
        item.visibilityPriority = .high
        return item
    }
}
