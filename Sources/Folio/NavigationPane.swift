import AppKit
import FolioCore

/// The sidebar (`.side`) on a blueprint grid tinted with the accent. It holds one outline: Quick access
/// (Home and the pins), This PC (every volume with its bar, each the root of a folder tree) and Network
/// (mounted shares, servers found on the network, Connect to server). The grid stays put while the
/// groups scroll, as in D1.
final class SidebarView: NSView {
    let outline = SidebarOutlineView(frame: .zero)
    let pane = NavigationPane()
    private let scroll = NSScrollView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = outline
        addSubview(scroll)
        pane.attach(outline)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Navigation")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        scroll.frame = NSRect(x: 0, y: 0, width: bounds.width - 1, height: bounds.height)
        outline.sizeLastColumnToFit()
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        fillRect(bounds, p.bg)
        // 16 pt minor and 64 pt major lines, offset by -1 like `background-position:-1px -1px`.
        for (step, color) in [(CGFloat(16), p.gridMinor), (CGFloat(64), p.gridMajor)] {
            var x = step - 1
            while x < bounds.width { fillRect(NSRect(x: x, y: 0, width: 1, height: bounds.height), color); x += step }
            var y = step - 1
            while y < bounds.height { fillRect(NSRect(x: 0, y: y, width: bounds.width, height: 1), color); y += step }
        }
        fillRect(NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height), p.line)
    }

    /// F6 and Tab: the outline takes the keys, on the row of the current folder.
    func takeKeyboardFocus() {
        pane.selectCurrentRow()
        window?.makeFirstResponder(outline)
    }
}

/// A change to the Quick access pins made in the sidebar.
enum PinEdit {
    case pin(String, at: Int)
    case move(from: Int, to: Int)
    case unpin(String)
}

/// Folder Options' navigation pane settings.
struct NavigationLayout: Equatable {
    var showAllFolders = false
    var showNetwork = true
    var showThisPC = true
    var hideEmptyDrives = true
    var showDriveLetters = false
}

/// One row of the navigation pane. Objects stay the same across reloads so the outline keeps what is
/// expanded.
final class SideNode: NSObject, @unchecked Sendable {
    /// `allFolders` replaces This PC and Network with Folder Options > Show all folders on.
    enum Section: String, CaseIterable { case quickAccess, thisPC, network, allFolders }

    enum Kind {
        case header(Section), footer(Section)
        case home
        case pin(QuickAccessPlace, index: Int)
        case cloud(CloudPlace)
        case recycle
        case volume(VolumeCapacity)
        case folder(TreeFolder)
        case share(VolumeCapacity)
        case browse, server(String), connect, notice(String)
        /// An iPhone or camera seen through Image Capture (a Mac has no MTP).
        case device(String)
    }

    var kind: Kind
    init(_ kind: Kind) { self.kind = kind }

    /// The folder this row opens, if it is one.
    var path: String? {
        switch kind {
        case .pin(let place, _): place.path
        case .cloud(let c): c.path
        case .recycle: RecycleBin.trashFolder(home: FileManager.default.homeDirectoryForCurrentUser).path
        case .volume(let v), .share(let v): v.path
        case .folder(let f): f.path
        default: nil
        }
    }

    var url: URL? { path.map { URL(fileURLWithPath: $0, isDirectory: true) } }

    var title: String {
        switch kind {
        case .header(.quickAccess): "Quick access"
        case .header(.thisPC): "This PC"
        case .header(.network): "Network"
        case .header(.allFolders): "All folders"
        case .footer: ""
        case .home: "Home"
        case .pin(let place, _): place.title
        case .cloud(let c): c.name
        case .recycle: "Recycle Bin"
        case .volume(let v), .share(let v): v.name
        case .folder(let f): f.name
        case .browse: "Browse network"
        case .server(let name): name
        case .device(let name): name
        case .connect: "Connect to server..."
        case .notice(let text): text
        }
    }

    var isFooter: Bool { if case .footer = kind { true } else { false } }
    var isHeader: Bool { if case .header = kind { true } else { false } }
}

