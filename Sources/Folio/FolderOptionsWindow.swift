import AppKit
import FolioCore

/// Explorer's Folder Options (View > Options, See more > Options): General, View and Search tabs with
/// Explorer's wording, each with Restore Defaults; OK, Cancel and Apply. Drawn as a D4 panel (the
/// Properties window's form): spotlight-card groups with mono uppercase labels, D4 check boxes and radios.
/// Settings that mean nothing on a Mac stay in the list, greyed, with "Not on macOS" as their tip.
@MainActor
final class FolderOptionsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: FolderOptionsWindowController?

    static func show(near anchor: NSWindow?, tab: FolderOptions.Tab = .general) {
        if let existing = shared {
            existing.select(tab)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let c = FolderOptionsWindowController()
        shared = c
        if let w = c.window {
            if let anchor {
                let f = anchor.frame
                w.setFrameTopLeftPoint(NSPoint(x: f.midX - w.frame.width / 2, y: f.maxY - 60))
            } else {
                w.center()
            }
        }
        c.select(tab)
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        c.searchBox.focus()
    }

    private var draft = ListOptions.folder
    private var tab = FolderOptions.Tab.general
    /// What the search box holds. While it is not empty, the body lists the matching settings of every tab.
    private var query = ""
    private let searchBox = SearchBoxView(frame: .zero)
    private let header = OptionsHeader()
    private var tabButtons: [FolderOptions.Tab: SegmentButton] = [:]
    private let body = FlippedView()
    private let scroll = NSScrollView()
    private let list = OptionsListView()
    private let restore = OSButton("Restore Defaults", glyph: .refresh)
    private let ok = OSButton("OK", glyph: .check, style: .primary)
    private let cancel = OSButton("Cancel", glyph: .close)
    private let apply = OSButton("Apply")
    /// Every check box and radio on screen, with the setting it shows.
    private var controls: [(NSButton, FolderOptions.Setting)] = []
    /// General's two boxes that change macOS itself at once (not on OK): they show what the Mac reports.
    private var folderHandlerBox: OSCheck?
    private var loginItemBox: OSCheck?
    private var revealBox: OSCheck?

    private init() {
        // 860 wide: General's two columns (milestone 9 added Folio and macOS) fit a 1024 pt screen.
        let window = OptionsWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 660),
                                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Folder Options"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.backgroundColor = ThemeColors.current.s2.ns
        super.init(window: window)
        window.delegate = self
        let content = PropertiesContentView()
        window.contentView = content
        content.addSubview(header)
        for t in FolderOptions.Tab.allCases {
            let b = SegmentButton(t.rawValue) { [weak self] in self?.select(t) }
            b.focusRingType = .none
            tabButtons[t] = b
            content.addSubview(b)
        }
        searchBox.folderName = "settings"
        searchBox.onChange = { [weak self] text in self?.search(text) }
        // Esc clears the box first; Esc in an empty box closes the window, as Esc does everywhere else in it.
        searchBox.onClear = { [weak self] in
            guard let self else { return }
            if self.query.isEmpty { self.window?.performClose(nil) } else { self.search("") }
        }
        // Return is OK, as in the rest of the dialog, but not while results show.
        searchBox.onEnter = { [weak self] text in if text.isEmpty { self?.commit(close: true) } }
        content.addSubview(searchBox)
        window.onFind = { [weak self] in self?.searchBox.focus() }
        content.addSubview(body)
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = list
        scroll.setAccessibilityLabel("Advanced settings")
        for b in [restore, ok, cancel, apply] { content.addSubview(b) }
        restore.onPress = { [weak self] in self?.restoreDefaults() }
        ok.onPress = { [weak self] in self?.commit(close: true) }
        cancel.onPress = { [weak self] in self?.window?.performClose(nil) }
        apply.onPress = { [weak self] in self?.commit(close: false) }
        (window as OptionsWindow).onReturn = { [weak self] in self?.commit(close: true) }
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged(_:)), name: ThemeController.didChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// A tab shows its own settings again: the search box empties.
    private func select(_ t: FolderOptions.Tab) {
        tab = t
        query = ""
        searchBox.text = ""
        build()
    }

    private func search(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed != query else { return }
        query = trimmed
        if searchBox.text != text { searchBox.text = text }
        build()
    }

    // MARK: Building the tabs

    private func build() {
        guard let content = window?.contentView else { return }
        body.subviews.forEach { $0.removeFromSuperview() }
        controls = []
        folderHandlerBox = nil
        loginItemBox = nil
        revealBox = nil
        let w = content.bounds.width, h = content.bounds.height
        header.frame = NSRect(x: 0, y: 0, width: w, height: 44)
        var x: CGFloat = 24
        for t in FolderOptions.Tab.allCases {
            guard let b = tabButtons[t] else { continue }
            // While results show, no tab is on: they come from all three.
            b.isOn = query.isEmpty && t == tab
            let bw = b.fit() + 16
            b.frame = NSRect(x: x, y: 58, width: bw, height: 34)
            x += bw - 1
        }
        searchBox.frame = NSRect(x: w - 24 - 300, y: 56, width: 300, height: 38)
        body.frame = NSRect(x: 18, y: 106, width: w - 36, height: h - 106 - 72)
        if !query.isEmpty {
            buildResults()
        } else {
            switch tab {
            case .general: buildGeneral()
            case .view: buildView()
            case .search: buildSearch()
            }
        }
        let y = h - 24 - 40
        let rw = restore.fit()
        restore.frame = NSRect(x: 24, y: y, width: rw, height: 40)
        // Restore Defaults works on one tab; the results come from all three.
        restore.isEnabled = query.isEmpty
        var right = w - 24
        for b in [apply, cancel, ok] {
            let bw = b.fit(minimum: 96)
            b.frame = NSRect(x: right - bw, y: y, width: bw, height: 40)
            right -= bw + 8
        }
        refresh()
        content.needsDisplay = true
    }

    private func check(_ title: String, _ setting: FolderOptions.Setting?, note: String? = nil) -> OSCheck {
        let c = OSCheck(title)
        if let setting {
            c.onToggle = { [weak self] _ in self?.flip(setting) }
            controls.append((c, setting))
            c.toolTip = note
        } else {
            c.isEnabled = false
            c.toolTip = "Not on macOS"
            c.setAccessibilityHelp("Not on macOS")
        }
        return c
    }

    private func radio(_ title: String, _ setting: FolderOptions.Setting) -> OSRadio {
        let r = OSRadio(title)
        r.onPick = { [weak self] in self?.flip(setting) }
        controls.append((r, setting))
        return r
    }

    /// One `.sgrp`: its heading, then a line per control (24 pt; a button line 36 pt). `column` 0 or 1 puts
    /// it in General's left or right half; nil spans the width.
    private func group(_ title: String, at y: inout CGFloat, column: Int? = nil, rows: [(NSView, CGFloat)]) {
        func lineH(_ v: NSView) -> CGFloat { v is OSButton || v is FlowView ? 38 : 24 }
        let height = FormGroupView.headH + rows.reduce(CGFloat(0)) { $0 + lineH($1.0) } + 6
        let g = FormGroupView(title: title)
        let half = (body.bounds.width - 12) / 2
        g.frame = column.map { NSRect(x: CGFloat($0) * (half + 12), y: y, width: half, height: height) }
            ?? NSRect(x: 0, y: y, width: body.bounds.width, height: height)
        var ry = FormGroupView.headH - 2
        for (view, indent) in rows {
            let fit = (view as? OSCheck)?.fit() ?? (view as? OSRadio)?.fit() ?? (view as? OSButton)?.fit() ?? (g.bounds.width - 28)
            let h = lineH(view)
            let rowH: CGFloat = h > 24 ? 34 : 20
            view.frame = NSRect(x: 14 + indent, y: ry + (h - rowH) / 2, width: min(fit, g.bounds.width - 28 - indent), height: rowH)
            g.addSubview(view)
            ry += h
        }
        body.addSubview(g)
        y += height + 8
    }

    /// One control for an entry of the settings list: its check box or radio, wired to the draft, or one
    /// of the boxes that change macOS at once. `width` is the line's width (the Clear row fills it).
    private func view(for e: FolderOptions.Entry, width: CGFloat) -> NSView {
        switch e.control {
        case .check(let s): return check(e.title, s, note: e.note)
        case .radio(let s):
            let r = radio(e.title, s)
            r.toolTip = e.note
            return r
        case .unavailable: return check(e.title, nil)
        case .openFoldersInFolio:
            let box = OSCheck(e.title)
            box.toolTip = e.note
            box.onToggle = { [weak self] on in self?.setFolderHandler(on) }
            folderHandlerBox = box
            return box
        case .revealInFolio:
            let box = OSCheck(e.title)
            box.toolTip = e.note
            box.onToggle = { [weak self] on in self?.setReveals(on) }
            revealBox = box
            return box
        case .launchAtLogin:
            let box = OSCheck(e.title)
            box.toolTip = e.note
            box.onToggle = { [weak self] on in self?.setLoginItem(on) }
            loginItemBox = box
            return box
        case .clearHistory:
            let clear = OSButton("Clear", glyph: .trash)
            clear.setAccessibilityLabel("Clear Folio history")
            clear.onPress = { [weak self] in self?.clearHistory() }
            let label = LabelView(e.title, font: Typeface.mono(12), color: { $0.text2 })
            let row = FlowView()
            let clearW = clear.fit(minimum: 96)
            row.add(label, width: width - clearW - 10)
            row.add(clear, width: clearW)
            return row
        }
    }

    /// The entries in their groups, in the list's order.
    private func groups(_ entries: [FolderOptions.Entry]) -> [(String, [FolderOptions.Entry])] {
        var out: [(String, [FolderOptions.Entry])] = []
        for e in entries {
            if out.last?.0 == e.group { out[out.count - 1].1.append(e) } else { out.append((e.group, [e])) }
        }
        return out
    }

    private func buildGeneral() {
        var left: CGFloat = 0, right: CGFloat = 0
        let lineW = (body.bounds.width - 12) / 2 - 28
        // Milestone 9's Folio and macOS: the folder, reveal and login boxes change macOS at once and show
        // what it reports; the rest wait for OK.
        for (name, entries) in groups(FolderOptions.generalEntries) {
            let rows = entries.map { e -> (NSView, CGFloat) in
                let underline = e.control == .radio(.underlineAlways) || e.control == .radio(.underlineHover)
                return (view(for: e, width: lineW), underline ? 22 : 0)
            }
            if ["Privacy", "Folio and macOS"].contains(name) {
                group(name, at: &right, column: 1, rows: rows)
            } else {
                group(name, at: &left, column: 0, rows: rows)
            }
        }
    }

    private func setFolderHandler(_ on: Bool) {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        app.setFolderHandler(on: on, sheetOn: window) { [weak self] in self?.refresh() }
    }

    private func setReveals(_ on: Bool) {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        app.setRevealsInFolio(on, sheetOn: window) { [weak self] in self?.refresh() }
    }

    private func setLoginItem(_ on: Bool) {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        app.setLaunchAtLogin(on, sheetOn: window) { [weak self] in self?.refresh() }
    }

    private func buildView() {
        // No Folder views group: Folio has one view for every folder and no folder keeps its own, so
        // Explorer's Apply to Folders and Reset Folders have nothing to do (View > Make This the Default View).
        let y: CGFloat = 0
        // Advanced settings: Explorer's long list, scrolling inside its group.
        let advanced = FormGroupView(title: "Advanced settings")
        advanced.frame = NSRect(x: 0, y: y, width: body.bounds.width, height: body.bounds.height - y)
        body.addSubview(advanced)
        scroll.frame = NSRect(x: 1, y: FormGroupView.headH, width: advanced.bounds.width - 2, height: advanced.bounds.height - FormGroupView.headH - 4)
        scroll.setAccessibilityLabel("Advanced settings")
        advanced.addSubview(scroll)
        var rows: [(NSView, CGFloat, Bool)] = []
        for row in FolderOptions.viewRows {
            let indent = CGFloat(row.indent) * 20 - 6
            switch row.kind {
            case .heading:
                rows.append((LabelView(row.title, font: Typeface.ui(12, weight: 700), color: { $0.text }), max(0, indent), true))
            case .check:
                rows.append((check(row.title, row.setting, note: row.note), indent, false))
            case .radio:
                if let s = row.setting { rows.append((radio(row.title, s), indent, false)) }
            }
        }
        list.place(rows, width: scroll.bounds.width)
        list.scroll(.zero)
    }

    private func buildSearch() {
        var y: CGFloat = 0
        for (name, entries) in groups(FolderOptions.searchEntries) {
            group(name, at: &y, rows: entries.map { (view(for: $0, width: body.bounds.width - 28), 0) })
        }
    }

    /// The search box's results: every matching setting of the three tabs, as live controls, each with the
    /// tab and group it lives in. A change waits for OK or Apply, as on the tabs.
    private func buildResults() {
        let found = FolderOptions.search(query)
        let title = found.isEmpty ? "No settings match" : found.count == 1 ? "1 setting" : "\(found.count) settings"
        let box = FormGroupView(title: title)
        box.frame = body.bounds
        body.addSubview(box)
        guard !found.isEmpty else {
            let hint = LabelView("No setting matches \u{201C}\(query)\u{201D}. Try other words, such as hidden, Finder or zip.",
                                 font: Typeface.ui(13), color: { $0.text2 })
            hint.frame = NSRect(x: 14, y: FormGroupView.headH + 2, width: box.bounds.width - 28, height: 20)
            box.addSubview(hint)
            return
        }
        scroll.frame = NSRect(x: 1, y: FormGroupView.headH, width: box.bounds.width - 2, height: box.bounds.height - FormGroupView.headH - 4)
        scroll.setAccessibilityLabel("Matching settings")
        box.addSubview(scroll)
        let placeW: CGFloat = 270
        let lineW = scroll.bounds.width - 28 - placeW - 16
        let rows = found.map { e -> (NSView, NSView) in
            (view(for: e, width: lineW), LabelView(e.place, font: Typeface.ui(12), color: { $0.muted }))
        }
        list.placeResults(rows, width: scroll.bounds.width, placeWidth: placeW)
        list.scroll(.zero)
    }

    // MARK: State

    private func flip(_ s: FolderOptions.Setting) {
        draft.toggle(s)
        refresh()
    }

    /// Every control shows the draft; Apply lights when it differs from what is saved.
    private func refresh() {
        for (control, setting) in controls {
            if let c = control as? OSCheck { c.isChecked = draft.isOn(setting) }
            if let r = control as? OSRadio { r.isSelected = draft.isOn(setting) }
        }
        folderHandlerBox?.isChecked = SystemSettings.foldersOpenInFolio
        revealBox?.isChecked = SystemSettings.revealsInFolio
        loginItemBox?.isChecked = SystemSettings.launchesAtLogin
        apply.isEnabled = draft != ListOptions.folder
    }

    private func restoreDefaults() {
        draft.restoreDefaults(tab)
        refresh()
    }

    private func commit(close: Bool) {
        if draft != ListOptions.folder { ListOptions.apply(draft) }
        refresh()
        if close { window?.performClose(nil) }
    }

    /// Clear: recent files, frequent folders (the address history behind Recent locations), recent searches.
    private func clearHistory() {
        let d = UserDefaults.standard
        for key in [RecentFiles.key, AddressHistory.key, "recentSearches"] { d.removeObject(forKey: key) }
        NSDocumentController.shared.clearRecentDocuments(nil)
        NotificationCenter.default.post(name: HomeData.didChange, object: nil)
    }

    @objc private func themeChanged(_ note: Notification) {
        window?.backgroundColor = ThemeColors.current.s2.ns
        if let content = window?.contentView { refreshTheme(in: content) }
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        Self.shared = nil
    }
}

