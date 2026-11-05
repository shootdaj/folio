import AppKit
import FolioCore

/// D1 list metrics. `--row-h` in the design is 24 px.
enum ListMetrics {
    static let rowHeight: CGFloat = 24
    static let headerHeight: CGFloat = 32
    /// The list's 4 px top padding (`.list{padding:4px 0}`), drawn as part of the header strip.
    static let listTopPad: CGFloat = 4
    static let columnGap: CGFloat = 14
    /// Grid padding-left is 10 px; NSTableView already insets cells by half the column gap.
    static let rowLead: CGFloat = 10 - columnGap / 2
}

/// The table, with hover tracking for the 5.5% row wash.
final class FolioTableView: NSTableView {
    private(set) var hoveredRow = -1

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setHovered(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(-1)
    }

    private func setHovered(_ row: Int) {
        guard row != hoveredRow else { return }
        let old = hoveredRow
        hoveredRow = row
        for r in [old, row] where r >= 0 && r < numberOfRows {
            if let view = rowView(atRow: r, makeIfNecessary: false) as? FolioRowView {
                view.isHovered = r == row
            }
        }
    }
}

/// The column header (`.lh`): s2 strip, wide Archivo labels, the sorted column in the accent with a
/// glowing underline and arrow. Clicks, resizing and reordering stay NSTableHeaderView's own.
final class FolioHeaderView: NSTableHeaderView {
    var sort = SortSpec.standard { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    private var font: NSFont { Typeface.ui(12, weight: 650, width: 116) }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        guard let table = tableView else { return }
        fillRect(bounds, p.s1)
        fillRect(NSRect(x: 0, y: 0, width: bounds.width, height: ListMetrics.headerHeight), p.s2)
        fillRect(NSRect(x: 0, y: ListMetrics.headerHeight - 1, width: bounds.width, height: 1), p.line)
        for (index, column) in table.tableColumns.enumerated() {
            var rect = headerRect(ofColumn: index)
            if index == draggedColumn { rect.origin.x += draggedDistance }
            rect.size.height = ListMetrics.headerHeight - 1
            guard let key = SortKey(rawValue: column.identifier.rawValue) else { continue }
            drawHeader(column.title, key: key, in: rect, p)
        }
    }

    private func drawHeader(_ title: String, key: SortKey, in rect: NSRect, _ p: Palette) {
        let on = sort.key == key
        let color = on ? p.accent : p.txt2
        let kern: CGFloat = 0.24
        let tw = textWidth(title, font: font, kern: kern)
        let arrow: CGFloat = 14, gap: CGFloat = 6
        let half = ListMetrics.columnGap / 2
        // Name sits 16 px in from the grid edge; Size hugs the right, its arrow slot still reserved.
        let x: CGFloat = switch key {
        case .name: rect.minX + ListMetrics.rowLead + half + 16
        case .size: rect.maxX - half - arrow - gap - tw
        default: rect.minX + half
        }
        let mid = rect.midY.rounded()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        drawLine(title, font: font, color: color, x: x, midY: mid, maxWidth: max(0, rect.maxX - x - half), kern: kern)
        if on {
            // 2 px underline 8 px below the label box, with a glow in dark.
            let underline = NSRect(x: x, y: mid + 6 + 8 - 2, width: tw, height: 2)
            if p.glows, let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 9, color: p.accent.withAlpha(0.6).cg)
                fillRect(underline, p.accent)
                ctx.restoreGState()
            } else {
                fillRect(underline, p.accent)
            }
            Glyph.sort.draw(in: NSRect(x: x + tw + gap, y: mid - arrow / 2, width: arrow, height: arrow),
                            color: p.accent.ns, rotation: sort.ascending ? 0 : .pi)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// A row (`.row`): hover wash, and when selected the accent fill inset 3 px with corner brackets.
final class FolioRowView: NSTableRowView {
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            for case let cell as RowCellView in subviews { cell.rowSelectionChanged(isSelected) }
            needsDisplay = true
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if isHovered && !isSelected {
            fillRounded(bounds.insetBy(dx: 3, dy: 0), radius: 3, Palette.current.txt.withAlpha(0.055))
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let p = Palette.current
        let r = bounds.insetBy(dx: 3, dy: 0)
        fillRect(r, p.selectionFill)
        drawBrackets(r, color: p.accent.ns, length: 7)
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        (subview as? RowCellView)?.rowSelectionChanged(isSelected)
    }
}

@MainActor
protocol RowCellView: AnyObject {
    func rowSelectionChanged(_ selected: Bool)
}

/// Name cell: selection light, folder or file icon, name (accent and semibold when selected).
final class NameCellView: NSTableCellView, RowCellView, ThemeAware {
    var entry: FileEntry? { didSet { needsDisplay = true; setAccessibilityLabel(entry?.name) } }
    private var selected = false
    private let light = LedView(diameter: 6)

