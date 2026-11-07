import AppKit
import FolioCore

/// D4's `.os-btn`: 44 pt tall at most, radius 12, a line-2 border on s2 (outline on hover), Geist 500 14,
/// an optional 16 pt icon 7 pt before the label, a slight shrink while pressed. Styles: plain, primary
/// (accent fill, ink label), warn (`.danger`: coral), ghost (no fill, text-2; s2 on hover). `isOn` is
/// `aria-pressed` (an accent border).
final class OSButton: NSButton {
    enum Style { case plain, primary, warn, ghost }

    var style: Style = .plain { didSet { needsDisplay = true } }
    var glyph: Glyph? { didSet { needsDisplay = true } }
    var isOn = false { didSet { needsDisplay = true; setAccessibilityValue(isOn ? 1 : 0) } }
    var onPress: (() -> Void)?
    private var hovered = false

    init(_ title: String, glyph: Glyph? = nil, style: Style = .plain, onPress: (() -> Void)? = nil) {
        self.style = style
        self.glyph = glyph
        self.onPress = onPress
        super.init(frame: NSRect(x: 0, y: 0, width: 112, height: 40))
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(pressed(_:))
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    @objc private func pressed(_ sender: Any?) { onPress?() }

    func setTitle(_ text: String, glyph: Glyph?, style: Style) {
        if title != text { title = text; setAccessibilityLabel(text) }
        self.glyph = glyph
        self.style = style
    }

    private var labelFont: NSFont { Typeface.ui(14, weight: style == .primary ? 600 : 500) }

    /// Width for the label and icon with D4's 16 pt padding, at least `minimum`.
    func fit(minimum: CGFloat = 0) -> CGFloat {
        max(minimum, 16 + (glyph == nil ? 0 : 16 + 7) + textWidth(title, font: labelFont) + 16)
    }

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
        let enabled = isEnabled
        let hot = enabled && hovered
        // `:active { transform: scale(.97) }`
        let r = isHighlighted && enabled ? bounds.insetBy(dx: bounds.width * 0.015, dy: bounds.height * 0.015) : bounds
        let radius: CGFloat = min(12, r.height / 2)
        var text = p.text
        switch style {
        case .primary:
            fillRounded(r, radius: radius, enabled ? p.accent : p.line2)
            if hot { withGlow(p.accent.withAlpha(0.35), blur: 24) { fillRounded(r, radius: radius, p.accent) } }
            text = enabled ? p.onAccent : p.text2
        case .warn:
            fillRounded(r, radius: radius, hot ? p.miss.withAlpha(0.12).over(p.s2) : p.s2)
            strokeRounded(r, radius: radius, hot ? p.miss : p.miss.mixed(0.55, with: p.line2))
            text = p.miss
        case .ghost:
            if hot { fillRounded(r, radius: radius, p.s2) }
            text = p.text2
        case .plain:
            fillRounded(r, radius: radius, p.s2)
            strokeRounded(r, radius: radius, isOn ? p.accent : hot ? p.outline : p.line2)
        }
        let tone = enabled ? text : text.withAlpha(0.45)
        let tw = textWidth(title, font: labelFont)
        let total = (glyph == nil ? 0 : 16 + 7) + tw
        var x = (bounds.width - total) / 2
        if let glyph {
            glyph.draw(in: NSRect(x: x, y: bounds.midY - 8, width: 16, height: 16), color: tone.ns)
            x += 23
        }
        drawLine(title, font: labelFont, color: tone, x: x, midY: bounds.midY)
    }
}

/// A check box in D4's language: a 14 pt box (outline hairline, accent fill and an ink tick when on) and
/// a Geist label. An NSButton of the switch type, so accessibility sees a check box.
final class OSCheck: NSButton {
    var onToggle: ((Bool) -> Void)?

    init(_ title: String, onToggle: ((Bool) -> Void)? = nil) {
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        setButtonType(.switch)
        self.title = title
        setAccessibilityLabel(title)
        isBordered = false
        target = self
        action = #selector(toggled(_:))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var isChecked: Bool {
        get { state == .on }
        set { state = newValue ? .on : .off; isMixed = false; needsDisplay = true }
    }

    /// A multi-selection where some items have it and some do not; a click turns it on for all.
    var isMixed = false { didSet { needsDisplay = true } }

    @objc private func toggled(_ sender: Any?) {
        if isMixed { state = .on }
        isMixed = false
        needsDisplay = true
        onToggle?(isChecked)
    }

    private var labelFont: NSFont { Typeface.ui(13) }

    func fit() -> CGFloat { 14 + 8 + textWidth(title, font: labelFont) + 2 }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        let box = NSRect(x: 0, y: (bounds.height - 14) / 2, width: 14, height: 14)
        // Greyed when it cannot change (Choose details' Name).
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.5) }
        CheckBox.draw(in: box, on: isChecked && !isMixed, mixed: isMixed, p)
        drawLine(title, font: labelFont, color: isChecked || isMixed ? p.text : p.text2, x: 22, midY: bounds.midY,
                 maxWidth: bounds.width - 22)
    }
}

/// The check box drawing shared by OSCheck, the list's item check boxes and the header box.
@MainActor
enum CheckBox {
    static func draw(in box: NSRect, on: Bool, mixed: Bool, _ p: Palette) {
        if on || mixed {
            fillRounded(box, radius: 4, p.accent)
            let path = NSBezierPath()
            if mixed {
                path.move(to: NSPoint(x: box.minX + 3.5, y: box.midY))
                path.line(to: NSPoint(x: box.maxX - 3.5, y: box.midY))
            } else {
                // The tick, in the box's own flipped space.
                path.move(to: NSPoint(x: box.minX + 3.2, y: box.midY + 0.2))
                path.line(to: NSPoint(x: box.minX + 5.9, y: box.midY + 2.8))
                path.line(to: NSPoint(x: box.maxX - 3, y: box.midY - 2.8))
            }
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            p.onAccent.ns.setStroke()
            path.stroke()
        } else {
            fillRounded(box, radius: 4, p.s1)
            strokeRounded(box, radius: 4, p.outline, width: 1.25)
        }
    }
}