/// A view laid out top-down.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Esc cancels and Return is OK, as in Explorer's dialog. Cmd+F goes to the search box.
final class OptionsWindow: NSWindow {
    var onReturn: (() -> Void)?
    var onFind: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            onFind?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?(); return }
        super.keyDown(with: event)
    }
}

/// The strip under the window's own buttons: "Folder Options".
final class OptionsHeader: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        fillRect(bounds, p.s1)
        fillRect(NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1), p.line)
        drawLine("Folder Options", font: Typeface.ui(14, weight: 700), color: p.text, x: 82, midY: 22)
    }
}

/// A settings group as a D4 spotlight card: s1 with a hairline, radius 12, and a mono uppercase label.
final class FormGroupView: NSView {
    static let headH: CGFloat = 34
    let title: String

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        fillRounded(bounds, radius: 12, p.s1)
        strokeRounded(bounds, radius: 12, p.line)
        drawLine(Typeface.caption(title), font: Typeface.mono(12, weight: 600), color: p.muted, x: 14, midY: Self.headH / 2,
                 kern: Typeface.labelKern(12))
    }
}

/// The Advanced settings list inside its scroll view: headings, check boxes and radios, one per line.
final class OptionsListView: NSView {
    static let rowH: CGFloat = 26
    override var isFlipped: Bool { true }

