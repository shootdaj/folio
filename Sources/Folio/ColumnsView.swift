import AppKit
import FolioCore

/// One folder's items as its column shows them: read off the main thread through the window's own
/// listing path (BrowserWindowController.listFolder: FolderListing, the Recycle Bin's rows, a zip's central
/// directory) and sorted like the list (filters and groups do not apply to columns).
struct ColumnListing: Sendable {
    let url: URL
    /// The standardized path the columns go by.
    let path: String
    /// FilePaths.folderKey: what file operations and the folder watcher report.
    let folderKey: String
    let rows: [FileEntry]
    let keys: [String]
    let sort: SortSpec
    let hidden: Bool
    let protected: Bool
    /// The name of a hidden item put in so the path shows (a dot folder on the way while hidden items are off).
    let ensured: String?
    let error: String?
    /// When it was read: a column older than a moment is read again quietly once its folder is entered.
    var read = Date()
    /// How long reading and sorting took, off the main thread (the perf log).
    var readMs = 0
    /// Its folder changed on disk since: still shown and still opened at once, but read again.
    var stale = false
    /// Set by the store: a new number for every listing, so a column reloads only when its rows change.
    var id = 0
}

/// The Columns view's state for one window: where the columns start, the listings read for them, the
/// widths. Nothing here is saved per folder; the one width every column opens at is in the defaults.
@MainActor
final class ColumnStore {
    /// The first column's folder, the current folder the columns were built for, every folder shown, and
    /// the folders from the first column to the current one (watched for changes on disk).
    var root: String?
    var shownFolder: String?
    var shownPaths: [String] = []
    var pathFolders: [String] = []
    /// Right on a folder whose column is still being read: go in when it lands.
    var pendingEnter: String?
    /// The list's version last put in the cache as the current folder's listing.
    var cachedVersion = -1
    /// The listing the list was just shown from (showColumnFolder): it is the current folder's listing as is.
    var adoptedID: Int?
    private var listings: [String: ColumnListing] = [:]
    private var used: [String] = []
    private var nextID = 1
    var inFlight: Set<String> = []
    /// A selected folder's column (after the current one) is read one folder at a time; the latest wins,
    /// so holding Down over many folders does not start a read for each.
    var trailingBusy = false
    var trailingWanted: (path: String, ensure: String?)?
    /// The width every column opens at; a column dragged or fitted keeps its own while it is on screen.
    var width = CGFloat(ColumnWidth.load(.standard))
    var widths: [String: CGFloat] = [:]

    static let limit = 48

    func listing(_ path: String) -> ColumnListing? { listings[path] }

    @discardableResult
    func put(_ listing: ColumnListing) -> ColumnListing {
        var l = listing
        l.id = nextID
        nextID += 1
        listings[l.path] = l
        used.removeAll { $0 == l.path }
        used.append(l.path)
        // The least recently read go first, never a folder on screen.
        while listings.count > Self.limit, let old = used.first(where: { !shownPaths.contains($0) }) {
            used.removeAll { $0 == old }
            listings.removeValue(forKey: old)
        }
        return l
    }

    /// Folders changed on disk (FilePaths.folderKey values; nil for any folder): their listings are marked
    /// stale, so the columns read them again (a column still opens at once meanwhile). True when any were.
    @discardableResult
    func forget(_ folderKeys: Set<String>?) -> Bool {
        let hit = listings.values.filter { !$0.stale && (folderKeys?.contains($0.folderKey) ?? true) }.map(\.path)
        for path in hit { listings[path]?.stale = true }
        if !hit.isEmpty { cachedVersion = -1 }
        return !hit.isEmpty
    }

    /// F5, or leaving the Columns view: every listing goes.
    func clear() {
        listings = [:]
        used = []
        cachedVersion = -1
    }

    /// Leaving the Columns view: the next time it opens it starts afresh.
    func reset() {
        root = nil
        shownFolder = nil
        shownPaths = []
        pathFolders = []
        pendingEnter = nil
        widths = [:]
    }
}