    override init(frame: NSRect) {
        super.init(frame: frame)
        light.isLit = false
        light.breathing = true
        addSubview(light)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func rowSelectionChanged(_ selected: Bool) {
        guard selected != self.selected else { return }
        self.selected = selected
        light.isLit = selected
        needsDisplay = true
    }

    func themeDidChange() { light.themeDidChange() }

    override func layout() {
        super.layout()
        light.place(dotAt: NSPoint(x: ListMetrics.rowLead, y: (bounds.midY - 3).rounded()))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let entry else { return }
        let p = Palette.current
        let mid = bounds.midY
        let iconX = ListMetrics.rowLead + 6 + 8
        let textX: CGFloat
        if entry.isFolder {
            ItemIcon.drawFolder(in: NSRect(x: iconX, y: mid - 7.5, width: 18, height: 15), palette: p, lit: selected)
            textX = iconX + 18 + 8
        } else {
            ItemIcon.drawFile(named: entry.name, in: NSRect(x: iconX, y: mid - 7.5, width: 15, height: 15), palette: p)
            textX = iconX + 15 + 8
        }
        drawLine(entry.name, font: Typeface.ui(13, weight: selected ? 600 : 400),
                 color: selected ? p.accent : p.txt, x: textX, midY: mid, maxWidth: max(0, bounds.width - textX))
    }
}

/// Date, Type and Size cells: one line of text, mono for dates and sizes, Size right-aligned.
final class TextCellView: NSTableCellView, RowCellView {
    var text = "" { didSet { if text != oldValue { needsDisplay = true; setAccessibilityLabel(text) } } }
    var mono = false
    var alignRight = false

    override var isFlipped: Bool { true }

    func rowSelectionChanged(_ selected: Bool) {}

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        let font = mono ? Typeface.mono(12) : Typeface.ui(13)
        drawLine(text, font: font, color: p.txt2, x: alignRight ? bounds.maxX : 0, midY: bounds.midY,
                 maxWidth: bounds.width, alignRight: alignRight)
    }
}

/// The list pane (`.pane`): s1 panel with a hairline border, radius 4 and accent corner brackets.
final class ListPaneView: NSView {
    let scrollView = NSScrollView()
    private let overlay = BracketOverlay()

    override init(frame: NSRect) {
        super.init(frame: frame)
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        // Name always fits the columns to the list (BrowserWindowController.fitColumns).
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        // Keeps the header's square corners inside the pane's 4 pt radius.
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 3
        scrollView.layer?.masksToBounds = true
        addSubview(scrollView)
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        scrollView.frame = bounds.insetBy(dx: 1, dy: 1)
        overlay.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRounded(bounds, radius: 4, p.s1)
        strokeRounded(bounds, radius: 4, p.line)
    }

    /// Brackets drawn above the scrolling rows; never takes clicks.
    private final class BracketOverlay: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            drawBrackets(bounds, color: Palette.current.bracket.ns, length: 12)
        }
    }
}