    func place(_ rows: [(NSView, CGFloat, Bool)], width: CGFloat) {
        subviews.forEach { $0.removeFromSuperview() }
        var y: CGFloat = 4
        for (view, indent, heading) in rows {
            let fit = (view as? OSCheck)?.fit() ?? (view as? OSRadio)?.fit() ?? width
            view.frame = NSRect(x: 14 + indent, y: y + 3, width: min(fit, width - 28 - indent), height: 20)
            addSubview(view)
            y += heading ? Self.rowH + 2 : Self.rowH
        }
        frame = NSRect(x: 0, y: 0, width: width, height: y + 6)
    }

    /// The search results: a control on the left, and where it lives (its tab and group) on the right.
    func placeResults(_ rows: [(NSView, NSView)], width: CGFloat, placeWidth: CGFloat) {
        subviews.forEach { $0.removeFromSuperview() }
        let controlW = width - 28 - placeWidth - 16
        var y: CGFloat = 4
        for (view, place) in rows {
            let h: CGFloat = view is OSButton || view is FlowView ? 38 : Self.rowH
            let rowH: CGFloat = h > Self.rowH ? 34 : 20
            let fit = (view as? OSCheck)?.fit() ?? (view as? OSRadio)?.fit() ?? controlW
            view.frame = NSRect(x: 14, y: y + (h - rowH) / 2, width: min(fit, controlW), height: rowH)
            place.frame = NSRect(x: width - 14 - placeWidth, y: y + (h - 20) / 2, width: placeWidth, height: 20)
            addSubview(view)
            addSubview(place)
            y += h
        }
        frame = NSRect(x: 0, y: 0, width: width, height: y + 6)
    }
}

