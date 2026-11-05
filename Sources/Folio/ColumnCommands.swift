import AppKit
import FolioCore

/// The header's right-click menu, Size column to fit, Size all columns to fit and Choose details.
extension BrowserWindowController {
    /// Size column to fit and Size all columns to fit, ticks for the common columns, More...
    func headerMenu(_ column: ColumnID?) -> NSMenu? {
        let menu = NSMenu(title: "Columns")
        menu.font = Typeface.mono(13)
        menu.autoenablesItems = true
        func add(_ title: String, _ action: Selector, _ object: Any? = nil, key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.representedObject = object
            menu.addItem(item)
        }
        add("Size column to fit", #selector(sizeColumnToFit(_:)), column?.rawValue)
        add("Size all columns to fit", #selector(sizeAllColumnsToFit(_:)), key: "=")
        menu.addItem(.separator())
        let set = ColumnCenter.shared.set
        let listed = ColumnID.allCases.filter { $0.isCommon || set.isVisible($0) }
        for c in listed { add(columnTitle(c), #selector(toggleColumn(_:)), c.rawValue) }
        menu.addItem(.separator())
        add("More...", #selector(chooseDetails(_:)))
        return menu
    }

    @objc func toggleColumn(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let c = ColumnID(rawValue: raw) else { return }
        ColumnCenter.shared.update { $0.toggle(c) }
    }

    @objc func sizeColumnToFit(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let c = ColumnID(rawValue: raw), c != .name,
              let column = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(raw)) else { return }
        column.width = fitWidth(of: c)
    }

    /// Explorer's Ctrl+Numpad + (Cmd+= here): a one-off fit of every column to what it shows now.
    @objc func sizeAllColumnsToFit(_ sender: Any?) {
        for column in tableView.tableColumns {
            guard let c = ColumnID(rawValue: column.identifier.rawValue), c != .name else { continue }
            column.width = fitWidth(of: c)
        }
        fitColumns()
    }

    /// The widest value the column shows (and its header with the sort and filter slots), at most 600.
    func fitWidth(of c: ColumnID) -> CGFloat {
        let head = textWidth(columnTitle(c), font: Typeface.ui(12, weight: 650, width: 116), kern: 0.24) + 14 + 6 + 15 + FolioHeaderView.chevronW
        let font = c.isMono ? Typeface.mono(12) : Typeface.ui(13)
        var widest: CGFloat = 0
        var seen = Set<String>()
        for e in entries.prefix(5000) {
            let meta = c.needsMetadata ? MetadataCache.shared.cached(e) : nil
            let text = ColumnValues.text(e, c, meta)
            guard !text.isEmpty, seen.insert(text).inserted else { continue }
            widest = max(widest, textWidth(text, font: font))
        }
        if c == .name { widest += 18 + 8 + 30 }
        return min(600, max(48, ceil(max(head, widest + 6))))
    }

    /// More... in the header menu: every column with a box, Move up, Move down and the width in pixels.
    @objc func chooseDetails(_ sender: Any?) {
        guard let window else { return }
        let panel = ColumnChooserPanel(set: ColumnCenter.shared.set, title: { [weak self] in self?.columnTitle($0) ?? $0.title })
        panel.onDone = { [weak self, weak window] result in
            if let result {
                ColumnCenter.shared.update { $0 = result }
                self?.rebuildColumns()
            }
            if let sheet = panel.window, let window { window.endSheet(sheet) }
        }
        if let sheet = panel.window {
            window.beginSheet(sheet)
            panel.focusList()
        }
        columnChooser = panel
    }
}

/// Choose Details: Explorer's dialog in D1 dress. The shown columns come first in their order, then
/// all the others alphabetically; Name is always on and greyed.
@MainActor
final class ColumnChooserPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private(set) var window: NSPanel?
    var onDone: ((ColumnSet?) -> Void)?
    private var chooser: ColumnChooser
    private var set: ColumnSet
    private let titleOf: (ColumnID) -> String
    private let table = ChooserTable()
    private let width = NSTextField(string: "")
    private let up: D1Button
    private let down: D1Button

    init(set: ColumnSet, title: @escaping (ColumnID) -> String) {
        self.set = set
        chooser = ColumnChooser(set)
        titleOf = title
        up = D1Button("Move Up")
        down = D1Button("Move Down")
        super.init()
        build()
    }

    private func build() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Choose Details"
        let root = ChooserBackground(frame: panel.contentRect(forFrameRect: panel.frame))
        panel.contentView = root
        let title = label("CHOOSE DETAILS", font: Typeface.ui(13, weight: 700, width: 116), color: Palette.current.accent)
        title.frame = NSRect(x: 20, y: 14, width: 300, height: 20)
        let intro = label("Select the details you want to display for the items in every folder.", font: Typeface.ui(13), color: Palette.current.txt2)
        intro.frame = NSRect(x: 20, y: 36, width: 430, height: 20)
        let head = label("Details:", font: Typeface.ui(12, weight: 650, width: 116), color: Palette.current.txt2)
        head.frame = NSRect(x: 20, y: 54, width: 200, height: 16)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 72, width: 300, height: 360))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        column.width = 280
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 26
        table.backgroundColor = .clear
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Details")
        // Type a column's name to find it, Space to tick or untick it.
        table.onSpace = { [weak self] in
            guard let self, let c = self.selected, c != .name, let row = self.table.selectedRow as Int? else { return }
            self.chooser.setChecked(c, !self.chooser.checked.contains(c))
            self.table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        }
        scroll.documentView = table
        let frame = WellView(frame: scroll.frame.insetBy(dx: -1, dy: -1))
        up.frame = NSRect(x: 336, y: 72, width: 114, height: 34)
        down.frame = NSRect(x: 336, y: 114, width: 114, height: 34)
        up.onPress = { [weak self] in self?.move(up: true) }
        down.onPress = { [weak self] in self?.move(up: false) }
        let wl = label("Width of selected column (in pixels):", font: Typeface.ui(13), color: Palette.current.txt)
        wl.frame = NSRect(x: 20, y: 446, width: 250, height: 20)
        width.frame = NSRect(x: 272, y: 444, width: 60, height: 24)
        width.font = Typeface.mono(12)
        width.delegate = self
        width.setAccessibilityLabel("Width of selected column")
        let ok = D1Button("OK", style: .primary) { [weak self] in self?.finish(true) }
        let cancel = D1Button("Cancel") { [weak self] in self?.finish(false) }
        ok.frame = NSRect(x: 254, y: 476, width: 96, height: 32)
        cancel.frame = NSRect(x: 356, y: 476, width: 96, height: 32)
        ok.keyEquivalent = "\r"
        cancel.keyEquivalent = "\u{1b}"
        for v in [title, intro, head, frame, scroll, up, down, wl, width, ok, cancel] as [NSView] { root.addSubview(v) }
        panel.initialFirstResponder = table
        window = panel
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        syncControls()
    }