/// What a column asks of its window: how to fill a row, drops, type-to-select and widths.
@MainActor
protocol ColumnHost: AnyObject {
    func columnCell(_ cell: NameCellView, for entry: FileEntry, key: String)
    func columnValidateDrop(_ column: ColumnView, _ info: NSDraggingInfo, row: Int) -> NSDragOperation
    func columnAcceptDrop(_ column: ColumnView, _ info: NSDraggingInfo, row: Int) -> Bool
    func columnTypeSelect(_ text: String, at time: TimeInterval)
    /// A divider dragged (`done` once the mouse comes up).
    func columnWidthChanged(_ column: ColumnView, done: Bool)
    /// A divider double-clicked: the column fits its widest name.
    func columnFit(_ column: ColumnView)
}

/// The Columns view (Finder's column view in D4's look): a column per folder from the first to the current
/// one, then a selected folder's contents or a selected file's preview, side by side on the pane colour
/// with hairlines between them. The strip scrolls sideways; each column scrolls on its own.
final class ColumnBrowserView: NSView {
    let scroll = NSScrollView()
    private let strip = FlippedView()
    private(set) var columns: [ColumnView] = []
    private var dividers: [ColumnDivider] = []
    let preview = ColumnPreviewView(frame: .zero)
    private(set) var showsPreview = false
    static let previewMin: CGFloat = 300
    /// A drag is over the columns: nothing scrolls or shifts under it (a spring-loaded folder opening must
    /// not slide another column under the pointer).
    var holdsStill = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = strip
        addSubview(scroll)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// The current folder's column: the window's selection and keys act on it.
    var activeColumn: ColumnView? { columns.last { $0.isActive } }

    func column(for path: String) -> ColumnView? { columns.first { $0.path == path } }

    /// Puts these columns in place (views of folders still shown are kept, with their scroll places), and
    /// the preview after them or not. True when the columns or the preview changed.
    @discardableResult
    func setColumns(_ list: [ColumnView], preview showPreview: Bool) -> Bool {
        let changed = list.map(ObjectIdentifier.init) != columns.map(ObjectIdentifier.init) || showPreview != showsPreview
        for c in columns where !list.contains(where: { $0 === c }) { c.removeFromSuperview() }
        // New columns go in beside their neighbours, so the views (and what VoiceOver reads) run left to
        // right; the ones kept are never taken out (a press may be tracking a drag in one).
        for (i, c) in list.enumerated() where c.superview !== strip {
            if i > 0 {
                strip.addSubview(c, positioned: .above, relativeTo: list[i - 1])
            } else {
                strip.addSubview(c, positioned: .below, relativeTo: list.dropFirst().first { $0.superview === strip })
            }
        }
        columns = list
        showsPreview = showPreview
        if showPreview {
            if preview.superview !== strip { strip.addSubview(preview, positioned: .above, relativeTo: list.last) }
        } else if preview.superview != nil {
            preview.removeFromSuperview()
        }
        while dividers.count < list.count { dividers.append(ColumnDivider(frame: .zero)) }
        while dividers.count > list.count { dividers.removeLast().removeFromSuperview() }
        for (d, c) in zip(dividers, list) { d.column = c }
        // The handles sit above every column, so each takes the press on either side of its hairline.
        let views = strip.subviews
        let lowestHandle = views.firstIndex { $0 is ColumnDivider } ?? views.count
        let highestColumn = views.lastIndex { !($0 is ColumnDivider) } ?? -1
        if lowestHandle < highestColumn || dividers.contains(where: { $0.superview !== strip }) {
            for d in dividers { strip.addSubview(d) }
        }
        layoutStrip()
        return changed
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        layoutStrip()
    }

