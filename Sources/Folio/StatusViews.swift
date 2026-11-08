import AppKit
import FolioCore

/// An SF Symbol tinted `color`, drawn in `rect` (Native's glyphs: the view toggle, the pane's close mark).
/// A missing symbol draws nothing.
@MainActor
func drawPaneSymbol(_ name: String, in rect: NSRect, color: NSColor, pointSize: CGFloat, weight: NSFont.Weight = .regular) {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
    let size = base.size
    let tinted = NSImage(size: size, flipped: false) { r in
        base.draw(in: r)
        color.set()
        r.fill(using: .sourceAtop)
        return true
    }
    let scale = min(rect.width / max(1, size.width), rect.height / max(1, size.height), 1)
    let w = size.width * scale, h = size.height * scale
    tinted.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h), from: .zero,
                operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

/// D4's 28 pt status bar (`.status`): on the left a light (green, or the accent pulsing while a search
/// gathers), "28 items, 1 selected" with the numbers in mono, and the selected name; on the right the
/// sort, the volume's free space and the view toggle (Details or Large icons, as Explorer's two status
/// bar buttons). The HUD's readouts moved here. Its accessibility value stays the count line.
final class StatusBarView: NSView {
    /// The left text when there is no readout (a message, Home, Loading) and the accessibility value.
    var countText = "" {
        didSet {
            guard countText != oldValue else { return }
            needsDisplay = true
            needsLayout = true
            setAccessibilityValue(countText)
        }
    }
    /// What the list shows; nil leaves the left to `countText` and the right empty but for the view.
    var readout: StatusReadout? {
        didSet {
            guard readout != oldValue else { return }
            light.pulsing = readout?.busy ?? false
            light.tone = { [weak self] p in self?.readout?.busy == true ? p.accent : p.ok }
            viewToggle.text = readout?.view ?? viewToggle.text
            viewToggle.isHidden = readout == nil
            needsDisplay = true
            needsLayout = true
        }
    }
    /// The view toggle at the right end was pressed.
    var onToggleView: (() -> Void)? { didSet { viewToggle.onPress = onToggleView } }
    let viewToggle = StatusViewToggle()
    /// Explorer's one-line "Copying 3 items" while a job runs; clicking it brings the progress window back.
    let chip = StatusChip()
    var chipText: String? {
        didSet {
            guard chipText != oldValue else { return }
            chip.text = chipText ?? ""
            chip.isHidden = chipText == nil
            needsLayout = true
            needsDisplay = true
        }
    }
    private let light = LedView(diameter: 6)

