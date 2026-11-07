import AppKit
import FolioCore

/// One row of a dropdown.
struct DropdownRow: Equatable {
    var text: String
    /// What picking the row means: a folder path, or an index for history lists.
    var value: String
    /// Field style: the first characters drawn bold (the part typed so far).
    var boldLength = 0
    /// Menu style: the folder on the current path, drawn in the accent with brackets.
    var isCurrent = false
}

enum DropdownStyle: Equatable {
    /// Under the address bar at its full width: header, rows of full paths, key footer (D4 `.ta`).
    case field(header: String, count: String)
    /// A folder list under a crumb arrow or a toolbar button (D4 `.menu`).
    case menu
}

struct DropdownContent: Equatable {
    var style: DropdownStyle
    /// The panel's window title, which is also its accessibility name ("Folders in Code").
    var title: String
    var rows: [DropdownRow]
    var empty: String
    /// Recent searches under the search box: a magnifier per row and "Enter runs, Esc closes".
    var isSearchList = false
}

/// The one dropdown a browser window shows at a time: the typeahead, the address history, a crumb's
/// folders, the « list, or the Back and Forward lists. A child panel that never takes focus, so the
/// address field keeps the caret while Up, Down, Tab and Enter drive the list.
@MainActor
final class Dropdown {
    private var panel: DropdownPanel?
    private(set) var id: String?
    private var onPick: ((DropdownRow) -> Void)?
    private var monitor: Any?
    private var lastClosed: (id: String, time: TimeInterval)?
    /// Clicks inside this rect of the parent window leave the dropdown open (the address bar while editing).
    var keepOpenRect: NSRect = .zero
    var onClose: (() -> Void)?

    var isOpen: Bool { panel != nil }
    var highlighted: Int? { panel?.view.highlighted }
    var content: DropdownContent? { panel?.view.content }

    func isOpen(_ id: String) -> Bool { isOpen && self.id == id }

    /// True when `id` was closed by the click that is now arriving, so that click does not reopen it.
    func wasJustClosed(_ id: String, by event: NSEvent) -> Bool {
        guard let last = lastClosed, last.id == id else { return false }
        return abs(last.time - event.timestamp) < 0.001
    }

    /// Opens below `anchor` (in `view`'s coordinates). Field style takes the anchor's width; menu style
    /// sizes to its rows and starts 6 pt left of the anchor, as D4 places `.menu`.
    func show(_ content: DropdownContent, id: String, below anchor: NSRect, in view: NSView,
              onPick: @escaping (DropdownRow) -> Void) {
        guard let window = view.window else { return }
        close()
        let panel = DropdownPanel(content: content)
        panel.view.onPick = { [weak self] index in self?.pick(index) }
        self.panel = panel
        self.id = id
        self.onPick = onPick
        let anchorOnScreen = window.convertToScreen(view.convert(anchor, to: nil))
        place(panel, anchor: anchorOnScreen, parent: window)
        window.addChildWindow(panel, ordered: .above)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                panel.animator().alphaValue = 1
            }
        }
        panel.invalidateShadow()
        startMonitor(parent: window)
    }

    /// New rows for the open dropdown (the typeahead filtering as you type); the highlight clears.
    func update(_ content: DropdownContent) {
        guard let panel, let parent = panel.parent else { return }
        let top = panel.frame.maxY
        let anchor = NSRect(x: panel.frame.minX, y: top + 6, width: panel.frame.width, height: 0)
        panel.view.content = content
        panel.view.setHighlight(nil, fromKeyboard: false)
        panel.title = content.title
        place(panel, anchor: anchor, parent: parent, keepX: true)
        panel.invalidateShadow()
    }

    func moveHighlight(_ delta: Int) {
        guard let view = panel?.view, !view.content.rows.isEmpty else { return }
        let n = view.content.rows.count
        let next: Int = if let h = view.highlighted { (h + delta % n + n) % n } else { delta > 0 ? 0 : n - 1 }
        view.setHighlight(next, fromKeyboard: true)
    }

    /// Enter: opens the highlighted row. False when nothing is highlighted.
    @discardableResult
    func pickHighlighted() -> Bool {
        guard let h = highlighted else { return false }
        pick(h)
        return true
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
        id = nil
        onPick = nil
        keepOpenRect = .zero
        onClose?()
    }

    private func pick(_ index: Int) {
        guard let rows = panel?.view.content.rows, rows.indices.contains(index), let onPick else { return }
        let row = rows[index]
        close()
        onPick(row)
    }

    private func place(_ panel: DropdownPanel, anchor: NSRect, parent: NSWindow, keepX: Bool = false) {
        let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        let maxHeight = max(80, anchor.minY - 6 - visible.minY - 8)
        let isField = if case .field = panel.view.content.style { true } else { false }
        let size = panel.view.preferredSize(width: isField ? anchor.width : nil, maxHeight: maxHeight)
        var x = anchor.minX - (isField || keepX ? 0 : 6)
        if !isField {
            x = min(max(x, parent.frame.minX + 8), parent.frame.maxX - size.width - 8)
        }
        panel.setFrame(NSRect(x: x, y: anchor.minY - 6 - size.height, width: size.width, height: size.height), display: true)
    }

    private func startMonitor(parent: NSWindow) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, event.window !== panel else { return }
                if event.window === parent, self.keepOpenRect.contains(event.locationInWindow) { return }
                self.lastClosed = (self.id ?? "", event.timestamp)
                self.close()
            }
            return event
        }
    }
}

