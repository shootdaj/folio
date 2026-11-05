import AppKit
import FolioCore

/// D1 list metrics. `--row-h` in the design is 24 px.
enum ListMetrics {
    static let rowHeight: CGFloat = 24
    /// View > Compact view.
    static let compactRowHeight: CGFloat = 20
    /// A Group by header row ("Today (3)").
    static let groupRowHeight: CGFloat = 32
    static let headerHeight: CGFloat = 32
    /// The list's 4 px top padding (`.list{padding:4px 0}`), drawn as part of the header strip.
    static let listTopPad: CGFloat = 4
    static let columnGap: CGFloat = 14
    /// Grid padding-left is 10 px; NSTableView already insets cells by half the column gap.
    static let rowLead: CGFloat = 10 - columnGap / 2
}

/// What the list asks of its window controller: Explorer's selection rules live there (ListSelection).
/// Rows here are items (the shown items in order, group headers not counted); the Details table and
/// the icon grid both speak it.
@MainActor
protocol FileListDelegate: AnyObject {
    func list(_ list: NSView, clicked row: Int, modifiers: NSEvent.ModifierFlags)
    func list(_ list: NSView, toggledCheckboxOf row: Int)
    func list(_ list: NSView, opened row: Int)
    /// The rubber band now covers `rows` (already combined with the old selection for Cmd+drag).
    func list(_ list: NSView, banded rows: IndexSet, focus: Int?)
    func listToggledAll(_ list: NSView)
    /// Option+double-click: Properties (Explorer's Alt+double-click).
    func list(_ list: NSView, showPropertiesOf row: Int)
    /// The press on a row became a drag of the selection (left or right button).
    func list(_ list: NSView, beginDragWith event: NSEvent, rightButton: Bool)
    /// Right-click: the item menu for `row`, or the background menu for -1.
    func list(_ list: NSView, menuFor row: Int, event: NSEvent) -> NSMenu?
    /// A drag left the list or ended over it.
    func listDragExited(_ list: NSView)
    /// Services: the selected items' file URLs.
    func listSelectedURLs(_ list: NSView) -> [URL]
    /// The middle button on a row: a folder opens in a background tab.
    func list(_ list: NSView, middleClicked row: Int)
    /// A Group by header: a click selects the group, its chevron or a double-click folds it.
    func list(_ list: NSView, pressedGroup group: Int, onChevron: Bool, clickCount: Int)
    /// Right-click a group header: Collapse group, Collapse all groups, Expand all groups.
    func list(_ list: NSView, menuForGroup group: Int) -> NSMenu?
    /// Is this item selected (the model, not the table, decides).
    func listIsSelected(_ row: Int) -> Bool
}

