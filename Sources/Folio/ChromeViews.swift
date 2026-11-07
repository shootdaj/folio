import AppKit
import FolioCore

/// A status light (D4's `.sb-dot`): a dot with a soft glow. `breathing` runs a slow opacity cycle from
/// 0.42 to 1 (off under Reduce motion).
final class LedView: NSView, ThemeAware {
    static let padding: CGFloat = 5
    let diameter: CGFloat
    var tone: (Palette) -> RGBA = { $0.accent } { didSet { themeDidChange() } }
    var breathing = false { didSet { updateAnimation() } }
    /// Two quick flashes every 1.6 s.
    var pulsing = false { didSet { if pulsing != oldValue { updateAnimation() } } }
    /// On, then at 18% for half of every second (paused, waiting on a conflict).
    var blinking = false { didSet { if blinking != oldValue { updateAnimation() } } }
    var isLit = true { didSet { isHidden = !isLit; updateAnimation() } }

    private let ring = CALayer()
    private let core = CALayer()

    init(diameter: CGFloat) {
        self.diameter = diameter
        let side = diameter + 2 * Self.padding
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        wantsLayer = true
        clipsToBounds = false
        let c = NSRect(x: Self.padding, y: Self.padding, width: diameter, height: diameter)
        ring.frame = c.insetBy(dx: -2, dy: -2)
        ring.cornerRadius = ring.frame.width / 2
        core.frame = c
        core.cornerRadius = diameter / 2
        core.shadowOffset = .zero
        core.shadowRadius = 4
        layer?.addSublayer(ring)
        layer?.addSublayer(core)
        themeDidChange()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Positions the light so its dot's top-left sits at `origin`.
    func place(dotAt origin: NSPoint) {
        setFrameOrigin(NSPoint(x: origin.x - Self.padding, y: origin.y - Self.padding))
    }

    func themeDidChange() {
        let p = Palette.current
        let c = tone(p)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        core.backgroundColor = c.cg
        ring.backgroundColor = NSColor.clear.cgColor
        core.shadowColor = c.cg
        core.shadowOpacity = 0.8
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    private func updateAnimation() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "breathe")
        guard breathing || pulsing || blinking, isLit, window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        if blinking {
            let k = CAKeyframeAnimation(keyPath: "opacity")
            k.values = [1, 0.18]
            k.keyTimes = [0, 0.5]
            k.calculationMode = .discrete
            k.duration = 1
            k.repeatCount = .infinity
            layer.add(k, forKey: "breathe")
            return
        }
        if pulsing {
            let k = CAKeyframeAnimation(keyPath: "opacity")
            k.values = [0.3, 1, 0.3, 1, 0.3, 0.3]
            k.keyTimes = [0, 0.07, 0.14, 0.21, 0.34, 1]
            k.duration = 1.6
            k.repeatCount = .infinity
            layer.add(k, forKey: "breathe")
            return
        }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 0.42
        a.toValue = 1
        a.duration = 1.6
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(a, forKey: "breathe")
    }
}

/// D4's icon button (`.ib`): 44 pt, a stroke icon in text-2 (text on hover), an 8% state layer inset
/// 5 pt on hover, 14% and a slight shrink while pressed, faint when disabled.
final class ChromeButton: NSButton {
    var glyph: Glyph { didSet { needsDisplay = true } }
    var tone: (Palette) -> RGBA = { $0.text2 }
    var hoverTone: ((Palette) -> RGBA)? = { $0.text }
    var iconSize: CGFloat = 18
    fileprivate(set) var isHovered = false
    /// Access keys (Option tapped): the letter that presses this button, shown as a key cap.
    var accessKey: String? {
        didSet {
            guard accessKey != oldValue else { return }
            setAccessibilityValue(accessKey ?? "")
            needsDisplay = true
        }
    }

