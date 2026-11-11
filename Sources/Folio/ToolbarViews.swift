import AppKit
import FolioCore

/// Where focus goes when the address bar stops editing.
enum FocusMove { case list, next, previous, stay }

/// The breadcrumb address bar (`.addr`). The first crumb is the volume; each crumb jumps to its
/// folder and the arrow after it lists that folder's subfolders, the one on the path marked. Crumbs
/// that do not fit collapse from the left behind «. Clicking empty space, Cmd+L or Option+D turns the
/// crumbs into an editable path with the caret at the end; typing lists matching folders (Tab fills,
/// Enter opens, Esc cancels). The arrow at the right end, or F4, lists recent locations.
final class AddressBarView: NSView, NSTextFieldDelegate {
    var onNavigate: ((URL) -> Void)?
    var onEndEditing: ((FocusMove) -> Void)?
    var onEditingChanged: (() -> Void)?
    /// "No such folder" after Enter on a bad address; nil clears it.
    var onStatus: ((String?) -> Void)?
    var historyPaths: (() -> [String])?
    var dropdown: Dropdown?
    var volumes: [VolumeCapacity] = [] { didSet { if volumes != oldValue { recrumb() } } }
    /// Files dragged onto a crumb move or copy into that folder; hovering opens it.
    weak var dropHost: DropHost?
    /// A typed command (terminal, cmd, an app name) that is not a folder; false when nothing ran.
    var onCommand: ((AddressCommand) -> Bool)?
    /// Middle-click a crumb: that folder in a new background tab.
    var onMiddleClick: ((URL) -> Void)?
    /// \\server\share or smb://... typed: the window mounts it and opens it.
    var onServer: ((ServerTarget) -> Bool)?
    /// Header filters on the list, as tokens after the crumbs ("Type: Folder ✕"), Explorer's criteria
    /// in the address bar. The ✕ clears that column's filter.
    var tokens: [FilterToken] = [] {
        didSet {
            guard tokens != oldValue else { return }
            rebuildAccessibility()
            needsDisplay = true
            superview?.needsLayout = true
        }
    }
    var onClearToken: ((ColumnID) -> Void)?
    private var dropCrumb: Int? { didSet { if dropCrumb != oldValue { needsDisplay = true } } }
    /// A search is shown: "Search Results in <folder>" replaces the crumbs (D4's search step).
    var searchTitle: String? {
        didSet {
            guard searchTitle != oldValue else { return }
            rebuildAccessibility()
            needsDisplay = true
        }
    }
    /// The bar that fills the address bar while results gather; `searchDone` fades it.
    var searchProgress: Double = 0 { didSet { if searchProgress != oldValue { needsDisplay = true; updateSearchAccessibility() } } }
    var searchDone = false { didSet { if searchDone != oldValue { needsDisplay = true; updateSearchAccessibility() } } }
    private var searchElement: AddressPart?

    private(set) var folder = URL(fileURLWithPath: "/")
    private(set) var crumbs: [Crumb] = []
    private var hovered: Part?
    private var isHovered = false
    private(set) var isEditing = false
    private(set) var isInvalid = false
    /// Typeahead matches shown and in all, for the HUD's Matches readout.
    private(set) var matchCount = (shown: 0, total: 0)
    private let field = NSTextField(string: "")
    private var completion: Completion?
    private var folderCache: [String: [Subfolder]] = [:]
    private var listing: Set<String> = []
    private var axParts: [AddressPart] = []
    private var axKey: [String] = []

    /// D4's `.addr` padding: the crumbs start 4 pt in; the field and the search title 12 pt in.
    static let iconWidth: CGFloat = 4
    /// `.cchev`: 20 pt.
    static let arrowWidth: CGFloat = 20
    static let crumbPad: CGFloat = 7
    static let minHit: CGFloat = 40
    /// The volume crumb is D4's root: the drive glyph alone.
    static let rootWidth: CGFloat = 30

