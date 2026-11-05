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

    static let iconWidth: CGFloat = 40
    static let arrowWidth: CGFloat = 30
    static let crumbPad: CGFloat = 8
    static let minHit: CGFloat = 40

    enum Part: Equatable { case overflow, crumb(Int), arrow(Int), history, empty }
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

    private func recrumb() {
        crumbs = Breadcrumbs.crumbs(for: folder, volumes: volumes)
        rebuildAccessibility()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if isEditing { placeField() }
        rebuildAccessibility()
    }

    // MARK: Layout of the crumbs

    private var crumbFont: NSFont { Typeface.mono(13, weight: 500) }
    private var currentFont: NSFont { Typeface.mono(13, weight: 600) }

    private func crumbWidth(_ crumb: Crumb) -> CGFloat {
        textWidth(crumb.title, font: crumb.isCurrent ? currentFont : crumbFont) + 2 * Self.crumbPad
    }

    private var historyRect: NSRect {
        NSRect(x: bounds.width - 1 - Self.arrowWidth, y: 1, width: Self.arrowWidth, height: bounds.height - 2)
    }

    /// The «, crumbs and arrows from the left, then the empty area and the history arrow.
    private func slots() -> [Slot] {
        let h = bounds.height - 2
        let end = historyRect.minX
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
            out.append(Slot(rect: NSRect(x: x + w, y: 1, width: Self.arrowWidth, height: h), part: .arrow(i)))
            x += w + Self.arrowWidth
        }
        out.append(Slot(rect: NSRect(x: x, y: 1, width: max(0, end - x), height: h), part: .empty))
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

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        let box = bounds
        fillRounded(box, radius: 5, p.s2)
        let border: RGBA = isInvalid ? p.miss : isEditing ? p.accent : (isHovered ? p.line3 : p.line2)
        strokeRounded(box, radius: 5, border)
        ItemIcon.drawFolder(in: NSRect(x: 11, y: box.midY - 7.5, width: 18, height: 15), palette: p, lit: false)
        drawArrow(historyRect, open: dropdown?.isOpen("history") == true, down: true, hot: hovered == .history, p)
        guard !isEditing else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: Self.iconWidth, y: 0, width: historyRect.minX - Self.iconWidth, height: box.height)).addClip()
        for slot in slots() {
            let hot = hovered == slot.part
            switch slot.part {
            case .overflow:
                if hot { fillRounded(slot.rect, radius: 3, p.txt3.withAlpha(0.08)) }
                let open = dropdown?.isOpen("overflow") == true
                drawLine("\u{00AB}", font: crumbFont, color: open ? p.accent : p.txt3,
                         x: slot.rect.midX - textWidth("\u{00AB}", font: crumbFont) / 2, midY: box.midY)
            case .crumb(let i):
                let crumb = crumbs[i]
                let tone = crumb.isCurrent ? p.accent : p.txt
                if hot { fillRounded(slot.rect, radius: 3, tone.withAlpha(0.08)) }
                drawLine(crumb.title, font: crumb.isCurrent ? currentFont : crumbFont, color: tone,
                         x: slot.rect.minX + Self.crumbPad, midY: box.midY, maxWidth: slot.rect.width - 2 * Self.crumbPad)
            case .arrow(let i):
                drawArrow(slot.rect, open: dropdown?.isOpen("crumb:" + crumbs[i].path) == true, down: false, hot: hot, p)
            case .empty, .history:
                break
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// `.cr-arrow`: a 14 pt chevron in txt3; open, it turns to point down in the accent.
    private func drawArrow(_ r: NSRect, open: Bool, down: Bool, hot: Bool, _ p: Palette) {
        if hot && !open { fillRounded(r, radius: 3, p.txt3.withAlpha(0.08)) }
        let s: CGFloat = 14
        let icon = NSRect(x: r.midX - s / 2, y: bounds.midY - s / 2, width: s, height: s)
        if down {
            Glyph.chevronDown.draw(in: icon, color: (open ? p.accent : p.txt3).ns, rotation: open ? .pi : 0)
        } else {
            Glyph.chevron.draw(in: icon, color: (open ? p.accent : p.txt3).ns, rotation: open ? .pi / 2 : 0)
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
        // D1's empty address area takes a text cursor; crumbs and arrows keep the arrow.
        (hit == .empty && !isEditing ? NSCursor.iBeam : NSCursor.arrow).set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let (part, rect) = part(at: convert(event.locationInWindow, from: nil)) else { return }
        switch part {
        case .history: toggleHistory(event)
        case .crumb(let i): onNavigate?(URL(fileURLWithPath: crumbs[i].path, isDirectory: true))
        case .arrow(let i): toggleCrumbMenu(i, at: rect, event)
        case .overflow: toggleOverflow(at: rect, event)
        case .empty: beginEditing()
        }
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
        field.textColor = p.txt.ns
        field.stringValue = folder.path
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
        field.frame = NSRect(x: Self.iconWidth, y: (bounds.height - h) / 2, width: historyRect.minX - 4 - Self.iconWidth, height: h)
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
        guard let url = AddressInput.resolve(text, current: folder, env: .current) else {
            endEditing(focus: .list)
            return
        }
        if !open(url.path) {
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
        func add(_ label: String, _ rect: NSRect, _ press: @escaping (AddressBarView) -> Void) {
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
        if !isEditing {
            for slot in slots() {
                switch slot.part {
                case .overflow: add("Collapsed folders", slot.rect) { $0.toggleOverflow(at: slot.rect, nil) }
                case .crumb(let i):
                    let path = crumbs[i].path
                    add(crumbs[i].title, slot.rect) { $0.onNavigate?(URL(fileURLWithPath: path, isDirectory: true)) }
                case .arrow(let i): add("Folders in " + crumbs[i].title, slot.rect) { $0.toggleCrumbMenu(i, at: slot.rect, nil) }
                case .empty: add("Edit address", slot.rect) { $0.beginEditing() }
                case .history: break
                }
            }
        }
        add("Address history", historyRect) { $0.toggleHistory() }
        guard key != axKey else { return }
        axKey = key
        axParts = parts
    }

    override func accessibilityChildren() -> [Any]? {
        (isEditing ? [field] : []) + axParts
    }
}

final class AddressPart: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return true }
}

/// The search box, top right (`.search`): "Search <folder>". It does nothing until milestone 7.
final class SearchBoxView: NSView {
    var folderName = "" { didSet { needsDisplay = true; setAccessibilityLabel("Search " + folderName) } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRounded(bounds, radius: 5, p.s2)
        strokeRounded(bounds, radius: 5, p.line2)
        Glyph.search.draw(in: NSRect(x: 12, y: bounds.midY - 9, width: 18, height: 18), color: p.txt2.ns)
        drawLine("Search " + folderName, font: Typeface.ui(13), color: p.txt3, x: 38, midY: bounds.midY,
                 maxWidth: bounds.width - 38 - 8)
    }
}

/// The 56 pt toolbar (`.toolbar`): Back, Forward, Up, the address bar, the command bar (Explorer's New,
/// Cut, Copy, Paste, Rename, Share, Delete, Sort, View and See more, as D1 toolbar buttons), Refresh
/// and the search box. Commands that do not fit fold into See more, which always lists everything.
final class ToolbarView: NSView {
    let back: ChromeButton
    let forward: ChromeButton
    let up: ChromeButton
    let refresh: ChromeButton
    let address = AddressBarView(frame: .zero)
    let search = SearchBoxView(frame: .zero)
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
        for view in [self.back, self.forward, self.up, address, self.refresh, search] as [NSView] { addSubview(view) }
        address.onEditingChanged = { [weak self] in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let y = (bounds.height - 1 - 44) / 2
        back.frame = NSRect(x: 10, y: y, width: 44, height: 44)
        forward.frame = NSRect(x: 56, y: y, width: 44, height: 44)
        up.frame = NSRect(x: 102, y: y, width: 44, height: 44)
        let searchW: CGFloat = bounds.width < 1180 ? 220 : 280
        search.frame = NSRect(x: bounds.width - 10 - searchW, y: y, width: searchW, height: 44)
        refresh.frame = NSRect(x: search.frame.minX - 8 - 44, y: y, width: 44, height: 44)
        // The command bar takes what the address bar can spare; See more is always there.
        var right = refresh.frame.minX - 8
        separators = []
        if let more = commands.last {
            more.frame = NSRect(x: right - Self.commandW, y: y, width: Self.commandW, height: 44)
            right = more.frame.minX - 6
            separators.append(right - 0.5)
            right -= 7
            let rest = commands.dropLast()
            let room = right - 154 - Self.addressMin
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
        address.frame = NSRect(x: 154, y: y, width: max(80, right - 154), height: 44)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.s1)
        fillRect(NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1), p.line)
        if address.isEditing {
            // The 3 pt accent ring around the address bar while editing (`.addr.mode-address`).
            fillRounded(address.frame.insetBy(dx: -3, dy: -3), radius: 8, (address.isInvalid ? p.miss : p.accent).withAlpha(0.16))
        }
        for x in separators {
            fillRect(NSRect(x: x, y: (bounds.height - 1) / 2 - 11, width: 1, height: 22), p.line)
        }
    }
}
