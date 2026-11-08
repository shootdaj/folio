import AppKit
import FolioCore
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// QuickLookThumbnailing previews for images, video and PDFs, cached by path, date and size.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    private var pending: [String: [(NSImage?) -> Void]] = [:]

    init() { cache.countLimit = 2000 }

    /// Explorer thumbnails images, videos and PDFs; everything else keeps its type icon.
    static func wants(_ entry: FileEntry) -> Bool {
        guard !entry.isFolder, let type = UTType(filenameExtension: entry.url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .audiovisualContent) || type.conforms(to: .pdf)
    }

    private func key(_ entry: FileEntry, _ size: CGFloat) -> String {
        "\(entry.url.path)|\(entry.modified?.timeIntervalSince1970 ?? 0)|\(Int(size))"
    }

    func cached(_ entry: FileEntry, size: CGFloat) -> NSImage? { cache.object(forKey: key(entry, size) as NSString) }

    /// The thumbnail now if cached; otherwise nil and `done` gets it when Quick Look has made it.
    func image(for entry: FileEntry, size: CGFloat, done: @escaping (NSImage?) -> Void) -> NSImage? {
        let k = key(entry, size)
        if let hit = cache.object(forKey: k as NSString) { return hit }
        if pending[k] != nil {
            pending[k]?.append(done)
            return nil
        }
        pending[k] = [done]
        let request = QLThumbnailGenerator.Request(fileAt: entry.url, size: CGSize(width: size, height: size),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request, completion: Self.handler(for: k))
        return nil
    }

    /// Quick Look calls back on its own queue: the handler is made outside the main actor so Swift does
    /// not assert it runs there (it did, and the app trapped), then hops to the main thread itself.
    nonisolated private static func handler(for key: String) -> @Sendable (QLThumbnailRepresentation?, (any Error)?) -> Void {
        { rep, _ in
            let image = SendableImage(cg: rep?.cgImage)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { ThumbnailCache.shared.finish(key, image) }
            }
        }
    }

    private func finish(_ key: String, _ image: SendableImage) {
        let ns = image.cg.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / 2, height: CGFloat($0.height) / 2)) }
        if let ns { cache.setObject(ns, forKey: key as NSString) }
        let waiting = pending.removeValue(forKey: key) ?? []
        for w in waiting { w(ns) }
    }
}

private struct SendableImage: @unchecked Sendable { let cg: CGImage? }

