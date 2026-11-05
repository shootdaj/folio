import AppKit
import FolioCore

/// The 248 pt sidebar (`.side`) on a blueprint grid tinted with the accent: Quick access and This PC.
/// The grid stays put while the groups scroll, as in D1.
final class SidebarView: NSView {
    let content = SidebarContentView(frame: .zero)
    private let scroll = NSScrollView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = content
        addSubview(scroll)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Navigation")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        scroll.frame = NSRect(x: 0, y: 0, width: bounds.width - 1, height: bounds.height)
        content.frame = NSRect(x: 0, y: 0, width: bounds.width - 1, height: max(content.fittingHeight, bounds.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.bg)
        // 16 pt minor and 64 pt major lines, offset by -1 like `background-position:-1px -1px`.
        for (step, color) in [(CGFloat(16), p.gridMinor), (CGFloat(64), p.gridMajor)] {
            var x = step - 1
            while x < bounds.width { fillRect(NSRect(x: x, y: 0, width: 1, height: bounds.height), color); x += step }
            var y = step - 1
            while y < bounds.height { fillRect(NSRect(x: 0, y: y, width: bounds.width, height: 1), color); y += step }
        }
        fillRect(NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height), p.line)
    }
}

/// The groups themselves. Every row is drawn here; clicks navigate.
final class SidebarContentView: NSView {
    var onNavigate: ((URL) -> Void)?

    var places: [QuickAccessPlace] = [] { didSet { needsLayout = true; needsDisplay = true } }
    var volumes: [VolumeCapacity] = [] { didSet { needsLayout = true; needsDisplay = true } }
    var currentPath = "" { didSet { if currentPath != oldValue { needsLayout = true; needsDisplay = true } } }

    private var hovered: Int?
    private let light = LedView(diameter: 6)
    /// The row F6 or Tab lands on; Up and Down move it, Return opens it.
    private var focusRow = 0
    private var takingFocus = false

    private struct Row { let rect: NSRect; let path: String; let kind: Kind }
    private enum Kind { case place(QuickAccessPlace), volume(VolumeCapacity) }
    private struct Group { let rect: NSRect; let title: String; let glyph: Glyph; let count: Int }

    private static let pad: CGFloat = 10
    private static let header: CGFloat = 36
    private static let itemH: CGFloat = 30
    private static let volumeH: CGFloat = 77.75

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(light)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var fittingHeight: CGFloat {
        let (groups, _) = geometry()
        return (groups.last?.rect.maxY ?? 0) + 12
    }

    private func geometry() -> ([Group], [Row]) {
        let x = Self.pad, w = bounds.width - 2 * Self.pad
        var groups: [Group] = [], rows: [Row] = []
        var y: CGFloat = 12
        let qaH = 1 + Self.header + CGFloat(places.count) * Self.itemH + 6 + 1
        groups.append(Group(rect: NSRect(x: x, y: y, width: w, height: qaH), title: "Quick access", glyph: .star, count: places.count))
        var ry = y + 1 + Self.header
        for place in places {
            rows.append(Row(rect: NSRect(x: x + 5, y: ry, width: w - 10, height: Self.itemH), path: place.path, kind: .place(place)))
            ry += Self.itemH
        }
        y += qaH + 12
        let pcH = 1 + Self.header + CGFloat(volumes.count) * Self.volumeH + 6 + 1
        groups.append(Group(rect: NSRect(x: x, y: y, width: w, height: pcH), title: "This PC", glyph: .pc, count: volumes.count))
        ry = y + 1 + Self.header
        for volume in volumes {
            rows.append(Row(rect: NSRect(x: x + 5, y: ry, width: w - 10, height: Self.volumeH), path: volume.path, kind: .volume(volume)))
            ry += Self.volumeH
        }
        return (groups, rows)
    }