/// The borderless child panel; it never becomes key, so focus stays in the browser window.
final class DropdownPanel: NSPanel {
    let view: DropdownView

    init(content: DropdownContent) {
        view = DropdownView(content: content)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        title = content.title
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws a dropdown as D4's spotlight panels. Field style (`.ta`): --pop with a line-2 border at radius 12,
/// a header (mono uppercase label and the count), 32 pt rows (folder, the path in Geist Mono with the typed
/// part bold), a key footer. Menu style (`.menu`): 30 pt rows of folder names, the current one ticked.
final class DropdownView: NSView {
    var content: DropdownContent { didSet { rowsView.needsDisplay = true; needsDisplay = true; needsLayout = true } }
    private(set) var highlighted: Int?
    private var keyboardHighlight = false
    var onPick: ((Int) -> Void)?

    private let scroll = NSScrollView()
    private let rowsView = DropdownRowsView()
    private let overlay = DropdownOverlay()

    static let pad: CGFloat = 6
    static let headerH: CGFloat = 32
    static let footerH: CGFloat = 41
    static let menuMinW: CGFloat = 220, menuMaxW: CGFloat = 340, menuMaxH: CGFloat = 360

    init(content: DropdownContent) {
        self.content = content
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = rowsView
        rowsView.owner = self
        addSubview(scroll)
        addSubview(overlay)
        overlay.owner = self
        setAccessibilityRole(.list)
        setAccessibilityLabel(content.title)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var isField: Bool { if case .field = content.style { true } else { false } }
    var rowH: CGFloat { isField ? 32 : 30 }

    func setHighlight(_ index: Int?, fromKeyboard: Bool) {
        guard index != highlighted || fromKeyboard != keyboardHighlight else { return }
        highlighted = index
        keyboardHighlight = fromKeyboard
        rowsView.needsDisplay = true
        if let index { rowsView.scrollToVisible(rowsView.rowRect(index)) }
    }

    var isKeyboardHighlight: Bool { keyboardHighlight }

    // MARK: Size

    private var chromeH: CGFloat { isField ? 1 + Self.headerH + Self.footerH + Self.pad + 1 : 2 }

    func listHeight() -> CGFloat {
        content.rows.isEmpty ? (isField ? 46 : 38) + 2 * Self.pad : CGFloat(content.rows.count) * rowH + 2 * Self.pad
    }

    func preferredSize(width: CGFloat?, maxHeight: CGFloat) -> NSSize {
        var h = chromeH + listHeight()
        if !isField { h = min(h, Self.menuMaxH) }
        h = min(h, maxHeight)
        if let width { return NSSize(width: width, height: h) }
        let font = Typeface.ui(13, weight: 500)
        let widest = content.rows.map { textWidth($0.text, font: font) }.max() ?? textWidth(content.empty, font: Typeface.ui(13))
        let w = 2 + 2 * Self.pad + 10 + 16 + 9 + widest + 10 + 24
        return NSSize(width: min(max(w, Self.menuMinW), Self.menuMaxW), height: h)
    }

    override func layout() {
        super.layout()
        let top: CGFloat = isField ? 1 + Self.headerH : 1
        let bottom: CGFloat = isField ? Self.footerH + Self.pad + 1 : 1
        scroll.frame = NSRect(x: 1, y: top, width: bounds.width - 2, height: max(0, bounds.height - top - bottom))
        rowsView.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: listHeight())
        overlay.frame = bounds
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        fillRounded(bounds, radius: 12, p.pop.over(p.bg))
        strokeRounded(bounds, radius: 12, p.line2)
        guard case .field(let header, let count) = content.style else { return }
        let mid = 1 + Self.headerH / 2 + 2
        drawLine(header.uppercased(), font: Typeface.mono(12, weight: 600), color: p.muted, x: 18, midY: mid,
                 maxWidth: bounds.width - 120, kern: Typeface.labelKern(12))
        drawLine(count, font: Typeface.mono(12, weight: 500), color: p.muted, x: bounds.width - 16, midY: mid, alignRight: true)
        // Footer: "Tab fills, Enter opens, Esc cancels" with key caps.
        let footTop = bounds.height - 1 - Self.pad - Self.footerH
        fillRect(NSRect(x: 7, y: footTop, width: bounds.width - 14, height: 1), p.line)
        let lineMid = footTop + 1 + 9 + 11
        var x: CGFloat = 18
        let body = Typeface.ui(12)
        let keys = content.isSearchList ? [("Enter", " runs, ", false), ("Esc", " closes", true)]
            : [("Tab", " fills, ", false), ("Enter", " opens, ", false), ("Esc", " cancels", true)]
        for (key, words, tall) in keys {
            _ = tall
            x += drawKey(key, x: x, midY: lineMid, height: 20, p) + 2
            x += drawLine(words, font: body, color: p.muted, x: x, midY: lineMid)
        }
    }

    /// D4's `kbd`: s2 cap, line-2 border with a 2 pt bottom, Geist Mono 500 12 in text-2.
    private func drawKey(_ key: String, x: CGFloat, midY: CGFloat, height: CGFloat, _ p: ThemeColors) -> CGFloat {
        let font = Typeface.mono(12, weight: 500)
        let w = textWidth(key, font: font) + 12 + 2
        let r = NSRect(x: x, y: (midY - height / 2).rounded(), width: w, height: height)
        fillRounded(r, radius: 5, p.line2)
        fillRounded(NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 2, height: r.height - 3), radius: 4, p.s2)
        drawLine(key, font: font, color: p.text2, x: r.minX + 7, midY: r.minY + 1 + (r.height - 3) / 2)
        return w
    }
}

/// The scrolling rows of a dropdown.
final class DropdownRowsView: NSView {
    weak var owner: DropdownView?
    private var pressed: Int?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func rowRect(_ i: Int) -> NSRect {
        let h = owner?.rowH ?? 30
        return NSRect(x: DropdownView.pad, y: DropdownView.pad + CGFloat(i) * h, width: bounds.width - 2 * DropdownView.pad, height: h)
    }

