import AppKit
import CodexTouchBarCore
import QuartzCore

enum GlassAccent {
    case blue, purple, orange, green, red, teal, indigo, gray

    var color: NSColor {
        switch self {
        case .blue: return NSColor(srgbRed: 0.15, green: 0.55, blue: 1.00, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.63, green: 0.37, blue: 1.00, alpha: 1)
        case .orange: return NSColor(srgbRed: 1.00, green: 0.57, blue: 0.18, alpha: 1)
        case .green: return NSColor(srgbRed: 0.20, green: 0.82, blue: 0.49, alpha: 1)
        case .red: return NSColor(srgbRed: 1.00, green: 0.30, blue: 0.36, alpha: 1)
        case .teal: return NSColor(srgbRed: 0.14, green: 0.78, blue: 0.76, alpha: 1)
        case .indigo: return NSColor(srgbRed: 0.36, green: 0.45, blue: 1.00, alpha: 1)
        case .gray: return NSColor(srgbRed: 0.50, green: 0.54, blue: 0.62, alpha: 1)
        }
    }

    static func forPhase(_ phase: TaskPhase) -> GlassAccent {
        switch phase {
        case .thinking: return .blue
        case .usingTool: return .purple
        case .waitingApproval, .waitingInput: return .orange
        case .completed: return .green
        case .failed: return .red
        case .idle: return .gray
        }
    }
}

enum VisualVariant: Int {
    case native = 1
    case frosted = 2
    case balanced = 3
    case contrast = 4
    case minimal = 5

    static var current: VisualVariant = .balanced

    var tintAlpha: CGFloat {
        switch self {
        case .native: return 0.16
        case .frosted: return 0.27
        case .balanced: return 0.22
        case .contrast: return 0.36
        case .minimal: return 0.12
        }
    }

    var borderAlpha: CGFloat {
        switch self {
        case .native: return 0.42
        case .frosted: return 0.58
        case .balanced: return 0.50
        case .contrast: return 0.78
        case .minimal: return 0.32
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .native: return 6
        case .frosted: return 10
        case .balanced: return 8
        case .contrast: return 5
        case .minimal: return 7
        }
    }

    var textSize: CGFloat {
        self == .contrast ? 12 : 11.5
    }
}

/// A real AppKit button, rather than a gesture recognizer on a passive view.
/// This is important on the physical Touch Bar, where AppKit owns hit testing.
final class GlassBlockView: NSButton {
    var onTap: (() -> Void)? {
        didSet {
            target = self
            action = #selector(handleTap)
            toolTip = onTap == nil ? nil : "在 Codex 中打开此任务"
            setAccessibilityRole(onTap == nil ? .group : .button)
        }
    }

    private let tintLayer = CALayer()
    private let borderLayer = CAShapeLayer()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        bezelStyle = .recessed
        focusRingType = .none
        imagePosition = .noImage
        cell?.usesSingleLineMode = true
        cell?.wraps = false
        cell?.lineBreakMode = .byTruncatingTail
        cell?.truncatesLastVisibleLine = true
        cell?.alignment = .center
        // Trigger on touch-down so the physical Touch Bar's first tap is not
        // lost while AppKit waits for a mouse-up event.
        sendAction(on: [.leftMouseDown])
        layer?.cornerRadius = VisualVariant.current.cornerRadius
        layer?.masksToBounds = true
        layer?.addSublayer(tintLayer)

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(VisualVariant.current.borderAlpha).cgColor
        borderLayer.lineWidth = 0.9
        layer?.addSublayer(borderLayer)

        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 30)])
        set(text: "Codex · 连接中", accent: .blue)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func handleTap() { onTap?() }

    func set(text: String, accent: GlassAccent) {
        let dot = NSAttributedString(
            string: "● ",
            attributes: [
                .foregroundColor: accent.color.withAlphaComponent(0.98),
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            ]
        )
        let label = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: VisualVariant.current.textSize, weight: .semibold),
            ]
        )
        let title = NSMutableAttributedString()
        title.append(dot)
        title.append(label)
        attributedTitle = title
        tintLayer.backgroundColor = accent.color.withAlphaComponent(VisualVariant.current.tintAlpha).cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Give the custom glass button the same clear press feedback as native buttons.
        tintLayer.opacity = isHighlighted ? 0.58 : 1
    }

    override func layout() {
        super.layout()
        tintLayer.frame = bounds
        borderLayer.frame = bounds
        borderLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: VisualVariant.current.cornerRadius - 0.5,
            cornerHeight: VisualVariant.current.cornerRadius - 0.5,
            transform: nil
        )
    }
}

/// Uses Apple's native NSButton bezel and SF Symbol rendering for playback.
final class MediaButtonView: NSButton {
    init(symbolName: String, label: String, target: AnyObject, action: Selector) {
        var image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) ?? NSImage()
        super.init(frame: .zero)
        image = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)) ?? image
        self.image = image
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .rounded
        isBordered = true
        bezelColor = NSColor(calibratedWhite: 0.18, alpha: 0.92)
        focusRingType = .none
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = NSColor.white.withAlphaComponent(0.96)
        toolTip = label
        setAccessibilityLabel(label)
        sendAction(on: [.leftMouseDown])
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 48),
            heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

final class DashboardStripView: NSView {
    var onTaskSelected: ((String) -> Void)?
    private let rootStack = NSStackView()
    private let leftMediaStack = NSStackView()
    private let statusStack = NSStackView()
    private var snapshot = DashboardSnapshot()
    private var tickTimer: Timer?
    private var statusLayoutKey: [String]?
    private var taskBlocks: [GlassBlockView] = []
    private var quotaBlocks: [QuotaKind: GlassBlockView] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .horizontal
        rootStack.alignment = .centerY
        rootStack.spacing = 6
        rootStack.distribution = .fill

