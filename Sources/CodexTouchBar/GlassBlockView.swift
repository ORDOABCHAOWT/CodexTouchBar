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
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let dotView = NSView()
    private let tintLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private var accent: GlassAccent = .blue

    init(width: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        layer?.addSublayer(tintLayer)

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.42).cgColor
        borderLayer.lineWidth = 0.8
        layer?.addSublayer(borderLayer)

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3
        dotView.layer?.shadowRadius = 3
        dotView.layer?.shadowOpacity = 0.7
        dotView.layer?.shadowOffset = .zero

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.maximumNumberOfLines = 1

        addSubview(dotView)
        addSubview(titleLabel)
        addSubview(valueLabel)
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(click)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 30),
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 6),
            dotView.heightAnchor.constraint(equalToConstant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        set(title: "Codex", value: "正在连接", accent: .blue)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func handleTap() {
        onTap?()
    }

    func set(title: String, value: String, accent: GlassAccent) {
        titleLabel.stringValue = title
        valueLabel.stringValue = value
        self.accent = accent
        let color = accent.color
        tintLayer.backgroundColor = color.withAlphaComponent(0.30).cgColor
        dotView.layer?.backgroundColor = color.withAlphaComponent(0.96).cgColor
        dotView.layer?.shadowColor = color.cgColor
    }

    override func layout() {
        super.layout()
        tintLayer.frame = bounds
        borderLayer.frame = bounds
        borderLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 7.5, cornerHeight: 7.5, transform: nil)
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
        stack.spacing = 6
        stack.distribution = .fill
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 38),
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

        stack.addArrangedSubview(Self.edgeSpacer(width: 34))

        if snapshot.tasks.isEmpty {
            let block = GlassBlockView(width: 126)
            block.set(title: "Codex 任务", value: "等待新任务", accent: .gray)
            stack.addArrangedSubview(block)
        } else {
            for task in snapshot.tasks.prefix(3) {
                let block = GlassBlockView(width: snapshot.tasks.count >= 3 ? 116 : 136)
                let elapsed = Self.elapsedString(since: task.startedAt)
                let phase = task.phase == .usingTool && task.toolName != nil
                    ? task.toolName!
                    : task.phase.shortLabel
                block.set(
                    title: task.title,
                    value: "\(phase) · \(elapsed)",
                    accent: .forPhase(task.phase)
                )
                block.onTap = { [weak self] in self?.onTaskSelected?(task.sessionID) }
                stack.addArrangedSubview(block)
            }
        }

        let quotaByKind = Dictionary(uniqueKeysWithValues: snapshot.quotas.map { ($0.kind, $0) })
        addQuotaBlock(kind: .fiveHour, window: quotaByKind[.fiveHour], accent: .teal)
        addQuotaBlock(kind: .weekly, window: quotaByKind[.weekly], accent: .indigo)
        stack.addArrangedSubview(Self.edgeSpacer(width: 34))
    }

    private func addQuotaBlock(kind: QuotaKind, window: QuotaWindow?, accent: GlassAccent) {
        let block = GlassBlockView(width: 84)
        let value = window.map { "剩余 \($0.remainingPercent)%" } ?? "读取中…"
        block.set(title: kind.label, value: value, accent: accent)
        stack.addArrangedSubview(block)
    }

    private static func elapsedString(since start: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)秒" }
        if seconds < 3600 { return String(format: "%d:%02d", seconds / 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }

    private static func edgeSpacer(width: CGFloat) -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: width).isActive = true
        spacer.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return spacer
    }
}
