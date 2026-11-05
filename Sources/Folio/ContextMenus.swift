import AppKit
import FolioCore
import Quartz

/// The right-click menus (Explorer's file menu with its icon row, and the background menu) and the
/// milestone 4 commands they run: Open with, Open in Terminal, Quick Look, Copy path, Copy as path,
/// aliases, Send to, Share, Print, pins and Properties.
extension BrowserWindowController {
    // MARK: Building the menus

    func list(_ list: NSView, menuFor row: Int, event: NSEvent) -> NSMenu? {
        if renamer.isActive { renamer.cancel() }
        let extended = event.modifierFlags.contains(.shift)
        if row >= 0, entries.indices.contains(row) {
            // Explorer: right-clicking an unselected item selects it alone first.
            if !selection.rows.contains(row) {
                selection.click(row)
                applySelection(scrollTo: row)
            }
            return itemMenu(extended: extended)
        }
        selection.selectNone()
        applySelection(scroll: false)
        return backgroundMenu()
    }

    /// Shift+F10 and the Menu key: the item menu for the selection, at the focus row.
    override func showContextMenuForSelection(_ sender: Any?) {
        let shift = NSEvent.modifierFlags.contains(.shift)
        let menu = selection.rows.isEmpty ? backgroundMenu() : itemMenu(extended: shift)
        let row = selection.focus.flatMap { selection.rows.contains($0) ? $0 : nil } ?? selection.rows.first
        let at = row.flatMap(frameOfItem).map { NSPoint(x: $0.minX + 60, y: $0.maxY) } ?? NSPoint(x: 60, y: 40)
        menu.popUp(positioning: nil, at: at, in: listView)
    }

    private func styled(_ title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.font = Typeface.mono(13)
        menu.autoenablesItems = true
        return menu
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?, key: String = "",
                     mods: NSEvent.ModifierFlags = .command, object: Any? = nil, enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = action == nil ? nil : self
        item.representedObject = object
        if !enabled { item.action = nil }
        menu.addItem(item)
    }

    private func submenu(_ menu: NSMenu, _ title: String, _ items: NSMenu) {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = items
        menu.addItem(holder)
    }