/// One item of the icon grid: Small, Medium, Large and Extra large icons, List, Tiles, Content and the
/// Gallery strip, drawn the D4 way (hover wash, the --sel fill and an accent hairline when selected).
final class GridCellView: NSView, NSViewToolTipOwner {
    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        tip?() ?? ""
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if tip != nil { removeAllToolTips(); addToolTip(bounds, owner: self, userData: nil) }
    }

    var entry: FileEntry? { didSet { thumbnail = nil; needsDisplay = true; setAccessibilityLabel(entry?.name) } }
    var mode: ViewMode = .largeIcons { didSet { needsDisplay = true } }
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    var isFocusItem = false { didSet { if isFocusItem != oldValue { needsDisplay = true } } }
    var isDropTarget = false { didSet { if isDropTarget != oldValue { needsDisplay = true } } }
    var isCut = false { didSet { if isCut != oldValue { needsDisplay = true } } }
    var showsExtension = true
    var thumbnail: NSImage? { didSet { needsDisplay = true } }
    /// Display file icon on thumbnails: the type's small icon in the thumbnail's corner.
    var showsTypeBadge = true
    var tagColors: [TagColor] = [] { didSet { if tagColors != oldValue { needsDisplay = true } } }
    var isFlagDimmed = false
    /// Show pop-up description: built when the tip is about to show.
    var tip: (() -> String?)? { didSet { removeAllToolTips(); if tip != nil { addToolTip(bounds, owner: self, userData: nil) } } }
    /// Tiles and Content: Type, Size, Date modified and, when known, dimensions or duration.
    var details: [(key: String, value: String)] = [] { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// The icon's square in the cell, and where the name sits (for F2's box).
    var iconRect: NSRect {
        let s = CGFloat(mode.iconSize)
        switch mode {
        case .smallIcons, .list: return NSRect(x: 6, y: (bounds.height - s) / 2, width: s, height: s)
        case .tiles: return NSRect(x: 8, y: (bounds.height - s) / 2, width: s, height: s)
        case .content: return NSRect(x: 12, y: (bounds.height - s) / 2, width: s, height: s)
        default:
            let side = min(s, bounds.width - 16)
            return NSRect(x: (bounds.width - side) / 2, y: 8, width: side, height: side)
        }
    }

    var nameRect: NSRect {
        let icon = iconRect
        switch mode {
        case .smallIcons, .list: return NSRect(x: icon.maxX + 6, y: 0, width: bounds.width - icon.maxX - 10, height: bounds.height)
        case .tiles, .content: return NSRect(x: icon.maxX + 12, y: icon.minY - 2, width: bounds.width - icon.maxX - 20, height: 20)
        default:
            if isNative, let pill = namePillRect { return pill }
            return NSRect(x: 4, y: icon.maxY + 4, width: bounds.width - 8, height: 20)
        }
    }

    private var isNative: Bool { ThemeController.shared.look == .native }

    /// Native: the selected-name pill hugs the name, up to two lines. F2's box is the same rect.
    private var namePillRect: NSRect? {
        guard let entry else { return nil }
        let icon = iconRect
        let font = Typeface.ui(13)
        let maxW = bounds.width - 8
        let name = entry.displayName(extensions: showsExtension)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let text = NSAttributedString(string: name, attributes: [.font: font, .paragraphStyle: para])
        let line = ceil(font.ascender - font.descender + 2)
        let box = text.boundingRect(with: NSSize(width: maxW - 10, height: line * 2), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        let w = min(maxW, ceil(box.width) + 10)
        let h = min(line * 2, max(line, ceil(box.height))) + 4
        return NSRect(x: ((bounds.width - w) / 2).rounded(), y: icon.maxY + 6, width: w, height: h)
    }

    /// Native: the window is key and the grid has focus, so the selection draws in the accent.
    private var isActive: Bool {
        guard let window, window.isKeyWindow else { return false }
        return window.firstResponder is FileGridView
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyChanged), name: name, object: window)
        }
    }

    @objc private func keyChanged() { if isSelected { needsDisplay = true } }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func draw(_ dirtyRect: NSRect) {
        guard let entry else { return }
        let p = ThemeColors.current
        if isNative {
            drawNative(entry, p)
            return
        }
        let r = bounds.insetBy(dx: 2, dy: 2)
        if isSelected {
            fillRounded(r, radius: 8, p.selectionFill)
            strokeRounded(r, radius: 8, p.accent.withAlpha(0.55))
        } else if isHovered {
            fillRounded(r, radius: 8, p.text.withAlpha(0.05))
        }
        if isDropTarget {
            fillRounded(r, radius: 8, p.markFill)
            strokeRounded(r, radius: 8, p.accent)
        }
        if isFocusItem && !isSelected {
            let path = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.setLineDash([2, 2], count: 2, phase: 0)
            p.muted.ns.setStroke()
            path.stroke()
        }
        if mode == .content { fillRect(NSRect(x: 8, y: bounds.maxY - 1, width: bounds.width - 16, height: 1), p.line) }
        NSGraphicsContext.saveGraphicsState()
        if isCut || entry.isHidden || isFlagDimmed { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
        drawIcon(entry, p)
        drawText(entry, p)
        NSGraphicsContext.restoreGraphicsState()
    }

    private var isIconMode: Bool {
        switch mode {
        case .smallIcons, .list, .tiles, .content: return false
        default: return true
        }
    }

    /// Native: a plate behind the icon and an accent pill under the name in icon modes, a rounded
    /// inset fill in the row-like modes, a 2 pt accent outline for a drop and no hover wash.
    private func drawNative(_ entry: FileEntry, _ p: ThemeColors) {
        let fill = isActive ? p.selectionFill : p.selectionInactive
        let plate = iconRect.insetBy(dx: -4, dy: -4)
        let row = bounds.insetBy(dx: 4, dy: 1)
        if isSelected {
            if isIconMode {
                fillRounded(plate, radius: 6, fill)
                if let pill = namePillRect { fillRounded(pill, radius: 5, fill) }
            } else {
                fillRounded(row, radius: 5, fill)
            }
        }
        if isDropTarget { strokeRounded(isIconMode ? plate : row, radius: isIconMode ? 6 : 5, p.accent, width: 2) }
        if isFocusItem && !isSelected { strokeRounded(isIconMode ? plate : row, radius: isIconMode ? 6 : 5, p.accentSoft, width: 2) }
        if mode == .content { fillRect(NSRect(x: 8, y: bounds.maxY - 1, width: bounds.width - 16, height: 1), p.line) }
        NSGraphicsContext.saveGraphicsState()
        if isCut || entry.isHidden || isFlagDimmed { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
        drawIcon(entry, p)
        drawText(entry, p)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawIcon(_ entry: FileEntry, _ p: ThemeColors) {
        let icon = iconRect
        if let thumbnail {
            // Fit inside the square, centred on its bottom edge like Explorer's thumbnails.
            let size = thumbnail.size
            let scale = min(icon.width / max(1, size.width), icon.height / max(1, size.height))
            let w = size.width * scale, h = size.height * scale
            let frame = NSRect(x: icon.midX - w / 2, y: icon.maxY - h, width: w, height: h).integral
            thumbnail.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if isNative {
                strokeRounded(frame.insetBy(dx: -0.5, dy: -0.5), radius: 0, p.line, width: 0.5)
                if showsTypeBadge, frame.width >= 40 {
                    let b = max(14, min(24, frame.width * 0.22))
                    ItemIcon.draw(name: entry.name, isFolder: false,
                                  in: NSRect(x: frame.maxX - b - 2, y: frame.maxY - b - 2, width: b, height: b), palette: p)
                }
            } else {
                strokeRounded(frame.insetBy(dx: -0.5, dy: -0.5), radius: 1, p.line2)
                if showsTypeBadge, frame.width >= 40 {
                    let b = max(14, min(24, frame.width * 0.22))
                    let badge = NSRect(x: frame.maxX - b - 2, y: frame.maxY - b - 2, width: b, height: b)
                    fillRounded(badge.insetBy(dx: -2, dy: -2), radius: 3, p.s1.withAlpha(0.9))
                    ItemIcon.drawFile(named: entry.name, in: badge, palette: p)
                }
            }
        } else if entry.isFolder {
            let h = icon.width * 16 / 20
            ItemIcon.drawFolder(in: NSRect(x: icon.minX, y: icon.midY - h / 2, width: icon.width, height: h), palette: p, lit: isSelected && !isNative)
        } else {
            ItemIcon.drawFile(named: entry.name, in: icon, palette: p)
        }
        if entry.isLink {
            let b = max(9, icon.width * 0.32)
            ItemIcon.drawLinkBadge(in: NSRect(x: icon.minX, y: icon.maxY - b, width: b, height: b), palette: p)
        }
    }

    private func drawText(_ entry: FileEntry, _ p: ThemeColors) {
        let name = entry.displayName(extensions: showsExtension)
        let native = isNative
        // Native: white on the pill or row when the selection is active, no weight change.
        let onSelection = native && isSelected && isActive
        let tone = native ? (onSelection ? p.selectedText : p.text) : (isSelected ? p.accent : p.text)
        let font = Typeface.ui(13, weight: isSelected && !native ? 600 : 400)
        let detailColor = onSelection ? p.selectedText : p.text2
        let detailFont = native ? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular) : Typeface.ui(12)
        let nr = nameRect
        switch mode {
        case .smallIcons, .list:
            drawLine(name, font: font, color: tone, x: nr.minX, midY: nr.midY, maxWidth: nr.width)
        case .tiles, .content:
            drawLine(name, font: Typeface.ui(13, weight: native ? 400 : 600), color: tone, x: nr.minX, midY: nr.midY, maxWidth: nr.width)
            if mode == .tiles {
                for (i, d) in details.prefix(2).enumerated() {
                    drawLine(d.value, font: detailFont, color: detailColor, x: nr.minX, midY: nr.maxY + 8 + CGFloat(i) * 16, maxWidth: nr.width)
                }
            } else {
                // Content: Type under the name; Date modified and Size in the rightmost column, Explorer's
                // place for them; dimensions or duration in the column before it when there is room.
                let rest = Array(details.dropFirst())
                let main = rest.filter { $0.key == "Date modified" || $0.key == "Size" }
                let media = rest.filter { $0.key != "Date modified" && $0.key != "Size" }
                let colW: CGFloat = 240
                let right = bounds.width - 16
                let mediaFits = right - 2 * colW > nr.minX + min(220, nr.width * 0.4)
                if let kind = details.first {
                    // Too narrow for a column of their own: dimensions or duration follow the type.
                    let line = ([kind.value] + (mediaFits ? [] : media.map(\.value))).joined(separator: "  \u{00B7}  ")
                    drawLine(line, font: detailFont, color: detailColor, x: nr.minX, midY: nr.maxY + 9,
                             maxWidth: max(nr.width * 0.4, right - colW - nr.minX - 12))
                }
                for (col, list) in [(1, main), (0, media)] {
                    let x = right - CGFloat(2 - col) * colW
                    guard x > nr.minX + min(220, nr.width * 0.4) else { continue }
                    for (line, d) in list.prefix(2).enumerated() {
                        let y = bounds.midY - 9 + CGFloat(line) * 18
                        let kw = drawLine(d.key + ": ", font: Typeface.ui(12), color: native ? detailColor : p.muted, x: x, midY: y)
                        drawLine(d.value, font: native ? detailFont : Typeface.mono(12), color: detailColor, x: x + kw, midY: y, maxWidth: colW - kw - 12)
                    }
                }
            }
        default:
            // Under the icon, centred, two lines at most.
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byTruncatingMiddle
            let lines: CGFloat = mode == .mediumIcons ? 2 : 2
            var box = NSRect(x: nr.minX, y: nr.minY, width: nr.width, height: ceil(font.ascender - font.descender + 2) * lines)
            if native { box = nr.insetBy(dx: 5, dy: 2) }
            let text = NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: tone.ns, .paragraphStyle: para])
            text.draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
}

final class GridItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("gridItem")
    override func loadView() { view = GridCellView(frame: .zero) }
    var cell: GridCellView { view as! GridCellView }
}

