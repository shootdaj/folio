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

/// What the list asks of its window controller: Explorer's selection rules live there (ListSelection).
@MainActor
protocol FileListDelegate: AnyObject {
    func list(_ list: FolioTableView, clicked row: Int, modifiers: NSEvent.ModifierFlags)
    func list(_ list: FolioTableView, toggledCheckboxOf row: Int)
    func list(_ list: FolioTableView, opened row: Int)
    /// The rubber band now covers `rows` (already combined with the old selection for Cmd+drag).
    func list(_ list: FolioTableView, banded rows: IndexSet, focus: Int?)
    func listToggledAll(_ list: FolioTableView)
    /// Option+double-click: Properties (Explorer's Alt+double-click).
    func list(_ list: FolioTableView, showPropertiesOf row: Int)
    /// The press on a row became a drag of the selection (left or right button).
    func list(_ list: FolioTableView, beginDragWith event: NSEvent, rightButton: Bool)
    /// Right-click: the item menu for `row`, or the background menu for -1.
    func list(_ list: FolioTableView, menuFor row: Int, event: NSEvent) -> NSMenu?
    /// A drag left the list or ended over it.
    func listDragExited(_ list: FolioTableView)
    /// Services: the selected items' file URLs.
    func listSelectedURLs(_ list: FolioTableView) -> [URL]
}

/// The table, with hover tracking for the 5.5% row wash, Explorer clicks (Cmd+click toggles, Shift+click
/// ranges, Cmd+Shift+click adds a range), a rubber band from empty space, and item check boxes.
final class FolioTableView: NSTableView {
    private(set) var hoveredRow = -1
    weak var listDelegate: FileListDelegate?
    /// View > Item check boxes: a box in each Name cell (on hover and on selected rows) and in the header.
    var showsCheckboxes = false {
        didSet {
            guard showsCheckboxes != oldValue else { return }
            enumerateAvailableRowViews { row, _ in row.subviews.forEach { $0.needsDisplay = true } }
            headerView?.needsDisplay = true
        }
    }
    private let band = BandView()

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

    /// The check box of a row, in table coordinates (a little larger than drawn, to be easy to hit).
    func checkboxRect(row: Int) -> NSRect {
        let column = tableColumns.firstIndex { $0.identifier.rawValue == SortKey.name.rawValue } ?? 0
        let cell = frameOfCell(atColumn: column, row: row)
        return NSRect(x: cell.minX + NameCellView.boxX - 4, y: cell.midY - 11, width: 22, height: 22)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let delegate = listDelegate else { return super.mouseDown(with: event) }
        // Control+click is the Mac's right-click.
        if event.modifierFlags.contains(.control), let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        let mods = event.modifierFlags.intersection([.command, .shift])
        guard row >= 0 else {
            rubberBand(from: event, at: point, adding: mods.contains(.command))
            return
        }
        if showsCheckboxes, checkboxRect(row: row).contains(point) {
            delegate.list(self, toggledCheckboxOf: row)
            return
        }
        if event.clickCount >= 2, mods.isEmpty {
            if event.modifierFlags.contains(.option) {
                delegate.list(self, showPropertiesOf: row)
            } else {
                delegate.list(self, opened: row)
            }
            return
        }
        // A plain click on one of several selected rows keeps them all until the mouse comes up
        // without a drag, so a drag takes them all, as in Explorer.
        if mods.isEmpty, selectedRowIndexes.contains(row), selectedRowIndexes.count > 1 {
            if !trackDrag(from: point, button: .left) { delegate.list(self, clicked: row, modifiers: []) }
            return
        }
        delegate.list(self, clicked: row, modifiers: mods)
        // A press on a selected row can become a drag of the selection.
        if selectedRowIndexes.contains(row) { _ = trackDrag(from: point, button: .left) }
    }

    private enum Button { case left, right }

