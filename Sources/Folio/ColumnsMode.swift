import AppKit
import FolioCore

/// The Columns view in the window (ColumnsView.swift has the views). The current folder is the folder whose
/// column holds the selection: its column is the window's list (`entries`, `selection`), so every command
/// works there as in any view. The other columns are read off the main thread with the list's own listing
/// path and sort, and kept, so a click or an arrow in them makes their folder the current one at once.
extension BrowserWindowController: ColumnHost {
    var columnBrowser: ColumnBrowserView { chassis.pane.columns }

    /// The current folder's column's table: the list the keys and menus act on in Columns.
    var activeColumnTable: ColumnTableView? { columnBrowser.activeColumn?.table }

    /// Where the columns may start: home, the Quick access pins and every volume's root.
    var columnAnchors: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ([home] + pins.paths + volumes.map(\.path)).map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }

    /// How a column is sorted: the list's sort; filters and Group by do not apply to columns.
    var columnArrangeKey: ArrangeKey { ArrangeKey(filters: FilterSet(), sort: sortSpec, group: nil, collapsed: [], relevance: false) }

    /// Read and sorted the way the list is now (it may be stale: read again since its folder changed).
    private func isUsable(_ l: ColumnListing) -> Bool {
        l.sort == sortSpec && l.hidden == ListOptions.showHidden && l.protected == ListOptions.folder.hideProtectedOSFiles
    }

    private func isCurrent(_ l: ColumnListing) -> Bool { isUsable(l) && !l.stale }

    /// A folder whose column is read and sorted the way the list is now: it becomes the current folder with
    /// no wait (and is read again quietly when stale).
    func columnListingReady(_ url: URL) -> ColumnListing? {
        guard viewMode == .columns, !isSearching, !NavigationHistory.isHome(url),
              let l = columnStore.listing(url.standardizedFileURL.path), isUsable(l) else { return nil }
        return l
    }

    /// Back, Up or Left onto a folder the columns came down through: the folder that leads back is selected.
    func columnLandingSelection() -> Set<String> {
        guard let shown = columnStore.shownFolder,
              let child = ColumnPath.selection(arriving: history.current.standardizedFileURL.path, from: shown) else { return [] }
        return [FilePaths.itemKey(URL(fileURLWithPath: child))]
    }

    // MARK: Building the columns

    /// Makes the columns match the current folder and its selection. Cheap when nothing changed (it runs on
    /// every selection change).
    func syncColumns() {
        guard viewMode == .columns, !history.isHome, !isSearching, !searchUIShown, !isLoading else { return }
        let browser = columnBrowser
        let store = columnStore
        let current = history.current.standardizedFileURL.path
        if store.shownFolder != current || store.root == nil {
            store.root = ColumnPath.root(for: current, previous: store.root, shown: store.shownPaths, anchors: columnAnchors)
            store.shownFolder = current
        }
        // The current folder's list is its column's listing too, for when it is no longer the current one.
        let listed = listedFolder?.standardizedFileURL.path == current
        if listed, store.cachedVersion != entriesVersion, let adopted = store.adoptedID, store.listing(current)?.id == adopted {
            // Shown from this very listing: nothing to put, and the column needs no reload.
            store.cachedVersion = entriesVersion
        } else if listed, store.cachedVersion != entriesVersion, arrangedWith == columnArrangeKey {
            store.cachedVersion = entriesVersion
            store.put(ColumnListing(url: history.current, path: current, folderKey: FilePaths.folderKey(history.current), rows: entries,
                                    keys: entryKeys, sort: sortSpec, hidden: listedWith.hidden, protected: listedWith.protected,
                                    ensured: nil, error: loadError))
        }
        store.adoptedID = nil
        let selected = selectedEntries
        let plan = ColumnPlan.make(root: store.root ?? current, current: current,
                                   selected: selected.map { ($0.url.standardizedFileURL.path, $0.isFolder) })
        var list: [ColumnView] = []
        for (i, path) in plan.folders.enumerated() {
            let view = browser.column(for: path) ?? makeColumn(path)
            if i == plan.folders.count - 1 {
                view.isActive = true
                let cached = store.cachedVersion == entriesVersion ? store.listing(path) : nil
                if listed {
                    view.setRows(entries, keys: entryKeys, token: cached.map { "l\($0.id)" } ?? "e\(entriesVersion)")
                    view.message = entries.isEmpty ? (loadError ?? "Empty folder") : nil
                } else {
                    view.setRows([], keys: [], token: "pending")
                }
                view.light(selection.rows)
                view.focusRow = selection.focus
            } else {
                view.isActive = false
                fill(view, lit: plan.highlighted[i], trailing: false)
            }
            list.append(view)
        }
        var previewEntry: FileEntry?
        switch plan.tail {
        case .folder(let path):
            let view = browser.column(for: path) ?? makeColumn(path)
            view.isActive = false
            fill(view, lit: nil, trailing: true)
            list.append(view)
        case .preview:
            previewEntry = selected.first
        case .none:
            break
        }
        let paths = list.map(\.path)
        // Every folder from the first column to the current one stays live on disk (not a selected folder's
        // column: watching it would restart the watcher on every arrow press).
        let moved = plan.folders != store.pathFolders
        store.pathFolders = plan.folders
        store.shownPaths = paths
        store.widths = store.widths.filter { paths.contains($0.key) }
        let changed = browser.setColumns(list, preview: previewEntry != nil)
        if let previewEntry { showColumnPreview(previewEntry) }
        // The keyboard follows the current column (never away from the address bar, the search box or a rename).
        if let active = browser.activeColumn?.table, let window {
            let first = window.firstResponder
            if first == nil || first === window || first === tableView || first === grid || (first is ColumnTableView && first !== active) {
                window.makeFirstResponder(active)
            }
        }
        if changed { browser.reveal() }
        if moved { updateWatches() }
    }

    /// A column other than the current one: its listing if read (or being read), the lit item that leads on.
    private func fill(_ view: ColumnView, lit name: String?, trailing: Bool) {
        let store = columnStore
        guard let l = store.listing(view.path), isUsable(l) else {
            // Being read: the column keeps what it showed until the new rows land.
            requestColumn(view.path, ensure: name, trailing: trailing)
            return
        }
        // Changed on disk: shown as it was until it is read again.
        if l.stale { requestColumn(view.path, ensure: name, trailing: trailing) }
        view.setRows(l.rows, keys: l.keys, token: "l\(l.id)")
        view.message = l.rows.isEmpty ? (l.error ?? "Empty folder") : nil
        let (index, moved) = view.index(ofName: name)
        // A hidden folder on the way (hidden items off): read again with it put in, once.
        if let name, index == nil, l.ensured != name { requestColumn(view.path, ensure: name, trailing: trailing) }
        view.light(index.map { IndexSet(integer: $0) } ?? IndexSet())
        if moved, let index { view.table.scrollRowToVisible(index) }
    }

    private func makeColumn(_ path: String) -> ColumnView {
        let view = ColumnView(path: path, url: URL(fileURLWithPath: path), width: columnStore.widths[path] ?? columnStore.width)
        view.host = self
        view.table.listDelegate = columnRouter
        view.table.singleClickOpens = ListOptions.folder.singleClickOpens
        view.table.setAccessibilityLabel("Column " + displayName(view.url))
        return view
    }

    // MARK: Reading columns off the main thread

    /// Reads a column's folder. A selected folder's column (`trailing`) reads one at a time, the latest wins.
    func requestColumn(_ path: String, ensure name: String?, trailing: Bool) {
        let store = columnStore
        guard !store.inFlight.contains(path) else { return }
        if trailing, store.trailingBusy {
            store.trailingWanted = (path, name)
            return
        }
        store.inFlight.insert(path)
        if trailing { store.trailingBusy = true }
        let url = URL(fileURLWithPath: path)
        let key = columnArrangeKey
        let hidden = ListOptions.showHidden, protected = ListOptions.folder.hideProtectedOSFiles
        Task.detached(priority: .userInitiated) { [weak self] in
            let listing = Self.readColumn(url, path: path, key: key, hidden: hidden, protected: protected, ensure: name)
            await self?.columnArrived(listing, trailing: trailing)
        }
    }

    private func columnArrived(_ listing: ColumnListing, trailing: Bool) {
        let store = columnStore
        store.inFlight.remove(listing.path)
        let fresh = store.put(listing)
        // The current folder read again (it was entered from an older column): what changed shows, the
        // selection kept as it is now.
        if fresh.path == history.current.standardizedFileURL.path, listedFolder == history.current, viewMode == .columns,
           !isLoading, !renamer.isActive, arrangedWith == columnArrangeKey, isCurrent(fresh), fresh.rows != entries {
            self.listing = fresh.rows
            store.adoptedID = fresh.id
            show(ListLayout(items: fresh.rows), selecting: Set(selectedKeys), keys: fresh.keys)
            return
        }
        perfLog.notice("""
            columns: read \(listing.rows.count, privacy: .public) items in \(listing.path, privacy: .public) in \
            \(listing.readMs, privacy: .public) ms off the main thread
            """)
        if trailing {
            store.trailingBusy = false
            if let next = store.trailingWanted {
                store.trailingWanted = nil
                if next.path != listing.path { requestColumn(next.path, ensure: next.ensure, trailing: true) }
            }
        }
        if store.pendingEnter == listing.path {
            store.pendingEnter = nil
            if selectedEntries.count == 1, selectedEntries[0].url.standardizedFileURL.path == listing.path {
                enterColumn(listing)
                return
            }
        }
        syncColumns()
    }

    /// One column's rows, as the list would show that folder: the same listing path, then the list's sort.
    nonisolated static func readColumn(_ url: URL, path: String, key: ArrangeKey, hidden: Bool, protected: Bool,
                                       ensure name: String?) -> ColumnListing {
        let started = Date()
        var rows: [FileEntry] = []
        var problem: String?
        do {
            rows = try listFolder(url, hidden: hidden, protected: protected)
        } catch {
            problem = error.localizedDescription
        }
        if let name, !rows.contains(where: { $0.name == name }) {
            let child = url.appendingPathComponent(name)
            let values = try? child.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
            rows.append(FileEntry(url: child, name: name, isFolder: true, modified: values?.contentModificationDate, size: nil,
                                  kind: "Folder", isHidden: true, isLink: values?.isSymbolicLink == true))
        }
        let arranged = arrange(rows, key).items
        // `ensured`: read wanting that name, and it is in the rows (put in when hidden items are off).
        var listing = ColumnListing(url: url, path: path, folderKey: FilePaths.folderKey(url), rows: arranged,
                                    keys: FilePaths.itemKeys(arranged.map(\.url)), sort: key.sort, hidden: hidden, protected: protected,
                                    ensured: name, error: problem)
        listing.readMs = Int(Date().timeIntervalSince(started) * 1000)
        return listing
    }

    /// Files changed (FilePaths.folderKey values, nil for anywhere): those columns are read again.
    func columnFoldersChanged(_ folderKeys: Set<String>?) {
        guard viewMode == .columns else { return }
        if columnStore.forget(folderKeys) { syncColumns() }
    }

    // MARK: Left and Right

    /// Right: into the one selected folder, its first item selected. Plain Left and Right do nothing in
    /// the other views.
    func columnsRight() {
        let selected = selectedEntries
        guard case .enter(let path) = ColumnKeys.right(selected: selected.map { ($0.url.standardizedFileURL.path, $0.isFolder) }) else { return }
        if let listing = columnListingReady(URL(fileURLWithPath: path)) {
            enterColumn(listing)
        } else {
            // Its column is still being read: in as soon as it lands.
            columnStore.pendingEnter = path
            requestColumn(path, ensure: nil, trailing: true)
        }
    }

    private func enterColumn(_ listing: ColumnListing) {
        history.push(listing.url)
        showColumnFolder(listing, selecting: listing.keys.first.map { [$0] } ?? [])
    }

    /// Left: the column before, with this folder selected (in the first column, up a folder anyway).
    func columnsLeft() {
        guard !history.isHome, case .leave(let to, let select) = ColumnKeys.left(current: history.current.standardizedFileURL.path) else { return }
        history.push(URL(fileURLWithPath: to))
        load(restoring: ([FilePaths.itemKey(URL(fileURLWithPath: select))], 0))
    }

    /// A click (or a menu, or a drag) in a column that is not the current one: its folder becomes the
    /// current one, with `row` selected (nil for none).
    func openColumn(_ column: ColumnView, selecting row: Int?) {
        guard let listing = columnStore.listing(column.path), isUsable(listing) else { return }
        if renamer.isActive { renamer.cancel() }
        // The item as the column shows it (its listing may have been read again since).
        let select: Set<String> = row.flatMap { column.keys.indices.contains($0) ? [column.keys[$0]] : nil } ?? []
        history.push(listing.url)
        showColumnFolder(listing, selecting: select)
    }

    // MARK: The preview column

    private func showColumnPreview(_ entry: FileEntry) {
        let preview = columnBrowser.preview
        var meta = MetadataCache.shared.cached(entry)
        if meta == nil, !isInZip { requestMetadata(entry) }
        if isInZip { meta = nil }
        let tags = isInZip ? [] : ItemDecorCache.shared.tagColors(entry.url)
        preview.show(entry, fields: ColumnPreview.fields(entry, meta), tags: tags)
        guard !isInZip, ListOptions.thumbnails else { return }
        let side = CGFloat(240)
        if let image = ThumbnailCache.shared.image(for: entry, size: side, done: { [weak preview] image in
            guard let preview, preview.entry?.url == entry.url else { return }
            preview.thumbnail = image
        }) {
            preview.thumbnail = image
        }
    }

    // MARK: ColumnHost

    func columnCell(_ cell: NameCellView, for entry: FileEntry, key: String) {
        cell.isCut = dimmed.contains(key)
        cell.showsExtension = ListOptions.showExtensions
        decorate(cell, entry)
    }

    private func columnDropTarget(_ column: ColumnView, row: Int) -> Int {
        guard column.rows.indices.contains(row) else { return -1 }
        let e = column.rows[row]
        return e.isFolder || DropRules.isApp(e.url) ? row : -1
    }

    func columnValidateDrop(_ column: ColumnView, _ info: NSDraggingInfo, row: Int) -> NSDragOperation {
        let target = columnDropTarget(column, row: row)
        let url = target >= 0 ? column.rows[target].url : column.url
        let action = dropAction(info, onto: url)
        columnBrowser.holdsStill = true
        columnBrowser.clearDrops(except: column)
        column.dropRow = action == .none ? -1 : target
        column.isDropTarget = target < 0 && action != .none
        springLoad(target >= 0 && column.rows[target].isFolder ? url : nil)
        showDropTip(action, target: url, info: info)
        return dragOperation(for: action, info)
    }

    func columnAcceptDrop(_ column: ColumnView, _ info: NSDraggingInfo, row: Int) -> Bool {
        let target = columnDropTarget(column, row: row)
        columnBrowser.clearDrops()
        columnBrowser.holdsStill = false
        return performDrop(info, onto: target >= 0 ? column.rows[target].url : column.url)
    }

    func columnTypeSelect(_ text: String, at time: TimeInterval) { typeSelect(text, at: time) }

    func columnWidthChanged(_ column: ColumnView, done: Bool) {
        columnStore.widths[column.path] = column.width
        columnBrowser.layoutStrip()
        guard done else { return }
        // The width every column opens at from now on, in every window and the next launch.
        columnStore.width = column.width
        ColumnWidth.save(Double(column.width), .standard)
    }

    func columnFit(_ column: ColumnView) {
        let font = Typeface.ui(13, weight: 500)
        let widest = column.rows.reduce(CGFloat(0)) { max($0, textWidth($1.displayName(extensions: ListOptions.showExtensions), font: font)) }
        // The icon and its gaps on the left, the chevron's room on the right, tag dots and a little air.
        let chrome = ListMetrics.rowLead + 16 + 9 + FolioRowView.chevronRoom + 28
        column.width = CGFloat(ColumnWidth.fit(widest: Double(widest), chrome: Double(chrome)))
        columnStore.widths[column.path] = column.width
        columnBrowser.layoutStrip()
    }
}

