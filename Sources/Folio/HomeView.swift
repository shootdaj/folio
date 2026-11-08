import AppKit
import FolioCore

/// What Home lists, gathered by the window.
struct HomeContent {
    var pins: [QuickAccessPlace] = []
    var favorites: [URL] = []
    var recentFiles: [URL] = []
    var recentLocations: [URL] = []
}

/// Home in the list's place: on the pane colour, scrolling D4 spotlight cards for Quick access (the
/// pins as tiles, in the sidebar's order), Favorites, Recent files and Recent locations. Each section
/// folds from its header and stays folded. Clicking a tile or a folder opens it here; a file opens in
/// its app.
final class HomePaneView: NSView {
    let scrollView = NSScrollView()
    let home = HomeView(frame: .zero)

    override init(frame: NSRect) {
        super.init(frame: frame)
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = home
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        home.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: max(home.fittingHeight(width: scrollView.contentSize.width), scrollView.contentSize.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        fillRect(bounds, p.pane)
    }
}

final class HomeView: NSView {
    enum Section: String, CaseIterable {
        case quickAccess, favorites, recentFiles, recentLocations
        var title: String {
            switch self {
            case .quickAccess: "Quick access"
            case .favorites: "Favorites"
            case .recentFiles: "Recent files"
            case .recentLocations: "Recent locations"
            }
        }
        var glyph: Glyph {
            switch self {
            case .quickAccess: .star
            case .favorites: .star
            case .recentFiles: .clock
            case .recentLocations: .mapPin
            }
        }
    }

    var content = HomeContent() { didSet { relayout() } }
    var onOpenFolder: ((URL) -> Void)?
    var onOpenFile: ((URL) -> Void)?
    var menuProvider: ((URL) -> NSMenu?)?

    private struct Hit { let rect: NSRect; let target: Target }
    private enum Target: Equatable { case header(Section), item(URL, isFolder: Bool, label: String) }
    private var hits: [Hit] = []
    private var panels: [(Section, NSRect)] = []
    private var hovered: Int?
    private var collapsed: Set<String>
    private static let collapsedKey = "homeCollapsed"
    private var axParts: [AddressPart] = []

    private static let pad: CGFloat = 18, headerH: CGFloat = 36, rowH: CGFloat = 30
    private static let tileW: CGFloat = 214, tileH: CGFloat = 62, tileGap: CGFloat = 10
    /// Native metrics: no cards, a 20 pt margin, rows inset 8 pt, Quick access as icon-over-label tiles.
    private enum NativeMetrics {
        static let pad: CGFloat = 20, headerH: CGFloat = 28, rowH: CGFloat = 28, rowInset: CGFloat = 8
        static let tileW: CGFloat = 96, tileH: CGFloat = 82, tileGap: CGFloat = 4, sectionGap: CGFloat = 12, top: CGFloat = 52
    }
    private var native: Bool { ThemeController.shared.isNative }

    override init(frame: NSRect) {
        collapsed = Set(UserDefaults.standard.stringArray(forKey: Self.collapsedKey) ?? [])
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Home")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize.width != frame.width
        super.setFrameSize(newSize)
        if changed { relayout() }
    }

    private func relayout() {
        layoutHits(width: bounds.width)
        superview?.superview?.superview?.needsLayout = true
        needsDisplay = true
    }

    func fittingHeight(width: CGFloat) -> CGFloat {
        layoutHits(width: width)
        return (panels.last?.1.maxY ?? 0) + (native ? NativeMetrics.pad : Self.pad)
    }

    private func items(_ s: Section) -> [(URL, Bool, String)] {
        switch s {
        case .quickAccess: content.pins.map { (URL(fileURLWithPath: $0.path, isDirectory: true), true, $0.title) }
        case .favorites: content.favorites.map { ($0, Self.isFolder($0), $0.lastPathComponent) }
        case .recentFiles: content.recentFiles.map { ($0, false, $0.lastPathComponent) }
        case .recentLocations: content.recentLocations.map { ($0, true, $0.path == "/" ? "/" : $0.lastPathComponent) }
        }
    }

