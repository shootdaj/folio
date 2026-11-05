import AppKit
import FolioCore

/// Explorer's Folder Options (View > Options, See more > Options): General, View and Search tabs with
/// Explorer's wording, each with Restore Defaults; OK, Cancel and Apply. Drawn as D1's bracket panel
/// (the Properties window's form): `.sgrp` groups with `.sh` headings, D1 check boxes and radios.
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
    }

    private var draft = ListOptions.folder
    private var tab = FolderOptions.Tab.general
    private let header = OptionsHeader()
    private var tabButtons: [FolderOptions.Tab: SegmentButton] = [:]
    private let body = FlippedView()
    private let scroll = NSScrollView()
    private let list = OptionsListView()
    private let restore = D1Button("Restore Defaults", glyph: .refresh)
    private let ok = D1Button("OK", glyph: .check, style: .primary)
    private let cancel = D1Button("Cancel", glyph: .close)
    private let apply = D1Button("Apply")
    /// Every check box and radio on screen, with the setting it shows.
    private var controls: [(NSButton, FolderOptions.Setting)] = []
    /// General's two boxes that change macOS itself at once (not on OK): they show what the Mac reports.
    private var folderHandlerBox: D1Check?
    private var loginItemBox: D1Check?

    private init() {
        // 860 wide: General's two columns (milestone 9 added Folio and macOS) fit a 1024 pt screen.
        let window = OptionsWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 660),
                                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Folder Options"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.backgroundColor = Palette.current.s2.ns
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

    private func select(_ t: FolderOptions.Tab) {
        tab = t
        build()
    }

    // MARK: Building the tabs

    private func build() {
        guard let content = window?.contentView else { return }
        body.subviews.forEach { $0.removeFromSuperview() }
        controls = []
        folderHandlerBox = nil
        loginItemBox = nil
        let w = content.bounds.width, h = content.bounds.height
        header.frame = NSRect(x: 0, y: 0, width: w, height: 44)
        var x: CGFloat = 24
        for t in FolderOptions.Tab.allCases {
            guard let b = tabButtons[t] else { continue }
            b.isOn = t == tab
            let bw = b.fit() + 16
            b.frame = NSRect(x: x, y: 58, width: bw, height: 34)
            x += bw - 1
        }
        body.frame = NSRect(x: 18, y: 106, width: w - 36, height: h - 106 - 72)
        switch tab {
        case .general: buildGeneral()
        case .view: buildView()
        case .search: buildSearch()
        }
        let y = h - 24 - 40
        let rw = restore.fit()
        restore.frame = NSRect(x: 24, y: y, width: rw, height: 40)
        var right = w - 24
        for b in [apply, cancel, ok] {
            let bw = b.fit(minimum: 96)
            b.frame = NSRect(x: right - bw, y: y, width: bw, height: 40)
            right -= bw + 8
        }
        refresh()
        content.needsDisplay = true
    }

    private func check(_ title: String, _ setting: FolderOptions.Setting?, note: String? = nil) -> D1Check {
        let c = D1Check(title)
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

    private func radio(_ title: String, _ setting: FolderOptions.Setting) -> D1Radio {
        let r = D1Radio(title)
        r.onPick = { [weak self] in self?.flip(setting) }
        controls.append((r, setting))
        return r
    }

    /// One `.sgrp`: its heading, then a line per control (24 pt; a button line 36 pt). `column` 0 or 1 puts
    /// it in General's left or right half; nil spans the width.
    private func group(_ title: String, at y: inout CGFloat, column: Int? = nil, rows: [(NSView, CGFloat)]) {
        func lineH(_ v: NSView) -> CGFloat { v is D1Button || v is FlowView ? 38 : 24 }
        let height = FormGroupView.headH + rows.reduce(CGFloat(0)) { $0 + lineH($1.0) } + 6
        let g = FormGroupView(title: title)
        let half = (body.bounds.width - 12) / 2
        g.frame = column.map { NSRect(x: CGFloat($0) * (half + 12), y: y, width: half, height: height) }
            ?? NSRect(x: 0, y: y, width: body.bounds.width, height: height)
        var ry = FormGroupView.headH - 2
        for (view, indent) in rows {
            let fit = (view as? D1Check)?.fit() ?? (view as? D1Radio)?.fit() ?? (view as? D1Button)?.fit() ?? (g.bounds.width - 28)
            let h = lineH(view)
            let rowH: CGFloat = h > 24 ? 34 : 20
            view.frame = NSRect(x: 14 + indent, y: ry + (h - rowH) / 2, width: min(fit, g.bounds.width - 28 - indent), height: rowH)
            g.addSubview(view)
            ry += h
        }
        body.addSubview(g)
        y += height + 8
    }

    private func buildGeneral() {
        var y: CGFloat = 0
        group("Open Folio to", at: &y, column: 0, rows: [(radio("Home", .openToHome), 0), (radio("This PC (the startup disk)", .openToThisPC), 0)])
        group("Browse folders", at: &y, column: 0, rows: [(radio("Open each folder in the same window", .sameWindow), 0),
                                                          (radio("Open each folder in its own window", .ownWindow), 0)])
        group("Click items as follows", at: &y, column: 0, rows: [
            (radio("Single-click to open an item (point to select)", .singleClick), 0),
            (radio("Underline icon titles consistent with my browser", .underlineAlways), 22),
            (radio("Underline icon titles only when I point at them", .underlineHover), 22),
            (radio("Double-click to open an item (single-click to select)", .doubleClick), 0),
        ])
        let clear = D1Button("Clear", glyph: .trash)
        clear.setAccessibilityLabel("Clear Folio history")
        clear.onPress = { [weak self] in self?.clearHistory() }
        let label = LabelView("Clear recent files, folders, addresses", font: Typeface.mono(12), color: { $0.txt2 })
        let clearRow = FlowView()
        let clearW = clear.fit(minimum: 96)
        clearRow.add(label, width: (body.bounds.width - 12) / 2 - 28 - clearW - 10)
        clearRow.add(clear, width: clearW)
        var right: CGFloat = 0
        group("Privacy", at: &right, column: 1, rows: [(check("Show recently used files", .showRecentFiles), 0),
                                                       (check("Show frequently used folders", .showFrequentFolders), 0),
                                                       (clearRow, 0)])
        // Milestone 9. The first and last change macOS at once and show what it reports; the rest wait for OK.
        let handler = D1Check("Open folders in Folio instead of Finder")
        handler.toolTip = "Asks macOS to open folders and drives in Folio, then says what macOS kept"
        handler.onToggle = { [weak self] on in self?.setFolderHandler(on) }
        folderHandlerBox = handler
        let login = D1Check("Launch Folio at login")
        login.toolTip = "Adds Folio to your login items (System Settings > General > Login Items)"
        login.onToggle = { [weak self] on in self?.setLoginItem(on) }
        loginItemBox = login
        group("Folio and macOS", at: &right, column: 1, rows: [
            (handler, 0),
            (check("Open external folder links in a new tab", .externalFoldersInNewTab,
                   note: "Folders from ff and other apps open as a tab in the front window"), 0),
            (check("Reopen windows and tabs on relaunch", .reopenWindows), 0),
            (check("Keep running when the last window closes", .keepRunning, note: "Cmd+Q still quits"), 0),
            (login, 0),
        ])
    }

    private func setFolderHandler(_ on: Bool) {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        app.setFolderHandler(on: on, sheetOn: window) { [weak self] in self?.refresh() }
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
        advanced.addSubview(scroll)
        var rows: [(NSView, CGFloat, Bool)] = []
        for row in FolderOptions.viewRows {
            let indent = CGFloat(row.indent) * 20 - 6
            switch row.kind {
            case .heading:
                rows.append((LabelView(row.title, font: Typeface.ui(12, weight: 700, width: 116), color: { $0.txt }), max(0, indent), true))
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
        group("How to search", at: &y, rows: [
            (check("Don't use the index when searching in file folders for system files (searches might take longer)", .dontUseIndex,
                   note: "Spotlight is left out; the live walk covers everything"), 0),
        ])
        group("When searching non-indexed locations", at: &y, rows: [
            (check("Include system directories", .includeSystemDirectories), 0),
            (check("Include compressed files (ZIP)", .includeCompressedFiles, note: "Looks inside zips, as Search options > Zipped folders"), 0),
            (check("Always search file names and contents (this might take several minutes)", .alwaysSearchContents), 0),
        ])
    }

    // MARK: State

    private func flip(_ s: FolderOptions.Setting) {
        draft.toggle(s)
        refresh()
    }

    /// Every control shows the draft; Apply lights when it differs from what is saved.
    private func refresh() {
        for (control, setting) in controls {
            if let c = control as? D1Check { c.isChecked = draft.isOn(setting) }
            if let r = control as? D1Radio { r.isSelected = draft.isOn(setting) }
        }
        folderHandlerBox?.isChecked = SystemSettings.foldersOpenInFolio
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
        window?.backgroundColor = Palette.current.s2.ns
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

/// Esc cancels and Return is OK, as in Explorer's dialog.
final class OptionsWindow: NSWindow {
    var onReturn: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
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
        let p = Palette.current
        fillRect(bounds, p.s1)
        fillRect(NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1), p.line)
        drawLine("Folder Options", font: Typeface.ui(14, weight: 700, width: 124), color: p.txt, x: 82, midY: 22)
    }
}

/// D1's `.sgrp`: the bg at 86% with a hairline, radius 4, 8 pt brackets at 55% accent, and the `.sh`
/// heading (Archivo 700, wide, tracked).
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
        let p = Palette.current
        fillRounded(bounds, radius: 4, p.bg.withAlpha(0.86))
        strokeRounded(bounds.insetBy(dx: 0.5, dy: 0.5), radius: 4, p.line)
        drawBrackets(bounds, color: p.accent.withAlpha(0.55).ns, length: 8)
        drawLine(title, font: Typeface.ui(12, weight: 700, width: 124), color: p.txt, x: 12, midY: Self.headH / 2, kern: 0.48)
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
            let fit = (view as? D1Check)?.fit() ?? (view as? D1Radio)?.fit() ?? width
            view.frame = NSRect(x: 14 + indent, y: y + 3, width: min(fit, width - 28 - indent), height: 20)
            addSubview(view)
            y += heading ? Self.rowH + 2 : Self.rowH
        }
        frame = NSRect(x: 0, y: 0, width: width, height: y + 6)
    }
}