    /// Follows the pressed button: true when it moved more than 4 pt and a drag began.
    private func trackDrag(from start: NSPoint, button: Button) -> Bool {
        let types: NSEvent.EventTypeMask = button == .left ? [.leftMouseUp, .leftMouseDragged] : [.rightMouseUp, .rightMouseDragged]
        while let next = window?.nextEvent(matching: types) {
            if next.type == .leftMouseUp || next.type == .rightMouseUp { return false }
            let p = convert(next.locationInWindow, from: nil)
            if hypot(p.x - start.x, p.y - start.y) > 4 {
                listDelegate?.list(self, beginDragWith: next, rightButton: button == .right)
                return true
            }
        }
        return false
    }

    /// Explorer's right-button drag: press, drag and let go, and a menu asks what to do. A right press
    /// that does not move shows the item menu when the button comes up, as in Explorer.
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0, let delegate = listDelegate else { return super.rightMouseDown(with: event) }
        if !selectedRowIndexes.contains(row) { delegate.list(self, clicked: row, modifiers: []) }
        if trackDrag(from: point, button: .right) { return }
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        return listDelegate?.list(self, menuFor: row, event: event)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        listDelegate?.listDragExited(self)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        super.draggingEnded(sender)
        listDelegate?.listDragExited(self)
    }

    // MARK: Services (other apps' items in the context menu's Services submenu)

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                 returnType: NSPasteboard.PasteboardType?) -> Any? {
        if returnType == nil, let sendType, sendType == .fileURL || sendType == .string, !selectedRowIndexes.isEmpty {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    /// Explorer's marquee: from empty space, a rectangle that selects every row it touches; with Cmd
    /// it adds to what was selected. A click with no drag clears the selection.
    private func rubberBand(from event: NSEvent, at start: NSPoint, adding: Bool) {
        let base = adding ? selectedRowIndexes : IndexSet()
        if !adding { listDelegate?.list(self, banded: IndexSet(), focus: nil) }
        if band.superview == nil { addSubview(band) }
        let rowH = numberOfRows > 0 ? rect(ofRow: 0).height : rowHeight
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            autoscroll(with: next)
            let p = convert(next.locationInWindow, from: nil)
            let r = RubberBand.rect(from: (Double(start.x), Double(start.y)), to: (Double(p.x), Double(p.y)))
            band.frame = NSRect(x: r.x, y: r.y, width: r.width, height: r.height)
            band.isHidden = false
            let hit = RubberBand.rows(fromY: Double(start.y), toY: Double(p.y), rowHeight: Double(rowH), count: numberOfRows)
            let focus = hit.isEmpty ? nil : (p.y < start.y ? hit.first : hit.last)
            listDelegate?.list(self, banded: RubberBand.selection(base: base, hit: hit, adding: adding), focus: focus)
        }
        band.isHidden = true
    }

    /// The marquee: the selection fill and a 1 pt accent line.
    private final class BandView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            let p = Palette.current
            fillRect(bounds, p.selectionFill)
            p.accent.withAlpha(0.8).ns.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
    }
}

/// The column header (`.lh`): s2 strip, wide Archivo labels, the sorted column in the accent with a
/// glowing underline and arrow. Clicks, resizing and reordering stay NSTableHeaderView's own.
final class FolioHeaderView: NSTableHeaderView {
    var sort = SortSpec.standard { didSet { needsDisplay = true } }
    /// The header box: nil hides it; otherwise none, some (mixed) or all rows selected.
    var checkState: (all: Bool, some: Bool)? { didSet { needsDisplay = true } }
    var onToggleAll: (() -> Void)?

