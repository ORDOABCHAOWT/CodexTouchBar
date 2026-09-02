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

    private(set) var privateAPIAvailable = false

    override init() {
        super.init()
        dashboardView.onTaskSelected = { sessionID in
            _ = ThreadNavigator.open(sessionID: sessionID)
        }
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [dashboardIdentifier]
        touchBar.principalItemIdentifier = dashboardIdentifier
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
            CTBSetControlStripPresence(trayIdentifier.rawValue, true)
            _ = CTBPresentSystemModalTouchBar(touchBar, trayIdentifier.rawValue)
        }
    }

    func uninstall() {
        CTBDismissSystemModalTouchBar(touchBar)
        CTBSetControlStripPresence(trayIdentifier.rawValue, false)
        if let trayItem { CTBRemoveSystemTrayItem(trayItem) }
        trayItem = nil
    }

    func update(_ snapshot: DashboardSnapshot) {
        dashboardView.update(snapshot: snapshot)
    }

    @objc func present() {
        guard privateAPIAvailable else { return }
        _ = CTBPresentSystemModalTouchBar(touchBar, trayIdentifier.rawValue)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == dashboardIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: dashboardIdentifier)
        item.view = dashboardView
        item.visibilityPriority = .high
        return item
    }
}
