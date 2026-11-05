import AppKit
import FolioCore

/// View > Item check boxes, off by default, saved under `itemCheckBoxes`.
@MainActor
enum ListOptions {
    static let didChange = Notification.Name("FolioListOptionsDidChange")
    private static let key = "itemCheckBoxes"

    static var checkboxes: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}

/// The milestone 3 commands of a browser window: clipboard, Copy to and Move to, Trash, delete,
/// rename (F2, batch, Tab), New, undo and redo, the selection commands and the command bar.
extension BrowserWindowController: FileListDelegate {
    var selectedURLs: [URL] { selectedEntries.map(\.url) }
    private var folder: URL { history.current }

    // MARK: Clicks from the list

    func list(_ list: FolioTableView, clicked row: Int, modifiers: NSEvent.ModifierFlags) {
        if renamer.isActive { renamer.cancel() }
        switch modifiers {
        case [.command, .shift]: selection.addRange(to: row)
        case .command: selection.toggle(row)
        case .shift: selection.extend(to: row)
        default: selection.click(row)
        }
        applySelection(scrollTo: row)
    }

    func list(_ list: FolioTableView, toggledCheckboxOf row: Int) {
        selection.toggle(row)
        applySelection(scrollTo: row)
    }

    func list(_ list: FolioTableView, opened row: Int) {
        selection.click(row)
        applySelection(scrollTo: row)
        open(rows: IndexSet(integer: row))
    }

    func list(_ list: FolioTableView, banded rows: IndexSet, focus: Int?) {
        if renamer.isActive { renamer.cancel() }
        selection.adopt(rows, focus: focus)
        applySelection(scroll: false)
    }

    func listToggledAll(_ list: FolioTableView) { toggleAllFromHeader() }

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
        tableView.scrollRowToVisible(row)
        renameBatch = batch
        let entry = entries[row]
        let iconX = ListMetrics.rowLead + 6 + 8 + (tableView.showsCheckboxes ? NameCellView.boxShift : 0)
        let textX = iconX + (entry.isFolder ? 18 : 15) + 8
        renamer.begin(in: tableView, row: row, entry: entry, textX: textX)
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

    @objc func sortAscending(_ sender: Any?) { applySort(SortSpec(key: sortSpec.key, ascending: true)) }
    @objc func sortDescending(_ sender: Any?) { applySort(SortSpec(key: sortSpec.key, ascending: false)) }

    private func applySort(_ spec: SortSpec) {
        guard spec != sortSpec else { return }
        tableView.sortDescriptors = [NSSortDescriptor(key: spec.key.rawValue, ascending: spec.ascending)]
    }

    @objc func share(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty else { NSSound.beep(); return }
        let anchor: NSView = shareButton.flatMap { $0.isHidden ? nil : $0 } ?? tableView
        let rect = anchor === tableView ? tableView.rect(ofRow: selection.rows.first ?? 0) : anchor.bounds
        NSSharingServicePicker(items: urls).show(relativeTo: rect, of: anchor, preferredEdge: .minY)
    }

    // MARK: Menus

    func validateFileItem(_ item: NSMenuItem) -> Bool {
        let editingText = window?.firstResponder is NSTextView
        let any = !selectedURLs.isEmpty
        switch item.action {
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
        case #selector(paste(_:)):
            return FileClipboard.hasFiles
        case #selector(selectNone(_:)), #selector(invertSelection(_:)), #selector(selectAll(_:)):
            return !entries.isEmpty
        case #selector(toggleItemCheckBoxes(_:)):
            item.state = ListOptions.checkboxes ? .on : .off
            return true
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

    /// New, Cut, Copy, Paste, Rename, Share, Delete | Sort, View | See more, as D1 toolbar buttons.
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

    @objc func showViewMenu(_ sender: Any?) {
        let details = NSMenuItem(title: "Details", action: nil, keyEquivalent: "")
        details.state = .on
        popUp([details, .separator(),
               NSMenuItem(title: "Item check boxes", action: #selector(toggleItemCheckBoxes(_:)), keyEquivalent: "")], from: sender)
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
        // Properties arrives with milestone 4 and Folder Options later; they show where Explorer has them.
        items += ["Properties", "Options"].map { NSMenuItem(title: $0, action: nil, keyEquivalent: "") }
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