    private var nameColumnRect: NSRect? {
        guard let table = tableView,
              let i = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == SortKey.name.rawValue }) else { return nil }
        return headerRect(ofColumn: i)
    }

    private var boxRect: NSRect? {
        guard checkState != nil, let r = nameColumnRect else { return nil }
        return NSRect(x: r.minX + ListMetrics.columnGap / 2 + NameCellView.boxX, y: ListMetrics.headerHeight / 2 - 7, width: 14, height: 14)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let box = boxRect, box.insetBy(dx: -4, dy: -6).contains(point) {
            onToggleAll?()
            return
        }
        super.mouseDown(with: event)
    }

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
        if let box = boxRect, let state = checkState {
            CheckBox.draw(in: box, on: state.all, mixed: state.some && !state.all, p)
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
        case .name: rect.minX + ListMetrics.rowLead + half + 16 + (checkState == nil ? 0 : NameCellView.boxShift)
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
    var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
            subviews.forEach { $0.needsDisplay = true }
        }
    }
    /// Explorer's focus rectangle, drawn when the keyboard focus (Ctrl+arrows) is on an unselected row.
    var isFocusRow = false { didSet { if isFocusRow != oldValue { needsDisplay = true } } }

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
        if isFocusRow && !isSelected {
            let path = NSBezierPath(rect: bounds.insetBy(dx: 3.5, dy: 0.5))
            path.lineWidth = 1
            path.setLineDash([2, 2], count: 2, phase: 0)
            Palette.current.txt3.ns.setStroke()
            path.stroke()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let p = Palette.current
        let r = bounds.insetBy(dx: 3, dy: 0)
        fillRect(r, p.selectionFill)
        drawBrackets(r, color: p.accent.ns, length: 7)
    }

    /// A folder row under a drag: the mark fill, an accent outline and brackets, over the selection.
    var isDropTarget = false { didSet { if isDropTarget != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isDropTarget else { return }
        let p = Palette.current
        let r = bounds.insetBy(dx: 3, dy: 0)
        fillRect(r, p.markFill)
        strokeRounded(r.insetBy(dx: 0.5, dy: 0.5), radius: 3, p.accent)
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
    var entry: FileEntry? {
        didSet {
            needsDisplay = true
            setAccessibilityLabel(entry?.name)
            setAccessibilityValue(entry?.name)
        }
    }
    /// Cut and not yet pasted: drawn at Explorer's faded opacity.
    var isCut = false { didSet { if isCut != oldValue { needsDisplay = true } } }
    var showsCheckbox = false {
        didSet {
            guard showsCheckbox != oldValue else { return }
            light.isLit = selected && !showsCheckbox
            needsDisplay = true
        }
    }
    private var selected = false
    private let light = LedView(diameter: 6)

    /// Where the item check box sits in the cell, and how far it pushes the icon and name.
    static let boxX: CGFloat = ListMetrics.rowLead - 1
    static let boxShift: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        light.isLit = false
        light.breathing = true
        addSubview(light)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func rowSelectionChanged(_ selected: Bool) {
        guard selected != self.selected else { return }
        self.selected = selected
        light.isLit = selected && !showsCheckbox
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
        let hovered = (superview as? FolioRowView)?.isHovered ?? false
        if showsCheckbox && (selected || hovered) {
            CheckBox.draw(in: NSRect(x: Self.boxX, y: (mid - 7).rounded(), width: 14, height: 14), on: selected, mixed: false, p)
        }
        if isCut { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
        let iconX = ListMetrics.rowLead + 6 + 8 + (showsCheckbox ? Self.boxShift : 0)
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
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            needsDisplay = true
            setAccessibilityLabel(text)
            setAccessibilityValue(text)
        }
    }
    var mono = false
    var alignRight = false
    var isCut = false { didSet { if isCut != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    func rowSelectionChanged(_ selected: Bool) {}

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        if isCut { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
        let font = mono ? Typeface.mono(12) : Typeface.ui(13)
        drawLine(text, font: font, color: p.txt2, x: alignRight ? bounds.maxX : 0, midY: bounds.midY,
                 maxWidth: bounds.width, alignRight: alignRight)
    }
}

/// The list pane (`.pane`): s1 panel with a hairline border, radius 4 and accent corner brackets.
final class ListPaneView: NSView {
    let scrollView = NSScrollView()
    private let overlay = BracketOverlay()
    /// A drag over the list background: the whole pane is the target (the current folder).
    var isDropTarget = false {
        didSet {
            guard isDropTarget != oldValue else { return }
            overlay.lit = isDropTarget
            needsDisplay = true
            overlay.needsDisplay = true
        }
    }

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
        var lit = false
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            let p = Palette.current
            if lit {
                strokeRounded(bounds.insetBy(dx: 0.5, dy: 0.5), radius: 4, p.accent)
                drawBrackets(bounds, color: p.accent.ns, length: 14, width: 2)
            } else {
                drawBrackets(bounds, color: p.bracket.ns, length: 12)
            }
        }
    }
}