    /// The list takes the keys: type a column's name, Space ticks it, Return is OK.
    func focusList() { window?.makeFirstResponder(table) }

    private func label(_ text: String, font: NSFont, color: RGBA) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.textColor = color.ns
        return l
    }

    private var selected: ColumnID? {
        let r = table.selectedRow
        return chooser.order.indices.contains(r) ? chooser.order[r] : nil
    }

    private func move(up: Bool) {
        guard let c = selected else { return }
        let moved = up ? chooser.moveUp(c) : chooser.moveDown(c)
        guard moved, let i = chooser.order.firstIndex(of: c) else { return }
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        table.scrollRowToVisible(i)
    }

    private func syncControls() {
        guard let c = selected else { return }
        width.stringValue = "\(Int(set.width(of: c)))"
        width.isEnabled = c != .name
        let i = chooser.order.firstIndex(of: c) ?? 0
        up.isEnabled = i > 0
        down.isEnabled = i < chooser.order.count - 1
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let c = selected, c != .name, let w = Double(width.stringValue), w >= 20, w <= 2000 else { return }
        set.setWidth(w, of: c)
    }

    private func finish(_ ok: Bool) {
        onDone?(ok ? chooser.applied(to: set) : nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { chooser.order.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = chooser.order[row]
        let check = D1Check(titleOf(c)) { [weak self] on in
            self?.chooser.setChecked(c, on)
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        }
        check.isChecked = chooser.checked.contains(c)
        check.isEnabled = c != .name
        check.frame = NSRect(x: 8, y: 3, width: 260, height: 20)
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        holder.addSubview(check)
        return holder
    }

    func tableViewSelectionDidChange(_ notification: Notification) { syncControls() }

    /// D1's selected row (selection fill and accent brackets), not the system's blue.
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { FolioRowView() }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        titleOf(chooser.order[row])
    }

    final class ChooserTable: NSTableView {
        var onSpace: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 49, event.modifierFlags.intersection([.command, .option, .control]).isEmpty { onSpace?(); return }
            super.keyDown(with: event)
        }
    }

    private final class ChooserBackground: NSView {
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            let p = Palette.current
            fillRect(bounds, p.s1)
            drawBrackets(bounds.insetBy(dx: 6, dy: 6), color: p.bracket.ns, length: 12)
        }
    }

    private final class WellView: NSView {
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            let p = Palette.current
            fillRounded(bounds, radius: 4, p.s2)
            strokeRounded(bounds, radius: 4, p.line2)
        }
    }
}
