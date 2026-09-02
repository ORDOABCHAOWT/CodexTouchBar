import AppKit
import CodexTouchBarCore

@MainActor
final class PreviewWindowController: NSWindowController {
    private let dashboardView = DashboardStripView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 132),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodexTouchBar 预览"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        dashboardView.onTaskSelected = { sessionID in
            _ = ThreadNavigator.open(sessionID: sessionID)
        }
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func update(_ snapshot: DashboardSnapshot) {
        dashboardView.update(snapshot: snapshot)
        let taskCount = snapshot.tasks.count
        let quotaState: String
        if let error = snapshot.quotaError {
            quotaState = error
        } else if snapshot.quotas.isEmpty {
            quotaState = "正在读取额度"
        } else {
            quotaState = "额度连接正常"
        }
        statusLabel.stringValue = "\(taskCount) 个活动任务 · \(quotaState)"
    }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func renderPNG(to url: URL) throws {
        guard let view = window?.contentView else { throw PreviewError.missingContentView }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw PreviewError.renderFailed
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw PreviewError.renderFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(srgbRed: 0.035, green: 0.042, blue: 0.060, alpha: 1).cgColor

        let touchBarBackdrop = NSView()
        touchBarBackdrop.translatesAutoresizingMaskIntoConstraints = false
        touchBarBackdrop.wantsLayer = true
        touchBarBackdrop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.94).cgColor
        touchBarBackdrop.layer?.cornerRadius = 10
        touchBarBackdrop.layer?.borderWidth = 0.5
        touchBarBackdrop.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        dashboardView.translatesAutoresizingMaskIntoConstraints = false
        touchBarBackdrop.addSubview(dashboardView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        statusLabel.font = .systemFont(ofSize: 11)

        let note = NSTextField(labelWithString: "预览与实体 Touch Bar 共用同一套视图；颜色会随任务阶段自动变化。")
        note.translatesAutoresizingMaskIntoConstraints = false
        note.textColor = NSColor.white.withAlphaComponent(0.44)
        note.font = .systemFont(ofSize: 10)

        content.addSubview(touchBarBackdrop)
        content.addSubview(statusLabel)
        content.addSubview(note)
        NSLayoutConstraint.activate([
            touchBarBackdrop.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            touchBarBackdrop.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            touchBarBackdrop.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            touchBarBackdrop.heightAnchor.constraint(equalToConstant: 52),
            dashboardView.leadingAnchor.constraint(equalTo: touchBarBackdrop.leadingAnchor, constant: 6),
            dashboardView.trailingAnchor.constraint(lessThanOrEqualTo: touchBarBackdrop.trailingAnchor, constant: -6),
            dashboardView.centerYAnchor.constraint(equalTo: touchBarBackdrop.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: touchBarBackdrop.leadingAnchor, constant: 2),
            statusLabel.topAnchor.constraint(equalTo: touchBarBackdrop.bottomAnchor, constant: 12),
            note.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            note.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 5),
        ])
    }

    enum PreviewError: Error {
        case missingContentView
        case renderFailed
    }
}