/// A radio in D4's language: a 14 pt ring (outline), the accent ring and dot when chosen, a Geist label.
///
/// Not of AppKit's radio type: AppKit makes one group of every radio with the same superview and action,
/// and turning one on turns the others off. Advanced settings has two groups in one view (hidden items,
/// typing), so the typing radio turned "Show hidden files" off again. The window keeps each group's
/// choice itself. Accessibility still sees a radio button, with its value.
final class OSRadio: NSButton {
    var onPick: (() -> Void)?

    init(_ title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        setButtonType(.onOff)
        self.title = title
        setAccessibilityLabel(title)
        isBordered = false
        target = self
        action = #selector(picked(_:))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var isSelected: Bool {
        get { state == .on }
        set { state = newValue ? .on : .off; needsDisplay = true }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }
    override func accessibilityValue() -> Any? { NSNumber(value: isSelected ? 1 : 0) }

    /// A click on a chosen radio leaves it on, as a radio does (the on-off type would turn it off).
    @objc private func picked(_ sender: Any?) {
        isSelected = true
        onPick?()
    }

    private var labelFont: NSFont { Typeface.ui(13) }

    func fit() -> CGFloat { 14 + 8 + textWidth(title, font: labelFont) + 2 }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.5) }
        let box = NSRect(x: 0, y: (bounds.height - 14) / 2, width: 14, height: 14)
        if isSelected {
            fillRounded(box, radius: 7, p.s1)
            strokeRounded(box.insetBy(dx: 0.75, dy: 0.75), radius: 6.25, p.accent, width: 1.5)
            fillRounded(box.insetBy(dx: 4, dy: 4), radius: 3, p.accent)
        } else {
            fillRounded(box, radius: 7, p.s1)
            strokeRounded(box.insetBy(dx: 0.6, dy: 0.6), radius: 6.4, p.outline, width: 1.25)
        }
        drawLine(title, font: labelFont, color: isSelected ? p.text : p.text2, x: 22, midY: bounds.midY, maxWidth: bounds.width - 22)
    }
}
