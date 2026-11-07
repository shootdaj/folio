import AppKit
import FolioCore

/// A header's filter popover, opened from the chevron: a checkbox per value present in the folder
/// (the same buckets Group by uses), and for a date column a month calendar above them. Ticks apply
/// at once; ticks in one column are ORed, columns are ANDed (FilterSet).
@MainActor
final class FilterPanelController {
    let column: ColumnID
    private weak var owner: BrowserWindowController?
    private let panel: FilterPanel
    private var monitor: Any?
    private var keyMonitor: Any?
    private var computing = false
    /// The column whose panel the arriving click just closed, so that click (on its chevron) does not reopen it.
    static var lastClosed: (column: ColumnID, time: TimeInterval)?

    init(column: ColumnID, owner: BrowserWindowController) {
        self.column = column
        self.owner = owner
        panel = FilterPanel(title: "Filter " + owner.columnTitle(column))
        panel.view.controller = self
    }

    var isOpen: Bool { panel.isVisible }

    func show(below rect: NSRect, in view: NSView) {
        guard let window = view.window else { return }
        refresh()
        let anchor = window.convertToScreen(view.convert(rect, to: nil))
        let size = panel.view.preferredSize
        var x = anchor.maxX - size.width + 6
        x = min(max(x, window.frame.minX + 8), window.frame.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.minY - 4 - size.height, width: size.width, height: size.height), display: true)
        window.addChildWindow(panel, ordered: .above)
        panel.invalidateShadow()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel else { return }
                Self.lastClosed = (self.column, event.timestamp)
                self.close()
            }
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.close() }
            return nil
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        monitor = nil
        keyMonitor = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if owner?.filterPanel === self { owner?.filterPanel = nil }
    }

    /// The rows again from the folder and the filter as it is now.
    func refresh() {
        guard let owner else { return }
        let listing = owner.listing
        let cache = MetadataCache.shared
        if column.needsMetadata && !cache.hasAll(listing) {
            panel.view.update(column: column, rows: [], filter: owner.filters.filter(for: column), message: "Computing filters...",
                              days: [])
            guard !computing else { return }
            computing = true
            Task { [weak self] in
                await Task.detached(priority: .userInitiated) { cache.fill(listing) }.value
                self?.computing = false
                self?.refresh()
            }
            return
        }
        let context = BucketContext()
        let rows = Buckets.present(listing, column, context: context) { cache.cached($0) }
        var days = Set<Date>()
        if column.isDate {
            for e in listing {
                if let d = ColumnValues.date(e, column, column.needsMetadata ? cache.cached(e) : nil) {
                    days.insert(context.calendar.startOfDay(for: d))
                }
            }
        }
        panel.view.update(column: column, rows: rows, filter: owner.filters.filter(for: column),
                          message: rows.isEmpty ? "Nothing to filter" : "", days: days)
        resize()
    }

    private func resize() {
        guard panel.isVisible else { return }
        let size = panel.view.preferredSize
        var f = panel.frame
        f.origin.y += f.height - size.height
        f.size = size
        panel.setFrame(f, display: true)
    }

    func toggle(_ bucket: String) {
        owner?.filters.toggle(bucket, in: column)
        owner?.rearrange()
        refresh()
    }

    func setDays(_ range: DayRange?) {
        owner?.filters.setDays(range, in: column)
        owner?.rearrange()
        refresh()
    }

    func clear() {
        owner?.clearFilter(column)
        refresh()
    }
}

final class FilterPanel: NSPanel {
    let view = FilterView()

    init(title: String) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        self.title = title
        contentView = view
        view.setAccessibilityLabel(title)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// D4's `.menu` panel (--pop, line-2 border, radius 12): a title strip, the calendar for dates,
/// then one check box per bucket with its count.
final class FilterView: NSView {
    weak var controller: FilterPanelController?
    private var column: ColumnID = .name
    private var rows: [(bucket: Bucket, count: Int)] = []
    private var filter = ColumnFilter()
    private var message = ""
    private var checks: [OSCheck] = []
    private let calendar = MonthCalendarView()
    private let clearButton = OSButton("Clear", style: .ghost)
    static let width: CGFloat = 282
    static let headH: CGFloat = 38
    static let rowH: CGFloat = 28

