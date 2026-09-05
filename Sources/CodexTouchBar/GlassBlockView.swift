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

private enum ChromeTabTheme {
    private static let fallbackPalette: [NSColor] = [
        NSColor(srgbRed: 0.26, green: 0.52, blue: 0.96, alpha: 1),
        NSColor(srgbRed: 0.91, green: 0.29, blue: 0.24, alpha: 1),
        NSColor(srgbRed: 0.18, green: 0.69, blue: 0.42, alpha: 1),
        NSColor(srgbRed: 0.63, green: 0.40, blue: 0.92, alpha: 1),
        NSColor(srgbRed: 0.96, green: 0.62, blue: 0.18, alpha: 1),
        NSColor(srgbRed: 0.14, green: 0.67, blue: 0.75, alpha: 1),
        NSColor(srgbRed: 0.91, green: 0.36, blue: 0.59, alpha: 1),
    ]

    /// Uses only the already-visible title. No URL, favicon or page content is
    /// read, and the result is never persisted.
    static func accent(for title: String) -> NSColor {
        let normalized = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let known: [(tokens: [String], color: NSColor)] = [
            (["youtube"], NSColor(srgbRed: 1.00, green: 0.19, blue: 0.16, alpha: 1)),
            (["github"], NSColor(srgbRed: 0.60, green: 0.46, blue: 0.82, alpha: 1)),
            (["google", "谷歌"], NSColor(srgbRed: 0.26, green: 0.52, blue: 0.96, alpha: 1)),
            (["gmail"], NSColor(srgbRed: 0.92, green: 0.27, blue: 0.23, alpha: 1)),
            (["notion"], NSColor(srgbRed: 0.72, green: 0.73, blue: 0.76, alpha: 1)),
            (["figma"], NSColor(srgbRed: 0.72, green: 0.42, blue: 0.96, alpha: 1)),
            (["openai", "chatgpt"], NSColor(srgbRed: 0.22, green: 0.72, blue: 0.58, alpha: 1)),
            (["apple", "icloud"], NSColor(srgbRed: 0.68, green: 0.72, blue: 0.78, alpha: 1)),
            (["bilibili", "哔哩哔哩"], NSColor(srgbRed: 0.22, green: 0.69, blue: 0.88, alpha: 1)),
            (["知乎", "zhihu"], NSColor(srgbRed: 0.16, green: 0.49, blue: 0.96, alpha: 1)),
            (["微博", "weibo"], NSColor(srgbRed: 0.95, green: 0.42, blue: 0.19, alpha: 1)),
        ]
        if let match = known.first(where: { entry in entry.tokens.contains(where: normalized.contains) }) {
            return match.color
        }

        // FNV-1a is stable across launches, unlike Swift's randomized Hasher.
        let hash = normalized.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return fallbackPalette[Int(hash % UInt64(fallbackPalette.count))]
    }
}

/// A compact Chrome-inspired tab. An AppKit text field is used because a
/// CATextLayer can disappear on the physical Touch Bar when the tab is narrow.
final class ChromeTabButtonView: NSButton {
    var onTap: (() -> Void)? {
        didSet {
            target = self
            action = #selector(handleTap)
            setAccessibilityRole(.button)
        }
    }

    private let backgroundLayer = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()
    private let accentLayer = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private var fullTitle = ""
    private var active = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        focusRingType = .none
        imagePosition = .noImage
        cell?.usesSingleLineMode = true
        cell?.wraps = false
        cell?.lineBreakMode = .byTruncatingTail
        cell?.truncatesLastVisibleLine = true
        cell?.alignment = .center
        title = ""
        sendAction(on: [.leftMouseDown])

        backgroundLayer.fillColor = NSColor(srgbRed: 0.125, green: 0.129, blue: 0.141, alpha: 0.96).cgColor
        outlineLayer.fillColor = NSColor.clear.cgColor
        outlineLayer.lineWidth = 0.75
        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(outlineLayer)
        layer?.addSublayer(accentLayer)

