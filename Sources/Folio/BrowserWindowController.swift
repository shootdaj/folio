import AppKit
import FolioCore

/// Sees key presses before the table does, so Option+arrows work wherever focus is.
final class BrowserWindow: NSWindow {
    /// `--uitest` places the window off every screen so a run never covers what is on the desktop.
    var allowsOffscreen = false

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, PerfTrace.isOn { PerfTrace.mark("key", "code=\(event.keyCode)") }
        if let controller = windowController as? BrowserWindowController {
            // Access keys: an Option tap shows the command bar's letters; the next key uses or hides them.
            if event.type == .flagsChanged { controller.handleFlagsChanged(event) }
            if event.type == .flagsChanged {
                KeyLog.write("flags key=\(event.keyCode) mods=\(KeyLog.mods(event)) accessKeys=\(controller.showsAccessKeys)")
            }
            if event.type == .keyDown, controller.handleAccessKeyDown(event) {
                KeyLog.write("keyDown key=\(event.keyCode) mods=\(KeyLog.mods(event)) -> consumed by access keys")
                return
            }
            if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type), controller.showsAccessKeys {
                controller.setAccessKeys(false)
            }
            if event.type == .keyDown {
                let handled = controller.handleKeyDown(event)
                let responder = firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
                KeyLog.write("keyDown key=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "") mods=\(KeyLog.mods(event)) firstResponder=\(responder) dropdownOpen=\(controller.dropdown.isOpen) handled=\(handled)")
                if handled { return }
            }
            // Explorer's Ctrl+wheel (Cmd+scroll here) and a trackpad pinch step through the views.
            if event.type == .scrollWheel, event.modifierFlags.contains(.command), controller.zoomsWithScroll {
                controller.grid.zoom(with: event)
                return
            }
            if event.type == .magnify, controller.zoomsWithScroll {
                controller.pinch(event)
                return
            }
            // Mouse buttons 4 and 5 go back and forward (the middle button, 2, opens tabs where it lands).
            if event.type == .otherMouseDown, event.buttonNumber == 3 { controller.goBack(nil); return }
            if event.type == .otherMouseDown, event.buttonNumber == 4 { controller.goForward(nil); return }
        }
        super.sendEvent(event)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        allowsOffscreen ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    /// Centres the window's own close, minimise and zoom buttons in D4's 44 pt title bar,
    /// 14 pt from the left edge and 20 pt apart.
    func placeTrafficLights() {
        guard !styleMask.contains(.fullScreen),
              let close = standardWindowButton(.closeButton),
              let container = close.superview?.superview else { return }
        let bar = ChassisView.titleH
        var frame = container.frame
        frame.size.height = bar
        frame.origin.y = self.frame.height - bar
        if container.frame != frame { container.frame = frame }
        for (i, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = standardWindowButton(kind), let holder = button.superview else { continue }
            // Centred on the bar whichever way the holder is flipped.
            let midY = holder.convert(NSPoint(x: 0, y: frame.height / 2), from: container).y
            let origin = NSPoint(x: 16 - (button.frame.width - 12) / 2 + CGFloat(i) * 20,
                                 y: (midY - button.frame.height / 2).rounded())
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }
}

