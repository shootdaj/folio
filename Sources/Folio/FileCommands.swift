import AppKit
import FolioCore

/// View > Show: item check boxes, hidden items, file name extensions, thumbnails, compact view and
/// the right-hand pane, each saved in the defaults.
@MainActor
enum ListOptions {
    static let didChange = Notification.Name("FolioListOptionsDidChange")
    private static let key = "itemCheckBoxes"
    static let hiddenKey = "showHiddenItems"
    static let expandKey = "navPaneExpandToCurrent"
    static let navHiddenKey = "navPaneShowHidden"
    static let navPaneKey = "navPaneShown"
    static let extensionsKey = "showFileExtensions"
    static let thumbnailsKey = "showThumbnails"
    static let compactKey = "compactView"
    static let sidePaneKey = "sidePane"
    static let detailsSizeKey = "detailsSize"

    /// View > Show > File name extensions: on unless turned off.
    static var showExtensions: Bool {
        get { UserDefaults.standard.object(forKey: extensionsKey) as? Bool ?? true }
        set { set(newValue, extensionsKey) }
    }

    /// Thumbnails in the icon views; off is Explorer's "Always show icons, never thumbnails".
    static var thumbnails: Bool {
        get { UserDefaults.standard.object(forKey: thumbnailsKey) as? Bool ?? true }
        set { set(newValue, thumbnailsKey) }
    }

    /// View > Compact view: less space between items in every view.
    static var compact: Bool {
        get { UserDefaults.standard.bool(forKey: compactKey) }
        set { set(newValue, compactKey) }
    }

    /// View > Details Size: the Details list's text, icons and rows (read from the cached options, as
    /// every cell asks while it draws).
    static var detailsSize: DetailsSize {
        get { folder.detailsSize }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: detailsSizeKey)
            reload()
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// The right-hand pane: Preview (Option+P), Details (Option+Shift+P), or none.
    enum SidePane: String { case none, preview, details }

    static var sidePane: SidePane {
        get { UserDefaults.standard.string(forKey: sidePaneKey).flatMap(SidePane.init(rawValue:)) ?? .none }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: sidePaneKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static var checkboxes: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { set(newValue, key) }
    }