        titleLabel.translatesAutoresizingMaskIntoConstraints = true
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byClipping
        titleLabel.maximumNumberOfLines = 1
        titleLabel.textColor = NSColor(srgbRed: 0.95, green: 0.96, blue: 0.98, alpha: 1)
        titleLabel.backgroundColor = .clear
        titleLabel.drawsBackground = false
        titleLabel.isSelectable = false
        titleLabel.isEditable = false
        addSubview(titleLabel)

        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 30)])
    }

    required init?(coder: NSCoder) { nil }

    @objc private func handleTap() { onTap?() }

    func set(title: String, isActive: Bool) {
        fullTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新标签" : title
        active = isActive
        toolTip = title
        setAccessibilityLabel(title)
        let accent = ChromeTabTheme.accent(for: fullTitle)
        let neutral = NSColor(
            srgbRed: isActive ? 0.235 : 0.161,
            green: isActive ? 0.251 : 0.165,
            blue: isActive ? 0.278 : 0.176,
            alpha: 1
        )
        backgroundLayer.fillColor = neutral.blended(
            withFraction: isActive ? 0.22 : 0.10,
            of: accent
        )?.cgColor ?? neutral.cgColor
        outlineLayer.strokeColor = accent.withAlphaComponent(isActive ? 0.82 : 0.42).cgColor
        accentLayer.backgroundColor = accent.cgColor
        accentLayer.opacity = isActive ? 1 : 0.72
        updateVisibleTitle()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        backgroundLayer.opacity = isHighlighted ? 0.58 : 1
    }

    override func layout() {
        super.layout()
        let path = chromeTabPath(in: bounds.insetBy(dx: 0.4, dy: 0.4))
        backgroundLayer.frame = bounds
        backgroundLayer.path = path
        outlineLayer.frame = bounds
        outlineLayer.path = path
        let narrow = bounds.width < 48
        let inset: CGFloat = narrow ? 3 : 6
        accentLayer.frame = NSRect(x: inset, y: bounds.height - (active ? 2.6 : 2.0), width: max(0, bounds.width - inset * 2), height: active ? 2.2 : 1.6)
        accentLayer.cornerRadius = 0.8
        titleLabel.font = NSFont.systemFont(ofSize: narrow ? 10.5 : 11.5, weight: active ? .semibold : .medium)
        titleLabel.frame = NSRect(x: inset, y: 7, width: max(0, bounds.width - inset * 2), height: 16)
        updateVisibleTitle()
    }

    private func chromeTabPath(in rect: NSRect) -> CGPath {
        let topRadius: CGFloat = 7
        let bottomRadius: CGFloat = 3
        let path = CGMutablePath()
        path.move(to: NSPoint(x: rect.minX + bottomRadius, y: rect.minY))
        path.addLine(to: NSPoint(x: rect.maxX - bottomRadius, y: rect.minY))
        path.addQuadCurve(to: NSPoint(x: rect.maxX, y: rect.minY + bottomRadius), control: NSPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: NSPoint(x: rect.maxX, y: rect.maxY - topRadius))
        path.addQuadCurve(to: NSPoint(x: rect.maxX - topRadius, y: rect.maxY), control: NSPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: NSPoint(x: rect.minX + topRadius, y: rect.maxY))
        path.addQuadCurve(to: NSPoint(x: rect.minX, y: rect.maxY - topRadius), control: NSPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: NSPoint(x: rect.minX, y: rect.minY + bottomRadius))
        path.addQuadCurve(to: NSPoint(x: rect.minX + bottomRadius, y: rect.minY), control: NSPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }

    private func updateVisibleTitle() {
        guard !fullTitle.isEmpty else { return }
        titleLabel.stringValue = bounds.width < 48 ? String(fullTitle.prefix(2)) : fullTitle
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) && isEnabled ? self : nil
    }
}

final class DashboardStripView: NSView {
    var onTaskSelected: ((String) -> Void)?
    private let rootStack = NSStackView()
    private let leftMediaStack = NSStackView()
    private let statusStack = NSStackView()
    private let taskStack = NSStackView()
    private let quotaStack = NSStackView()
    private var snapshot = DashboardSnapshot()
    private var tickTimer: Timer?
    private var statusLayoutKey: [String]?
    private var taskBlocks: [GlassBlockView] = []
    private var chromeTabBlocks: [ChromeTabButtonView] = []
    private var quotaBlocks: [QuotaKind: GlassBlockView] = [:]
    private var quotaWidthConstraint: NSLayoutConstraint?
    private var mediaGroupWidthConstraint: NSLayoutConstraint?
    private var chromeTabs: [ChromeTabSnapshot] = []
    private var chromeStatusText: String?
    private var isChromeMode = false
    var onChromeTabSelected: ((Int64, Int64) -> Void)?

    func updateChromeTabs(_ tabs: [ChromeTabSnapshot], statusText: String? = nil) {
        let contentChanged = !isChromeMode || chromeTabs != tabs || chromeStatusText != statusText
        isChromeMode = true
        chromeTabs = tabs
        chromeStatusText = statusText
        leftMediaStack.isHidden = true
        mediaGroupWidthConstraint?.isActive = false
        quotaStack.isHidden = true
        quotaWidthConstraint?.isActive = false
        if contentChanged { rebuild() }
    }

