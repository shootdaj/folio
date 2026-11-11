import AppKit
import FolioCore

/// Per-item marks the list draws that need a file read: tag colours, locked or compressed flags and
/// custom folder icons. Read for the rows on screen, kept until the next listing.
@MainActor
final class ItemDecorCache {
    static let shared = ItemDecorCache()
    private var tags: [String: [TagColor]] = [:]
    private var flags: [String: Bool] = [:]
    private var icons: [String: NSImage?] = [:]

    func clear() {
        tags = [:]
        flags = [:]
        icons = [:]
    }

    func forget(_ url: URL) {
        tags[url.path] = nil
        flags[url.path] = nil
        icons[url.path] = nil
    }

    func tagColors(_ url: URL) -> [TagColor] {
        if let known = tags[url.path] { return known }
        let colors = FileTags.read(url).map(\.color).filter { $0 != .none }
        tags[url.path] = colors
        return colors
    }

    /// Locked (uchg) or compressed (APFS/HFS compression).
    func lockedOrCompressed(_ url: URL) -> Bool {
        if let known = flags[url.path] { return known }
        var st = stat()
        let on = lstat(url.path, &st) == 0 && st.st_flags & UInt32(UF_IMMUTABLE | UF_COMPRESSED | SF_IMMUTABLE) != 0
        flags[url.path] = on
        return on
    }

    func customIcon(_ url: URL) -> NSImage? {
        if let known = icons[url.path] { return known }
        let icon = FolderIcon.hasCustomIcon(url) ? NSWorkspace.shared.icon(forFile: url.path) : nil
        icons[url.path] = icon
        return icon
    }
}

extension BrowserWindowController {
    // MARK: Folder Options in the window

    /// After OK or Apply in Folder Options (and any View menu toggle): the window follows every setting.
    func applyFolderOptions() {
        let o = ListOptions.folder
        updateChrome()
        chassis.statusShown = o.showStatusBar
        tableView.singleClickOpens = o.singleClickOpens
        chassis.sidebar.pane.setLayout(NavigationLayout(showAllFolders: o.showAllFolders, showNetwork: o.showNetwork,
                                                        showThisPC: o.showThisPC, hideEmptyDrives: o.hideEmptyDrives,
                                                        showDriveLetters: o.showDriveLetters))
        if history.isHome { homeDataChanged(Notification(name: HomeData.didChange)) }
    }

    @objc func showFolderOptions(_ sender: Any?) { FolderOptionsWindowController.show(near: window) }

    var singleClickOpens: Bool { ListOptions.folder.singleClickOpens }

    /// What a Name cell or grid cell shows beyond the listing (tags, flags, icon, tip).
    func decorate(_ cell: NameCellView, _ entry: FileEntry) {
        let o = ListOptions.folder
        let decor = ItemDecorCache.shared
        let real = !isInZip
        cell.tagColors = real ? decor.tagColors(entry.url) : []
        cell.underline = o.singleClickOpens ? o.underline : nil
        cell.isFlagDimmed = real && o.showCompressedInColour && decor.lockedOrCompressed(entry.url)
        cell.customIcon = real && entry.isFolder ? decor.customIcon(entry.url) : nil
        cell.tip = o.showPopupDescriptions ? { [weak self] in self?.infoTip(entry) } : nil
    }

    func decorate(_ cell: GridCellView, _ entry: FileEntry) {
        let o = ListOptions.folder
        let decor = ItemDecorCache.shared
        cell.showsTypeBadge = o.fileIconOnThumbnails
        cell.tagColors = isInZip ? [] : decor.tagColors(entry.url)
        cell.isFlagDimmed = !isInZip && o.showCompressedInColour && decor.lockedOrCompressed(entry.url)
        cell.tip = o.showPopupDescriptions ? { [weak self] in self?.infoTip(entry) } : nil
    }

    /// Show pop-up description: type, dimensions, size and date; a folder's contents (and size with
    /// Display file size information in folder tips).
    func infoTip(_ entry: FileEntry) -> String? {
        let folder = entry.isFolder && !isInZip ? InfoTip.summarize(folder: entry.url) : nil
        let text = InfoTip.text(for: entry, metadata: MetadataCache.shared.cached(entry), folder: folder,
                                sizes: ListOptions.folder.fileSizeInFolderTips, formatter: ColumnValues.dateText)
        return text.isEmpty ? nil : text
    }

    // MARK: Auto-refresh

    func startWatching() {
        folderWatcher = FolderWatcher { [weak self] keys in
            MainActor.assumeIsolated { self?.watchedFoldersChanged(keys) }
        }
        treeWatcher = TreeWatcher { [weak self] keys in
            MainActor.assumeIsolated { self?.treeFoldersChanged(keys) }
        }
        updateWatches()
    }