    func layoutStrip() {
        let clip = scroll.contentSize
        let h = max(0, clip.height)
        var x: CGFloat = 0
        for (c, d) in zip(columns, dividers) {
            c.frame = NSRect(x: x, y: 0, width: c.width, height: h)
            x += c.width
            d.frame = NSRect(x: x - 3, y: 0, width: 6, height: h)
        }
        if showsPreview {
            let w = max(Self.previewMin, clip.width - x)
            preview.frame = NSRect(x: x, y: 0, width: w, height: h)
            x += w
        }
        var width = max(x, clip.width)
        if holdsStill { width = max(width, scroll.contentView.bounds.maxX) }
        let size = NSSize(width: width, height: h)
        if strip.frame.size != size { strip.setFrameSize(size) }
    }

    /// Scrolls sideways so the last column (or the preview) is in view, and the current column too when
    /// both fit.
    func reveal() {
        guard !holdsStill else { return }
        layoutStrip()
        let clip = scroll.contentView.bounds
        guard clip.width > 0, let last: NSView = showsPreview ? preview : columns.last else { return }
        var x = clip.minX
        if last.frame.maxX > clip.maxX { x = last.frame.maxX - clip.width }
        if let active = activeColumn, active.frame.minX < x, last.frame.maxX - active.frame.minX <= clip.width { x = active.frame.minX }
        if let first = columns.first, first.frame.minX > x - 1, x < 0 { x = 0 }
        x = max(0, min(x, strip.frame.width - clip.width))
        guard abs(x - clip.minX) > 0.5 else { return }
        scroll.contentView.scroll(to: NSPoint(x: x, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// A drag moved to another column: the old one's highlight goes.
    func clearDrops(except keep: ColumnView? = nil) {
        for c in columns where c !== keep {
            c.dropRow = -1
            c.isDropTarget = false
        }
    }

    func forEachTable(_ body: (ColumnTableView) -> Void) { columns.forEach { body($0.table) } }

    override func draw(_ dirtyRect: NSRect) {
        fillRect(bounds, Palette.current.pane)
    }
}

/// One column: its folder's items in a single-column table (D4 rows: the type-hued icon, the name in
/// Geist 500, a chevron on folders), a hairline at its right edge.
final class ColumnView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let path: String
    let url: URL
    let scroll = ColumnScrollView()
    let table = ColumnTableView()
    weak var host: ColumnHost?
    var width: CGFloat
    private(set) var rows: [FileEntry] = []
    private(set) var keys: [String] = []
    /// What `rows` came from ("l" and a listing's id, "e" and the list's version), to reload only on change.
    private(set) var token = ""
    /// The current folder's column: the window's selection, keys and menus act on it. The others light
    /// the item that leads on, quieter.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            table.isActiveColumn = isActive
            // Only the current column shows the keyboard focus ring; the others light their path row, quieter.
            table.enumerateAvailableRowViews { view, row in
                guard let view = view as? FolioRowView else { return }
                view.quiet = !isActive
                view.isFocusRow = isActive && row == focusRow
            }
        }
    }
    /// Explorer's focus rectangle (Ctrl+arrows), in the current column.
    var focusRow: Int? {
        didSet {
            guard focusRow != oldValue else { return }
            table.enumerateAvailableRowViews { view, row in (view as? FolioRowView)?.isFocusRow = isActive && row == focusRow }
        }
    }
    /// An empty folder, or why it could not be read.
    var message: String? { didSet { if message != oldValue { needsDisplay = true } } }
    /// The folder row lit under a drag, or the whole column (its own folder) as the target.
    var dropRow = -1 {
        didSet {
            guard dropRow != oldValue else { return }
            table.enumerateAvailableRowViews { view, row in (view as? FolioRowView)?.isDropTarget = row == dropRow }
        }
    }
    var isDropTarget = false { didSet { if isDropTarget != oldValue { overlay.lit = isDropTarget; overlay.needsDisplay = true } } }
    private let overlay = ColumnDropOverlay()
    /// The lit name in a column that is not the current one, and where it was found (rows can be 50,000 long).
    private var litName: String?
    private var litToken = ""
    private var litIndex: Int?