/// A Group by header above a group in the grid.
final class GridGroupHeader: NSView, NSCollectionViewElement {
    static let id = NSUserInterfaceItemIdentifier("gridGroup")
    var group = 0
    var title = "" { didSet { needsDisplay = true; setAccessibilityLabel("\(title) (\(count))") } }
    var count = 0 { didSet { needsDisplay = true; setAccessibilityLabel("\(title) (\(count))") } }
    var collapsed = false { didSet { needsDisplay = true } }
    weak var grid: FileGridView?
    private var hovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard let grid else { return }
        grid.window?.makeFirstResponder(grid)
        let p = convert(event.locationInWindow, from: nil)
        grid.listDelegate?.list(grid, pressedGroup: group, onChevron: p.x < 32, clickCount: event.clickCount)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let grid else { return nil }
        return grid.listDelegate?.list(grid, menuForGroup: group)
    }

    override func draw(_ dirtyRect: NSRect) {
        GroupHeaderDrawing.draw(title: title, count: count, collapsed: collapsed, hovered: hovered, in: bounds, lead: 8, ThemeColors.current)
    }
}

/// What the grid reads from its window: the layout, the selection and how to fill a cell.
@MainActor
protocol GridHost: AnyObject {
    var gridLayout: ListLayout { get }
    /// Folder Options > Single-click to open an item.
    var singleClickOpens: Bool { get }
    func configure(_ cell: GridCellView, item: Int)
    func gridZoom(_ steps: Int)
    /// A drag over the grid: `item` is the item under it (nil for the background).
    func gridValidateDrop(_ info: NSDraggingInfo, item: Int?) -> NSDragOperation
    func gridAcceptDrop(_ info: NSDraggingInfo, item: Int?) -> Bool
}