/// The outline's data, drawing state, clicks, keys, menus and drops, for one window.
@MainActor
final class NavigationPane: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onNavigate: ((URL) -> Void)?
    var onHome: (() -> Void)?
    var onOpenInNewTab: ((URL) -> Void)?
    var onPinsEdited: ((PinEdit) -> Void)?
    var onEject: ((VolumeCapacity) -> Void)?
    var onConnect: (() -> Void)?
    var onBrowse: (() -> Void)?
    var onServer: ((String) -> Void)?
    var onRenameVolume: ((VolumeCapacity) -> Void)?
    /// A phone or camera: Image Capture imports from it.
    var onDevice: (() -> Void)?
    private var deviceNodes: [SideNode] = []
    /// Files dropped on the Recycle Bin row.
    var onTrash: (([URL]) -> Void)?
    /// Right-click a row: the window builds the menu.
    var menuProvider: ((SideNode) -> NSMenu?)?
    weak var dropHost: DropHost?
    static let pinType = NSPasteboard.PasteboardType("com.anshul.folio.pin")

    let tree = FolderTree()
    private(set) weak var outline: SidebarOutlineView?

    private var headers: [SideNode.Section: SideNode] = [:]
    private var footers: [SideNode.Section: SideNode] = [:]
    private let homeNode = SideNode(.home)
    private let recycleNode = SideNode(.recycle)
    private var cloudNodes: [SideNode] = []
    private let browseNode = SideNode(.browse)
    private let connectNode = SideNode(.connect)
    private var pinNodes: [SideNode] = []
    private var volumeNodes: [SideNode] = []
    private var shareNodes: [SideNode] = []
    private var serverNodes: [SideNode] = []
    private var noticeNode: SideNode?
    private var dirNodes: [String: SideNode] = [:]
    private var collapsed: Set<String>
    /// A tree folder opened or closed (the window's session keeps which).
    var onTreeChanged: (() -> Void)?
    /// Folder Options' navigation pane settings, and the volumes as last given (for Hide empty drives).
    private(set) var layoutOptions = NavigationLayout()
    private var allVolumes: [VolumeCapacity] = []
    /// Show all folders: the home folder as a tree of its own, under All folders.
    private lazy var homeFolderNode: SideNode = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return SideNode(.cloud(CloudPlace(name: FileManager.default.displayName(atPath: home.path), path: home.path)))
    }()

    /// The sections shown, top to bottom.
    var sections: [SideNode.Section] {
        var out: [SideNode.Section] = [.quickAccess]
        if layoutOptions.showAllFolders { return out + [.allFolders] }
        if layoutOptions.showThisPC { out.append(.thisPC) }
        if layoutOptions.showNetwork { out.append(.network) }
        return out
    }

    /// The folder the window shows (a resolved path), or Home's.
    var currentPath = "" { didSet { if currentPath != oldValue { outline?.redrawRows() } } }
    var isHome = false { didSet { if isHome != oldValue { outline?.redrawRows() } } }
    var browseStatus = "Browse network" { didSet { if browseStatus != oldValue { reload(.network) } } }

    override init() {
        collapsed = SidebarStore(defaults: .standard).collapsed
        super.init()
        for s in SideNode.Section.allCases {
            headers[s] = SideNode(.header(s))
            footers[s] = SideNode(.footer(s))
        }
    }

    func attach(_ outline: SidebarOutlineView) {
        self.outline = outline
        outline.pane = self
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(rowClicked(_:))
        outline.reloadData()
        expandOpenSections()
    }

    private func expandOpenSections() {
        for s in SideNode.Section.allCases where !collapsed.contains(s.rawValue) { outline?.expandItem(headers[s]) }
    }

    // MARK: Content

    func setPlaces(_ places: [QuickAccessPlace]) {
        pinNodes = places.enumerated().map { i, place in SideNode(.pin(place, index: i)) }
        reload(.quickAccess)
    }

    /// iCloud Drive, Dropbox, Google Drive, OneDrive: below the pins, each the root of a tree.
    func setCloud(_ places: [CloudPlace]) {
        cloudNodes = places.map { place in
            if let node = cloudNodes.first(where: { $0.path == place.path }) { node.kind = .cloud(place); return node }
            return SideNode(.cloud(place))
        }
        reload(.quickAccess)
    }

    /// The number a header shows: pins, drives, shares.
    func headerCount(_ s: SideNode.Section) -> Int {
        switch s {
        case .quickAccess: pinNodes.count
        case .thisPC, .allFolders: volumeNodes.count
        case .network: shareNodes.count
        }
    }

    /// Folder Options changed: sections come and go, drives are filtered and labelled again.
    func setLayout(_ layout: NavigationLayout) {
        guard layout != layoutOptions else { return }
        let sectionsChanged = layout.showAllFolders != layoutOptions.showAllFolders || layout.showNetwork != layoutOptions.showNetwork
            || layout.showThisPC != layoutOptions.showThisPC
        layoutOptions = layout
        setVolumes(allVolumes)
        if sectionsChanged {
            outline?.reloadData()
            expandOpenSections()
        }
        outline?.redrawRows()
    }

    /// Phones and cameras connected now (ImageCaptureCore's device browser).
    func setDevices(_ names: [String]) {
        deviceNodes = names.map { name in deviceNodes.first { $0.title == name } ?? SideNode(.device(name)) }
        reload(.thisPC)
    }

    /// A drive's name, with its mount path when Show drive letters is on.
    func label(_ v: VolumeCapacity) -> String { VolumeList.label(v, showPath: layoutOptions.showDriveLetters) }

    func setVolumes(_ volumes: [VolumeCapacity]) {
        allVolumes = volumes
        let (drives, network) = VolumeList.arrange(volumes, hideEmpty: layoutOptions.hideEmptyDrives)
        func reuse(_ old: [SideNode], _ list: [VolumeCapacity], share: Bool) -> [SideNode] {
            list.map { v in
                if let node = old.first(where: { $0.path == v.path }) {
                    node.kind = share ? .share(v) : .volume(v)
                    return node
                }
                return SideNode(share ? .share(v) : .volume(v))
            }
        }
        volumeNodes = reuse(volumeNodes, drives, share: false)
        shareNodes = reuse(shareNodes, network, share: true)
        reload(.thisPC)
        reload(.network)
        reload(.allFolders)
    }

    func setServers(_ names: [String], notice: String?) {
        serverNodes = names.map { name in serverNodes.first { $0.title == name } ?? SideNode(.server(name)) }
        noticeNode = notice.map { SideNode(.notice($0)) }
        reload(.network)
    }

    private func reload(_ section: SideNode.Section) {
        guard let outline, let header = headers[section] else { return }
        outline.reloadItem(header, reloadChildren: true)
        if let footer = footers[section] { outline.reloadItem(footer) }
        if !collapsed.contains(section.rawValue) { outline.expandItem(header) }
        outline.redrawRows()
    }

    private func children(of section: SideNode.Section) -> [SideNode] {
        let network = shareNodes + serverNodes + (noticeNode.map { [$0] } ?? []) + [browseNode, connectNode]
        switch section {
        case .quickAccess: return [homeNode] + pinNodes + cloudNodes + (layoutOptions.showAllFolders ? [] : [recycleNode])
        case .thisPC: return volumeNodes + deviceNodes
        case .network: return network
        // The top of the Mac: Home, the drives, Network and the Recycle Bin, as Explorer's Desktop root.
        case .allFolders: return [homeFolderNode] + volumeNodes + (layoutOptions.showNetwork ? network : []) + [recycleNode]
        }
    }

    private func dirNode(_ folder: TreeFolder) -> SideNode {
        if let node = dirNodes[folder.path] {
            node.kind = .folder(folder)
            return node
        }
        let node = SideNode(.folder(folder))
        dirNodes[folder.path] = node
        return node
    }

    /// The folders under a tree node. Other drives are their own roots, so /Volumes is left out of /.
    private func treeChildren(_ path: String) -> [TreeFolder] {
        let kids = tree.children(of: path)
        return path == "/" ? kids.filter { $0.path != "/Volumes" } : kids
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? SideNode else { return sections.count * 2 }
        switch node.kind {
        case .header(let s): return children(of: s).count
        case .volume, .share, .folder, .cloud: return node.path.map { treeChildren($0).count } ?? 0
        default: return 0
        }
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? SideNode else {
            let s = sections[index / 2]
            return (index % 2 == 0 ? headers[s] : footers[s]) as Any
        }
        switch node.kind {
        case .header(let s): return children(of: s)[index]
        default:
            let kids = node.path.map(treeChildren) ?? []
            return kids.indices.contains(index) ? dirNode(kids[index]) : SideNode(.notice(""))
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? SideNode else { return false }
        switch node.kind {
        case .header: return true
        case .volume, .share, .cloud: return true
        case .folder(let f):
            if let kids = tree.cachedChildren(of: f.path) { return !kids.isEmpty }
            return true
        default: return false
        }
    }

    // MARK: Delegate

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let node = item as? SideNode else { return 30 }
        switch node.kind {
        case .header: return 12 + 1 + 36
        case .footer(let s):
            let open = !collapsed.contains(s.rawValue)
            return (open ? 6 : 0) + 1 + (s == sections.last ? 12 : 0)
        case .volume, .share: return 77.75
        case .folder: return 26
        default: return 30
        }
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let row = SideRowView()
        row.node = item as? SideNode
        row.pane = self
        return row
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SideNode else { return nil }
        let cell = SideCellView()
        cell.configure(node, pane: self)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? SideNode else { return false }
        if node.isFooter { return false }
        if case .notice = node.kind { return false }
        return true
    }

    func outlineViewItemDidExpand(_ notification: Notification) { noteHeader(notification, open: true) }
    func outlineViewItemDidCollapse(_ notification: Notification) { noteHeader(notification, open: false) }

    /// A section opened or closed: its footer changes height and the choice is kept.
    private func noteHeader(_ notification: Notification, open: Bool) {
        guard let node = notification.userInfo?["NSObject"] as? SideNode, case .header(let s) = node.kind,
              let outline, let footer = footers[s] else {
            outline?.redrawRows()
            onTreeChanged?()
            return
        }
        if open { collapsed.remove(s.rawValue) } else { collapsed.insert(s.rawValue) }
        SidebarStore(defaults: .standard).setCollapsed(collapsed)
        let row = outline.row(forItem: footer)
        if row >= 0 { outline.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row)) }
        outline.redrawRows()
    }

    func isCollapsed(_ s: SideNode.Section) -> Bool { collapsed.contains(s.rawValue) }

    // MARK: Drawing state

    /// Whether a row is the place the window shows (drawn lit, as D1's `.si.on`).
    func isCurrent(_ node: SideNode) -> Bool {
        if case .home = node.kind { return isHome }
        guard !isHome, let path = node.path else { return false }
        return FilePaths.folderKey(URL(fileURLWithPath: path)) == currentPath
    }

    /// The tree depth of a folder row (its volume's children are depth 0).
    func depth(of node: SideNode) -> Int {
        guard let outline else { return 0 }
        return max(0, outline.level(forItem: node) - 2)
    }

    /// The section rectangles (header to footer), drawn behind the rows.
    func panelRects() -> [NSRect] {
        guard let outline else { return [] }
        let w = outline.bounds.width
        return SideNode.Section.allCases.compactMap { s in
            guard let h = headers[s], let f = footers[s] else { return nil }
            let hr = outline.row(forItem: h), fr = outline.row(forItem: f)
            guard hr >= 0, fr >= 0 else { return nil }
            let top = outline.rect(ofRow: hr).minY + 12
            let bottom = outline.rect(ofRow: fr).maxY - (s == sections.last ? 12 : 0)
            return NSRect(x: 10, y: top, width: w - 20, height: bottom - top)
        }
    }

    // MARK: Clicks

    @objc func rowClicked(_ sender: Any?) {
        guard let outline else { return }
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? SideNode else { return }
        activate(node)
    }

    func activate(_ node: SideNode) {
        switch node.kind {
        case .header:
            guard let outline else { return }
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        case .home: onHome?()
        case .pin, .volume, .share, .folder, .cloud, .recycle: if let url = node.url { onNavigate?(url) }
        case .connect: onConnect?()
        case .browse: onBrowse?()
        case .server(let name): onServer?(name)
        case .device: onDevice?()
        case .footer, .notice: break
        }
    }

    func middleClicked(_ node: SideNode) {
        if let url = node.url { onOpenInNewTab?(url) }
    }

    func menu(for node: SideNode) -> NSMenu? { menuProvider?(node) }

    func toggle(_ node: SideNode, all: Bool) {
        guard let outline, outlineView(outline, isItemExpandable: node) else { return }
        if outline.isItemExpanded(node) {
            outline.collapseItem(node, collapseChildren: all)
        } else if all {
            expandAll(node)
        } else {
            outline.expandItem(node)
        }
    }

    /// Numpad * and Option-click: everything below the node (at most 400 folders).
    func expandAll(_ node: SideNode) {
        guard let outline else { return }
        guard let path = node.path else { outline.expandItem(node, expandChildren: false); return }
        outline.expandItem(node)
        for p in tree.descendants(of: path, limit: 400).dropFirst() {
            if let n = dirNodes[p] { outline.expandItem(n) }
        }
    }

    // MARK: The tree's open folders (saved with the window)

    /// Every open drive, share, cloud folder and tree folder, top to bottom (at most 300).
    func expandedFolders() -> [String] {
        guard let outline else { return [] }
        var out: [String] = []
        for row in 0..<outline.numberOfRows where out.count < 300 {
            guard let node = outline.item(atRow: row) as? SideNode, outline.isItemExpanded(node) else { continue }
            switch node.kind {
            case .volume, .share, .cloud, .folder: if let p = node.path, !out.contains(p) { out.append(p) }
            default: break
            }
        }
        return out
    }

    /// Opens these folders again, parents first; folders that are gone are skipped.
    func expandFolders(_ paths: [String]) {
        guard let outline else { return }
        let roots = volumeNodes + shareNodes + cloudNodes
        let fm = FileManager.default
        for path in paths.sorted(by: { $0.split(separator: "/").count < $1.split(separator: "/").count }) {
            if let root = roots.first(where: { $0.path == path }) {
                outline.expandItem(root)
                continue
            }
            guard fm.fileExists(atPath: path) else { continue }
            reveal(path)
            if let node = dirNodes[path] { outline.expandItem(node) }
        }
        outline.scrollRowToVisible(0)
        outline.redrawRows()
    }

    // MARK: Expand to current folder

    /// Opens the tree down to `path` (a resolved folder path), revealing hidden folders on the way, and
    /// scrolls its row into view. With `select`, the row also takes the keyboard selection.
    func reveal(_ path: String, select: Bool = false) {
        guard let outline else { return }
        let rootNodes = volumeNodes + shareNodes + cloudNodes
        let roots = rootNodes.compactMap(\.path)
        let root = FolderTree.root(for: path, roots: roots)
        guard let rootNode = rootNodes.first(where: { $0.path == root }),
              let chain = FolderTree.chain(from: root, to: path) else { return }
        for changed in tree.reveal(chain) {
            if changed == root { outline.reloadItem(rootNode, reloadChildren: true) }
            else if let node = dirNodes[changed] { outline.reloadItem(node, reloadChildren: true) }
        }
        let section: SideNode.Section = rootNode.isCloud ? .quickAccess : layoutOptions.showAllFolders ? .allFolders
            : rootNode.isShare ? .network : .thisPC
        if let header = headers[section], !outline.isItemExpanded(header) { outline.expandItem(header) }
        outline.expandItem(rootNode)
        var last: SideNode = rootNode
        for p in chain.dropFirst() {
            _ = outline.numberOfChildren(ofItem: last)
            guard let node = dirNodes[p] else { break }
            if p != chain.last { outline.expandItem(node) }
            last = node
        }
        let row = outline.row(forItem: last)
        guard row >= 0 else { return }
        outline.scrollRowToVisible(row)
        if select { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        outline.redrawRows()
    }

    /// F6: the selection goes to the current row (Home, a pin, a tree folder) or stays where it was.
    func selectCurrentRow() {
        guard let outline else { return }
        for row in 0..<outline.numberOfRows {
            if let node = outline.item(atRow: row) as? SideNode, isCurrent(node) {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outline.scrollRowToVisible(row)
                return
            }
        }
        if outline.selectedRow < 0, outline.numberOfRows > 1 {
            outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        }
    }

    /// Folders changed on disk: their tree nodes read again (those already read).
    func refresh(folders: Set<String>) {
        guard let outline else { return }
        for path in folders where tree.isLoaded(path) {
            tree.invalidate(path)
            if let node = dirNodes[path] {
                outline.reloadItem(node, reloadChildren: true)
            } else if let node = (volumeNodes + shareNodes + cloudNodes).first(where: { $0.path == path }) {
                outline.reloadItem(node, reloadChildren: true)
            }
        }
    }

    /// View > Hidden items: every node is read again.
    func setShowHidden(_ on: Bool) {
        guard tree.showHidden != on else { return }
        tree.showHidden = on
        for node in volumeNodes + shareNodes + cloudNodes { outline?.reloadItem(node, reloadChildren: true) }
    }

    // MARK: Dragging rows out

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? SideNode else { return nil }
        switch node.kind {
        case .pin(let place, let index):
            let item = NSPasteboardItem()
            item.setString(String(index), forType: Self.pinType)
            item.setString(place.path, forType: .string)
            return item
        case .folder(let f):
            return FileDragProvider(url: URL(fileURLWithPath: f.path, isDirectory: true))
        default:
            return nil
        }
    }

    // MARK: Dropping

    private var expandTimer: Timer?
    private var expandTarget: SideNode?

    func clearDrop() {
        outline?.dropRow = nil
        outline?.insertY = nil
        expandTimer?.invalidate()
        expandTimer = nil
        expandTarget = nil
        dropHost?.springLoad(nil)
        dropHost?.hideDropTip()
    }

    private func draggedFolders(_ info: NSDraggingInfo) -> [URL] {
        let urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        return urls.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue && !DropRules.isApp(url)
        }
    }

    /// The place between Quick access pins a point is close to (0...pins), with the line's y.
    private func pinInsertion(at point: NSPoint) -> (Int, CGFloat)? {
        guard let outline, !isCollapsed(.quickAccess), let panel = panelRects().first,
              panel.insetBy(dx: 0, dy: -2).contains(point) else { return nil }
        let homeRow = outline.row(forItem: homeNode)
        guard homeRow >= 0 else { return nil }
        let top = outline.rect(ofRow: homeRow).maxY
        if point.y < top { return (0, top) }
        let offset = point.y - top
        let k = Int((offset / 30).rounded())
        if k >= pinNodes.count { return point.y > top + CGFloat(pinNodes.count) * 30 - 6 ? (pinNodes.count, top + CGFloat(pinNodes.count) * 30) : nil }
        return abs(offset - CGFloat(k) * 30) <= 6 ? (k, top + CGFloat(k) * 30) : nil
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        guard let outline else { return [] }
        let point = outline.convert(info.draggingLocation, from: nil)
        let pinDrag = info.draggingPasteboard.types?.contains(Self.pinType) == true
        let folders = pinDrag ? [] : draggedFolders(info)
        if let (k, y) = pinInsertion(at: point), pinDrag || !folders.isEmpty {
            outline.dropRow = nil
            outline.insertY = y
            dropHost?.springLoad(nil)
            dropHost?.showTip("Pin to Quick access", accentFrom: 7, info: info)
            outline.setDropItem(headers[.quickAccess], dropChildIndex: k + 1)
            return pinDrag ? .move : .link
        }
        outline.insertY = nil
        let row = outline.row(at: point)
        guard !pinDrag, row >= 0, let node = outline.item(atRow: row) as? SideNode, let target = node.url,
              let host = dropHost else {
            clearDrop()
            return []
        }
        if case .recycle = node.kind {
            let urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            guard !urls.isEmpty else { clearDrop(); return [] }
            outline.dropRow = row
            host.springLoad(nil)
            host.showTip("Move to Recycle Bin", accentFrom: 8, info: info)
            outline.setDropItem(node, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return info.draggingSourceOperationMask.contains(.move) ? .move : .generic
        }
        let action = host.dropAction(info, onto: target)
        outline.dropRow = action == .none ? nil : row
        if case .pin = node.kind {
            host.springLoad(target)
        } else {
            host.springLoad(nil)
            hoverExpand(node)
        }
        host.showDropTip(action, target: target, info: info)
        outline.setDropItem(node, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return host.dragOperation(for: action, info)
    }

    /// Hovering a drag over a closed node opens it, so the drop can go deeper.
    private func hoverExpand(_ node: SideNode) {
        guard node !== expandTarget else { return }
        expandTimer?.invalidate()
        expandTarget = node
        guard let outline, !outline.isItemExpanded(node), outlineView(outline, isItemExpandable: node) else { return }
        let timer = Timer(timeInterval: 0.8, repeats: false) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, self.expandTarget === node else { return }
                self.outline?.expandItem(node)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        expandTimer = timer
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let outline else { return false }
        let insert = outline.insertY != nil
        let row = outline.dropRow
        defer { clearDrop() }
        if insert {
            DragState.droppedInFolio = true
            let at = max(0, index - 1)
            if let raw = info.draggingPasteboard.string(forType: Self.pinType), let from = Int(raw) {
                onPinsEdited?(.move(from: from, to: at))
            } else {
                for (n, folder) in draggedFolders(info).enumerated() { onPinsEdited?(.pin(folder.path, at: at + n)) }
            }
            return true
        }
        guard let row, let node = outline.item(atRow: row) as? SideNode, let target = node.url else { return false }
        if case .recycle = node.kind {
            let urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            DragState.droppedInFolio = true
            onTrash?(urls)
            return !urls.isEmpty
        }
        return dropHost?.performDrop(info, onto: target) ?? false
    }
}

extension SideNode {
    var isShare: Bool { if case .share = kind { true } else { false } }
    var isCloud: Bool { if case .cloud = kind { true } else { false } }
    var volume: VolumeCapacity? {
        switch kind {
        case .volume(let v), .share(let v): v
        default: nil
        }
    }
}

/// The outline: no header, no native disclosure triangles (the rows draw D1 chevrons), panels behind
/// the groups, an insertion line for pins, and the tree keys.
final class SidebarOutlineView: NSOutlineView {
    weak var pane: NavigationPane?
    private(set) var hoveredRow = -1
    var dropRow: Int? { didSet { if dropRow != oldValue { redrawRows() } } }
    var insertY: CGFloat? { didSet { if insertY != oldValue { overlay.y = insertY; overlay.needsDisplay = true } } }
    private let overlay = InsertionOverlay()
    private var navigateTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        addTableColumn(column)
        outlineTableColumn = column
        headerView = nil
        columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        indentationPerLevel = 0
        intercellSpacing = .zero
        backgroundColor = .clear
        focusRingType = .none
        style = .plain
        selectionHighlightStyle = .regular
        autoresizesOutlineColumn = false
        floatsGroupRows = false
        allowsEmptySelection = true
        allowsMultipleSelection = false
        registerForDraggedTypes(droppableTypes + [NavigationPane.pinType])
        setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: true)
        setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: false)
        draggingDestinationFeedbackStyle = .none
        setAccessibilityLabel("Quick access, This PC and Network")
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }

    /// A click in a window that is not in front acts at once (the Eject button, a row) instead of
    /// AppKit holding the press back to see whether it becomes a drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool { false }

    override func layout() {
        super.layout()
        overlay.frame = bounds
    }

    func redrawRows() {
        needsDisplay = true
        enumerateAvailableRowViews { view, _ in view.needsDisplay = true }
    }

    override func drawBackground(inClipRect clipRect: NSRect) {
        let p = Palette.current
        for r in pane?.panelRects() ?? [] {
            fillRounded(r, radius: 4, p.bg.withAlpha(0.86))
            strokeRounded(r, radius: 4, p.line)
            drawBrackets(r.insetBy(dx: -1, dy: -1), color: p.accent.withAlpha(0.55).ns, length: 8)
        }
    }

    override func drawGrid(inClipRect clipRect: NSRect) {}

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setHovered(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(-1)
    }

    private func setHovered(_ row: Int) {
        guard row != hoveredRow else { return }
        let old = hoveredRow
        hoveredRow = row
        for r in [old, row] where r >= 0 && r < numberOfRows { rowView(atRow: r, makeIfNecessary: false)?.needsDisplay = true }
    }

    /// Where a row's chevron is drawn (and clicked), in outline coordinates; nil when it has none.
    func chevronRect(row: Int) -> NSRect? {
        guard let pane, let node = item(atRow: row) as? SideNode, isExpandable(node) else { return nil }
        let r = rect(ofRow: row)
        switch node.kind {
        case .volume, .share: return NSRect(x: 15, y: r.minY + 8.8, width: 16, height: 16)
        case .cloud: return NSRect(x: 21, y: r.midY - 8, width: 16, height: 16)
        case .folder: return NSRect(x: 19 + CGFloat(pane.depth(of: node)) * 14, y: r.midY - 8, width: 16, height: 16)
        default: return nil
        }
    }

    /// Clicks are tracked here rather than by NSTableView: a press on a chevron opens or closes, on
    /// the Eject button ejects, on a row selects it and, unless it turns into a drag, opens it.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0, let node = item(atRow: row) as? SideNode else { return }
        if let chevron = chevronRect(row: row), chevron.insetBy(dx: -4, dy: -4).contains(point) {
            pane?.toggle(node, all: event.modifierFlags.contains(.option))
            return
        }
        if let cell = view(atColumn: 0, row: row, makeIfNecessary: false) as? SideCellView, let button = cell.ejectButton,
           button.frame.contains(cell.convert(point, from: self)) {
            button.highlight(true)
            var inside: Bool?
            while let next = MouseTracking.next(window, [.leftMouseUp, .leftMouseDragged]) {
                if next.type == .leftMouseUp { inside = button.bounds.contains(button.convert(next.locationInWindow, from: nil)); break }
            }
            // No up event: a release that was not delivered counts; a press that timed out does not.
            let clicked = inside ?? (NSEvent.pressedMouseButtons & 1 == 0)
            button.highlight(false)
            if clicked { button.performClick(nil) }
            return
        }
        window.makeFirstResponder(self)
        if pane?.outlineView(self, shouldSelectItem: node) == true {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        while let next = MouseTracking.next(window, [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp { break }
            let p = convert(next.locationInWindow, from: nil)
            if hypot(p.x - point.x, p.y - point.y) > 4 {
                beginRowDrag(row, node: node, event: next)
                return
            }
        }
        pane?.activate(node)
    }

    /// A pin (to reorder) or a tree folder (to move or copy it) dragged out of the pane.
    private func beginRowDrag(_ row: Int, node: SideNode, event: NSEvent) {
        guard let pane, let writer = pane.outlineView(self, pasteboardWriterForItem: node) else { return }
        let item = NSDraggingItem(pasteboardWriter: writer)
        let r = rect(ofRow: row)
        let image = NSImage(size: r.size)
        if let view = rowView(atRow: row, makeIfNecessary: false),
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            image.addRepresentation(rep)
        }
        item.setDraggingFrame(r, contents: image)
        DragState.droppedInFolio = false
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func otherMouseDown(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard event.buttonNumber == 2, row >= 0, let node = item(atRow: row) as? SideNode else {
            return super.otherMouseDown(with: event)
        }
        pane?.middleClicked(node)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0, let node = item(atRow: row) as? SideNode, !node.isFooter else { return nil }
        return pane?.menu(for: node)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        pane?.clearDrop()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        super.draggingEnded(sender)
        pane?.clearDrop()
    }

    // MARK: Keys: Up and Down skip the gaps, Right opens or goes in, Left closes or goes up, * opens all

    override func becomeFirstResponder() -> Bool { redrawRows(); return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { redrawRows(); return super.resignFirstResponder() }

    private var selectedNode: SideNode? { selectedRow >= 0 ? item(atRow: selectedRow) as? SideNode : nil }

    private func select(row: Int, navigate: Bool) {
        guard row >= 0, row < numberOfRows else { return }
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        scrollRowToVisible(row)
        guard navigate else { return }
        // Explorer opens the folder the arrows land on, once they stop.
        navigateTimer?.invalidate()
        let timer = Timer(timeInterval: 0.45, repeats: false) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, let node = self.selectedNode, node.url != nil || { if case .home = node.kind { true } else { false } }()
                else { return }
                self.pane?.activate(node)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        navigateTimer = timer
    }

    private func step(_ delta: Int) {
        var row = selectedRow < 0 ? (delta > 0 ? -1 : numberOfRows) : selectedRow
        repeat {
            row += delta
        } while row >= 0 && row < numberOfRows && !(pane.map { $0.outlineView(self, shouldSelectItem: item(atRow: row) as Any) } ?? false)
        if row >= 0 && row < numberOfRows { select(row: row, navigate: true) }
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let pane else { return super.keyDown(with: event) }
        switch (event.keyCode, mods) {
        case (125, []): step(1)                                     // Down
        case (126, []): step(-1)                                    // Up
        case (115, []): select(row: 0, navigate: false); step(1)    // Home
        case (119, []): select(row: numberOfRows - 1, navigate: false); step(-1)
        case (124, []):                                             // Right: open, then into the first child
            guard let node = selectedNode else { return }
            if pane.outlineView(self, isItemExpandable: node) && !isItemExpanded(node) {
                expandItem(node)
                // Bring the opened children into view, keeping the node itself on screen.
                let kids = numberOfChildren(ofItem: node)
                if kids > 0 { scrollRowToVisible(min(numberOfRows - 1, selectedRow + kids)) }
                scrollRowToVisible(selectedRow)
            } else if isItemExpanded(node), selectedRow + 1 < numberOfRows {
                select(row: selectedRow + 1, navigate: true)
            }
        case (123, []):                                             // Left: close, else up to the parent
            guard let node = selectedNode else { return }
            if isItemExpanded(node) {
                collapseItem(node)
            } else if let parent = parent(forItem: node) {
                let r = row(forItem: parent)
                if r >= 0 { select(row: r, navigate: !(parent as? SideNode)!.isHeader) }
            }
        case (67, _):                                               // Numpad *: everything below
            if let node = selectedNode { pane.expandAll(node) }
        case (78, _):                                               // Numpad -: close it and all below
            if let node = selectedNode { collapseItem(node, collapseChildren: true) }
        case (36, []), (76, []), (49, []):                          // Return, Enter, Space
            if let node = selectedNode { pane.activate(node) }
        case (120, []):                                             // F2 on a drive: rename it
            if let node = selectedNode, case .volume(let v) = node.kind { pane.onRenameVolume?(v) }
        default:
            super.keyDown(with: event)
        }
    }

    /// The accent line where a dropped folder would be pinned.
    private final class InsertionOverlay: NSView {
        var y: CGFloat?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            guard let y else { return }
            let p = Palette.current
            let line = NSRect(x: 18, y: y - 1, width: bounds.width - 36, height: 2)
            fillRect(line, p.accent)
            fillRounded(NSRect(x: line.minX - 3, y: y - 3, width: 6, height: 6), radius: 3, p.accent)
        }
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        // The insertion line stays above the rows the table adds.
        if subview !== overlay, overlay.superview === self {
            addSubview(overlay, positioned: .above, relativeTo: nil)
        }
    }
}