    init(path: String, url: URL, width: CGFloat) {
        self.path = path
        self.url = url
        self.width = width
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(SortKey.name.rawValue))
        column.resizingMask = []
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.focusRingType = .none
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = true
        table.allowsTypeSelect = false
        table.allowsColumnResizing = false
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.rowHeight = ListOptions.compact ? ListMetrics.compactRowHeight : ListMetrics.rowHeight
        table.dataSource = self
        table.delegate = self
        table.column = self
        table.registerForDraggedTypes(droppableTypes)
        table.draggingDestinationFeedbackStyle = .none
        scroll.documentView = table
        addSubview(scroll)
        addSubview(overlay)
        let name = url.path == "/" ? "/" : url.lastPathComponent
        table.setAccessibilityLabel("Column " + name)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        scroll.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - 1), height: bounds.height)
        overlay.frame = bounds
        // The cells stop short of the folder chevron the row draws at its right edge.
        let w = max(40, scroll.contentSize.width - FolioRowView.chevronRoom)
        if let column = table.tableColumns.first, abs(column.width - w) > 0.5 { column.width = w }
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.pane)
        // The hairline between columns.
        fillRect(NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height), p.line)
        if rows.isEmpty, let message {
            drawLine(message, font: Typeface.ui(12), color: p.muted, x: ListMetrics.rowLead, midY: 22, maxWidth: bounds.width - 2 * ListMetrics.rowLead)
        }
    }

    /// New rows (a listing, or the window's list for the current column); nothing happens for the same ones.
    func setRows(_ rows: [FileEntry], keys: [String], token: String) {
        guard token != self.token else { return }
        self.rows = rows
        self.keys = keys
        self.token = token
        table.reloadData()
        needsDisplay = true
    }

    /// The rows lit: the selection in the current column, the folder that leads on in the others.
    func light(_ lit: IndexSet) {
        guard table.selectedRowIndexes != lit else { return }
        table.selectRowIndexes(lit, byExtendingSelection: false)
    }

    /// Where `name` is in the rows (remembered until the rows change). True when it moved.
    func index(ofName name: String?) -> (index: Int?, moved: Bool) {
        if name == litName, token == litToken { return (litIndex, false) }
        let old = litIndex
        litName = name
        litToken = token
        litIndex = name.flatMap { n in rows.firstIndex { $0.name == n } }
        return (litIndex, litIndex != old)
    }

    func applyRowHeight(_ h: CGFloat) {
        guard table.rowHeight != h else { return }
        table.rowHeight = h
        if !rows.isEmpty { table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count)) }
    }

    /// Redraws the rows on screen with what is known now (tags, cut items, options).
    func reloadVisible() {
        let visible = table.rows(in: table.visibleRect)
        guard visible.length > 0 else { return }
        table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)), columnIndexes: IndexSet(integer: 0))
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("columnRow")
        let view = tableView.makeView(withIdentifier: id, owner: self) as? FolioRowView
            ?? { let v = FolioRowView(); v.identifier = id; return v }()
        view.columnStyle = true
        view.quiet = !isActive
        view.item = rows.indices.contains(row) ? FolioRowView.Item(name: rows[row].name, isFolder: rows[row].isFolder) : nil
        view.isFocusRow = isActive && focusRow == row
        view.isDropTarget = row == dropRow
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let id = NSUserInterfaceItemIdentifier(SortKey.name.rawValue)
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NameCellView
            ?? { let c = NameCellView(); c.identifier = id; return c }()
        cell.entry = rows[row]
        cell.showsCheckbox = false
        cell.highlights = []
        host?.columnCell(cell, for: rows[row], key: keys[row])
        cell.themeDidChange()
        return cell
    }

    // MARK: Drops: on a folder row, or anywhere else for this column's own folder

    private func dropRow(for info: NSDraggingInfo) -> Int { table.row(at: table.convert(info.draggingLocation, from: nil)) }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        let op = host?.columnValidateDrop(self, info, row: dropRow(for: info)) ?? []
        tableView.setDropRow(dropRow, dropOperation: .on)
        return op
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        host?.columnAcceptDrop(self, info, row: dropRow(for: info)) ?? false
    }
}

