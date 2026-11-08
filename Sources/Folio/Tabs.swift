import AppKit
import FolioCore

/// Milestone 5 in the window: tabs (new, close, reopen, cycle, Cmd+number, middle-click, duplicate,
/// close others and to the right, reorder, tear out, merge, drop on a tab), each with its own history,
/// sort and selection; the session they are saved in.
extension BrowserWindowController {
    // MARK: The strip

    func wireTabStrip() {
        let strip = chassis.tabStrip
        strip.onSelect = { [weak self] i in self?.activateTab(i) }
        strip.onClose = { [weak self] i in self?.closeTab(at: i) }
        strip.onNew = { [weak self] in self?.newTab(nil) }
        strip.onMove = { [weak self] from, to in self?.moveTab(from: from, to: to) }
        strip.menuProvider = { [weak self] i in self?.tabMenu(i) }
        strip.onTearOut = { [weak self] id, point in self?.tearOut(id, at: point) }
        strip.onReceive = { [weak self] number, id, index in self?.receiveTab(fromWindow: number, id: id, at: index) }
        strip.dropHost = self
    }

    func updateTabStrip() {
        updateWatches()
        let items = tabs.tabs.map { tab in
            var item = TabItem(id: tab.id, title: tab.history.search.map { s in
                                   "Search Results in " + (s.everywhere ? PlaceNames.thisComputer
                                    : tab.history.isSpecial ? PlaceNames.title(.home) : displayName(tab.current))
                               } ?? tabTitle(tab), page: tab.history.special,
                               folder: tab.history.isSpecial ? nil : tab.current)
            item.isSearch = tab.history.search != nil
            return item
        }
        chassis.tabStrip.items = items
        chassis.tabStrip.activeIndex = tabs.activeIndex
        chassis.setTabRowVisible(items.count >= 2)
    }

    /// A folder tab's title: its name, or with Folder Options > Display the full path in the title bar,
    /// its full path (the tabs are the title bar now).
    private func tabTitle(_ tab: BrowserTab) -> String {
        ListOptions.folder.fullPathInTitleBar && !tab.history.isSpecial ? tab.current.path : displayName(tab.current)
    }

    /// The shown tab's selection and scroll place, kept for when it is shown again.
    func stashActiveTab() {
        // While the folder is still being read the list is empty: the tab keeps what it had.
        guard !tabs.isEmpty, !history.isSpecial, !isLoading else { return }
        tabs.active.selection = selectedKeys
        let clip = chassis.pane.scrollView.contentView.bounds
        tabs.active.scrollRow = max(0, tableView.row(at: NSPoint(x: 1, y: clip.minY + header.frame.height + 1)))
    }

    /// Shows the active tab: its sort on the header, its folder listed, its selection and scroll back.
    func showActiveTab() {
        let tab = tabs.active
        header.sort = tab.sort
        load(restoring: (Set(tab.selection), tab.scrollRow))
        updateTabStrip()
        sessionChanged()
    }

    func activateTab(_ index: Int) {
        guard index != tabs.activeIndex, tabs.tabs.indices.contains(index) else { return }
        stashActiveTab()
        tabs.select(index)
        showActiveTab()
    }

    // MARK: Commands

    /// Cmd+T: a new tab on the folder this tab shows.
    @objc func newTab(_ sender: Any?) {
        stashActiveTab()
        var tab = BrowserTab(history: NavigationHistory(start: history.current), sort: sortSpec)
        tab.group = group
        tabs.append(tab)
        showActiveTab()
    }

    /// Open in new tab and middle-click: a tab next to this one, in the background unless `activate`.
    func openInNewTab(_ url: URL, activate: Bool) {
        if activate { stashActiveTab() }
        var tab = BrowserTab(folder: url, sort: sortSpec)
        tab.group = group
        tabs.openNext(tab, activate: activate)
        if activate { showActiveTab() } else { updateTabStrip(); sessionChanged() }
    }

    @objc func openSelectionInNewTab(_ sender: Any?) {
        for entry in selectedEntries where entry.isFolder { openInNewTab(entry.url, activate: false) }
    }

    /// Cmd+W: closes the shown tab; the last one closes the window.
    @objc func closeTab(_ sender: Any?) { closeTab(at: tabs.activeIndex) }

