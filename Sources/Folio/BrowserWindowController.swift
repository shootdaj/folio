import AppKit
import FolioCore

/// Sees key presses before the table does, so Option+arrows work wherever focus is.
final class BrowserWindow: NSWindow {
    /// `--uitest` places the window off every screen so a run never covers what is on the desktop.
    var allowsOffscreen = false

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let controller = windowController as? BrowserWindowController,
           controller.handleKeyDown(event) {
            return
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
    }

    private var history: NavigationHistory
    private(set) var entries: [FileEntry] = []
    private(set) var sortSpec = SortSpec.standard
    private var isLoading = false
    private var isResorting = false
    private var loadError: String?
    private var volume: VolumeCapacity?
    /// Bumped on every load or re-sort; results for an older value are dropped.
    private var requestID = 0

    let tableView = FolioTableView()
    private let header = FolioHeaderView(frame: NSRect(x: 0, y: 0, width: 100,
                                                       height: ListMetrics.headerHeight + ListMetrics.listTopPad))
    private var chassis: ChassisView!
    private var titleBar: TitleBarView { chassis.titleBar }
    private var toolbar: ToolbarView { chassis.toolbar }

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
        toolbar.address.onNavigate = { [weak self] url in self?.navigate(to: url) }
        toolbar.address.onEndEditing = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.tableView)
        }
        chassis.sidebar.content.onNavigate = { [weak self] url in self?.navigate(to: url) }
        chassis.sidebar.content.places = QuickAccess.places(home: FileManager.default.homeDirectoryForCurrentUser)
        chassis.rail.onJump = { [weak self] fraction in self?.jump(to: fraction) }

        // Name fills the pane at the starting size; the others keep D1's widths. Columns never
        // stretch with the window afterwards (Explorer), and saved widths win when there are some.
        let listWidth = ChassisView.listWidth(windowWidth: options.size.width)
        let fixed = Self.columns.dropFirst().reduce(0) { $0 + $1.width }
        let nameWidth = max(200, listWidth - ListMetrics.columnGap / 2 - fixed
                            - ListMetrics.columnGap * CGFloat(Self.columns.count))
        for column in Self.columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.key.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.key == .name ? nameWidth : column.width
            tableColumn.minWidth = 40
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
        tableView.target = self
        tableView.doubleAction = #selector(openClickedRow(_:))
        tableView.sortDescriptors = [descriptor(for: sortSpec)]
        tableView.setAccessibilityLabel("Files")
        if !options.uitest {
            // After the columns exist, so saved widths and order are applied to them.
            tableView.autosaveName = "DetailsColumnsD1"
            tableView.autosaveTableColumns = true
        }
        header.sort = sortSpec

        let scrollView = chassis.pane.scrollView
        scrollView.documentView = tableView
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
        default: true
        }
    }

    // MARK: Loading and sorting (off the main thread)

    private func load() {
        let folder = history.current
        let spec = sortSpec
        requestID += 1
        let id = requestID
        isLoading = true
        loadError = nil
        updateChrome()
        let started = Date()
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result { try FolderListing.list(folder, sortedBy: spec) }
            let volume = VolumeCapacity.read(folder)
            await self?.finishLoad(result, volume: volume, id: id, spec: spec, folder: folder, started: started)
        }
    }

    private func loadVolumes() {
        Task.detached(priority: .utility) { [weak self] in
            let volumes = VolumeCapacity.mounted()
            await self?.showVolumes(volumes)
        }
    }

    private func showVolumes(_ volumes: [VolumeCapacity]) {
        chassis.sidebar.content.volumes = volumes
        chassis.sidebar.needsLayout = true
    }

    private func finishLoad(_ result: Result<[FileEntry], any Error>, volume: VolumeCapacity?, id: Int,
                            spec: SortSpec, folder: URL, started: Date) {
        guard id == requestID else { return }
        isLoading = false
        self.volume = volume
        switch result {
        case .success(let list):
            show(list, selecting: [])
        case .failure(let error):
            loadError = error.localizedDescription
            show([], selecting: [])
        }
        tableView.scrollRowToVisible(0)
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
        let selected = Set(tableView.selectedRowIndexes.map { entries[$0].url })
        requestID += 1
        let id = requestID
        isResorting = true
        updateStatus()
        Task.detached(priority: .userInitiated) { [weak self] in
            let sorted = SortEngine.sort(current, by: spec)
            await self?.finishResort(sorted, id: id, selecting: selected)
        }
    }

    private func finishResort(_ sorted: [FileEntry], id: Int, selecting selected: Set<URL>) {
        guard id == requestID else { return }
        isResorting = false
        show(sorted, selecting: selected)
        if let first = tableView.selectedRowIndexes.first { tableView.scrollRowToVisible(first) }
    }

    private func show(_ list: [FileEntry], selecting selected: Set<URL>) {
        entries = list
        tableView.reloadData()
        if !selected.isEmpty {
            let rows = IndexSet(entries.indices.filter { selected.contains(entries[$0].url) })
            tableView.selectRowIndexes(rows, byExtendingSelection: false)
        }
        updateStatus()
        updateVisibleRange()
    }

    private func updateChrome() {
        let folder = history.current
        let name = folder.path == "/" ? Breadcrumbs.rootTitle : FileManager.default.displayName(atPath: folder.path)
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

    private var selectedEntries: [FileEntry] {
        tableView.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
    }

    private func updateStatus() {
        let selection = SelectionSummary(selectedEntries)
        let path = history.current.path
        if let loadError {
            chassis.status.countText = loadError
        } else if isLoading {
            chassis.status.countText = "Loading " + (path as NSString).lastPathComponent
        } else {
            chassis.status.countText = StatusText.count(items: entries.count, selection: selection)
        }
        chassis.status.ticker.items = Ticker.items(volume: volume, selection: selection, sort: sortSpec, path: path)
        chassis.hud.segments = Hud.segments(path: path, entries: entries, sort: sortSpec, selection: selection)
        chassis.rail.rowCount = entries.count
        chassis.rail.selected = tableView.selectedRowIndexes
        header.sort = sortSpec
    }

    @objc private func listScrolled(_ note: Notification) { updateVisibleRange() }

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

    @objc private func openClickedRow(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0 else { return } // double-click on the header or empty space
        let selection = tableView.selectedRowIndexes
        open(rows: selection.contains(row) ? selection : IndexSet(integer: row))
    }

    /// One folder: go into it. Otherwise open files with their apps and folders in new windows.
    private func open(rows: IndexSet) {
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

    /// Window-level shortcuts. Returns true when the key was handled.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let tableFocused = window?.firstResponder === tableView
        let editingText = window?.firstResponder is NSTextView
        switch (event.keyCode, modifiers) {
        case (126, .option): goUp(nil)                          // Option+Up
        case (123, .option) where !editingText: goBack(nil)     // Option+Left
        case (124, .option) where !editingText: goForward(nil)  // Option+Right
        case (2, .option): focusAddressBar(nil)                 // Option+D (Cmd+D after Karabiner)
        case (51, []) where tableFocused: goBack(nil)           // Backspace
        case (36, []) where tableFocused, (76, []) where tableFocused:
            open(rows: tableView.selectedRowIndexes)            // Return, Enter
        case (115, []) where tableFocused: selectRow(0)         // Home
        case (119, []) where tableFocused: selectRow(entries.count - 1) // End
        default: return false
        }
        return true
    }

    private func selectRow(_ row: Int) {
        guard entries.indices.contains(row) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    // MARK: Table data

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("row")
        if let view = tableView.makeView(withIdentifier: id, owner: self) as? FolioRowView { return view }
        let view = FolioRowView()
        view.identifier = id
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let key = SortKey(rawValue: tableColumn.identifier.rawValue) else { return nil }
        let entry = entries[row]
        if key == .name {
            let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NameCellView
                ?? { let c = NameCellView(); c.identifier = tableColumn.identifier; return c }()
            cell.entry = entry
            cell.themeDidChange()
            return cell
        }
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? TextCellView
            ?? { let c = TextCellView(); c.identifier = tableColumn.identifier; return c }()
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
        updateStatus()
    }

    // MARK: Window

    func windowDidResize(_ notification: Notification) {
        (window as? BrowserWindow)?.placeTrafficLights()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        (window as? BrowserWindow)?.placeTrafficLights()
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        (NSApp.delegate as? AppDelegate)?.windowClosed(self)
    }
}