/// Clicks, menus and drags in the columns. The current folder's column passes them to the window as the
/// Details table does; another column first makes its folder the current one (at once, from its listing).
@MainActor
final class ColumnRouter: FileListDelegate {
    weak var controller: BrowserWindowController?

    private func column(_ list: NSView) -> ColumnView? { (list as? ColumnTableView)?.column }

    /// A press in a column that is not the current one (ColumnTableView): its folder becomes the current one.
    func press(_ column: ColumnView, row: Int?) {
        controller?.openColumn(column, selecting: row)
    }

    /// The column is the current one now (opening it if it was not); false when it could not be.
    private func activate(_ list: NSView, selecting row: Int?) -> Bool {
        guard let c = controller, let col = column(list) else { return false }
        if col.isActive { return true }
        c.openColumn(col, selecting: row)
        return col.isActive
    }

    func list(_ list: NSView, clicked row: Int, modifiers: NSEvent.ModifierFlags) {
        guard let c = controller, let col = column(list) else { return }
        if col.isActive { c.list(list, clicked: row, modifiers: modifiers) } else { c.openColumn(col, selecting: row) }
    }

    func list(_ list: NSView, toggledCheckboxOf row: Int) {
        if activate(list, selecting: nil) { controller?.list(list, toggledCheckboxOf: row) }
    }

