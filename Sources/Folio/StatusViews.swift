import AppKit
import FolioCore

/// The 32 pt status bar (`.status`): a breathing light and "N items, K selected" on the left,
/// a separator, and the ticker on the right.
final class StatusBarView: NSView {
    var countText = "" {
        didSet {
            guard countText != oldValue else { return }
            needsDisplay = true
            needsLayout = true
            setAccessibilityValue(countText)
        }
    }
    let ticker = TickerView(frame: .zero)
    private let light = LedView(diameter: 7)

    override init(frame: NSRect) {
        super.init(frame: frame)
        light.breathing = true
        addSubview(light)
        addSubview(ticker)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Status bar")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private var countFont: NSFont { Typeface.ui(12, weight: 500) }

    /// Left block: padding 12, light 7, gap 9, the count; then gap 12, a 1 pt rule, gap 12.
    private var tickerX: CGFloat { 12 + 7 + 9 + textWidth(countText, font: countFont) + 12 + 1 + 12 }

    override func layout() {
        super.layout()
        light.place(dotAt: NSPoint(x: 12, y: ((bounds.height + 1) / 2 - 3.5).rounded()))
        ticker.frame = NSRect(x: tickerX, y: (bounds.height + 1 - 20) / 2, width: max(0, bounds.width - tickerX - 12), height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.bg)
        fillRect(NSRect(x: 0, y: 0, width: bounds.width, height: 1), p.line)
        let mid = (bounds.height + 1) / 2
        let w = drawLine(countText, font: countFont, color: p.txt, x: 12 + 7 + 9, midY: mid)
        fillRect(NSRect(x: 12 + 7 + 9 + w + 12, y: mid - 7, width: 1, height: 14), p.line2)
    }
}

/// The ticker (`.ticker`): free space, selection, sort and path scrolling left in a loop at 36 pt/s,
/// faded at both ends, paused while the mouse is over it. Still under Reduce motion.
final class TickerView: NSView, ThemeAware {
    var items: [TickerItem] = [] { didSet { if items != oldValue { rebuild() } } }
    private let track = TickerTrackView(frame: .zero)
    private let fade = CAGradientLayer()
    private var halfWidth: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(track)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.mask = fade
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func themeDidChange() { track.needsDisplay = true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        let edge = bounds.width > 0 ? NSNumber(value: Double(24 / bounds.width)) : 0
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, edge, NSNumber(value: 1 - edge.doubleValue), 1]
        CATransaction.commit()
        rebuild()
    }

    private func rebuild() {
        let one = track.measure(items)
        guard one > 0, bounds.width > 0 else { return }
        let reps = max(1, Int((bounds.width / one).rounded(.up)))
        track.items = Array(repeating: items, count: reps * 2).flatMap { $0 }
        let newHalf = one * CGFloat(reps)
        track.frame = NSRect(x: 0, y: 0, width: newHalf * 2, height: bounds.height)
        track.needsDisplay = true
        if newHalf != halfWidth || track.layer?.animation(forKey: "tick") == nil {
            halfWidth = newHalf
            startAnimation()
        }
    }

    private func startAnimation() {
        guard let layer = track.layer else { return }
        layer.removeAnimation(forKey: "tick")
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, halfWidth > 0 else { return }
        let a = CABasicAnimation(keyPath: "transform.translation.x")
        a.fromValue = 0
        a.toValue = -halfWidth
        a.duration = max(20, Double(halfWidth) / 36)
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(a, forKey: "tick")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        guard let layer = track.layer, layer.speed != 0 else { return }
        let paused = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = paused
    }

    override func mouseExited(with event: NSEvent) {
        guard let layer = track.layer, layer.speed == 0 else { return }
        let paused = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
    }

    var isPaused: Bool { track.layer?.speed == 0 }
}

/// The ticker's content: each item is an accent diamond, gap 8, mono text with bright runs, then 18 pt.
final class TickerTrackView: NSView {
    var items: [TickerItem] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private var plain: NSFont { Typeface.mono(12) }
    private var strong: NSFont { Typeface.mono(12, weight: 500) }

