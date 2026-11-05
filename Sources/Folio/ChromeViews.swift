import AppKit
import FolioCore

/// D1's status light (`.led`): a dot with a soft ring and, in dark, a glow. `breathing` runs the
/// 3.2 s opacity cycle from 0.42 to 1 (off under Reduce motion).
final class LedView: NSView, ThemeAware {
    static let padding: CGFloat = 5
    let diameter: CGFloat
    var tone: (Palette) -> RGBA = { $0.accent } { didSet { themeDidChange() } }
    var breathing = false { didSet { updateAnimation() } }
    /// D1's `pulse2`: two quick flashes every 1.6 s (the HUD while the address is being edited).
    var pulsing = false { didSet { if pulsing != oldValue { updateAnimation() } } }
    /// D1's `blink`: on, then at 18% for half of every second (paused, waiting on a conflict).
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
        core.shadowRadius = 4.5
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
        ring.backgroundColor = c.withAlpha(0.18).cg
        core.shadowColor = c.cg
        core.shadowOpacity = p.glows ? 0.62 : 0
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

/// A 44 pt toolbar button drawn the D1 way: stroke icon, an 8% state layer on hover, 14% pressed,
/// 34% opacity when disabled, and corner brackets on hover (`.hb`).
final class ChromeButton: NSButton {
    var glyph: Glyph { didSet { needsDisplay = true } }
    var tone: (Palette) -> RGBA = { $0.txt }
    var hoverTone: ((Palette) -> RGBA)?
    var iconSize: CGFloat = 18
    var hoverBrackets = true
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
        var tone = button.tone(p)
        if hot, let hover = button.hoverTone { tone = hover(p) }
        if isEnabled && (hot || isHighlighted) {
            fillRounded(cellFrame, radius: 5, tone.withAlpha(isHighlighted ? 0.14 : 0.08))
        }
        let s = button.iconSize * (isHighlighted ? 0.95 : 1)
        let icon = NSRect(x: cellFrame.midX - s / 2, y: cellFrame.midY - s / 2, width: s, height: s)
        button.glyph.draw(in: icon, color: tone.withAlpha(isEnabled ? 1 : 0.34).ns)
        if hot && button.hoverBrackets {
            drawBrackets(cellFrame, color: p.bracket.ns, length: 7)
        }
        if let key = button.accessKey {
            // D1's kbd: line-3 outline with a 2 pt bottom edge, s2, Chivo Mono 500.
            let font = Typeface.mono(11, weight: 600)
            let w = max(16, textWidth(key, font: font) + 8)
            let cap = NSRect(x: cellFrame.maxX - w - 1, y: cellFrame.maxY - 18, width: w, height: 17)
            fillRounded(cap, radius: 3, p.line3)
            fillRounded(NSRect(x: cap.minX + 1, y: cap.minY + 1, width: cap.width - 2, height: cap.height - 3), radius: 2.5, p.s2)
            drawLine(key, font: font, color: p.accent, x: cap.midX - textWidth(key, font: font) / 2, midY: cap.minY + 7.5)
        }
    }
}

/// One accent swatch in the title bar (`.acc`): a 14 pt dot, ringed when chosen.
final class AccentSwatch: NSButton {
    let accent: AccentChoice
    var isChosen = false { didSet { needsDisplay = true } }

    init(accent: AccentChoice, target: AnyObject?, action: Selector?) {
        self.accent = accent
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 44))
        isBordered = false
        title = ""
        self.target = target
        self.action = action
        toolTip = accent.title + " accent"
        setAccessibilityLabel(accent.title + " accent")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        func dot(_ r: CGFloat, _ color: RGBA) {
            color.ns.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
        }
        let r: CGFloat = isChosen ? 7.35 : 7
        if isChosen {
            dot(r + 3.5, p.txt)
            dot(r + 2, p.bg)
        } else {
            dot(r + 1, p.line3)
            dot(r + 0.01, p.bg)
        }
        dot(r, accent.color(for: p.appearance))
    }
}