    override init(frame: NSRect) {
        super.init(frame: frame)
        light.tone = { $0.ok }
        addSubview(light)
        chip.isHidden = true
        addSubview(chip)
        viewToggle.isHidden = true
        addSubview(viewToggle)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Status bar")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Native is Finder's thin bar: 11 pt grey text, no light and no rules between the parts.
    private var native: Bool { ThemeController.shared.look == .native }

    private var wordFont: NSFont { native ? Typeface.ui(11) : Typeface.ui(12, weight: 500) }
    private var numberFont: NSFont { native ? Typeface.mono(11) : Typeface.mono(12, weight: 500) }

    /// "28 items, 1 selected": the digit runs in Geist Mono in the text colour, the words in muted Geist.
    private func countString(_ text: String, _ p: ThemeColors) -> NSAttributedString {
        if native { return NSAttributedString(string: text, attributes: [.font: wordFont, .foregroundColor: NSColor.secondaryLabelColor]) }
        let out = NSMutableAttributedString()
        var run = "", runIsNumber = false
        func flush() {
            guard !run.isEmpty else { return }
            out.append(NSAttributedString(string: run, attributes: [
                .font: runIsNumber ? numberFont : wordFont, .foregroundColor: (runIsNumber ? p.text : p.muted).ns]))
            run = ""
        }
        for ch in text {
            let isNumber = ch.isNumber || (ch == "," && runIsNumber && !run.isEmpty)
            if isNumber != runIsNumber && !run.isEmpty { flush() }
            runIsNumber = isNumber
            run.append(ch)
        }
        flush()
        return out
    }

    private var leftText: String { readout?.count ?? countText }

    /// Left block: padding 6 + 10, the 6 pt light, gap 6, the count; then the selected name in its own
    /// segment and the job chip.
    private var countEnd: CGFloat {
        if native { return 12 + ceil(countString(leftText, ThemeColors.current).size().width) + 12 }
        return 16 + 6 + 6 + ceil(countString(leftText, ThemeColors.current).size().width) + 10
    }

    private struct Segment { var x: CGFloat; var width: CGFloat }

    /// The right-hand segments, right to left: view toggle, volume, sort (each 10 pt padded, a hairline before).
    private func rightSegments(_ p: ThemeColors) -> (sort: Segment?, volume: Segment?, view: Segment?) {
        guard let r = readout else { return (nil, nil, nil) }
        if native {
            // No icons and no rules: the sort, the volume and the toggle are plain text.
            var x = bounds.width - 6
            let viewW = viewToggle.fit()
            x -= viewW
            let view = Segment(x: x, width: viewW)
            var volume: Segment?
            if let text = r.volumeText {
                let w = textWidth(text, font: wordFont) + 16
                x -= w
                volume = Segment(x: x, width: w)
            }
            let sw = textWidth(r.sort, font: wordFont) + 16
            let sort = x - sw > countEnd + 40 ? Segment(x: x - sw, width: sw) : nil
            return (sort, volume, view)
        }
        var x = bounds.width - 6
        let viewW = viewToggle.fit()
        x -= viewW
        let view = Segment(x: x, width: viewW)
        var volume: Segment?
        if let text = r.volumeText {
            let w = 10 + 14 + 6 + textWidth(text, font: wordFont) + 10
            x -= w
            volume = Segment(x: x, width: w)
        }
        let sw = 10 + textWidth(r.sort, font: wordFont) + 10
        let sort = x - sw > countEnd + 40 ? Segment(x: x - sw, width: sw) : nil
        return (sort, volume, view)
    }

    override func layout() {
        super.layout()
        if native {
            light.isHidden = true
            let segs = rightSegments(ThemeColors.current)
            if let v = segs.view { viewToggle.frame = NSRect(x: v.x, y: 1, width: v.width, height: max(0, bounds.height - 1)) }
            var x = countEnd
            if let sel = readout?.selected { x += textWidth(sel, font: wordFont) + 16 }
            let h = min(18, max(0, bounds.height - 2))
            chip.frame = NSRect(x: x, y: 1 + (bounds.height - 1 - h) / 2, width: chip.fit(), height: h)
            return
        }
        light.place(dotAt: NSPoint(x: 16, y: ((bounds.height + 1) / 2 - 3).rounded()))
        let segs = rightSegments(ThemeColors.current)
        if let v = segs.view { viewToggle.frame = NSRect(x: v.x, y: 1, width: v.width, height: bounds.height - 1) }
        var x = countEnd
        if let sel = readout?.selected { x += 10 + textWidth(sel, font: wordFont) + 10 }
        chip.frame = NSRect(x: x + 8, y: (bounds.height + 1 - 20) / 2, width: chip.fit(), height: 20)
    }

    /// Native: the window's background, a 1 pt separator on top, then the count, the selected name and
    /// the sort and volume on the right, all in secondary label colour.
    private func drawNative() {
        let p = ThemeColors.current
        fillRect(bounds, NSColor.windowBackgroundColor)
        fillRect(NSRect(x: 0, y: 0, width: bounds.width, height: 1), NSColor.separatorColor)
        let mid = (bounds.height + 1) / 2
        let segs = rightSegments(p)
        let limit = (segs.sort?.x ?? segs.volume?.x ?? segs.view?.x ?? bounds.width) - 8
        let count = countString(leftText, p)
        drawAttributed(count, x: 12, midY: mid, width: min(ceil(count.size().width), max(0, limit - 12)), font: wordFont)
        if let sel = readout?.selected, countEnd < limit - 20 {
            drawLine(sel, font: wordFont, color: NSColor.secondaryLabelColor, x: countEnd, midY: mid, maxWidth: limit - countEnd - 8)
        }
        guard let r = readout else { return }
        if let s = segs.sort { drawLine(r.sort, font: wordFont, color: NSColor.secondaryLabelColor, x: s.x + 8, midY: mid) }
        if let v = segs.volume, let text = r.volumeText {
            drawLine(text, font: wordFont, color: NSColor.secondaryLabelColor, x: v.x + 8, midY: mid)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if native { drawNative(); return }
        let p = ThemeColors.current
        fillRect(bounds, p.chrome)
        fillRect(NSRect(x: 0, y: 0, width: bounds.width, height: 1), p.line)
        let mid = (bounds.height + 1) / 2
        let segs = rightSegments(p)
        let limit = (segs.sort?.x ?? segs.volume?.x ?? segs.view?.x ?? bounds.width) - 10
        let count = countString(leftText, p)
        drawAttributed(count, x: 28, midY: mid, width: min(ceil(count.size().width), max(0, limit - 28)), font: wordFont)
        var x = countEnd
        if let sel = readout?.selected, x < limit - 20 {
            fillRect(NSRect(x: x, y: 1, width: 1, height: bounds.height - 1), p.line)
            drawLine(sel, font: wordFont, color: p.text2, x: x + 10, midY: mid, maxWidth: limit - x - 20)
            x += 10 + textWidth(sel, font: wordFont) + 10
        }
        guard let r = readout else { return }
        if let s = segs.sort {
            fillRect(NSRect(x: s.x, y: 1, width: 1, height: bounds.height - 1), p.line)
            drawLine(r.sort, font: wordFont, color: p.muted, x: s.x + 10, midY: mid)
        }
        if let v = segs.volume, let name = r.volumeName, let free = r.volumeFree {
            fillRect(NSRect(x: v.x, y: 1, width: 1, height: bounds.height - 1), p.line)
            Glyph.drive.draw(in: NSRect(x: v.x + 10, y: mid - 7, width: 14, height: 14), color: p.muted.ns)
            let line = NSMutableAttributedString(string: name + ", ", attributes: [.font: wordFont, .foregroundColor: p.muted.ns])
            line.append(NSAttributedString(string: free, attributes: [.font: numberFont, .foregroundColor: p.text.ns]))
            line.append(NSAttributedString(string: " free", attributes: [.font: wordFont, .foregroundColor: p.muted.ns]))
            drawAttributed(line, x: v.x + 30, midY: mid, width: ceil(line.size().width), font: wordFont)
        }
        if let v = segs.view {
            fillRect(NSRect(x: v.x, y: 1, width: 1, height: bounds.height - 1), p.line)
        }
    }
}

/// The view toggle at the status bar's right end (`.sb-view`): a list glyph and the view's name.
/// Pressing it switches between Details and Large icons, as Explorer's status bar buttons do.
final class StatusViewToggle: NSButton {
    var text = "Details" {
        didSet {
            guard text != oldValue else { return }
            setAccessibilityLabel("View: " + text)
            needsDisplay = true
        }
    }
    var onPress: (() -> Void)?
    private var hovered = false

    init() {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        target = self
        action = #selector(pressed(_:))
        toolTip = "Switch between Details and Large icons"
        setAccessibilityLabel("View: Details")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    @objc private func pressed(_ sender: Any?) { onPress?() }

    private var labelFont: NSFont { Typeface.ui(12, weight: 500) }
    private var native: Bool { ThemeController.shared.look == .native }

    func fit() -> CGFloat { native ? 30 : 10 + 14 + 6 + textWidth(text, font: labelFont) + 10 }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if native {
            // A symbol for the current view, with no hover pill.
            let tone = hovered || isHighlighted ? NSColor.labelColor : NSColor.secondaryLabelColor
            drawPaneSymbol(text == "Details" ? "list.bullet" : "square.grid.2x2", in: bounds.insetBy(dx: 8, dy: 3), color: tone,
                           pointSize: 11, weight: .medium)
            return
        }
        let p = ThemeColors.current
        let tone = hovered ? p.text : p.muted
        if hovered || isHighlighted { fillRounded(bounds.insetBy(dx: 2, dy: 3), radius: 5, p.text.withAlpha(isHighlighted ? 0.12 : 0.06)) }
        let mid = bounds.midY
        Glyph.view.draw(in: NSRect(x: 10, y: mid - 7, width: 14, height: 14), color: tone.ns)
        drawLine(text, font: labelFont, color: tone, x: 30, midY: mid)
    }
}

/// The status bar's job chip: a pulsing light and "Copying 3 items, 42%" in mono on the accent's soft fill.
final class StatusChip: NSButton {
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            title = text
            setAccessibilityLabel(text)
            needsDisplay = true
        }
    }
    var onPress: (() -> Void)?
    private let light = LedView(diameter: 7)
    private let spinner = NSProgressIndicator()
    private var hovered = false
    private var native: Bool { ThemeController.shared.look == .native }