/// A column's table: the Details table's rows and clicks (FolioTableView), with letters typed going to
/// the window's type-to-select.
final class ColumnTableView: FolioTableView {
    weak var column: ColumnView?
    var isActiveColumn = false

    /// A press in a column that is not the current one makes its folder the current one first (with the
    /// item under the pointer selected), so the click, the drag or the menu that follows acts there.
    private func activate(for event: NSEvent) -> Bool {
        guard !isActiveColumn, let column, let router = listDelegate as? ColumnRouter else { return true }
        let row = row(at: convert(event.locationInWindow, from: nil))
        window?.makeFirstResponder(self)
        router.press(column, row: row >= 0 ? row : nil)
        return isActiveColumn
    }

    override func mouseDown(with event: NSEvent) {
        let wasActive = isActiveColumn
        guard activate(for: event) || event.modifierFlags.contains(.control) else { return }
        // Cmd or Shift on another column's item: that item, selected; the modifier has nothing to add to yet.
        if !wasActive, !event.modifierFlags.intersection([.command, .shift]).isEmpty { return }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        _ = activate(for: event)
        super.rightMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Arrows, Return, Space and the rest are the window's (BrowserWindow.sendEvent); letters select.
        if let text = event.characters, let scalar = text.unicodeScalars.first,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           scalar.value >= 0x20, scalar.value != 0x7F, scalar.value < 0xF700 {
            column?.host?.columnTypeSelect(text, at: event.timestamp)
            return
        }
        super.keyDown(with: event)
    }
}

/// A column's own vertical scrolling; a mostly sideways swipe goes to the strip, which scrolls the columns.
final class ColumnScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), let outer = superview?.enclosingScrollView {
            outer.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }
}

/// The handle on the hairline between two columns: drag to resize the column on its left, double-click
/// to fit it to its widest name.
final class ColumnDivider: NSView {
    weak var column: ColumnView?

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    override func mouseDown(with event: NSEvent) {
        guard let column, let window else { return }
        if event.clickCount >= 2 {
            column.host?.columnFit(column)
            return
        }
        let startX = event.locationInWindow.x, startW = column.width
        var moved = false
        while let next = MouseTracking.next(window, [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            column.width = CGFloat(ColumnWidth.clamp(Double(startW + next.locationInWindow.x - startX)))
            moved = true
            column.host?.columnWidthChanged(column, done: false)
        }
        if moved { column.host?.columnWidthChanged(column, done: true) }
    }
}

/// A drag over a column's background: its own folder is the target (an accent outline, the soft halo).
private final class ColumnDropOverlay: NSView {
    var lit = false
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard lit else { return }
        let p = Palette.current
        fillRect(bounds.insetBy(dx: 1, dy: 1), p.accentSoft.withAlpha(p.accentSoft.a / 2))
        strokeRounded(bounds.insetBy(dx: 2, dy: 2), radius: 8, p.accent, width: 2)
    }
}

