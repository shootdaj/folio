import AppKit
import FolioCore

/// The accent picker (D4's `.picker`): an NSPopover under the title bar's swatch with D4's eight preset
/// swatches and a full-spectrum hue slider. Dragging the slider recolours every window live; the hue is
/// saved when the drag ends (or at once for a preset or a key press). Esc or a click outside closes it.
@MainActor
final class AccentPicker: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let view = AccentPickerView(frame: NSRect(x: 0, y: 0, width: 316, height: 156))
    private weak var button: AccentButton?

    var isShown: Bool { popover.isShown }

    override init() {
        super.init()
        let controller = NSViewController()
        controller.view = view
        popover.contentViewController = controller
        popover.contentSize = view.frame.size
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        // D4's picker is a plain rounded panel, no arrow.
        if popover.responds(to: NSSelectorFromString("setShouldHideAnchor:")) {
            popover.setValue(true, forKey: "shouldHideAnchor")
        }
    }

    func toggle(from button: AccentButton) {
        if popover.isShown { popover.performClose(nil); return }
        self.button = button
        view.refresh()
        popover.appearance = NSApp.effectiveAppearance
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        button.isOpen = true
    }

    func close() { if popover.isShown { popover.performClose(nil) } }

    func popoverDidClose(_ notification: Notification) {
        view.commitPreview()
        button?.isOpen = false
    }
}

/// The picker's content: header ("ACCENT", "262°"), the presets, the slider, the Dark and Light dots.
final class AccentPickerView: NSView, ThemeAware {
    private var swatches: [PresetSwatch] = []
    private let slider = HueSlider(frame: .zero)

    override init(frame: NSRect) {
        super.init(frame: frame)
        for preset in Accent.presets {
            let s = PresetSwatch(name: preset.name, hue: preset.hue)
            s.target = self
            s.action = #selector(pickPreset(_:))
            swatches.append(s)
            addSubview(s)
        }
        slider.minValue = 0
        slider.maxValue = 359
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(slid(_:))
        slider.setAccessibilityLabel("Accent hue")
        addSubview(slider)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Accent colour")
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged(_:)), name: ThemeController.didChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    @objc private func themeChanged(_ note: Notification) { themeDidChange() }

    func themeDidChange() {
        refresh()
    }

    /// Ticks the chosen preset and puts the slider on the current hue.
    func refresh() {
        let hue = ThemeController.shared.hue
        for s in swatches { s.isChosen = s.hue == hue; s.needsDisplay = true }
        if Int(slider.doubleValue.rounded()) != hue { slider.doubleValue = Double(hue) }
        slider.needsDisplay = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        // `.pk-pre`: eight columns across the panel, 4 pt past its padding on each side, 36 pt high.
        let left: CGFloat = 10, width = bounds.width - 20
        let col = width / CGFloat(swatches.count)
        for (i, s) in swatches.enumerated() {
            s.frame = NSRect(x: left + CGFloat(i) * col, y: 34, width: col, height: 36)
        }
        slider.frame = NSRect(x: 14, y: 76, width: bounds.width - 28, height: 36)
    }

    @objc private func pickPreset(_ sender: PresetSwatch) {
        ThemeController.shared.hue = sender.hue
        refresh()
    }

    @objc private func slid(_ sender: HueSlider) {
        let hue = Accent.normalized(sender.doubleValue)
        let event = NSApp.currentEvent?.type
        if event == .leftMouseDragged || event == .leftMouseDown {
            ThemeController.shared.preview(hue: hue)
        } else {
            ThemeController.shared.hue = hue
        }
        for s in swatches { s.isChosen = s.hue == hue; s.needsDisplay = true }
        needsDisplay = true
    }

