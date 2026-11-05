import AppKit
import FolioCore

/// The 30 pt HUD strip under the toolbar (`.hud`): Path depth (with a breathing light), Items,
/// Folders, Files, Sort, View, and Selected pinned right. Dark in both themes.
final class HudView: NSView, ThemeAware {
    var segments: [HudSegment] = [] { didSet { if segments != oldValue { needsLayout = true; needsDisplay = true } } }
    private let light = LedView(diameter: 7)

    override init(frame: NSRect) {
        super.init(frame: frame)
        light.tone = { $0.hudAccent }
        light.breathing = true
        addSubview(light)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Folder readouts")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func themeDidChange() {}

    private var keyFont: NSFont { Typeface.ui(12, weight: 600, width: 116) }
    private var valueFont: NSFont { Typeface.mono(12, weight: 500) }

    override func layout() {
        super.layout()
        let mid = (bounds.height - 1) / 2
        light.isLit = segments.first?.hasLight ?? false
        light.place(dotAt: NSPoint(x: 14, y: (mid - 3.5).rounded()))
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.hudBg)
        let band = bounds.height - 1
        // 4 pt of hairline ticks every 8 pt along the bottom edge.
        var tx: CGFloat = 0
        while tx < bounds.width {
            fillRect(NSRect(x: tx, y: band - 4, width: 1, height: 4), p.hudLine)
            tx += 8
        }
        fillRect(NSRect(x: 0, y: band, width: bounds.width, height: 1), p.line)

        let mid = band / 2
        var x: CGFloat = 0
        let lead = segments.filter { !$0.trailing }
        for seg in lead {
            var cx = x + 14
            if seg.hasLight { cx += 7 + 8 }
            let kw = drawLine(seg.key, font: keyFont, color: p.hudTxt2, x: cx, midY: mid)
            let vw = drawLine(seg.value, font: valueFont, color: p.hudAccent, x: cx + kw + 8, midY: mid)
            x = cx + kw + 8 + vw + 14
            fillRect(NSRect(x: x, y: 0, width: 1, height: band), p.hudLine)
            x += 1
        }
        if let tail = segments.first(where: \.trailing) {
            let kw = textWidth(tail.key, font: keyFont)
            let room = bounds.width - x - 28 - kw - 8 - 1
            guard room > 24 else { return }
            let vw = min(textWidth(tail.value, font: valueFont), room)
            let left = bounds.width - 14 - vw - 8 - kw - 14 - 1
            fillRect(NSRect(x: left, y: 0, width: 1, height: band), p.hudLine)
            drawLine(tail.key, font: keyFont, color: p.hudTxt2, x: left + 1 + 14, midY: mid)
            drawLine(tail.value, font: valueFont, color: p.hudAccent, x: left + 1 + 14 + kw + 8, midY: mid, maxWidth: vw)
        }
    }
}
