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

final class GlassBlockView: NSVisualEffectView {
    var onTap: (() -> Void)? {
        didSet {
            toolTip = onTap == nil ? nil : "在 Codex 中打开此任务"
            setAccessibilityRole(onTap == nil ? .group : .button)
        }
    }

    private let textLabel = NSTextField(labelWithString: "")
    private let dotView = NSView()
    private let tintLayer = CALayer()
    private let borderLayer = CAShapeLayer()

    init(width: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        layer?.addSublayer(tintLayer)

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.46).cgColor
        borderLayer.lineWidth = 0.8
        layer?.addSublayer(borderLayer)

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 2.5

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        textLabel.textColor = .white
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(dotView)
        addSubview(textLabel)
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(handleTap)))

        let preferredWidth = widthAnchor.constraint(equalToConstant: width)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            preferredWidth,
            heightAnchor.constraint(equalToConstant: 24),
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 5),
            dotView.heightAnchor.constraint(equalToConstant: 5),
            textLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 5),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.25),
        ])
        set(text: "Codex · 连接中", accent: .blue)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func handleTap() { onTap?() }

    func set(text: String, accent: GlassAccent) {
        textLabel.stringValue = text
        let color = accent.color
        tintLayer.backgroundColor = color.withAlphaComponent(0.24).cgColor
        dotView.layer?.backgroundColor = color.withAlphaComponent(0.98).cgColor
    }

    override func layout() {
        super.layout()
        tintLayer.frame = bounds
        borderLayer.frame = bounds
        borderLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: 6.5,
            cornerHeight: 6.5,
            transform: nil
        )
    }
}

final class MediaButtonView: NSButton {
    private let tintLayer = CALayer()
    private let borderLayer = CAShapeLayer()

    init(symbolName: String, label: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        toolTip = label
        self.target = target
        self.action = action
        setAccessibilityLabel(label)
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        tintLayer.backgroundColor = NSColor.white.withAlphaComponent(0.11).cgColor
        layer?.addSublayer(tintLayer)
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.38).cgColor
        borderLayer.lineWidth = 0.8
        layer?.addSublayer(borderLayer)
        contentTintColor = NSColor.white.withAlphaComponent(0.94)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        tintLayer.frame = bounds
        borderLayer.frame = bounds
        borderLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: 6.5,
            cornerHeight: 6.5,
            transform: nil
        )
    }
}

final class DashboardStripView: NSView {
    var onTaskSelected: ((String) -> Void)?
    private let stack = NSStackView()
    private var snapshot = DashboardSnapshot()
    private var tickTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.distribution = .fill
        addSubview(stack)
        let preferredStripWidth = widthAnchor.constraint(greaterThanOrEqualToConstant: 700)
        preferredStripWidth.priority = .defaultLow
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            preferredStripWidth,
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
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        addMediaButton(symbol: "backward.fill", label: "上一首", action: #selector(previousTrack))
        addMediaButton(symbol: "playpause.fill", label: "播放或暂停", action: #selector(togglePlayPause))
        stack.addArrangedSubview(Self.flexibleSpacer())

        if snapshot.tasks.isEmpty {
            let block = GlassBlockView(width: 118)
            block.set(text: "Codex · 等待任务", accent: .gray)
            stack.addArrangedSubview(block)
        } else {
            let width: CGFloat = snapshot.tasks.count >= 3 ? 98 : 120
            for task in snapshot.tasks.prefix(3) {
                let block = GlassBlockView(width: width)
                let elapsed = Self.elapsedString(since: task.startedAt)
                let titleLimit = snapshot.tasks.count >= 3 ? 3 : 7
                let compactTitle = String(task.title.prefix(titleLimit))
                block.set(
                    text: "\(compactTitle) · \(Self.phaseGlyph(task.phase)) \(elapsed)",
                    accent: .forPhase(task.phase)
                )
                block.onTap = { [weak self] in self?.onTaskSelected?(task.sessionID) }
                stack.addArrangedSubview(block)
            }
        }

        let quotaByKind = Dictionary(uniqueKeysWithValues: snapshot.quotas.map { ($0.kind, $0) })
        addQuotaBlock(kind: .fiveHour, window: quotaByKind[.fiveHour], accent: .teal)
        addQuotaBlock(kind: .weekly, window: quotaByKind[.weekly], accent: .indigo)
        stack.addArrangedSubview(Self.flexibleSpacer())
        addMediaButton(symbol: "forward.fill", label: "下一首", action: #selector(nextTrack))
    }

    private func addQuotaBlock(kind: QuotaKind, window: QuotaWindow?, accent: GlassAccent) {
        let block = GlassBlockView(width: 70)
        let prefix = kind == .fiveHour ? "5h" : "周"
        let value = window.map { "\(prefix) \($0.remainingPercent)%" } ?? "\(prefix) …"
        block.set(text: value, accent: accent)
        stack.addArrangedSubview(block)
    }

    private func addMediaButton(symbol: String, label: String, action: Selector) {
        let button = MediaButtonView(symbolName: symbol, label: label, target: self, action: action)
        button.isEnabled = MediaController.isAvailable
        button.alphaValue = button.isEnabled ? 1 : 0.42
        stack.addArrangedSubview(button)
    }

    @objc private func previousTrack() { MediaController.send(.previousTrack) }
    @objc private func togglePlayPause() { MediaController.send(.togglePlayPause) }
    @objc private func nextTrack() { MediaController.send(.nextTrack) }

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

    private static func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 8).isActive = true
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }
}