    init(glyph: Glyph, label: String, target: AnyObject?, action: Selector?) {
        self.glyph = glyph
        super.init(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
        cell = ChromeButtonCell()
        isBordered = false
        title = ""
        setButtonType(.momentaryPushIn)
        self.target = target
        self.action = action
        toolTip = label
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    /// Back and Forward: holding the button 0.45 s, or right-clicking it, shows the history list.
    var onHold: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard let onHold, isEnabled, let window else { return super.mouseDown(with: event) }
        isHighlighted = true
        let deadline = Date().addingTimeInterval(0.45)
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: deadline,
                                              inMode: .eventTracking, dequeue: true) else {
                isHighlighted = false
                onHold()
                return
            }
            if next.type == .leftMouseUp {
                isHighlighted = false
                if bounds.contains(convert(next.locationInWindow, from: nil)) { sendAction(action, to: target) }
                return
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let onHold else { return super.rightMouseDown(with: event) }
        if isEnabled { onHold() }
    }
}

final class ChromeButtonCell: NSButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let button = controlView as? ChromeButton else { return }
        let p = Palette.current
        let hot = isEnabled && button.isHovered
        var tone = isEnabled ? button.tone(p) : p.faint
        if hot, let hover = button.hoverTone { tone = hover(p) }
        if isEnabled && (hot || isHighlighted) {
            // The state layer: currentColor at 8% (hover) or 14% (pressed), 5 pt in, radius 8.
            let inset = min(5, max(1, (min(cellFrame.width, cellFrame.height) - 24) / 2))
            fillRounded(cellFrame.insetBy(dx: inset, dy: inset), radius: 8, tone.withAlpha(isHighlighted ? 0.14 : 0.08))
        }
        let s = button.iconSize * (isHighlighted ? 0.92 : 1)
        let icon = NSRect(x: cellFrame.midX - s / 2, y: cellFrame.midY - s / 2, width: s, height: s)
        button.glyph.draw(in: icon, color: tone.ns)
        if let key = button.accessKey {
            // D4's kbd: line-2 outline with a 2 pt bottom edge, s2, Geist Mono 500 in text-2.
            let font = Typeface.mono(11, weight: 600)
            let w = max(16, textWidth(key, font: font) + 8)
            let cap = NSRect(x: cellFrame.maxX - w - 1, y: cellFrame.maxY - 18, width: w, height: 17)
            fillRounded(cap, radius: 5, p.line2)
            fillRounded(NSRect(x: cap.minX + 1, y: cap.minY + 1, width: cap.width - 2, height: cap.height - 3), radius: 4, p.s2)
            drawLine(key, font: font, color: p.text, x: cap.midX - textWidth(key, font: font) / 2, midY: cap.minY + 7.5)
        }
    }
}

/// The accent swatch at the right end of the title bar (`.acc-btn`): an 18 pt dot in the accent with a
/// hairline and a 3 pt accent halo, growing a little on hover and while its popover is open.
final class AccentButton: NSButton {
    private var hovered = false
    var isOpen = false { didSet { needsDisplay = true } }

    init(target: AnyObject?, action: Selector?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
        isBordered = false
        title = ""
        self.target = target
        self.action = action
        toolTip = "Accent colour"
        setAccessibilityLabel("Accent colour")
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        if hovered || isHighlighted {
            fillRounded(bounds.insetBy(dx: 5, dy: 5), radius: 8, p.text.withAlpha(isHighlighted ? 0.14 : 0.08))
        }
        let r: CGFloat = 9 * (hovered || isOpen ? 1.14 : 1)
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        func dot(_ radius: CGFloat, _ color: RGBA) {
            color.ns.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius)).fill()
        }
        dot(r + 3, p.accent.withAlpha(0.22))
        dot(r, p.accent)
        p.text.withAlpha(0.22).ns.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r + 0.5, y: c.y - r + 0.5, width: 2 * r - 1, height: 2 * r - 1))
        ring.lineWidth = 1
        ring.stroke()
    }
}

/// The 44 pt title bar (`.titlebar`): the window's traffic lights, the tabs, and the accent swatch at the
/// right end. `--chrome` with a hairline under it. Dragging empty space moves the window.
final class TitleBarView: NSView, ThemeAware {
    let accentButton: AccentButton

    init(target: AnyObject?, accentAction: Selector) {
        accentButton = AccentButton(target: target, action: accentAction)
        super.init(frame: .zero)
        addSubview(accentButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func themeDidChange() { accentButton.needsDisplay = true }

    /// Where the tabs go: after the lights (16 + 52) and the 20 pt of margin and gap, up to the swatch.
    var tabsFrame: NSRect {
        NSRect(x: 88, y: 0, width: max(0, accentButton.frame.minX - 10 - 88), height: bounds.height)
    }

    override func layout() {
        super.layout()
        accentButton.frame = NSRect(x: bounds.width - 6 - 44, y: 0, width: 44, height: 44)
        (window as? BrowserWindow)?.placeTrafficLights()
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.chrome)
        fillRect(NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1), p.line)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}