    override func layout() {
        super.layout()
        let (_, rows) = geometry()
        if let on = rows.first(where: { if case .place = $0.kind { $0.path == currentPath } else { false } }) {
            light.isLit = true
            light.place(dotAt: NSPoint(x: on.rect.minX + 8, y: (on.rect.midY - 3).rounded()))
        } else {
            light.isLit = false
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        let (groups, rows) = geometry()
        for group in groups {
            fillRounded(group.rect, radius: 4, p.bg.withAlpha(0.86))
            strokeRounded(group.rect, radius: 4, p.line)
            drawBrackets(group.rect.insetBy(dx: -1, dy: -1), color: p.accent.withAlpha(0.55).ns, length: 8)
            let mid = group.rect.minY + 1 + Self.header / 2
            group.glyph.draw(in: NSRect(x: group.rect.minX + 11, y: mid - 8, width: 16, height: 16), color: p.txt2.ns)
            let tw = drawLine(group.title, font: Typeface.ui(12, weight: 700, width: 124), color: p.txt,
                              x: group.rect.minX + 35, midY: mid, kern: 0.48)
            drawLine("\(group.count)", font: Typeface.mono(12), color: p.txt3, x: group.rect.minX + 35 + tw + 8, midY: mid)
            Glyph.chevronDown.draw(in: NSRect(x: group.rect.maxX - 11 - 16, y: mid - 8, width: 16, height: 16), color: p.txt2.ns)
        }
        for (i, row) in rows.enumerated() {
            let on = row.path == currentPath
            if on, case .place = row.kind {
                fillRounded(row.rect, radius: 3, p.selectionFill)
            } else if hovered == i {
                fillRounded(row.rect, radius: 3, p.txt.withAlpha(0.08))
            }
            switch row.kind {
            case .place(let place): drawPlace(place, in: row.rect, on: on, p)
            case .volume(let volume): drawVolume(volume, in: row.rect, p)
            }
            // D1's `:focus-visible`: a 2 pt accent outline, drawn inside the row.
            if i == focusRow, window?.firstResponder === self {
                strokeRounded(row.rect.insetBy(dx: 1, dy: 1), radius: 3, p.accent, width: 2)
            }
        }
    }

    private func drawPlace(_ place: QuickAccessPlace, in r: NSRect, on: Bool, _ p: Palette) {
        let mid = r.midY
        let iconX = r.minX + 8 + 6 + 10
        let glyph: Glyph? = switch place.title {
        case "Downloads": .download
        case "Desktop": .desktop
        case "Documents": .docs
        case "Pictures": .pics
        case "Movies": .movies
        default: nil
        }
        let textX: CGFloat
        if let glyph {
            glyph.draw(in: NSRect(x: iconX, y: mid - 8, width: 16, height: 16), color: (on ? p.accent : p.txt2).ns)
            textX = iconX + 16 + 10
        } else {
            ItemIcon.drawFolder(in: NSRect(x: iconX, y: mid - 7.5, width: 18, height: 15), palette: p, lit: on)
            textX = iconX + 18 + 10
        }
        let font = Typeface.ui(13)
        let room = r.maxX - 8 - textX
        let pw = place.prefix.isEmpty ? 0 : drawLine(place.prefix, font: font, color: p.txt3, x: textX, midY: mid, maxWidth: room)
        drawLine(place.title, font: font, color: on ? p.accent : p.txt, x: textX + pw, midY: mid, maxWidth: room - pw)
    }

    private func drawVolume(_ v: VolumeCapacity, in r: NSRect, _ p: Palette) {
        let topMid = r.minY + 8 + 8.8
        Glyph.drive.draw(in: NSRect(x: r.minX + 8, y: topMid - 8, width: 16, height: 16), color: p.txt2.ns)
        let pctW = drawLine(v.percentText, font: Typeface.mono(12), color: p.accent, x: r.maxX - 8, midY: topMid, alignRight: true)
        drawLine(v.name, font: Typeface.ui(13, weight: 600), color: p.txt, x: r.minX + 34, midY: topMid,
                 maxWidth: r.width - 34 - 8 - pctW - 8)
        // 24 segments, gap 2, the used share lit in the accent.
        let barY = r.minY + 8 + 17.55 + 9
        let barW = r.width - 16
        let segW = (barW - 23 * 2) / 24
        let lit = v.litSegments()
        for i in 0..<24 {
            let seg = NSRect(x: r.minX + 8 + CGFloat(i) * (segW + 2), y: barY, width: segW, height: 10)
            if i < lit {
                if p.glows, let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: 9, color: p.accent.withAlpha(0.5).cg)
                    fillRounded(seg, radius: 1, p.accent)
                    ctx.restoreGState()
                } else {
                    fillRounded(seg, radius: 1, p.accent)
                }
            } else {
                fillRounded(seg, radius: 1, p.line2)
            }
        }
        let subMid = barY + 10 + 7 + 8.1
        drawLine(v.freeText, font: Typeface.mono(12), color: p.txt2, x: r.minX + 8, midY: subMid)
        drawLine(v.totalText, font: Typeface.mono(12), color: p.txt2, x: r.maxX - 8, midY: subMid, alignRight: true)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func rowIndex(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return geometry().1.firstIndex { $0.rect.contains(point) }
    }

    override func mouseMoved(with event: NSEvent) {
        let i = rowIndex(at: event)
        if i != hovered { hovered = i; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard let i = rowIndex(at: event) else { return }
        focusRow = i
        onNavigate?(URL(fileURLWithPath: geometry().1[i].path, isDirectory: true))
    }

    // MARK: Keyboard focus (F6, Tab): until milestone 5's tree, the sidebar's rows are the tree.

    /// Only F6 and Tab focus the sidebar; a click navigates and leaves focus where it was.
    override var acceptsFirstResponder: Bool { takingFocus }

    func takeKeyboardFocus() {
        let rows = geometry().1
        focusRow = rows.firstIndex { $0.path == currentPath } ?? min(focusRow, max(0, rows.count - 1))
        takingFocus = true
        window?.makeFirstResponder(self)
        takingFocus = false
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    override func keyDown(with event: NSEvent) {
        let rows = geometry().1
        guard !rows.isEmpty else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 125: focusRow = min(rows.count - 1, focusRow + 1)                 // Down
        case 126: focusRow = max(0, focusRow - 1)                              // Up
        case 115: focusRow = 0                                                 // Home
        case 119: focusRow = rows.count - 1                                    // End
        case 36, 76, 49:                                                       // Return, Enter, Space
            onNavigate?(URL(fileURLWithPath: rows[min(focusRow, rows.count - 1)].path, isDirectory: true))
        default: return super.keyDown(with: event)
        }
        needsDisplay = true
        scrollToVisible(rows[min(focusRow, rows.count - 1)].rect.insetBy(dx: 0, dy: -8))
    }
}
