import AppKit
import FolioCore

/// Sees key presses before the table does, so Option+arrows work wherever focus is.
final class BrowserWindow: NSWindow {
    /// `--uitest` places the window off every screen so a run never covers what is on the desktop.
    var allowsOffscreen = false

    override func sendEvent(_ event: NSEvent) {
        if let controller = windowController as? BrowserWindowController {
            if event.type == .keyDown, controller.handleKeyDown(event) { return }
            // Mouse buttons 4 and 5 go back and forward.
            if event.type == .otherMouseDown, event.buttonNumber == 3 { controller.goBack(nil); return }
            if event.type == .otherMouseDown, event.buttonNumber == 4 { controller.goForward(nil); return }
        }
        super.sendEvent(event)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        allowsOffscreen ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    /// Centres the window's own close, minimise and zoom buttons in D1's 44 pt title bar,
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
            let origin = NSPoint(x: 14 - (button.frame.width - 12) / 2 + CGFloat(i) * 20,
                                 y: (midY - button.frame.height / 2).rounded())
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }
}

/// One window showing one folder in a Details view, in the D1 control-room chassis.
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

    private(set) var history: NavigationHistory
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
    private(set) var sortSpec = SortSpec.standard
    private var isLoading = false
    private var isResorting = false
    private var loadError: String?
    /// The share button, for anchoring the share picker.
    var shareButton: ChromeButton?
    private var volume: VolumeCapacity?
    /// Bumped on every load or re-sort; results for an older value are dropped.
    private var requestID = 0
    private var isFittingColumns = false
    /// The one dropdown this window shows at a time (typeahead, history, crumb folders, Back list).
    let dropdown = Dropdown()
    private let addressHistory: AddressHistory
    /// "No such folder" after Enter on a bad address, until the next edit or navigation.
    var statusMessage: String?
    /// Quick access pins, shared by every window through the defaults.
    var pins: PinStore
    /// The drag badge ("Move to target") and the folder a drag is hovering to spring open.
    let dropTip = DropTipView()
    var springTarget: URL?
    var springTimer: Timer?
    /// The folder row lit under a drag (-1 for none); the list draws D1's feedback, not AppKit's.
    var dropTargetRow = -1 {
        didSet {
            guard dropTargetRow != oldValue else { return }
            tableView.enumerateAvailableRowViews { view, row in (view as? FolioRowView)?.isDropTarget = row == dropTargetRow }
        }
    }
    /// What Quick Look shows: the selection when it opened.
    var quickLookItems: [URL] = []

    let tableView = FolioTableView()
    let header = FolioHeaderView(frame: NSRect(x: 0, y: 0, width: 100,
                                                       height: ListMetrics.headerHeight + ListMetrics.listTopPad))
    private(set) var chassis: ChassisView!
    private var titleBar: TitleBarView { chassis.titleBar }
    var toolbar: ToolbarView { chassis.toolbar }

    private static let nameMinWidth: CGFloat = 120
    private static let columns: [(key: SortKey, title: String, width: CGFloat)] = [
        (.name, "Name", 320), (.modified, "Date modified", 150), (.kind, "Type", 132), (.size, "Size", 88),
    ]
    /// D1 shows dates as 2026-05-22 21:28 in local time, each date with its own daylight-saving rule.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// True once the listing and any re-sort have landed.
    var isIdle: Bool { !isLoading && !isResorting }

    init(folder: URL, options: Options = Options()) {
        history = NavigationHistory(start: folder)
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
        window.minSize = NSSize(width: 760, height: 480)
        window.backgroundColor = Palette.current.bg.ns
        window.allowsOffscreen = options.uitest
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
        loadVolumes()
        load()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    private func buildContent(in window: NSWindow, options: Options) {
        let titleBar = TitleBarView(target: self, accentAction: #selector(chooseAccent(_:)),
                                    themeAction: #selector(toggleTheme(_:)))
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
        chassis.sidebar.content.onNavigate = { [weak self] url in self?.navigate(to: url) }
        chassis.sidebar.content.places = pins.places
        chassis.sidebar.content.dropHost = self
        chassis.sidebar.content.onPinsEdited = { [weak self] edit in self?.editPins(edit) }
        chassis.sidebar.content.menuProvider = { [weak self] path, isPin in self?.sidebarMenu(path: path, isPin: isPin) }
        address.dropHost = self
        address.onCommand = { [weak self] command in self?.runAddressCommand(command) ?? false }
        chassis.rail.onJump = { [weak self] fraction in self?.jump(to: fraction) }

        // Date, Type and Size keep D1's widths; Name takes the rest of the list (fitColumns), so the
        // four columns always fit and there is never a horizontal scroller.
        let nameWidth = CGFloat(ColumnFit.nameWidth(
            clipWidth: Double(ChassisView.listWidth(windowWidth: options.size.width)),
            otherWidths: Self.columns.dropFirst().map { Double($0.width) },
            gap: Double(ListMetrics.columnGap), minimum: Double(Self.nameMinWidth)))
        for column in Self.columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.key.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.key == .name ? nameWidth : column.width
            tableColumn.minWidth = column.key == .name ? Self.nameMinWidth : 40
            tableColumn.sortDescriptorPrototype = descriptor(for: SortSpec(key: column.key, ascending: column.key.defaultAscending))
            tableView.addTableColumn(tableColumn)
        }
        tableView.headerView = header
        tableView.cornerView = nil
        tableView.style = .plain
        tableView.rowHeight = ListMetrics.rowHeight
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
        renamer.onCommit = { [weak self] name, move in self?.commitRename(name, move: move) ?? true }
        renamer.onEnd = { [weak self] in self?.renameEnded() }
        chassis.status.chip.onPress = { OperationCenter.shared.showProgress() }
        toolbar.commands = makeCommandBar()
        toolbar.groupEnds = [6, 8]
        tableView.sortDescriptors = [descriptor(for: sortSpec)]
        tableView.setAccessibilityLabel("Files")
        tableView.registerForDraggedTypes(droppableTypes)
        tableView.draggingDestinationFeedbackStyle = .none
        dropTip.isHidden = true
        if !options.uitest {
            // After the columns exist, so saved widths and order are applied to them.
            tableView.autosaveName = "DetailsColumnsD1"
            tableView.autosaveTableColumns = true
        }
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

    private func descriptor(for spec: SortSpec) -> NSSortDescriptor {
        NSSortDescriptor(key: spec.key.rawValue, ascending: spec.ascending)
    }

    // MARK: Navigation

    func navigate(to folder: URL) {
        history.push(folder)
        load()
    }

    @objc func goBack(_ sender: Any?) { if history.goBack() != nil { load() } }
    @objc func goForward(_ sender: Any?) { if history.goForward() != nil { load() } }
    @objc func goUp(_ sender: Any?) { if history.goUp() != nil { load() } }
    @objc func goHome(_ sender: Any?) { navigate(to: FileManager.default.homeDirectoryForCurrentUser) }
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
        url.path == "/" ? (toolbar.address.volumes.first { $0.path == "/" }?.name ?? Breadcrumbs.rootTitle)
            : FileManager.default.displayName(atPath: url.path)
    }

    // MARK: Focus (F6, Tab, Shift+Tab): the address bar, the sidebar, the file list

    enum Pane: CaseIterable { case address, sidebar, list }

    private var focusedPane: Pane {
        if toolbar.address.isEditing { return .address }
        return window?.firstResponder === chassis.sidebar.content ? .sidebar : .list
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
        case .sidebar: chassis.sidebar.content.takeKeyboardFocus()
        case .list: window?.makeFirstResponder(tableView)
        }
    }

    @objc func chooseAccent(_ sender: Any?) {
        guard let swatch = sender as? AccentSwatch else { return }
        ThemeController.shared.accent = swatch.accent
    }

    /// The title bar's sun or moon: switches to the other of dark and light.
    @objc func toggleTheme(_ sender: Any?) {
        ThemeController.shared.theme = Palette.current.appearance == .dark ? .light : .dark
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(goBack(_:)): history.canGoBack
        case #selector(goForward(_:)): history.canGoForward
        case #selector(goUp(_:)): history.canGoUp
        default: validateFileItem(item)
        }
    }

    // MARK: Loading and sorting (off the main thread)

    /// `keepingState` is a refresh of the same folder: selection, scroll, focus and an open address
    /// edit stay as they are.
    private func load(keepingState: Bool = false) {
        let folder = history.current
        let spec = sortSpec
        requestID += 1
        let id = requestID
        isLoading = true
        if !keepingState {
            loadError = nil
            statusMessage = nil
            pendingSelect = nil
            pendingRenamePath = nil
            renamer.cancel()
            dropdown.close()
            updateChrome()
        }
        let started = Date()
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result { try FolderListing.list(folder, sortedBy: spec) }
            let volume = VolumeCapacity.read(folder)
            await self?.finishLoad(result, volume: volume, id: id, spec: spec, folder: folder, started: started,
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
        pendingSelect = select ?? pendingSelect ?? Set(tableView.selectedRowIndexes.compactMap { entryKeys.indices.contains($0) ? entryKeys[$0] : nil })
        scrollToPending = scrollToPending || (select?.isEmpty == false)
        load(keepingState: true)
    }

    private func loadVolumes() {
        Task.detached(priority: .utility) { [weak self] in
            let volumes = VolumeCapacity.mounted()
            await self?.showVolumes(volumes)
        }
    }

    private func showVolumes(_ volumes: [VolumeCapacity]) {
        chassis.sidebar.content.volumes = volumes
        toolbar.address.volumes = volumes
        chassis.sidebar.needsLayout = true
    }

    private func finishLoad(_ result: Result<[FileEntry], any Error>, volume: VolumeCapacity?, id: Int,
                            spec: SortSpec, folder: URL, started: Date, keepingState: Bool) {
        guard id == requestID else { return }
        isLoading = false
        self.volume = volume
        let select = pendingSelect ?? []
        let scroll = scrollToPending
        pendingSelect = nil
        scrollToPending = false
        switch result {
        case .success(let list):
            show(list, selecting: select)
            if !keepingState { addressHistory.record(folder.path) }
        case .failure(let error):
            loadError = error.localizedDescription
            show([], selecting: [])
        }
        if !keepingState {
            tableView.scrollRowToVisible(0)
        } else if scroll, let first = tableView.selectedRowIndexes.first {
            tableView.scrollRowToVisible(first)
        }
        if let path = pendingRenamePath {
            pendingRenamePath = nil
            if let row = entryKeys.firstIndex(of: path) {
                selection.click(row)
                applySelection(scrollTo: row)
                beginRename(row: row, batch: nil)
            }
        }
        window?.displayIfNeeded()
        let now = Date()
        perfLog.notice("""
            rows visible: \(self.entries.count, privacy: .public) items in \(folder.path, privacy: .public); \
            list+sort \(Int(now.timeIntervalSince(started) * 1000), privacy: .public) ms; \
            \(Int(now.timeIntervalSince(processStartDate) * 1000), privacy: .public) ms since launch
            """)
        if spec != sortSpec { resort() }
    }

    private func resort() {
        guard !isLoading else { return } // the pending load re-sorts when it lands
        let spec = sortSpec
        let current = entries
        let selected = Set(tableView.selectedRowIndexes.map { entryKeys[$0] })
        requestID += 1
        let id = requestID
        isResorting = true
        updateStatus()
        Task.detached(priority: .userInitiated) { [weak self] in
            let sorted = SortEngine.sort(current, by: spec)
            await self?.finishResort(sorted, id: id, selecting: selected)
        }
    }

    private func finishResort(_ sorted: [FileEntry], id: Int, selecting selected: Set<String>) {
        guard id == requestID else { return }
        isResorting = false
        show(sorted, selecting: selected)
        if let first = tableView.selectedRowIndexes.first { tableView.scrollRowToVisible(first) }
    }

    private func show(_ list: [FileEntry], selecting selected: Set<String>) {
        entries = list
        entryKeys = list.map { FilePaths.itemKey($0.url) }
        dimmed = FileClipboard.dimmedPaths
        let rows = IndexSet(entries.indices.filter { selected.contains(entryKeys[$0]) })
        selection = ListSelection(count: entries.count)
        selection.adopt(rows, focus: rows.first)
        applyingSelection = true
        tableView.reloadData()
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
        applyingSelection = false
        updateFocusRow()
        updateStatus()
        updateVisibleRange()
    }

    /// Shows `selection` in the table (and scrolls to `scrollTo`, or the focus row, unless told not to).
    func applySelection(scrollTo: Int? = nil, scroll: Bool = true) {
        applyingSelection = true
        tableView.selectRowIndexes(selection.rows, byExtendingSelection: false)
        applyingSelection = false
        if scroll, let row = scrollTo ?? selection.focus { tableView.scrollRowToVisible(row) }
        updateFocusRow()
        updateStatus()
    }

    func updateFocusRow() {
        let focus = selection.focus
        tableView.enumerateAvailableRowViews { view, row in (view as? FolioRowView)?.isFocusRow = row == focus }
    }

    private func updateChrome() {
        let folder = history.current
        let name = displayName(folder)
        window?.title = name
        titleBar.folderName = name
        titleBar.folderPath = folder.path
        toolbar.back.isEnabled = history.canGoBack
        toolbar.forward.isEnabled = history.canGoForward
        toolbar.up.isEnabled = history.canGoUp
        toolbar.address.show(folder)
        toolbar.search.folderName = name
        chassis.sidebar.content.currentPath = folder.path
        updateStatus()
    }

    var selectedEntries: [FileEntry] {
        tableView.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
    }

    func updateStatus() {
        let selection = SelectionSummary(selectedEntries)
        let path = history.current.path
        if let statusMessage {
            chassis.status.countText = statusMessage
        } else if let loadError {
            chassis.status.countText = loadError
        } else if isLoading {
            chassis.status.countText = "Loading " + (path as NSString).lastPathComponent
        } else {
            chassis.status.countText = StatusText.count(items: entries.count, selection: selection)
        }
        chassis.status.ticker.items = Ticker.items(volume: volume, selection: selection, sort: sortSpec, path: path)
        let address = toolbar.address
        chassis.hud.segments = address.isEditing
            ? Hud.editingSegments(shown: address.matchCount.shown, total: address.matchCount.total, path: path, selection: selection)
            : Hud.segments(path: path, entries: entries, sort: sortSpec, selection: selection)
        chassis.rail.rowCount = entries.count
        chassis.rail.selected = tableView.selectedRowIndexes
        header.sort = sortSpec
        let n = tableView.selectedRowIndexes.count
        header.checkState = ListOptions.checkboxes ? (all: n > 0 && n == entries.count, some: n > 0) : nil
        chassis.status.chipText = OperationCenter.shared.chipText
        updateCommandBar()
    }

    @objc private func listScrolled(_ note: Notification) { updateVisibleRange() }

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
        // A periodic refresh while a job runs only concerns windows on its destination.
        let here = FilePaths.folderKey(history.current)
        if let folders = note.userInfo?["folders"] as? Set<String>, !folders.contains(here) { return }
        let mine = ((note.userInfo?["select"] as? [String]) ?? [])
            .map { FilePaths.itemKey(URL(fileURLWithPath: $0)) }
            .filter { FilePaths.parentKey(ofItemKey: $0) == here }
        reloadContents(select: mine.isEmpty ? nil : Set(mine))
    }

    @objc private func clipboardChanged(_ note: Notification) {
        let now = FileClipboard.dimmedPaths
        guard now != dimmed else { return }
        dimmed = now
        guard !entries.isEmpty else { return }
        tableView.reloadData(forRowIndexes: IndexSet(entries.indices), columnIndexes: IndexSet(tableView.tableColumns.indices))
    }

    @objc private func jobsChanged(_ note: Notification) {
        chassis.status.chipText = OperationCenter.shared.chipText
    }

    @objc private func listOptionsChanged(_ note: Notification) {
        tableView.showsCheckboxes = ListOptions.checkboxes
        if !entries.isEmpty {
            tableView.reloadData(forRowIndexes: IndexSet(entries.indices), columnIndexes: IndexSet(tableView.tableColumns.indices))
        }
        updateStatus()
    }

    @objc private func listResized(_ note: Notification) {
        fitColumns()
        updateVisibleRange()
    }

    /// Name gets the list width the fixed columns leave, whatever the scroller style.
    private func fitColumns() {
        let nameID = NSUserInterfaceItemIdentifier(SortKey.name.rawValue)
        guard !isFittingColumns, let name = tableView.tableColumn(withIdentifier: nameID) else { return }
        let clip = chassis.pane.scrollView.contentView.bounds.width
        guard clip > 0 else { return }
        let others = tableView.tableColumns.filter { $0 !== name }.map { Double($0.width) }
        let width = CGFloat(ColumnFit.nameWidth(clipWidth: Double(clip), otherWidths: others,
                                                gap: Double(ListMetrics.columnGap), minimum: Double(Self.nameMinWidth)))
        guard abs(name.width - width) >= 0.5 else { return }
        isFittingColumns = true
        name.width = width
        isFittingColumns = false
    }

    private func updateVisibleRange() {
        let clip = chassis.pane.scrollView.contentView
        let total = max(1, tableView.frame.height)
        chassis.rail.visibleRange = (Double(clip.bounds.minY / total), Double(clip.bounds.height / total))
    }

    private func jump(to fraction: Double) {
        guard !entries.isEmpty else { return }
        let row = min(entries.count - 1, Int(fraction * Double(entries.count)))
        tableView.scrollRowToVisible(row)
    }

    @objc private func themeChanged(_ note: Notification) {
        window?.backgroundColor = Palette.current.bg.ns
        if let content = window?.contentView { refreshTheme(in: content) }
        tableView.enumerateAvailableRowViews { rowView, _ in refreshTheme(in: rowView) }
        header.needsDisplay = true
    }

    // MARK: Opening

    /// One folder: go into it. Otherwise open files with their apps and folders in new windows.
    func open(rows: IndexSet) {
        let items = rows.map { entries[$0] }
        if items.count == 1, let folder = items.first, folder.isFolder {
            navigate(to: folder.url)
            return
        }
        for item in items {
            if item.isFolder {
                (NSApp.delegate as? AppDelegate)?.openWindow(at: item.url)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }
    }

    // MARK: Keyboard

    /// Window-level shortcuts, as macOS sees them after Anshul's Karabiner swap (docs/plan/MILESTONES.md
    /// key map). Returns true when the key was handled.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let tableFocused = window?.firstResponder === tableView
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
        switch (event.keyCode, modifiers) {
        case (126, .option): goUp(nil)                          // Option+Up (Cmd+Up after Karabiner)
        case (123, .option) where !editingText: goBack(nil)     // Option+Left
        case (124, .option) where !editingText: goForward(nil)  // Option+Right
        case (2, .option): focusAddressBar(nil)                 // Option+D (Cmd+D after Karabiner)
        case (51, []) where !editingText: goBack(nil)           // Backspace, even with files selected
        case (36, []) where tableFocused, (76, []) where tableFocused:
            open(rows: tableView.selectedRowIndexes)            // Return, Enter
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
        case (16, .command) where !editingText: redoOperation(nil)             // Cmd+Y (Explorer's Ctrl+Y)
        case (114, .control) where !editingText: copy(nil)                     // Ctrl+Insert
        case (114, .shift) where !editingText: paste(nil)                      // Shift+Insert
        case (96, []), (15, .control): refresh(nil)             // F5, Ctrl+R
        case (118, []): showAddressHistory(nil)                 // F4
        case (118, .option): window?.performClose(nil)          // Option+F4 (Cmd+F4 after Karabiner)
        case (97, []): cycleFocus(forward: true)                // F6
        case (97, .shift): cycleFocus(forward: false)
        case (48, []) where !editingText: cycleFocus(forward: true)    // Tab
        case (48, .shift) where !editingText: cycleFocus(forward: false)
        default: return false
        }
        return true
    }

    private var pageRows: Int {
        max(1, Int(chassis.pane.scrollView.contentView.bounds.height / ListMetrics.rowHeight) - 1)
    }

    private func moveSelection(_ move: ListSelection.Move, extend: Bool) {
        selection.move(move, extend: extend)
        applySelection()
    }

    private func moveFocus(_ move: ListSelection.Move) {
        selection.moveFocus(move)
        if let f = selection.focus { tableView.scrollRowToVisible(f) }
        updateFocusRow()
    }

    // MARK: Table data

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let view = tableView.makeView(withIdentifier: id, owner: self) as? FolioRowView
            ?? { let v = FolioRowView(); v.identifier = id; return v }()
        view.isFocusRow = row == selection.focus
        view.isDropTarget = row == dropTargetRow
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let key = SortKey(rawValue: tableColumn.identifier.rawValue) else { return nil }
        let entry = entries[row]
        if key == .name {
            let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NameCellView
                ?? { let c = NameCellView(); c.identifier = tableColumn.identifier; return c }()
            cell.entry = entry
            cell.isCut = dimmed.contains(entryKeys[row])
            cell.showsCheckbox = self.tableView.showsCheckboxes
            cell.themeDidChange()
            return cell
        }
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? TextCellView
            ?? { let c = TextCellView(); c.identifier = tableColumn.identifier; return c }()
        cell.isCut = dimmed.contains(entryKeys[row])
        switch key {
        case .modified:
            cell.mono = true
            cell.text = entry.modified.map(Self.dateFormatter.string(from:)) ?? ""
        case .kind:
            cell.text = entry.kind
        case .size:
            cell.mono = true
            cell.alignRight = true
            cell.text = entry.size.map(ByteText.kilobytes) ?? ""
        case .name:
            break
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        tableColumn == nil || tableColumn?.identifier.rawValue == SortKey.name.rawValue ? entries[row].name : nil
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let first = tableView.sortDescriptors.first,
              let key = first.key.flatMap(SortKey.init(rawValue:)) else { return }
        guard SortSpec(key: key, ascending: first.ascending) != sortSpec else { return } // our own update
        sortSpec = sortSpec.clicking(key)
        tableView.sortDescriptors = [descriptor(for: sortSpec)]
        header.sort = sortSpec
        resort()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Type to select and the table's own Select All change the rows behind the model's back.
        if !applyingSelection, tableView.selectedRowIndexes != selection.rows {
            let row = tableView.selectedRow
            selection.adopt(tableView.selectedRowIndexes, focus: row >= 0 ? row : nil)
            updateFocusRow()
        }
        updateStatus()
    }

    /// Dragging the Date, Type or Size divider gives or takes the space from Name.
    func tableViewColumnDidResize(_ notification: Notification) {
        let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn
        if column?.identifier.rawValue != SortKey.name.rawValue { fitColumns() }
    }

    // MARK: Window

    func windowDidResize(_ notification: Notification) {
        (window as? BrowserWindow)?.placeTrafficLights()
        dropdown.close()
    }

    func windowDidResignKey(_ notification: Notification) {
        dropdown.close()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        (window as? BrowserWindow)?.placeTrafficLights()
    }

    func windowWillClose(_ notification: Notification) {
        dropdown.close()
        renamer.end()
        NotificationCenter.default.removeObserver(self)
        (NSApp.delegate as? AppDelegate)?.windowClosed(self)
    }
}
