import AppKit
import FolioCore

/// What the strip shows for one tab.
struct TabItem: Equatable {
    let id: UUID
    let title: String
    let page: SpecialPlace?
    /// The tab shows search results (a magnifier instead of the folder).
    var isSearch = false
    /// The folder a file dropped on the tab goes into (nil for Home).
    let folder: URL?
}

/// The tabs in the title bar (D4's `.tabs`): each sized to its title (at most 260 pt), the active one on
/// the toolbar's surface with hairline sides and a plain 2 pt accent underline, a + after the last.
/// Click selects, the x or a middle-click closes, double-click on empty space opens a new tab. Drag a
/// tab sideways to reorder it; drag it off the strip (up, down or past the window's edge) to tear it
/// out into its own window, or onto another Folio window's strip to move it there. Files dragged over a tab switch to it after a moment,
/// and dropping them on a tab moves or copies them into that tab's folder.
final class TabStripView: NSView, NSDraggingSource {
    static let tabType = NSPasteboard.PasteboardType("com.anshul.folio.tab")

    var items: [TabItem] = [] { didSet { if items != oldValue { rebuildAccessibility(); needsDisplay = true } } }
    var activeIndex = 0 { didSet { if activeIndex != oldValue { rebuildAccessibility(); needsDisplay = true } } }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNew: (() -> Void)?
    var onMove: ((Int, Int) -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?
    /// A tab dragged off every strip: (its id, the screen point where it was let go).
    var onTearOut: ((UUID, NSPoint) -> Void)?
    /// A tab from another window dropped here: (that window's number, the tab's id, the index).
    var onReceive: ((Int, UUID, Int) -> Void)?
    weak var dropHost: DropHost?

    private var hovered: Int?
    private var hoveredClose = false
    private var hoveredPlus = false
    private var dropTab: Int? { didSet { if dropTab != oldValue { needsDisplay = true } } }
    private var insertAt: Int? { didSet { if insertAt != oldValue { needsDisplay = true } } }
    private var springTimer: Timer?
    private var axParts: [AddressPart] = []

    private static let lead: CGFloat = 0
    private static let maxW: CGFloat = 260, minW: CGFloat = 84
    private static let plusW: CGFloat = 44
    private static let tabH: CGFloat = 36
    /// A drag that set this was dropped on a strip (so the source does not tear the tab out).
    @MainActor static var dropAccepted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([Self.tabType] + droppableTypes)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Tabs")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// The strip sits in the window's title bar area: a press there is the strip's (select, reorder, tear
    /// out), never a window drag; empty space moves the window from mouseDown.
    override var mouseDownCanMoveWindow: Bool { false }

    /// AppKit's title bar drags the window from any part of its area that no view claims; the strip claims
    /// all of itself, so a tab drag reorders or tears out instead of moving the window (as Chromium does
    /// for its tab strip in the same place).
    @objc(_opaqueRectForWindowMoveWhenInTitlebar)
    func opaqueRectForWindowMoveWhenInTitlebar() -> NSRect { native ? .zero : bounds }

    /// Native look: flat equal-width tabs on a 28 pt row, with no icons and no underline.
    private var native: Bool { ThemeController.shared.look == .native }
    private static let nativeLead: CGFloat = 8, nativePlusW: CGFloat = 28, nativeMaxW: CGFloat = 240
    private static let nativeTabH: CGFloat = 28, nativeMinW: CGFloat = 24

    // MARK: Geometry

    private var titleFont: NSFont { Typeface.ui(13, weight: 500) }

    /// `.tab-main`'s padding 13 and 12, the 15 pt icon and 8 pt gap, the title, and the 30 pt close
    /// button with its 4 pt margin when there is more than one tab.
    private func naturalWidth(_ item: TabItem) -> CGFloat {
        13 + 15 + 8 + textWidth(item.title, font: titleFont) + 12 + (items.count > 1 ? 34 : 0)
    }

    /// Each tab's width: its title's, cut down evenly when they do not all fit (2 pt apart).
    private var widths: [CGFloat] {
        if native {
            guard !items.isEmpty else { return [] }
            let room = bounds.width - Self.nativeLead - Self.nativePlusW
            let each = min(Self.nativeMaxW, max(Self.nativeMinW, floor(room / CGFloat(items.count))))
            return Array(repeating: each, count: items.count)
        }
        let natural = items.map { min(Self.maxW, ceil(naturalWidth($0))) }
        let room = bounds.width - Self.plusW - 2 * CGFloat(max(0, items.count))
        let total = natural.reduce(0, +)
        guard total > room, !natural.isEmpty else { return natural }
        let even = max(Self.minW, floor(room / CGFloat(natural.count)))
        return natural.map { min($0, even) }
    }

    func tabRect(_ i: Int) -> NSRect {
        let w = widths
        guard w.indices.contains(i) else { return .zero }
        if native {
            return NSRect(x: Self.nativeLead + w.prefix(i).reduce(0, +), y: bounds.height - Self.nativeTabH - 1,
                          width: w[i], height: Self.nativeTabH)
        }
        let x = Self.lead + w.prefix(i).reduce(0, +) + CGFloat(i) * 2
        return NSRect(x: x, y: bounds.height - Self.tabH, width: w[i], height: Self.tabH)
    }

    private func closeRect(_ i: Int) -> NSRect {
        let r = tabRect(i)
        if native { return NSRect(x: r.minX + 6, y: r.midY - 9, width: 18, height: 18) }
        return NSRect(x: r.maxX - 4 - 30, y: r.midY - 15, width: 30, height: 30)
    }

    private var plusRect: NSRect {
        if native {
            let end = items.isEmpty ? Self.nativeLead : tabRect(items.count - 1).maxX
            return NSRect(x: end, y: bounds.height - Self.nativeTabH - 1, width: Self.nativePlusW, height: Self.nativeTabH)
        }
        let end = items.isEmpty ? Self.lead : tabRect(items.count - 1).maxX + 2
        return NSRect(x: end, y: (bounds.height - 44) / 2, width: 44, height: 44)
    }

    private func index(at point: NSPoint) -> Int? {
        items.indices.first { tabRect($0).contains(point) }
    }

    /// The gap a dragged tab would land in (0...count).
    private func insertion(at point: NSPoint) -> Int {
        for i in items.indices where point.x < tabRect(i).midX { return i }
        return items.count
    }

    // MARK: Drawing

    /// Native look: the close mark shows on the active tab and under the pointer.
    private func closeVisible(_ i: Int) -> Bool { items.count > 1 && (i == activeIndex || hovered == i) }

    private func drawNative(_ p: ThemeColors) {
        for (i, item) in items.enumerated() {
            let r = tabRect(i)
            let on = i == activeIndex
            let fill = r.insetBy(dx: 1, dy: 1)
            if on {
                p.s3.setFill()
                NSBezierPath(roundedRect: fill, xRadius: 6, yRadius: 6).fill()
            } else if hovered == i {
                NSColor.quaternarySystemFill.setFill()
                NSBezierPath(roundedRect: fill, xRadius: 6, yRadius: 6).fill()
            }
            if dropTab == i { strokeRounded(fill, radius: 6, p.accent) }
            let font = NSFont.systemFont(ofSize: 12)
            let lineH = ceil(font.ascender - font.descender)
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style,
                .foregroundColor: on ? NSColor.labelColor : NSColor.secondaryLabelColor]
            let rect = NSRect(x: r.minX + 26, y: (r.midY - lineH / 2).rounded(), width: max(0, r.width - 52), height: lineH)
            NSAttributedString(string: item.title, attributes: attrs)
                .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            if closeVisible(i) {
                let c = closeRect(i)
                let hot = hoveredClose && hovered == i
                if hot {
                    NSColor.tertiarySystemFill.setFill()
                    NSBezierPath(roundedRect: c, xRadius: 4, yRadius: 4).fill()
                }
                drawSymbol("xmark", in: c, pointSize: 9, color: hot ? .labelColor : .secondaryLabelColor)
            }
        }
        if let at = insertAt {
            let x = at < items.count ? tabRect(at).minX : (items.isEmpty ? Self.nativeLead : tabRect(items.count - 1).maxX)
            NSColor.controlAccentColor.setFill()
            NSRect(x: x - 1, y: bounds.height - Self.nativeTabH + 3, width: 2, height: Self.nativeTabH - 6).fill()
        }
        let plus = plusRect
        if hoveredPlus {
            NSColor.quaternarySystemFill.setFill()
            NSBezierPath(roundedRect: plus.insetBy(dx: 2, dy: 3), xRadius: 6, yRadius: 6).fill()
        }
        drawSymbol("plus", in: plus, pointSize: 12, color: hoveredPlus ? .labelColor : .secondaryLabelColor)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    private func drawSymbol(_ name: String, in rect: NSRect, pointSize: CGFloat, color: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(.init(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let s = image.size
        image.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        if native { drawNative(p); return }
        for (i, item) in items.enumerated() {
            let r = tabRect(i)
            let on = i == activeIndex
            if on {
                // `.tab.on`: --bar-solid, top line-2 and sides line, radius 8 at the top, no bottom edge.
                let shape = topRounded(r, radius: 8)
                p.bar.ns.setFill()
                shape.fill()
                p.line.ns.setStroke()
                shape.lineWidth = 1
                topRounded(r.insetBy(dx: 0.5, dy: 0).offsetBy(dx: 0, dy: 0.5), radius: 7.5, open: true).stroke()
                p.line2.ns.setStroke()
                let top = NSBezierPath()
                top.move(to: NSPoint(x: r.minX + 8, y: r.minY + 0.5))
                top.line(to: NSPoint(x: r.maxX - 8, y: r.minY + 0.5))
                top.lineWidth = 1
                top.stroke()
                // A plain 2 pt accent underline, 12 pt in from each side, no glow.
                let line = NSRect(x: r.minX + 12, y: r.maxY - 2, width: r.width - 24, height: 2)
                p.accent.ns.setFill()
                NSBezierPath(roundedRect: line, xRadius: 1, yRadius: 1).fill()
            } else if hovered == i {
                p.text.withAlpha(0.05).ns.setFill()
                topRounded(r, radius: 8).fill()
            }
            if dropTab == i {
                fillRounded(r, radius: 8, p.markFill)
                strokeRounded(r, radius: 8, p.accent)
            }
            let mid = r.midY
            let iconX = r.minX + 13
            let icon = NSRect(x: iconX, y: mid - 7.5, width: 15, height: 15)
            if item.page == .home {
                Glyph.home.draw(in: icon, color: p.accent.ns)
            } else if item.page == .suggestions {
                Glyph.sparkles.draw(in: icon, color: p.accent.ns)
            } else if item.isSearch {
                Glyph.search.draw(in: icon, color: p.accent.ns)
            } else {
                ItemIcon.drawFolder(in: icon, palette: p, lit: false)
            }
            let showClose = items.count > 1
            let textX = iconX + 15 + 8
            let room = r.maxX - textX - (showClose ? 34 : 12)
            let tone: NSColor = on ? p.text : (hovered == i ? p.text2 : p.muted)
            drawLine(item.title, font: titleFont, color: tone, x: textX, midY: mid, maxWidth: room)
            if showClose {
                let c = closeRect(i)
                let hot = hoveredClose && hovered == i
                if hot { fillRounded(c.insetBy(dx: 5, dy: 5), radius: 8, p.text.withAlpha(0.08)) }
                Glyph.close.draw(in: NSRect(x: c.midX - 7, y: c.midY - 7, width: 14, height: 14), color: (hot ? p.text : p.text2).ns)
            }
        }
        if let at = insertAt {
            let x = at < items.count ? tabRect(at).minX - 1 : (items.isEmpty ? 0 : tabRect(items.count - 1).maxX + 1)
            fillRect(NSRect(x: x - 1, y: bounds.height - Self.tabH + 4, width: 2, height: Self.tabH - 8), p.accent)
        }
        let plus = plusRect
        if hoveredPlus { fillRounded(plus.insetBy(dx: 5, dy: 5), radius: 8, p.text.withAlpha(0.08)) }
        Glyph.plus.draw(in: NSRect(x: plus.midX - 8, y: plus.midY - 8, width: 16, height: 16), color: (hoveredPlus ? p.text : p.muted).ns)
    }

    /// A rect with only its top corners rounded; `open` leaves the bottom edge out (for stroking).
    private func topRounded(_ r: NSRect, radius: CGFloat, open: Bool = false) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX, y: r.maxY))
        path.line(to: NSPoint(x: r.minX, y: r.minY + radius))
        path.appendArc(withCenter: NSPoint(x: r.minX + radius, y: r.minY + radius), radius: radius, startAngle: 180, endAngle: 270)
        path.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
        path.appendArc(withCenter: NSPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: r.maxX, y: r.maxY))
        if !open { path.close() }
        return path
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = index(at: p)
        let onClose = items.count > 1 && (i.map { closeRect($0).contains(p) } ?? false)
        let onPlus = plusRect.contains(p)
        if i != hovered || onClose != hoveredClose || onPlus != hoveredPlus {
            hovered = i
            hoveredClose = onClose
            hoveredPlus = onPlus
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        hoveredClose = false
        hoveredPlus = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        if plusRect.contains(start) { onNew?(); return }
        guard let i = index(at: start) else {
            if event.clickCount == 2 { onNew?() } else { window?.performDrag(with: event) }
            return
        }
        if items.count > 1, closeRect(i).contains(start), !native || i == activeIndex || hovered == i {
            // Closes when the button comes up over the x, as a button does.
            guard let window else { return }
            while let next = MouseTracking.next(window, [.leftMouseUp, .leftMouseDragged]) {
                if next.type == .leftMouseUp {
                    if closeRect(i).contains(convert(next.locationInWindow, from: nil)) { onClose?(i) }
                    return
                }
            }
            return
        }
        onSelect?(i)
        trackDrag(from: start, index: i, event: event)
    }

