import AppKit
import FolioCore
import Quartz

/// Milestone 6 in the window: the views (and Cmd+scroll between them), Group by and its headers, the
/// header filters' tokens, metadata columns read lazily, the Preview and Details panes, Show options.
extension BrowserWindowController: GridHost {
    // MARK: Views

    /// Cmd+scroll zooms wherever the pointer is over the list (not over the tree or the address bar).
    var zoomsWithScroll: Bool { !history.isHome }

    @objc func viewModeChanged(_ note: Notification) { applyViewMode() }

    func applyViewMode() {
        let started = Date()
        let mode = viewMode
        let focused = window?.firstResponder === tableView || window?.firstResponder === grid
        chassis.pane.mode = mode
        grid.compact = ListOptions.compact
        grid.mode = mode
        if !mode.usesTable { grid.reloadData() }
        if focused || window?.firstResponder === window { window?.makeFirstResponder(listView) }
        window?.initialFirstResponder = listView
        if let f = selection.focus ?? selection.rows.first { scrollToItem(f) }
        updateStatus()
        selectionDidChange()
        window?.displayIfNeeded()
        perfLog.notice("""
            view \(mode.rawValue, privacy: .public): \(self.entries.count, privacy: .public) items shown in \
            \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public) ms
            """)
        PerfTrace.mark("view", "mode=\(mode.rawValue) items=\(entries.count) ms=\(PerfTrace.ms(since: started.timeIntervalSince1970))")
    }