    enum Part: Equatable { case overflow, crumb(Int), arrow(Int), history, empty, token(Int) }
    private struct Slot { let rect: NSRect; let part: Part }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isHidden = true
        field.delegate = self
        field.lineBreakMode = .byTruncatingHead
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setAccessibilityLabel("Address")
        addSubview(field)
        registerForDraggedTypes(droppableTypes)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Address bar")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func show(_ url: URL) {
        folder = url
        if isEditing { endEditing(focus: .list) }
        recrumb()
    }

    private var isHome: Bool { NavigationHistory.isHome(folder) }

    /// The folder a crumb opens (Home's one crumb is Home).
    private func crumbURL(_ i: Int) -> URL {
        crumbs[i].path == NavigationHistory.homePath ? NavigationHistory.home : URL(fileURLWithPath: crumbs[i].path, isDirectory: true)
    }

    private func recrumb() {
        crumbs = isHome ? [Crumb(title: "Home", path: NavigationHistory.homePath, isCurrent: true, isVolume: true)]
            : Breadcrumbs.crumbs(for: folder, volumes: volumes)
        // The Trash reads as Explorer's Recycle Bin.
        if let last = crumbs.last, RecycleBin.isTrash(URL(fileURLWithPath: last.path), home: FileManager.default.homeDirectoryForCurrentUser) {
            crumbs[crumbs.count - 1] = Crumb(title: "Recycle Bin", path: last.path, isCurrent: last.isCurrent)
        }
        rebuildAccessibility()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if isEditing { placeField() }
        rebuildAccessibility()
    }

    // MARK: Layout of the crumbs

    private var crumbFont: NSFont { Typeface.ui(13, weight: 500) }
    private var currentFont: NSFont { Typeface.ui(13, weight: 600) }

    /// The root crumb is the volume's glyph (Home keeps its name).
    private func isRoot(_ crumb: Crumb) -> Bool { crumb.isVolume && !isHome }

    private func crumbWidth(_ crumb: Crumb) -> CGFloat {
        isRoot(crumb) ? Self.rootWidth : textWidth(crumb.title, font: crumb.isCurrent ? currentFont : crumbFont) + 2 * Self.crumbPad
    }

    /// The field box: 3 pt in from top and bottom (`.addr::before{inset:3px 0}`).
    private var box: NSRect { bounds.insetBy(dx: 0, dy: 3) }

    private var historyRect: NSRect {
        NSRect(x: bounds.width - 4 - 28, y: 3, width: 28, height: bounds.height - 6)
    }

    private var tokenFont: NSFont { Typeface.ui(12, weight: 500) }

    private func tokenWidth(_ t: FilterToken) -> CGFloat { textWidth(t.text, font: tokenFont) + 10 + 8 + 14 + 6 }

    /// What the tokens take, so the toolbar can make room for them.
    var tokensWidth: CGFloat { tokens.isEmpty ? 0 : tokens.map(tokenWidth).reduce(0, +) + CGFloat(tokens.count) * 6 + 4 }

    /// The ✕ at a token's right end.
    private func clearRect(_ r: NSRect) -> NSRect { NSRect(x: r.maxX - 22, y: r.minY, width: 22, height: r.height) }

    /// The «, crumbs and arrows from the left, the filter tokens, then the empty area and the history arrow.
    private func slots() -> [Slot] {
        let h = bounds.height - 2
        if searchTitle != nil {
            return [Slot(rect: NSRect(x: Self.iconWidth, y: 1, width: max(0, historyRect.minX - Self.iconWidth), height: h), part: .empty),
                    Slot(rect: historyRect, part: .history)]
        }
        let tokenWidths = tokens.map(tokenWidth)
        let tokensTotal = tokens.isEmpty ? 0 : tokenWidths.reduce(0, +) + CGFloat(tokens.count) * 6 + 4
        let end = historyRect.minX - min(tokensTotal, max(0, historyRect.minX - Self.iconWidth - 160))
        let widths = crumbs.map { Double(crumbWidth($0) + Self.arrowWidth) }
        let first = CrumbFit.firstVisible(widths: widths, available: Double(end - Self.iconWidth - Self.minHit),
                                          overflowWidth: Double(Self.arrowWidth))
        var out: [Slot] = []
        var x = Self.iconWidth
        if first > 0 {
            out.append(Slot(rect: NSRect(x: x, y: 1, width: Self.arrowWidth, height: h), part: .overflow))
            x += Self.arrowWidth
        }
        for i in crumbs.indices where i >= first {
            // Only a current crumb too wide on its own is cut short.
            let w = min(crumbWidth(crumbs[i]), max(48, end - Self.minHit - Self.arrowWidth - x))
            out.append(Slot(rect: NSRect(x: x, y: 1, width: w, height: h), part: .crumb(i)))
            guard !isHome else { x += w; continue }
            out.append(Slot(rect: NSRect(x: x + w, y: 1, width: Self.arrowWidth, height: h), part: .arrow(i)))
            x += w + Self.arrowWidth
        }
        if !tokens.isEmpty {
            x += 4
            for (i, w) in tokenWidths.enumerated() {
                let width = min(w, max(60, historyRect.minX - 6 - x))
                guard width > 40 else { break }
                out.append(Slot(rect: NSRect(x: x, y: 8, width: width, height: h - 14), part: .token(i)))
                x += width + 6
            }
        }
        out.append(Slot(rect: NSRect(x: x, y: 1, width: max(0, historyRect.minX - x), height: h), part: .empty))
        out.append(Slot(rect: historyRect, part: .history))
        return out
    }

    private var firstVisible: Int {
        slots().compactMap { if case .crumb(let i) = $0.part { i } else { nil } }.first ?? 0
    }

    private func part(at point: NSPoint) -> (Part, NSRect)? {
        if historyRect.contains(point) { return (.history, historyRect) }
        if isEditing { return nil }
        if point.x < Self.iconWidth { return (.empty, bounds) }
        return slots().first { $0.rect.contains(point) }.map { ($0.part, $0.rect) }
    }

    /// D4's `.addr`: the --field box with a line-2 hairline (outline on hover, accent while editing, coral
    /// for a bad path) at radius 12; the root crumb is the drive glyph in the accent, crumbs in Geist 500
    /// text-2 with the current one 600 in the text colour, chevrons muted (accent and turned when open).
    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRounded(box, radius: 12, p.field)
        if let title = searchTitle, !isEditing {
            drawSearchMode(title, p)
            drawArrow(historyRect, open: dropdown?.isOpen("history") == true, down: true, hot: hovered == .history, p)
            return
        }
        let border: RGBA = isInvalid ? p.miss : isEditing ? p.accent : (isHovered ? p.outline : p.line2)
        strokeRounded(box, radius: 12, border)
        drawArrow(historyRect, open: dropdown?.isOpen("history") == true, down: true, hot: hovered == .history, p)
        if isEditing {
            // `.addr.edit`: the accent folder 12 pt in, then the path in Geist Mono.
            ItemIcon.drawFolder(in: NSRect(x: 12, y: box.midY - 8, width: 16, height: 16), palette: p, lit: false)
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: Self.iconWidth, y: 0, width: historyRect.minX - Self.iconWidth, height: bounds.height)).addClip()
        for slot in slots() {
            let hot = hovered == slot.part
            // `.crumb::after`: currentColor at 9% (hover), inset 9 pt top and bottom, radius 5.
            let wash = NSRect(x: slot.rect.minX, y: 9, width: slot.rect.width, height: bounds.height - 18)
            switch slot.part {
            case .overflow:
                if hot { fillRounded(wash, radius: 5, p.text.withAlpha(0.09)) }
                let open = dropdown?.isOpen("overflow") == true
                Glyph.more.draw(in: NSRect(x: slot.rect.midX - 8, y: box.midY - 8, width: 16, height: 16), color: (open ? p.accent : p.text2).ns)
            case .crumb(let i):
                let crumb = crumbs[i]
                let tone = crumb.isCurrent ? p.text : (hot ? p.text : p.text2)
                if dropCrumb == i {
                    fillRounded(wash, radius: 5, p.markFill)
                    strokeRounded(wash, radius: 5, p.accent)
                } else if hot { fillRounded(wash, radius: 5, tone.withAlpha(0.09)) }
                if isRoot(crumb) {
                    Glyph.drive.draw(in: NSRect(x: slot.rect.midX - 8, y: box.midY - 8, width: 16, height: 16), color: p.accent.ns)
                } else {
                    drawLine(crumb.title, font: crumb.isCurrent ? currentFont : crumbFont, color: tone,
                             x: slot.rect.minX + Self.crumbPad, midY: box.midY, maxWidth: slot.rect.width - 2 * Self.crumbPad)
                }
            case .arrow(let i):
                drawArrow(slot.rect, open: dropdown?.isOpen("crumb:" + crumbs[i].path) == true, down: false, hot: hot, p)
            case .token(let i):
                // A filter token as D4's pressed chip: the accent border over a 14% accent tint.
                let r = slot.rect
                fillRounded(r, radius: 10, p.accent.withAlpha(0.14).over(p.field))
                strokeRounded(r, radius: 10, p.accent)
                drawLine(tokens[i].text, font: tokenFont, color: p.text, x: r.minX + 10, midY: r.midY, maxWidth: r.width - 10 - 24)
                let x = clearRect(r)
                if hot { fillRounded(x.insetBy(dx: 2, dy: 3), radius: 6, p.text.withAlpha(0.10)) }
                Glyph.close.draw(in: NSRect(x: x.midX - 6, y: x.midY - 6, width: 12, height: 12), color: (hot ? p.text : p.text2).ns,
                                 lineWidth: 2)
            case .empty, .history:
                break
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// D4's search address (`.addr.is-search`): the magnifier in the accent and "Search Results in work";
    /// while results gather a 2 pt accent line grows along the field's bottom edge, dimming when done.
    private func drawSearchMode(_ title: String, _ p: Palette) {
        let progress = CGFloat(max(0, min(1, searchProgress)))
        strokeRounded(box, radius: 12, isHovered ? p.outline : p.line2)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: box.insetBy(dx: 1, dy: 1), xRadius: 11, yRadius: 11).addClip()
        let line = NSRect(x: box.minX + 1, y: box.maxY - 3, width: (box.width - 2) * (searchDone ? 1 : progress), height: 2)
        if searchDone {
            fillRect(line, p.accent.withAlpha(0.4))
        } else if progress > 0 {
            withGlow(p.accent, blur: 10) { fillRect(line, p.accent) }
        }
        NSGraphicsContext.restoreGraphicsState()
        Glyph.search.draw(in: NSRect(x: 12, y: box.midY - 8, width: 16, height: 16), color: p.accent.ns)
        drawLine(title, font: Typeface.ui(13, weight: 600), color: p.text, x: 12 + 16 + 8, midY: box.midY,
                 maxWidth: historyRect.minX - 36 - 8)
    }

    /// The search label as an element a test can read: its value says how far the search got.
    private func updateSearchAccessibility() {
        searchElement?.setAccessibilityValue(searchDone ? "done" : "searching \(Int(searchProgress * 100))%")
    }

    /// `.cchev`: a 14 pt chevron, muted; open, it turns to point down in the accent.
    private func drawArrow(_ r: NSRect, open: Bool, down: Bool, hot: Bool, _ p: Palette) {
        if hot || open { fillRounded(NSRect(x: r.minX, y: 9, width: r.width, height: bounds.height - 18), radius: 5, p.text.withAlpha(0.09)) }
        let s: CGFloat = 14
        let icon = NSRect(x: r.midX - s / 2, y: bounds.midY - s / 2, width: s, height: s)
        if down {
            Glyph.chevronDown.draw(in: icon, color: (open ? p.accent : p.muted).ns, rotation: open ? .pi : 0)
        } else {
            Glyph.chevron.draw(in: icon, color: (open ? p.accent : p.muted).ns, rotation: open ? .pi / 2 : 0)
        }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; hovered = nil; needsDisplay = true }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hit = part(at: point)?.0
        let next: Part? = hit == .empty ? nil : hit
        if next != hovered { hovered = next; needsDisplay = true }
        // D4's empty address area takes a text cursor; crumbs and arrows keep the arrow.
        (hit == .empty && !isEditing ? NSCursor.iBeam : NSCursor.arrow).set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let (part, rect) = part(at: convert(event.locationInWindow, from: nil)) else { return }
        switch part {
        case .history: toggleHistory(event)
        case .crumb(let i): onNavigate?(crumbURL(i))
        case .arrow(let i): toggleCrumbMenu(i, at: rect, event)
        case .overflow: toggleOverflow(at: rect, event)
        case .empty: beginEditing()
        case .token(let i):
            if clearRect(rect).contains(convert(event.locationInWindow, from: nil)), tokens.indices.contains(i) {
                onClearToken?(tokens[i].column)
            }
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, let (part, _) = part(at: convert(event.locationInWindow, from: nil)),
              case .crumb(let i) = part else { return super.otherMouseDown(with: event) }
        onMiddleClick?(crumbURL(i))
    }

    // MARK: Dropping on crumbs

    private func crumbIndex(_ info: NSDraggingInfo) -> Int? {
        guard !isEditing, !isHome, let (part, _) = part(at: convert(info.draggingLocation, from: nil)),
              case .crumb(let i) = part else { return nil }
        return i
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation { draggingUpdated(info) }

    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        guard let i = crumbIndex(info), let host = dropHost else {
            clearDrop()
            return []
        }
        let target = URL(fileURLWithPath: crumbs[i].path, isDirectory: true)
        let action = host.dropAction(info, onto: target)
        dropCrumb = action == .none ? nil : i
        host.springLoad(crumbs[i].isCurrent ? nil : target)
        host.showDropTip(action, target: target, info: info)
        return host.dragOperation(for: action, info)
    }

    private func clearDrop() {
        dropCrumb = nil
        dropHost?.springLoad(nil)
        dropHost?.hideDropTip()
    }

    override func draggingExited(_ info: NSDraggingInfo?) { clearDrop() }
    override func draggingEnded(_ info: NSDraggingInfo) { clearDrop() }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        defer { clearDrop() }
        guard let i = dropCrumb, crumbs.indices.contains(i) else { return false }
        return dropHost?.performDrop(info, onto: URL(fileURLWithPath: crumbs[i].path, isDirectory: true)) ?? false
    }

    /// Right-click: Copy address, Copy address as text, Edit address (the window controller does them).
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy Address", action: #selector(BrowserWindowController.copyAddress(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Address as Text", action: #selector(BrowserWindowController.copyAddressAsText(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Edit Address", action: #selector(BrowserWindowController.focusAddressBar(_:)), keyEquivalent: "")
        return menu
    }

    // MARK: Dropdowns from the crumbs

    private func toggleCrumbMenu(_ i: Int, at rect: NSRect, _ event: NSEvent?) {
        guard let dropdown, crumbs.indices.contains(i) else { return }
        let crumb = crumbs[i]
        let id = "crumb:" + crumb.path
        if let event, dropdown.wasJustClosed(id, by: event) { return }
        if dropdown.isOpen(id) { dropdown.close(); return }
        let items = FolderMenu.items(in: URL(fileURLWithPath: crumb.path, isDirectory: true), current: folder)
        let content = DropdownContent(style: .menu, title: "Folders in " + crumb.title,
                                      rows: items.map { DropdownRow(text: $0.name, value: $0.path, isCurrent: $0.isOnPath) },
                                      empty: "No folders to show")
        dropdown.show(content, id: id, below: rect, in: self) { [weak self] row in
            self?.onNavigate?(URL(fileURLWithPath: row.value, isDirectory: true))
        }
        needsDisplay = true
    }

    /// «: the crumbs that did not fit, nearest first.
    private func toggleOverflow(at rect: NSRect, _ event: NSEvent?) {
        guard let dropdown else { return }
        if let event, dropdown.wasJustClosed("overflow", by: event) { return }
        if dropdown.isOpen("overflow") { dropdown.close(); return }
        let hidden = crumbs.prefix(firstVisible).reversed()
        let content = DropdownContent(style: .menu, title: "Collapsed folders",
                                      rows: hidden.map { DropdownRow(text: $0.title, value: $0.path) }, empty: "")
        dropdown.show(content, id: "overflow", below: rect, in: self) { [weak self] row in
            self?.onNavigate?(URL(fileURLWithPath: row.value, isDirectory: true))
        }
        needsDisplay = true
    }

    /// F4 or the arrow at the right end: recent locations under the bar, newest first.
    func toggleHistory(_ event: NSEvent? = nil) {
        guard let dropdown else { return }
        if let event, dropdown.wasJustClosed("history", by: event) { return }
        if dropdown.isOpen("history") { dropdown.close(); return }
        if !isEditing { beginEditing() }
        let paths = historyPaths?() ?? []
        let content = DropdownContent(style: .field(header: "Recent locations", count: "\(paths.count) of \(AddressHistory.limit)"),
                                      title: "Address history", rows: paths.map { DropdownRow(text: $0, value: $0) },
                                      empty: "No recent locations")
        dropdown.show(content, id: "history", below: bounds, in: self) { [weak self] row in self?.open(row.value) }
        dropdown.keepOpenRect = convert(bounds, to: nil)
        needsDisplay = true
    }

    // MARK: Editing

    /// Crumbs become the full path with an accent caret at the end.
    func beginEditing() {
        guard !isEditing, let window else { return }
        dropdown?.close()
        isEditing = true
        isInvalid = false
        hovered = nil
        let p = Palette.current
        field.font = Typeface.mono(13, weight: 500)
        field.textColor = p.text.ns
        field.stringValue = isHome ? "" : folder.path
        placeField()
        field.isHidden = false
        window.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.insertionPointColor = p.accent.ns
            editor.selectedTextAttributes = [.backgroundColor: p.markFill.ns]
            caretToEnd()
        }
        matchCount = (0, 0)
        completion = nil
        rebuildAccessibility()
        needsDisplay = true
        onEditingChanged?()
    }

    func endEditing(focus: FocusMove) {
        guard isEditing else { return }
        isEditing = false
        if let dropdown, dropdown.isOpen("typeahead") || dropdown.isOpen("history") { dropdown.close() }
        field.isHidden = true
        field.abortEditing()
        if isInvalid { isInvalid = false; onStatus?(nil) }
        completion = nil
        folderCache.removeAll()
        rebuildAccessibility()
        needsDisplay = true
        onEditingChanged?()
        onEndEditing?(focus)
    }

    private func placeField() {
        guard let font = field.font else { return }
        let h = ceil(font.ascender - font.descender) + 4
        field.frame = NSRect(x: 12 + 16 + 8, y: (bounds.height - h) / 2, width: historyRect.minX - 4 - 36, height: h)
    }

    private func caretToEnd() {
        guard let editor = field.currentEditor() as? NSTextView else { return }
        let end = NSRange(location: (field.stringValue as NSString).length, length: 0)
        editor.setSelectedRange(end)
        editor.scrollRangeToVisible(end)
    }

    private func setText(_ text: String) {
        field.stringValue = text
        caretToEnd()
        textChanged()
    }

    private func textChanged() {
        if isInvalid { isInvalid = false; onStatus?(nil); needsDisplay = true }
        updateTypeahead()
    }

    func controlTextDidChange(_ notification: Notification) { textChanged() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let fieldList = dropdown.map { $0.isOpen("typeahead") || $0.isOpen("history") } ?? false
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            endEditing(focus: .list)
        case #selector(NSResponder.moveDown(_:)) where fieldList:
            dropdown?.moveHighlight(1)
        case #selector(NSResponder.moveUp(_:)) where fieldList:
            dropdown?.moveHighlight(-1)
        case #selector(NSResponder.insertTab(_:)):
            if let filled = fill() { setText(filled) } else { endEditing(focus: .next) }
        case #selector(NSResponder.insertBacktab(_:)):
            endEditing(focus: .previous)
        case #selector(NSResponder.insertNewline(_:)):
            if fieldList, dropdown?.pickHighlighted() == true { break }
            commit(field.stringValue)
        default:
            return false
        }
        return true
    }

    /// Tab: the highlighted (or first) typeahead match, or history entry, as a path ending in a slash.
    private func fill() -> String? {
        guard let dropdown else { return nil }
        if dropdown.isOpen("typeahead"), let completion { return completion.filled(dropdown.highlighted) }
        if dropdown.isOpen("history"), let rows = dropdown.content?.rows, !rows.isEmpty {
            let path = rows[dropdown.highlighted ?? 0].value
            return path == "/" ? path : path + "/"
        }
        return nil
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        // Focus left the field (a click elsewhere): back to crumbs, focus stays where it went.
        if isEditing { endEditing(focus: .stay) }
    }

    /// Enter: go to the typed folder, or shake and say "No such folder" and stay.
    private func commit(_ text: String) {
        // \\server\share and smb://, afp://, nfs://, WebDAV and FTP addresses mount first.
        if let target = ServerAddress.parse(text), onServer?(target) == true {
            endEditing(focus: .list)
            return
        }
        guard let url = AddressInput.resolve(text, current: folder, env: .current) else {
            endEditing(focus: .list)
            return
        }
        if !open(url.path) {
            // Explorer's address bar also runs commands: terminal, cmd, wt, an app name.
            if let command = AddressCommand.parse(text), onCommand?(command) == true {
                endEditing(focus: .list)
                return
            }
            isInvalid = true
            dropdown?.close()
            onStatus?(StatusText.noSuchFolder)
            shake()
            needsDisplay = true
            onEditingChanged?()
        }
    }

    @discardableResult
    private func open(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        endEditing(focus: .list)
        onNavigate?(URL(fileURLWithPath: path, isDirectory: true))
        return true
    }

    private func shake() {
        guard let layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values = [0, -9, 9, -7, 7, -4, 4, 0]
        a.duration = 0.38
        layer.add(a, forKey: "shake")
    }

    // MARK: Typeahead

    /// Lists the folder the text points into (once per folder, off the main thread) and shows the
    /// matches; the list closes when nothing matches.
    private func updateTypeahead() {
        guard isEditing, dropdown != nil else { return }
        guard let (directory, prefix) = PathCompleter.query(field.stringValue, current: folder, env: .current) else {
            showMatches(nil)
            return
        }
        let key = directory.path
        if let folders = folderCache[key] {
            let (shown, total) = PathCompleter.matches(folders, prefix: prefix)
            showMatches(Completion(directory: directory, prefix: prefix, names: shown, total: total))
        } else if !listing.contains(key) {
            listing.insert(key)
            Task.detached(priority: .userInitiated) { [weak self] in
                let folders = PathCompleter.subfolders(in: directory)
                await self?.listed(folders, key: key)
            }
        }
    }

    private func listed(_ folders: [Subfolder], key: String) {
        listing.remove(key)
        guard isEditing else { return }
        folderCache[key] = folders
        updateTypeahead()
    }

    private func showMatches(_ c: Completion?) {
        guard let dropdown else { return }
        completion = c
        matchCount = (c?.names.count ?? 0, c?.total ?? 0)
        onEditingChanged?()
        guard let c, !c.names.isEmpty else {
            if dropdown.isOpen("typeahead") { dropdown.close() }
            return
        }
        let header = "Folders in " + (c.directory.path == "/" ? (crumbs.first?.title ?? Breadcrumbs.rootTitle) : c.directory.lastPathComponent)
        let content = DropdownContent(style: .field(header: header, count: "\(c.names.count) of \(c.total)"),
                                      title: "Address typeahead",
                                      rows: c.rows.map { DropdownRow(text: $0.path, value: $0.path, boldLength: $0.boldLength) },
                                      empty: "")
        if dropdown.isOpen("typeahead") {
            if dropdown.content != content { dropdown.update(content) }
        } else {
            dropdown.show(content, id: "typeahead", below: bounds, in: self) { [weak self] row in self?.open(row.value) }
            dropdown.keepOpenRect = convert(bounds, to: nil)
        }
    }

    // MARK: Accessibility: every crumb, arrow and the history arrow is a button a test can press.

    /// Kept as long as the crumbs and their frames stay the same, so a test that looks a button up and
    /// then presses it reaches the same element.
    private func rebuildAccessibility() {
        var key: [String] = []
        var parts: [AddressPart] = []
        func add(_ label: String, _ rect: NSRect, _ press: @escaping @MainActor (AddressBarView) -> Void) {
            key.append("\(label)|\(rect)")
            let e = AddressPart()
            e.setAccessibilityRole(.button)
            e.setAccessibilityLabel(label)
            e.setAccessibilityTitle(label)
            e.setAccessibilityParent(self)
            e.setAccessibilityFrameInParentSpace(rect)
            e.press = { [weak self] in if let self { press(self) } }
            parts.append(e)
        }
        if let title = searchTitle, !isEditing {
            let e = AddressPart()
            e.setAccessibilityRole(.staticText)
            e.setAccessibilityLabel(title)
            e.setAccessibilityParent(self)
            e.setAccessibilityFrameInParentSpace(NSRect(x: 36, y: 3, width: historyRect.minX - 36, height: bounds.height - 6))
            e.setAccessibilityValue(searchDone ? "done" : "searching \(Int(searchProgress * 100))%")
            key.append("search|\(title)")
            parts.append(e)
        }
        if !isEditing {
            for slot in slots() {
                switch slot.part {
                case .overflow: add("Collapsed folders", slot.rect) { $0.toggleOverflow(at: slot.rect, nil) }
                case .crumb(let i):
                    let url = crumbURL(i)
                    add(crumbs[i].title, slot.rect) { $0.onNavigate?(url) }
                case .arrow(let i): add("Folders in " + crumbs[i].title, slot.rect) { $0.toggleCrumbMenu(i, at: slot.rect, nil) }
                case .empty: add("Edit address", slot.rect) { $0.beginEditing() }
                case .token(let i):
                    let token = tokens[i]
                    add("Filter " + token.text, NSRect(x: slot.rect.minX, y: slot.rect.minY, width: slot.rect.width - 22,
                                                      height: slot.rect.height)) { _ in }
                    add("Clear filter " + token.text, clearRect(slot.rect)) { $0.onClearToken?(token.column) }
                case .history: break
                }
            }
        }
        add("Address history", historyRect) { $0.toggleHistory() }
        guard key != axKey else { return }
        axKey = key
        axParts = parts
        searchElement = searchTitle == nil ? nil : parts.first { $0.accessibilityRole() == .staticText }
    }

    override func accessibilityChildren() -> [Any]? {
        (isEditing ? [field] : []) + axParts
    }
}