        leftMediaStack.orientation = .horizontal
        leftMediaStack.alignment = .centerY
        leftMediaStack.spacing = 4
        leftMediaStack.setContentHuggingPriority(.required, for: .horizontal)
        leftMediaStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        let mediaGroupWidth = leftMediaStack.widthAnchor.constraint(equalToConstant: 152)
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 5
        statusStack.distribution = .fillEqually
        statusStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let preferredStatusWidth = statusStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 520)
        preferredStatusWidth.priority = .defaultHigh

        rootStack.addArrangedSubview(leftMediaStack)
        rootStack.addArrangedSubview(statusStack)
        addSubview(rootStack)

        let preferredStripWidth = widthAnchor.constraint(greaterThanOrEqualToConstant: 950)
        preferredStripWidth.priority = .defaultLow
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            rootStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            mediaGroupWidth,
            preferredStripWidth,
            preferredStatusWidth,
            heightAnchor.constraint(equalToConstant: 30),
        ])
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.rebuild() }
    }

    required init?(coder: NSCoder) { nil }

    func update(snapshot: DashboardSnapshot) {
        self.snapshot = snapshot
        rebuild()
    }

    private func rebuild() {
        // Keep the actual NSButton instances alive between timer ticks. Replacing
        // them every second can invalidate a touch that is already in progress.
        if leftMediaStack.arrangedSubviews.isEmpty {
            leftMediaStack.addArrangedSubview(MediaButtonView(
                symbolName: "backward.fill",
                label: "上一首",
                target: self,
                action: #selector(previousTrack)
            ))
            leftMediaStack.addArrangedSubview(MediaButtonView(
                symbolName: "playpause.fill",
                label: "播放或暂停",
                target: self,
                action: #selector(togglePlayPause)
            ))
            leftMediaStack.addArrangedSubview(MediaButtonView(
                symbolName: "forward.fill",
                label: "下一首",
                target: self,
                action: #selector(nextTrack)
            ))
        }

        let visibleTasks = Array(snapshot.tasks.prefix(3))
        let layoutKey = visibleTasks.isEmpty ? ["__waiting__"] : visibleTasks.map(\.sessionID)
        if statusLayoutKey != layoutKey {
            statusStack.arrangedSubviews.forEach { view in
                statusStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            taskBlocks = []
            quotaBlocks = [:]

            if visibleTasks.isEmpty {
                let block = GlassBlockView()
                block.set(text: "Codex · 等待任务", accent: .gray)
                statusStack.addArrangedSubview(block)
            } else {
                for task in visibleTasks {
                    let block = GlassBlockView()
                    block.onTap = { [weak self] in self?.onTaskSelected?(task.sessionID) }
                    taskBlocks.append(block)
                    statusStack.addArrangedSubview(block)
                }
            }
            quotaBlocks[.fiveHour] = addQuotaBlock(kind: .fiveHour, accent: .teal)
            quotaBlocks[.weekly] = addQuotaBlock(kind: .weekly, accent: .indigo)
            statusLayoutKey = layoutKey
        }

        let titleLimit = visibleTasks.count >= 3 ? 4 : 7
        for (task, block) in zip(visibleTasks, taskBlocks) {
            let elapsed = Self.elapsedString(since: task.startedAt)
            let compactTitle = String(task.title.prefix(titleLimit))
            block.set(
                text: "\(compactTitle) · \(Self.phaseGlyph(task.phase)) \(elapsed)",
                accent: .forPhase(task.phase)
            )
        }

        let quotaByKind = Dictionary(uniqueKeysWithValues: snapshot.quotas.map { ($0.kind, $0) })
        updateQuotaBlock(quotaBlocks[.fiveHour], kind: .fiveHour, window: quotaByKind[.fiveHour], accent: .teal)
        updateQuotaBlock(quotaBlocks[.weekly], kind: .weekly, window: quotaByKind[.weekly], accent: .indigo)

    }

    @discardableResult
    private func addQuotaBlock(kind: QuotaKind, accent: GlassAccent) -> GlassBlockView {
        let block = GlassBlockView()
        statusStack.addArrangedSubview(block)
        updateQuotaBlock(block, kind: kind, window: nil, accent: accent)
        return block
    }

    private func updateQuotaBlock(_ block: GlassBlockView?, kind: QuotaKind, window: QuotaWindow?, accent: GlassAccent) {
        guard let block else { return }
        let prefix = kind == .fiveHour ? "5h" : "周"
        let value = window.map { "\(prefix) \($0.remainingPercent)%" } ?? "\(prefix) …"
        block.set(text: value, accent: accent)
    }

    @objc private func previousTrack() { _ = MediaController.send(.previousTrack) }
    @objc private func togglePlayPause() { _ = MediaController.send(.togglePlayPause) }
    @objc private func nextTrack() { _ = MediaController.send(.nextTrack) }

    private static func elapsedString(since start: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return String(format: "%d:%02d", seconds / 60, seconds % 60) }
        return String(format: "%dh%02d", seconds / 3600, (seconds % 3600) / 60)
    }

    private static func phaseGlyph(_ phase: TaskPhase) -> String {
        switch phase {
        case .thinking: return "思"
        case .usingTool: return "工"
        case .waitingApproval: return "批"
        case .waitingInput: return "等"
        case .completed: return "成"
        case .failed: return "错"
        case .idle: return "闲"
        }
    }
}
