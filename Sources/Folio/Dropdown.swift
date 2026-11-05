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
    /// Under the address bar at its full width: header, rows of full paths, key footer (D1 `.ta`).
    case field(header: String, count: String)
    /// A folder list under a crumb arrow or a toolbar button (D1 `.menu`).
    case menu
}

struct DropdownContent: Equatable {
    var style: DropdownStyle
    /// The panel's window title, which is also its accessibility name ("Folders in Code").
    var title: String
    var rows: [DropdownRow]
    var empty: String
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
    /// sizes to its rows and starts 6 pt left of the anchor, as D1 places `.menu`.
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

/// Draws a dropdown the D1 way. Field style (`.ta`): s3 panel, line-2 border, accent corner brackets,
/// a 32 pt header, 32 pt rows with a light, folder icon and the path (typed part bold), a key footer.
/// Menu style (`.menu`): 30 pt rows of folder names in Chivo Mono, the current one in the accent.
final class DropdownView: NSView {
    var content: DropdownContent { didSet { rowsView.needsDisplay = true; needsDisplay = true; needsLayout = true } }
    private(set) var highlighted: Int?
    private var keyboardHighlight = false
    var onPick: ((Int) -> Void)?

    private let scroll = NSScrollView()
    private let rowsView = DropdownRowsView()
    private let overlay = DropdownOverlay()

    static let pad: CGFloat = 4
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
        let font = Typeface.mono(13, weight: 500)
        let widest = content.rows.map { textWidth($0.text, font: font) }.max() ?? textWidth(content.empty, font: Typeface.ui(13))
        let w = 2 + 2 * Self.pad + 10 + 18 + 10 + widest + 10
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
        let p = Palette.current
        fillRounded(bounds, radius: 4, p.s3)
        strokeRounded(bounds, radius: 4, p.line2)
        guard case .field(let header, let count) = content.style else { return }
        let mid = 1 + Self.headerH / 2
        drawLine(header, font: Typeface.ui(12, weight: 650, width: 116), color: p.txt2, x: 13, midY: mid,
                 maxWidth: bounds.width - 120)
        drawLine(count, font: Typeface.mono(12), color: p.txt2, x: bounds.width - 13, midY: mid, alignRight: true)
        fillRect(NSRect(x: 1, y: Self.headerH, width: bounds.width - 2, height: 1), p.line)
        // Footer: "Tab fills, Enter opens, Esc cancels" with key caps.
        let footTop = bounds.height - 1 - Self.pad - Self.footerH
        fillRect(NSRect(x: 1, y: footTop, width: bounds.width - 2, height: 1), p.line)
        let lineMid = footTop + 1 + 9 + 13
        var x: CGFloat = 13
        let body = Typeface.ui(13)
        for (key, words, tall) in [("Tab", " fills, ", false), ("Enter", " opens, ", false), ("Esc", " cancels", true)] {
            x += drawKey(key, x: x, midY: lineMid, height: tall ? 24 : 20, p) + 2
            x += drawLine(words, font: body, color: p.txt2, x: x, midY: lineMid)
        }
    }