    @objc func setViewMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ViewMode(rawValue: raw) else { return }
        chooseView(mode)
    }

    /// The one view for every window, or while results show, theirs alone (they open in Details).
    func chooseView(_ mode: ViewMode) {
        if isSearching {
            guard mode != viewMode else { return }
            searchView = mode
            applyViewMode()
        } else {
            ViewCenter.shared.set(mode)
        }
    }

    /// View > Make this the default view: the only view setting there is; every launch starts in it.
    @objc func makeDefaultView(_ sender: Any?) { ViewCenter.shared.makeDefault() }

    func gridZoom(_ steps: Int) { chooseView(viewMode.zoomed(by: steps)) }

    /// A trackpad pinch: out to larger icons, in to smaller.
    func pinch(_ event: NSEvent) {
        pinchTotal += event.magnification
        if abs(pinchTotal) >= 0.25 {
            gridZoom(pinchTotal > 0 ? 1 : -1)
            pinchTotal = 0
        }
        if event.phase == .ended || event.phase == .cancelled { pinchTotal = 0 }
    }

    /// Ctrl+Shift+1 to 8 pick Explorer's layouts; Option+P and Option+Shift+P the right-hand panes;
    /// Cmd+= (Explorer's Ctrl+Numpad +) fits every column.
    func handleViewKey(_ event: NSEvent, modifiers: NSEvent.ModifierFlags, editingText: Bool) -> Bool {
        let numbers: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8]
        switch (event.keyCode, modifiers) {
        case (let code, [.control, .shift]) where numbers[code] != nil:
            if let mode = ViewMode.forShortcut(numbers[code]!) { chooseView(mode) }
        case (35, .option) where !editingText: togglePreviewPane(nil)
        case (35, [.option, .shift]) where !editingText: toggleDetailsPane(nil)
        case (24, .command) where !editingText, (69, .command) where !editingText: sizeAllColumnsToFit(nil)
        default: return false
        }
        return true
    }

    @objc func toggleCompactView(_ sender: Any?) { ListOptions.compact.toggle() }
    @objc func toggleFileExtensions(_ sender: Any?) { ListOptions.showExtensions.toggle() }
    @objc func toggleThumbnails(_ sender: Any?) { ListOptions.thumbnails.toggle() }
    @objc func togglePreviewPane(_ sender: Any?) { ListOptions.sidePane = ListOptions.sidePane == .preview ? .none : .preview }
    @objc func toggleDetailsPane(_ sender: Any?) { ListOptions.sidePane = ListOptions.sidePane == .details ? .none : .details }

    /// The View menu's checks and the View button's menu (the main menu's View menu is the same).
    func validateViewItem(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(setViewMode(_:)):
            item.state = (item.representedObject as? String) == viewMode.rawValue ? .on : .off
            return true
        case #selector(makeDefaultView(_:)):
            item.state = ViewCenter.shared.settings.isDefault ? .on : .off
            return !ViewCenter.shared.settings.isDefault
        case #selector(toggleCompactView(_:)): item.state = ListOptions.compact ? .on : .off
        case #selector(toggleFileExtensions(_:)): item.state = ListOptions.showExtensions ? .on : .off
        case #selector(toggleThumbnails(_:)):
            // "Always show icons, never thumbnails" is the same setting, the other way round.
            let iconsOnly = (item.representedObject as? String) == "iconsOnly"
            item.state = ListOptions.thumbnails != iconsOnly ? .on : .off
        case #selector(togglePreviewPane(_:)): item.state = ListOptions.sidePane == .preview ? .on : .off
        case #selector(toggleDetailsPane(_:)): item.state = ListOptions.sidePane == .details ? .on : .off
        case #selector(groupByColumn(_:)):
            let raw = item.representedObject as? String
            item.state = raw == (group?.key.rawValue ?? "none") ? .on : .off
        case #selector(groupAscending(_:)):
            item.state = group?.ascending == true ? .on : .off
            return group != nil
        case #selector(groupDescending(_:)):
            item.state = group?.ascending == false ? .on : .off
            return group != nil
        case #selector(collapseAllGroups(_:)), #selector(expandAllGroups(_:)):
            return layout.isGrouped
        case #selector(sizeAllColumnsToFit(_:)), #selector(chooseDetails(_:)):
            return !history.isHome
        case #selector(toggleColumn(_:)):
            let raw = item.representedObject as? String
            item.state = raw.flatMap(ColumnID.init(rawValue:)).map(ColumnCenter.shared.set.isVisible) == true ? .on : .off
            return raw != ColumnID.name.rawValue
        case #selector(sizeColumnToFit(_:)):
            return item.representedObject != nil
        case #selector(clearAllFilters(_:)):
            return !filters.isEmpty
        default: return nil
        }
        return true
    }

    // MARK: Group by

    @objc func groupByColumn(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let next: GroupSpec? = ColumnID(rawValue: raw).map { GroupSpec(key: $0, ascending: group?.ascending ?? !$0.isDate) }
        guard next != group else { return }
        group = next
        collapsedGroups = []
        rearrange()
        sessionChanged()
    }

    @objc func groupAscending(_ sender: Any?) { setGroupDirection(true) }
    @objc func groupDescending(_ sender: Any?) { setGroupDirection(false) }

    private func setGroupDirection(_ ascending: Bool) {
        guard var g = group, g.ascending != ascending else { return }
        g.ascending = ascending
        group = g
        rearrange()
        sessionChanged()
    }

    @objc func collapseAllGroups(_ sender: Any?) {
        collapsedGroups = Set(layout.groups.map(\.bucket.id))
        rearrange()
    }

    @objc func expandAllGroups(_ sender: Any?) {
        collapsedGroups = []
        rearrange()
    }

    func toggleGroup(_ g: Int) {
        guard layout.groups.indices.contains(g) else { return }
        let id = layout.groups[g].bucket.id
        if collapsedGroups.contains(id) { collapsedGroups.remove(id) } else { collapsedGroups.insert(id) }
        rearrange()
    }

    @objc private func toggleGroupItem(_ sender: NSMenuItem) {
        if let g = sender.representedObject as? Int { toggleGroup(g) }
    }

    func list(_ list: NSView, pressedGroup group: Int, onChevron: Bool, clickCount: Int) {
        if renamer.isActive { renamer.cancel() }
        if onChevron || clickCount >= 2 {
            toggleGroup(group)
            return
        }
        // A click on the header selects the whole group (one group at a time, as since Windows 7).
        guard layout.groupRanges.indices.contains(group) else { return }
        let range = layout.groupRanges[group]
        selection.adopt(IndexSet(integersIn: range), focus: range.isEmpty ? nil : range.lowerBound)
        if range.isEmpty { selection.selectNone() }
        applySelection(scroll: false)
    }

    func list(_ list: NSView, menuForGroup group: Int) -> NSMenu? {
        guard layout.groups.indices.contains(group) else { return nil }
        let menu = NSMenu(title: "Group")
        menu.font = Typeface.mono(13)
        let one = NSMenuItem(title: layout.isCollapsed(group) ? "Expand group" : "Collapse group",
                             action: #selector(toggleGroupItem(_:)), keyEquivalent: "")
        one.representedObject = group
        one.target = self
        menu.addItem(one)
        menu.addItem(.separator())
        for (title, action) in [("Collapse all groups", #selector(collapseAllGroups(_:))), ("Expand all groups", #selector(expandAllGroups(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    func listIsSelected(_ row: Int) -> Bool { selection.rows.contains(row) }

    // MARK: Filters

    func clearFilter(_ column: ColumnID) {
        filters.clear(column)
        rearrange()
        filterPanel?.refresh()
    }

    @objc func clearAllFilters(_ sender: Any?) {
        filters.clearAll()
        rearrange()
    }

    func updateFilterTokens() {
        let known: (ColumnID) -> [Bucket] = { [listing] column in
            Buckets.present(listing, column, context: BucketContext()) { MetadataCache.shared.cached($0) }.map(\.bucket)
        }
        let tokens = filters.isEmpty ? [] : filters.tokens(known: known)
        toolbar.address.tokens = tokens
    }

    // MARK: Metadata columns, read off the main thread as rows come into view

    func requestMetadata(_ entry: FileEntry) {
        guard !metadataInFlight.contains(entry.url.path) else { return }
        metadataInFlight.insert(entry.url.path)
        metadataQueue.append(entry)
        guard !metadataFlushScheduled else { return }
        metadataFlushScheduled = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.flushMetadata() } }
    }

    private func flushMetadata() {
        metadataFlushScheduled = false
        let batch = metadataQueue
        metadataQueue = []
        guard !batch.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            MetadataCache.shared.fill(batch)
            await self?.metadataArrived(batch)
        }
    }

    private func metadataArrived(_ batch: [FileEntry]) {
        for e in batch { metadataInFlight.remove(e.url.path) }
        reloadVisibleItems()
        selectionDidChange()
    }

    /// Redraws the rows and cells on screen with what is known now (metadata, cut items, options).
    func reloadVisibleItems() {
        let visible = tableView.rows(in: tableView.visibleRect)
        if visible.length > 0 {
            tableView.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)),
                                 columnIndexes: IndexSet(tableView.tableColumns.indices))
        }
        grid.forEachVisibleCell { cell, i in configure(cell, item: i) }
    }

    /// Tags or Comments typed in the Details pane.
    func editMetadata(_ url: URL, tags: [String]?, comment: String?) {
        do {
            if let tags { try MetadataWriter.setTags(tags, of: url) }
            if let comment { try MetadataWriter.setComment(comment, of: url) }
        } catch {
            OperationCenter.shared.present(error, window: window)
        }
        MetadataCache.shared.invalidate(url)
        ItemDecorCache.shared.forget(url)
        if let e = entries.first(where: { $0.url == url }) { requestMetadata(e) }
        reloadVisibleItems()
    }

    // MARK: The grid's cells

    var gridLayout: ListLayout { layout }

    func configure(_ cell: GridCellView, item i: Int) {
        guard entries.indices.contains(i) else { return }
        let e = entries[i]
        let mode = viewMode
        cell.mode = mode
        if cell.entry != e { cell.entry = e }
        cell.showsExtension = ListOptions.showExtensions
        cell.isSelected = selection.rows.contains(i)
        cell.isFocusItem = selection.focus == i
        cell.isCut = dimmed.contains(entryKeys[i])
        cell.isDropTarget = dropTargetRow == i
        decorate(cell, e)
        switch mode {
        case .tiles:
            cell.details = [("Type", e.kind), ("Size", e.size.map(ByteText.kilobytes) ?? "")].filter { !$0.1.isEmpty }
        case .content:
            var details: [(key: String, value: String)] = [("Type", e.kind)]
            details.append(("Date modified", e.modified.map(ColumnValues.dateText) ?? ""))
            if let size = e.size { details.append(("Size", ByteText.kilobytes(size))) }
            if !e.isFolder {
                let meta = MetadataCache.shared.cached(e)
                if meta == nil && ThumbnailCache.wants(e) { requestMetadata(e) }
                let dims = ColumnValues.text(e, .dimensions, meta), length = ColumnValues.text(e, .duration, meta)
                if !dims.isEmpty { details.append(("Dimensions", dims)) }
                if !length.isEmpty { details.append(("Duration", length)) }
            }
            cell.details = details
        default:
            cell.details = []
        }
        let size = CGFloat(mode.iconSize)
        if mode.showsThumbnails, ListOptions.thumbnails, !isInZip, ThumbnailCache.wants(e) {
            cell.thumbnail = ThumbnailCache.shared.image(for: e, size: size) { [weak cell] image in
                guard let cell, cell.entry?.url == e.url else { return }
                cell.thumbnail = image
            }
        } else {
            cell.thumbnail = nil
        }
    }

    // MARK: Type to select in the grid (the table has its own)

    func typeSelect(_ text: String, at time: TimeInterval) {
        if time - typeSelectTime > 1.0 { typeSelectBuffer = "" }
        typeSelectTime = time
        typeSelectBuffer += text
        let prefix = typeSelectBuffer.lowercased()
        guard let hit = entries.firstIndex(where: { $0.name.lowercased().hasPrefix(prefix) }) else { return }
        selection.click(hit)
        applySelection(scrollTo: hit)
    }

    // MARK: Following the selection: the right-hand pane, the Gallery's preview, Quick Look

    func selectionDidChange() {
        let selected = selectedEntries
        sessionChanged()
        chassis.sidebar.pane.details = DetailsCard.make(history.isHome ? [] : selected)
        if ListOptions.sidePane != .none, !history.isHome {
            var meta: ItemMetadata?
            if selected.count == 1, let one = selected.first {
                meta = MetadataCache.shared.cached(one)
                if meta == nil { requestMetadata(one) }
            }
            chassis.sidePane.show(selection: selected, folder: history.current, folderName: displayName(history.current),
                                  itemCount: shownCount, meta: meta)
        }
        if viewMode == .gallery {
            let target = selected.count == 1 ? selected.first : nil
            chassis.pane.gallery.show(target.flatMap { $0.isFolder ? nil : $0.url },
                                      message: selected.isEmpty ? "Select a picture or a video" :
                                        target?.isFolder == true ? "No preview for folders" : "\(selected.count) items selected")
        }
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible,
           panel.dataSource === self as AnyObject, !selected.isEmpty {
            let urls = selected.map(\.url)
            if urls != quickLookItems {
                quickLookItems = urls
                panel.reloadData()
            }
        }
    }
}