/// The table, with hover tracking for the 5.5% row wash, Explorer clicks (Cmd+click toggles, Shift+click
/// ranges, Cmd+Shift+click adds a range), a rubber band from empty space, and item check boxes.
final class FolioTableView: NSTableView {
    private(set) var hoveredRow = -1
    weak var listDelegate: FileListDelegate?
    /// Table row to item (nil on a group header) and item to table row; identity until grouped.
    var itemAtRow: (Int) -> Int? = { $0 }
    var rowOfItem: (Int) -> Int = { $0 }
    var groupAtRow: (Int) -> Int? = { _ in nil }
    /// View > Item check boxes: a box in each Name cell (on hover and on selected rows) and in the header.
    var showsCheckboxes = false {
        didSet {
            guard showsCheckboxes != oldValue else { return }
            enumerateAvailableRowViews { row, _ in row.subviews.forEach { $0.needsDisplay = true } }
            headerView?.needsDisplay = true
        }
    }
    private let band = BandView()
    /// Folder Options > Single-click to open an item (point to select).
    var singleClickOpens = false
    private var hoverSelect: Timer?

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
        let row = groupAtRow(row) == nil ? row : -1
        guard row != hoveredRow else { return }
        let old = hoveredRow
        hoveredRow = row
        // Point to select: resting on an item a moment selects it.
        hoverSelect?.invalidate()
        hoverSelect = nil
        if singleClickOpens, row >= 0, let item = itemAtRow(row), NSEvent.pressedMouseButtons == 0 {
            hoverSelect = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.hoveredRow == row, self.listDelegate?.listIsSelected(item) == false else { return }
                    self.listDelegate?.list(self, clicked: item, modifiers: NSEvent.modifierFlags.intersection([.command, .shift]))
                }
            }
        }
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
        let tableRow = row(at: point)
        let mods = event.modifierFlags.intersection([.command, .shift])
        if let group = groupAtRow(tableRow) {
            delegate.list(self, pressedGroup: group, onChevron: point.x < GroupHeaderCellView.chevronEnd,
                          clickCount: event.clickCount)
            return
        }
        guard tableRow >= 0, let row = itemAtRow(tableRow) else {
            rubberBand(from: event, at: point, adding: mods.contains(.command))
            return
        }
        if showsCheckboxes, checkboxRect(row: tableRow).contains(point) {
            delegate.list(self, toggledCheckboxOf: row)
            return
        }
        // Single-click mode: the first click opened it already.
        if singleClickOpens, event.clickCount >= 2 { return }
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
        if mods.isEmpty, delegate.listIsSelected(row), selectedRowIndexes.count > 1 {
            if !trackDrag(from: point, button: .left) { delegate.list(self, clicked: row, modifiers: []) }
            return
        }
        delegate.list(self, clicked: row, modifiers: mods)
        // A press on a selected row can become a drag of the selection; single-click mode opens on release.
        if delegate.listIsSelected(row) {
            let dragged = trackDrag(from: point, button: .left)
            if !dragged, singleClickOpens, mods.isEmpty, !event.modifierFlags.contains(.option) { delegate.list(self, opened: row) }
        }
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
        let tableRow = row(at: point)
        guard tableRow >= 0, let row = itemAtRow(tableRow), let delegate = listDelegate else { return super.rightMouseDown(with: event) }
        if !delegate.listIsSelected(row) { delegate.list(self, clicked: row, modifiers: []) }
        if trackDrag(from: point, button: .right) { return }
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let tableRow = row(at: convert(event.locationInWindow, from: nil))
        if let group = groupAtRow(tableRow) { return listDelegate?.list(self, menuForGroup: group) }
        return listDelegate?.list(self, menuFor: itemAtRow(tableRow) ?? -1, event: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        let tableRow = row(at: convert(event.locationInWindow, from: nil))
        guard event.buttonNumber == 2, let row = itemAtRow(tableRow), let delegate = listDelegate else {
            return super.otherMouseDown(with: event)
        }
        delegate.list(self, middleClicked: row)
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
        let base = adding ? IndexSet(selectedRowIndexes.compactMap(itemAtRow)) : IndexSet()
        if !adding { listDelegate?.list(self, banded: IndexSet(), focus: nil) }
        if band.superview == nil { addSubview(band) }
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            autoscroll(with: next)
            let p = convert(next.locationInWindow, from: nil)
            let r = RubberBand.rect(from: (Double(start.x), Double(start.y)), to: (Double(p.x), Double(p.y)))
            band.frame = NSRect(x: r.x, y: r.y, width: r.width, height: r.height)
            band.isHidden = false
            // Rows the band's vertical span touches (group headers are taller and take no part).
            let span = rows(in: NSRect(x: 0, y: min(start.y, p.y), width: 1, height: max(0.5, abs(p.y - start.y))))
            let hit = IndexSet((span.location..<(span.location + span.length)).compactMap(itemAtRow))
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
/// glowing underline and arrow; with several sort keys each sorted column gets a numbered badge.
/// Hovering a header shows a filter chevron at its right edge; a filtered column shows a tick there
/// instead. Resizing and reordering stay NSTableHeaderView's own.
final class FolioHeaderView: NSTableHeaderView {
    var sort = SortSpec.standard { didSet { needsDisplay = true; if sort != oldValue { rebuildAccessibility() } } }
    /// Off for search results in relevance order: no column carries the sort arrow.
    var showsSort = true { didSet { if showsSort != oldValue { needsDisplay = true; axKey = ""; rebuildAccessibility() } } }

    private func rank(of key: ColumnID) -> Int? { showsSort ? sort.rank(of: key) : nil }
    /// Columns with a header filter on: a tick where the chevron goes.
    var filtered: Set<ColumnID> = [] { didSet { if filtered != oldValue { needsDisplay = true; rebuildAccessibility() } } }
    /// The header box: nil hides it; otherwise none, some (mixed) or all rows selected.
    var checkState: (all: Bool, some: Bool)? { didSet { needsDisplay = true } }
    var onToggleAll: (() -> Void)?
    /// The chevron (or tick) of a column was clicked: open its filter below `rect` (header coordinates).
    var onFilter: ((ColumnID, NSRect) -> Void)?
    /// Right-click: the menu for the column under the pointer (nil past the last column).
    var onMenu: ((ColumnID?) -> NSMenu?)?
    private var hoverColumn = -1 {
        didSet {
            guard hoverColumn != oldValue else { return }
            needsDisplay = true
            rebuildAccessibility()
        }
    }
    private var axElements: [NSAccessibilityElement] = []
    private var axKey = ""

    static let chevronW: CGFloat = 20

    private var nameColumnRect: NSRect? {
        guard let table = tableView,
              let i = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == SortKey.name.rawValue }) else { return nil }
        return headerRect(ofColumn: i)
    }

    private var boxRect: NSRect? {
        guard checkState != nil, let r = nameColumnRect else { return nil }
        return NSRect(x: r.minX + ListMetrics.columnGap / 2 + NameCellView.boxX, y: ListMetrics.headerHeight / 2 - 7, width: 14, height: 14)
    }

    private func key(ofColumn i: Int) -> ColumnID? {
        guard let table = tableView, table.tableColumns.indices.contains(i) else { return nil }
        return ColumnID(rawValue: table.tableColumns[i].identifier.rawValue)
    }

    /// The chevron's hit area at the right edge of column `i` (the gap is the column's own half).
    func chevronRect(ofColumn i: Int) -> NSRect {
        let r = headerRect(ofColumn: i)
        return NSRect(x: r.maxX - ListMetrics.columnGap / 2 - Self.chevronW, y: 6, width: Self.chevronW, height: ListMetrics.headerHeight - 12)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let p = convert(event.locationInWindow, from: nil)
        hoverColumn = p.y < ListMetrics.headerHeight ? column(at: p) : -1
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoverColumn = -1
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let box = boxRect, box.insetBy(dx: -4, dy: -6).contains(point) {
            onToggleAll?()
            return
        }
        let i = column(at: point)
        if i >= 0, let key = key(ofColumn: i), chevronRect(ofColumn: i).contains(point), event.modifierFlags.intersection([.shift, .command]).isEmpty {
            onFilter?(key, chevronRect(ofColumn: i))
            return
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let i = column(at: convert(event.locationInWindow, from: nil))
        return onMenu?(key(ofColumn: i))
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
            drawHeader(column.title, key: key, in: rect, hovered: index == hoverColumn && draggedColumn < 0, p)
        }
        if let box = boxRect, let state = checkState {
            CheckBox.draw(in: box, on: state.all, mixed: state.some && !state.all, p)
        }
    }

    private func drawHeader(_ title: String, key: SortKey, in rect: NSRect, hovered: Bool, _ p: Palette) {
        let rank = rank(of: key)
        let primary = rank == 1
        let multi = sort.terms.count > 1
        let color = primary ? p.accent : (rank != nil ? p.txt : p.txt2)
        let kern: CGFloat = 0.24
        let tw = textWidth(title, font: font, kern: kern)
        let arrow: CGFloat = 14, gap: CGFloat = 6, badge: CGFloat = multi ? 15 : 0
        let half = ListMetrics.columnGap / 2
        let chevron = Self.chevronW
        // Name sits 16 px in from the grid edge; right-aligned columns hug the right, the arrow and the
        // filter chevron's slots still reserved.
        let x: CGFloat = if key == .name {
            rect.minX + ListMetrics.rowLead + half + 16 + (checkState == nil ? 0 : NameCellView.boxShift)
        } else if key.alignsRight {
            max(rect.minX + half, rect.maxX - half - chevron - badge - arrow - gap - tw)
        } else {
            rect.minX + half
        }
        let mid = rect.midY.rounded()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        let room = max(0, rect.maxX - x - half - chevron - (rank != nil ? arrow + gap + badge : 0))
        let drawn = drawLine(title, font: font, color: color, x: x, midY: mid, maxWidth: room, kern: kern)
        if let rank {
            if primary {
                // 2 px underline 8 px below the label box, with a glow in dark.
                let underline = NSRect(x: x, y: mid + 6 + 8 - 2, width: drawn, height: 2)
                if p.glows, let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: 9, color: p.accent.withAlpha(0.6).cg)
                    fillRect(underline, p.accent)
                    ctx.restoreGState()
                } else {
                    fillRect(underline, p.accent)
                }
            }
            let ax = x + drawn + gap
            Glyph.sort.draw(in: NSRect(x: ax, y: mid - arrow / 2, width: arrow, height: arrow),
                            color: (primary ? p.accent : p.txt2).ns, rotation: (sort.isAscending(key) ?? true) ? 0 : .pi)
            if multi {
                // The sort key's number: 1 for the first key, 2 and on for Shift+click keys.
                let b = NSRect(x: ax + arrow + 1, y: mid - 7, width: 14, height: 14)
                if primary {
                    fillRounded(b, radius: 3, p.accent)
                } else {
                    fillRounded(b, radius: 3, p.s3)
                    strokeRounded(b, radius: 3, p.line3)
                }
                let digit = "\(rank)"
                let f = Typeface.mono(10, weight: 600)
                drawLine(digit, font: f, color: primary ? p.onAccent : p.txt, x: b.midX - textWidth(digit, font: f) / 2, midY: b.midY)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let c = NSRect(x: rect.maxX - half - chevron, y: 6, width: chevron, height: ListMetrics.headerHeight - 12)
        if filtered.contains(key) {
            // A filtered column: the tick stays, in the accent, with the chevron's hover box.
            if hovered { fillRounded(c, radius: 3, p.accent.withAlpha(0.12)) }
            Glyph.check.draw(in: NSRect(x: c.midX - 7, y: c.midY - 7, width: 14, height: 14), color: p.accent.ns, lineWidth: 2)
        } else if hovered {
            fillRounded(c, radius: 3, p.txt.withAlpha(0.08))
            drawBrackets(c, color: p.bracket.ns, length: 5)
            Glyph.chevronDown.draw(in: NSRect(x: c.midX - 7, y: c.midY - 7, width: 14, height: 14), color: p.txt.ns)
        }
    }

    // MARK: Accessibility: each header and its filter chevron, so a test can find and press them.

    private func rebuildAccessibility() {
        guard let table = tableView else { return }
        var key = ""
        var elements: [NSAccessibilityElement] = []
        for (i, column) in table.tableColumns.enumerated() {
            guard let id = ColumnID(rawValue: column.identifier.rawValue) else { continue }
            let head = headerRect(ofColumn: i), chev = chevronRect(ofColumn: i)
            key += "\(id.rawValue)|\(head)|"
            let h = HeaderElement()
            h.setAccessibilityRole(.button)
            h.setAccessibilityLabel(column.title + " header")
            // "sort 2 ascending": the key's number among the sort keys and its direction.
            if let rank = rank(of: id) {
                h.setAccessibilityValue("sort \(rank) " + ((sort.isAscending(id) ?? true) ? "ascending" : "descending"))
            }
            h.setAccessibilityParent(self)
            h.setAccessibilityFrameInParentSpace(NSRect(x: head.minX, y: 0, width: head.width, height: ListMetrics.headerHeight))
            let f = HeaderElement()
            f.setAccessibilityRole(.button)
            f.setAccessibilityLabel("Filter " + column.title)
            f.setAccessibilityValue(filtered.contains(id) ? "filtered" : "")
            f.setAccessibilityParent(self)
            f.setAccessibilityFrameInParentSpace(chev)
            f.press = { [weak self] in self?.onFilter?(id, chev) }
            elements += [h, f]
        }
        key += filtered.map(\.rawValue).sorted().joined(separator: ",") + SortLabel.label(sort)
        guard key != axKey else { return }
        axKey = key
        axElements = elements
    }

    override func layout() {
        super.layout()
        rebuildAccessibility()
    }

    override func accessibilityChildren() -> [Any]? {
        rebuildAccessibility()
        return (super.accessibilityChildren() ?? []) + axElements
    }
}