/// The preview column for a selected file (Finder's preview column) as a D4 spotlight card: the Quick
/// Look thumbnail or the type icon, the name and kind, then Kind, Size, Created, Modified and Tags as
/// mono uppercase keys over their values.
final class ColumnPreviewView: NSView {
    private(set) var entry: FileEntry?
    private var fields: [(key: String, value: String)] = []
    private var tagColors: [TagColor] = []
    var thumbnail: NSImage? { didSet { needsDisplay = true } }
    static let cardMax: CGFloat = 380
    private static let pad: CGFloat = 16
    private static let headH: CGFloat = 38

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Preview")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func show(_ entry: FileEntry, fields: [(key: String, value: String)], tags: [TagColor]) {
        if self.entry?.url != entry.url { thumbnail = nil }
        self.entry = entry
        self.fields = fields
        tagColors = tags
        setAccessibilityValue(([entry.name] + fields.map { "\($0.key): \($0.value)" }).joined(separator: "; "))
        needsDisplay = true
    }

    private var card: NSRect {
        let w = min(Self.cardMax, bounds.width - 2 * 14)
        return NSRect(x: 14, y: 14, width: max(0, w), height: max(0, bounds.height - 28))
    }

    /// Everything in the card but the thumbnail: the label, the gaps, the name and kind, the fields.
    private var textHeight: CGFloat { Self.headH + 14 + 16 + 22 + 24 + 8 + CGFloat(fields.count) * 38 + 10 }

    /// The thumbnail's square: up to 240 pt, smaller when the column is short, so every line fits.
    private var imageSide: CGFloat { max(48, min(card.width - 2 * Self.pad, 240, card.height - textHeight)) }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.pane)
        guard let entry else { return }
        let c = card
        let side = imageSide
        let keyFont = Typeface.mono(12, weight: 600), valueFont = Typeface.mono(12)
        let r = NSRect(x: c.minX, y: c.minY, width: c.width, height: min(c.height, textHeight + side))
        // The spotlight card: s1, a hairline, radius 12, a mono uppercase label.
        fillRounded(r, radius: 12, p.s1)
        strokeRounded(r, radius: 12, p.line)
        drawLine("PREVIEW", font: keyFont, color: p.muted, x: r.minX + 14, midY: r.minY + Self.headH / 2, kern: Typeface.labelKern(12))
        fillRect(NSRect(x: r.minX + 1, y: r.minY + Self.headH - 1, width: r.width - 2, height: 1), p.line)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).addClip()
        let box = NSRect(x: r.midX - side / 2, y: r.minY + Self.headH + 14, width: side, height: side)
        if let thumbnail {
            let size = thumbnail.size
            let scale = min(box.width / max(1, size.width), box.height / max(1, size.height))
            let w = size.width * scale, h = size.height * scale
            let frame = NSRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h).integral
            thumbnail.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            strokeRounded(frame.insetBy(dx: -0.5, dy: -0.5), radius: 2, p.line2)
        } else {
            let s = side * 0.55
            ItemIcon.draw(name: entry.name, isFolder: entry.isFolder, in: NSRect(x: box.midX - s / 2, y: box.midY - s / 2, width: s, height: s),
                          palette: p, glow: true)
        }
        var y = box.maxY + 16
        let nameFont = Typeface.ui(15, weight: 600)
        let maxW = r.width - 2 * Self.pad
        let nw = min(textWidth(entry.name, font: nameFont), maxW)
        drawLine(entry.name, font: nameFont, color: p.text, x: r.midX - nw / 2, midY: y + 11, maxWidth: maxW)
        y += 22
        let kind = entry.isFolder ? "Folder" : entry.kind
        let kw = min(textWidth(kind, font: Typeface.ui(12)), maxW)
        drawLine(kind, font: Typeface.ui(12), color: p.muted, x: r.midX - kw / 2, midY: y + 9, maxWidth: maxW)
        y += 18 + 6
        fillRect(NSRect(x: r.minX + Self.pad, y: y, width: maxW, height: 1), p.line)
        y += 8
        for f in fields {
            drawLine(f.key.uppercased(), font: keyFont, color: p.muted, x: r.minX + Self.pad, midY: y + 8.5, kern: Typeface.labelKern(12))
            var x = r.minX + Self.pad
            if f.key == "Tags", !tagColors.isEmpty {
                x += TagDots.draw(tagColors, x: x, midY: y + 27, p) + 6
            }
            drawLine(f.value, font: valueFont, color: p.text2, x: x, midY: y + 27, maxWidth: r.maxX - Self.pad - x)
            y += 38
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