/// Every view but Details: an NSCollectionView with a flow layout per view, sections for Group by
/// groups (a collapsed group has no items), Explorer's clicks and rubber band, and Cmd+scroll zoom.
final class FileGridView: NSCollectionView {
    weak var listDelegate: FileListDelegate?
    /// Data source and delegate. Never the collection view itself: NSCollectionView forwards
    /// willDisplayItem to its delegate, so being its own delegate loops forever.
    private let source = GridSource()
    weak var host: GridHost?
    private let flow = NSCollectionViewFlowLayout()
    private let band = BandOverlay()
    private(set) var hoveredItem: Int?
    private var hoverSelect: Timer?
    var mode: ViewMode = .largeIcons {
        didSet {
            guard mode != oldValue else { return }
            applyMode()
        }
    }
    var compact = false { didSet { if compact != oldValue { applyMode() } } }

    init() {
        super.init(frame: .zero)
        collectionViewLayout = flow
        source.grid = self
        dataSource = source
        delegate = source
        isSelectable = false
        backgroundColors = [.clear]
        register(GridItem.self, forItemWithIdentifier: GridItem.id)
        register(GridGroupHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: GridGroupHeader.id)
        setAccessibilityLabel("Files")
        applyMode()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    private var layoutModel: ListLayout { host?.gridLayout ?? ListLayout(items: []) }

    // MARK: Layout per view

    var isHorizontal: Bool { mode == .list || mode == .gallery }

    private func applyMode() {
        flow.scrollDirection = isHorizontal ? .horizontal : .vertical
        let gap: CGFloat = compact ? 2 : 6
        flow.minimumInteritemSpacing = mode == .list ? 0 : gap
        flow.minimumLineSpacing = mode == .list ? 12 : gap
        flow.sectionInset = NSEdgeInsets(top: 6, left: 8, bottom: 10, right: 8)
        flow.sectionHeadersPinToVisibleBounds = false
        flow.invalidateLayout()
        reloadData()
    }

    /// Room across the scroll direction; an item never asks for more (a flow layout given an item wider
    /// than its view lays out forever).
    private var room: NSSize {
        let clip = enclosingScrollView?.contentSize ?? bounds.size
        return NSSize(width: max(24, clip.width - 17), height: max(24, clip.height - 17))
    }

    var itemSize: NSSize {
        let want = wantedItemSize
        return isHorizontal ? NSSize(width: want.width, height: min(want.height, room.height))
            : NSSize(width: min(want.width, room.width), height: want.height)
    }

    private var wantedItemSize: NSSize {
        let s = CGFloat(mode.iconSize)
        let tight: CGFloat = compact ? 0.85 : 1
        switch mode {
        case .extraLargeIcons: return NSSize(width: s + 24, height: s + 16 + 40)
        case .largeIcons: return NSSize(width: (s + 36) * tight, height: s + 16 + 38)
        case .mediumIcons: return NSSize(width: (s + 44) * tight, height: s + 14 + 38)
        case .smallIcons: return NSSize(width: 220, height: compact ? 20 : 24)
        case .list: return NSSize(width: 240, height: compact ? 20 : 22)
        case .tiles: return NSSize(width: 270, height: compact ? 62 : 70)
        case .content:
            return NSSize(width: room.width, height: compact ? 54 : 62)
        case .gallery: return NSSize(width: 150, height: 160)
        case .details: return NSSize(width: 200, height: 24)
        }
    }

    /// In Details the grid is hidden and holds nothing.
    func sectionCount() -> Int {
        // Counts depend on the view and the layout only, never on geometry, or the collection view's cached
        // counts and its layout's disagree and it lays out forever.
        guard !mode.usesTable else { return 0 }
        return layoutModel.isGrouped ? layoutModel.groups.count : 1
    }

    func itemCount(inSection section: Int) -> Int {
        let l = layoutModel
        return l.isGrouped ? (l.groupRanges.indices.contains(section) ? l.groupRanges[section].count : 0) : l.items.count
    }

    func makeGridItem(at indexPath: IndexPath) -> NSCollectionViewItem {
        let item = makeItem(withIdentifier: GridItem.id, for: indexPath) as! GridItem
        let i = index(of: indexPath)
        item.cell.mode = mode
        host?.configure(item.cell, item: i)
        item.cell.isHovered = hoveredItem == i
        return item
    }

    func makeHeader(ofKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
        let header = makeSupplementaryView(ofKind: kind, withIdentifier: GridGroupHeader.id, for: indexPath) as! GridGroupHeader
        let l = layoutModel
        header.grid = self
        header.group = indexPath.section
        if l.groups.indices.contains(indexPath.section) {
            header.title = l.groups[indexPath.section].bucket.title
            header.count = l.groups[indexPath.section].items.count
            header.collapsed = l.isCollapsed(indexPath.section)
        }
        return header
    }

    func headerSize(inSection section: Int) -> NSSize {
        guard layoutModel.isGrouped else { return .zero }
        return isHorizontal ? NSSize(width: 170, height: min(32, room.height)) : NSSize(width: room.width, height: 34)
    }



    // MARK: Items and index paths

    func index(of path: IndexPath) -> Int {
        let l = layoutModel
        guard l.isGrouped, l.groupRanges.indices.contains(path.section) else { return path.item }
        return l.groupRanges[path.section].lowerBound + path.item
    }

    func indexPath(ofItem i: Int) -> IndexPath? {
        let l = layoutModel
        guard l.items.indices.contains(i) else { return nil }
        guard l.isGrouped, let g = l.group(ofItem: i) else { return IndexPath(item: i, section: 0) }
        return IndexPath(item: i - l.groupRanges[g].lowerBound, section: g)
    }

    func item(at point: NSPoint) -> Int? { indexPathForItem(at: point).map(index(of:)) }

    func cell(ofItem i: Int) -> GridCellView? {
        guard let path = indexPath(ofItem: i) else { return nil }
        return (self.item(at: path) as? GridItem)?.cell
    }

    func frame(ofItem i: Int) -> NSRect? {
        guard let path = indexPath(ofItem: i) else { return nil }
        return layoutAttributesForItem(at: path)?.frame
    }

    /// Calls `body` with each realised cell and its item.
    func forEachVisibleCell(_ body: (GridCellView, Int) -> Void) {
        for path in indexPathsForVisibleItems() {
            if let cell = (self.item(at: path) as? GridItem)?.cell { body(cell, index(of: path)) }
        }
    }

    func scrollToItem(_ i: Int) {
        guard let path = indexPath(ofItem: i) else { return }
        scrollToItems(at: [path], scrollPosition: isHorizontal ? .nearestVerticalEdge : .nearestHorizontalEdge)
    }

    /// How many items sit side by side (across the scroll direction), for the arrow keys.
    var itemsPerLine: Int {
        let size = itemSize
        if isHorizontal {
            let h = (enclosingScrollView?.contentView.bounds.height ?? bounds.height) - 16
            return max(1, Int((h + flow.minimumInteritemSpacing) / (size.height + flow.minimumInteritemSpacing)))
        }
        let w = bounds.width - 16
        return max(1, Int((w + flow.minimumInteritemSpacing) / (size.width + flow.minimumInteritemSpacing)))
    }

    private var laidOutWidth: CGFloat = 0

    override func layout() {
        // Content rows and group headers track the list's width; a new width lays the grid out again once.
        let w = room.width
        if abs(w - laidOutWidth) > 1 {
            laidOutWidth = w
            flow.invalidateLayout()
        }
        super.layout()
    }

    // MARK: Mouse (the same Explorer clicks as the Details table)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setHovered(item(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(nil)
    }