    /// D1's `kbd`: s2 cap, line-3 border with a 2 pt bottom, Chivo Mono 12.
    private func drawKey(_ key: String, x: CGFloat, midY: CGFloat, height: CGFloat, _ p: Palette) -> CGFloat {
        let font = Typeface.mono(12, weight: 500)
        let w = textWidth(key, font: font) + 12 + 2
        let r = NSRect(x: x, y: (midY - height / 2).rounded(), width: w, height: height)
        fillRounded(r, radius: 3, p.line3)
        fillRounded(NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 2, height: r.height - 3), radius: 2, p.s2)
        drawLine(key, font: font, color: p.txt, x: r.minX + 7, midY: r.minY + 1 + (r.height - 3) / 2)
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
        // D1 keeps the typeahead highlight where the pointer left it; menus drop it.
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
        let p = Palette.current
        let content = owner.content
        if content.rows.isEmpty {
            drawLine(content.empty, font: Typeface.ui(13), color: p.txt2, x: DropdownView.pad + 12,
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
    private func drawFieldRow(_ row: DropdownRow, in r: NSRect, hi: Bool, _ p: Palette) {
        if hi {
            fillRounded(r, radius: 3, p.selectionFill)
            drawBrackets(r, color: p.accent.ns, length: 6)
            let dot = NSRect(x: r.minX + 10, y: r.midY - 3, width: 6, height: 6)
            p.accent.withAlpha(0.18).ns.setFill()
            NSBezierPath(ovalIn: dot.insetBy(dx: -2, dy: -2)).fill()
            p.accent.ns.setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
        ItemIcon.drawFolder(in: NSRect(x: r.minX + 26, y: r.midY - 7.5, width: 18, height: 15), palette: p, lit: hi)
        let textX = r.minX + 26 + 18 + 10
        let room = r.maxX - 10 - textX
        let slash = row.text.lastIndex(of: "/").map { row.text.index(after: $0) } ?? row.text.startIndex
        let dir = String(row.text[..<slash]), leaf = String(row.text[slash...])
        let dirBold = min(row.boldLength, dir.count)
        let leafBold = max(0, min(row.boldLength - dir.count, leaf.count))
        let strong: [NSAttributedString.Key: Any] = [.font: Typeface.mono(13, weight: 600), .foregroundColor: (hi ? p.accent : p.txt).ns]
        let plain: [NSAttributedString.Key: Any] = [.font: Typeface.mono(13), .foregroundColor: (hi ? p.txt : p.txt2).ns]
        func styled(_ s: String, bold: Int) -> NSAttributedString {
            let out = NSMutableAttributedString(string: String(s.prefix(bold)), attributes: strong)
            out.append(NSAttributedString(string: String(s.dropFirst(bold)), attributes: plain))
            return out
        }
        let dirText = styled(dir, bold: dirBold), leafText = styled(leaf, bold: leafBold)
        let leafW = min(ceil(leafText.size().width), room)
        let dirW = max(0, min(ceil(dirText.size().width), room - leafW))
        let font = Typeface.mono(13)
        if dirW > 0 { drawAttributed(dirText, x: textX, midY: r.midY, width: dirW, font: font) }
        drawAttributed(leafText, x: textX + dirW, midY: r.midY, width: leafW, font: font)
    }

    /// `.mi`: folder and name; `.mi.cur` in the accent with a fill and brackets.
    private func drawMenuRow(_ row: DropdownRow, in r: NSRect, hi: Bool, keyboard: Bool, _ p: Palette) {
        let tone = row.isCurrent ? p.accent : p.txt
        if row.isCurrent {
            fillRounded(r, radius: 3, p.selectionFill)
            drawBrackets(r.insetBy(dx: 2, dy: 0), color: p.accent.ns, length: 6)
        }
        if hi {
            fillRounded(r, radius: 3, tone.withAlpha(keyboard ? 0.10 : 0.08))
            if keyboard { strokeRounded(r.insetBy(dx: 2, dy: 2), radius: 2, p.accent, width: 2) }
        }
        ItemIcon.drawFolder(in: NSRect(x: r.minX + 10, y: r.midY - 7.5, width: 18, height: 15), palette: p, lit: row.isCurrent)
        drawLine(row.text, font: Typeface.mono(13, weight: 500), color: tone, x: r.minX + 10 + 18 + 10, midY: r.midY,
                 maxWidth: r.maxX - 10 - (r.minX + 38))
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

/// Field-style corner brackets in the accent, above the scrolling rows.
final class DropdownOverlay: NSView {
    weak var owner: DropdownView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard owner?.isField == true else { return }
        drawBrackets(bounds, color: Palette.current.accent.ns, length: 10)
    }
}