final class HeaderElement: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return press != nil }
}

/// A Group by header row in the Details view (and the grid's section header): a chevron on the left
/// that folds the group, "Today (3)" in the wide face, and a hairline to the right edge.
@MainActor
enum GroupHeaderDrawing {
    static func draw(title: String, count: Int, collapsed: Bool, hovered: Bool, in r: NSRect, lead: CGFloat, _ p: Palette) {
        let mid = r.midY.rounded() + 2
        let chev = NSRect(x: lead, y: mid - 7, width: 14, height: 14)
        if hovered { fillRounded(r.insetBy(dx: 3, dy: 3), radius: 3, p.txt.withAlpha(0.045)) }
        Glyph.chevronDown.draw(in: chev, color: (hovered ? p.accent : p.txt2).ns, rotation: collapsed ? -.pi / 2 : 0)
        let font = Typeface.ui(13, weight: 650, width: 116)
        let tx = chev.maxX + 8
        let w = drawLine(title, font: font, color: hovered ? p.accent : p.txt, x: tx, midY: mid, maxWidth: max(0, r.maxX - tx - 60), kern: 0.2)
        let countText = "(\(count))"
        let cw = drawLine(countText, font: Typeface.mono(12), color: p.txt3, x: tx + w + 6, midY: mid)
        let lineX = tx + w + 6 + cw + 10
        if lineX < r.maxX - 10 {
            fillRect(NSRect(x: lineX, y: mid, width: r.maxX - 10 - lineX, height: 1), p.line)
            // D1's bracket language: a short accent tick where the rule starts.
            fillRect(NSRect(x: lineX, y: mid - 2, width: 1, height: 5), hovered ? p.accent : p.line3)
        }
    }
}