    func closeTab(at index: Int) {
        guard tabs.tabs.indices.contains(index) else { return }
        guard tabs.count > 1 else {
            window?.performClose(nil)
            return
        }
        let wasActive = index == tabs.activeIndex
        if wasActive { stashActiveTab() }
        if let closed = tabs.close(at: index) { appDelegate?.closedTabs.push(closed, index: index) }
        if wasActive { showActiveTab() } else { updateTabStrip(); sessionChanged() }
    }

    /// Cmd+Shift+T: the last closed tab, back where it was, with its history.
    @objc func reopenClosedTab(_ sender: Any?) {
        guard let entry = appDelegate?.closedTabs.pop() else { NSSound.beep(); return }
        stashActiveTab()
        tabs.insert(entry.tab, at: entry.index, activate: true)
        showActiveTab()
    }

    @objc func nextTab(_ sender: Any?) { cycleTab(forward: true) }
    @objc func previousTab(_ sender: Any?) { cycleTab(forward: false) }

    func cycleTab(forward: Bool) {
        guard tabs.count > 1 else { return }
        stashActiveTab()
        tabs.cycle(forward: forward)
        showActiveTab()
    }

    func selectTabNumber(_ n: Int) {
        var probe = tabs
        guard probe.selectNumber(n), probe.activeIndex != tabs.activeIndex else { return }
        activateTab(probe.activeIndex)
    }

    func moveTab(from: Int, to: Int) {
        tabs.move(from: from, to: to)
        updateTabStrip()
        sessionChanged()
    }

    /// Ctrl+Tab, Ctrl+Shift+Tab (Anshul's Fn+Tab arrives as Ctrl+Tab), Cmd+1 to Cmd+9.
    func handleTabKey(_ event: NSEvent, modifiers: NSEvent.ModifierFlags, editingText: Bool) -> Bool {
        switch (event.keyCode, modifiers) {
        case (48, .control): cycleTab(forward: true)
        case (48, [.control, .shift]): cycleTab(forward: false)
        case (14, [.control, .shift]): expandToCurrentFolder(nil)          // Ctrl+Shift+E
        default:
            let numbers: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
            guard modifiers == .command, let n = numbers[event.keyCode] else { return false }
            selectTabNumber(n)
        }
        return true
    }

    // MARK: The tab menu