    init() {
        super.init(frame: .zero)
        calendar.onPick = { [weak self] range in self?.controller?.setDays(range) }
        addSubview(calendar)
        clearButton.onPress = { [weak self] in self?.controller?.clear() }
        addSubview(clearButton)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var calendarH: CGFloat { column.isDate ? MonthCalendarView.height + 8 : 0 }

    var preferredSize: NSSize {
        let list = message.isEmpty ? CGFloat(rows.count) * Self.rowH : 40
        return NSSize(width: Self.width, height: Self.headH + calendarH + list + 10)
    }

    func update(column: ColumnID, rows: [(bucket: Bucket, count: Int)], filter: ColumnFilter, message: String, days: Set<Date>) {
        self.column = column
        self.rows = rows
        self.filter = filter
        self.message = message
        calendar.isHidden = !column.isDate
        calendar.daysWithItems = days
        calendar.selected = filter.days
        clearButton.isHidden = filter.isEmpty
        let ids = rows.map(\.bucket.id)
        if checks.count != rows.count || zip(checks, rows).contains(where: { $0.0.title != $0.1.bucket.label }) {
            checks.forEach { $0.removeFromSuperview() }
            checks = zip(ids, rows).map { id, row in
                let check = OSCheck(row.bucket.label) { [weak self] _ in self?.controller?.toggle(id) }
                addSubview(check)
                return check
            }
        }
        for (check, id) in zip(checks, ids) { check.isChecked = filter.buckets.contains(id) }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        clearButton.frame = NSRect(x: bounds.width - 10 - 64, y: 5, width: 64, height: 28)
        calendar.frame = NSRect(x: 10, y: Self.headH + 2, width: bounds.width - 20, height: MonthCalendarView.height)
        let top = Self.headH + calendarH
        for (i, check) in checks.enumerated() {
            check.frame = NSRect(x: 16, y: top + CGFloat(i) * Self.rowH + 4, width: bounds.width - 16 - 52, height: 20)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        fillRounded(bounds, radius: 12, p.pop.over(p.bg))
        strokeRounded(bounds, radius: 12, p.line2)
        let head = Typeface.caption("Filter  " + column.title)
        drawLine(head, font: Typeface.mono(12, weight: 600), color: p.muted, x: 14, midY: Self.headH / 2, kern: Typeface.labelKern(12))
        fillRect(NSRect(x: 1, y: Self.headH - 1, width: bounds.width - 2, height: 1), p.line)
        let top = Self.headH + calendarH
        if column.isDate { fillRect(NSRect(x: 10, y: top - 4, width: bounds.width - 20, height: 1), p.line) }
        if !message.isEmpty {
            drawLine(message, font: Typeface.ui(13), color: p.text2, x: 16, midY: top + 20)
            return
        }
        for (i, row) in rows.enumerated() {
            let y = top + CGFloat(i) * Self.rowH
            let r = NSRect(x: 4, y: y, width: bounds.width - 8, height: Self.rowH)
            if filter.buckets.contains(row.bucket.id) { fillRounded(r.insetBy(dx: 2, dy: 1), radius: 3, p.selectionFill) }
            drawLine(ByteText.grouped(row.count), font: Typeface.mono(12), color: p.muted, x: bounds.width - 16, midY: y + Self.rowH / 2,
                     alignRight: true)
        }
    }
}

/// The Date filter's calendar: a month of days starting on the user's first weekday; click a day or
/// drag across days for a range (Shift+click extends it). Days with items carry a dot.
final class MonthCalendarView: NSView {
    static let height: CGFloat = 218
    var onPick: ((DayRange?) -> Void)?
    var daysWithItems: Set<Date> = [] { didSet { needsDisplay = true } }
    var selected: DayRange? { didSet { needsDisplay = true; rebuildAccessibility() } }
    private var cal = Calendar.current
    private var month: Date
    private var dragStart: Date?
    private var dragEnd: Date?
    private var axDays: [NSAccessibilityElement] = []

    override init(frame: NSRect) {
        month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        super.init(frame: frame)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Select a date or date range")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private let headH: CGFloat = 30, weekH: CGFloat = 22

    private var cellW: CGFloat { bounds.width / 7 }
    private var cellH: CGFloat { (Self.height - headH - weekH) / 6 }

    /// The first day shown (the start of the week holding the 1st).
    private var gridStart: Date { cal.dateInterval(of: .weekOfYear, for: month)?.start ?? month }

    private func day(at index: Int) -> Date { cal.date(byAdding: .day, value: index, to: gridStart)! }

    private func cellRect(_ index: Int) -> NSRect {
        NSRect(x: CGFloat(index % 7) * cellW, y: headH + weekH + CGFloat(index / 7) * cellH, width: cellW, height: cellH)
    }

    private func index(at p: NSPoint) -> Int? {
        guard p.y >= headH + weekH else { return nil }
        let col = Int(p.x / cellW), row = Int((p.y - headH - weekH) / cellH)
        guard (0..<7).contains(col), (0..<6).contains(row) else { return nil }
        return row * 7 + col
    }

    private var prevRect: NSRect { NSRect(x: 0, y: 2, width: 28, height: 26) }
    private var nextRect: NSRect { NSRect(x: bounds.width - 28, y: 2, width: 28, height: 26) }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if prevRect.contains(p) || nextRect.contains(p) {
            month = cal.date(byAdding: .month, value: prevRect.contains(p) ? -1 : 1, to: month)!
            needsDisplay = true
            rebuildAccessibility()
            return
        }
        guard let i = index(at: p) else { return }
        let d = day(at: i)
        if event.modifierFlags.contains(.shift), let s = selected {
            onPick?(DayRange(s.first, d, calendar: cal))
            return
        }
        dragStart = d
        dragEnd = d
        needsDisplay = true
        while let window, let next = MouseTracking.next(window, [.leftMouseDragged, .leftMouseUp], idle: nil) {
            let q = convert(next.locationInWindow, from: nil)
            if let j = index(at: q) { dragEnd = day(at: j); needsDisplay = true }
            if next.type == .leftMouseUp { break }
        }
        guard let a = dragStart, let b = dragEnd else { return }
        dragStart = nil
        dragEnd = nil
        let range = DayRange(a, b, calendar: cal)
        // A click on the one day already picked takes it off.
        onPick?(range == selected ? nil : range)
    }

    private func isPicked(_ d: Date) -> Bool {
        if let a = dragStart, let b = dragEnd { return DayRange(a, b, calendar: cal).contains(d, calendar: cal) }
        return selected?.contains(d, calendar: cal) ?? false
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        let title = month.formatted(.dateTime.month(.wide).year())
        let tf = Typeface.ui(13, weight: 650)
        drawLine(title, font: tf, color: p.text, x: bounds.midX - textWidth(title, font: tf) / 2, midY: headH / 2 + 1)
        Glyph.back.draw(in: NSRect(x: prevRect.midX - 7, y: prevRect.midY - 7, width: 14, height: 14), color: p.text2.ns)
        Glyph.forward.draw(in: NSRect(x: nextRect.midX - 7, y: nextRect.midY - 7, width: 14, height: 14), color: p.text2.ns)
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let wf = Typeface.mono(11, weight: 600)
        for c in 0..<7 {
            let s = symbols[(cal.firstWeekday - 1 + c) % 7]
            drawLine(s, font: wf, color: p.muted, x: CGFloat(c) * cellW + cellW / 2 - textWidth(s, font: wf) / 2, midY: headH + weekH / 2)
        }
        let today = cal.startOfDay(for: Date())
        let df = Typeface.mono(12)
        for i in 0..<42 {
            let d = day(at: i)
            let r = cellRect(i).insetBy(dx: 2, dy: 1.5)
            let inMonth = cal.isDate(d, equalTo: month, toGranularity: .month)
            let picked = isPicked(d)
            if picked {
                fillRounded(r, radius: 3, p.accent)
            } else if d == today {
                strokeRounded(r, radius: 3, p.accent)
            }
            let n = "\(cal.component(.day, from: d))"
            let tone: NSColor = picked ? p.onAccent : (inMonth ? p.text : p.muted)
            drawLine(n, font: df, color: tone, x: r.midX - textWidth(n, font: df) / 2, midY: r.midY - 1)
            if daysWithItems.contains(cal.startOfDay(for: d)) {
                (picked ? p.onAccent : p.accent).ns.setFill()
                NSBezierPath(ovalIn: NSRect(x: r.midX - 1.5, y: r.maxY - 5, width: 3, height: 3)).fill()
            }
        }
    }

    // Accessibility: each day a button ("2026-11-05"), so a test can pick one.
    private func rebuildAccessibility() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        axDays = (0..<42).map { i in
            let d = day(at: i)
            let e = HeaderElement()
            e.setAccessibilityRole(.button)
            e.setAccessibilityLabel(f.string(from: d))
            e.setAccessibilityParent(self)
            e.setAccessibilityFrameInParentSpace(cellRect(i))
            e.press = { [weak self] in
                guard let self else { return }
                let range = DayRange(d, d, calendar: self.cal)
                self.onPick?(range == self.selected ? nil : range)
            }
            return e
        }
    }

    override func layout() {
        super.layout()
        rebuildAccessibility()
    }

    override func accessibilityChildren() -> [Any]? { axDays }
}

extension BrowserWindowController {
    /// The chevron (or tick) of a header was clicked.
    func showFilter(_ column: ColumnID, below rect: NSRect) {
        if let last = FilterPanelController.lastClosed, last.column == column, let event = NSApp.currentEvent,
           abs(last.time - event.timestamp) < 0.001 {
            return
        }
        if let open = filterPanel {
            let same = open.column == column
            open.close()
            if same { return }
        }
        let panel = FilterPanelController(column: column, owner: self)
        filterPanel = panel
        panel.show(below: rect, in: header)
    }
}