/// A row: every navigation pane row is drawn here (headers, places, volumes with their bars, tree
/// folders), with the hover wash, the lit current row, the drop highlight and the keyboard focus.
final class SideRowView: NSTableRowView {
    var node: SideNode?
    weak var pane: NavigationPane?

    override var isFlipped: Bool { true }
    override var isSelected: Bool { didSet { if isSelected != oldValue { needsDisplay = true } } }

    private var outline: SidebarOutlineView? { superview as? SidebarOutlineView }
    private var myRow: Int { outline?.row(for: self) ?? -1 }

    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawBackground(in dirtyRect: NSRect) {}

    /// The row inside its panel (5 pt in from the panel's sides).
    private var inner: NSRect { NSRect(x: 15, y: 0, width: bounds.width - 30, height: bounds.height) }

    override func draw(_ dirtyRect: NSRect) {
        guard let node, let pane, let outline else { return }
        let p = Palette.current
        let row = myRow
        let hovered = row >= 0 && outline.hoveredRow == row
        let focused = isSelected && outline.window?.firstResponder === outline
        let on = pane.isCurrent(node)
        switch node.kind {
        case .header(let s): drawHeader(s, hovered: hovered, focused: focused, collapsed: pane.isCollapsed(s), p)
        case .footer: break
        default:
            let r = inner
            if on, node.volume == nil {
                fillRounded(r, radius: 3, p.selectionFill)
            } else if hovered {
                fillRounded(r, radius: 3, p.txt.withAlpha(0.08))
            }
            if outline.dropRow == row {
                fillRounded(r, radius: 3, p.markFill)
                strokeRounded(r.insetBy(dx: 0.5, dy: 0.5), radius: 3, p.accent)
                drawBrackets(r, color: p.accent.ns, length: 7)
            }
            drawContent(node, in: r, on: on, p)
            if focused { strokeRounded(r.insetBy(dx: 1, dy: 1), radius: 3, p.accent, width: 2) }
        }
    }