/// D1's radio: a 14 pt ring (line-3), the accent ring and dot when chosen, a mono label. An NSButton of the
/// radio type, so accessibility sees a radio button.
final class D1Radio: NSButton {
    var onPick: (() -> Void)?

    init(_ title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        setButtonType(.radio)
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

    @objc private func picked(_ sender: Any?) {
        isSelected = true
        onPick?()
    }

    private var labelFont: NSFont { Typeface.mono(12) }

    func fit() -> CGFloat { 14 + 8 + textWidth(title, font: labelFont) + 2 }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.5) }
        let box = NSRect(x: 0, y: (bounds.height - 14) / 2, width: 14, height: 14)
        if isSelected {
            fillRounded(box, radius: 7, p.s1)
            strokeRounded(box.insetBy(dx: 0.75, dy: 0.75), radius: 6.25, p.accent, width: 1.5)
            fillRounded(box.insetBy(dx: 4, dy: 4), radius: 3, p.accent)
        } else {
            fillRounded(box, radius: 7, p.s1)
            strokeRounded(box.insetBy(dx: 0.6, dy: 0.6), radius: 6.4, p.line3, width: 1.25)
        }
        drawLine(title, font: labelFont, color: isSelected ? p.txt : p.txt2, x: 22, midY: bounds.midY, maxWidth: bounds.width - 22)
    }
}
