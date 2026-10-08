import AppKit

public typealias PopoverActionCallback = @convention(c) (Int32) -> Void

private enum PopoverAction: Int32 {
    case refresh = 0
    case toggleStartAtLogin = 1
    case quit = 2
}

private enum PopoverDataStatus: Int32 {
    case synced = 0
    case stale = 1
    case unavailable = 2
    case refreshing = 3

    var symbolName: String {
        switch self {
        case .synced:
            return "checkmark.circle.fill"
        case .stale:
            return "exclamationmark.triangle.fill"
        case .unavailable:
            return "wifi.slash"
        case .refreshing:
            return "arrow.triangle.2.circlepath"
        }
    }

    var tint: NSColor {
        switch self {
        case .synced:
            return .systemGreen
        case .stale:
            return .systemOrange
        case .unavailable:
            return .secondaryLabelColor
        case .refreshing:
            return .controlAccentColor
        }
    }
}

// Both sizes share the same remaining-quota geometry; zero is an empty ring.
private func drawQuotaRing(in bounds: NSRect, fraction: Double, color: NSColor) {
    let width: CGFloat = bounds.width < 24 ? 2 : 7
    let rect = bounds.insetBy(dx: width / 2 + 1, dy: width / 2 + 1)
    let track = NSBezierPath(ovalIn: rect)
    track.lineWidth = width
    NSColor.secondaryLabelColor.withAlphaComponent(0.22).setStroke()
    track.stroke()
    guard fraction > 0 else { return }
    let arc = NSBezierPath()
    arc.lineWidth = width
    arc.lineCapStyle = .round
    arc.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY),
                  radius: rect.width / 2, startAngle: 90,
                  endAngle: 90 - 360 * min(fraction, 1), clockwise: true)
    color.setStroke()
    arc.stroke()
}

// Borderless battery: a quiet solid track and true proportional green fill.
private func drawQuotaBadge(in bounds: NSRect, fraction: Double, percentage: String) {
    let body = NSRect(x: bounds.minX, y: bounds.midY - 5, width: 23, height: 10)
    let shape = NSBezierPath(roundedRect: body, xRadius: 2.6, yRadius: 2.6)
    NSColor.labelColor.withAlphaComponent(0.12).setFill()
    shape.fill()
    NSColor.labelColor.withAlphaComponent(0.23).setFill()
    NSBezierPath(roundedRect: NSRect(x: body.maxX + 1.5, y: body.midY - 1.8,
                                   width: 1.8, height: 3.6), xRadius: 0.9, yRadius: 0.9).fill()
    let level = fraction.isFinite ? min(max(fraction, 0), 1) : 0
    if percentage != "—" && level > 0 {
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSColor.systemGreen.setFill()
        NSRect(x: body.minX, y: body.minY,
               width: body.width * level, height: body.height).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    let text = NSAttributedString(string: percentage, attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.labelColor,
    ])
    text.draw(at: NSPoint(x: body.maxX + 9, y: bounds.midY - text.size().height / 2))
}