    private func drawHeader(_ s: SideNode.Section, hovered: Bool, focused: Bool, collapsed: Bool, _ p: Palette) {
        let r = NSRect(x: 10, y: 13, width: bounds.width - 20, height: 36)
        if hovered { fillRounded(r.insetBy(dx: 1, dy: 0), radius: 4, p.txt2.withAlpha(0.08)) }
        let mid = r.midY
        let glyph: Glyph = switch s { case .quickAccess: .star; case .thisPC: .pc; case .network: .globe; case .allFolders: .desktop }
        glyph.draw(in: NSRect(x: r.minX + 11, y: mid - 8, width: 16, height: 16), color: p.txt2.ns)
        let title = node?.title ?? ""
        let tw = drawLine(title, font: Typeface.ui(12, weight: 700, width: 124), color: p.txt, x: r.minX + 35, midY: mid, kern: 0.48)
        let shown = pane?.headerCount(s) ?? 0
        drawLine("\(shown)", font: Typeface.mono(12), color: p.txt3, x: r.minX + 35 + tw + 8, midY: mid)
        Glyph.chevronDown.draw(in: NSRect(x: r.maxX - 11 - 16, y: mid - 8, width: 16, height: 16), color: p.txt2.ns,
                               rotation: collapsed ? -.pi / 2 : 0)
        if focused { strokeRounded(r.insetBy(dx: 1, dy: 1), radius: 4, p.accent, width: 2) }
    }