    /// View > Show > Hidden Items: dot files and flagged items in the list (the tree has its own box).
    static var showHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hiddenKey) }
        set { set(newValue, hiddenKey) }
    }

    /// View > Navigation Pane > Show Hidden Folders: hidden folders in the tree, off unless turned on.
    static var navPaneShowHidden: Bool {
        get { UserDefaults.standard.bool(forKey: navHiddenKey) }
        set { set(newValue, navHiddenKey) }
    }

    /// Explorer's "Expand to open folder": on unless turned off.
    static var expandToCurrent: Bool {
        get { UserDefaults.standard.object(forKey: expandKey) as? Bool ?? true }
        set { set(newValue, expandKey) }
    }

    /// View > Navigation pane.
    static var navPaneShown: Bool {
        get { UserDefaults.standard.object(forKey: navPaneKey) as? Bool ?? true }
        set { set(newValue, navPaneKey) }
    }

    static var navPaneWidth: CGFloat {
        guard let w = SidebarStore(defaults: .standard).width else { return ChassisView.sideW }
        return min(ChassisView.sideMax, max(ChassisView.sideMin, CGFloat(w)))
    }

    private static func set(_ value: Bool, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
        reload()
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: Folder Options

    private static let store = FolderOptionsStore(defaults: .standard)
    /// Every Folder Options setting, read once and again after each change (they share the keys above).
    private(set) static var folder = FolderOptionsStore(defaults: .standard).load()

    static func reload() { folder = store.load() }

    /// OK or Apply in Folder Options: saved, and every window follows.
    static func apply(_ options: FolderOptions) {
        store.save(options)
        folder = options
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

/// The milestone 3 commands of a browser window: clipboard, Copy to and Move to, Trash, delete,
/// rename (F2, batch, Tab), New, undo and redo, the selection commands and the command bar.
extension BrowserWindowController: FileListDelegate {
    /// The selected items' URLs; an item inside another selected folder (open in place) is left to its folder.
    var selectedURLs: [URL] { outermostSelectedRows.map { entries[$0].url } }
    private var folder: URL { history.current }

    // MARK: Clicks from the list

    func list(_ list: NSView, clicked row: Int, modifiers: NSEvent.ModifierFlags) {
        if renamer.isActive { renamer.cancel() }
        switch modifiers {
        case [.command, .shift]: selection.addRange(to: row)
        case .command: selection.toggle(row)
        case .shift: selection.extend(to: row)
        default: selection.click(row)
        }
        applySelection(scrollTo: row)
    }

    /// Explorer: middle-click a folder and it opens in a tab behind this one.
    func list(_ list: NSView, middleClicked row: Int) {
        guard entries.indices.contains(row), entries[row].isFolder else { return }
        openInNewTab(entries[row].url, activate: false)
    }

    func list(_ list: NSView, toggledCheckboxOf row: Int) {
        selection.toggle(row)
        applySelection(scrollTo: row)
    }

    func list(_ list: NSView, opened row: Int) {
        selection.click(row)
        applySelection(scrollTo: row)
        open(rows: IndexSet(integer: row))
    }

    func list(_ list: NSView, banded rows: IndexSet, focus: Int?) {
        if renamer.isActive { renamer.cancel() }
        selection.adopt(rows, focus: focus)
        applySelection(scroll: false)
    }

    func listToggledAll(_ list: NSView) { toggleAllFromHeader() }

    func toggleAllFromHeader() {
        if !entries.isEmpty && selection.rows.count == entries.count { selection.selectNone() } else { selection.selectAll() }
        applySelection(scroll: false)
    }

    // MARK: Selection commands

    override func selectAll(_ sender: Any?) {
        selection.selectAll()
        applySelection(scroll: false)
    }

    @objc func selectNone(_ sender: Any?) {
        selection.selectNone()
        applySelection(scroll: false)
    }

    @objc func invertSelection(_ sender: Any?) {
        selection.invert()
        applySelection(scroll: false)
    }

    @objc func toggleItemCheckBoxes(_ sender: Any?) {
        ListOptions.checkboxes.toggle()
    }

    // MARK: Clipboard

    @objc func cut(_ sender: Any?) {
        guard !selectedURLs.isEmpty else { NSSound.beep(); return }
        FileClipboard.write(selectedURLs, cut: true)
    }

    @objc func copy(_ sender: Any?) {
        guard !selectedURLs.isEmpty else { NSSound.beep(); return }
        // Inside a zip the entries are copied out first (Explorer copies them from the Compressed folder).
        if isInZip { copyOutOfZip(); return }
        FileClipboard.write(selectedURLs, cut: false)
    }

    /// Paste into the current folder: a cut moves, a copy copies (Name - Copy in the same folder).
    @objc func paste(_ sender: Any?) {
        let (urls, isCut) = FileClipboard.read()
        guard !urls.isEmpty else { NSSound.beep(); return }
        // Explorer empties the clipboard once a cut has been pasted.
        if isCut { FileClipboard.endCut() }
        OperationCenter.shared.start(isCut ? .move : .copy, sources: urls, into: folder, near: window)
    }

    @objc func copyTo(_ sender: Any?) { pickFolder(for: .copy) }
    @objc func moveTo(_ sender: Any?) { pickFolder(for: .move) }

    /// Copy to... and Move to...: a folder picker, then the job.
    private func pickFolder(for kind: JobKind) {
        let sources = selectedURLs
        guard !sources.isEmpty, let window else { NSSound.beep(); return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = kind == .copy ? "Copy" : "Move"
        panel.message = (kind == .copy ? "Copy " : "Move ") + itemsPhrase(sources) + " to:"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let target = panel.url else { return }
            MainActor.assumeIsolated {
                OperationCenter.shared.start(kind, sources: sources, into: target, near: window)
            }
        }
    }

    // MARK: Delete

    @objc func moveToTrash(_ sender: Any?) {
        guard !selectedURLs.isEmpty else { NSSound.beep(); return }
        OperationCenter.shared.trash(selectedURLs, window: window)
    }

    /// Shift+Delete: asks first, then removes for good.
    @objc func deletePermanently(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty, let window else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = urls.count == 1
            ? "Permanently delete \u{201C}\(urls[0].lastPathComponent)\u{201D}?"
            : "Permanently delete these \(urls.count) items?"
        alert.informativeText = "They will not go to the Trash, and this can't be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { OperationCenter.shared.deletePermanently(urls, window: window) }
        }
    }

    // MARK: New

    @objc func newFolder(_ sender: Any?) {
        do {
            let url = try FileOps.newFolder(in: folder)
            OperationCenter.shared.record(.newFolder(url))
            created(url)
        } catch {
            OperationCenter.shared.present(error, window: window)
        }
    }

    @objc func newTextDocument(_ sender: Any?) {
        do {
            let url = try FileOps.newTextDocument(in: folder)
            OperationCenter.shared.record(.newFile(url))
            created(url)
        } catch {
            OperationCenter.shared.present(error, window: window)
        }
    }

    /// Explorer drops a new item straight into rename.
    private func created(_ url: URL) {
        pendingRenamePath = FilePaths.itemKey(url)
        OperationCenter.shared.postChanged(select: [url])
    }

    // MARK: Rename

    @objc func renameSelection(_ sender: Any?) {
        guard !entries.isEmpty, !selection.rows.isEmpty else { NSSound.beep(); return }
        let row = selection.focus.flatMap { selection.rows.contains($0) ? $0 : nil } ?? selection.rows.first!
        let batch = selection.rows.count > 1 ? selection.rows.map { entries[$0].url } : nil
        beginRename(row: row, batch: batch)
    }

    func beginRename(row: Int, batch: [URL]?) {
        guard entries.indices.contains(row) else { return }
        scrollToItem(row)
        renameBatch = batch
        let entry = entries[row]
        if !viewMode.usesTable {
            // The icon views: the box goes over the label, as wide as the cell.
            grid.layoutSubtreeIfNeeded()
            guard let frame = grid.frame(ofItem: row), let cell = grid.cell(ofItem: row) else { return }
            let name = cell.renameRect
            let box = NSRect(x: frame.minX + name.minX, y: frame.minY + name.minY - 2, width: ThemeController.shared.isNative ? name.width : max(name.width, 160), height: 24)
            renamer.begin(in: grid, cell: box, row: row, entry: entry, textX: 5)
            return
        }
        let iconX = ListMetrics.rowLead + (tableView.showsCheckboxes ? NameCellView.boxShift + 8 : 0)
            + NameCellView.contentShift(depth: layout.depth(ofItem: row))
        let textX = iconX + ListMetrics.iconSize + 9
        renamer.begin(in: tableView, tableRow: tableRow(ofItem: row), row: row, entry: entry, textX: textX,
                      fontSize: ListMetrics.textSize, height: max(28, tableView.rowHeight + 4))
    }

    /// Enter, Tab, Shift+Tab or a click away. False keeps the box open (a name that can't be used).
    func commitRename(_ name: String, move: Int) -> Bool {
        guard let row = renamer.row, entries.indices.contains(row) else { return true }
        let entry = entries[row]
        let next = entryKeys.indices.contains(row + move) && move != 0 ? entryKeys[row + move] : nil
        let batch = renameBatch
        if name == entry.name && batch == nil {
            continueRename(at: next)
            return true
        }
        if let problem = FileNaming.problem(with: name) {
            NSSound.beep()
            statusMessage = problem.message
            updateStatus()
            return false
        }
        if batch == nil, FileNaming.changesExtension(from: entry.name, to: name, isFolder: entry.isFolder) {
            let alert = NSAlert()
            alert.messageText = "Change the extension?"
            alert.informativeText = "If you change a file name extension, the file might become unusable."
            alert.addButton(withTitle: "Change")
            alert.addButton(withTitle: "Keep editing")
            if alert.runModal() != .alertFirstButtonReturn { return false }
        }
        statusMessage = nil
        var renamed: [URL] = []
        do {
            if let batch {
                let base = FileNaming.split(name, isFolder: entry.isFolder).base
                let pairs = try FileOps.batchRename(batch, base: base)
                OperationCenter.shared.record(.rename(pairs))
                renamed = pairs.map(\.to)
            } else {
                let to = try FileOps.rename(entry.url, to: name)
                OperationCenter.shared.record(.rename([Pair(from: entry.url, to: to)]))
                renamed = [to]
            }
        } catch let partial as FileOps.BatchRenameError {
            if !partial.done.isEmpty { OperationCenter.shared.record(.rename(partial.done)) }
            OperationCenter.shared.present(partial.underlying, window: window)
            renamed = partial.done.map(\.to)
        } catch {
            NSSound.beep()
            statusMessage = (error as? FileOpError)?.message ?? error.localizedDescription
            updateStatus()
            return false
        }
        renameBatch = nil
        continueRename(at: next)
        OperationCenter.shared.postChanged(select: renamed)
        return true
    }

    /// Tab and Shift+Tab: the next or previous item in view order goes into rename once the list is back.
    private func continueRename(at path: String?) {
        renameBatch = nil
        guard let path else { return }
        pendingRenamePath = path
        if !isLoadingContents { reloadContents(select: [path]) }
    }

    private var isLoadingContents: Bool { !isIdle }

    // MARK: Undo and redo

    /// Cmd+Z: undoes typing while a name or the address is being edited, otherwise the last file operation.
    @objc func undoOperation(_ sender: Any?) {
        if let text = window?.firstResponder as? NSTextView {
            text.undoManager?.undo()
            return
        }
        OperationCenter.shared.undo(window: window)
    }

    /// Cmd+Shift+Z and Cmd+Y.
    @objc func redoOperation(_ sender: Any?) {
        if let text = window?.firstResponder as? NSTextView {
            text.undoManager?.redo()
            return
        }
        OperationCenter.shared.redo(window: window)
    }

    // MARK: Sort and share from the command bar

    @objc func sortByColumn(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let key = SortKey(rawValue: raw) else { return }
        applySort(SortSpec(key: key, ascending: sortSpec.key == key ? sortSpec.ascending : key.defaultAscending))
    }

    @objc func sortAscending(_ sender: Any?) { applySort(SortSpec(key: sortSpec.key, ascending: true, then: sortSpec.then)) }
    @objc func sortDescending(_ sender: Any?) { applySort(SortSpec(key: sortSpec.key, ascending: false, then: sortSpec.then)) }

    @objc func share(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty else { NSSound.beep(); return }
        let anchor: NSView = shareButton.flatMap { $0.isHidden ? nil : $0 } ?? listView
        let rect = anchor === listView ? (frameOfItem(selection.rows.first ?? 0) ?? listView.bounds) : anchor.bounds
        NSSharingServicePicker(items: urls).show(relativeTo: rect, of: anchor, preferredEdge: .minY)
    }

    // MARK: Menus

    func validateFileItem(_ item: NSMenuItem) -> Bool {
        if let view = validateViewItem(item) { return view }
        let editingText = window?.firstResponder is NSTextView
        let any = !selectedURLs.isEmpty
        // Home is not a folder: nothing is pasted, made or opened in it.
        if history.isHome {
            switch item.action {
            case #selector(paste(_:)), #selector(pasteShortcut(_:)), #selector(newFolder(_:)), #selector(newTextDocument(_:)),
                 #selector(openInTerminal(_:)), #selector(showFolderProperties(_:)), #selector(copyAsPath(_:)),
                 #selector(selectAll(_:)), #selector(copyAddress(_:)), #selector(copyAddressAsText(_:)):
                return false
            default: break
            }
        }
        // Inside a zip: read-only, as Explorer's Compressed folder. Open, Copy and Extract all stay.
        if isInZip {
            switch item.action {
            case #selector(cut(_:)), #selector(paste(_:)), #selector(pasteShortcut(_:)), #selector(pasteIntoFolder(_:)),
                 #selector(newFolder(_:)), #selector(newTextDocument(_:)), #selector(renameSelection(_:)), #selector(moveToTrash(_:)),
                 #selector(deletePermanently(_:)), #selector(createAlias(_:)), #selector(createSymlink(_:)), #selector(share(_:)),
                 #selector(printSelection(_:)), #selector(openInTerminal(_:)), #selector(copyTo(_:)), #selector(moveTo(_:)),
                 #selector(compressSelection(_:)), #selector(sendToCompressedFolder(_:)), #selector(showProperties(_:)),
                 #selector(showFolderProperties(_:)), #selector(toggleFavorite(_:)):
                return false
            default: break
            }
        }
        switch item.action {
        case #selector(extractAll(_:)):
            return archiveForExtract != nil && !editingText
        case #selector(compressSelection(_:)), #selector(sendToCompressedFolder(_:)):
            return any && !editingText
        case #selector(rotateRight(_:)), #selector(rotateLeft(_:)), #selector(setDesktopBackground(_:)):
            return !selectedImages.isEmpty
        case #selector(formatDrive(_:)):
            return (item.representedObject as? String).map { p in volumes.contains { $0.path == p && !$0.isRoot && $0.isLocal } }
                ?? (currentDrive.map { !$0.isRoot && $0.isLocal } ?? false)
        case #selector(checkDrive(_:)):
            return item.representedObject != nil || currentDrive != nil
        case #selector(toggleFullScreenWindow(_:)):
            item.title = window?.styleMask.contains(.fullScreen) == true ? "Exit Full Screen" : "Full Screen"
            return true
        case #selector(undoOperation(_:)):
            if editingText, let text = window?.firstResponder as? NSTextView {
                item.title = "Undo"
                return text.undoManager?.canUndo ?? false
            }
            item.title = OperationCenter.shared.undoTitle ?? "Undo"
            return OperationCenter.shared.undoTitle != nil
        case #selector(redoOperation(_:)):
            if editingText, let text = window?.firstResponder as? NSTextView {
                item.title = "Redo"
                return text.undoManager?.canRedo ?? false
            }
            item.title = OperationCenter.shared.redoTitle ?? "Redo"
            return OperationCenter.shared.redoTitle != nil
        case #selector(cut(_:)), #selector(copy(_:)):
            return any
        case #selector(copyTo(_:)), #selector(moveTo(_:)), #selector(moveToTrash(_:)), #selector(deletePermanently(_:)),
             #selector(renameSelection(_:)), #selector(share(_:)):
            // Off while text is edited, so Cmd+Delete deletes typing instead of files.
            return any && !editingText
        case #selector(paste(_:)), #selector(pasteShortcut(_:)):
            return FileClipboard.hasFiles && !editingText
        case #selector(pasteIntoFolder(_:)):
            return FileClipboard.hasFiles && selectedEntries.contains(where: \.isFolder)
        case #selector(copyPath(_:)), #selector(createAlias(_:)), #selector(createSymlink(_:)), #selector(openWithOther(_:)),
             #selector(sendToDesktop(_:)), #selector(sendToMail(_:)), #selector(sendToAirDrop(_:)), #selector(sendToFolder(_:)),
             #selector(sendToApp(_:)), #selector(openSelection(_:)), #selector(openWithApp(_:)):
            return any && !editingText
        case #selector(copyAsPath(_:)), #selector(showProperties(_:)):
            return !editingText
        case #selector(printSelection(_:)):
            return selectedEntries.contains { !$0.isFolder } && !editingText
        case #selector(openInNewWindow(_:)):
            return selectedEntries.contains(where: \.isFolder)
        case #selector(toggleQuickLook(_:)):
            return any
        case #selector(selectNone(_:)), #selector(invertSelection(_:)), #selector(selectAll(_:)):
            return !entries.isEmpty
        case #selector(toggleItemCheckBoxes(_:)):
            item.state = ListOptions.checkboxes ? .on : .off
            return true
        case #selector(toggleHiddenItems(_:)):
            item.state = ListOptions.showHidden ? .on : .off
            return true
        case #selector(toggleNavigationPane(_:)):
            item.state = ListOptions.navPaneShown ? .on : .off
            return true
        case #selector(toggleExpandToCurrent(_:)):
            item.state = ListOptions.expandToCurrent ? .on : .off
            return true
        case #selector(toggleNavPaneHidden(_:)):
            item.state = ListOptions.navPaneShowHidden ? .on : .off
            return true
        case #selector(expandToCurrentFolder(_:)):
            return !history.isHome
        case #selector(ejectCurrentVolume(_:)):
            if let v = currentEjectable { item.title = (v.isNetwork ? "Disconnect \u{201C}" : "Eject \u{201C}") + v.name + "\u{201D}" }
            else { item.title = "Eject" }
            return currentEjectable != nil
        case #selector(openSelectionInNewTab(_:)):
            return selectedEntries.contains(where: \.isFolder)
        case #selector(toggleFavorite(_:)):
            guard selectedURLs.count == 1, let url = selectedURLs.first else { return false }
            item.title = FavoritesStore(defaults: options.historyDefaults).contains(url.path) ? "Remove from Favorites" : "Add to Favorites"
            return true
        case #selector(reopenClosedTab(_:)):
            return (appDelegate?.closedTabs.count ?? 0) > 0
        case #selector(nextTab(_:)), #selector(previousTab(_:)), #selector(mergeAllWindows(_:)):
            return item.action == #selector(mergeAllWindows(_:)) ? (appDelegate?.browserControllers.count ?? 0) > 1 : tabs.count > 1
        case #selector(moveTabToNewWindow(_:)):
            return tabs.count > 1
        case #selector(restoreFromTrash(_:)):
            return isTrashView && any
        case #selector(emptyRecycleBin(_:)):
            return isTrashView
        case #selector(sortByColumn(_:)):
            item.state = (item.representedObject as? String) == sortSpec.key.rawValue ? .on : .off
            return true
        case #selector(sortAscending(_:)):
            item.state = sortSpec.ascending ? .on : .off
            return true
        case #selector(sortDescending(_:)):
            item.state = sortSpec.ascending ? .off : .on
            return true
        default:
            return true
        }
    }

    private func itemsPhrase(_ urls: [URL]) -> String {
        urls.count == 1 ? "\u{201C}\(urls[0].lastPathComponent)\u{201D}" : "\(urls.count) items"
    }

    // MARK: The command bar

    /// New, Cut, Copy, Paste, Rename, Share, Delete | Sort, View | See more, as D4 `.ib` buttons.
    func makeCommandBar() -> [ChromeButton] {
        func button(_ glyph: Glyph, _ label: String, _ action: Selector?) -> ChromeButton {
            let b = ChromeButton(glyph: glyph, label: label, target: self, action: action)
            b.iconSize = 18
            return b
        }
        let new = button(.newFolder, "New", #selector(showNewMenu(_:)))
        let cut = button(.cut, "Cut (Cmd+X)", #selector(cut(_:)))
        let copy = button(.copy, "Copy (Cmd+C)", #selector(copy(_:)))
        let paste = button(.paste, "Paste (Cmd+V)", #selector(paste(_:)))
        let rename = button(.rename, "Rename (F2)", #selector(renameSelection(_:)))
        let share = button(.share, "Share", #selector(share(_:)))
        let delete = button(.trash, "Delete", #selector(moveToTrash(_:)))
        let sort = button(.sortLines, "Sort", #selector(showSortMenu(_:)))
        let view = button(.view, "View", #selector(showViewMenu(_:)))
        let more = button(.more, "See more", #selector(showMoreMenu(_:)))
        shareButton = share
        return [new, cut, copy, paste, rename, share, delete, sort, view, more]
    }

    func updateCommandBar() {
        let any = !selection.rows.isEmpty
        let buttons = toolbar.commands
        guard buttons.count == 10 else { return }
        for i in [1, 2, 4, 5, 6] { buttons[i].isEnabled = any }
        buttons[3].isEnabled = FileClipboard.hasFiles
    }

    @objc func showNewMenu(_ sender: Any?) {
        popUp(MainMenu.newItems(), from: sender)
    }

    @objc func showSortMenu(_ sender: Any?) {
        popUp(MainMenu.sortItems(), from: sender)
    }

    /// The command bar's View: the layouts, Compact view, Show and Make this the default view.
    @objc func showViewMenu(_ sender: Any?) {
        popUp(MainMenu.viewItems(compactMenu: true), from: sender)
    }

    /// See more: the selection commands, Copy to and Move to, and everything the bar had no room for.
    @objc func showMoreMenu(_ sender: Any?) {
        var items: [NSMenuItem] = []
        let hidden = toolbar.commands.dropLast().filter(\.isHidden)
        if !hidden.isEmpty {
            for b in hidden {
                let item = NSMenuItem(title: b.toolTip ?? "", action: b.action, keyEquivalent: "")
                item.target = self
                items.append(item)
            }
            items.append(.separator())
        }
        let plain: [(String, Selector)] = [
            ("Select all", #selector(selectAll(_:))), ("Select none", #selector(selectNone(_:))),
            ("Invert selection", #selector(invertSelection(_:))),
        ]
        items += plain.map { NSMenuItem(title: $0.0, action: $0.1, keyEquivalent: "") }
        items.append(.separator())
        items += [("Copy to...", #selector(copyTo(_:))), ("Move to...", #selector(moveTo(_:))),
                  ("Delete permanently...", #selector(deletePermanently(_:)))]
            .map { NSMenuItem(title: $0.0, action: $0.1, keyEquivalent: "") }
        items.append(.separator())
        items += [("Copy as path", #selector(copyAsPath(_:))), ("Open in Terminal", #selector(openInTerminal(_:)))]
            .map { NSMenuItem(title: $0.0, action: $0.1, keyEquivalent: "") }
        items.append(.separator())
        items += [NSMenuItem(title: "Properties", action: #selector(showProperties(_:)), keyEquivalent: ""),
                  NSMenuItem(title: "Options", action: #selector(showFolderOptions(_:)), keyEquivalent: "")]
        popUp(items, from: sender)
    }

    private func popUp(_ items: [NSMenuItem], from sender: Any?) {
        let menu = NSMenu()
        menu.autoenablesItems = true
        for item in items {
            if item.action != nil, item.target == nil { item.target = self }
            menu.addItem(item)
        }
        guard let button = sender as? NSView else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }
}