private final class QuotaProgressView: NSView {
    var value = 0.0 { didSet { needsDisplay = true } }
    var fillColor = NSColor.systemGreen { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("剩余额度")
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 104, height: 104) }

    override func draw(_ dirtyRect: NSRect) {
        drawQuotaRing(in: bounds, fraction: value, color: fillColor)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class StatusPopoverViewController: NSViewController {
    private let callback: PopoverActionCallback

    private let titleLabel = NSTextField(labelWithString: "Codex left")
    private let percentageLabel = NSTextField(labelWithString: "—")
    private let usedLabel = NSTextField(labelWithString: "已用 —")
    private let windowLabel = NSTextField(labelWithString: "Not available")
    private let progressIndicator = QuotaProgressView()
    private let modelValue = NSTextField(labelWithString: "Not available")
    private let resetValue = NSTextField(labelWithString: "Not available")
    private let statusIcon = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "Unavailable")
    private let refreshSpinner = NSProgressIndicator()
    private let startAtLoginSwitch = NSSwitch()

    init(callback: @escaping PopoverActionCallback) {
        self.callback = callback
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let materialView = NSVisualEffectView()
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 18
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true
        materialView.layer?.borderWidth = 0.7
        materialView.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
        materialView.setAccessibilityRole(.group)
        materialView.setAccessibilityLabel("Codex quota details")

        configureLabels()
        configureProgress()
        configureActions()

        let content = NSStackView(views: [
            makeHeader(),
            makeQuotaSection(),
            makeDetailsSection(),
            separator(),
            makeActionsSection(),
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 15
        content.translatesAutoresizingMaskIntoConstraints = false

        materialView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: materialView.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 17),
            content.bottomAnchor.constraint(equalTo: materialView.bottomAnchor, constant: -17),
            materialView.widthAnchor.constraint(equalToConstant: 304),
            materialView.heightAnchor.constraint(equalToConstant: 388),
        ])

        view = materialView
        updateStatusAppearance(.unavailable)
    }

    func update(
        title: String,
        percentage: String,
        windowName: String,
        progress: Double,
        modelName: String,
        resetTime: String,
        statusText: String,
        statusCode: Int32,
        startAtLogin: Bool
    ) {
        _ = view // Load the controls before applying the first snapshot.
        titleLabel.stringValue = "Codex Lens"
        percentageLabel.stringValue = percentage
        windowLabel.stringValue = windowName == "5-hour quota" ? "5 小时额度" : (windowName == "Weekly quota" ? "本周额度" : "额度暂不可用")
        usedLabel.stringValue = percentage == "—" ? "已用 —" : "已用 \(Int((100 - progress * 100).rounded()))%"
        progressIndicator.value = min(max(progress, 0), 1)
        modelValue.stringValue = modelName
        resetValue.stringValue = resetTime
        statusLabel.stringValue = statusText
        startAtLoginSwitch.state = startAtLogin ? .on : .off

        let status = PopoverDataStatus(rawValue: statusCode) ?? .unavailable
        updateStatusAppearance(status)
        updateAccessibility(percentage: percentage, statusText: statusText)
    }

    func setStartAtLogin(_ enabled: Bool) {
        startAtLoginSwitch.state = enabled ? .on : .off
    }

    private func configureLabels() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let quotaDescriptor = NSFont
            .systemFont(ofSize: 27, weight: .semibold)
            .fontDescriptor
            .withDesign(.rounded)
        percentageLabel.font = quotaDescriptor
            .flatMap { NSFont(descriptor: $0, size: 27) }
            ?? .systemFont(ofSize: 27, weight: .semibold)
        percentageLabel.maximumNumberOfLines = 1

        usedLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        usedLabel.textColor = .secondaryLabelColor
        windowLabel.font = .systemFont(ofSize: 13)
        windowLabel.textColor = .secondaryLabelColor

        for value in [modelValue, resetValue] {
            value.font = .systemFont(ofSize: 12.5)
            value.maximumNumberOfLines = 0
            value.lineBreakMode = .byWordWrapping
            value.isSelectable = true
        }

        statusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        statusLabel.maximumNumberOfLines = 1
    }

    private func configureProgress() {
        progressIndicator.value = 0
        progressIndicator.fillColor = .secondaryLabelColor

        refreshSpinner.style = .spinning
        refreshSpinner.controlSize = .small
        refreshSpinner.isDisplayedWhenStopped = false
        refreshSpinner.setAccessibilityElement(false)
    }

    private func configureActions() {
        startAtLoginSwitch.controlSize = .small
        startAtLoginSwitch.target = self
        startAtLoginSwitch.action = #selector(toggleStartAtLogin)
        startAtLoginSwitch.setAccessibilityLabel("Start at login")
    }

    private func makeHeader() -> NSView {
        let gauge = symbolView(
            "gauge.with.dots.needle.50percent",
            description: "Codex quota"
        )
        gauge.contentTintColor = .controlAccentColor

        statusIcon.imageScaling = .scaleProportionallyDown
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusIcon.widthAnchor.constraint(equalToConstant: 14),
            statusIcon.heightAnchor.constraint(equalToConstant: 14),
        ])

        let status = NSStackView(views: [statusIcon, statusLabel])
        status.orientation = .horizontal
        status.alignment = .centerY
        status.spacing = 5
        status.setAccessibilityRole(.group)

        let row = NSStackView(views: [gauge, titleLabel, flexibleSpacer(), status])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        pinToContentWidth(row)
        return row
    }

    private func makeQuotaSection() -> NSView {
        let ring = NSView()
        ring.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        percentageLabel.translatesAutoresizingMaskIntoConstraints = false
        ring.addSubview(progressIndicator)
        ring.addSubview(percentageLabel)
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 104),
            ring.heightAnchor.constraint(equalToConstant: 104),
            progressIndicator.leadingAnchor.constraint(equalTo: ring.leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: ring.trailingAnchor),
            progressIndicator.topAnchor.constraint(equalTo: ring.topAnchor),
            progressIndicator.bottomAnchor.constraint(equalTo: ring.bottomAnchor),
            percentageLabel.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            percentageLabel.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
        ])
        let remainingLabel = NSTextField(labelWithString: "剩余额度")
        remainingLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        let details = NSStackView(views: [remainingLabel, windowLabel, usedLabel])
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 8
        let row = NSStackView(views: [ring, details])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        pinToContentWidth(row)
        return row
    }

    private func makeDetailsSection() -> NSView {
        let stack = NSStackView(views: [
            detailRow(
                symbol: "cpu",
                label: "Current model",
                value: modelValue
            ),
            detailRow(
                symbol: "clock.arrow.circlepath",
                label: "Next reset",
                value: resetValue
            ),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        pinToContentWidth(stack)
        return stack
    }

    private func makeActionsSection() -> NSView {
        let refreshButton = actionButton(
            "Refresh now",
            symbol: "arrow.clockwise",
            action: #selector(refresh)
        )
        refreshButton.setAccessibilityHelp("Refreshes Codex quota data")

        let refreshRow = NSStackView(views: [
            refreshButton,
            flexibleSpacer(),
            refreshSpinner,
        ])
        refreshRow.orientation = .horizontal
        refreshRow.alignment = .centerY
        pinToContentWidth(refreshRow)

        let startLabel = NSTextField(labelWithString: "Start at login")
        startLabel.font = .systemFont(ofSize: 12.5)
        let powerIcon = symbolView("power", description: nil)
        powerIcon.contentTintColor = .labelColor
        let startRow = NSStackView(views: [
            powerIcon,
            startLabel,
            flexibleSpacer(),
            startAtLoginSwitch,
        ])
        startRow.orientation = .horizontal
        startRow.alignment = .centerY
        startRow.spacing = 7
        pinToContentWidth(startRow)

        let quitButton = actionButton(
            "Quit",
            symbol: "power.circle",
            action: #selector(quit)
        )
        quitButton.contentTintColor = .systemRed
        quitButton.setAccessibilityHelp("Quits Codex Lens")

        let stack = NSStackView(views: [refreshRow, startRow, quitButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        pinToContentWidth(stack)
        quitButton.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func detailRow(
        symbol: String,
        label: String,
        value: NSTextField
    ) -> NSView {
        let icon = symbolView(symbol, description: nil)
        icon.contentTintColor = .secondaryLabelColor

        let caption = NSTextField(labelWithString: label)
        caption.font = .systemFont(ofSize: 10.5)
        caption.textColor = .secondaryLabelColor

        let values = NSStackView(views: [caption, value])
        values.orientation = .vertical
        values.alignment = .leading
        values.spacing = 2

        let row = NSStackView(views: [icon, values])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 9
        pinToContentWidth(row)
        values.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -25).isActive = true
        return row
    }

    private func actionButton(
        _ title: String,
        symbol: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 12.5)
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        )
        button.imagePosition = .imageLeading
        return button
    }

    private func symbolView(
        _ name: String,
        description: String?
    ) -> NSImageView {
        let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: description
        ) ?? NSImage()
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyDown
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 16),
            view.heightAnchor.constraint(equalToConstant: 16),
        ])
        if description == nil {
            view.setAccessibilityElement(false)
        }
        return view
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        pinToContentWidth(line)
        return line
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func pinToContentWidth(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 268).isActive = true
    }

    private func updateStatusAppearance(_ status: PopoverDataStatus) {
        statusIcon.image = NSImage(
            systemSymbolName: status.symbolName,
            accessibilityDescription: nil
        )
        statusIcon.contentTintColor = status.tint
        statusLabel.textColor = status.tint

        if status == .refreshing {
            refreshSpinner.startAnimation(nil)
        } else {
            refreshSpinner.stopAnimation(nil)
        }

        progressIndicator.fillColor = percentageLabel.stringValue == "—"
            ? .secondaryLabelColor : .systemGreen
    }

    private func updateAccessibility(percentage: String, statusText: String) {
        percentageLabel.setAccessibilityLabel(
            percentage == "—"
                ? "Quota unavailable"
                : "\(percentage) remaining"
        )
        progressIndicator.setAccessibilityValue(
            percentage == "—" ? "Unavailable" : percentage
        )
        statusIcon.setAccessibilityElement(false)
        statusLabel.setAccessibilityLabel("Sync status: \(statusText)")
        modelValue.setAccessibilityLabel("Current model: \(modelValue.stringValue)")
        resetValue.setAccessibilityLabel("Next reset: \(resetValue.stringValue)")
    }

    @objc private func refresh() {
        callback(PopoverAction.refresh.rawValue)
    }

    @objc private func toggleStartAtLogin() {
        callback(PopoverAction.toggleStartAtLogin.rawValue)
    }

    @objc private func quit() {
        callback(PopoverAction.quit.rawValue)
    }
}