    /// Sideways: the tab moves along the strip as it passes its neighbours. Off the strip: a real drag
    /// that another window's strip can take, or that tears the tab out where it is let go.
    private func trackDrag(from start: NSPoint, index: Int, event: NSEvent) {
        var current = index
        var moved = false
        guard let window else { return }
        while let next = MouseTracking.next(window, [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp { return }
            let p = convert(next.locationInWindow, from: nil)
            if !moved && hypot(p.x - start.x, p.y - start.y) < 4 { continue }
            moved = true
            if p.y < -24 || p.y > bounds.height + 24 || p.x < -24 || p.x > bounds.width + 24 {
                beginTabDrag(current, event: next)
                return
            }
            // The tab whose middle is nearest the pointer (tabs differ in width and sit 2 pt apart).
            let target = items.indices.min { abs(tabRect($0).midX - p.x) < abs(tabRect($1).midX - p.x) } ?? current
            if target != current {
                onMove?(current, target)
                current = target
            }
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, let i = index(at: convert(event.locationInWindow, from: nil)) else {
            return super.otherMouseDown(with: event)
        }
        onClose?(i)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let i = index(at: convert(event.locationInWindow, from: nil)) else { return nil }
        return menuProvider?(i)
    }

    // MARK: Dragging a tab out

    private func beginTabDrag(_ i: Int, event: NSEvent) {
        guard items.indices.contains(i), let window else { return }
        let item = NSPasteboardItem()
        item.setString("\(window.windowNumber):\(items[i].id.uuidString)", forType: Self.tabType)
        let drag = NSDraggingItem(pasteboardWriter: item)
        let r = tabRect(i)
        let image = NSImage(size: r.size)
        if let rep = bitmapImageRepForCachingDisplay(in: r) {
            cacheDisplay(in: r, to: rep)
            image.addRepresentation(rep)
        }
        drag.setDraggingFrame(r, contents: image)
        Self.dropAccepted = false
        let session = beginDraggingSession(with: [drag], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard !Self.dropAccepted,
              let raw = session.draggingPasteboard.string(forType: Self.tabType),
              let id = UUID(uuidString: String(raw.split(separator: ":").last ?? "")) else { return }
        onTearOut?(id, screenPoint)
    }

    // MARK: Dropping on the strip

    private func tabSource(_ info: NSDraggingInfo) -> (window: Int, id: UUID)? {
        guard let raw = info.draggingPasteboard.string(forType: Self.tabType) else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let number = Int(parts[0]), let id = UUID(uuidString: String(parts[1])) else { return nil }
        return (number, id)
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation { draggingUpdated(info) }

    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        let p = convert(info.draggingLocation, from: nil)
        if tabSource(info) != nil {
            dropTab = nil
            insertAt = insertion(at: p)
            return .move
        }
        insertAt = nil
        guard let i = index(at: p), let host = dropHost, let folder = items[i].folder else {
            clearDrop()
            return []
        }
        let action = host.dropAction(info, onto: folder)
        dropTab = action == .none ? nil : i
        springSelect(i)
        host.showDropTip(action, target: folder, info: info)
        return host.dragOperation(for: action, info)
    }

    /// Hovering a drag over a tab switches to it, so the drop can go into its list.
    private func springSelect(_ i: Int) {
        guard i != activeIndex else { springTimer?.invalidate(); springTimer = nil; return }
        if springTimer != nil { return }
        let timer = Timer(timeInterval: 0.6, repeats: false) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                self.springTimer = nil
                if let d = self.dropTab, d != self.activeIndex { self.onSelect?(d) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        springTimer = timer
    }

    private func clearDrop() {
        dropTab = nil
        insertAt = nil
        springTimer?.invalidate()
        springTimer = nil
        dropHost?.hideDropTip()
    }

    override func draggingExited(_ info: NSDraggingInfo?) { clearDrop() }
    override func draggingEnded(_ info: NSDraggingInfo) { clearDrop() }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        let p = convert(info.draggingLocation, from: nil)
        defer { clearDrop() }
        if let source = tabSource(info) {
            Self.dropAccepted = true
            onReceive?(source.window, source.id, insertion(at: p))
            return true
        }
        guard let i = dropTab, items.indices.contains(i), let folder = items[i].folder else { return false }
        return dropHost?.performDrop(info, onto: folder) ?? false
    }

    // MARK: Accessibility: each tab is a radio button (pressing it selects), + is a button.

    private func rebuildAccessibility() {
        var parts: [AddressPart] = []
        for (i, item) in items.enumerated() {
            let e = AddressPart()
            e.setAccessibilityRole(.radioButton)
            e.setAccessibilityLabel(item.title)
            e.setAccessibilityTitle(item.title)
            e.setAccessibilityValue(i == activeIndex ? 1 : 0)
            e.setAccessibilityParent(self)
            e.setAccessibilityFrameInParentSpace(tabRect(i))
            e.press = { [weak self] in self?.onSelect?(i) }
            parts.append(e)
        }
        let plus = AddressPart()
        plus.setAccessibilityRole(.button)
        plus.setAccessibilityLabel("New tab")
        plus.setAccessibilityParent(self)
        plus.setAccessibilityFrameInParentSpace(plusRect)
        plus.press = { [weak self] in self?.onNew?() }
        parts.append(plus)
        axParts = parts
    }

    override func layout() {
        super.layout()
        rebuildAccessibility()
    }

    override func accessibilityChildren() -> [Any]? { axParts }
}
