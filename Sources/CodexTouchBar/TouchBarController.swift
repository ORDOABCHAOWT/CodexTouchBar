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
    private(set) var lastSupportedProvider: TaskProvider = .codex
    private let codexBundleIdentifiers: Set<String> = ["com.openai.codex", "com.openai.chatgpt"]
    private let claudeBundleIdentifiers: Set<String> = ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
    var onFrontmostProviderChanged: ((TaskProvider?) -> Void)?
    var onTaskRouteSelected: ((TaskRoute) -> Void)?
    var onRefreshRequested: (() -> Void)?

    private(set) var privateAPIAvailable = false
    var visibleTaskCount: Int { dashboardView.visibleTaskCount }

    override init() {
        super.init()
        dashboardView.onTaskSelected = { sessionID in
            guard !ThreadNavigator.open(sessionID: sessionID) else { return }
            // Launch Services can transiently reject the first URL open while
            // Codex is changing windows. Retry only an explicit failure so a
            // successful tap is never delivered twice.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                _ = ThreadNavigator.open(sessionID: sessionID)
            }
        }
        dashboardView.onTaskRouteSelected = { [weak self] route in
            if let handler = self?.onTaskRouteSelected { handler(route); return }
            guard route.supported else { return }
            _ = ThreadNavigator.open(route: route)
        }
        dashboardView.onRefreshRequested = { [weak self] in self?.onRefreshRequested?() }
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
    }

    func update(_ snapshot: DashboardSnapshot) {
        dashboardView.update(snapshot: snapshot)
    }

    @objc func present() {
        guard privateAPIAvailable, isInstalled, frontmostProvider != nil else { return }
        CTBSetControlStripPresence(trayIdentifier.rawValue, true)
        _ = CTBPresentSystemModalTouchBar(touchBar, trayIdentifier.rawValue)
    }

    private var isCodexFrontmost: Bool {
        guard let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return codexBundleIdentifiers.contains(bundleIdentifier)
    }

    private var frontmostProvider: TaskProvider? {
        guard let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        if codexBundleIdentifiers.contains(bundleIdentifier) { return .codex }
        if claudeBundleIdentifiers.contains(bundleIdentifier) { return .claude }
        return nil
    }

    private func updateForFrontmostApplication() {
        let provider = frontmostProvider
        if let provider { lastSupportedProvider = provider }
        onFrontmostProviderChanged?(provider)
        guard privateAPIAvailable, isInstalled else { return }
        if provider != nil {
            present()
        } else {
            CTBDismissSystemModalTouchBar(touchBar)
            CTBSetControlStripPresence(trayIdentifier.rawValue, false)
        }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == dashboardIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: dashboardIdentifier)
        item.view = dashboardView
        item.visibilityPriority = .high
        return item
    }
}