    func itemMenu(extended: Bool) -> NSMenu {
        let urls = selectedURLs
        let items = selectedEntries
        let menu = styled("Item")
        let row = NSMenuItem()
        row.view = MenuIconRow(owner: self)
        menu.addItem(row)
        menu.addItem(.separator())

        let folders = items.filter(\.isFolder)
        let oneFolder = items.count == 1 && folders.count == 1
        if isTrashView {
            add(menu, "Restore", #selector(restoreFromTrash(_:)))
            menu.addItem(.separator())
        }
        add(menu, "Open", #selector(openSelection(_:)))
        if !oneFolder || items.count > 1 { submenu(menu, "Open with", openWithMenu(for: urls)) }
        if isSearching { add(menu, "Open file location", #selector(openFileLocation(_:))) }
        if !folders.isEmpty {
            add(menu, "Open in new tab", #selector(openSelectionInNewTab(_:)))
            add(menu, "Open in new window", #selector(openInNewWindow(_:)))
            add(menu, "Open in Terminal", #selector(openInTerminal(_:)))
        }
        // No Space key equivalent here: a space typed to find an item by name would open Quick Look.
        add(menu, "Quick Look", #selector(toggleQuickLook(_:)))
        if oneFolder, let path = folders.first?.url.path {
            if pins.isPinned(path) {
                add(menu, "Unpin from Quick access", #selector(unpinFolder(_:)), object: path)
            } else {
                add(menu, "Pin to Quick access", #selector(pinFolder(_:)), object: path)
            }
        }
        if items.count == 1, let path = urls.first?.path {
            let starred = FavoritesStore(defaults: options.historyDefaults).contains(path)
            add(menu, starred ? "Remove from Favorites" : "Add to Favorites", #selector(toggleFavorite(_:)))
        }
        menu.addItem(.separator())
        add(menu, "Cut", #selector(cut(_:)), key: "x")
        add(menu, "Copy", #selector(copy(_:)), key: "c")
        if oneFolder { add(menu, "Paste into folder", #selector(pasteIntoFolder(_:)), key: "v") }
        add(menu, "Copy path", #selector(copyPath(_:)))
        add(menu, "Copy as path", #selector(copyAsPath(_:)), key: "c", mods: [.command, .shift])
        menu.addItem(.separator())
        add(menu, "Create alias", #selector(createAlias(_:)), key: "a", mods: [.command, .control])
        add(menu, "Create symbolic link", #selector(createSymlink(_:)))
        add(menu, "Rename", #selector(renameSelection(_:)), key: String(utf16CodeUnits: [unichar(NSF2FunctionKey)], count: 1), mods: [])
        add(menu, "Move to Trash", #selector(moveToTrash(_:)), key: "\u{8}")
        // Explorer's Shift+right-click extended menu; holding Shift with the menu open swaps it in too.
        let delete = NSMenuItem(title: "Delete permanently...", action: #selector(deletePermanently(_:)), keyEquivalent: "\u{8}")
        delete.keyEquivalentModifierMask = [.command, .shift]
        delete.target = self
        delete.isAlternate = !extended
        menu.addItem(delete)
        menu.addItem(.separator())
        let share = NSSharingServicePicker(items: urls).standardShareMenuItem
        share.title = "Share"
        menu.addItem(share)
        submenu(menu, "Send to", sendToMenu(extended: extended))
        let compress = NSMenuItem(title: "Compress to ZIP file", action: nil, keyEquivalent: "")
        compress.toolTip = "Arrives with milestone 8"
        menu.addItem(compress)
        add(menu, "Print", #selector(printSelection(_:)))
        menu.addItem(.separator())
        add(menu, "Properties", #selector(showProperties(_:)), key: "\r", mods: .option)
        return menu
    }

    func backgroundMenu() -> NSMenu {
        let menu = styled("Background")
        if isSearching {
            add(menu, "Save search", #selector(saveSearch(_:)))
            menu.addItem(.separator())
        }
        let view = styled("View")
        for item in MainMenu.viewItems(compactMenu: true) { view.addItem(item) }
        submenu(menu, "View", view)
        let sort = styled("Sort by")
        for item in MainMenu.sortItems() {
            if item.action != nil { item.target = self }
            sort.addItem(item)
        }
        submenu(menu, "Sort by", sort)
        let group = styled("Group by")
        for item in MainMenu.groupItems() {
            if item.action != nil { item.target = self }
            group.addItem(item)
        }
        submenu(menu, "Group by", group)
        add(menu, "Refresh", #selector(refresh(_:)), key: String(utf16CodeUnits: [unichar(NSF5FunctionKey)], count: 1), mods: [])
        menu.addItem(.separator())
        add(menu, "Paste", #selector(paste(_:)), key: "v")
        add(menu, "Paste shortcut", #selector(pasteShortcut(_:)))
        add(menu, OperationCenter.shared.undoTitle ?? "Undo", #selector(undoOperation(_:)), key: "z")
        add(menu, OperationCenter.shared.redoTitle ?? "Redo", #selector(redoOperation(_:)), key: "z", mods: [.command, .shift])
        menu.addItem(.separator())
        let new = styled("New")
        for item in MainMenu.newItems() { item.target = self; new.addItem(item) }
        submenu(menu, "New", new)
        add(menu, "Open in Terminal", #selector(openInTerminal(_:)))
        if isTrashView { add(menu, "Empty Recycle Bin", #selector(emptyRecycleBin(_:))) }
        let here = history.current.path
        if pins.isPinned(here) {
            add(menu, "Unpin from Quick access", #selector(unpinFolder(_:)), object: here)
        } else {
            add(menu, "Pin to Quick access", #selector(pinFolder(_:)), object: here)
        }
        menu.addItem(.separator())
        add(menu, "Properties", #selector(showFolderProperties(_:)))
        return menu
    }

    /// Open with: the apps Launch Services lists for the first item (its default first), then Other...
    private func openWithMenu(for urls: [URL]) -> NSMenu {
        let menu = styled("Open with")
        guard let first = urls.first else { return menu }
        let apps = OpenWith.apps(for: first)
        let standard = OpenWith.defaultApp(for: first)
        for app in apps {
            let item = NSMenuItem(title: app == standard ? app.name + " (default)" : app.name,
                                  action: #selector(openWithApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.url
            let icon = NSWorkspace.shared.icon(forFile: app.url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
            if app == standard && apps.count > 1 { menu.addItem(.separator()) }
        }
        if !apps.isEmpty { menu.addItem(.separator()) }
        add(menu, "Other...", #selector(openWithOther(_:)))
        return menu
    }

    /// Send to: Desktop (as an alias), Mail recipient, AirDrop, Compressed folder, the other drives,
    /// then your own targets from Folio's Send To folder.
    private func sendToMenu(extended: Bool) -> NSMenu {
        let menu = styled("Send to")
        add(menu, "Desktop (create alias)", #selector(sendToDesktop(_:)))
        add(menu, "Mail recipient", #selector(sendToMail(_:)))
        add(menu, "AirDrop", #selector(sendToAirDrop(_:)))
        let zip = NSMenuItem(title: "Compressed (zipped) folder", action: nil, keyEquivalent: "")
        zip.toolTip = "Arrives with milestone 8"
        menu.addItem(zip)
        let here = VolumeCapacity.read(history.current)?.path
        let drives = volumes.filter { $0.path != here && $0.isLocal }
        if !drives.isEmpty {
            menu.addItem(.separator())
            for drive in drives { add(menu, drive.name, #selector(sendToFolder(_:)), object: URL(fileURLWithPath: drive.path)) }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let mine = SendTo.targets(in: SendTo.folder(home: home))
        // Explorer's Shift+right-click adds the pinned folders.
        let pinned = extended ? pins.places.map { SendTarget(name: $0.title, url: URL(fileURLWithPath: $0.path), isApp: false) } : []
        if !mine.isEmpty || !pinned.isEmpty {
            menu.addItem(.separator())
            for target in mine + pinned {
                add(menu, target.name, target.isApp ? #selector(sendToApp(_:)) : #selector(sendToFolder(_:)), object: target.url)
            }
        }
        menu.addItem(.separator())
        add(menu, "Open Send To folder", #selector(openSendToFolder(_:)))
        return menu
    }

    // MARK: Commands

    @objc func openSelection(_ sender: Any?) { open(rows: selection.rows) }

    @objc func openInNewWindow(_ sender: Any?) {
        for entry in selectedEntries where entry.isFolder {
            (NSApp.delegate as? AppDelegate)?.openWindow(at: entry.url)
        }
    }

    /// The selected folders, or the current one from the background menu or the address bar.
    @objc func openInTerminal(_ sender: Any?) {
        let folders = selectedEntries.filter(\.isFolder).map(\.url)
        openTerminal(at: folders.isEmpty ? [history.current] : folders)
    }

    func openTerminal(at folders: [URL]) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(folders, withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func openWithApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(selectedURLs, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Choose another app, with Explorer's "Always use this app" box: ticked, it becomes the Mac default.
    @objc func openWithOther(_ sender: Any?) {
        let urls = selectedURLs
        guard let first = urls.first, let window else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Open"
        panel.message = "Choose an app to open \u{201C}\(first.lastPathComponent)\u{201D}"
        let always = NSButton(checkboxWithTitle: "Always open files like this with the app", target: nil, action: nil)
        always.sizeToFit()
        let box = NSView(frame: NSRect(x: 0, y: 0, width: always.frame.width + 40, height: always.frame.height + 16))
        always.frame.origin = NSPoint(x: 20, y: 8)
        box.addSubview(always)
        panel.accessoryView = box
        panel.isAccessoryViewDisclosed = true
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let app = panel.url else { return }
            MainActor.assumeIsolated {
                if always.state == .on {
                    NSWorkspace.shared.setDefaultApplication(at: app, toOpenContentTypeOfFileAt: first) { _ in }
                }
                NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    /// Paste into the selected folder (the item menu on a folder).
    @objc func pasteIntoFolder(_ sender: Any?) {
        guard let target = selectedEntries.first(where: \.isFolder)?.url else { return }
        let (urls, isCut) = FileClipboard.read()
        guard !urls.isEmpty else { NSSound.beep(); return }
        if isCut { FileClipboard.endCut() }
        OperationCenter.shared.start(isCut ? .move : .copy, sources: urls, into: target, near: window)
    }

    @objc func copyPath(_ sender: Any?) { putText(PathText.plain(selectedURLs)) }

    /// Explorer's Ctrl+Shift+C (Cmd+Shift+C here): the quoted paths, one per line.
    @objc func copyAsPath(_ sender: Any?) {
        let urls = selectedURLs.isEmpty ? [history.current] : selectedURLs
        putText(PathText.quoted(urls))
    }

    private func putText(_ text: String) {
        guard !text.isEmpty else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func createAlias(_ sender: Any?) { makeLinks(.alias) }
    @objc func createSymlink(_ sender: Any?) { makeLinks(.symlink) }

    /// Explorer's Create shortcut: next to the items, or on the Desktop when this folder is read-only.
    private func makeLinks(_ kind: LinkKind) {
        let urls = selectedURLs
        guard !urls.isEmpty else { NSSound.beep(); return }
        var folder = history.current
        if !FileManager.default.isWritableFile(atPath: folder.path) {
            folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        }
        OperationCenter.shared.makeLinks(kind, to: urls, in: folder, window: window)
    }

    /// Paste shortcut: aliases of the copied items in this folder.
    @objc func pasteShortcut(_ sender: Any?) {
        let (urls, _) = FileClipboard.read()
        guard !urls.isEmpty else { NSSound.beep(); return }
        OperationCenter.shared.makeLinks(.alias, to: urls, in: history.current, window: window)
    }

    @objc func sendToDesktop(_ sender: Any?) {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        OperationCenter.shared.makeLinks(.alias, to: selectedURLs, in: desktop, window: window)
    }

    @objc func sendToMail(_ sender: Any?) { perform(.composeEmail) }
    @objc func sendToAirDrop(_ sender: Any?) { perform(.sendViaAirDrop) }

    private func perform(_ name: NSSharingService.Name) {
        let urls = selectedURLs
        guard let service = NSSharingService(named: name), service.canPerform(withItems: urls) else { NSSound.beep(); return }
        service.perform(withItems: urls)
    }

    @objc func sendToFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? URL else { return }
        OperationCenter.shared.start(.copy, sources: selectedURLs, into: folder, near: window)
    }

    @objc func sendToApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(selectedURLs, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func openSendToFolder(_ sender: Any?) {
        let folder = SendTo.folder(home: FileManager.default.homeDirectoryForCurrentUser)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        (NSApp.delegate as? AppDelegate)?.openWindow(at: folder)
    }

    /// PDFs, text and images to lp; other documents to their app's print command.
    @objc func printSelection(_ sender: Any?) {
        let urls = selectedEntries.filter { !$0.isFolder }.map(\.url)
        guard !urls.isEmpty else { NSSound.beep(); return }
        let lp = urls.filter { PrintRoute.route(for: $0) == .lp }
        let apps = urls.filter { PrintRoute.route(for: $0) == .app }
        for url in apps {
            let items = [url] as CFArray
            var spec = LSLaunchURLSpec(appURL: nil, itemURLs: Unmanaged.passUnretained(items), passThruParams: nil,
                                       launchFlags: .andPrint, asyncRefCon: nil)
            LSOpenFromURLSpec(&spec, nil)
            withExtendedLifetime(items) {}
        }
        guard !lp.isEmpty else { return }
        let window = self.window
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/lp")
            process.arguments = PrintRoute.lpArguments(lp)
            let err = Pipe()
            process.standardError = err
            process.standardOutput = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {}
            let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let failed = process.terminationStatus != 0
            await MainActor.run {
                if failed {
                    OperationCenter.shared.present(FileOpError.system(message.isEmpty ? "lp could not print." : message), window: window)
                }
            }
        }
    }

    @objc func pinFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        pins.pin(path)
        PinsChanged.post()
    }

    @objc func unpinFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        pins.unpin(path)
        PinsChanged.post()
    }

    // MARK: Properties

    /// Option+Return (Explorer's Alt+Enter), Cmd+I, Option+double-click, the menus.
    @objc func showProperties(_ sender: Any?) {
        let urls = selectedURLs
        PropertiesWindowController.show(urls.isEmpty ? [history.current] : urls, near: window)
    }

    @objc func showFolderProperties(_ sender: Any?) {
        PropertiesWindowController.show([history.current], near: window)
    }

    func list(_ list: NSView, showPropertiesOf row: Int) {
        selection.click(row)
        applySelection(scrollTo: row)
        showProperties(nil)
    }

    // MARK: Quick Look (Space)

    @objc func toggleQuickLook(_ sender: Any?) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            quickLookItems = selectedURLs
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }
}

extension BrowserWindowController: QLPreviewPanelDelegate {
    /// The arrow keys in Quick Look walk the list, as in Finder: the next item is selected and previewed.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let key = event.keyCode
        return MainActor.assumeIsolated {
            guard quickLookItems.count <= 1 else { return false }
            let grid = !viewMode.usesTable
            let line = grid ? self.grid.itemsPerLine : 1
            switch key {
            case 125: moveSelection(grid && line > 1 && !self.grid.isHorizontal ? .pageDown(line) : .down, extend: false)
            case 126: moveSelection(grid && line > 1 && !self.grid.isHorizontal ? .pageUp(line) : .up, extend: false)
            case 124 where grid: moveSelection(self.grid.isHorizontal ? .pageDown(line) : .down, extend: false)
            case 123 where grid: moveSelection(self.grid.isHorizontal ? .pageUp(line) : .up, extend: false)
            default: return false
            }
            return true
        }
    }
}

extension BrowserWindowController: QLPreviewPanelDataSource {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { quickLookItems.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { quickLookItems[index] as NSURL }
    }
}

/// Pins changed in one window: every window's sidebar redraws its Quick access.
@MainActor
enum PinsChanged {
    static let name = Notification.Name("FolioPinsChanged")
    static func post() { NotificationCenter.default.post(name: name, object: nil) }
}

/// The icon row at the top of the item menu (Windows 11's Cut, Copy, Paste, Rename, Share, Delete),
/// drawn the D1 way: stroke icons with the hover state layer and brackets, the name of the one under
/// the pointer at the right.
final class MenuIconRow: NSView {
    private struct Action { let glyph: Glyph; let name: String; let selector: Selector }
    private let actions: [Action] = [
        Action(glyph: .cut, name: "Cut", selector: #selector(BrowserWindowController.cut(_:))),
        Action(glyph: .copy, name: "Copy", selector: #selector(BrowserWindowController.copy(_:))),
        Action(glyph: .paste, name: "Paste", selector: #selector(BrowserWindowController.paste(_:))),
        Action(glyph: .rename, name: "Rename", selector: #selector(BrowserWindowController.renameSelection(_:))),
        Action(glyph: .share, name: "Share", selector: #selector(BrowserWindowController.share(_:))),
        Action(glyph: .trash, name: "Delete", selector: #selector(BrowserWindowController.moveToTrash(_:))),
    ]
    private weak var owner: BrowserWindowController?
    private var hovered: Int?
    private static let cell: CGFloat = 36, lead: CGFloat = 10

    init(owner: BrowserWindowController) {
        self.owner = owner
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        setAccessibilityRole(.group)
        setAccessibilityLabel("Cut, Copy, Paste, Rename, Share, Delete")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private func rect(_ i: Int) -> NSRect {
        NSRect(x: Self.lead + CGFloat(i) * Self.cell, y: 2, width: Self.cell, height: Self.cell)
    }

    private func enabled(_ i: Int) -> Bool {
        guard let owner else { return false }
        let item = NSMenuItem(title: "", action: actions[i].selector, keyEquivalent: "")
        return owner.validateMenuItem(item)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func index(at event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        return actions.indices.first { rect($0).contains(p) }
    }

    override func mouseMoved(with event: NSEvent) { setHovered(index(at: event)) }
    override func mouseExited(with event: NSEvent) { setHovered(nil) }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard let i = index(at: event), enabled(i), let owner else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        let selector = actions[i].selector
        DispatchQueue.main.async { NSApp.sendAction(selector, to: owner, from: owner.shareButton) }
    }

    private func setHovered(_ i: Int?) {
        guard i != hovered else { return }
        hovered = i
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        for i in actions.indices {
            let r = rect(i)
            let on = enabled(i)
            if hovered == i && on {
                fillRounded(r, radius: 5, p.txt.withAlpha(0.08))
                drawBrackets(r, color: p.bracket.ns, length: 7)
            }
            let s: CGFloat = 18
            actions[i].glyph.draw(in: NSRect(x: r.midX - s / 2, y: r.midY - s / 2, width: s, height: s),
                                  color: p.txt.withAlpha(on ? 1 : 0.34).ns)
        }
        if let hovered {
            drawLine(actions[hovered].name, font: Typeface.mono(12), color: p.txt2, x: bounds.maxX - 12,
                     midY: rect(0).midY, alignRight: true)
        }
    }
}

/// Quick access edits from the sidebar, its menu, and the address bar's commands.
extension BrowserWindowController {
    @objc func pinsChanged(_ note: Notification) {
        chassis.sidebar.pane.setPlaces(pins.places)
        if !history.isHome, ListOptions.expandToCurrent { revealCurrentFolder(select: false) }
        homeDataChanged(note)
    }

    func editPins(_ edit: PinEdit) {
        switch edit {
        case .pin(let path, let at): pins.pin(path, at: at)
        case .move(let from, let to): pins.move(from: from, to: to)
        case .unpin(let path): pins.unpin(path)
        }
        PinsChanged.post()
    }

    /// terminal, cmd, wt: Terminal in this folder; notepad, calc or an app's name: that app.
    func runAddressCommand(_ command: AddressCommand) -> Bool {
        switch command {
        case .terminal:
            openTerminal(at: [history.current])
            return true
        case .app(let name):
            if name.lowercased() == "folio" {
                (NSApp.delegate as? AppDelegate)?.openWindow(at: history.current)
                return true
            }
            guard let app = AddressCommand.findApp(named: name, in: AddressCommand.appFolders) else { return false }
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            return true
        }
    }
}
