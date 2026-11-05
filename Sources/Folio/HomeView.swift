import AppKit
import FolioCore

/// What Home lists, gathered by the window.
struct HomeContent {
    var pins: [QuickAccessPlace] = []
    var favorites: [URL] = []
    var recentFiles: [URL] = []
    var recentLocations: [URL] = []
}

/// Home in the list's place: the s1 pane with its brackets, scrolling D1 panels for Quick access (the
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
        scrollView.frame = bounds.insetBy(dx: 1, dy: 1)
        home.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: max(home.fittingHeight(width: scrollView.contentSize.width), scrollView.contentSize.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRounded(bounds, radius: 4, p.s1)
        strokeRounded(bounds, radius: 4, p.line)
        drawBrackets(bounds, color: p.bracket.ns, length: 12)
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
        return (panels.last?.1.maxY ?? 0) + Self.pad
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

    private func layoutHits(width: CGFloat) {
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

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        // Title strip: HOME and what it holds, like the HUD's readouts.
        let titleW = drawLine("Home", font: Typeface.ui(18, weight: 750, width: 124), color: p.txt, x: Self.pad, midY: 28, kern: 0.2)
        let summary = "\(content.pins.count) PINNED  \(content.favorites.count) FAVORITES  \(content.recentFiles.count) RECENT"
        let summaryFont = Typeface.mono(11, weight: 500)
        // The readout only where it fits beside the title.
        if textWidth(summary, font: summaryFont, kern: 0.6) + titleW + 24 < bounds.width - 2 * Self.pad {
            drawLine(summary, font: summaryFont, color: p.txt3, x: bounds.width - Self.pad, midY: 29, alignRight: true, kern: 0.6)
        }
        for (s, r) in panels {
            fillRounded(r, radius: 4, p.s2)
            strokeRounded(r, radius: 4, p.line)
            drawBrackets(r.insetBy(dx: -1, dy: -1), color: p.accent.withAlpha(0.55).ns, length: 8)
            let mid = r.minY + 1 + Self.headerH / 2
            s.glyph.draw(in: NSRect(x: r.minX + 11, y: mid - 8, width: 16, height: 16), color: p.txt2.ns)
            let tw = drawLine(s.title, font: Typeface.ui(12, weight: 700, width: 124), color: p.txt, x: r.minX + 35, midY: mid, kern: 0.48)
            drawLine("\(items(s).count)", font: Typeface.mono(12), color: p.txt3, x: r.minX + 35 + tw + 8, midY: mid)
            Glyph.chevronDown.draw(in: NSRect(x: r.maxX - 11 - 16, y: mid - 8, width: 16, height: 16), color: p.txt2.ns,
                                   rotation: collapsed.contains(s.rawValue) ? -.pi / 2 : 0)
            if !collapsed.contains(s.rawValue), items(s).isEmpty {
                let empty = switch s {
                case .quickAccess: "Nothing pinned: right-click a folder and pick Pin to Quick access"
                case .favorites: "No favorites yet: right-click a file and pick Add to Favorites"
                case .recentFiles: "Files you open from Folio show here"
                case .recentLocations: "Folders you visit show here"
                }
                drawLine(empty, font: Typeface.mono(12), color: p.txt3, x: r.minX + 16, midY: r.minY + 1 + Self.headerH + 15,
                         maxWidth: r.width - 32)
            }
        }
        for (i, hit) in hits.enumerated() {
            let hot = hovered == i
            switch hit.target {
            case .header(let s):
                if hot { fillRounded(hit.rect.insetBy(dx: 1, dy: 0), radius: 4, p.txt2.withAlpha(0.08)) }
                _ = s
            case .item(let url, let isFolder, let label):
                if hit.rect.height == Self.tileH {
                    drawTile(url, label: label, in: hit.rect, hot: hot, p)
                } else {
                    drawRow(url, isFolder: isFolder, label: label, in: hit.rect, hot: hot, p)
                }
            }
        }
    }

    private func drawTile(_ url: URL, label: String, in r: NSRect, hot: Bool, _ p: Palette) {
        fillRounded(r, radius: 4, hot ? p.s3 : p.s1)
        strokeRounded(r, radius: 4, hot ? p.line3 : p.line)
        if hot { drawBrackets(r, color: p.accent.ns, length: 8) }
        ItemIcon.drawFolder(in: NSRect(x: r.minX + 14, y: r.midY - 11, width: 26, height: 22), palette: p, lit: hot)
        drawLine(label, font: Typeface.ui(13, weight: 600), color: hot ? p.accent : p.txt, x: r.minX + 52, midY: r.minY + 22,
                 maxWidth: r.width - 62)
        let parent = (url.path as NSString).deletingLastPathComponent.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        drawLine(parent, font: Typeface.mono(11), color: p.txt3, x: r.minX + 52, midY: r.minY + 41, maxWidth: r.width - 62)
    }

    private func drawRow(_ url: URL, isFolder: Bool, label: String, in r: NSRect, hot: Bool, _ p: Palette) {
        if hot {
            fillRounded(r, radius: 3, p.txt.withAlpha(0.08))
            drawBrackets(r, color: p.bracket.ns, length: 6)
        }
        let mid = r.midY
        if isFolder {
            ItemIcon.drawFolder(in: NSRect(x: r.minX + 10, y: mid - 7.5, width: 18, height: 15), palette: p, lit: false)
        } else {
            ItemIcon.drawFile(named: url.lastPathComponent, in: NSRect(x: r.minX + 11, y: mid - 7.5, width: 15, height: 15), palette: p)
        }
        let dateW: CGFloat = 130
        let nameW = drawLine(label, font: Typeface.ui(13), color: hot ? p.accent : p.txt, x: r.minX + 38, midY: mid,
                             maxWidth: (r.width - 38) * 0.45)
        let folder = (isFolder ? url.path : (url.path as NSString).deletingLastPathComponent)
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        drawLine(folder, font: Typeface.mono(12), color: p.txt3, x: r.minX + 38 + nameW + 14, midY: mid,
                 maxWidth: r.maxX - dateW - (r.minX + 38 + nameW + 14) - 8)
        if !isFolder, let date = (try? url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate {
            drawLine(Self.dateFormatter.string(from: date), font: Typeface.mono(12), color: p.txt2, x: r.maxX - 10, midY: mid, alignRight: true)
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
