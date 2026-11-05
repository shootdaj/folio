import AppKit
import FolioCore

/// D1's `.btn`: 1 pt line-3 border, radius 5, Archivo 600, an optional 16 pt icon 8 pt before the
/// label, the 8% hover and 14% press state layer. Styles: plain, primary (accent fill), warn (miss
/// outline), ghost (no border, txt2). `isOn` is `aria-pressed` (accent outline on the selection fill).
final class D1Button: NSButton {
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

    private var labelFont: NSFont { Typeface.ui(13, weight: 600) }

    /// Width for the label and icon with D1's 14 pt padding, at least `minimum`.
    func fit(minimum: CGFloat = 0) -> CGFloat {
        max(minimum, 14 + (glyph == nil ? 0 : 16 + 8) + textWidth(title, font: labelFont) + 14)
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
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        var text = p.txt
        let enabled = isEnabled
        switch style {
        case .primary:
            if enabled {
                fillRounded(r, radius: 5, p.accent)
                text = p.onAccent
            } else {
                fillRounded(r, radius: 5, p.line2)
                text = p.txt2
            }
        case .warn:
            strokeRounded(bounds, radius: 5, p.miss)
            text = p.miss
        case .ghost:
            text = p.txt2
        case .plain:
            if isOn {
                fillRounded(r, radius: 5, p.selectionFill)
                strokeRounded(bounds, radius: 5, p.accent)
                text = p.accent
            } else {
                strokeRounded(bounds, radius: 5, p.line3)
            }
        }
        if enabled && (hovered || isHighlighted) {
            fillRounded(r, radius: 5, text.withAlpha(isHighlighted ? 0.14 : 0.08))
        }
        let tone = enabled ? text : text.withAlpha(0.45)
        let tw = textWidth(title, font: labelFont)
        let total = (glyph == nil ? 0 : 16 + 8) + tw
        var x = (bounds.width - total) / 2
        if let glyph {
            glyph.draw(in: NSRect(x: x, y: bounds.midY - 8, width: 16, height: 16), color: tone.ns)
            x += 24
        }
        drawLine(title, font: labelFont, color: tone, x: x, midY: bounds.midY)
    }
}

/// A D1-styled check box: a 14 pt box (line-3 outline, accent fill and an on-accent tick when on) and a
/// mono label. An NSButton of the switch type, so accessibility sees a check box.
final class D1Check: NSButton {
    var onToggle: ((Bool) -> Void)?

    init(_ title: String, onToggle: ((Bool) -> Void)? = nil) {
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        setButtonType(.switch)
        self.title = title
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

    private var labelFont: NSFont { Typeface.mono(12) }

    func fit() -> CGFloat { 14 + 8 + textWidth(title, font: labelFont) + 2 }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        let box = NSRect(x: 0, y: (bounds.height - 14) / 2, width: 14, height: 14)
        CheckBox.draw(in: box, on: isChecked && !isMixed, mixed: isMixed, p)
        drawLine(title, font: labelFont, color: isChecked || isMixed ? p.txt : p.txt2, x: 22, midY: bounds.midY,
                 maxWidth: bounds.width - 22)
    }
}

/// The check box drawing shared by D1Check, the list's item check boxes and the header box.
@MainActor
enum CheckBox {
    static func draw(in box: NSRect, on: Bool, mixed: Bool, _ p: Palette) {
        if on || mixed {
            fillRounded(box, radius: 3, p.accent)
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
            fillRounded(box, radius: 3, p.s1)
            strokeRounded(box, radius: 3, p.line3, width: 1.25)
        }
    }
}