    private func drawLight(at point: NSPoint, _ p: Palette) {
        let c = NSRect(x: point.x, y: point.y, width: 6, height: 6)
        fillRounded(c.insetBy(dx: -2, dy: -2), radius: 5, p.accent.withAlpha(0.18))
        if p.glows, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 4.5, color: p.accent.withAlpha(0.62).cg)
            fillRounded(c, radius: 3, p.accent)
            ctx.restoreGState()
        } else {
            fillRounded(c, radius: 3, p.accent)
        }
    }

    private func drawContent(_ node: SideNode, in r: NSRect, on: Bool, _ p: Palette) {
        let mid = r.midY
        let font = Typeface.ui(13)
        switch node.kind {
        case .home:
            if on { drawLight(at: NSPoint(x: r.minX + 8, y: (mid - 3).rounded()), p) }
            Glyph.home.draw(in: NSRect(x: r.minX + 24, y: mid - 8, width: 16, height: 16), color: (on ? p.accent : p.txt2).ns)
            drawLine("Home", font: font, color: on ? p.accent : p.txt, x: r.minX + 50, midY: mid, maxWidth: r.width - 58)
        case .pin(let place, _):
            if on { drawLight(at: NSPoint(x: r.minX + 8, y: (mid - 3).rounded()), p) }
            drawPlace(place, in: r, on: on, p)
        case .cloud(let c):
            if on { drawLight(at: NSPoint(x: r.minX + 8, y: (mid - 3).rounded()), p) }
            if let outline, outline.isExpandable(node) {
                Glyph.chevron.draw(in: NSRect(x: r.minX + 8, y: mid - 6, width: 12, height: 12), color: p.txt3.ns, lineWidth: 2,
                                   rotation: outline.isItemExpanded(node) ? .pi / 2 : 0)
            }
            let glyph: Glyph = c.path == FileManager.default.homeDirectoryForCurrentUser.path ? .home : .cloud
            glyph.draw(in: NSRect(x: r.minX + 24, y: mid - 8, width: 16, height: 16), color: (on ? p.accent : p.txt2).ns)
            drawLine(c.name, font: font, color: on ? p.accent : p.txt, x: r.minX + 50, midY: mid, maxWidth: r.width - 58)
        case .recycle:
            if on { drawLight(at: NSPoint(x: r.minX + 8, y: (mid - 3).rounded()), p) }
            Glyph.trash.draw(in: NSRect(x: r.minX + 24, y: mid - 8, width: 16, height: 16), color: (on ? p.accent : p.txt2).ns)
            drawLine("Recycle Bin", font: font, color: on ? p.accent : p.txt, x: r.minX + 50, midY: mid, maxWidth: r.width - 58)
        case .volume(let v): drawVolume(v, in: r, glyph: .drive, on: on, node: node, p)
        case .share(let v): drawVolume(v, in: r, glyph: .server, on: on, node: node, p)
        case .folder(let f):
            let depth = CGFloat(pane?.depth(of: node) ?? 0)
            let x0 = r.minX + 4 + depth * 14
            if let outline, outline.isExpandable(node) {
                Glyph.chevron.draw(in: NSRect(x: x0 + 2, y: mid - 6, width: 12, height: 12), color: p.txt3.ns, lineWidth: 2,
                                   rotation: outline.isItemExpanded(node) ? .pi / 2 : 0)
            }
            if on { drawLight(at: NSPoint(x: x0 - 6, y: (mid - 3).rounded()), p) }
            ItemIcon.drawFolder(in: NSRect(x: x0 + 18, y: mid - 6.5, width: 16, height: 13), palette: p, lit: on)
            let tone: RGBA = on ? p.accent : (f.isHidden ? p.txt3 : p.txt)
            drawLine(f.name, font: Typeface.ui(13, weight: on ? 600 : 400), color: tone, x: x0 + 42, midY: mid,
                     maxWidth: r.maxX - x0 - 48)
        case .browse:
            Glyph.globe.draw(in: NSRect(x: r.minX + 24, y: mid - 8, width: 16, height: 16), color: p.txt2.ns)
            drawLine(pane?.browseStatus ?? "Browse network", font: font, color: p.txt2, x: r.minX + 50, midY: mid, maxWidth: r.width - 58)
        case .device(let name):
            Glyph.pics.draw(in: NSRect(x: r.minX + 24, y: mid - 8, width: 16, height: 16), color: p.txt2.ns)
            drawLine(name, font: font, color: p.txt, x: r.minX + 50, midY: mid, maxWidth: r.width - 58)
        case .server(let name):
            Glyph.server.draw(in: NSRect(x: r.minX + 24, y: mid - 8, width: 16, height: 16), color: p.txt2.ns)
            drawLine(name, font: font, color: p.txt, x: r.minX + 50, midY: mid, maxWidth: r.width - 58)
        case .connect:
            Glyph.link.draw(in: NSRect(x: r.minX + 24, y: mid - 8, width: 16, height: 16), color: p.txt2.ns)
            drawLine("Connect to server...", font: font, color: p.txt2, x: r.minX + 50, midY: mid, maxWidth: r.width - 58)
        case .notice(let text):
            drawLine(text, font: Typeface.mono(11), color: p.part, x: r.minX + 10, midY: mid, maxWidth: r.width - 16)
        case .header, .footer:
            break
        }
    }

    private func drawPlace(_ place: QuickAccessPlace, in r: NSRect, on: Bool, _ p: Palette) {
        let mid = r.midY
        let iconX = r.minX + 8 + 6 + 10
        let glyph: Glyph? = switch place.title {
        case "Downloads": .download
        case "Desktop": .desktop
        case "Documents": .docs
        case "Pictures": .pics
        case "Movies": .movies
        default: nil
        }
        let textX: CGFloat
        if let glyph {
            glyph.draw(in: NSRect(x: iconX, y: mid - 8, width: 16, height: 16), color: (on ? p.accent : p.txt2).ns)
            textX = iconX + 16 + 10
        } else {
            ItemIcon.drawFolder(in: NSRect(x: iconX, y: mid - 7.5, width: 18, height: 15), palette: p, lit: on)
            textX = iconX + 18 + 10
        }
        let font = Typeface.ui(13)
        let room = r.maxX - 8 - textX
        let pw = place.prefix.isEmpty ? 0 : drawLine(place.prefix, font: font, color: p.txt3, x: textX, midY: mid, maxWidth: room)
        drawLine(place.title, font: font, color: on ? p.accent : p.txt, x: textX + pw, midY: mid, maxWidth: room - pw)
    }

    private func drawVolume(_ v: VolumeCapacity, in r: NSRect, glyph: Glyph, on: Bool, node: SideNode, _ p: Palette) {
        let topMid = r.minY + 8 + 8.8
        let tone: RGBA = v.isNearlyFull ? p.miss : p.accent
        if let outline {
            Glyph.chevron.draw(in: NSRect(x: r.minX + 2, y: topMid - 6, width: 12, height: 12), color: p.txt3.ns, lineWidth: 2,
                               rotation: outline.isItemExpanded(node) ? .pi / 2 : 0)
        }
        glyph.draw(in: NSRect(x: r.minX + 18, y: topMid - 8, width: 16, height: 16), color: (on ? p.accent : p.txt2).ns)
        let ejectRoom: CGFloat = v.canEject ? 26 : 0
        let pctW = drawLine(v.percentText, font: Typeface.mono(12), color: tone, x: r.maxX - 8 - ejectRoom, midY: topMid, alignRight: true)
        drawLine(pane?.label(v) ?? v.name, font: Typeface.ui(13, weight: 600), color: on ? p.accent : p.txt, x: r.minX + 42, midY: topMid,
                 maxWidth: r.width - 42 - 8 - pctW - 8 - ejectRoom)
        // 24 segments, gap 2, the used share lit in the accent (red from 90% full).
        let barY = r.minY + 8 + 17.55 + 9
        let barW = r.width - 16
        let segW = (barW - 23 * 2) / 24
        let lit = v.litSegments()
        for i in 0..<24 {
            let seg = NSRect(x: r.minX + 8 + CGFloat(i) * (segW + 2), y: barY, width: segW, height: 10)
            if i < lit {
                if p.glows, let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: 9, color: tone.withAlpha(0.5).cg)
                    fillRounded(seg, radius: 1, tone)
                    ctx.restoreGState()
                } else {
                    fillRounded(seg, radius: 1, tone)
                }
            } else {
                fillRounded(seg, radius: 1, p.line2)
            }
        }
        let subMid = barY + 10 + 7 + 8.1
        drawLine(v.freeText, font: Typeface.mono(12), color: v.isNearlyFull ? p.miss : p.txt2, x: r.minX + 8, midY: subMid)
        drawLine(v.totalText, font: Typeface.mono(12), color: p.txt2, x: r.maxX - 8, midY: subMid, alignRight: true)
    }
}