final class AddressPart: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return true }
}

/// D4's 52 pt frosted toolbar (`.toolbar`): Back, Forward, Up, the address bar, the command bar (Explorer's
/// New, Cut, Copy, Paste, Rename, Share, Delete, Sort, View and See more, as `.ib` buttons), Refresh and
/// the search box. Commands that do not fit fold into See more, which always lists everything.
final class ToolbarView: NSView {
    let back: ChromeButton
    let forward: ChromeButton
    let up: ChromeButton
    let refresh: ChromeButton
    let address = AddressBarView(frame: .zero)
    let search = SearchBoxView(frame: .zero)
    /// The search box's left edge: drag it to widen the box (the address bar gives up the room).
    private let searchEdge = SearchEdgeHandle(frame: .zero)
    static let searchWidthKey = "searchBoxWidth"
    /// The width dragged to, kept for every window; nil is the default for the window's width.
    var searchWidth: CGFloat? = UserDefaults.standard.object(forKey: ToolbarView.searchWidthKey) as? CGFloat {
        didSet { needsLayout = true }
    }
    /// Left to right; the last one is See more. Groups end after the indexes in `groupEnds`.
    var commands: [ChromeButton] = [] {
        didSet {
            oldValue.forEach { $0.removeFromSuperview() }
            commands.forEach { addSubview($0) }
            needsLayout = true
        }
    }
    var groupEnds: Set<Int> = []
    private var separators: [CGFloat] = []
    static let commandW: CGFloat = 36
    static let addressMin: CGFloat = 300

