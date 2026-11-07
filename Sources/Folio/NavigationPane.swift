import AppKit
import FolioCore

/// The sidebar (D4's `.side`): one outline drawn as spotlight cards. Quick access (Home and the pins),
/// This PC (every volume with its capacity bar, each the root of a folder tree), Details (the selected
/// item) and Network (mounted shares, servers found on the network, Connect to server).
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
        fillRect(bounds, p.side)
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
    /// `allFolders` replaces This PC and Network with Folder Options > Show all folders on. `details` is
    /// D4's card for the selected item.
    enum Section: String, CaseIterable { case quickAccess, thisPC, network, allFolders, details }

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
        /// The Details card's body.
        case details
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
        case .header(.details): "Details"
        case .details: ""
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
    private let detailsNode = SideNode(.details)
    /// The Details card: what the window has selected.
    var details = DetailsCard.make([]) {
        didSet {
            guard details != oldValue, let outline else { return }
            let row = outline.row(forItem: detailsNode)
            if row >= 0 { outline.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row)) }
            outline.redrawRows()
        }
    }
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

    /// The cards shown, top to bottom: D4's Quick access, This PC and Details, then Network.
    var sections: [SideNode.Section] {
        var out: [SideNode.Section] = [.quickAccess]
        if layoutOptions.showAllFolders { return out + [.allFolders, .details] }
        if layoutOptions.showThisPC { out.append(.thisPC) }
        out.append(.details)
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

    /// The number a card's label shows: pins, drives, shares (Details has none).
    func headerCount(_ s: SideNode.Section) -> Int? {
        switch s {
        case .quickAccess: pinNodes.count
        case .thisPC, .allFolders: volumeNodes.count
        case .network: shareNodes.count
        case .details: nil
        }
    }

    /// The hue a card's rows take on hover (D4's `--hue` per card).
    func hue(of s: SideNode.Section, _ p: Palette) -> RGBA {
        switch s {
        case .quickAccess, .allFolders: p.accent
        case .thisPC: p.hue(.green)
        case .network: p.hue(.teal)
        case .details: p.accent
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
        case .details: return [detailsNode]
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

    /// D4's cards: 10 pt between them, a 40 pt label row, 30 pt items, 8 pt under the last item, and 14 pt
    /// under the last card. A drive adds its capacity bar and free space under its row.
    static let cardGap: CGFloat = 10, labelH: CGFloat = 40, itemH: CGFloat = 30, volumeH: CGFloat = 68

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let node = item as? SideNode else { return Self.itemH }
        switch node.kind {
        case .header: return Self.cardGap + Self.labelH
        case .footer(let s):
            let open = !collapsed.contains(s.rawValue)
            return (open ? 8 : 0) + 1 + (s == sections.last ? 14 : 0)
        case .volume, .share: return Self.volumeH
        case .folder: return 26
        case .details: return DetailsCardDrawing.height(details, width: outlineView.bounds.width - 20)
        default: return Self.itemH
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
        if case .details = node.kind { return false }
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

    /// Whether a row is the place the window shows (drawn lit, as D4's `.sitem.on`).
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

    /// The cards (label row to footer), drawn behind the rows.
    func panelRects() -> [NSRect] {
        guard let outline else { return [] }
        let w = outline.bounds.width
        return SideNode.Section.allCases.compactMap { s in
            guard let h = headers[s], let f = footers[s] else { return nil }
            let hr = outline.row(forItem: h), fr = outline.row(forItem: f)
            guard hr >= 0, fr >= 0 else { return nil }
            let top = outline.rect(ofRow: hr).minY + Self.cardGap
            let bottom = outline.rect(ofRow: fr).maxY - (s == sections.last ? 14 : 0)
            return NSRect(x: 10, y: top, width: w - 20, height: bottom - top)
        }
    }

    /// The card a row belongs to.
    func section(of node: SideNode) -> SideNode.Section? {
        guard let outline else { return nil }
        var item: Any? = node
        while let n = item as? SideNode {
            if case .header(let s) = n.kind { return s }
            item = outline.parent(forItem: n)
        }
        return nil
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
        case .footer, .notice, .details: break
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

/// The outline: no header, no native disclosure triangles (the rows draw their own chevrons), D4's cards
/// behind the groups, an insertion line for pins, and the tree keys.
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

    /// `.scard.os-card`: s1, a hairline, radius 12; no hover effect on the card itself.
    override func drawBackground(inClipRect clipRect: NSRect) {
        let p = Palette.current
        for r in pane?.panelRects() ?? [] {
            fillRounded(r, radius: 12, p.s1)
            strokeRounded(r, radius: 12, p.line)
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
        case .volume, .share: return NSRect(x: 12, y: r.minY + 7, width: 16, height: 16)
        case .cloud: return NSRect(x: 12, y: r.midY - 8, width: 16, height: 16)
        case .folder: return NSRect(x: 18 + CGFloat(pane.depth(of: node)) * 14, y: r.midY - 8, width: 16, height: 16)
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
            let line = NSRect(x: 24, y: y - 1, width: bounds.width - 48, height: 2)
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

/// A row: every navigation pane row is drawn here (card labels, places, drives with their capacity bars,
/// tree folders, the Details card), with D4's `.sitem` states: a 7% wash on hover, the accent at 16% with
/// a glowing left edge on the current place, the drop highlight and the keyboard focus ring.
final class SideRowView: NSTableRowView {
    var node: SideNode?
    weak var pane: NavigationPane?

    override var isFlipped: Bool { true }
    override var isSelected: Bool { didSet { if isSelected != oldValue { needsDisplay = true } } }

    private var outline: SidebarOutlineView? { superview as? SidebarOutlineView }
    private var myRow: Int { outline?.row(for: self) ?? -1 }

    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawBackground(in dirtyRect: NSRect) {}

    /// The row across its card (the card is 10 pt in from the sidebar's sides).
    private var inner: NSRect { NSRect(x: 10, y: 0, width: bounds.width - 20, height: bounds.height) }
    /// The 30 pt item line at the top of the row (a drive's bar and free space sit under it).
    private var line: NSRect { NSRect(x: inner.minX, y: 0, width: inner.width, height: min(bounds.height, NavigationPane.itemH)) }

    override func draw(_ dirtyRect: NSRect) {
        guard let node, let pane, let outline else { return }
        let p = Palette.current
        let row = myRow
        let hovered = row >= 0 && outline.hoveredRow == row
        let focused = isSelected && outline.window?.firstResponder === outline
        let on = pane.isCurrent(node)
        let hue = pane.section(of: node).map { pane.hue(of: $0, p) } ?? p.accent
        switch node.kind {
        case .header(let s): drawHeader(s, hovered: hovered, focused: focused, collapsed: pane.isCollapsed(s), p)
        case .footer: break
        case .details: DetailsCardDrawing.draw(pane.details, in: inner, p)
        default:
            // `.sitem::before`: inset 1 pt top and bottom and 6 pt at the sides, radius 8.
            let wash = line.insetBy(dx: 6, dy: 1)
            if on {
                fillRounded(wash, radius: 8, p.accent.withAlpha(0.16))
                drawEdgeBar(NSRect(x: inner.minX, y: line.minY + 7, width: 3, height: line.height - 14), color: p.accent,
                            glowAlpha: 1, rounded: true)
            } else if hovered {
                fillRounded(wash, radius: 8, p.text.withAlpha(0.07))
            }
            if outline.dropRow == row {
                fillRounded(wash, radius: 8, p.markFill)
                strokeRounded(wash, radius: 8, p.accent)
            }
            drawContent(node, on: on, hovered: hovered, hue: hue, p)
            if focused { strokeRounded(line.insetBy(dx: 3, dy: 1), radius: 8, p.accent, width: 2) }
        }
    }

    /// `.scard-h`: the mono uppercase label (text-2 on hover), the count, and the chevron at the right.
    private func drawHeader(_ s: SideNode.Section, hovered: Bool, focused: Bool, collapsed: Bool, _ p: Palette) {
        let r = NSRect(x: inner.minX, y: NavigationPane.cardGap, width: inner.width, height: NavigationPane.labelH)
        let mid = r.midY
        let title = (node?.title ?? "").uppercased()
        let font = Typeface.mono(12, weight: 600)
        let tw = drawLine(title, font: font, color: hovered ? p.text2 : p.muted, x: r.minX + 14, midY: mid, kern: Typeface.labelKern(12))
        if let count = pane?.headerCount(s) {
            drawLine("\(count)", font: Typeface.mono(12, weight: 500), color: p.muted, x: r.minX + 14 + tw + 8, midY: mid)
        }
        Glyph.chevronDown.draw(in: NSRect(x: r.maxX - 10 - 16, y: mid - 8, width: 16, height: 16), color: p.muted.ns,
                               rotation: collapsed ? -.pi / 2 : 0)
        if focused { strokeRounded(r.insetBy(dx: 3, dy: 3), radius: 12, p.accent, width: 2) }
    }

    /// A place's glyph: muted, the card's hue under the pointer, the accent when it is the current place.
    private func glyphTone(on: Bool, hovered: Bool, hue: RGBA, _ p: Palette) -> RGBA { on ? p.accent : hovered ? hue : p.muted }
    private func labelTone(on: Bool, hovered: Bool, _ p: Palette) -> RGBA { on || hovered ? p.text : p.text2 }

    private func drawContent(_ node: SideNode, on: Bool, hovered: Bool, hue: RGBA, _ p: Palette) {
        let r = line
        let mid = r.midY
        let font = Typeface.ui(13, weight: 500)
        let icon = NSRect(x: r.minX + 14, y: mid - 8, width: 16, height: 16)
        let textX = icon.maxX + 10
        let room = r.maxX - 12 - textX
        let glyph = glyphTone(on: on, hovered: hovered, hue: hue, p).ns
        let label = labelTone(on: on, hovered: hovered, p)
        func chevron(at x: CGFloat) {
            guard let outline, outline.isExpandable(node) else { return }
            Glyph.chevron.draw(in: NSRect(x: x, y: mid - 5, width: 10, height: 10), color: p.muted.ns, lineWidth: 2.2,
                               rotation: outline.isItemExpanded(node) ? .pi / 2 : 0)
        }
        switch node.kind {
        case .home:
            Glyph.home.draw(in: icon, color: glyph)
            drawLine("Home", font: font, color: label, x: textX, midY: mid, maxWidth: room)
        case .pin(let place, _):
            drawPlace(place, icon: icon, textX: textX, room: room, glyph: glyph, label: label, p)
        case .cloud(let c):
            chevron(at: r.minX + 3)
            let g: Glyph = c.path == FileManager.default.homeDirectoryForCurrentUser.path ? .home : .cloud
            g.draw(in: icon, color: glyph)
            drawLine(c.name, font: font, color: label, x: textX, midY: mid, maxWidth: room)
        case .recycle:
            Glyph.trash.draw(in: icon, color: glyph)
            drawLine("Recycle Bin", font: font, color: label, x: textX, midY: mid, maxWidth: room)
        case .volume(let v): drawVolume(v, glyph: .drive, on: on, hovered: hovered, hue: hue, node: node, p)
        case .share(let v): drawVolume(v, glyph: .server, on: on, hovered: hovered, hue: hue, node: node, p)
        case .folder(let f):
            let depth = CGFloat(pane?.depth(of: node) ?? 0)
            let x0 = r.minX + 8 + depth * 14
            chevron(at: x0 + 3)
            ItemIcon.drawFolder(in: NSRect(x: x0 + 18, y: mid - 8, width: 16, height: 16), hue: p.accent, palette: p, glow: on || hovered)
            let tone: RGBA = on ? p.text : (f.isHidden ? p.muted : label)
            drawLine(f.name, font: Typeface.ui(13, weight: on ? 600 : 500), color: tone, x: x0 + 42, midY: mid, maxWidth: r.maxX - x0 - 48)
        case .browse:
            Glyph.globe.draw(in: icon, color: glyph)
            drawLine(pane?.browseStatus ?? "Browse network", font: font, color: label, x: textX, midY: mid, maxWidth: room)
        case .device(let name):
            Glyph.pics.draw(in: icon, color: glyph)
            drawLine(name, font: font, color: label, x: textX, midY: mid, maxWidth: room)
        case .server(let name):
            Glyph.server.draw(in: icon, color: glyph)
            drawLine(name, font: font, color: label, x: textX, midY: mid, maxWidth: room)
        case .connect:
            Glyph.link.draw(in: icon, color: glyph)
            drawLine("Connect to server...", font: font, color: label, x: textX, midY: mid, maxWidth: room)
        case .notice(let text):
            drawLine(text, font: Typeface.mono(12), color: p.part, x: r.minX + 14, midY: mid, maxWidth: r.width - 26)
        case .header, .footer, .details:
            break
        }
    }

    /// A pin: D4's place glyphs (download, monitor, doc, image, film), else the accent folder; the
    /// parent path dim before the name ("Anshul/" Code).
    private func drawPlace(_ place: QuickAccessPlace, icon: NSRect, textX: CGFloat, room: CGFloat, glyph: NSColor, label: RGBA, _ p: Palette) {
        let g: Glyph? = switch place.title {
        case "Downloads": .download
        case "Desktop": .desktop
        case "Documents": .docs
        case "Pictures": .pics
        case "Movies": .movies
        case "Code": .code
        default: nil
        }
        if let g {
            g.draw(in: icon, color: glyph)
        } else {
            ItemIcon.drawFolder(in: icon, hue: p.accent, palette: p)
        }
        let font = Typeface.ui(13, weight: 500)
        let pw = place.prefix.isEmpty ? 0 : drawLine(place.prefix, font: font, color: p.muted, x: textX, midY: icon.midY, maxWidth: room)
        drawLine(place.title, font: font, color: label, x: textX + pw, midY: icon.midY, maxWidth: room - pw)
    }

    /// A drive (`.sitem` + `.cap` + `.cap-l`): the row with its used share in the card's hue, a 6 pt
    /// capacity bar glowing in the hue (coral from 90% full), and "81.0 GB free of 926 GB" in mono.
    private func drawVolume(_ v: VolumeCapacity, glyph: Glyph, on: Bool, hovered: Bool, hue: RGBA, node: SideNode, _ p: Palette) {
        let r = line
        let mid = r.midY
        let tone: RGBA = v.isNearlyFull ? p.miss : hue
        if let outline, outline.isExpandable(node) {
            Glyph.chevron.draw(in: NSRect(x: r.minX + 3, y: mid - 5, width: 10, height: 10), color: p.muted.ns, lineWidth: 2.2,
                               rotation: outline.isItemExpanded(node) ? .pi / 2 : 0)
        }
        let icon = NSRect(x: r.minX + 16, y: mid - 8, width: 16, height: 16)
        glyph.draw(in: icon, color: glyphTone(on: on, hovered: hovered, hue: hue, p).ns)
        let ejectRoom: CGFloat = v.canEject ? 26 : 0
        let pctW = drawLine(v.percentText, font: Typeface.mono(12, weight: 500), color: tone, x: r.maxX - 12 - ejectRoom, midY: mid,
                            alignRight: true)
        drawLine(pane?.label(v) ?? v.name, font: Typeface.ui(13, weight: 500), color: labelTone(on: on, hovered: hovered, p),
                 x: icon.maxX + 10, midY: mid, maxWidth: r.maxX - 12 - ejectRoom - pctW - 8 - icon.maxX - 10)
        // `.cap`: 6 pt, 6 pt under the row, 14 pt in from the card's sides, s3 track.
        let bar = NSRect(x: inner.minX + 14, y: r.maxY + 6, width: inner.width - 28, height: 6)
        fillRounded(bar, radius: 3, p.s3)
        let used = NSRect(x: bar.minX, y: bar.minY, width: max(bar.height, bar.width * CGFloat(min(1, v.usedFraction))), height: bar.height)
        withGlow(tone, blur: 10) { fillRounded(used, radius: 3, tone) }
        // `.cap-l`: the free figure in text-2 500, the rest muted.
        let mono = Typeface.mono(12)
        let s = NSMutableAttributedString(string: ByteText.storage(v.free),
                                          attributes: [.font: Typeface.mono(12, weight: 500), .foregroundColor: p.text2.ns])
        s.append(NSAttributedString(string: " free of " + ByteText.storage(v.total), attributes: [.font: mono, .foregroundColor: p.muted.ns]))
        drawAttributed(s, x: inner.minX + 14, midY: bar.maxY + 8 + 8, width: min(ceil(s.size().width), inner.width - 28), font: mono)
    }
}

/// The Details card's body (D4's `.dt`): the glyph at 34 pt with the name and kind beside it, then each
/// field's mono uppercase key over its value; or "Select an item to see its details here."
@MainActor
enum DetailsCardDrawing {
    private static let pad: CGFloat = 14
    private static var keyFont: NSFont { Typeface.mono(12, weight: 600) }
    private static var valueFont: NSFont { Typeface.mono(12) }
    private static var nameFont: NSFont { Typeface.ui(14, weight: 600) }

    private static func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        style.lineHeightMultiple = 1.1
        let r = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
            .boundingRect(with: NSSize(width: max(10, width), height: 1000), options: [.usesLineFragmentOrigin])
        return ceil(r.height)
    }

    /// Height of the body for a card `width` wide.
    static func height(_ card: DetailsCard, width: CGFloat) -> CGFloat {
        let w = width - 2 * pad
        if card.isEmpty { return textHeight(card.title, font: Typeface.ui(12), width: w) + 12 }
        var h: CGFloat = 2 + 34 + 12
        for f in card.fields { h += 17 + 3 + textHeight(f.value, font: valueFont, width: w) + 7 }
        return h - (card.fields.isEmpty ? 12 : 7) + 10
    }

    static func draw(_ card: DetailsCard, in r: NSRect, _ p: Palette) {
        let x = r.minX + pad, w = r.width - 2 * pad
        if card.isEmpty {
            draw(card.title, font: Typeface.ui(12), color: p.muted, in: NSRect(x: x, y: r.minY, width: w, height: r.height))
            return
        }
        let icon = NSRect(x: x, y: r.minY + 2, width: 34, height: 34)
        switch card.icon {
        case .item(let name, let isFolder)?: ItemIcon.draw(name: name, isFolder: isFolder, in: icon, palette: p)
        case .stack?: Glyph.stack.draw(in: icon.insetBy(dx: 3, dy: 3), color: p.accent.ns, lineWidth: 1.6)
        case nil: break
        }
        drawLine(card.title, font: nameFont, color: p.text, x: icon.maxX + 12, midY: icon.midY - 8, maxWidth: w - 46)
        drawLine(card.subtitle, font: Typeface.ui(12), color: p.muted, x: icon.maxX + 12, midY: icon.midY + 9, maxWidth: w - 46)
        var y = icon.maxY + 12
        for f in card.fields {
            drawLine(f.key.uppercased(), font: keyFont, color: p.muted, x: x, midY: y + 8.5, kern: Typeface.labelKern(12))
            y += 17 + 3
            let h = textHeight(f.value, font: valueFont, width: w)
            draw(f.value, font: valueFont, color: p.text2, in: NSRect(x: x, y: y, width: w, height: h))
            y += h + 7
        }
    }

    private static func draw(_ text: String, font: NSFont, color: RGBA, in rect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        style.lineHeightMultiple = 1.1
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color.ns, .paragraphStyle: style])
            .draw(with: rect, options: [.usesLineFragmentOrigin])
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
            button.tone = { $0.muted }
            button.hoverTone = { $0.accent }
            addSubview(button)
            eject = button
        }
    }

    override func layout() {
        super.layout()
        guard let eject, let row = superview else { return }
        let r = row.bounds
        let inner = NSRect(x: 10, y: 0, width: r.width - 20, height: r.height)
        let frame = NSRect(x: inner.maxX - 6 - 22, y: NavigationPane.itemH / 2 - 11, width: 22, height: 22)
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