    /// The popover closed or the mouse came up mid-drag: keep what is shown.
    func commitPreview() {
        let shown = ThemeController.shared.hue
        ThemeController.shared.hue = shown
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        // `--pop` (s2 88%, light s1 93%) over the window, with D4's line-2 border.
        let fill = p.pop.over(p.bg)
        fillRounded(bounds, radius: 12, fill)
        strokeRounded(bounds, radius: 12, p.line2)
        let hue = ThemeController.shared.hue
        drawLine("ACCENT", font: Typeface.mono(12, weight: 600), color: p.muted, x: 14, midY: 19, kern: Typeface.labelKern(12))
        drawLine("\(hue)°", font: Typeface.mono(12, weight: 500), color: p.text2, x: bounds.width - 14, midY: 19, alignRight: true)
        // `.pk-f`: a hairline, then the Dark and Light shades and the note.
        fillRect(NSRect(x: 14, y: 118, width: bounds.width - 28, height: 1), p.line)
        let mid: CGFloat = 137
        let small = Typeface.ui(12)
        var x: CGFloat = 14
        for (label, appearance) in [("Dark", Appearance.dark), ("Light", .light)] {
            fillRounded(NSRect(x: x, y: mid - 5, width: 10, height: 10), radius: 5, Accent.color(hue: hue, appearance))
            x += 16 + drawLine(label, font: small, color: p.muted, x: x + 16, midY: mid) + 12
        }
        drawLine("Light uses a deeper shade", font: small, color: p.muted, x: bounds.width - 14, midY: mid, alignRight: true)
    }
}

/// One preset (`.pk-sw`): a 22 pt dot in the hue at this theme's lightness, ringed when chosen.
final class PresetSwatch: NSButton {
    let hue: Int
    var isChosen = false { didSet { setAccessibilityValue(isChosen ? 1 : 0) } }
    private var hovered = false

    init(name: String, hue: Int) {
        self.hue = hue
        super.init(frame: .zero)
        isBordered = false
        title = ""
        toolTip = name
        setAccessibilityLabel(name)
        setAccessibilityRole(.radioButton)
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
        let p = ThemeColors.current
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let r: CGFloat = 11 * (isHighlighted ? 0.88 : hovered ? 1.15 : 1)
        let dot = NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        Accent.color(hue: hue, p.appearance).ns.setFill()
        NSBezierPath(ovalIn: dot).fill()
        p.text.withAlpha(0.16).ns.setStroke()
        let edge = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5))
        edge.lineWidth = 1
        edge.stroke()
        if isChosen {
            p.text.ns.setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - 14, y: c.y - 14, width: 28, height: 28))
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

/// The hue slider (`.pk-range`): a 14 pt track painted with the spectrum at this theme's lightness and
/// a 22 pt thumb in the accent with a 3 pt ring in the text colour.
final class HueSlider: NSSlider {
    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = HueSliderCell()
        isContinuous = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func accessibilityValue() -> Any? { Int(doubleValue.rounded()) }
}

final class HueSliderCell: NSSliderCell {
    private static let thumb: CGFloat = 22

    override func knobRect(flipped: Bool) -> NSRect {
        guard let view = controlView else { return super.knobRect(flipped: flipped) }
        let b = view.bounds
        let span = b.width - Self.thumb
        let f = maxValue > minValue ? (doubleValue - minValue) / (maxValue - minValue) : 0
        return NSRect(x: b.minX + CGFloat(f) * span, y: b.midY - Self.thumb / 2, width: Self.thumb, height: Self.thumb)
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard let view = controlView else { return }
        let p = ThemeColors.current
        let b = view.bounds
        let track = NSRect(x: b.minX, y: b.midY - 7, width: b.width, height: 14)
        let stops = (0...12).map { Accent.color(hue: $0 * 30, p.appearance).ns }
        let locations = (0...12).map { CGFloat($0) / 12 }
        if let gradient = NSGradient(colors: stops, atLocations: locations, colorSpace: .sRGB) {
            gradient.draw(in: NSBezierPath(roundedRect: track, xRadius: 7, yRadius: 7), angle: 0)
        }
        strokeRounded(track, radius: 7, p.text.withAlpha(0.14))
    }

    override func drawKnob(_ knobRect: NSRect) {
        let p = ThemeColors.current
        let r = knobRect.insetBy(dx: 1.5, dy: 1.5)
        withGlow(RGBA(r: 0, g: 0, b: 0, a: 0.4), blur: 6) {
            p.accent.ns.setFill()
            NSBezierPath(ovalIn: r).fill()
        }
        p.text.ns.setStroke()
        let ring = NSBezierPath(ovalIn: r)
        ring.lineWidth = 3
        ring.stroke()
    }
}