/// The row's cell: no drawing of its own, the row's name for accessibility, and the Eject button on
/// drives that can be ejected (Disconnect on shares).
final class SideCellView: NSTableCellView {
    private var eject: ChromeButton?
    var ejectButton: ChromeButton? { eject }
    private var volume: VolumeCapacity?
    private weak var pane: NavigationPane?

    override var isFlipped: Bool { true }

    func configure(_ node: SideNode, pane: NavigationPane) {
        self.pane = pane
        setAccessibilityLabel(node.title)
        setAccessibilityRole(.cell)
        if let v = node.volume, v.canEject {
            volume = v
            let label = (v.isNetwork ? "Disconnect " : "Eject ") + v.name
            let button = ChromeButton(glyph: .eject, label: label, target: self, action: #selector(ejectPressed(_:)))
            button.iconSize = 14
            button.tone = { $0.txt2 }
            button.hoverTone = { $0.accent }
            addSubview(button)
            eject = button
        }
    }

    override func layout() {
        super.layout()
        guard let eject, let row = superview else { return }
        let r = row.bounds
        let inner = NSRect(x: 15, y: 0, width: r.width - 30, height: r.height)
        let frame = NSRect(x: inner.maxX - 8 - 22, y: 8 + 8.8 - 11, width: 22, height: 22)
        eject.frame = convert(frame, from: row)
    }

    @objc private func ejectPressed(_ sender: Any?) {
        if let volume { pane?.onEject?(volume) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only the Eject button takes clicks; the rest go to the outline (select, drag, open).
        if let eject, !eject.isHidden, let hit = eject.hitTest(convert(point, from: superview)) { return hit }
        return nil
    }
}

/// Following a press without trusting that its button-up event arrives: the next drag or up event, or
/// nil once the mouse button is no longer down, or when nothing has happened for `idle` seconds (a
/// release that never reached the app must not leave the window stuck in the press).
@MainActor
enum MouseTracking {
    static func next(_ window: NSWindow, _ mask: NSEvent.EventTypeMask, idle: TimeInterval = 3) -> NSEvent? {
        let giveUp = Date(timeIntervalSinceNow: idle)
        while Date() < giveUp {
            if let e = window.nextEvent(matching: mask, until: Date(timeIntervalSinceNow: 0.1), inMode: .eventTracking, dequeue: true) {
                return e
            }
            if NSEvent.pressedMouseButtons & 1 == 0 { return nil }
        }
        return nil
    }
}