    func list(_ list: NSView, opened row: Int) {
        if activate(list, selecting: row) { controller?.list(list, opened: row) }
    }

    func list(_ list: NSView, banded rows: IndexSet, focus: Int?) {
        guard let col = column(list) else { return }
        if !col.isActive {
            // A press on a column's empty space: its folder, nothing selected.
            controller?.openColumn(col, selecting: nil)
            if rows.isEmpty { return }
        }
        if col.isActive { controller?.list(list, banded: rows, focus: focus) }
    }

    func listToggledAll(_ list: NSView) {
        if activate(list, selecting: nil) { controller?.listToggledAll(list) }
    }

    func list(_ list: NSView, showPropertiesOf row: Int) {
        if activate(list, selecting: row) { controller?.list(list, showPropertiesOf: row) }
    }

    func list(_ list: NSView, beginDragWith event: NSEvent, rightButton: Bool) {
        guard column(list)?.isActive == true else { return }
        controller?.list(list, beginDragWith: event, rightButton: rightButton)
    }

    func list(_ list: NSView, menuFor row: Int, event: NSEvent) -> NSMenu? {
        guard activate(list, selecting: row >= 0 ? row : nil) else { return nil }
        return controller?.list(list, menuFor: row, event: event)
    }

    func listDragExited(_ list: NSView) {
        controller?.columnBrowser.clearDrops()
        // A drag that left the columns, or ended: the strip may settle again.
        if let browser = controller?.columnBrowser, let window = list.window,
           !browser.frame.contains(browser.superview?.convert(window.mouseLocationOutsideOfEventStream, from: nil) ?? .zero)
            || NSEvent.pressedMouseButtons == 0 {
            browser.holdsStill = false
        }
        controller?.listDragExited(list)
    }

    func listSelectedURLs(_ list: NSView) -> [URL] {
        column(list)?.isActive == true ? controller?.selectedURLs ?? [] : []
    }

    func list(_ list: NSView, middleClicked row: Int) {
        guard let col = column(list), col.rows.indices.contains(row), col.rows[row].isFolder else { return }
        controller?.openInNewTab(col.rows[row].url, activate: false)
    }

    func list(_ list: NSView, pressedGroup group: Int, onChevron: Bool, clickCount: Int) {}

    func list(_ list: NSView, menuForGroup group: Int) -> NSMenu? { nil }

    /// Asked after a press made its column the current one (FolioTableView), so the window's selection answers.
    func listIsSelected(_ row: Int) -> Bool { controller?.listIsSelected(row) ?? false }
}