    init(target: AnyObject?, back: Selector, forward: Selector, up: Selector, refresh: Selector) {
        self.back = ChromeButton(glyph: .back, label: "Back (Cmd+Left), hold for history", target: target, action: back)
        self.forward = ChromeButton(glyph: .forward, label: "Forward (Cmd+Right), hold for history", target: target, action: forward)
        self.up = ChromeButton(glyph: .up, label: "Up (Cmd+Up)", target: target, action: up)
        self.refresh = ChromeButton(glyph: .refresh, label: "Refresh", target: target, action: refresh)
        super.init(frame: .zero)
        for view in [self.back, self.forward, self.up, address, self.refresh, search, searchEdge] as [NSView] { addSubview(view) }
        address.onEditingChanged = { [weak self] in self?.needsDisplay = true }
        searchEdge.onDrag = { [weak self] x in
            guard let self else { return }
            let w = min(max(180, self.search.frame.maxX - x), max(180, self.bounds.width - Self.addressX - Self.addressMin - 120))
            self.searchWidth = w
            UserDefaults.standard.set(Double(w), forKey: Self.searchWidthKey)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Where the address bar starts: 8 pt in, three 44 pt buttons 4 pt apart, then its 8 pt margin.
    static let addressX: CGFloat = 156

    override func layout() {
        super.layout()
        let y = ((bounds.height - 1 - 44) / 2).rounded()
        back.frame = NSRect(x: 8, y: y, width: 44, height: 44)
        forward.frame = NSRect(x: 56, y: y, width: 44, height: 44)
        up.frame = NSRect(x: 104, y: y, width: 44, height: 44)
        let left = Self.addressX
        // Narrow windows (two side by side) give the search box's room to the address bar.
        let standard: CGFloat = bounds.width < 1180 ? 220 : 280
        let searchW: CGFloat = bounds.width < 720 ? 0
            : min(searchWidth ?? standard, max(standard, bounds.width - left - Self.addressMin - 120))
        search.isHidden = searchW == 0
        search.frame = NSRect(x: bounds.width - 12 - searchW, y: y, width: searchW, height: 44)
        searchEdge.isHidden = search.isHidden
        searchEdge.frame = NSRect(x: search.frame.minX - 4, y: y, width: 8, height: 44)
        refresh.frame = NSRect(x: (searchW == 0 ? bounds.width - 2 : search.frame.minX) - 8 - 44, y: y, width: 44, height: 44)
        // The command bar takes what the address bar can spare; See more is always there.
        var right = refresh.frame.minX - 8
        separators = []
        if let more = commands.last {
            more.frame = NSRect(x: right - Self.commandW, y: y, width: Self.commandW, height: 44)
            right = more.frame.minX - 6
            separators.append(right - 0.5)
            right -= 7
            let rest = commands.dropLast()
            // Filter tokens widen the address bar; the commands that no longer fit fold into See more.
            let room = right - left - max(Self.addressMin, 230 + address.tokensWidth)
            let groups = CGFloat(groupEnds.filter { $0 < rest.count - 1 }.count)
            var fit = rest.count
            while fit > 0, CGFloat(fit) * Self.commandW + groups * 13 > room { fit -= 1 }
            var x = right - CGFloat(fit) * Self.commandW
                - CGFloat(groupEnds.filter { $0 < fit - 1 }.count) * 13
            let left = x
            for (i, button) in rest.enumerated() {
                button.isHidden = i >= fit
                guard i < fit else { continue }
                button.frame = NSRect(x: x, y: y, width: Self.commandW, height: 44)
                x += Self.commandW
                if groupEnds.contains(i), i < fit - 1 {
                    separators.append(x + 6.5)
                    x += 13
                }
            }
            if fit == 0 { separators.removeAll() }
            right = fit > 0 ? left - 8 : right + 7
        }
        address.frame = NSRect(x: left, y: y, width: max(80, right - left), height: 44)
    }

    /// `--bar` (s1 at 78% over the bg; white in light) with a hairline under it. While the address is
    /// edited its box carries the accent's 3 pt halo and a soft glow (`.addr.edit::before`).
    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.bar)
        fillRect(NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1), p.line)
        if address.isEditing {
            let tone = address.isInvalid ? p.miss : p.accent
            let box = address.frame.insetBy(dx: 0, dy: 3).insetBy(dx: -3, dy: -3)
            withGlow(tone.withAlpha(0.18), blur: 24) { fillRounded(box, radius: 15, tone.withAlpha(p.accentSoft.a)) }
        }
        for x in separators {
            fillRect(NSRect(x: x, y: (bounds.height - 1) / 2 - 11, width: 1, height: 22), p.line)
        }
    }
}

/// The search box's left edge, a resize cursor and a drag that moves it (Explorer since 1909).
final class SearchEdgeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    override func mouseDown(with event: NSEvent) {
        guard let window, let host = superview else { return }
        while let next = MouseTracking.next(window, [.leftMouseDragged, .leftMouseUp], idle: nil) {
            if next.type == .leftMouseUp { break }
            onDrag?(host.convert(next.locationInWindow, from: nil).x)
        }
    }
}