/// The Details table's group header cell.
final class GroupHeaderCellView: NSTableCellView {
    /// Clicks left of this x (table coordinates) are on the chevron.
    static let chevronEnd: CGFloat = 40
    var title = "" { didSet { needsDisplay = true; setAccessibilityLabel(title + " (\(count))") } }
    var count = 0 { didSet { needsDisplay = true; setAccessibilityLabel(title + " (\(count))") } }
    var collapsed = false { didSet { needsDisplay = true; setAccessibilityValue(collapsed ? "collapsed" : "expanded") } }
    private var hovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        GroupHeaderDrawing.draw(title: title, count: count, collapsed: collapsed, hovered: hovered, in: bounds,
                                lead: ListMetrics.rowLead + 6, Palette.current)
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
        guard !isGroupRowStyle else { return }
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
        guard !isGroupRowStyle else { return }
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

/// Name cell: selection light, folder or file icon, tag dots, name (accent and semibold when selected).
final class NameCellView: NSTableCellView, RowCellView, ThemeAware, NSViewToolTipOwner {
    /// Finder tags with a colour: a dot each before the name, as Finder marks them.
    var tagColors: [TagColor] = [] { didSet { if tagColors != oldValue { needsDisplay = true } } }
    /// Single-click to open: names underlined always, or only under the pointer; nil in double-click mode.
    var underline: FolderOptions.Underline? { didSet { if underline != oldValue { needsDisplay = true } } }
    /// Show encrypted or compressed files in colour: a locked or compressed item draws dimmed.
    var isFlagDimmed = false { didSet { if isFlagDimmed != oldValue { needsDisplay = true } } }
    /// A folder with a custom icon (Customize this folder) shows it instead of D1's folder.
    var customIcon: NSImage? { didSet { needsDisplay = true } }
    /// Show pop-up description: the hover tip, built when it is about to show.
    var tip: (() -> String?)? { didSet { needsLayout = true } }
    var entry: FileEntry? {
        didSet {
            needsDisplay = true
            setAccessibilityLabel(entry?.name)
            setAccessibilityValue(entry?.name)
        }
    }
    /// Cut and not yet pasted, or a hidden item while hidden items show: drawn at Explorer's faded opacity.
    var isCut = false { didSet { if isCut != oldValue { needsDisplay = true } } }
    /// View > File name extensions.
    var showsExtension = true { didSet { if showsExtension != oldValue { needsDisplay = true } } }
    var showsCheckbox = false {
        didSet {
            guard showsCheckbox != oldValue else { return }
            light.isLit = selected && !showsCheckbox
            needsDisplay = true
        }
    }
    private var selected = false
    private let light = LedView(diameter: 6)
    /// Search results: the parts of the name that matched (UTF-16 ranges of the name shown), lit.
    var highlights: [NSRange] = [] { didSet { if highlights != oldValue { needsDisplay = true } } }

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
        removeAllToolTips()
        if tip != nil { addToolTip(bounds, owner: self, userData: nil) }
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        tip?() ?? ""
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let entry else { return }
        let p = Palette.current
        let mid = bounds.midY
        let hovered = (superview as? FolioRowView)?.isHovered ?? false
        if showsCheckbox && (selected || hovered) {
            CheckBox.draw(in: NSRect(x: Self.boxX, y: (mid - 7).rounded(), width: 14, height: 14), on: selected, mixed: false, p)
        }
        if isCut || entry.isHidden || isFlagDimmed { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
        let iconX = ListMetrics.rowLead + 6 + 8 + (showsCheckbox ? Self.boxShift : 0)
        var textX: CGFloat
        if let customIcon, entry.isFolder {
            customIcon.draw(in: NSRect(x: iconX, y: mid - 9, width: 18, height: 18), from: .zero, operation: .sourceOver,
                            fraction: 1, respectFlipped: true, hints: nil)
            textX = iconX + 18 + 8
        } else if entry.isFolder {
            ItemIcon.drawFolder(in: NSRect(x: iconX, y: mid - 7.5, width: 18, height: 15), palette: p, lit: selected)
            textX = iconX + 18 + 8
        } else {
            ItemIcon.drawFile(named: entry.name, in: NSRect(x: iconX, y: mid - 7.5, width: 15, height: 15), palette: p)
            textX = iconX + 15 + 8
        }
        if entry.isLink { ItemIcon.drawLinkBadge(in: NSRect(x: iconX - 2, y: mid + 1, width: 9, height: 9), palette: p) }
        if !tagColors.isEmpty {
            textX += TagDots.draw(tagColors, x: textX - 2, midY: mid, p) + 4
        }
        let shown = entry.displayName(extensions: showsExtension)
        let font = Typeface.ui(13, weight: selected ? 600 : 400)
        let maxW = max(0, bounds.width - textX - (entry.isCloudOnly ? 22 : 0))
        if !highlights.isEmpty {
            // A soft accent mark behind each matched word start, as Explorer lights search terms.
            let ns = shown as NSString
            for r in highlights where r.location + r.length <= ns.length {
                let x0 = textWidth(ns.substring(to: r.location), font: font)
                let w = textWidth(ns.substring(with: r), font: font)
                guard x0 < maxW else { continue }
                let rect = NSRect(x: textX + x0 - 1, y: mid - 9, width: min(w + 2, maxW - x0 + 1), height: 18)
                fillRounded(rect, radius: 3, p.accent.withAlpha(0.22))
            }
        }
        let nameW = drawLine(shown, font: font, color: selected ? p.accent : p.txt, x: textX, midY: mid, maxWidth: maxW)
        if let underline, underline == .always || hovered {
            fillRect(NSRect(x: textX, y: (mid + 7).rounded(), width: nameW, height: 1), selected ? p.accent : p.txt.withAlpha(0.7))
        }
        if entry.isCloudOnly {
            // Online only: a cloud after the name, as Explorer marks OneDrive files.
            Glyph.cloud.draw(in: NSRect(x: textX + nameW + 6, y: mid - 7, width: 14, height: 14), color: p.txt3.ns, lineWidth: 1.6)
        }
    }
}

/// Finder's tag dots: one per colour, overlapping a little, each ringed in the row's background.
@MainActor
enum TagDots {
    static func color(_ c: TagColor, _ p: Palette) -> RGBA {
        let dark = p.appearance == .dark
        switch c {
        case .red: return p.miss
        case .orange: return p.typeData
        case .yellow: return p.typeCode
        case .green: return p.ok
        case .blue: return p.typeDoc
        case .purple: return RGBA(hex: dark ? 0xB794F6 : 0x6D4BB0)
        case .gray, .none: return p.txt3
        }
    }

