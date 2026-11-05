import AppKit
import FolioCore

/// What the strip shows for one tab.
struct TabItem: Equatable {
    let id: UUID
    let title: String
    let isHome: Bool
    /// The folder a file dropped on the tab goes into (nil for Home).
    let folder: URL?
}

/// The tab strip under the title bar (D1 has none, so it is drawn in D1's language): mono labels, the
/// active tab on the s1 surface with an accent underline, corner brackets on hover, a + at the end.
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

    private static let lead: CGFloat = 10
    private static let maxW: CGFloat = 220, minW: CGFloat = 84
    private static let plusW: CGFloat = 32
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

    // MARK: Geometry

    private var readoutW: CGFloat { 96 }

    private var tabWidth: CGFloat {
        guard !items.isEmpty else { return Self.maxW }
        let room = bounds.width - Self.lead - Self.plusW - 8 - readoutW
        return min(Self.maxW, max(Self.minW, floor(room / CGFloat(items.count))))
    }

    func tabRect(_ i: Int) -> NSRect {
        NSRect(x: Self.lead + CGFloat(i) * tabWidth, y: 5, width: tabWidth, height: bounds.height - 5)
    }

    private func closeRect(_ i: Int) -> NSRect {
        let r = tabRect(i)
        return NSRect(x: r.maxX - 26, y: r.midY - 9, width: 18, height: 18)
    }

    private var plusRect: NSRect {
        let x = Self.lead + CGFloat(items.count) * tabWidth + 4
        return NSRect(x: x, y: 7, width: 28, height: bounds.height - 12)
    }

    private func index(at point: NSPoint) -> Int? {
        items.indices.first { tabRect($0).contains(point) }
    }

    /// The gap a dragged tab would land in (0...count).
    private func insertion(at point: NSPoint) -> Int {
        let w = tabWidth
        return max(0, min(items.count, Int(((point.x - Self.lead) / w).rounded())))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.bg)
        fillRect(NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1), p.line)
        let label = Typeface.mono(12, weight: 500), active = Typeface.mono(12, weight: 600)
        for (i, item) in items.enumerated() {
            let r = tabRect(i)
            let on = i == activeIndex
            if on {
                fillRect(NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height), p.s1)
                fillRect(NSRect(x: r.minX, y: r.minY, width: 1, height: r.height), p.line)
                fillRect(NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height), p.line)
                fillRect(NSRect(x: r.minX, y: r.minY, width: r.width, height: 1), p.line)
                // The accent underline, glowing in dark like the sorted column's.
                let line = NSRect(x: r.minX + 1, y: r.maxY - 2, width: r.width - 2, height: 2)
                if p.glows, let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: 9, color: p.accent.withAlpha(0.6).cg)
                    fillRect(line, p.accent)
                    ctx.restoreGState()
                } else {
                    fillRect(line, p.accent)
                }
            } else {
                if hovered == i { fillRect(r.insetBy(dx: 1, dy: 0), p.txt.withAlpha(0.06)) }
                let next = i + 1
                if next != activeIndex && next < items.count {
                    fillRect(NSRect(x: r.maxX - 0.5, y: r.minY + 8, width: 1, height: r.height - 16), p.line)
                }
            }
            if hovered == i && !on { drawBrackets(r.insetBy(dx: 1, dy: 1), color: p.bracket.ns, length: 7) }
            if dropTab == i {
                fillRect(r, p.markFill)
                strokeRounded(r.insetBy(dx: 0.5, dy: 0.5), radius: 2, p.accent)
                drawBrackets(r, color: p.accent.ns, length: 7)
            }
            let mid = r.midY
            let iconX = r.minX + 12
            if item.isHome {
                Glyph.home.draw(in: NSRect(x: iconX, y: mid - 7.5, width: 15, height: 15), color: (on ? p.accent : p.txt2).ns)
            } else {
                ItemIcon.drawFolder(in: NSRect(x: iconX, y: mid - 6.5, width: 16, height: 13), palette: p, lit: on)
            }
            let showClose = on || hovered == i
            let textX = iconX + 16 + 8
            let room = r.maxX - textX - (showClose ? 30 : 10)
            drawLine(item.title, font: on ? active : label, color: on ? p.txt : p.txt2, x: textX, midY: mid, maxWidth: room)
            if showClose {
                let c = closeRect(i)
                if hoveredClose && hovered == i { fillRounded(c, radius: 3, p.txt.withAlpha(0.12)) }
                Glyph.close.draw(in: c.insetBy(dx: 3, dy: 3), color: p.txt2.ns, lineWidth: 1.6)
            }
        }
        if let at = insertAt {
            let x = Self.lead + CGFloat(at) * tabWidth
            fillRect(NSRect(x: x - 1, y: 6, width: 2, height: bounds.height - 10), p.accent)
        }
        let plus = plusRect
        if hoveredPlus {
            fillRounded(plus, radius: 4, p.txt.withAlpha(0.08))
            drawBrackets(plus, color: p.bracket.ns, length: 6)
        }
        Glyph.plus.draw(in: NSRect(x: plus.midX - 8, y: plus.midY - 8, width: 16, height: 16), color: p.txt2.ns)
        // The readout at the right: which tab of how many.
        let readout = "TAB \(min(activeIndex + 1, items.count))/\(items.count)"
        drawLine(readout, font: Typeface.mono(11, weight: 500), color: p.txt3, x: bounds.width - 14, midY: bounds.height / 2 + 2,
                 alignRight: true, kern: 0.6)
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
        let onClose = i.map { closeRect($0).contains(p) } ?? false
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
        if closeRect(i).contains(start), i == activeIndex || hovered == i {
            // Closes when the button comes up over the x, as a button does.
            while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
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
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp { return }
            let p = convert(next.locationInWindow, from: nil)
            if !moved && hypot(p.x - start.x, p.y - start.y) < 4 { continue }
            moved = true
            if p.y < -24 || p.y > bounds.height + 24 || p.x < -24 || p.x > bounds.width + 24 {
                beginTabDrag(current, event: next)
                return
            }
            let target = max(0, min(items.count - 1, Int((p.x - Self.lead) / tabWidth)))
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