    func stopWatching() {
        folderWatcher?.stop()
        treeWatcher?.stop()
    }

    /// The folders every tab shows (not Home, not inside a zip), and the tree's roots.
    func updateWatches() {
        let folders = tabs.tabs.map(\.history.current).filter { !NavigationHistory.isHome($0) && ZipPath.split($0) == nil }
        folderWatcher?.watch(Set(folders.map(\.path)))
        let roots = Set(volumes.map(\.path) + [FileManager.default.homeDirectoryForCurrentUser.path])
        treeWatcher?.watch(roots: roots)
    }

    /// The shown tab's folder changed on disk: listed again, selection and scroll kept.
    private func watchedFoldersChanged(_ keys: Set<String>) {
        guard !history.isHome, !isInZip, !isSearching else { return }
        guard keys.contains(FilePaths.folderKey(history.current)) else { return }
        ItemDecorCache.shared.clear()
        perfLog.notice("auto-refresh: \(self.history.current.path, privacy: .public) changed on disk")
        reloadContents()
    }

    /// Folders under the tree's roots changed: nodes already read whose subfolders differ are read again.
    /// The folders are read off the main thread, and a stale node takes the read instead of a second one.
    private func treeFoldersChanged(_ keys: Set<String>) {
        let loaded = keys.filter { chassis.sidebar.pane.tree.isLoaded($0) }
        guard !loaded.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            var lists: [String: [TreeFolder]] = [:]
            for key in loaded { lists[key] = FolderTree.subfolders(of: key) }
            await self?.treeFoldersRead(lists)
        }
    }

    private func treeFoldersRead(_ lists: [String: [TreeFolder]]) {
        let pane = chassis.sidebar.pane
        var stale: Set<String> = []
        for (key, all) in lists {
            guard let cached = pane.tree.cachedChildren(of: key) else { continue }
            if Set(cached.map(\.path)) != Set(pane.tree.shown(all).map(\.path)) { stale.insert(key) }
        }
        if !stale.isEmpty { pane.refresh(folders: stale, lists: lists) }
    }

    // MARK: Access keys (Explorer's Alt)

    /// Option pressed and let go alone: the command bar's letters show (again: they go).
    func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let tap = optionTap.flagsChanged(option: flags.contains(.option), others: !flags.subtracting(.option).isEmpty,
                                         at: ProcessInfo.processInfo.systemUptime)
        guard tap, !(window?.firstResponder is NSTextView) else { return }
        setAccessKeys(!showsAccessKeys)
    }

    /// While the letters show, a letter presses its button and Esc hides them. True when used.
    func handleAccessKeyDown(_ event: NSEvent) -> Bool {
        optionTap.keyDown()
        guard showsAccessKeys else { return false }
        setAccessKeys(false)
        if event.keyCode == 53 { return true }
        let typed = event.charactersIgnoringModifiers ?? ""
        guard let key = AccessKeys.command(for: typed), let i = CommandKey.allCases.firstIndex(of: key),
              toolbar.commands.indices.contains(i) else { return false }
        let button = toolbar.commands[i]
        guard button.isEnabled, let action = button.action else { NSSound.beep(); return true }
        if !button.isHidden {
            button.performClick(nil)
        } else {
            // Folded into See more on a narrow window: the letter still runs it, its menu under See more.
            let anchor = toolbar.commands.last.flatMap { $0.isHidden ? nil : $0 } ?? button
            NSApp.sendAction(action, to: button.target, from: anchor)
        }
        return true
    }

    func setAccessKeys(_ on: Bool) {
        showsAccessKeys = on
        for (i, button) in toolbar.commands.enumerated() where CommandKey.allCases.indices.contains(i) {
            button.accessKey = on ? AccessKeys.letter(for: CommandKey.allCases[i]) : nil
        }
    }

    // MARK: Full screen (F11)

    /// View > Full screen: Ctrl+Cmd+F, and F11 when the function keys send F11.
    @objc func toggleFullScreenWindow(_ sender: Any?) { window?.toggleFullScreen(sender) }

    static var fnState: Bool? { UserDefaults(suiteName: "NSGlobalDomain")?.object(forKey: "com.apple.keyboard.fnState") as? Bool }

    // MARK: When typing into list view: type into the Search box

    /// A letter typed in the list goes to the search box when Folder Options say so.
    func typeIntoSearchBox(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard ListOptions.folder.typing == .searchBox, modifiers.subtracting(.shift).isEmpty,
              let chars = event.characters, chars.count == 1, let c = chars.unicodeScalars.first,
              CharacterSet.alphanumerics.union(.punctuationCharacters).contains(c) else { return false }
        focusSearch(nil)
        (window?.firstResponder as? NSTextView)?.insertText(chars, replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
    }

    // MARK: Tags

    /// Item menu > Tags: the seven colours (ticked when every selected item has it), the other tags in this
    /// folder, Tags... for a new one, Remove all tags.
    func tagsMenu() -> NSMenu {
        let menu = NSMenu(title: "Tags")
        menu.font = Typeface.mono(13)
        let urls = selectedURLs
        func state(_ tag: FileTag) -> NSControl.StateValue {
            switch FileTags.state(of: tag, on: urls) { case .on: .on; case .mixed: .mixed; case .off: .off }
        }
        for color in TagColor.menuOrder {
            let tag = FileTag.standard(color)
            let item = NSMenuItem(title: color.name, action: #selector(toggleTag(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [tag.name, String(color.rawValue)]
            item.image = TagDots.image(color)
            item.state = state(tag)
            menu.addItem(item)
        }
        let standard = Set(TagColor.menuOrder.map(\.name))
        let others = Set(entries.prefix(500).flatMap { e in FileTags.read(e.url) }.filter { !standard.contains($0.name) })
        if !others.isEmpty {
            menu.addItem(.separator())
            for tag in others.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                let item = NSMenuItem(title: tag.name, action: #selector(toggleTag(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = [tag.name, String(tag.color.rawValue)]
                if tag.color != .none { item.image = TagDots.image(tag.color) }
                item.state = state(tag)
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let custom = NSMenuItem(title: "Tags...", action: #selector(addCustomTag(_:)), keyEquivalent: "")
        custom.target = self
        menu.addItem(custom)
        let clear = NSMenuItem(title: "Remove all tags", action: #selector(removeAllTags(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        return menu
    }

    @objc func toggleTag(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? [String], raw.count == 2 else { return }
        let tag = FileTag(name: raw[0], color: TagColor(rawValue: Int(raw[1]) ?? 0) ?? .none)
        changeTags { try FileTags.toggle(tag, on: $0) }
    }

    @objc func addCustomTag(_ sender: Any?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Add a tag"
        alert.informativeText = "Type a tag for the selected items. Finder and tag: search see it too."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let names = MetadataWriter.parseTags(field.stringValue)
            MainActor.assumeIsolated {
                self?.changeTags { urls in
                    for name in names {
                        let tag = FileTag(name: name, color: FileTags.standardColor(for: name))
                        if FileTags.state(of: tag, on: urls) != .on { try FileTags.toggle(tag, on: urls) }
                    }
                }
            }
        }
    }

    @objc func removeAllTags(_ sender: Any?) { changeTags { urls in for u in urls { try FileTags.write([], to: u) } } }

    private func changeTags(_ change: ([URL]) throws -> Void) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        do { try change(urls) } catch { OperationCenter.shared.present(error, window: window) }
        for url in urls {
            MetadataCache.shared.invalidate(url)
            ItemDecorCache.shared.forget(url)
        }
        reloadVisibleItems()
        if arrangeKey.filters.columns.contains(.tags) || group?.key == .tags || sortSpec.terms.contains(where: { $0.key == .tags }) {
            rearrange()
        }
        selectionDidChange()
    }

    // MARK: Image commands

    var selectedImages: [URL] { isInZip ? [] : selectedURLs.filter(ImageTools.canRotate) }

    @objc func rotateRight(_ sender: Any?) { rotate(clockwise: true) }
    @objc func rotateLeft(_ sender: Any?) { rotate(clockwise: false) }

    private func rotate(clockwise: Bool) {
        let urls = selectedImages
        guard !urls.isEmpty else { NSSound.beep(); return }
        for url in urls {
            do { try ImageTools.rotate(url, clockwise: clockwise) } catch {
                OperationCenter.shared.present(error, window: window)
                break
            }
            // Thumbnails are keyed by the file's date, which the rewrite moved on.
            MetadataCache.shared.invalidate(url)
        }
        OperationCenter.shared.postChanged(select: urls)
    }

    /// Set as desktop background: every screen.
    @objc func setDesktopBackground(_ sender: Any?) {
        guard let url = selectedImages.first else { NSSound.beep(); return }
        for screen in NSScreen.screens {
            do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) } catch {
                OperationCenter.shared.present(error, window: window)
                return
            }
        }
    }

    // MARK: Cloud files: Always keep on this device, Free up space

    var selectedCloudItems: [URL] { selectedURLs.filter(CloudFiles.isUbiquitous) }

    @objc func keepOnDevice(_ sender: Any?) { cloud { try CloudFiles.keep($0) } }
    @objc func freeUpSpace(_ sender: Any?) { cloud { try CloudFiles.freeUp($0) } }

    private func cloud(_ change: (URL) throws -> Void) {
        for url in selectedCloudItems {
            do { try change(url) } catch { OperationCenter.shared.present(error, window: window); return }
        }
        reloadContents()
    }

    // MARK: Give access to: share a folder on the network (File Sharing)

    @objc func shareOnNetwork(_ sender: Any?) {
        guard let folder = selectedEntries.first(where: \.isFolder)?.url ?? (selectedURLs.isEmpty ? history.current : nil) else { return }
        let args = DriveTools.shareArguments(folder: folder.path, name: folder.lastPathComponent)
        AdminTool.run("/usr/sbin/sharing", args, window: window,
                      done: "\u{201C}\(folder.lastPathComponent)\u{201D} is shared on the network (File Sharing, SMB).")
    }

    @objc func stopSharing(_ sender: Any?) {
        guard let folder = selectedEntries.first(where: \.isFolder)?.url ?? (selectedURLs.isEmpty ? history.current : nil) else { return }
        let names = DriveTools.sharedNames(ArchiveJob.capture(["/usr/sbin/sharing", "-l"]))
        guard let name = names[folder.path] else { NSSound.beep(); return }
        AdminTool.run("/usr/sbin/sharing", DriveTools.unshareArguments(name: name), window: window, done: "Sharing stopped.")
    }

    // MARK: Drives: Format, Check for errors

    @objc func formatDrive(_ sender: Any?) {
        guard let v = driveFromMenu(sender), !v.isRoot, let window else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Format \u{201C}\(v.name)\u{201D}?"
        alert.informativeText = "Formatting will erase ALL data on this drive. To format the drive, choose a file system and a name."
        alert.alertStyle = .critical
        let name = NSTextField(string: v.name)
        name.frame = NSRect(x: 0, y: 30, width: 280, height: 24)
        let format = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        for f in DriveTools.Format.allCases {
            format.addItem(withTitle: f.title)
            format.lastItem?.representedObject = f.rawValue
        }
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
        box.addSubview(name)
        box.addSubview(format)
        alert.accessoryView = box
        alert.addButton(withTitle: "Format")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn,
                  let raw = format.selectedItem?.representedObject as? String, let f = DriveTools.Format(rawValue: raw) else { return }
            let args = DriveTools.formatArguments(volume: v.path, name: name.stringValue.isEmpty ? v.name : name.stringValue, format: f)
            MainActor.assumeIsolated {
                VolumeCenter.run("/usr/sbin/diskutil", args) { code, output in
                    if code != 0 { OperationCenter.shared.present(FileOpError.system(output), window: window) }
                    VolumeCenter.shared.refresh()
                }
            }
        }
    }

    @objc func checkDrive(_ sender: Any?) {
        guard let v = driveFromMenu(sender) else { NSSound.beep(); return }
        let window = self.window
        statusMessage = "Checking \(v.name) for errors..."
        updateStatus()
        VolumeCenter.run("/usr/sbin/diskutil", DriveTools.verifyArguments(volume: v.path)) { [weak self] code, output in
            self?.statusMessage = nil
            self?.updateStatus()
            let alert = NSAlert()
            alert.messageText = code == 0 ? "\u{201C}\(v.name)\u{201D} has no errors" : "\u{201C}\(v.name)\u{201D} needs repair"
            let tail = output.split(separator: "\n").suffix(6).joined(separator: "\n")
            alert.informativeText = code == 0 ? "diskutil verifyVolume found nothing to repair.\n\n" + tail
                : tail + "\n\nRepair it with Disk Utility's First Aid."
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
    }

    private func driveFromMenu(_ sender: Any?) -> VolumeCapacity? {
        if let path = (sender as? NSMenuItem)?.representedObject as? String { return volumes.first { $0.path == path } }
        return currentDrive
    }

    /// The drive the shown folder is the root of, or the selected drive root.
    var currentDrive: VolumeCapacity? {
        let key = FilePaths.folderKey(selectedEntries.first?.url ?? history.current)
        return volumes.first { $0.path == key }
    }
}

/// A tool that needs an administrator (File Sharing): macOS asks for the password, as Explorer's UAC does.
@MainActor
enum AdminTool {
    static func run(_ tool: String, _ args: [String], window: NSWindow?, done message: String) {
        let quoted = ([tool] + args).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let script = "do shell script \"" + quoted.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            + "\" with administrator privileges"
        VolumeCenter.run("/usr/bin/osascript", ["-e", script]) { code, output in
            let alert = NSAlert()
            alert.messageText = code == 0 ? message : "Folio couldn't change sharing"
            if code != 0 { alert.informativeText = output }
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
    }
}