    /// Returns the width drawn.
    @discardableResult
    static func draw(_ colors: [TagColor], x: CGFloat, midY: CGFloat, _ p: Palette, size: CGFloat = 8) -> CGFloat {
        let shown = Array(colors.prefix(3))
        for (i, c) in shown.enumerated().reversed() {
            let r = NSRect(x: x + CGFloat(i) * (size - 3), y: (midY - size / 2).rounded(), width: size, height: size)
            fillRounded(r.insetBy(dx: -1, dy: -1), radius: size / 2 + 1, p.s1)
            fillRounded(r, radius: size / 2, color(c, p))
        }
        return shown.isEmpty ? 0 : size + CGFloat(shown.count - 1) * (size - 3)
    }

    /// A menu item's coloured dot.
    static func image(_ c: TagColor) -> NSImage {
        let p = Palette.current
        return NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            fillRounded(r.insetBy(dx: 1, dy: 1), radius: 5, color(c, p))
            return true
        }
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
    /// A metadata column whose value is still being read: a dim placeholder.
    var pending = false

    override var isFlipped: Bool { true }

    func rowSelectionChanged(_ selected: Bool) {}

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        if isCut { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
        let font = mono ? Typeface.mono(12) : Typeface.ui(13)
        if pending && text.isEmpty {
            fillRect(NSRect(x: alignRight ? bounds.maxX - 18 : 0, y: bounds.midY, width: 18, height: 1), p.line2)
            return
        }
        drawLine(text, font: font, color: p.txt2, x: alignRight ? bounds.maxX : 0, midY: bounds.midY,
                 maxWidth: bounds.width, alignRight: alignRight)
    }
}

/// The list pane (`.pane`): s1 panel with a hairline border, radius 4 and accent corner brackets.
/// It holds the Details table and the icon grid (one shown at a time) and, in Gallery, Quick Look's
/// preview above the grid's strip.
final class ListPaneView: NSView {
    let scrollView = NSScrollView()
    let gridScroll = NSScrollView()
    let gallery = QuickLookBox()
    static let galleryStripH: CGFloat = 186
    var mode: ViewMode = .details {
        didSet {
            guard mode != oldValue else { return }
            scrollView.isHidden = !mode.usesTable
            gridScroll.isHidden = mode.usesTable
            gallery.isHidden = mode != .gallery
            if mode != .gallery { gallery.close() }
            gridScroll.hasHorizontalScroller = mode == .list || mode == .gallery
            gridScroll.hasVerticalScroller = !(mode == .list || mode == .gallery)
            needsLayout = true
        }
    }
    private let overlay = BracketOverlay()
    /// Search results: "Search again in" under the list, and the empty or working text over it.
    let searchFooter = SearchFooterView(frame: .zero)
    let searchEmpty = SearchEmptyView(frame: .zero)
    var showsSearchFooter = false {
        didSet {
            guard showsSearchFooter != oldValue else { return }
            searchFooter.isHidden = !showsSearchFooter
            if !showsSearchFooter { searchEmpty.isHidden = true }
            needsLayout = true
        }
    }
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
        // Name fills the list (BrowserWindowController.fitColumns); with more columns than fit, the
        // list scrolls sideways.
        scrollView.hasHorizontalScroller = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        // Keeps the header's square corners inside the pane's 4 pt radius.
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 3
        scrollView.layer?.masksToBounds = true
        addSubview(scrollView)
        gridScroll.drawsBackground = false
        gridScroll.contentView.drawsBackground = false
        gridScroll.borderType = .noBorder
        gridScroll.hasVerticalScroller = true
        gridScroll.autohidesScrollers = true
        gridScroll.scrollerStyle = .overlay
        gridScroll.isHidden = true
        gridScroll.wantsLayer = true
        gridScroll.layer?.cornerRadius = 3
        gridScroll.layer?.masksToBounds = true
        addSubview(gridScroll)
        gallery.isHidden = true
        addSubview(gallery)
        searchFooter.isHidden = true
        searchEmpty.isHidden = true
        addSubview(searchEmpty)
        addSubview(searchFooter)
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        guard bounds.width > 4, bounds.height > 4 else { return }
        var inner = bounds.insetBy(dx: 1, dy: 1)
        if showsSearchFooter {
            searchFooter.frame = NSRect(x: inner.minX, y: inner.maxY - SearchFooterView.height, width: inner.width, height: SearchFooterView.height)
            inner.size.height -= SearchFooterView.height
            let top = ListMetrics.headerHeight + ListMetrics.listTopPad
            searchEmpty.frame = NSRect(x: inner.minX, y: inner.minY + top, width: inner.width, height: max(0, min(120, inner.height - top)))
        }
        scrollView.frame = inner
        if mode == .gallery {
            let strip = min(Self.galleryStripH, inner.height / 2)
            gallery.frame = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height - strip)
            gridScroll.frame = NSRect(x: inner.minX, y: inner.maxY - strip, width: inner.width, height: strip)
        } else {
            gridScroll.frame = inner
        }
        overlay.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRounded(bounds, radius: 4, p.s1)
        strokeRounded(bounds, radius: 4, p.line)
        if mode == .gallery {
            fillRect(NSRect(x: 1, y: gridScroll.frame.minY - 1, width: bounds.width - 2, height: 1), p.line)
        }
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