    private func string(_ item: TickerItem, _ p: Palette) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for seg in item.segments {
            out.append(NSAttributedString(string: seg.text, attributes: [
                .font: seg.strong ? strong : plain,
                .foregroundColor: (seg.strong ? p.txt : p.txt2).ns,
            ]))
        }
        return out
    }

    func measure(_ items: [TickerItem]) -> CGFloat {
        let p = Palette.current
        return items.reduce(0) { $0 + 7 + 8 + ceil(string($1, p).size().width) + 18 }
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        let mid = bounds.midY
        var x: CGFloat = 0
        for item in items {
            let s = string(item, p)
            let w = ceil(s.size().width)
            let itemW = 7 + 8 + w + 18
            if x + itemW >= dirtyRect.minX && x <= dirtyRect.maxX {
                // A 5 pt square turned 45 degrees.
                let d = NSBezierPath()
                let cx = x + 3.5
                d.move(to: NSPoint(x: cx, y: mid - 3.5))
                d.line(to: NSPoint(x: cx + 3.5, y: mid))
                d.line(to: NSPoint(x: cx, y: mid + 3.5))
                d.line(to: NSPoint(x: cx - 3.5, y: mid))
                d.close()
                p.accent.withAlpha(0.7).ns.setFill()
                d.fill()
                drawAttributed(s, x: x + 15, midY: mid, width: w, font: plain)
            }
            x += itemW
        }
    }
}

/// The right-edge tick strip (`.rail`): one tick per row (longer every fifth), selected rows lit in
/// the accent, and a bracketed window marking the visible range. Clicking jumps there.
final class TickStripView: NSView {
    var onJump: ((Double) -> Void)?
    var rowCount = 0 { didSet { if rowCount != oldValue { needsDisplay = true } } }
    var selected = IndexSet() { didSet { if selected != oldValue { needsDisplay = true } } }
    /// Visible range as fractions of the whole list: top and height, 0...1.
    var visibleRange: (top: Double, height: Double) = (0, 1) {
        didSet { if visibleRange != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    private var inner: NSRect { NSRect(x: 0, y: 14, width: bounds.width, height: max(0, bounds.height - 28)) }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.bg)
        fillRect(NSRect(x: 0, y: 0, width: 1, height: bounds.height), p.line)
        let r = inner
        guard rowCount > 0, r.height > 0 else { return }
        let right = bounds.width - 6
        let n = Double(rowCount)
        func y(_ i: Int) -> CGFloat { r.minY + CGFloat((Double(i) + 0.5) / n) * r.height }
        // Never closer than 3 pt: large folders sample rows.
        let step = max(1, Int((n * 3 / Double(r.height)).rounded(.up)))
        var i = 0
        while i < rowCount {
            let major = (i / step) % 5 == 0
            let w: CGFloat = major ? 13 : 8
            fillRect(NSRect(x: right - w, y: y(i).rounded(), width: w, height: 1), p.line3)
            i += step
        }
        var lastY: CGFloat = -10
        let ctx = NSGraphicsContext.current?.cgContext
        for range in selected.rangeView {
            for row in range where row < rowCount {
                let ty = y(row).rounded()
                if ty - lastY < 1 { continue }
                lastY = ty
                ctx?.saveGState()
                if p.glows { ctx?.setShadow(offset: .zero, blur: 9, color: p.accent.cg) }
                fillRect(NSRect(x: right - 18, y: ty - 0.5, width: 18, height: 2), p.accent)
                ctx?.restoreGState()
            }
        }
        let top = r.minY + CGFloat(visibleRange.top) * r.height
        let h = max(6, CGFloat(min(1, visibleRange.height)) * r.height)
        drawBrackets(NSRect(x: 3, y: top, width: bounds.width - 6, height: min(h, r.maxY - top)), color: p.txt3.ns, length: 5)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let r = inner
        guard r.height > 0 else { return }
        onJump?(min(1, max(0, Double((point.y - r.minY) / r.height))))
    }
}
