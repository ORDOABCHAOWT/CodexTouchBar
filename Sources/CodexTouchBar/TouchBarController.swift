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
    private var chromeRefreshInFlight = false
    private var chromeSelectionInFlight = false
    // Touch Bar presses can arrive while Chrome is acknowledging the previous
    // Apple Event. Keep the newest press instead of silently dropping it;
    // dropping the first press is what made users need a second tap.
    private var pendingChromeSelection: (windowID: Int64, tabID: Int64)?
    private var activeChromeSelection: (windowID: Int64, tabID: Int64)?
    private var chromeRequestGeneration: UInt64 = 0

    private(set) var privateAPIAvailable = false

    override init() {
        super.init()
        dashboardView.onTaskSelected = { sessionID in
            _ = ThreadNavigator.open(sessionID: sessionID)
        }
        dashboardView.onChromeTabSelected = { [weak self] windowID, tabID in
            self?.activateChromeTab(windowID: windowID, tabID: tabID)
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
            pendingChromeSelection = nil
            dashboardView.showCodex()
            present()
        } else if isChromeFrontmost {
            refreshChromeTabs()
            if chromeRefreshTimer == nil {
                chromeRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refreshChromeTabs() }
                }
            }
            CTBSetControlStripPresence(trayIdentifier.rawValue, true)
            _ = CTBPresentSystemModalTouchBar(touchBar, trayIdentifier.rawValue)
        } else {
            chromeRefreshTimer?.invalidate(); chromeRefreshTimer = nil
            pendingChromeSelection = nil
            CTBDismissSystemModalTouchBar(touchBar)
            CTBSetControlStripPresence(trayIdentifier.rawValue, false)
        }
    }

    private func refreshChromeTabs() {
        guard isChromeFrontmost, !chromeSelectionInFlight, !chromeRefreshInFlight else { return }
        chromeRefreshInFlight = true
        let generation = nextChromeRequestGeneration()
        ChromeTabController.refreshAsync { [weak self] tabs in
            guard let self else { return }
            self.chromeRefreshInFlight = false
            guard self.isChromeFrontmost, generation == self.chromeRequestGeneration else { return }
            guard let tabs else {
                self.dashboardView.updateChromeTabs([], statusText: "Chrome · 请允许自动化控制")
                return
            }
            self.dashboardView.updateChromeTabs(tabs)
        }
    }

    private func activateChromeTab(windowID: Int64, tabID: Int64) {
        guard isChromeFrontmost else { return }
        if chromeSelectionInFlight {
            if let active = activeChromeSelection,
               active.windowID == windowID,
               active.tabID == tabID {
                return
            }
            // Coalesce rapid presses to the last tab the user touched. This
            // preserves first-tap intent without queuing stale tab changes.
            pendingChromeSelection = (windowID, tabID)
            return
        }
        startChromeTabActivation(windowID: windowID, tabID: tabID)
    }

    private func startChromeTabActivation(windowID: Int64, tabID: Int64) {
        guard isChromeFrontmost, !chromeSelectionInFlight else { return }
        chromeSelectionInFlight = true
        activeChromeSelection = (windowID, tabID)
        let generation = nextChromeRequestGeneration()
        ChromeTabController.activateAsync(windowID: windowID, tabID: tabID) { [weak self] didActivate, tabs in
            guard let self else { return }
            self.chromeSelectionInFlight = false
            self.activeChromeSelection = nil
            guard self.isChromeFrontmost else {
                self.pendingChromeSelection = nil
                return
            }
            guard generation == self.chromeRequestGeneration else { return }
            if didActivate, let tabs {
                self.dashboardView.updateChromeTabs(tabs)
            } else {
                self.refreshChromeTabs()
            }
            if let pending = self.pendingChromeSelection {
                self.pendingChromeSelection = nil
                self.startChromeTabActivation(windowID: pending.windowID, tabID: pending.tabID)
            }
        }
    }

    private func nextChromeRequestGeneration() -> UInt64 {
        chromeRequestGeneration &+= 1
        return chromeRequestGeneration
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == dashboardIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: dashboardIdentifier)
        item.view = dashboardView
        item.visibilityPriority = .high
        return item
    }
}