    private func setHovered(_ i: Int?) {
        guard i != hoveredItem else { return }
        let old = hoveredItem
        hoveredItem = i
        if let old { cell(ofItem: old)?.isHovered = false }
        if let i { cell(ofItem: i)?.isHovered = true }
        // Single-click mode's point to select: resting on an item a moment selects it.
        hoverSelect?.invalidate()
        hoverSelect = nil
        if singleClickOpens, let i, NSEvent.pressedMouseButtons == 0 {
            hoverSelect = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.hoveredItem == i, self.listDelegate?.listIsSelected(i) == false else { return }
                    self.listDelegate?.list(self, clicked: i, modifiers: NSEvent.modifierFlags.intersection([.command, .shift]))
                }
            }
        }
    }


    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let delegate = listDelegate else { return }
        if event.modifierFlags.contains(.control), let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let mods = event.modifierFlags.intersection([.command, .shift])
        guard let row = item(at: point) else {
            rubberBand(from: point, adding: mods.contains(.command))
            return
        }
        if singleClickOpens, event.clickCount >= 2 { return }
        if event.clickCount >= 2, mods.isEmpty {
            if event.modifierFlags.contains(.option) { delegate.list(self, showPropertiesOf: row) } else { delegate.list(self, opened: row) }
            return
        }
        if mods.isEmpty, delegate.listIsSelected(row), (host?.gridLayout.items.count ?? 0) > 0 {
            let several = (0..<(host?.gridLayout.items.count ?? 0)).lazy.filter { delegate.listIsSelected($0) }.prefix(2).count > 1
            if several {
                if !trackDrag(from: point, right: false) { delegate.list(self, clicked: row, modifiers: []) }
                return
            }
        }
        delegate.list(self, clicked: row, modifiers: mods)
        if delegate.listIsSelected(row) {
            let dragged = trackDrag(from: point, right: false)
            if !dragged, singleClickOpens, mods.isEmpty, !event.modifierFlags.contains(.option) { delegate.list(self, opened: row) }
        }
    }

    /// Folder Options > Single-click to open an item.
    var singleClickOpens: Bool {
        get { host?.singleClickOpens ?? false }
    }

    private func trackDrag(from start: NSPoint, right: Bool) -> Bool {
        let types: NSEvent.EventTypeMask = right ? [.rightMouseUp, .rightMouseDragged] : [.leftMouseUp, .leftMouseDragged]
        while let window, let next = MouseTracking.next(window, types, idle: nil, button: right ? 1 : 0) {
            if next.type == .leftMouseUp || next.type == .rightMouseUp { return false }
            let p = convert(next.locationInWindow, from: nil)
            if hypot(p.x - start.x, p.y - start.y) > 4 {
                listDelegate?.list(self, beginDragWith: next, rightButton: right)
                return true
            }
        }
        return false
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let row = item(at: point), let delegate = listDelegate else { return super.rightMouseDown(with: event) }
        if !delegate.listIsSelected(row) { delegate.list(self, clicked: row, modifiers: []) }
        if trackDrag(from: point, right: true) { return }
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = item(at: convert(event.locationInWindow, from: nil)) ?? -1
        return listDelegate?.list(self, menuFor: row, event: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, let row = item(at: convert(event.locationInWindow, from: nil)) else {
            return super.otherMouseDown(with: event)
        }
        listDelegate?.list(self, middleClicked: row)
    }

    override func keyDown(with event: NSEvent) {
        // The window controller handles the keys it knows (BrowserWindow.sendEvent); letters are type-select.
        if let text = event.characters, !text.isEmpty, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let host = host as? BrowserWindowController {
            host.typeSelect(text, at: event.timestamp)
            return
        }
        super.keyDown(with: event)
    }

    private func rubberBand(from start: NSPoint, adding: Bool) {
        let base = adding ? IndexSet((0..<(host?.gridLayout.items.count ?? 0)).filter { listDelegate?.listIsSelected($0) == true }) : IndexSet()
        if !adding { listDelegate?.list(self, banded: IndexSet(), focus: nil) }
        if band.superview == nil { addSubview(band) }
        while let window, let next = MouseTracking.next(window, [.leftMouseDragged, .leftMouseUp], idle: nil) {
            if next.type == .leftMouseUp { break }
            autoscroll(with: next)
            let p = convert(next.locationInWindow, from: nil)
            let r = RubberBand.rect(from: (Double(start.x), Double(start.y)), to: (Double(p.x), Double(p.y)))
            let rect = NSRect(x: r.x, y: r.y, width: r.width, height: r.height)
            band.frame = rect
            band.isHidden = false
            let hits = (flow.layoutAttributesForElements(in: rect))
                .filter { $0.representedElementCategory == .item && $0.frame.intersects(rect) }
                .compactMap { $0.indexPath.map(index(of:)) }
            let hit = IndexSet(hits)
            listDelegate?.list(self, banded: RubberBand.selection(base: base, hit: hit, adding: adding), focus: hit.last)
        }
        band.isHidden = true
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        listDelegate?.listDragExited(self)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        super.draggingEnded(sender)
        listDelegate?.listDragExited(self)
    }

    // MARK: Cmd+scroll and pinch step through the views (BrowserWindow sends them here too)

    private var zoomAccumulator: CGFloat = 0

    func zoom(with event: NSEvent) {
        var dy = event.scrollingDeltaY
        if event.isDirectionInvertedFromDevice { dy = -dy }
        if !event.hasPreciseScrollingDeltas {
            if dy != 0 { host?.gridZoom(dy > 0 ? 1 : -1) }
            return
        }
        zoomAccumulator += dy
        if abs(zoomAccumulator) >= 40 {
            host?.gridZoom(zoomAccumulator > 0 ? 1 : -1)
            zoomAccumulator = 0
        }
        if event.phase == .ended || event.momentumPhase == .ended { zoomAccumulator = 0 }
    }

    private final class BandOverlay: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            let p = ThemeColors.current
            fillRect(bounds, p.selectionFill)
            p.accent.withAlpha(0.8).ns.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
    }
}