    private func row(at event: NSEvent) -> Int? {
        guard let owner else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        return owner.content.rows.indices.first { rowRect($0).contains(point) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let owner, let i = row(at: event) else { return }
        owner.setHighlight(i, fromKeyboard: false)
    }

    override func mouseExited(with event: NSEvent) {
        // D4 keeps the typeahead highlight where the pointer left it; menus drop it.
        if let owner, !owner.isField, !owner.isKeyboardHighlight { owner.setHighlight(nil, fromKeyboard: false) }
    }

    override func mouseDown(with event: NSEvent) { pressed = row(at: event) }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        guard let i = row(at: event), i == pressed else { return }
        owner?.onPick?(i)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let owner else { return }
        let p = ThemeColors.current
        let content = owner.content
        if content.rows.isEmpty {
            drawLine(content.empty, font: Typeface.ui(13), color: p.text2, x: DropdownView.pad + 12,
                     midY: DropdownView.pad + (owner.isField ? 23 : 19), maxWidth: bounds.width - 32)
            return
        }
        for (i, row) in content.rows.enumerated() {
            let r = rowRect(i)
            guard r.intersects(dirtyRect) else { continue }
            if owner.isField {
                drawFieldRow(row, in: r, hi: owner.highlighted == i, p)
            } else {
                drawMenuRow(row, in: r, hi: owner.highlighted == i, keyboard: owner.isKeyboardHighlight, p)
            }
        }
    }