/// The 44 pt title bar: traffic lights (the window's own), the Folio mark, the folder name and full
/// path, the accent swatches and the theme switch. Dragging it moves the window.
final class TitleBarView: NSView, ThemeAware {
    var folderName = "" { didSet { needsDisplay = true } }
    var folderPath = "" { didSet { needsDisplay = true } }

    let swatches: [AccentSwatch]
    let themeButton: ChromeButton

    init(target: AnyObject?, accentAction: Selector, themeAction: Selector) {
        swatches = AccentChoice.allCases.map { AccentSwatch(accent: $0, target: target, action: accentAction) }
        themeButton = ChromeButton(glyph: .sun, label: "Switch theme", target: target, action: themeAction)
        themeButton.tone = { $0.txt2 }
        themeButton.hoverTone = { $0.txt }
        themeButton.hoverBrackets = false
        super.init(frame: .zero)
        for swatch in swatches { addSubview(swatch) }
        addSubview(themeButton)
        themeDidChange()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func themeDidChange() {
        let p = Palette.current
        for swatch in swatches { swatch.isChosen = swatch.accent == p.accentChoice }
        themeButton.glyph = p.appearance == .dark ? .sun : .moon
        themeButton.toolTip = p.appearance == .dark ? "Light theme" : "Dark theme"
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        themeButton.frame = NSRect(x: w - 6 - 44, y: 0, width: 44, height: 44)
        // .accents: padding 0 6, gap 6, border-right, then margin 2 and gap 6 before the theme button.
        let groupRight = themeButton.frame.minX - 6 - 2
        var x = groupRight - 1 - 6 - 30 * 3 - 6 * 2
        for swatch in swatches {
            swatch.frame = NSRect(x: x, y: 0, width: 30, height: 44)
            x += 36
        }
        (window as? BrowserWindow)?.placeTrafficLights()
    }

    private var accentGroupLeft: CGFloat { (swatches.first?.frame.minX ?? bounds.width) - 6 }
    private var accentGroupRight: CGFloat { themeButton.frame.minX - 8 - 1 }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.bg)
        fillRect(NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1), p.line)
        let mid = bounds.height / 2
        // Brand: traffic lights take 14 + 52, then a 12 gap.
        let brandX: CGFloat = 78
        ItemIcon.drawBrand(in: NSRect(x: brandX + 6, y: mid - 9, width: 18, height: 18), palette: p)
        let brandFont = Typeface.ui(14, weight: 800, width: 124)
        let brandW = drawLine("Folio", font: brandFont, color: p.txt, x: brandX + 32, midY: mid, kern: 0.14)
        let brandRight = brandX + 32 + brandW + 10
        fillRect(NSRect(x: brandRight, y: mid - 11, width: 1, height: 22), p.line)
        // Folder name and path, baseline aligned; the path gives way first.
        fillRect(NSRect(x: accentGroupRight, y: 0, width: 1, height: bounds.height - 1), p.line)
        let titleX = brandRight + 1 + 12
        let room = accentGroupLeft - 12 - titleX
        guard room > 20 else { return }
        let nameFont = Typeface.ui(14, weight: 700, width: 124)
        let nameW = drawLine(folderName, font: nameFont, color: p.txt, x: titleX, midY: mid, maxWidth: room)
        let pathRoom = room - nameW - 12
        if pathRoom > 30 {
            let pathFont = Typeface.mono(12)
            // Same baseline as the name: shift by the ascender difference.
            let shift = (nameFont.ascender - nameFont.descender) / 2 - nameFont.ascender
                - ((pathFont.ascender - pathFont.descender) / 2 - pathFont.ascender)
            drawLine(folderPath, font: pathFont, color: p.txt3, x: titleX + nameW + 12, midY: mid - shift, maxWidth: pathRoom)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}