// Let the system menu bar supply the backdrop. A barely tinted surface
// groups the values without stacking another refractive glass layer over it.
private final class QuotaCapsuleSurfaceView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor.white.withAlphaComponent(0.075) : NSColor.black.withAlphaComponent(0.045)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class QuotaCapsuleContentView: NSView {
    var percentage = "—"
    var fraction = 0.0
    var resetLabel = ""
    private let resetFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    private let quotaFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

    private var badgeWidth: CGFloat {
        32 + ceil((percentage as NSString).size(withAttributes: [.font: quotaFont]).width)
    }

    var requiredWidth: CGFloat {
        let textWidth = (resetLabel as NSString).size(withAttributes: [.font: resetFont]).width
        return ceil(10 + badgeWidth + (resetLabel.isEmpty ? 0 : 12 + textWidth) + 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        let badge = NSRect(x: 10, y: bounds.midY - 9, width: badgeWidth, height: 18)
        drawQuotaBadge(in: badge, fraction: fraction, percentage: percentage)
        let text = NSAttributedString(string: resetLabel, attributes: [
            .font: resetFont,
            .foregroundColor: NSColor.labelColor,
        ])
        text.draw(at: NSPoint(x: badge.maxX + 12, y: bounds.midY - text.size().height / 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// Handle the native button's complete bounds. The tray library's hit view
// does not resize when Swift changes the image and title directly.
private final class StatusPopoverClickView: NSView {
    var onClick: (() -> Void)?
    weak var rightClickTarget: NSView?
    private let capsuleContent = QuotaCapsuleContentView()
    private let material = QuotaCapsuleSurfaceView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(material)
        addSubview(capsuleContent)
    }

    required init?(coder: NSCoder) { nil }

    func update(percentage: String, fraction: Double, resetLabel: String) -> CGFloat {
        capsuleContent.percentage = percentage
        capsuleContent.fraction = fraction
        capsuleContent.resetLabel = resetLabel
        capsuleContent.needsDisplay = true
        needsLayout = true
        return capsuleContent.requiredWidth + 4
    }

    override func layout() {
        super.layout()
        let height = min(22, bounds.height)
        material.frame = NSRect(x: 2, y: bounds.midY - height / 2, width: max(0, bounds.width - 4), height: height)
        capsuleContent.frame = material.frame
    }

    // Decorative surfaces must never steal the capsule's click target.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        (superview as? NSStatusBarButton)?.highlight(true)
    }

    override func mouseUp(with event: NSEvent) {
        (superview as? NSStatusBarButton)?.highlight(false)
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        rightClickTarget?.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        rightClickTarget?.rightMouseUp(with: event)
    }
}

private final class StatusPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let clickView = StatusPopoverClickView()
    private let content: StatusPopoverViewController
    private var statusItem: NSStatusItem?

    init(statusItem: NSStatusItem, callback: @escaping PopoverActionCallback) {
        self.statusItem = statusItem
        content = StatusPopoverViewController(callback: callback)
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 304, height: 388)
        popover.contentViewController = content
        popover.delegate = self

        if let button = statusItem.button {
            clickView.rightClickTarget = button.subviews.first {
                String(describing: type(of: $0)) == "TaoTrayTarget"
            }
            clickView.frame = button.bounds
            clickView.autoresizingMask = [.width, .height]
            clickView.setAccessibilityElement(false)
            clickView.onClick = { [weak self] in self?.toggle() }
            button.addSubview(clickView, positioned: .above, relativeTo: nil)
        }
    }

    func update(
        title: String,
        percentage: String,
        windowName: String,
        progress: Double,
        modelName: String,
        resetTime: String,
        statusText: String,
        statusCode: Int32,
        startAtLogin: Bool
    ) {
        if let button = statusItem?.button {
            let hasValue = percentage != "—"
            let fraction = hasValue && progress.isFinite ? min(max(progress, 0), 1) : 0
            // The percentage lives inside the badge; the label carries only reset/status.
            let resetLabel = hasValue && title.hasPrefix(percentage)
                ? String(title.dropFirst(percentage.count)).trimmingCharacters(in: .whitespaces)
                : "5 小时额度不可用"
            let compactLabel = resetLabel.hasPrefix("·")
                ? String(resetLabel.dropFirst()).trimmingCharacters(in: .whitespaces)
                : resetLabel
            button.image = nil
            button.title = ""
            let width = clickView.update(percentage: percentage, fraction: fraction, resetLabel: compactLabel)
            // Size from the complete string: no truncation, including cross-day resets.
            statusItem?.length = width
            clickView.frame = button.bounds
            clickView.layoutSubtreeIfNeeded()
            button.setAccessibilityLabel("Codex Lens，五小时剩余 \(percentage)，\(resetTime) 重置，\(statusText)")
        }
        content.update(
            title: title,
            percentage: percentage,
            windowName: windowName,
            progress: progress,
            modelName: modelName,
            resetTime: resetTime,
            statusText: statusText,
            statusCode: statusCode,
            startAtLogin: startAtLogin
        )
    }

    func setStartAtLogin(_ enabled: Bool) {
        content.setStartAtLogin(enabled)
    }

    func toggle() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            button.highlight(true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
    }
}

private enum StatusPopoverBridge {
    static var controller: StatusPopoverController?
}

private func copyCString(_ value: UnsafePointer<CChar>?) -> String {
    guard let value else { return "" }
    return String(cString: value)
}

@_cdecl("codex_lens_status_popover_configure")
public func codexLensStatusPopoverConfigure(
    _ statusItemPointer: UnsafeMutableRawPointer,
    _ callback: @escaping PopoverActionCallback
) {
    let statusItem = Unmanaged<NSStatusItem>
        .fromOpaque(statusItemPointer)
        .takeUnretainedValue()
    DispatchQueue.main.async {
        StatusPopoverBridge.controller = StatusPopoverController(
            statusItem: statusItem,
            callback: callback
        )
    }
}

@_cdecl("codex_lens_status_popover_update")
public func codexLensStatusPopoverUpdate(
    _ titlePointer: UnsafePointer<CChar>?,
    _ percentagePointer: UnsafePointer<CChar>?,
    _ windowPointer: UnsafePointer<CChar>?,
    _ progress: Double,
    _ modelPointer: UnsafePointer<CChar>?,
    _ resetPointer: UnsafePointer<CChar>?,
    _ statusPointer: UnsafePointer<CChar>?,
    _ statusCode: Int32,
    _ startAtLogin: Int32
) {
    let title = copyCString(titlePointer)
    let percentage = copyCString(percentagePointer)
    let windowName = copyCString(windowPointer)
    let modelName = copyCString(modelPointer)
    let resetTime = copyCString(resetPointer)
    let statusText = copyCString(statusPointer)

    DispatchQueue.main.async {
        StatusPopoverBridge.controller?.update(
            title: title,
            percentage: percentage,
            windowName: windowName,
            progress: progress,
            modelName: modelName,
            resetTime: resetTime,
            statusText: statusText,
            statusCode: statusCode,
            startAtLogin: startAtLogin != 0
        )
    }
}

@_cdecl("codex_lens_status_popover_set_start_at_login")
public func codexLensStatusPopoverSetStartAtLogin(_ enabled: Int32) {
    DispatchQueue.main.async {
        StatusPopoverBridge.controller?.setStartAtLogin(enabled != 0)
    }
}

@_cdecl("codex_lens_status_popover_toggle")
public func codexLensStatusPopoverToggle() {
    DispatchQueue.main.async {
        StatusPopoverBridge.controller?.toggle()
    }
}
