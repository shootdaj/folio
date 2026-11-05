import AppKit
import FolioCore

/// The breadcrumb address bar (`.addr`). Each crumb jumps to its folder; the last is in the accent.
/// Clicking empty space, Cmd+L or Option+D turns the crumbs into an editable path; Esc puts them back.
/// The chevrons after the crumbs are drawn now; their folder flyouts come in milestone 2.
final class AddressBarView: NSView, NSTextFieldDelegate {
    var onNavigate: ((URL) -> Void)?
    var onEndEditing: (() -> Void)?
    var onEditingChanged: (() -> Void)?

    private(set) var folder = URL(fileURLWithPath: "/")
    private var crumbs: [Crumb] = []
    private var hovered: Int?          // crumb index under the mouse
    private var isHovered = false
    private(set) var isEditing = false
    private let field = NSTextField(string: "")

    private static let iconWidth: CGFloat = 40
    private static let arrowWidth: CGFloat = 30
    private static let crumbPad: CGFloat = 8
    private static let minHit: CGFloat = 40

    override init(frame: NSRect) {
        super.init(frame: frame)
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
        crumbs = Breadcrumbs.crumbs(for: url)
        if isEditing { endEditing(restore: true) }
        needsDisplay = true
    }

    // MARK: Layout of the crumbs

    private struct Slot { let rect: NSRect; let crumb: Int?; let isArrow: Bool }

    private var crumbFont: NSFont { Typeface.mono(13, weight: 500) }
    private var currentFont: NSFont { Typeface.mono(13, weight: 600) }