    func tabMenu(_ i: Int) -> NSMenu {
        let menu = NSMenu(title: "Tab")
        menu.font = Typeface.menu()
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
            item.target = self
            item.tag = i
            menu.addItem(item)
        }
        add("New tab", #selector(newTab(_:)))
        add("Duplicate tab", #selector(duplicateTab(_:)))
        add("Move to new window", #selector(moveTabToNewWindow(_:)), enabled: tabs.count > 1)
        menu.addItem(.separator())
        add("Close tab", #selector(closeTabFromMenu(_:)))
        add("Close other tabs", #selector(closeOtherTabs(_:)), enabled: tabs.count > 1)
        add("Close tabs to the right", #selector(closeTabsToTheRight(_:)), enabled: i < tabs.count - 1)
        menu.addItem(.separator())
        add("Reopen closed tab", #selector(reopenClosedTab(_:)), enabled: (appDelegate?.closedTabs.count ?? 0) > 0)
        return menu
    }

    private func tabIndex(_ sender: Any?) -> Int { (sender as? NSMenuItem)?.tag ?? tabs.activeIndex }

    @objc func duplicateTab(_ sender: Any?) {
        stashActiveTab()
        tabs.duplicate(at: tabIndex(sender))
        showActiveTab()
    }

    @objc func closeTabFromMenu(_ sender: Any?) { closeTab(at: tabIndex(sender)) }

    @objc func closeOtherTabs(_ sender: Any?) {
        let keep = tabIndex(sender)
        let changes = keep != tabs.activeIndex
        stashActiveTab()
        let closed = tabs.closeOthers(keeping: keep)
        for tab in closed { appDelegate?.closedTabs.push(tab, index: 1) }
        if changes { showActiveTab() } else { updateTabStrip(); sessionChanged() }
    }

    @objc func closeTabsToTheRight(_ sender: Any?) {
        let at = tabIndex(sender)
        let before = tabs.active.id
        stashActiveTab()
        let closed = tabs.closeToTheRight(of: at)
        for (n, tab) in closed.enumerated() { appDelegate?.closedTabs.push(tab, index: at + 1 + n) }
        if tabs.active.id != before { showActiveTab() } else { updateTabStrip(); sessionChanged() }
    }

    @objc func moveTabToNewWindow(_ sender: Any?) {
        let i = tabIndex(sender)
        guard tabs.count > 1, tabs.tabs.indices.contains(i) else { return }
        let origin = window.map { NSPoint(x: $0.frame.minX + 40, y: $0.frame.maxY - 40) }
        tearOut(tabs.tabs[i].id, at: origin)
    }

    // MARK: Tear out and merge

    /// Takes a tab out of this window (the window closes when it was the last).
    func detachTab(_ id: UUID) -> BrowserTab? {
        let wasActive = tabs.active.id == id
        if wasActive { stashActiveTab() }
        guard let tab = tabs.remove(id: id) else { return nil }
        if tabs.isEmpty {
            window?.close()
        } else if wasActive {
            showActiveTab()
        } else {
            updateTabStrip()
            sessionChanged()
        }
        return tab
    }

    /// A tab let go off every strip: its own window there, the strip under the pointer.
    func tearOut(_ id: UUID, at screenPoint: NSPoint?) {
        guard tabs.count > 1, let tab = detachTab(id) else { return }
        appDelegate?.openWindow(with: [tab], active: 0, near: screenPoint, size: window?.frame.size)
    }

    /// A tab dropped on this strip, from this window (a reorder) or another (a merge).
    func receiveTab(fromWindow number: Int, id: UUID, at index: Int) {
        if number == window?.windowNumber {
            guard let from = tabs.index(of: id) else { return }
            moveTab(from: from, to: from < index ? index - 1 : index)
            return
        }
        guard let source = appDelegate?.controller(windowNumber: number), let tab = source.detachTab(id) else { return }
        stashActiveTab()
        tabs.insert(tab, at: index, activate: true)
        showActiveTab()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Window > Merge all windows: every other window's tabs come here, after these.
    @objc func mergeAllWindows(_ sender: Any?) {
        guard let app = appDelegate else { return }
        stashActiveTab()
        for other in app.browserControllers where other !== self {
            other.stashActiveTab()
            for tab in other.tabs.tabs {
                _ = other.tabs.remove(id: tab.id)
                tabs.insert(tab, at: tabs.count, activate: false)
            }
            other.window?.close()
        }
        updateTabStrip()
        sessionChanged()
    }

    var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    // MARK: Session

    func windowSession() -> WindowSession? {
        guard let window, !tabs.isEmpty else { return nil }
        stashActiveTab()
        let f = window.frame
        let display = window.screen.map { s in
            SessionDisplay(name: s.localizedName, frame: SessionFrame(x: s.frame.minX, y: s.frame.minY,
                                                                      width: s.frame.width, height: s.frame.height))
        }
        return WindowSession(frame: SessionFrame(x: f.minX, y: f.minY, width: f.width, height: f.height), display: display,
                             tabs: tabs.tabs.map(TabSession.init), active: tabs.activeIndex,
                             expandedFolders: pendingTreeFolders ?? chassis.sidebar.pane.expandedFolders())
    }

    /// The tree's open folders from the session, opened once the drives are known.
    func restoreTree(_ folders: [String]) {
        guard !folders.isEmpty else { return }
        pendingTreeFolders = folders
        if !volumes.isEmpty { applyPendingTree() }
    }

    func applyPendingTree() {
        guard let folders = pendingTreeFolders else { return }
        pendingTreeFolders = nil
        chassis.sidebar.pane.expandFoldersInBackground(folders)
    }

    func sessionChanged() {
        guard !options.uitest else { return }
        appDelegate?.scheduleSessionSave()
    }

    /// After every move to another folder (or Home): the tree follows, the tab's title, the session.
    func didNavigate() {
        if !history.isSpecial, ListOptions.expandToCurrent { revealCurrentFolder(select: false) }
        updateTabStrip()
        sessionChanged()
        updateWatches()
        SuggestionsCenter.shared.setViewing(self, history.isSuggestions && !isSearching)
    }
}

// MARK: - The navigation pane

extension BrowserWindowController {
    func wireNavigationPane() {
        let pane = chassis.sidebar.pane
        pane.tree.showHidden = ListOptions.navPaneShowHidden
        pane.setPlaces(pins.places)
        pane.onNavigate = { [weak self] url in self?.navigate(to: url) }
        pane.onHome = { [weak self] in self?.goHome(nil) }
        pane.onPage = { [weak self] place in self?.navigate(to: place.url) }
        pane.onOpenInNewTab = { [weak self] url in self?.openInNewTab(url, activate: false) }
        pane.onPinsEdited = { [weak self] edit in self?.editPins(edit) }
        pane.onEject = { [weak self] v in self?.ejectVolume(v) }
        pane.onConnect = { [weak self] in self?.connectToServer(nil) }
        pane.onBrowse = { VolumeCenter.shared.browse() }
        pane.onServer = { [weak self] name in
            let host = name.contains(".") ? name : name + ".local"
            if let target = ServerAddress.parse("smb://" + host) { _ = self?.connect(to: target) }
        }
        pane.onRenameVolume = { [weak self] v in VolumeCenter.shared.rename(v, window: self?.window) }
        pane.onDevice = { [weak self] in self?.openImageCapture(nil) }
        pane.setDevices(DeviceCenter.shared.names)
        pane.onTrash = { [weak self] urls in OperationCenter.shared.trash(urls, window: self?.window) }
        pane.setCloud(CloudFolders.locations(home: FileManager.default.homeDirectoryForCurrentUser))
        pane.menuProvider = { [weak self] node in self?.nodeMenu(node) }
        pane.dropHost = self
        pane.onTreeChanged = { [weak self] in self?.sessionChanged() }
        // The right-hand pane's width, dragged at its left edge, is kept for every window.
        let store = SidebarStore(defaults: .standard)
        chassis.sidePaneWidth = CGFloat(store.sidePaneWidth.map(SidePaneSize.clamped) ?? SidePaneSize.standard)
        chassis.onSidePaneResized = { width in SidebarStore(defaults: .standard).setSidePaneWidth(width.map(Double.init)) }
        chassis.onSidebarResized = { [weak self] width in
            SidebarStore(defaults: .standard).setWidth(Double(width))
            self?.chassis.needsLayout = true
        }
        applyNavigationPaneOptions()
    }

    func applyNavigationPaneOptions() {
        chassis.sidebarShown = ListOptions.navPaneShown
        chassis.sideWidth = ListOptions.navPaneWidth
    }

    /// The tree opens down to the folder this tab shows (Ctrl+Shift+E, and after every move while
    /// View > Navigation pane > Always expand to current folder is on).
    func revealCurrentFolder(select: Bool) {
        // Home and the Recycle Bin have their own rows; the tree is not opened for them.
        guard !history.isSpecial, !RecycleBin.isTrash(history.current, home: FileManager.default.homeDirectoryForCurrentUser) else { return }
        chassis.sidebar.pane.revealInBackground(FilePaths.folderKey(history.current), select: select)
    }

    /// Ctrl+Shift+E: the tree opens to this folder, which takes the keyboard there (Right, Left, * work on).
    @objc func expandToCurrentFolder(_ sender: Any?) {
        if !ListOptions.navPaneShown { ListOptions.navPaneShown = true }
        revealCurrentFolder(select: true)
        if toolbar.address.isEditing { toolbar.address.endEditing(focus: .stay) }
        window?.makeFirstResponder(chassis.sidebar.outline)
    }

    @objc func toggleNavigationPane(_ sender: Any?) { ListOptions.navPaneShown.toggle() }
    @objc func toggleExpandToCurrent(_ sender: Any?) { ListOptions.expandToCurrent.toggle() }
    @objc func toggleHiddenItems(_ sender: Any?) { ListOptions.showHidden.toggle() }
    @objc func toggleNavPaneHidden(_ sender: Any?) { ListOptions.navPaneShowHidden.toggle() }

    @objc func volumesChanged(_ note: Notification) {
        let list = VolumeCenter.shared.volumes
        showVolumes(list)
        // A tab on a drive that went away goes Home, as Explorer goes to This PC.
        let roots = Set(list.map(\.path))
        var activeGone = false
        for i in tabs.tabs.indices {
            let place = tabs.tabs[i].history.current
            guard !NavigationHistory.isSpecial(place), place.path.hasPrefix("/Volumes/") else { continue }
            let root = "/Volumes/" + (place.path.dropFirst(9).split(separator: "/").first.map(String.init) ?? "")
            if !roots.contains(root) {
                tabs.modify(at: i) { $0.history.push(NavigationHistory.home) }
                if i == tabs.activeIndex { activeGone = true }
            }
        }
        if activeGone { load() }
        updateTabStrip()
    }

    @objc func serversChanged(_ note: Notification) {
        let center = VolumeCenter.shared
        chassis.sidebar.pane.browseStatus = center.browseStatus
        chassis.sidebar.pane.setServers(center.servers, notice: center.browseNotice)
    }

    /// Folders that changed on disk: their tree nodes are read again.
    func refreshTree(_ note: Notification) {
        var folders = (note.userInfo?["folders"] as? Set<String>) ?? []
        // Each pasted item's folder, resolved once per folder (a paste of thousands shares a few).
        let parents = Set(((note.userInfo?["select"] as? [String]) ?? []).map { ($0 as NSString).deletingLastPathComponent })
        for parent in parents { folders.insert(FilePaths.folderKey(URL(fileURLWithPath: parent))) }
        if folders.isEmpty, !history.isSpecial { folders.insert(FilePaths.folderKey(history.current)) }
        chassis.sidebar.pane.refresh(folders: folders)
    }

    func ejectVolume(_ v: VolumeCapacity) {
        if v.isNetwork { VolumeCenter.shared.disconnect(v, window: window) } else { VolumeCenter.shared.eject(v, window: window) }
    }

    /// File > Eject: the drive the shown folder is on.
    @objc func ejectCurrentVolume(_ sender: Any?) {
        guard let v = currentEjectable else { NSSound.beep(); return }
        ejectVolume(v)
    }

    var currentEjectable: VolumeCapacity? {
        guard !history.isSpecial else { return nil }
        let key = FilePaths.folderKey(history.current)
        return volumes.filter { $0.canEject && (key == $0.path || key.hasPrefix($0.path + "/")) }.max { $0.path.count < $1.path.count }
    }

    @objc func connectToServer(_ sender: Any?) {
        VolumeCenter.shared.connectToServer(window: window) { [weak self] url in self?.navigate(to: url) }
    }

    /// \\server\share or smb://... typed in the address bar.
    func connect(to target: ServerTarget) -> Bool {
        VolumeCenter.shared.mount(target, window: window) { [weak self] url in self?.navigate(to: url) }
        return true
    }

    // MARK: Right-click a node: the folder's menu without opening it

    func nodeMenu(_ node: SideNode) -> NSMenu? {
        let menu = NSMenu(title: "Navigation")
        menu.font = Typeface.menu()
        func add(_ title: String, _ action: Selector, _ object: Any? = nil, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
            item.target = self
            item.representedObject = object
            menu.addItem(item)
        }
        switch node.kind {
        case .home:
            add("Open", #selector(goHome(_:)))
            add("Open in new tab", #selector(nodeOpenHomeTab(_:)))
            return menu
        case .suggestions:
            add("Open", #selector(goSuggestions(_:)))
            add("Open in new tab", #selector(nodeOpenSuggestionsTab(_:)))
            return menu
        case .device:
            add("Import pictures and videos", #selector(openImageCapture(_:)))
            return menu
        case .connect, .browse, .server:
            add("Connect to server...", #selector(connectToServer(_:)))
            if case .server = node.kind { add("Browse network again", #selector(nodeBrowse(_:))) }
            return menu
        case .header, .footer, .notice:
            return nil
        default:
            break
        }
        guard let url = node.url else { return nil }
        add("Open", #selector(nodeOpen(_:)), url)
        add("Open in new tab", #selector(nodeOpenTab(_:)), url)
        add("Open in new window", #selector(nodeOpenWindow(_:)), url)
        add("Open in Terminal", #selector(nodeTerminal(_:)), url)
        menu.addItem(.separator())
        add("Paste", #selector(nodePaste(_:)), url, enabled: FileClipboard.hasFiles)
        add("New folder here", #selector(nodeNewFolder(_:)), url)
        menu.addItem(.separator())
        if case .pin = node.kind {
            add("Unpin from Quick access", #selector(nodeUnpin(_:)), url)
            add("Move up", #selector(nodeMoveUp(_:)), url)
            add("Move down", #selector(nodeMoveDown(_:)), url)
        } else if pins.isPinned(url.path) {
            add("Unpin from Quick access", #selector(nodeUnpin(_:)), url)
        } else {
            add("Pin to Quick access", #selector(nodePin(_:)), url)
        }
        if let v = node.volume {
            menu.addItem(.separator())
            if v.isNetwork {
                add("Disconnect", #selector(nodeEject(_:)), v.path)
            } else {
                if v.canEject { add("Eject", #selector(nodeEject(_:)), v.path) }
                if !v.isRoot { add("Rename...", #selector(nodeRename(_:)), v.path) }
                // Explorer's drive menu and Properties > Tools: Format and Check (diskutil).
                add("Check for errors", #selector(checkDrive(_:)), v.path)
                if !v.isRoot { add("Format...", #selector(formatDrive(_:)), v.path) }
            }
        }
        menu.addItem(.separator())
        add("Copy as path", #selector(nodeCopyPath(_:)), url)
        add("Properties", #selector(nodeProperties(_:)), url)
        return menu
    }

    private func nodeURL(_ sender: Any?) -> URL? { (sender as? NSMenuItem)?.representedObject as? URL }
    private func nodeVolume(_ sender: Any?) -> VolumeCapacity? {
        guard let path = (sender as? NSMenuItem)?.representedObject as? String else { return nil }
        return volumes.first { $0.path == path }
    }

    @objc func nodeOpen(_ sender: Any?) { if let url = nodeURL(sender) { navigate(to: url) } }
    @objc func nodeOpenTab(_ sender: Any?) { if let url = nodeURL(sender) { openInNewTab(url, activate: true) } }
    @objc func nodeOpenHomeTab(_ sender: Any?) { openInNewTab(NavigationHistory.home, activate: true) }
    @objc func nodeOpenSuggestionsTab(_ sender: Any?) { openInNewTab(NavigationHistory.suggestions, activate: true) }
    @objc func nodeOpenWindow(_ sender: Any?) { if let url = nodeURL(sender) { appDelegate?.openWindow(at: url) } }
    @objc func nodeTerminal(_ sender: Any?) { if let url = nodeURL(sender) { openTerminal(at: [url]) } }
    @objc func nodeBrowse(_ sender: Any?) { VolumeCenter.shared.browse() }

    @objc func nodePaste(_ sender: Any?) {
        guard let target = nodeURL(sender) else { return }
        let (urls, isCut) = FileClipboard.read()
        guard !urls.isEmpty else { NSSound.beep(); return }
        if isCut { FileClipboard.endCut() }
        OperationCenter.shared.start(isCut ? .move : .copy, sources: urls, into: target, near: window)
    }

    /// New folder inside the node, without opening it; the node opens to show it.
    @objc func nodeNewFolder(_ sender: Any?) {
        guard let target = nodeURL(sender) else { return }
        do {
            let url = try FileOps.newFolder(in: target)
            OperationCenter.shared.record(.newFolder(url))
            OperationCenter.shared.postChanged(select: [url])
            chassis.sidebar.pane.reveal(FilePaths.folderKey(url))
        } catch {
            OperationCenter.shared.present(error, window: window)
        }
    }

    @objc func nodePin(_ sender: Any?) { if let url = nodeURL(sender) { editPins(.pin(url.path, at: Int.max)) } }
    @objc func nodeUnpin(_ sender: Any?) { if let url = nodeURL(sender) { editPins(.unpin(url.path)) } }
    @objc func nodeMoveUp(_ sender: Any?) { moveNodePin(sender, by: -1) }
    @objc func nodeMoveDown(_ sender: Any?) { moveNodePin(sender, by: 2) }

    private func moveNodePin(_ sender: Any?, by step: Int) {
        guard let url = nodeURL(sender), let i = pins.paths.firstIndex(of: url.path) else { return }
        editPins(.move(from: i, to: max(0, min(pins.paths.count, i + step))))
    }

    @objc func nodeEject(_ sender: Any?) { if let v = nodeVolume(sender) { ejectVolume(v) } }
    @objc func nodeRename(_ sender: Any?) { if let v = nodeVolume(sender) { VolumeCenter.shared.rename(v, window: window) } }

    @objc func nodeCopyPath(_ sender: Any?) {
        guard let url = nodeURL(sender) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PathText.quoted([url]), forType: .string)
    }

    @objc func nodeProperties(_ sender: Any?) {
        if let url = nodeURL(sender) { PropertiesWindowController.show([url], near: window) }
    }
}

// MARK: - Home

/// Where Home's lists come from: the pins, Favorites, Recent files (Folio's own log plus the system's
/// recent documents) and Recent locations (the address history).
@MainActor
enum HomeData {
    static let didChange = Notification.Name("FolioHomeDataChanged")

    static func noteOpened(_ url: URL, defaults: UserDefaults) {
        RecentFiles(defaults: defaults).record(url.path)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func content(pins: PinStore, defaults: UserDefaults) -> HomeContent {
        let fm = FileManager.default
        let own = RecentFiles(defaults: defaults).paths
        let system = NSDocumentController.shared.recentDocumentURLs.filter(\.isFileURL).map(\.path)
        let recent = RecentFiles.merged(own: own, system: system).filter { fm.fileExists(atPath: $0) }
        let favorites = FavoritesStore(defaults: defaults).paths.filter { fm.fileExists(atPath: $0) }
        let locations = AddressHistory(defaults: defaults).paths.filter { fm.fileExists(atPath: $0) }
        // Folder Options > Privacy: Show recently used files, Show frequently used folders.
        let privacy = ListOptions.folder
        return HomeContent(pins: pins.places,
                           favorites: favorites.map { URL(fileURLWithPath: $0) },
                           recentFiles: privacy.showRecentFiles ? recent.map { URL(fileURLWithPath: $0) } : [],
                           recentLocations: privacy.showFrequentFolders
                               ? locations.prefix(12).map { URL(fileURLWithPath: $0, isDirectory: true) } : [])
    }
}

extension BrowserWindowController {
    func wireHome() {
        let home = chassis.home.home
        home.onOpenFolder = { [weak self] url in self?.navigate(to: url) }
        home.onOpenFile = { [weak self] url in self?.openFile(url) }
        home.menuProvider = { [weak self] url in self?.homeMenu(url) }
    }

    /// The tab shows Home: no listing, the list pane swaps for the Home panels.
    func showHome() {
        requestID += 1
        isLoading = false
        loadError = nil
        statusMessage = nil
        pendingSelect = nil
        renamer.cancel()
        dropdown.close()
        showEmptyList()
        chassis.page = .home
        chassis.home.home.content = HomeData.content(pins: pins, defaults: options.historyDefaults)
        chassis.home.needsLayout = true
        updateChrome()
        didNavigate()
    }

    var homeStatusText: String {
        let c = chassis.home.home.content
        return "Home: \(c.pins.count) pinned, \(c.favorites.count) favorites, \(c.recentFiles.count) recent files"
    }

    @objc func homeDataChanged(_ note: Notification) {
        guard history.isHome else { return }
        chassis.home.home.content = HomeData.content(pins: pins, defaults: options.historyDefaults)
        updateStatus()
    }

    func homeMenu(_ url: URL) -> NSMenu {
        let menu = NSMenu(title: "Home")
        menu.font = Typeface.menu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = url
            menu.addItem(item)
        }
        add("Open", #selector(homeOpen(_:)))
        add("Open file location", #selector(homeOpenLocation(_:)))
        add("Open in new tab", #selector(homeOpenTab(_:)))
        menu.addItem(.separator())
        let favorites = FavoritesStore(defaults: options.historyDefaults)
        add(favorites.contains(url.path) ? "Remove from Favorites" : "Add to Favorites", #selector(homeToggleFavorite(_:)))
        if RecentFiles(defaults: options.historyDefaults).paths.contains(url.path) {
            add("Remove from Recent", #selector(homeRemoveRecent(_:)))
        }
        add("Copy as path", #selector(nodeCopyPath(_:)))
        add("Properties", #selector(nodeProperties(_:)))
        return menu
    }

    private func homeURL(_ sender: Any?) -> URL? { (sender as? NSMenuItem)?.representedObject as? URL }

    @objc func homeOpen(_ sender: Any?) {
        guard let url = homeURL(sender) else { return }
        var dir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &dir), dir.boolValue, !DropRules.isApp(url) {
            navigate(to: url)
        } else {
            openFile(url)
        }
    }

    @objc func homeOpenLocation(_ sender: Any?) {
        guard let url = homeURL(sender) else { return }
        navigate(to: url.deletingLastPathComponent(), selecting: FilePaths.itemKey(url))
    }

    @objc func homeOpenTab(_ sender: Any?) {
        guard let url = homeURL(sender) else { return }
        openInNewTab(url.hasDirectoryPath ? url : url.deletingLastPathComponent(), activate: true)
    }

    @objc func homeToggleFavorite(_ sender: Any?) {
        guard let url = homeURL(sender) else { return }
        var favorites = FavoritesStore(defaults: options.historyDefaults)
        favorites.toggle(url.path)
        NotificationCenter.default.post(name: HomeData.didChange, object: nil)
    }

    @objc func homeRemoveRecent(_ sender: Any?) {
        guard let url = homeURL(sender) else { return }
        RecentFiles(defaults: options.historyDefaults).remove(url.path)
        NotificationCenter.default.post(name: HomeData.didChange, object: nil)
    }

    /// Item menu > Add to Favorites / Remove from Favorites.
    @objc func toggleFavorite(_ sender: Any?) {
        guard let url = selectedURLs.first else { return }
        var favorites = FavoritesStore(defaults: options.historyDefaults)
        favorites.toggle(url.path)
        NotificationCenter.default.post(name: HomeData.didChange, object: nil)
    }
}

// MARK: - The Recycle Bin

extension BrowserWindowController {
    /// Restore: each item goes back to the folder it was deleted from (Folio remembers it).
    @objc func restoreFromTrash(_ sender: Any?) {
        let origins = TrashOrigins(defaults: .standard)
        var byFolder: [URL: [URL]] = [:]
        var unknown: [String] = []
        for url in selectedURLs {
            if let folder = RecycleBin.restoreFolder(original: origins.original(of: url.path)) {
                byFolder[folder, default: []].append(url)
                origins.forget(url.path)
            } else {
                unknown.append(url.lastPathComponent)
            }
        }
        for (folder, urls) in byFolder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            OperationCenter.shared.start(.move, sources: urls, into: folder, near: window)
        }
        if !unknown.isEmpty {
            let text = "Folio doesn't know where these came from (they were deleted outside Folio): " + unknown.joined(separator: ", ")
                + ". Drag them to a folder instead."
            OperationCenter.shared.present(FileOpError.system(text), window: window)
        }
    }

    /// Empty Recycle Bin (the Trash view menu).
    @objc func emptyRecycleBin(_ sender: Any?) { confirmEmptyTrash() }

    /// Asks, then deletes everything in the Trash for good. It takes no folder: the center names the Trash,
    /// and refuses anything that is not the Trash of the home (or of the test fixture's home).
    func confirmEmptyTrash() {
        guard let trash = SuggestionsCenter.shared.trashFolder else { NSSound.beep(); return }
        let items = ((try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent != ".DS_Store" }
        guard !items.isEmpty, let window else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Permanently delete these \(items.count) items?"
        alert.informativeText = "Everything in the \(PlaceNames.recycleBin) goes for good. This can't be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Empty " + PlaceNames.recycleBin)
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated {
                let center = SuggestionsCenter.shared
                center.markEmptying()
                OperationCenter.shared.deletePermanently(items, window: window, finished: { center.finishEmptying() })
            }
        }
    }
}