    func showCodex() {
        guard isChromeMode else { return }
        isChromeMode = false
        chromeTabs = []
        chromeStatusText = nil
        leftMediaStack.isHidden = false
        mediaGroupWidthConstraint?.isActive = true
        quotaStack.isHidden = false
        quotaWidthConstraint?.isActive = true
        statusLayoutKey = nil
        rebuild()
    }

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
        mediaGroupWidthConstraint = mediaGroupWidth
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 5
        statusStack.distribution = .fill
        statusStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        taskStack.orientation = .horizontal
        taskStack.alignment = .centerY
        taskStack.spacing = 5
        taskStack.distribution = .fillEqually
        taskStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        taskStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        quotaStack.orientation = .horizontal
        quotaStack.alignment = .centerY
        quotaStack.spacing = 5
        quotaStack.distribution = .fill
        quotaStack.setContentHuggingPriority(.required, for: .horizontal)
        quotaStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        let preferredQuotaWidth = quotaStack.widthAnchor.constraint(equalToConstant: 181)
        preferredQuotaWidth.priority = .defaultHigh
        quotaWidthConstraint = preferredQuotaWidth
        // Use the native 13-inch Touch Bar width as a preferred size. The
        // constraint is intentionally high-but-breakable: on a narrower bar
        // AppKit must shrink the equal-fill status blocks instead of clipping
        // the rightmost one.
        let preferredStatusWidth = statusStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 520)
        preferredStatusWidth.priority = .defaultHigh

        rootStack.addArrangedSubview(leftMediaStack)
        rootStack.addArrangedSubview(statusStack)
        statusStack.addArrangedSubview(taskStack)
        statusStack.addArrangedSubview(quotaStack)
        addSubview(rootStack)

        let preferredStripWidth = widthAnchor.constraint(equalToConstant: 1000)
        preferredStripWidth.priority = .defaultLow
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            rootStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            mediaGroupWidth,
            preferredStripWidth,
            preferredStatusWidth,
            preferredQuotaWidth,
            heightAnchor.constraint(equalToConstant: 30),
        ])
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.isChromeMode else { return }
            self.rebuild()
        }
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        // NSTouchBar sizes custom items from their intrinsic content size.
        // 1000 points fits the usable width of the 13-inch Touch Bar while
        // leaving AppKit enough room to compress task tabs on smaller bars.
        NSSize(width: 1000, height: 30)
    }

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

        if isChromeMode {
            let layoutKey = ["__chrome__", chromeStatusText ?? ""]
                + chromeTabs.map { "\($0.windowID):\($0.tabID)" }
            if statusLayoutKey != layoutKey {
                [taskStack, quotaStack].forEach { stack in
                    stack.arrangedSubviews.forEach { view in
                        stack.removeArrangedSubview(view)
                        view.removeFromSuperview()
                    }
                }
                taskBlocks = []
                chromeTabBlocks = []
                for tab in chromeTabs {
                    let block = ChromeTabButtonView()
                    block.onTap = { [weak self] in
                        self?.onChromeTabSelected?(tab.windowID, tab.tabID)
                    }
                    chromeTabBlocks.append(block)
                    taskStack.addArrangedSubview(block)
                }
                if chromeTabs.isEmpty {
                    let block = ChromeTabButtonView()
                    block.isEnabled = false
                    block.set(title: chromeStatusText ?? "Chrome · 无标签页", isActive: false)
                    taskStack.addArrangedSubview(block)
                }
                statusLayoutKey = layoutKey
            }
            for (tab, block) in zip(chromeTabs, chromeTabBlocks) {
                block.set(title: tab.title, isActive: tab.isActive)
            }
            return
        }

        let visibleTasks = Array(snapshot.tasks.prefix(6))
        let layoutKey = visibleTasks.isEmpty ? ["__waiting__"] : visibleTasks.map(\.sessionID)
        if statusLayoutKey != layoutKey {
            [taskStack, quotaStack].forEach { stack in
                stack.arrangedSubviews.forEach { view in
                    stack.removeArrangedSubview(view)
                    view.removeFromSuperview()
                }
            }
            taskBlocks = []
            chromeTabBlocks = []
            quotaBlocks = [:]

            if visibleTasks.isEmpty {
                let block = GlassBlockView()
                block.set(text: "Codex · 等待任务", accent: .gray)
                taskStack.addArrangedSubview(block)
            } else {
                for task in visibleTasks {
                    let block = GlassBlockView()
                    block.onTap = { [weak self] in self?.onTaskSelected?(task.sessionID) }
                    taskBlocks.append(block)
                    taskStack.addArrangedSubview(block)
                }
            }
            quotaBlocks[.fiveHour] = addQuotaBlock(kind: .fiveHour, accent: .teal)
            quotaBlocks[.weekly] = addQuotaBlock(kind: .weekly, accent: .indigo)
            statusLayoutKey = layoutKey
        }

        for (task, block) in zip(visibleTasks, taskBlocks) {
            let elapsed = Self.elapsedString(since: task.startedAt)
            let compactTitle = String(task.title.prefix(80))
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
        let width = block.widthAnchor.constraint(equalToConstant: 88)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([width])
        quotaStack.addArrangedSubview(block)
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