    /// `.ta-row`: light, folder, then the directory (ellipsized) and the leaf name, typed part bold.
    private func drawFieldRow(_ row: DropdownRow, in r: NSRect, hi: Bool, _ p: ThemeColors) {
        // `.ta-row.hi`: the --sel fill and a glowing 3 pt accent edge, 7 pt short of top and bottom.
        if hi {
            fillRounded(r, radius: 8, p.selectionFill)
            drawEdgeBar(NSRect(x: r.minX, y: r.minY + 7, width: 3, height: r.height - 14), color: p.accent, glowAlpha: 1, rounded: true)
        }
        if owner?.content.isSearchList == true {
            Glyph.search.draw(in: NSRect(x: r.minX + 12, y: r.midY - 8, width: 16, height: 16), color: (hi ? p.accent : p.muted).ns)
        } else {
            ItemIcon.drawFolder(in: NSRect(x: r.minX + 12, y: r.midY - 8, width: 16, height: 16), palette: p, lit: hi)
        }
        let textX = r.minX + 12 + 16 + 10
        let room = r.maxX - 10 - textX
        let slash = row.text.lastIndex(of: "/").map { row.text.index(after: $0) } ?? row.text.startIndex
        let dir = String(row.text[..<slash]), leaf = String(row.text[slash...])
        let dirBold = min(row.boldLength, dir.count)
        let leafBold = max(0, min(row.boldLength - dir.count, leaf.count))
        // `.ta-row`: the directory muted, the typed part of the name bold in the text colour, the rest text-2.
        let strong: [NSAttributedString.Key: Any] = [.font: Typeface.mono(13, weight: 700), .foregroundColor: p.text.ns]
        let plain: [NSAttributedString.Key: Any] = [.font: Typeface.mono(13), .foregroundColor: (hi ? p.text : p.text2).ns]
        let dim: [NSAttributedString.Key: Any] = [.font: Typeface.mono(13), .foregroundColor: p.muted.ns]
        _ = dirBold
        let dirText = NSAttributedString(string: dir, attributes: dim)
        let leafText = NSMutableAttributedString(string: String(leaf.prefix(leafBold)), attributes: strong)
        leafText.append(NSAttributedString(string: String(leaf.dropFirst(leafBold)), attributes: plain))
        let leafW = min(ceil(leafText.size().width), room)
        let dirW = max(0, min(ceil(dirText.size().width), room - leafW))
        let font = Typeface.mono(13)
        if dirW > 0 { drawAttributed(dirText, x: textX, midY: r.midY, width: dirW, font: font) }
        drawAttributed(leafText, x: textX + dirW, midY: r.midY, width: leafW, font: font)
    }

    /// `.mi`: folder and name in Geist 500; the folder on the path (`.mi.cur`) in the text colour with
    /// the accent tick at the right.
    private func drawMenuRow(_ row: DropdownRow, in r: NSRect, hi: Bool, keyboard: Bool, _ p: ThemeColors) {
        let tone = row.isCurrent || hi ? p.text : p.text2
        if hi {
            fillRounded(r, radius: 8, p.text.withAlpha(0.07))
            if keyboard { strokeRounded(r.insetBy(dx: 1, dy: 1), radius: 7, p.accent, width: 2) }
        }
        ItemIcon.drawFolder(in: NSRect(x: r.minX + 10, y: r.midY - 8, width: 16, height: 16), palette: p, lit: row.isCurrent)
        let tick: CGFloat = row.isCurrent ? 24 : 0
        drawLine(row.text, font: Typeface.ui(13, weight: 500), color: tone, x: r.minX + 10 + 16 + 9, midY: r.midY,
                 maxWidth: r.maxX - 10 - tick - (r.minX + 35))
        if row.isCurrent {
            Glyph.check.draw(in: NSRect(x: r.maxX - 10 - 14, y: r.midY - 7, width: 14, height: 14), color: p.accent.ns)
        }
    }

    // MARK: Accessibility: one button per row, so a test can count and press them.

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? {
        guard let owner else { return nil }
        return owner.content.rows.enumerated().map { i, row in
            let e = DropdownRowElement()
            e.setAccessibilityRole(.button)
            e.setAccessibilityLabel(row.text)
            e.setAccessibilityTitle(row.text)
            e.setAccessibilityParent(self)
            e.setAccessibilityFrameInParentSpace(rowRect(i))
            e.press = { [weak owner] in owner?.onPick?(i) }
            return e
        }
    }
}

final class DropdownRowElement: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return true }
}

/// Above the scrolling rows: nothing to draw in D4 (kept as the place the panel's edge would go).
final class DropdownOverlay: NSView {
    weak var owner: DropdownView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