    init() {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        target = self
        action = #selector(pressed(_:))
        if ThemeController.shared.look == .native {
            // Native: a small spinner and plain text.
            spinner.style = .spinning
            spinner.controlSize = .mini
            spinner.isIndeterminate = true
            spinner.startAnimation(nil)
            addSubview(spinner)
        } else {
            light.pulsing = true
            addSubview(light)
        }
        toolTip = "Show the progress window"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    @objc private func pressed(_ sender: Any?) { onPress?() }

    private var labelFont: NSFont { Typeface.mono(12, weight: 500) }

    func fit() -> CGFloat {
        if native { return 6 + 12 + 6 + textWidth(text, font: nativeFont) + 6 }
        return 8 + 7 + 8 + textWidth(text, font: labelFont) + 8
    }

    private var nativeFont: NSFont { Typeface.ui(11) }

    override func layout() {
        super.layout()
        if native {
            spinner.frame = NSRect(x: 6, y: ((bounds.height - 12) / 2).rounded(), width: 12, height: 12)
            return
        }
        light.place(dotAt: NSPoint(x: 8, y: (bounds.height / 2 - 3.5).rounded()))
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
        if native {
            drawLine(text, font: nativeFont, color: hovered ? NSColor.labelColor : NSColor.secondaryLabelColor,
                     x: 6 + 12 + 6, midY: bounds.midY)
            return
        }
        let p = ThemeColors.current
        fillRounded(bounds, radius: 10, hovered ? p.accent.withAlpha(0.24) : p.accentSoft)
        drawLine(text, font: labelFont, color: p.text, x: 8 + 7 + 8, midY: bounds.midY)
    }
}