/// The grid's data source and delegate, asking the grid for everything.
final class GridSource: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    weak var grid: FileGridView?

    func numberOfSections(in collectionView: NSCollectionView) -> Int { grid?.sectionCount() ?? 0 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        grid?.itemCount(inSection: section) ?? 0
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        grid!.makeGridItem(at: indexPath)
    }

    // These four must exist: without them NSCollectionView (macOS 15) spins forever in its own
    // willDisplayItem shim the first time it shows an item (seen in the VM with `sample`).
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
                        forRepresentedObjectAt indexPath: IndexPath) {}

    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
                        forRepresentedObjectAt indexPath: IndexPath) {}

    func collectionView(_ collectionView: NSCollectionView, willDisplaySupplementaryView view: NSView,
                        forElementKind elementKind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) {}

    func collectionView(_ collectionView: NSCollectionView, didEndDisplayingSupplementaryView view: NSView,
                        forElementOfKind elementKind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) {}

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        grid!.makeHeader(ofKind: kind, at: indexPath)
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> NSSize { grid?.headerSize(inSection: section) ?? .zero }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> NSSize { grid?.itemSize ?? NSSize(width: 100, height: 100) }

    // MARK: Drops (on a folder item, or the background for the folder on screen)

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        dropOperation.pointee = .on
        return grid?.host?.gridValidateDrop(draggingInfo, item: grid?.item(at: collectionView.convert(draggingInfo.draggingLocation, from: nil))) ?? []
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath,
                        dropOperation: NSCollectionView.DropOperation) -> Bool {
        grid?.host?.gridAcceptDrop(draggingInfo, item: grid?.item(at: collectionView.convert(draggingInfo.draggingLocation, from: nil))) ?? false
    }

}