    private static func isFolder(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
            && !((try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false)
    }

    /// Native layout: the same targets as D4, with no card borders and tighter rows.
    private func layoutHitsNative(width: CGFloat) {
        typealias M = NativeMetrics
        var out: [Hit] = []
        var boxes: [(Section, NSRect)] = []
        var y = M.top
        let x = M.pad, w = max(200, width - 2 * M.pad)
        for s in Section.allCases {
            let list = items(s)
            var h = M.headerH
            out.append(Hit(rect: NSRect(x: x - M.rowInset, y: y, width: w + 2 * M.rowInset, height: M.headerH), target: .header(s)))
            if !collapsed.contains(s.rawValue) {
                if s == .quickAccess {
                    let cols = max(1, Int((w + M.tileGap) / (M.tileW + M.tileGap)))
                    for (i, item) in list.enumerated() {
                        let r = NSRect(x: x + CGFloat(i % cols) * (M.tileW + M.tileGap),
                                       y: y + h + CGFloat(i / cols) * (M.tileH + M.tileGap), width: M.tileW, height: M.tileH)
                        out.append(Hit(rect: r, target: .item(item.0, isFolder: true, label: item.2)))
                    }
                    h += list.isEmpty ? M.rowH : CGFloat((list.count + cols - 1) / cols) * (M.tileH + M.tileGap)
                } else {
                    for (i, item) in list.enumerated() {
                        let r = NSRect(x: x - M.rowInset, y: y + h + CGFloat(i) * M.rowH, width: w + 2 * M.rowInset, height: M.rowH)
                        out.append(Hit(rect: r, target: .item(item.0, isFolder: item.1, label: item.2)))
                    }
                    h += CGFloat(max(1, list.count)) * M.rowH
                }
            }
            boxes.append((s, NSRect(x: x, y: y, width: w, height: h)))
            y += h + M.sectionGap
        }
        hits = out
        panels = boxes
        rebuildAccessibility()
    }

    private func layoutHits(width: CGFloat) {
        if native { layoutHitsNative(width: width); return }
        var out: [Hit] = []
        var boxes: [(Section, NSRect)] = []
        var y: CGFloat = 54
        let x = Self.pad, w = max(200, width - 2 * Self.pad)
        for s in Section.allCases {
            let list = items(s)
            let shut = collapsed.contains(s.rawValue)
            var h = 1 + Self.headerH
            out.append(Hit(rect: NSRect(x: x, y: y + 1, width: w, height: Self.headerH), target: .header(s)))
            if !shut {
                if s == .quickAccess {
                    let cols = max(1, Int((w - 20 + Self.tileGap) / (Self.tileW + Self.tileGap)))
                    let tileW = floor((w - 20 - CGFloat(cols - 1) * Self.tileGap) / CGFloat(cols))
                    for (i, item) in list.enumerated() {
                        let r = NSRect(x: x + 10 + CGFloat(i % cols) * (tileW + Self.tileGap),
                                       y: y + h + CGFloat(i / cols) * (Self.tileH + Self.tileGap), width: tileW, height: Self.tileH)
                        out.append(Hit(rect: r, target: .item(item.0, isFolder: true, label: item.2)))
                    }
                    let rows = list.isEmpty ? 1 : (list.count + cols - 1) / cols
                    h += CGFloat(rows) * (Self.tileH + Self.tileGap) + 4
                } else {
                    for (i, item) in list.enumerated() {
                        let r = NSRect(x: x + 5, y: y + h + CGFloat(i) * Self.rowH, width: w - 10, height: Self.rowH)
                        out.append(Hit(rect: r, target: .item(item.0, isFolder: item.1, label: item.2)))
                    }
                    h += CGFloat(max(1, list.count)) * Self.rowH + 8
                }
            }
            h += 1
            boxes.append((s, NSRect(x: x, y: y, width: w, height: h)))
            y += h + 14
        }
        hits = out
        panels = boxes
        rebuildAccessibility()
    }

    // MARK: Drawing

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static let nativeDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func emptyText(_ s: Section) -> String {
        switch s {
        case .quickAccess: "Nothing pinned: right-click a folder and pick Pin to Quick access"
        case .favorites: "No favorites yet: right-click a file and pick Add to Favorites"
        case .recentFiles: "Files you open from Folio show here"
        case .recentLocations: "Folders you visit show here"
        }
    }

    /// Native drawing: a plain list on the pane colour, with Finder's type and colours.
    private func drawNative() {
        typealias M = NativeMetrics
        drawLine("Home", font: .systemFont(ofSize: 20, weight: .semibold), color: .labelColor, x: M.pad, midY: 28)
        for (s, r) in panels {
            let shut = collapsed.contains(s.rawValue)
            let mid = r.minY + M.headerH / 2
            Glyph.chevronDown.draw(in: NSRect(x: r.minX - 4, y: mid - 7, width: 14, height: 14), color: .secondaryLabelColor,
                                   rotation: shut ? -.pi / 2 : 0)
            let tw = drawLine(s.title, font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor, x: r.minX + 14, midY: mid)
            drawLine("\(items(s).count)", font: .systemFont(ofSize: 11), color: .tertiaryLabelColor, x: r.minX + 14 + tw + 6, midY: mid)
            if !shut, items(s).isEmpty {
                drawLine(emptyText(s), font: .systemFont(ofSize: 13), color: .secondaryLabelColor, x: r.minX,
                         midY: r.minY + M.headerH + M.rowH / 2, maxWidth: r.width)
            }
        }
        for (i, hit) in hits.enumerated() {
            guard case .item(let url, let isFolder, let label) = hit.target else { continue }
            let r = hit.rect
            if hovered == i { fillRounded(r, radius: 6, .quaternarySystemFill) }
            if r.height == M.tileH {
                FinderIcon.draw(name: url.lastPathComponent, isDir: true, isLink: false,
                                in: NSRect(x: r.midX - 20, y: r.minY + 8, width: 40, height: 40))
                let font = NSFont.systemFont(ofSize: 12)
                let lw = min(textWidth(label, font: font), r.width - 8)
                drawLine(label, font: font, color: .labelColor, x: r.midX - lw / 2, midY: r.minY + 62, maxWidth: r.width - 8)
            } else {
                let mid = r.midY
                FinderIcon.draw(name: url.lastPathComponent, isDir: isFolder, isLink: false,
                                in: NSRect(x: r.minX + M.rowInset, y: mid - 9, width: 18, height: 18))
                let dateW: CGFloat = 150
                let left = r.minX + M.rowInset + 18 + 8
                let nameW = drawLine(label, font: .systemFont(ofSize: 13), color: .labelColor, x: left, midY: mid,
                                     maxWidth: (r.width - 34) * 0.45)
                let folder = (isFolder ? url.path : (url.path as NSString).deletingLastPathComponent)
                    .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
                drawLine(folder, font: .systemFont(ofSize: 13), color: .secondaryLabelColor, x: left + nameW + 12, midY: mid,
                         maxWidth: r.maxX - dateW - (left + nameW + 12) - M.rowInset)
                if !isFolder, let date = (try? url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate {
                    drawLine(Self.nativeDateFormatter.string(from: date), font: .systemFont(ofSize: 13), color: .secondaryLabelColor,
                             x: r.maxX - M.rowInset, midY: mid, alignRight: true)
                }
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if native { drawNative(); return }
        let p = ThemeColors.current
        // Title strip: Home and what it holds, in mono labels.
        let titleW = drawLine("Home", font: Typeface.ui(18, weight: 700), color: p.text, x: Self.pad, midY: 28)
        let summary = "\(content.pins.count) PINNED  \(content.favorites.count) FAVORITES  \(content.recentFiles.count) RECENT"
        let summaryFont = Typeface.mono(11, weight: 500)
        // The readout only where it fits beside the title.
        if textWidth(summary, font: summaryFont, kern: 0.6) + titleW + 24 < bounds.width - 2 * Self.pad {
            drawLine(summary, font: summaryFont, color: p.muted, x: bounds.width - Self.pad, midY: 29, alignRight: true, kern: 0.6)
        }
        for (s, r) in panels {
            // A spotlight card: s1, a hairline, radius 12, a mono uppercase label and its count.
            fillRounded(r, radius: 12, p.s1)
            strokeRounded(r, radius: 12, p.line)
            let mid = r.minY + 1 + Self.headerH / 2
            let tw = drawLine(Typeface.caption(s.title), font: Typeface.mono(12, weight: 600), color: p.muted, x: r.minX + 14, midY: mid,
                              kern: Typeface.labelKern(12))
            drawLine("\(items(s).count)", font: Typeface.mono(12, weight: 500), color: p.muted, x: r.minX + 14 + tw + 6, midY: mid)
            Glyph.chevronDown.draw(in: NSRect(x: r.maxX - 10 - 16, y: mid - 8, width: 16, height: 16), color: p.muted.ns,
                                   rotation: collapsed.contains(s.rawValue) ? -.pi / 2 : 0)
            if !collapsed.contains(s.rawValue), items(s).isEmpty {
                let empty = switch s {
                case .quickAccess: "Nothing pinned: right-click a folder and pick Pin to Quick access"
                case .favorites: "No favorites yet: right-click a file and pick Add to Favorites"
                case .recentFiles: "Files you open from Folio show here"
                case .recentLocations: "Folders you visit show here"
                }
                drawLine(empty, font: Typeface.mono(12), color: p.muted, x: r.minX + 16, midY: r.minY + 1 + Self.headerH + 15,
                         maxWidth: r.width - 32)
            }
        }
        for (i, hit) in hits.enumerated() {
            let hot = hovered == i
            switch hit.target {
            case .header:
                break
            case .item(let url, let isFolder, let label):
                if hit.rect.height == Self.tileH {
                    drawTile(url, label: label, in: hit.rect, hot: hot, p)
                } else {
                    drawRow(url, isFolder: isFolder, label: label, in: hit.rect, hot: hot, p)
                }
            }
        }
    }

    private func drawTile(_ url: URL, label: String, in r: NSRect, hot: Bool, _ p: ThemeColors) {
        fillRounded(r, radius: 12, p.s2)
        strokeRounded(r, radius: 12, hot ? p.accent.mixed(0.45, with: p.line) : p.line)
        if hot { drawCursorGlow(in: r.insetBy(dx: 1, dy: 1), center: NSPoint(x: r.minX + r.width * 0.3, y: r.midY), radius: 200,
                                color: p.accent, alpha: p.glowAlpha) }
        ItemIcon.drawFolder(in: NSRect(x: r.minX + 14, y: r.midY - 12, width: 24, height: 24), palette: p, lit: hot)
        drawLine(label, font: Typeface.ui(13, weight: 600), color: p.text, x: r.minX + 52, midY: r.minY + 22,
                 maxWidth: r.width - 62)
        let parent = (url.path as NSString).deletingLastPathComponent.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        drawLine(parent, font: Typeface.mono(11), color: p.muted, x: r.minX + 52, midY: r.minY + 41, maxWidth: r.width - 62)
    }

    private func drawRow(_ url: URL, isFolder: Bool, label: String, in r: NSRect, hot: Bool, _ p: ThemeColors) {
        if hot { fillRounded(r, radius: 8, p.text.withAlpha(0.07)) }
        let mid = r.midY
        ItemIcon.draw(name: url.lastPathComponent, isFolder: isFolder, in: NSRect(x: r.minX + 10, y: mid - 8, width: 16, height: 16),
                      palette: p, glow: hot)
        let dateW: CGFloat = 130
        let nameW = drawLine(label, font: Typeface.ui(13, weight: 500), color: p.text, x: r.minX + 38, midY: mid,
                             maxWidth: (r.width - 38) * 0.45)
        let folder = (isFolder ? url.path : (url.path as NSString).deletingLastPathComponent)
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        drawLine(folder, font: Typeface.mono(12), color: p.muted, x: r.minX + 38 + nameW + 14, midY: mid,
                 maxWidth: r.maxX - dateW - (r.minX + 38 + nameW + 14) - 8)
        if !isFolder, let date = (try? url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate {
            drawLine(Self.dateFormatter.string(from: date), font: Typeface.mono(12), color: p.text2, x: r.maxX - 10, midY: mid, alignRight: true)
        }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func hitIndex(_ event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return hits.indices.first { hits[$0].rect.contains(point) }
    }

    override func mouseMoved(with event: NSEvent) {
        let i = hitIndex(event)
        if i != hovered { hovered = i; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard let i = hitIndex(event) else { return }
        press(hits[i].target)
    }

    private func press(_ target: Target) {
        switch target {
        case .header(let s):
            if collapsed.contains(s.rawValue) { collapsed.remove(s.rawValue) } else { collapsed.insert(s.rawValue) }
            UserDefaults.standard.set(Array(collapsed).sorted(), forKey: Self.collapsedKey)
            relayout()
        case .item(let url, let isFolder, _):
            if isFolder { onOpenFolder?(url) } else { onOpenFile?(url) }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let i = hitIndex(event), case .item(let url, _, _) = hits[i].target else { return nil }
        return menuProvider?(url)
    }

    // MARK: Accessibility: every header and item is a button.

    private func rebuildAccessibility() {
        axParts = hits.map { hit in
            let e = AddressPart()
            e.setAccessibilityRole(.button)
            switch hit.target {
            case .header(let s): e.setAccessibilityLabel(s.title + " section")
            case .item(_, _, let label): e.setAccessibilityLabel(label)
            }
            e.setAccessibilityParent(self)
            e.setAccessibilityFrameInParentSpace(hit.rect)
            let target = hit.target
            e.press = { [weak self] in self?.press(target) }
            return e
        }
    }

    override func accessibilityChildren() -> [Any]? { axParts }
}