/// One window in D4's Obsidian spotlight chassis: tabs, each showing a folder in a Details view (or Home),
/// with the navigation pane's tree beside them.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {

    struct Options {
        var size = NSSize(width: 1280, height: 800)
        /// `--uitest`: no column autosave, no window restoration, placed off-screen.
        var uitest = false
        /// Where the address history lives: the app's defaults, or a temp store under `--uitest`.
        var historyDefaults: UserDefaults = .standard
    }

    /// The window's tabs; the shown one owns the history, sort and selection the list works with.
    var tabs: TabList
    var history: NavigationHistory {
        get { tabs.active.history }
        set { tabs.active.history = newValue }
    }
    let options: Options
    /// The row to bring back to the top once a tab's listing lands (switching back to a tab).
    var restoreRow: Int?
    /// The navigation pane's open folders from the session, waiting for the drives (milestone 9).
    var pendingTreeFolders: [String]?
    /// The folder as listed (or the search results), before filters, sort and groups.
    var listing: [FileEntry] = []
    /// Header filters: transient, dropped on navigating away and never saved.
    var filters = FilterSet()
    /// Group by groups folded shut (bucket ids), until the folder changes.
    var collapsedGroups: Set<String> = []
    /// What the list shows: the shown items in order and, when grouped, the header rows between them.
    private(set) var layout = ListLayout(items: [])
    /// The inputs `layout` was arranged from, to tell when it must be arranged again.
    var arrangedWith: ArrangeKey?
    /// The shown items in order (collapsed groups' items left out); selection indexes these.
    private(set) var entries: [FileEntry] = []
    /// `FilePaths.itemKey` of each entry: selection, dimming and refreshes match on these.
    private(set) var entryKeys: [String] = []
    /// Explorer's selection rules (anchor, focus, ranges); the table shows `selection.rows`.
    var selection = ListSelection(count: 0)
    private var applyingSelection = false
    /// Paths to select once the next listing lands (after a paste, rename, undo).
    var pendingSelect: Set<String>?
    private var scrollToPending = false
    /// Starts F2 on this item once the listing lands (New folder, Tab while renaming).
    var pendingRenamePath: String?
    /// Cut items, dimmed until pasted.
    var dimmed: Set<String> = []
    let renamer = RenameEditor()
    /// Several selected and F2: the items Enter renames to "Name (1)", "Name (2)".
    var renameBatch: [URL]?
    private var refreshAfterRename = false
    /// The tab's sort, or while searching the results' own (nil `searchSort` is relevance order).
    var sortSpec: SortSpec {
        get { isSearching ? (searchSort ?? tabs.active.sort) : tabs.active.sort }
        set { if isSearching { searchSort = newValue } else { tabs.active.sort = newValue } }
    }

    // MARK: Search state (Search.swift)

    var searchEngine: SearchEngine?
    /// Bumped per run; updates from an older run are dropped.
    var searchRun = 0
    var searchHits: [SearchHit] = []
    var searchStarted = Date()
    var searchFinished = false
    var searchEngineProgress = 0.0
    var searchDebounce: Timer?
    var searchTicker: Timer?
    var searchError: String?
    /// A header clicked in the results; nil keeps relevance order.
    var searchSort: SortSpec?
    /// A view picked while results show (they open in Details).
    var searchView: ViewMode?
    var searchUIShown = false
    /// The bare and name: terms, for highlighting names.
    var searchTerms: [TextMatch] = []
    var searchReplacePending = false
    var searchLoggedFirst = false
    /// Each searching tab's Group by from before its results showed (results start ungrouped; leaving
    /// the search puts it back).
    var groupsBeforeSearch: [UUID: GroupSpec?] = [:]
    /// The tab the results' own sort and view belong to.
    var searchTabID: UUID?
    /// Group by of the shown tab; nil is (None).
    var group: GroupSpec? {
        get { tabs.active.group }
        set { tabs.active.group = newValue }
    }
    var isLoading = false
    private var isResorting = false
    var loadError: String?
    /// The share button, for anchoring the share picker.
    var shareButton: ChromeButton?
    private var volume: VolumeCapacity?
    /// Every mounted volume, for the address bar, Send to and File > Eject.
    var volumes: [VolumeCapacity] = []
    /// The list shows the Trash: Date deleted and Original location columns, Restore in the menus.
    var isTrashView = false {
        didSet {
            guard isTrashView != oldValue else { return }
            for column in tableView.tableColumns {
                if let key = SortKey(rawValue: column.identifier.rawValue) { column.title = columnTitle(key) }
            }
            header.needsDisplay = true
        }
    }
    /// Bumped on every load or re-sort; results for an older value are dropped.
    var requestID = 0
    /// The folder read in flight (`load`), cancelled when a newer one starts.
    private var loadTask: Task<Void, Never>?
    /// Streaming search results are arranged at a pace (arrangeSearchSoon).
    var searchArrangeWork: DispatchWorkItem?
    var lastSearchArrange: CFTimeInterval = 0
    var lastSearchTitle = ""
    /// The Preview pane, Gallery and Quick Look follow the selection at this pace (updatePreviewsSoon).
    var previewWork: DispatchWorkItem?
    var lastPreviewUpdate: CFTimeInterval = 0
    private var isFittingColumns = false
    /// The one dropdown this window shows at a time (typeahead, history, crumb folders, Back list).
    let dropdown = Dropdown()
    /// The accent picker under the title bar's swatch.
    lazy var accentPicker = AccentPicker()
    private let addressHistory: AddressHistory
    /// "No such folder" after Enter on a bad address, until the next edit or navigation.
    var statusMessage: String?
    /// Quick access pins, shared by every window through the defaults.
    var pins: PinStore
    /// The drag badge ("Move to target") and the folder a drag is hovering to spring open.
    let dropTip = DropTipView()
    var springTarget: URL?
    var springTimer: Timer?
    /// The folder row lit under a drag (-1 for none); the list draws D4's feedback, not AppKit's.
    /// The folder item lit under a drag (-1 for none); the list draws D4's feedback, not AppKit's.
    var dropTargetRow = -1 {
        didSet {
            guard dropTargetRow != oldValue else { return }
            tableView.enumerateAvailableRowViews { view, row in
                (view as? FolioRowView)?.isDropTarget = dropTargetRow >= 0 && layout.item(atRow: row) == dropTargetRow
            }
            grid.forEachVisibleCell { cell, i in cell.isDropTarget = i == dropTargetRow }
        }
    }
    /// The open header filter, and Choose details while it is up.
    var filterPanel: FilterPanelController?
    var columnChooser: ColumnChooserPanel?
    /// What Quick Look shows: the selection when it opened.
    var quickLookItems: [URL] = []

    // MARK: Milestone 8 state

    /// The tab shows the inside of a zip (read-only, Explorer's Compressed folder).
    var isInZip = false
    var extractSheet: ExtractSheetController?
    /// Auto-refresh: every tab's folder (kqueue and FSEvents) and the tree's roots (FSEvents).
    var folderWatcher: FolderWatcher?
    var treeWatcher: TreeWatcher?
    /// Access keys: Option tapped alone shows the command bar's letters until a letter, Esc or a click.
    var optionTap = OptionTap()
    var showsAccessKeys = false
    /// What the listing was last read with, to tell when Folder Options need it read again.
    var listedWith: (hidden: Bool, protected: Bool) = (false, true)

    let tableView = FolioTableView()
    /// Every view but Details.
    let grid = FileGridView()
    /// The list the keyboard and menus act on: the table in Details, the grid otherwise.
    var listView: NSView { viewMode.usesTable ? tableView : grid }
    var viewMode: ViewMode { isSearching ? (searchView ?? .details) : ViewCenter.shared.mode }
    /// The Recycle Bin's Date and Type columns read Date deleted and Original location.
    func columnTitle(_ key: SortKey) -> String {
        guard isTrashView else { return key.title }
        return key == .modified ? "Date deleted" : key == .kind ? "Original location" : key.title
    }
    /// Metadata reads waiting to be sent off the main thread, and those already on their way.
    var metadataQueue: [FileEntry] = []
    var metadataInFlight: Set<String> = []
    var metadataFlushScheduled = false
    private var isRebuildingColumns = false
    var typeSelectBuffer = ""
    var typeSelectTime: TimeInterval = 0
    var pinchTotal: CGFloat = 0
    let header = FolioHeaderView(frame: NSRect(x: 0, y: 0, width: 100,
                                                       height: ListMetrics.headerHeight + ListMetrics.listTopPad))
    private(set) var chassis: ChassisView!
    var titleBar: TitleBarView { chassis.titleBar }
    var toolbar: ToolbarView { chassis.toolbar }

    static let nameMinWidth: CGFloat = 120

    /// True once the listing and any re-sort have landed.
    var isIdle: Bool { !isLoading && !isResorting }

    convenience init(folder: URL, options: Options = Options()) {
        self.init(tabs: [BrowserTab(folder: folder)], active: 0, options: options)
    }

    init(tabs list: [BrowserTab], active: Int, options: Options = Options()) {
        tabs = TabList(list, active: active)
        self.options = options
        addressHistory = AddressHistory(defaults: options.historyDefaults)
        pins = PinStore(defaults: options.historyDefaults, home: FileManager.default.homeDirectoryForCurrentUser)
        let window = BrowserWindow(
            contentRect: NSRect(origin: .zero, size: options.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // Small enough for two windows side by side on a 1024 pt screen (Window > Tile).
        window.minSize = NSSize(width: 500, height: 480)
        window.backgroundColor = Palette.current.pane.ns
        window.allowsOffscreen = options.uitest
        window.collectionBehavior.insert(.fullScreenPrimary)
        if options.uitest { window.isRestorable = false }
        super.init(window: window)
        window.delegate = self
        buildContent(in: window, options: options)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged(_:)),
                                               name: ThemeController.didChange, object: nil)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(filesChanged(_:)), name: OperationCenter.filesChanged, object: nil)
        center.addObserver(self, selector: #selector(clipboardChanged(_:)), name: FileClipboard.didChange, object: nil)
        center.addObserver(self, selector: #selector(clipboardChanged(_:)), name: NSApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(jobsChanged(_:)), name: OperationCenter.jobsChanged, object: nil)
        center.addObserver(self, selector: #selector(listOptionsChanged(_:)), name: ListOptions.didChange, object: nil)
        center.addObserver(self, selector: #selector(pinsChanged(_:)), name: PinsChanged.name, object: nil)
        center.addObserver(self, selector: #selector(volumesChanged(_:)), name: VolumeCenter.didChange, object: nil)
        center.addObserver(self, selector: #selector(serversChanged(_:)), name: VolumeCenter.serversChanged, object: nil)
        center.addObserver(self, selector: #selector(homeDataChanged(_:)), name: HomeData.didChange, object: nil)
        center.addObserver(self, selector: #selector(viewModeChanged(_:)), name: ViewCenter.didChange, object: nil)
        center.addObserver(self, selector: #selector(columnsChanged(_:)), name: ColumnCenter.didChange, object: nil)
        center.addObserver(self, selector: #selector(devicesChanged(_:)), name: DeviceCenter.didChange, object: nil)
        loadVolumes()
        updateTabStrip()
        header.sort = sortSpec
        applyViewMode()
        applyFolderOptions()
        // A restored tab comes back with its selection and scroll place; a folder from ff with its item.
        let first = tabs.active
        if first.selection.isEmpty && first.scrollRow == 0 { load() } else { load(restoring: (Set(first.selection), first.scrollRow)) }
        startWatching()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    private func buildContent(in window: NSWindow, options: Options) {
        let titleBar = TitleBarView(target: self, accentAction: #selector(chooseAccent(_:)))
        let toolbar = ToolbarView(target: self, back: #selector(goBack(_:)), forward: #selector(goForward(_:)),
                                  up: #selector(goUp(_:)), refresh: #selector(refresh(_:)))
        chassis = ChassisView(titleBar: titleBar, toolbar: toolbar)
        let address = toolbar.address
        address.dropdown = dropdown
        address.onNavigate = { [weak self] url in self?.navigate(to: url) }
        address.onEndEditing = { [weak self] move in
            switch move {
            case .list, .previous: self?.focus(.list)
            case .next: self?.focus(.sidebar)
            case .stay: break
            }
        }
        address.onEditingChanged = { [weak self] in
            self?.toolbar.needsDisplay = true
            self?.updateStatus()
        }
        address.onStatus = { [weak self] message in
            self?.statusMessage = message
            self?.toolbar.needsDisplay = true
            self?.updateStatus()
        }
        address.historyPaths = { [weak self] in self?.addressHistory.paths ?? [] }
        dropdown.onClose = { [weak self] in self?.toolbar.address.needsDisplay = true }
        toolbar.back.onHold = { [weak self] in self?.showHistoryList(back: true) }
        toolbar.forward.onHold = { [weak self] in self?.showHistoryList(back: false) }
        wireNavigationPane()
        wireTabStrip()
        wireHome()
        wireSearch()
        address.dropHost = self
        address.onMiddleClick = { [weak self] url in self?.openInNewTab(url, activate: false) }
        address.onServer = { [weak self] target in self?.connect(to: target) ?? false }
        address.onCommand = { [weak self] command in self?.runAddressCommand(command) ?? false }
        chassis.status.onToggleView = { [weak self] in
            guard let self else { return }
            self.chooseView(self.viewMode == .details ? .largeIcons : .details)
        }

        // The shown columns keep their widths; Name takes the rest of the list (fitColumns), so the
        // standard four always fit with no horizontal scroller.
        rebuildColumns(windowWidth: options.size.width)
        tableView.headerView = header
        tableView.cornerView = nil
        tableView.style = .plain
        tableView.rowHeight = ListOptions.compact ? ListMetrics.compactRowHeight : ListMetrics.rowHeight
        // Group headers scroll with their rows; a header click sorts or adds a sort key, never selects a column.
        tableView.floatsGroupRows = false
        tableView.allowsColumnSelection = false
        tableView.intercellSpacing = NSSize(width: ListMetrics.columnGap, height: 0)
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.focusRingType = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsTypeSelect = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.dataSource = self
        tableView.delegate = self
        tableView.listDelegate = self
        tableView.showsCheckboxes = ListOptions.checkboxes
        header.onToggleAll = { [weak self] in self?.toggleAllFromHeader() }
        header.onFilter = { [weak self] column, rect in self?.showFilter(column, below: rect) }
        header.onMenu = { [weak self] column in self?.headerMenu(column) }
        tableView.itemAtRow = { [weak self] row in self?.layout.item(atRow: row) }
        tableView.groupAtRow = { [weak self] row in self?.layout.group(atRow: row) }
        tableView.rowOfItem = { [weak self] item in self?.tableRow(ofItem: item) ?? item }
        grid.host = self
        grid.listDelegate = self
        grid.registerForDraggedTypes(droppableTypes)
        grid.setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: true)
        chassis.pane.gridScroll.documentView = grid
        chassis.sidePane.onClose = { ListOptions.sidePane = .none }
        chassis.sidePane.onEdit = { [weak self] url, tags, comment in self?.editMetadata(url, tags: tags, comment: comment) }
        chassis.sidePaneKind = ListOptions.sidePane
        toolbar.address.onClearToken = { [weak self] column in self?.clearFilter(column) }
        renamer.onCommit = { [weak self] name, move in self?.commitRename(name, move: move) ?? true }
        renamer.onEnd = { [weak self] in self?.renameEnded() }
        chassis.status.chip.onPress = { OperationCenter.shared.showProgress() }
        toolbar.commands = makeCommandBar()
        toolbar.groupEnds = [6, 8]
        tableView.setAccessibilityLabel("Files")
        tableView.registerForDraggedTypes(droppableTypes)
        tableView.draggingDestinationFeedbackStyle = .none
        dropTip.isHidden = true
        header.sort = sortSpec

        let scrollView = chassis.pane.scrollView
        scrollView.documentView = tableView
        // The clip narrows when always-visible scrollbars appear; refit Name whenever it changes.
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(listResized(_:)),
                                               name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(listScrolled(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        window.contentView = chassis
        window.initialFirstResponder = tableView
    }

    // MARK: Navigation

    func navigate(to folder: URL) {
        history.push(folder)
        load()
    }

    /// Goes to the folder with one item selected (Open file location).
    func navigate(to folder: URL, selecting key: String) {
        history.push(folder)
        load(restoring: ([key], 0))
    }

    /// The list empties (Home has no rows).
    func showEmptyList() {
        listing = []
        layout = ListLayout(items: [])
        entries = []
        entryKeys = []
        selection = ListSelection(count: 0)
        tableView.reloadData()
        grid.reloadData()
        updateFocusRow()
    }

    @objc func goBack(_ sender: Any?) { if history.goBack() != nil { load() } }
    @objc func goForward(_ sender: Any?) { if history.goForward() != nil { load() } }
    @objc func goUp(_ sender: Any?) { if history.goUp() != nil { load() } }
    /// Go > Home (Cmd+Shift+H) and Quick access's Home: the Home view.
    @objc func goHome(_ sender: Any?) { navigate(to: NavigationHistory.home) }
    @objc func goHomeFolder(_ sender: Any?) { navigate(to: FileManager.default.homeDirectoryForCurrentUser) }
    @objc func refresh(_ sender: Any?) { load() }

    /// Cmd+L, and Option+D (Anshul's Cmd+D): the crumbs become an editable path.
    @objc func focusAddressBar(_ sender: Any?) { toolbar.address.beginEditing() }

    /// F4, or the arrow at the right end of the address bar: recent locations.
    @objc func showAddressHistory(_ sender: Any?) { toolbar.address.toggleHistory() }

    /// Right-click the address bar > Copy Address: the folder as a file object and as text.
    @objc func copyAddress(_ sender: Any?) {
        let url = history.current
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setString(url.path, forType: .string)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    /// Copy Address as Text: the plain path, no quotes.
    @objc func copyAddressAsText(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(history.current.path, forType: .string)
    }

    /// Right-click or hold Back or Forward: the folders that way, nearest first; picking one jumps there.
    private func showHistoryList(back: Bool) {
        let id = back ? "back" : "forward"
        if let event = NSApp.currentEvent, dropdown.wasJustClosed(id, by: event) { return }
        if dropdown.isOpen(id) { dropdown.close(); return }
        let list = back ? history.backList : history.forwardList
        guard !list.isEmpty else { return }
        let rows = list.enumerated().map { i, url in DropdownRow(text: displayName(url), value: String(i + 1)) }
        let button = back ? toolbar.back : toolbar.forward
        let content = DropdownContent(style: .menu, title: back ? "Back history" : "Forward history", rows: rows, empty: "")
        dropdown.show(content, id: id, below: button.bounds, in: button) { [weak self] row in
            guard let self, let steps = Int(row.value) else { return }
            let moved = back ? self.history.goBack(steps: steps) : self.history.goForward(steps: steps)
            if moved != nil { self.load() }
        }
    }

    func displayName(_ url: URL) -> String {
        if NavigationHistory.isHome(url) { return "Home" }
        if RecycleBin.isTrash(url, home: FileManager.default.homeDirectoryForCurrentUser) { return "Recycle Bin" }
        return url.path == "/" ? (toolbar.address.volumes.first { $0.path == "/" }?.name ?? Breadcrumbs.rootTitle)
            : FileManager.default.displayName(atPath: url.path)
    }

    // MARK: Focus (F6, Tab, Shift+Tab): the address bar, the sidebar, the file list

    enum Pane: CaseIterable { case address, sidebar, list }

    private var focusedPane: Pane {
        if toolbar.address.isEditing { return .address }
        return window?.firstResponder === chassis.sidebar.outline ? .sidebar : .list
    }

    private func cycleFocus(forward: Bool) {
        let order = Pane.allCases
        let i = order.firstIndex(of: focusedPane) ?? 0
        focus(order[(i + (forward ? 1 : order.count - 1)) % order.count])
    }

    func focus(_ pane: Pane) {
        if pane != .address, toolbar.address.isEditing { toolbar.address.endEditing(focus: .stay) }
        switch pane {
        case .address: toolbar.address.beginEditing()
        case .sidebar: chassis.sidebar.takeKeyboardFocus()
        case .list: window?.makeFirstResponder(listView)
        }
    }

    /// The title bar's accent swatch: the picker opens under it (pressed again, it closes).
    @objc func chooseAccent(_ sender: Any?) {
        accentPicker.toggle(from: titleBar.accentButton)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // Option+Left, Option+Right (Back, Forward) and Option+Return (Properties) are the menus' keys; while
        // a name, the address or a search is typed they belong to the text instead.
        let editingText = window?.firstResponder is NSTextView
        return switch item.action {
        case #selector(goBack(_:)): history.canGoBack && !editingText
        case #selector(goForward(_:)): history.canGoForward && !editingText
        case #selector(showProperties(_:)) where editingText: false
        case #selector(goUp(_:)): history.canGoUp
        case #selector(saveSearch(_:)): isSearching
        case #selector(openFileLocation(_:)): isSearching && !selectedEntries.isEmpty
        default: validateFileItem(item)
        }
    }

    // MARK: Loading and sorting (off the main thread)

    /// `keepingState` is a refresh of the same folder: selection, scroll, focus and an open address
    /// edit stay as they are.
    /// `restoring` puts a tab's selection and scroll place back once its folder is listed.
    func load(keepingState: Bool = false, restoring: (select: Set<String>, row: Int)? = nil) {
        // A search is a place in the history: its results instead of the folder.
        if isSearching {
            if !keepingState {
                statusMessage = nil
                loadError = nil
                renamer.cancel()
                dropdown.close()
            }
            enterSearchMode()
            updateChrome()
            runSearch(keepingState: keepingState)
            if !keepingState { didNavigate() }
            return
        }
        if let saved = groupsBeforeSearch.removeValue(forKey: tabs.active.id) {
            group = saved
            collapsedGroups = []
        }
        if searchUIShown { leaveSearchMode() }
        if history.isHome {
            if !keepingState { showHome() }
            return
        }
        chassis.showsHome = false
        let folder = history.current
        if !keepingState {
            // A filter and folded groups belong to the folder on screen.
            filters.clearAll()
            collapsedGroups = []
        }
        let key = arrangeKey
        let hidden = ListOptions.showHidden
        let protected = ListOptions.folder.hideProtectedOSFiles
        listedWith = (hidden, protected)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let trash = RecycleBin.isTrash(folder, home: home)
        let cloud = CloudFolders.isCloud(folder, home: home)
        // A zip, or a folder inside one, lists from its central directory (Explorer's Compressed folder).
        let zip = ZipPath.split(folder) != nil
        isInZip = zip
        isTrashView = trash
        requestID += 1
        let id = requestID
        isLoading = true
        if !keepingState {
            loadError = nil
            statusMessage = nil
            pendingSelect = restoring.map(\.select)
            restoreRow = restoring?.row
            pendingRenamePath = nil
            renamer.cancel()
            dropdown.close()
            updateChrome()
        }
        let started = Date()
        // Tags, flags and custom icons are read again for what the list shows next (other windows keep theirs).
        ItemDecorCache.shared.clear(under: folder)
        // A newer load replaces this one: the old one stops at its next step instead of finishing unseen.
        loadTask?.cancel()
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result { () -> ([FileEntry], ListLayout) in
                let rows: [FileEntry]
                if zip {
                    let all = try ZipFolder.list(folder)
                    rows = hidden ? all : all.filter { !$0.isHidden }
                } else if trash {
                    // The Recycle Bin: Date deleted and Original location in the Date and Type columns.
                    let origins = TrashOrigins(defaults: .standard)
                    rows = RecycleBin.rows(try FolderListing.list(folder), original: { origins.original(of: $0) },
                                           deleted: { (try? $0.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate })
                } else {
                    rows = try FolderListing.list(folder, includeHidden: hidden, cloud: cloud, hideProtected: protected)
                }
                try Task.checkCancellation()
                return (rows, Self.arrange(rows, key))
            }
            if Task.isCancelled { return }
            let volume = VolumeCapacity.read(folder)
            await self?.finishLoad(result, volume: volume, id: id, key: key, folder: folder, started: started,
                                   keepingState: keepingState)
        }
    }

    /// Lists the folder again. `select` replaces the selection (paths); nil keeps it.
    func reloadContents(select: Set<String>? = nil) {
        if renamer.isActive {
            refreshAfterRename = true
            if let select { pendingSelect = select }
            return
        }
        pendingSelect = select ?? pendingSelect ?? Set(selectedKeys)
        scrollToPending = scrollToPending || (select?.isEmpty == false)
        load(keepingState: true)
    }

    private func loadVolumes() {
        let shared = VolumeCenter.shared
        if !shared.volumes.isEmpty {
            showVolumes(shared.volumes)
        } else {
            Task.detached(priority: .utility) { [weak self] in
                let volumes = VolumeCapacity.mounted()
                await self?.showVolumes(volumes)
            }
        }
    }

    func showVolumes(_ volumes: [VolumeCapacity]) {
        self.volumes = volumes
        chassis.sidebar.pane.setVolumes(volumes)
        toolbar.address.volumes = volumes
        chassis.sidebar.needsLayout = true
        if !volumes.isEmpty { applyPendingTree() }
        if !history.isHome, ListOptions.expandToCurrent { revealCurrentFolder(select: false) }
        updateWatches()
    }

    private func finishLoad(_ result: Result<([FileEntry], ListLayout), any Error>, volume: VolumeCapacity?, id: Int,
                            key: ArrangeKey, folder: URL, started: Date, keepingState: Bool) {
        guard id == requestID else { return }
        isLoading = false
        self.volume = volume
        let select = pendingSelect ?? []
        let scroll = scrollToPending
        pendingSelect = nil
        scrollToPending = false
        switch result {
        case .success(let (rows, arranged)):
            listing = rows
            arrangedWith = key
            show(arranged, selecting: select)
            if !keepingState { addressHistory.record(folder.path) }
        case .failure(let error):
            loadError = isTrashView && (error as NSError).code == NSFileReadNoPermissionError
                ? "Folio needs Full Disk Access to show the Recycle Bin (System Settings, Privacy & Security)"
                : error.localizedDescription
            listing = []
            arrangedWith = key
            show(ListLayout(items: []), selecting: [])
        }
        if !keepingState {
            if let row = restoreRow, row > 0, row < layout.rows.count {
                tableView.scroll(NSPoint(x: 0, y: tableView.rect(ofRow: row).minY - (header.frame.height)))
            } else if !select.isEmpty, let first = selection.rows.first {
                // Open file location, ff --reveal: the selected item is in view.
                scrollToItem(first)
            } else {
                tableView.scrollRowToVisible(0)
                grid.scroll(.zero)
            }
            restoreRow = nil
            didNavigate()
        } else if scroll, let first = selection.rows.first {
            scrollToItem(first)
        }
        if let path = pendingRenamePath {
            pendingRenamePath = nil
            if let row = entryKeys.firstIndex(of: path) {
                selection.click(row)
                applySelection(scrollTo: row)
                beginRename(row: row, batch: nil)
            }
        }
        if arrangeKey != key { rearrange() }
        window?.displayIfNeeded()
        let now = Date()
        perfLog.notice("""
            rows visible: \(self.entries.count, privacy: .public) items in \(folder.path, privacy: .public); \
            list+sort \(Int(now.timeIntervalSince(started) * 1000), privacy: .public) ms; \
            \(Int(now.timeIntervalSince(processStartDate) * 1000), privacy: .public) ms since launch
            """)
        if PerfTrace.isOn {
            PerfTrace.mark("rows", "items=\(entries.count) ms=\(PerfTrace.ms(since: started.timeIntervalSince1970)) "
                + "launch_ms=\(PerfTrace.ms(since: processStartDate.timeIntervalSince1970)) mb=\(PerfTrace.footprintMB) path=\(folder.path)")
        }
    }

    // MARK: Arranging: filters, sort and groups, off the main thread

    /// Everything the shown list depends on besides the folder's items.
    struct ArrangeKey: Equatable, Sendable {
        var filters: FilterSet
        var sort: SortSpec
        var group: GroupSpec?
        var collapsed: Set<String>
        /// Search results in relevance order: the order they are listed in.
        var relevance = false
    }

    var arrangeKey: ArrangeKey {
        ArrangeKey(filters: filters, sort: sortSpec, group: group, collapsed: collapsedGroups, relevance: isRelevanceOrder)
    }

    /// Filters, then groups (sorted inside) or a plain sort. Columns that need metadata (Dimensions,
    /// Tags...) read it for every item first, through the shared cache.
    nonisolated static func arrange(_ rows: [FileEntry], _ key: ArrangeKey) -> ListLayout {
        var layout = arrangeItems(rows, key)
        // The items' keys too, so the main thread does not resolve a path per item.
        layout.keys = FilePaths.itemKeys(layout.items.map(\.url))
        return layout
    }

    private nonisolated static func arrangeItems(_ rows: [FileEntry], _ key: ArrangeKey) -> ListLayout {
        let context = BucketContext()
        let wantsMeta = key.filters.columns.contains { $0.needsMetadata } || key.sort.terms.contains { $0.key.needsMetadata }
            || key.group?.key.needsMetadata == true
        if wantsMeta { MetadataCache.shared.fill(rows) }
        let meta: (FileEntry) -> ItemMetadata? = wantsMeta ? { MetadataCache.shared.cached($0) } : { _ in nil }
        let shown = key.filters.apply(rows, context: context, metadata: meta)
        if let group = key.group {
            return ListLayout(groups: GroupBuilder.build(shown, by: group, sort: key.sort, context: context, metadata: meta),
                              collapsed: key.collapsed)
        }
        if key.relevance { return ListLayout(items: shown) }
        return ListLayout(items: SortEngine.sort(shown, by: key.sort, metadata: meta))
    }

    /// The list again from the folder's items, after a sort, filter or Group by change; the selection stays.
    func rearrange() {
        guard !isLoading else { return } // the pending load arranges again when it lands
        let key = arrangeKey
        // Folding a group needs no new sort: the groups stay, only their rows change.
        if let old = arrangedWith, layout.isGrouped, old.filters == key.filters, old.sort == key.sort, old.group == key.group {
            arrangedWith = key
            show(ListLayout(groups: layout.groups, collapsed: key.collapsed), selecting: Set(selectedKeys))
            return
        }
        let rows = listing
        let selected = Set(selectedKeys)
        requestID += 1
        let id = requestID
        isResorting = true
        updateStatus()
        let started = PerfTrace.now
        Task.detached(priority: .userInitiated) { [weak self] in
            let arranged = Self.arrange(rows, key)
            await self?.finishRearrange(arranged, key: key, id: id, selecting: selected, started: started)
        }
    }

    private func finishRearrange(_ arranged: ListLayout, key: ArrangeKey, id: Int, selecting selected: Set<String>, started: Double) {
        guard id == requestID else { return }
        isResorting = false
        arrangedWith = key
        show(arranged, selecting: selected)
        if let first = selection.rows.first { scrollToItem(first) }
        if arrangeKey != key { rearrange() }
        if PerfTrace.isOn {
            window?.displayIfNeeded()
            PerfTrace.mark("arranged", "items=\(entries.count) ms=\(PerfTrace.ms(since: started)) searching=\(isSearching ? 1 : 0) "
                + "done=\(searchFinished ? 1 : 0) sort=\(key.sort.key.rawValue)")
        }
    }

    /// The selected items' keys, in list order.
    var selectedKeys: [String] { selection.rows.compactMap { entryKeys.indices.contains($0) ? entryKeys[$0] : nil } }

    func show(_ arranged: ListLayout, selecting selected: Set<String>) {
        layout = arranged
        entries = arranged.items
        entryKeys = arranged.keys ?? FilePaths.itemKeys(entries.map(\.url))
        dimmed = FileClipboard.dimmedPaths
        let rows = IndexSet(entries.indices.filter { selected.contains(entryKeys[$0]) })
        selection = ListSelection(count: entries.count)
        selection.adopt(rows, focus: rows.first)
        applyingSelection = true
        tableView.reloadData()
        // The grid is hidden in Details: it reloads when an icon view shows it (applyViewMode).
        if !viewMode.usesTable { grid.reloadData() }
        tableView.selectRowIndexes(tableRows(of: rows), byExtendingSelection: false)
        applyingSelection = false
        header.filtered = Set(filters.columns)
        updateFilterTokens()
        updateFocusRow()
        updateStatus()
        selectionDidChange()
    }

    // MARK: Items and rows

    /// The table row of an item (rows include group headers when grouped).
    func tableRow(ofItem i: Int) -> Int { layout.rowOfItem.indices.contains(i) ? layout.rowOfItem[i] : i }

    /// Ungrouped, an item's row is its index: the set as it is (Cmd+A in a big folder maps nothing).
    func tableRows(of items: IndexSet) -> IndexSet { layout.isGrouped ? IndexSet(items.map(tableRow(ofItem:))) : items }

    func scrollToItem(_ i: Int) {
        guard entries.indices.contains(i) else { return }
        if viewMode.usesTable { tableView.scrollRowToVisible(tableRow(ofItem: i)) } else { grid.scrollToItem(i) }
    }

    /// Where item `i` is on screen, in the list view's coordinates.
    func frameOfItem(_ i: Int) -> NSRect? {
        if viewMode.usesTable { return entries.indices.contains(i) ? tableView.rect(ofRow: tableRow(ofItem: i)) : nil }
        return grid.frame(ofItem: i)
    }

    /// Shows `selection` in the list (and scrolls to `scrollTo`, or the focus row, unless told not to).
    func applySelection(scrollTo: Int? = nil, scroll: Bool = true) {
        applyingSelection = true
        tableView.selectRowIndexes(tableRows(of: selection.rows), byExtendingSelection: false)
        applyingSelection = false
        grid.forEachVisibleCell { cell, i in cell.isSelected = selection.rows.contains(i) }
        if scroll, let row = scrollTo ?? selection.focus { scrollToItem(row) }
        updateFocusRow()
        updateStatus()
        selectionDidChange()
    }

    func updateFocusRow() {
        let focus = selection.focus
        tableView.enumerateAvailableRowViews { view, row in (view as? FolioRowView)?.isFocusRow = layout.item(atRow: row) == focus && focus != nil }
        grid.forEachVisibleCell { cell, i in cell.isFocusItem = i == focus }
    }

    func updateChrome() {
        let folder = history.current
        let name = displayName(folder)
        defer { updateSearchChrome() }
        // Folder Options > Display the full path in the title bar.
        let title = ListOptions.folder.fullPathInTitleBar && !history.isHome ? folder.path : name
        window?.title = title
        toolbar.back.isEnabled = history.canGoBack
        toolbar.forward.isEnabled = history.canGoForward
        toolbar.up.isEnabled = history.canGoUp
        toolbar.address.show(folder)
        toolbar.search.folderName = name
        if !isSearching {
            toolbar.address.searchTitle = nil
            if !toolbar.search.isEditing { toolbar.search.text = "" }
        }
        chassis.sidebar.pane.isHome = history.isHome
        chassis.sidebar.pane.currentPath = history.isHome ? "" : FilePaths.folderKey(folder)
        updateTabStrip()
        updateStatus()
    }

    var selectedEntries: [FileEntry] {
        selection.rows.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
    }

    func updateStatus() {
        let selection = SelectionSummary(entries, rows: self.selection.rows)
        let path = history.isHome ? "Home" : history.current.path
        if let statusMessage {
            chassis.status.countText = statusMessage
        } else if let loadError {
            chassis.status.countText = loadError
        } else if let searching = searchStatusText {
            chassis.status.countText = searching
        } else if isSearching {
            chassis.status.countText = StatusText.count(items: shownCount, selection: selection,
                                                        total: filters.isEmpty ? nil : listing.count)
        } else if history.isHome {
            chassis.status.countText = homeStatusText
        } else if isLoading {
            chassis.status.countText = "Loading " + (path as NSString).lastPathComponent
        } else {
            chassis.status.countText = StatusText.count(items: shownCount, selection: selection,
                                                        total: filters.isEmpty ? nil : listing.count)
        }
        // The HUD's readouts, in the status bar: count, selection, sort, free space, view.
        let listed = statusMessage == nil && loadError == nil && (searchError == nil || !isSearching)
            && !history.isHome && (isSearching || !isLoading)
        chassis.status.readout = !listed ? nil : StatusReadout.make(
            items: shownCount, total: filters.isEmpty ? nil : listing.count, selection: selection,
            sort: isRelevanceOrder ? nil : sortSpec, volume: volume, view: viewMode.title,
            searchingIn: isSearching && !searchFinished && searchError == nil ? searchScopeName : nil)
        if searchUIShown { updateSearchEmpty() }
        header.sort = sortSpec
        header.showsSort = !isRelevanceOrder
        let n = self.selection.rows.count
        header.checkState = ListOptions.checkboxes ? (all: n > 0 && n == entries.count, some: n > 0) : nil
        chassis.status.chipText = OperationCenter.shared.chipText
        updateCommandBar()
    }

    /// Items that pass the filters, collapsed groups' items included (the status bar counts these).
    var shownItems: [FileEntry] { layout.isGrouped ? layout.groups.flatMap(\.items) : entries }
    var shownCount: Int { layout.isGrouped ? layout.groups.reduce(0) { $0 + $1.items.count } : entries.count }

    @objc private func listScrolled(_ note: Notification) {
        // The scroll place is part of the session (written half a second after the last change).
        if !isLoading { sessionChanged() }
    }

    /// The rename box is down: a refresh that waited for it runs now.
    func renameEnded() {
        renameBatch = nil
        if refreshAfterRename {
            refreshAfterRename = false
            reloadContents(select: pendingSelect)
        }
    }

    // MARK: Notifications from file operations

    @objc private func filesChanged(_ note: Notification) {
        refreshTree(note)
        if isSearching {
            searchFilesChanged(note.userInfo?["folders"] as? Set<String>)
            return
        }
        guard !history.isHome else { return }
        // A periodic refresh while a job runs only concerns windows on its destination.
        let here = FilePaths.folderKey(history.current)
        if let folders = note.userInfo?["folders"] as? Set<String>, !folders.contains(here) { return }
        let mine = FilePaths.itemKeys(((note.userInfo?["select"] as? [String]) ?? []).map { URL(fileURLWithPath: $0) })
            .filter { FilePaths.parentKey(ofItemKey: $0) == here }
        reloadContents(select: mine.isEmpty ? nil : Set(mine))
    }

    @objc private func clipboardChanged(_ note: Notification) {
        let now = FileClipboard.dimmedPaths
        guard now != dimmed else { return }
        dimmed = now
        guard !entries.isEmpty else { return }
        reloadVisibleItems()
    }

    @objc private func jobsChanged(_ note: Notification) {
        chassis.status.chipText = OperationCenter.shared.chipText
    }

    @objc private func listOptionsChanged(_ note: Notification) {
        if chassis.sidebar.pane.tree.showHidden != ListOptions.showHidden {
            chassis.sidebar.pane.setShowHidden(ListOptions.showHidden)
        }
        let folderOptions = ListOptions.folder
        if listedWith != (ListOptions.showHidden, folderOptions.hideProtectedOSFiles) {
            listedWith = (ListOptions.showHidden, folderOptions.hideProtectedOSFiles)
            if isSearching { runSearch(keepingState: true) } else if !history.isHome { reloadContents() }
        }
        applyFolderOptions()
        applyNavigationPaneOptions()
        tableView.showsCheckboxes = ListOptions.checkboxes
        let rowH = ListOptions.compact ? ListMetrics.compactRowHeight : ListMetrics.rowHeight
        if tableView.rowHeight != rowH {
            tableView.rowHeight = rowH
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<layout.rows.count))
        }
        grid.compact = ListOptions.compact
        chassis.sidePaneKind = ListOptions.sidePane
        if !entries.isEmpty {
            tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<layout.rows.count), columnIndexes: IndexSet(tableView.tableColumns.indices))
            if !viewMode.usesTable { grid.reloadData() }
        }
        updateStatus()
        selectionDidChange()
    }

    @objc private func listResized(_ note: Notification) {
        fitColumns()
    }

    /// Name gets the list width the fixed columns leave, whatever the scroller style.
    func fitColumns() {
        let nameID = NSUserInterfaceItemIdentifier(SortKey.name.rawValue)
        guard !isFittingColumns, !isRebuildingColumns, let name = tableView.tableColumn(withIdentifier: nameID) else { return }
        let clip = chassis.pane.scrollView.contentView.bounds.width
        guard clip > 0 else { return }
        let others = tableView.tableColumns.filter { $0 !== name }.map { Double($0.width) }
        let width = CGFloat(ColumnFit.nameWidth(clipWidth: Double(clip), otherWidths: others, gap: Double(ListMetrics.columnGap),
                                                trailing: Double(ListMetrics.gutterRight), minimum: Double(Self.nameMinWidth)))
        guard abs(name.width - width) >= 0.5 else { return }
        isFittingColumns = true
        name.width = width
        isFittingColumns = false
    }

    @objc private func themeChanged(_ note: Notification) {
        window?.backgroundColor = Palette.current.pane.ns
        if let content = window?.contentView { refreshTheme(in: content) }
        tableView.enumerateAvailableRowViews { rowView, _ in refreshTheme(in: rowView) }
        header.needsDisplay = true
        grid.forEachVisibleCell { cell, _ in cell.needsDisplay = true }
        grid.reloadData()
    }

    // MARK: Opening

    /// One folder: go into it. Otherwise open files with their apps and folders in new windows.
    func open(rows: IndexSet) {
        let items = rows.map { entries[$0] }
        if let s = history.search, !items.isEmpty { recentSearches.record(s.text) }
        // A zip opens like a folder; Folder Options > Open each folder in its own window opens a window.
        if items.count == 1, let folder = items.first, folder.isFolder || ArchiveNaming.isBrowsable(folder.url) {
            if isSearching { window?.makeFirstResponder(listView) }
            if ListOptions.folder.openFoldersInNewWindow && !isInZip {
                (NSApp.delegate as? AppDelegate)?.openWindow(at: folder.url)
            } else {
                navigate(to: folder.url)
            }
            return
        }
        for item in items {
            if isInZip && !item.isFolder {
                openFromZip(item.url)
            } else if item.isFolder {
                (NSApp.delegate as? AppDelegate)?.openWindow(at: item.url)
            } else {
                openFile(item.url)
            }
        }
    }

    /// A file opens in its app and goes on Home's Recent files; a disk image is mounted and opened here.
    func openFile(_ url: URL) {
        if VolumeCenter.isDiskImage(url) {
            VolumeCenter.shared.mountImage(url, window: window) { [weak self] mount in self?.navigate(to: mount) }
            return
        }
        NSWorkspace.shared.open(url)
        HomeData.noteOpened(url, defaults: options.historyDefaults)
    }

    // MARK: Keyboard

    /// Window-level shortcuts, as macOS sees them after Anshul's Karabiner swap (docs/plan/MILESTONES.md
    /// key map). Returns true when the key was handled.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let tableFocused = window?.firstResponder === tableView || window?.firstResponder === grid
        let gridFocused = window?.firstResponder === grid
        let editingText = window?.firstResponder is NSTextView
        // An open crumb, « or Back list takes the arrows, Return and Esc (the address field drives its own).
        if dropdown.isOpen, !editingText {
            switch (event.keyCode, modifiers) {
            case (125, []): dropdown.moveHighlight(1); return true                  // Down
            case (126, []): dropdown.moveHighlight(-1); return true                 // Up
            case (36, []), (76, []): if !dropdown.pickHighlighted() { dropdown.close() }; return true
            case (53, []): dropdown.close(); return true                            // Esc
            default: break
            }
        }
        if handleTabKey(event, modifiers: modifiers, editingText: editingText) { return true }
        if handleViewKey(event, modifiers: modifiers, editingText: editingText) { return true }
        if gridFocused, handleGridArrow(event, modifiers: modifiers) { return true }
        switch (event.keyCode, modifiers) {
        case (126, .option): goUp(nil)                          // Option+Up (Cmd+Up after Karabiner)
        case (123, .option) where !editingText: goBack(nil)     // Option+Left
        case (124, .option) where !editingText: goForward(nil)  // Option+Right
        // Finder's keys still work; the Go menu shows Explorer's (Option+arrows).
        case (33, .command) where !editingText: goBack(nil)     // Cmd+[
        case (30, .command) where !editingText: goForward(nil)  // Cmd+]
        case (126, .command) where !editingText: goUp(nil)      // Cmd+Up
        case (123, .command) where !editingText: goBack(nil)    // Cmd+Left: what BTT's global rule sends for Anshul's physical Cmd+Left (Karabiner on)
        case (124, .command) where !editingText: goForward(nil) // Cmd+Right
        case (34, .command) where !editingText: showProperties(nil) // Cmd+I (the menu shows Option+Return)
        case (13, [.command, .shift]): window?.performClose(nil) // Cmd+Shift+W (the menu shows Option+F4)
        case (6, [.command, .shift]): redoOperation(nil)        // Cmd+Shift+Z (the menu shows Cmd+Y)
        case (2, .command) where tableFocused: moveToTrash(nil) // Cmd+D, Explorer's Ctrl+D
        case (2, .option): focusAddressBar(nil)                 // Option+D (Cmd+D after Karabiner)
        case (14, .command), (3, .command), (99, []): focusSearch(nil) // Explorer's Ctrl+E, Ctrl+F (Cmd after Karabiner), F3
        case (51, []) where !editingText: goBack(nil)           // Backspace, even with files selected
        case (36, []) where tableFocused, (76, []) where tableFocused:
            open(rows: selection.rows)                          // Return, Enter
        case (36, .option) where !editingText, (76, .option) where !editingText:
            showProperties(nil)                                 // Option+Return (Explorer's Alt+Enter)
        case (49, []) where tableFocused: toggleQuickLook(nil)  // Space: Quick Look
        case (109, .shift) where !editingText, (110, []) where !editingText:
            showContextMenuForSelection(nil)                    // Shift+F10, the Menu key
        case (125, []) where tableFocused, (125, .shift) where tableFocused:   // Down, Shift+Down
            moveSelection(.down, extend: modifiers == .shift)
        case (126, []) where tableFocused, (126, .shift) where tableFocused:   // Up, Shift+Up
            moveSelection(.up, extend: modifiers == .shift)
        case (115, []) where tableFocused, (115, .shift) where tableFocused:   // Home, Shift+Home
            moveSelection(.home, extend: modifiers == .shift)
        case (119, []) where tableFocused, (119, .shift) where tableFocused:   // End, Shift+End
            moveSelection(.end, extend: modifiers == .shift)
        case (116, []) where tableFocused, (116, .shift) where tableFocused:   // Page Up
            moveSelection(.pageUp(pageRows), extend: modifiers == .shift)
        case (121, []) where tableFocused, (121, .shift) where tableFocused:   // Page Down
            moveSelection(.pageDown(pageRows), extend: modifiers == .shift)
        case (125, .control) where tableFocused: moveFocus(.down)              // Ctrl+arrows: focus only
        case (126, .control) where tableFocused: moveFocus(.up)
        case (115, .control) where tableFocused: moveFocus(.home)
        case (119, .control) where tableFocused: moveFocus(.end)
        case (49, .control) where tableFocused:                                // Ctrl+Space toggles it
            selection.toggleFocused()
            applySelection()
        case (120, []) where tableFocused: renameSelection(nil)                // F2
        case (117, []) where tableFocused, (51, .option) where tableFocused, (51, .command) where tableFocused:
            moveToTrash(nil)                                                   // Delete (forward), Fn+Delete
        case (117, .shift) where tableFocused, (51, [.option, .shift]) where tableFocused,
             (51, [.command, .shift]) where tableFocused:
            deletePermanently(nil)                                             // Shift+Delete
        case (53, []) where !editingText && FileClipboard.hasPendingCut: FileClipboard.endCut() // Esc
        case (114, .control) where !editingText: copy(nil)                     // Ctrl+Insert
        case (114, .shift) where !editingText: paste(nil)                      // Shift+Insert
        case (103, []): toggleFullScreenWindow(nil)             // F11, when it reaches the app
        case (96, []), (15, .control), (15, .command): refresh(nil) // F5, Ctrl+R, Cmd+R (Explorer's Ctrl+R as Fn+R)
        case (118, []): showAddressHistory(nil)                 // F4
        case (118, .option): window?.performClose(nil)          // Option+F4 (Cmd+F4 after Karabiner)
        case (97, []): cycleFocus(forward: true)                // F6
        case (97, .shift): cycleFocus(forward: false)
        case (48, []) where !editingText: cycleFocus(forward: true)    // Tab
        case (48, .shift) where !editingText: cycleFocus(forward: false)
        default:
            // Folder Options > When typing into list view > Automatically type into the Search Box.
            return tableFocused && typeIntoSearchBox(event, modifiers: modifiers)
        }
        return true
    }

    private var pageRows: Int {
        if !viewMode.usesTable {
            let size = grid.itemSize
            let clip = chassis.pane.gridScroll.contentView.bounds
            let lines = grid.isHorizontal ? max(1, Int(clip.width / max(1, size.width)) - 1) : max(1, Int(clip.height / max(1, size.height)) - 1)
            return lines * grid.itemsPerLine
        }
        return max(1, Int(chassis.pane.scrollView.contentView.bounds.height / tableView.rowHeight) - 1)
    }

    func moveSelection(_ move: ListSelection.Move, extend: Bool) {
        selection.move(move, extend: extend)
        applySelection()
    }

    private func moveFocus(_ move: ListSelection.Move) {
        selection.moveFocus(move)
        if let f = selection.focus { scrollToItem(f) }
        updateFocusRow()
    }

    /// The icon grid's arrows: along a line by one, across lines by a line's worth (List flows down
    /// its columns, so there Up and Down step by one).
    private func handleGridArrow(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.isEmpty || modifiers == .shift else { return false }
        let extend = modifiers == .shift
        let line = grid.itemsPerLine
        let along: (back: UInt16, next: UInt16) = grid.isHorizontal ? (126, 125) : (123, 124)
        let across: (back: UInt16, next: UInt16) = grid.isHorizontal ? (123, 124) : (126, 125)
        switch event.keyCode {
        case along.back: moveSelection(.up, extend: extend)
        case along.next: moveSelection(.down, extend: extend)
        case across.back: moveSelection(selection.focus == nil ? .home : .pageUp(line), extend: extend)
        case across.next: moveSelection(selection.focus == nil ? .home : .pageDown(line), extend: extend)
        default: return false
        }
        return true
    }

    // MARK: Table data

    func numberOfRows(in tableView: NSTableView) -> Int { layout.rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { layout.group(atRow: row) != nil }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        layout.group(atRow: row) != nil ? ListMetrics.groupRowHeight : tableView.rowHeight
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { layout.item(atRow: row) != nil }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let view = tableView.makeView(withIdentifier: id, owner: self) as? FolioRowView
            ?? { let v = FolioRowView(); v.identifier = id; return v }()
        let item = layout.item(atRow: row)
        view.item = item.flatMap { entries.indices.contains($0) ? FolioRowView.Item(name: entries[$0].name, isFolder: entries[$0].isFolder) : nil }
        view.isFocusRow = item != nil && item == selection.focus
        view.isDropTarget = item != nil && item == dropTargetRow
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let g = layout.group(atRow: row) {
            let id = NSUserInterfaceItemIdentifier("groupHeader")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? GroupHeaderCellView
                ?? { let c = GroupHeaderCellView(); c.identifier = id; return c }()
            cell.title = layout.groups[g].bucket.title
            cell.count = layout.groups[g].items.count
            cell.collapsed = layout.isCollapsed(g)
            return cell
        }
        guard let tableColumn, let key = SortKey(rawValue: tableColumn.identifier.rawValue),
              let i = layout.item(atRow: row), entries.indices.contains(i) else { return nil }
        let entry = entries[i]
        let faded = dimmed.contains(entryKeys[i])
        if key == .name {
            let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NameCellView
                ?? { let c = NameCellView(); c.identifier = tableColumn.identifier; return c }()
            cell.entry = entry
            cell.isCut = faded
            cell.showsExtension = ListOptions.showExtensions
            cell.highlights = searchHighlights(entry.displayName(extensions: ListOptions.showExtensions))
            cell.showsCheckbox = self.tableView.showsCheckboxes
            decorate(cell, entry)
            cell.themeDidChange()
            return cell
        }
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? TextCellView
            ?? { let c = TextCellView(); c.identifier = tableColumn.identifier; return c }()
        cell.isCut = faded || entry.isHidden
        cell.mono = key.isMono
        cell.alignRight = key.alignsRight
        var meta: ItemMetadata?
        if key.needsMetadata {
            meta = MetadataCache.shared.cached(entry)
            if meta == nil { requestMetadata(entry) }
        }
        cell.pending = key.needsMetadata && meta == nil
        cell.text = ColumnValues.text(entry, key, meta)
        return cell
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard let i = layout.item(atRow: row), entries.indices.contains(i) else { return nil }
        return tableColumn == nil || tableColumn?.identifier.rawValue == SortKey.name.rawValue ? entries[i].name : nil
    }

    /// A header click (not a drag or a resize): sort on it; Shift+click adds it as another key.
    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard let key = SortKey(rawValue: tableColumn.identifier.rawValue) else { return }
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        // From relevance order the first click sorts on that column in its usual direction.
        if isRelevanceOrder { applySort(SortSpec(key: key, ascending: key.defaultAscending)); return }
        applySort(shift ? sortSpec.shiftClicking(key) : sortSpec.clicking(key))
    }

    /// Every sort change lands here: the header, the menus, the session.
    func applySort(_ spec: SortSpec) {
        guard spec != sortSpec || isRelevanceOrder else { return }
        sortSpec = spec
        header.sort = spec
        rearrange()
        sessionChanged()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // A change the window made itself (applySelection, show) is already in the model.
        guard !applyingSelection else { return }
        // Type to select and the table's own Select All change the rows behind the model's back.
        let items = layout.isGrouped ? IndexSet(tableView.selectedRowIndexes.compactMap { layout.item(atRow: $0) })
            : tableView.selectedRowIndexes
        if items != selection.rows {
            let focus = layout.item(atRow: tableView.selectedRow)
            selection.adopt(items, focus: focus)
            updateFocusRow()
            grid.forEachVisibleCell { cell, i in cell.isSelected = items.contains(i) }
            selectionDidChange()
            updateStatus()
        }
    }

    /// Dragging a divider gives or takes the space from Name; the width is kept for every folder.
    func tableViewColumnDidResize(_ notification: Notification) {
        guard !isRebuildingColumns, let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
              let key = ColumnID(rawValue: column.identifier.rawValue) else { return }
        guard key != .name else { return }
        let width = Double(column.width)
        ColumnCenter.shared.update({ $0.setWidth(width, of: key) }, post: false)
        fitColumns()
    }

    /// A header dragged to a new place: the order is kept for every folder.
    func tableViewColumnDidMove(_ notification: Notification) {
        guard !isRebuildingColumns else { return }
        // The search's own Folder column is not part of the saved set.
        let order = tableView.tableColumns.compactMap { ColumnID(rawValue: $0.identifier.rawValue) }
            .filter { ColumnCenter.shared.set.isVisible($0) }
        ColumnCenter.shared.update({ set in for (i, c) in order.enumerated() { set.move(c, to: i) } }, post: false)
        header.needsDisplay = true
    }

    /// A divider double-click: the widest value in the column (and its header).
    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
        guard tableView.tableColumns.indices.contains(column),
              let key = ColumnID(rawValue: tableView.tableColumns[column].identifier.rawValue) else { return 100 }
        return fitWidth(of: key)
    }

    // MARK: Columns

    /// Makes the table's columns match the shared column set (order, which are shown, widths).
    /// The shared columns, plus Folder while search results show (Explorer adds it to results).
    var shownColumns: [ColumnID] {
        let visible = ColumnCenter.shared.set.visible
        return isSearching && !visible.contains(.folder) ? visible + [.folder] : visible
    }

    func rebuildColumns(windowWidth: CGFloat? = nil) {
        let set = ColumnCenter.shared.set
        let shown = shownColumns
        let now = tableView.tableColumns.compactMap { ColumnID(rawValue: $0.identifier.rawValue) }
        if now == shown {
            for column in tableView.tableColumns {
                guard let key = ColumnID(rawValue: column.identifier.rawValue), key != .name else { continue }
                let w = CGFloat(set.width(of: key))
                if abs(column.width - w) > 0.5 { column.width = w }
            }
            fitColumns()
            return
        }
        isRebuildingColumns = true
        for column in tableView.tableColumns { tableView.removeTableColumn(column) }
        for key in shown {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key.rawValue))
            column.title = columnTitle(key)
            column.width = key == .name ? CGFloat(set.width(of: .name)) : CGFloat(set.width(of: key))
            column.minWidth = key == .name ? Self.nameMinWidth : 40
            column.resizingMask = .userResizingMask
            tableView.addTableColumn(column)
        }
        isRebuildingColumns = false
        if let windowWidth, let name = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(ColumnID.name.rawValue)) {
            let others = shown.filter { $0 != .name }.map { set.width(of: $0) }
            name.width = CGFloat(ColumnFit.nameWidth(clipWidth: Double(ChassisView.listWidth(windowWidth: windowWidth)), otherWidths: others,
                                                     gap: Double(ListMetrics.columnGap), trailing: Double(ListMetrics.gutterRight),
                                                     minimum: Double(Self.nameMinWidth)))
        }
        fitColumns()
        header.needsDisplay = true
        if !entries.isEmpty { tableView.reloadData() }
    }

    @objc func columnsChanged(_ note: Notification) {
        rebuildColumns()
        if arrangeKey != arrangedWith { rearrange() }
    }

    // MARK: Window

    func windowDidResize(_ notification: Notification) {
        (window as? BrowserWindow)?.placeTrafficLights()
        dropdown.close()
        sessionChanged()
    }

    func windowDidMove(_ notification: Notification) { sessionChanged() }

    func windowDidBecomeMain(_ notification: Notification) { sessionChanged() }

    func windowDidResignKey(_ notification: Notification) {
        dropdown.close()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        // Back from full screen the window may come back larger than its screen: it is fitted to it.
        if let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame, !options.uitest,
           window.frame.width > visible.width || window.frame.height > visible.height {
            let w = min(window.frame.width, visible.width), h = min(window.frame.height, visible.height)
            let x = min(max(window.frame.minX, visible.minX), visible.maxX - w)
            let y = min(max(window.frame.minY, visible.minY), visible.maxY - h)
            window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        }
        (window as? BrowserWindow)?.placeTrafficLights()
    }

    func windowWillClose(_ notification: Notification) {
        // A search in a closed window stops: the walk, Spotlight, its ticker and a pending arrange.
        searchEngine?.cancel()
        searchTicker?.invalidate()
        searchArrangeWork?.cancel()
        dropdown.close()
        renamer.end()
        // Cmd+Shift+T can bring back the tabs of a closed window too.
        if !tabs.isEmpty, let app = NSApp.delegate as? AppDelegate {
            stashActiveTab()
            for (i, tab) in tabs.tabs.enumerated() { app.closedTabs.push(tab, index: i) }
        }
        NotificationCenter.default.removeObserver(self)
        stopWatching()
        (NSApp.delegate as? AppDelegate)?.windowClosed(self)
    }
}