    /// Crumb and arrow rects, right-aligned and clipped on the left when the path is too long.
    private func slots() -> (slots: [Slot], clipped: Bool) {
        var items: [(width: CGFloat, crumb: Int?, arrow: Bool)] = []
        let isRoot = crumbs.count == 1 && crumbs[0].path == "/"
        if !isRoot { items.append((Self.arrowWidth, nil, true)) }
        for (i, crumb) in crumbs.enumerated() {
            let font = crumb.isCurrent ? currentFont : crumbFont
            items.append((textWidth(crumb.title, font: font) + 2 * Self.crumbPad, i, false))
            items.append((Self.arrowWidth, i, true))
        }
        let total = items.reduce(0) { $0 + $1.width }
        let room = bounds.width - Self.iconWidth - Self.minHit
        var x = Self.iconWidth + min(0, room - total)
        var out: [Slot] = []
        for item in items {
            out.append(Slot(rect: NSRect(x: x, y: 1, width: item.width, height: bounds.height - 2),
                            crumb: item.crumb, isArrow: item.arrow))
            x += item.width
        }
        return (out, total > room)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        let box = bounds
        fillRounded(box, radius: 5, p.s2)
        let border: RGBA = isEditing ? p.accent : (isHovered ? p.line3 : p.line2)
        strokeRounded(box, radius: 5, border)
        // Folder icon in a 40 pt well.
        ItemIcon.drawFolder(in: NSRect(x: 11, y: box.midY - 7.5, width: 18, height: 15), palette: p, lit: false)
        guard !isEditing else { return }

        let (slots, clipped) = slots()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: Self.iconWidth, y: 0, width: box.width - Self.iconWidth, height: box.height)).addClip()
        for slot in slots {
            if let i = hovered, slot.crumb == i, !slot.isArrow {
                fillRounded(slot.rect.insetBy(dx: 0, dy: 0), radius: 3, p.txt.withAlpha(0.08))
            }
            if slot.isArrow {
                let s: CGFloat = 14
                Glyph.chevron.draw(in: NSRect(x: slot.rect.midX - s / 2, y: box.midY - s / 2, width: s, height: s),
                                   color: p.txt3.ns)
            } else if let i = slot.crumb {
                let crumb = crumbs[i]
                drawLine(crumb.title, font: crumb.isCurrent ? currentFont : crumbFont,
                         color: crumb.isCurrent ? p.accent : p.txt,
                         x: slot.rect.minX + Self.crumbPad, midY: box.midY)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        if clipped {
            // D1 masks the first 22 pt of clipped crumbs into the bar.
            let fade = NSGradient(starting: p.s2.ns, ending: p.s2.withAlpha(0).ns)
            fade?.draw(in: NSRect(x: Self.iconWidth, y: 1, width: 22, height: box.height - 2), angle: 0)
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
        let hit = slots().slots.first { !$0.isArrow && $0.rect.contains(point) && $0.rect.minX >= Self.iconWidth }?.crumb
        if hit != hovered { hovered = hit; needsDisplay = true }
        // D1's empty address area takes a text cursor; crumbs and arrows keep the arrow.
        let onSlot = slots().slots.contains { $0.rect.contains(point) && $0.rect.minX >= Self.iconWidth }
        (onSlot || isEditing || point.x < Self.iconWidth ? NSCursor.arrow : NSCursor.iBeam).set()
    }

    override func mouseDown(with event: NSEvent) {
        guard !isEditing else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let slot = slots().slots.first(where: { $0.rect.contains(point) && $0.rect.minX >= Self.iconWidth }) {
            if !slot.isArrow, let i = slot.crumb {
                onNavigate?(URL(fileURLWithPath: crumbs[i].path, isDirectory: true))
            }
            return  // arrow flyouts arrive in milestone 2
        }
        beginEditing()
    }

    // MARK: Editing

    /// Crumbs become the full path, selected, with an accent caret.
    func beginEditing() {
        guard !isEditing, let window else { return }
        isEditing = true
        hovered = nil
        let p = Palette.current
        field.font = Typeface.mono(13, weight: 500)
        field.textColor = p.txt.ns
        field.stringValue = folder.path
        let h = ceil(field.font!.ascender - field.font!.descender) + 4
        field.frame = NSRect(x: Self.iconWidth, y: (bounds.height - h) / 2, width: bounds.width - Self.iconWidth - 12, height: h)
        field.isHidden = false
        window.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.insertionPointColor = p.accent.ns
            editor.selectedTextAttributes = [.backgroundColor: p.markFill.ns]
            editor.selectAll(nil)
        }
        needsDisplay = true
        onEditingChanged?()
    }

    func endEditing(restore: Bool) {
        guard isEditing else { return }
        isEditing = false
        field.isHidden = true
        field.abortEditing()
        needsDisplay = true
        onEditingChanged?()
        onEndEditing?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            endEditing(restore: true)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            let home = FileManager.default.homeDirectoryForCurrentUser
            var isDirectory: ObjCBool = false
            if let url = Breadcrumbs.resolve(typed: field.stringValue, current: folder, home: home),
               FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                endEditing(restore: false)
                onNavigate?(url)
            } else {
                NSSound.beep()
            }
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        // Focus left the field (a click elsewhere): back to crumbs.
        if isEditing { endEditing(restore: true) }
    }
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

/// The 56 pt toolbar (`.toolbar`): Back, Forward, Up, the address bar, Refresh and the search box.
final class ToolbarView: NSView {
    let back: ChromeButton
    let forward: ChromeButton
    let up: ChromeButton
    let refresh: ChromeButton
    let address = AddressBarView(frame: .zero)
    let search = SearchBoxView(frame: .zero)

    init(target: AnyObject?, back: Selector, forward: Selector, up: Selector, refresh: Selector) {
        self.back = ChromeButton(glyph: .back, label: "Back (Cmd+Left)", target: target, action: back)
        self.forward = ChromeButton(glyph: .forward, label: "Forward (Cmd+Right)", target: target, action: forward)
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
        address.frame = NSRect(x: 154, y: y, width: max(80, refresh.frame.minX - 8 - 154), height: 44)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.s1)
        fillRect(NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1), p.line)
        if address.isEditing {
            // The 3 pt accent ring around the address bar while editing (`.addr.mode-address`).
            fillRounded(address.frame.insetBy(dx: -3, dy: -3), radius: 8, p.accent.withAlpha(0.16))
        }
    }
}
