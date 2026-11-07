import AppKit
import FolioCore
import UniformTypeIdentifiers

/// A dragged file for other apps: its file URL (Finder, Terminal, Mail and browsers read it) and a file
/// promise for apps that only take promises (they get a copy written where they ask).
final class FileDragProvider: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    let url: URL

    init(url: URL) {
        self.url = url
        super.init()
        let type: UTType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? .data
        fileType = type.identifier
        delegate = self
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL] + super.writableTypes(for: pasteboard)
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType,
                                 pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == .fileURL ? [] : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .fileURL ? (url as NSURL).pasteboardPropertyList(forType: type) : super.pasteboardPropertyList(forType: type)
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        url.lastPathComponent
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo destination: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

/// The drag Folio itself started: whether the right button holds it (Explorer's right-drag menu).
@MainActor
enum DragState {
    static var rightButton = false
    /// The drag pasteboard's change count after Folio last wrote it, and whether that drag was dropped in
    /// Folio. Its file promises must not outlive the drag: at quit AppKit resolves every promise still on
    /// a pasteboard Folio owns, and a promise nobody asked for blocks quitting.
    static var ownedChangeCount: Int?
    static var droppedInFolio = false

    /// Drops what Folio left on the drag pasteboard, if nothing else has written it since.
    static func releasePasteboard() {
        let pb = NSPasteboard(name: .drag)
        guard let mine = ownedChangeCount, pb.changeCount == mine else { return }
        pb.clearContents()
        ownedChangeCount = nil
    }
}

/// What every drop target in a window (the list, its folder rows, the sidebar, the crumbs) asks of
/// the window: the action for these items onto that folder, the badge, spring-loading, the drop itself.
@MainActor
protocol DropHost: AnyObject {
    func dropAction(_ info: NSDraggingInfo, onto target: URL) -> DropAction
    func dragOperation(for action: DropAction, _ info: NSDraggingInfo) -> NSDragOperation
    @discardableResult
    func performDrop(_ info: NSDraggingInfo, onto target: URL) -> Bool
    func showDropTip(_ action: DropAction, target: URL, info: NSDraggingInfo)
    func showTip(_ text: String, accentFrom: Int, info: NSDraggingInfo)
    func hideDropTip()
    /// Hovering a folder 0.8 s while dragging opens it; nil stops the clock.
    func springLoad(_ folder: URL?)
}

/// D4's `.tip`, following the drag: the action and the folder ("Move to target"), like Explorer's
/// drag tooltip.
final class DropTipView: NSView {
    var text = "" { didSet { needsDisplay = true } }
    var accentFrom = 0

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var font: NSFont { Typeface.ui(12, weight: 500) }

    func fittingSize(for text: String) -> NSSize {
        NSSize(width: ceil(textWidth(text, font: font)) + 18 + 14, height: 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        // D4's `.tip`: --tip-bg (s4), a line-2 hairline, radius 8.
        fillRounded(bounds, radius: 8, p.s4)
        strokeRounded(bounds, radius: 8, p.line2)
        Glyph.arrow.draw(in: NSRect(x: 7, y: bounds.midY - 6, width: 12, height: 12), color: p.accent.ns)
        let head = String(text.prefix(accentFrom)), tail = String(text.dropFirst(accentFrom))
        let w = drawLine(head, font: font, color: p.text2, x: 24, midY: bounds.midY)
        drawLine(tail, font: Typeface.ui(12, weight: 600), color: p.text, x: 24 + w, midY: bounds.midY)
    }
}

extension FolioTableView: NSServicesMenuRequestor {
    nonisolated func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let urls: [URL] = MainActor.assumeIsolated { listDelegate?.listSelectedURLs(self) ?? [] }
        guard !urls.isEmpty else { return false }
        pboard.clearContents()
        pboard.writeObjects(urls as [NSURL])
        pboard.addTypes([.string], owner: nil)
        pboard.setString(PathText.plain(urls), forType: .string)
        return true
    }
}

/// Every type a drop target in Folio takes: file URLs and other apps' file promises.
@MainActor
let droppableTypes: [NSPasteboard.PasteboardType] =
    [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

extension BrowserWindowController: NSDraggingSource, DropHost {
    // MARK: Dragging out

    func list(_ list: NSView, beginDragWith event: NSEvent, rightButton: Bool) {
        let rows = selection.rows
        guard !rows.isEmpty else { return }
        // Out of a zip: the entries are copied out to a temp folder first, and those files are dragged.
        var staged: [Int: URL] = [:]
        if isInZip {
            let picked = rows.filter { entries.indices.contains($0) }
            let urls = stagedFromZip(picked.map { entries[$0].url })
            for (i, url) in zip(picked, urls) { staged[i] = url }
        }
        let items: [NSDraggingItem]
        let source: NSView
        if list === grid {
            source = grid
            items = rows.compactMap { i -> NSDraggingItem? in
                guard entries.indices.contains(i) else { return nil }
                let item = NSDraggingItem(pasteboardWriter: FileDragProvider(url: staged[i] ?? entries[i].url))
                let frame = grid.frame(ofItem: i) ?? NSRect(x: 0, y: 0, width: 64, height: 64)
                item.setDraggingFrame(frame, contents: gridDragImage(i, size: frame.size))
                return item
            }
        } else {
            source = tableView
            let nameColumn = tableView.tableColumns.firstIndex { $0.identifier.rawValue == SortKey.name.rawValue } ?? 0
            items = rows.compactMap { i -> NSDraggingItem? in
                guard entries.indices.contains(i) else { return nil }
                let row = tableRow(ofItem: i)
                let item = NSDraggingItem(pasteboardWriter: FileDragProvider(url: staged[i] ?? entries[i].url))
                var frame = tableView.frameOfCell(atColumn: nameColumn, row: row)
                frame.size.width = min(frame.width, 320)
                item.setDraggingFrame(frame, contents: dragImage(row: row, column: nameColumn, size: frame.size))
                return item
            }
        }
        guard !items.isEmpty else { return }
        DragState.rightButton = rightButton
        DragState.droppedInFolio = false
        let session = source.beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .stack
        DragState.ownedChangeCount = session.draggingPasteboard.changeCount
    }

    /// A grid cell as it looks now.
    private func gridDragImage(_ i: Int, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        guard let cell = grid.cell(ofItem: i),
              let rep = cell.bitmapImageRepForCachingDisplay(in: NSRect(origin: .zero, size: size)) else { return image }
        cell.cacheDisplay(in: NSRect(origin: .zero, size: size), to: rep)
        image.addRepresentation(rep)
        return image
    }

    /// The row's name cell (icon and name) as the drag image.
    private func dragImage(row: Int, column: Int, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        guard let cell = tableView.view(atColumn: column, row: row, makeIfNecessary: false),
              let rep = cell.bitmapImageRepForCachingDisplay(in: NSRect(origin: .zero, size: size)) else { return image }
        cell.cacheDisplay(in: NSRect(origin: .zero, size: size), to: rep)
        image.addRepresentation(rep)
        return image
    }

    nonisolated func draggingSession(_ session: NSDraggingSession,
                                     sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.copy, .move, .link, .generic] : [.copy, .move, .link, .generic, .delete]
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                                     operation: NSDragOperation) {
        MainActor.assumeIsolated {
            DragState.rightButton = false
            // Landed in Folio (or nowhere): no other app will ask for the file promises.
            if DragState.droppedInFolio || operation.isEmpty { DragState.releasePasteboard() }
            hideDropTip()
            // Another app moved them away, or the Dock's Trash took them (Finder trashes file URLs
            // itself): the list catches up.
            if operation.contains(.move) || operation.contains(.generic) || operation.contains(.delete) { reloadContents() }
        }
    }

    // MARK: Dropping onto the list

    /// The folder item under the drag, or -1 for the list background (the current folder).
    private func dropRow(_ info: NSDraggingInfo) -> Int {
        let row = layout.item(atRow: tableView.row(at: tableView.convert(info.draggingLocation, from: nil))) ?? -1
        return dropTarget(row)
    }

    private func dropTarget(_ item: Int?) -> Int {
        guard let item, entries.indices.contains(item) else { return -1 }
        let e = entries[item]
        return e.isFolder || DropRules.isApp(e.url) ? item : -1
    }

    func gridValidateDrop(_ info: NSDraggingInfo, item: Int?) -> NSDragOperation {
        let target = dropTarget(item)
        let url = target >= 0 ? entries[target].url : history.current
        let action = dropAction(info, onto: url)
        dropTargetRow = action == .none ? -1 : target
        chassis.pane.isDropTarget = target < 0 && action != .none
        springLoad(target >= 0 && entries[target].isFolder ? url : nil)
        showDropTip(action, target: url, info: info)
        return dragOperation(for: action, info)
    }

    func gridAcceptDrop(_ info: NSDraggingInfo, item: Int?) -> Bool {
        let target = dropTarget(item)
        chassis.pane.isDropTarget = false
        dropTargetRow = -1
        return performDrop(info, onto: target >= 0 ? entries[target].url : history.current)
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        let target = dropRow(info)
        let url = target >= 0 ? entries[target].url : history.current
        let action = dropAction(info, onto: url)
        tableView.setDropRow(target >= 0 ? tableRow(ofItem: target) : -1, dropOperation: .on)
        dropTargetRow = action == .none ? -1 : target
        chassis.pane.isDropTarget = target < 0 && action != .none
        springLoad(target >= 0 && entries[target].isFolder ? url : nil)
        showDropTip(action, target: url, info: info)
        return dragOperation(for: action, info)
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        let target = dropRow(info)
        chassis.pane.isDropTarget = false
        dropTargetRow = -1
        return performDrop(info, onto: target >= 0 ? entries[target].url : history.current)
    }

    func listDragExited(_ list: NSView) {
        chassis.pane.isDropTarget = false
        dropTargetRow = -1
        springLoad(nil)
        hideDropTip()
    }

    func listSelectedURLs(_ list: NSView) -> [URL] { selectedURLs }

    // MARK: DropHost

    private func draggedURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    private func promises(_ info: NSDraggingInfo) -> [NSFilePromiseReceiver] {
        (info.draggingPasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver]) ?? []
    }

    /// The keys held right now (the drag may come from another app, so not this app's last event).
    private var heldKeys: DropKeys {
        let flags = NSEvent.modifierFlags
        var keys: DropKeys = []
        if flags.contains(.option) { keys.insert(.option) }
        if flags.contains(.command) { keys.insert(.command) }
        if flags.contains(.control) { keys.insert(.control) }
        return keys
    }

    func dropAction(_ info: NSDraggingInfo, onto target: URL) -> DropAction {
        // A zip browsed as a folder is read-only here.
        if ZipPath.split(target) != nil { return .none }
        let urls = draggedURLs(info)
        let keys = heldKeys
        let fromFolio = info.draggingSource is BrowserWindowController
        let rightButton = DragState.rightButton && fromFolio
        if urls.isEmpty {
            // Another app's file promise (Mail attachments, browser images): always a copy.
            return promises(info).isEmpty ? .none : (keys.contains(.control) || rightButton ? .none : .copy)
        }
        // With no key held the source's mask says what it allows; a held key is the user's choice.
        var allowed: DropAllowed = .all
        if keys.isEmpty, !fromFolio {
            let mask = info.draggingSourceOperationMask
            allowed = []
            if mask.contains(.move) || mask.contains(.generic) { allowed.insert(.move) }
            if mask.contains(.copy) { allowed.insert(.copy) }
            if mask.contains(.link) { allowed.insert(.link) }
        }
        return DropRules.action(dropping: urls, onto: target, keys: keys, rightButton: rightButton, allowed: allowed)
    }

    func dragOperation(for action: DropAction, _ info: NSDraggingInfo) -> NSDragOperation {
        let mask = info.draggingSourceOperationMask
        let wanted: [NSDragOperation] = switch action {
        case .move: [.move, .generic]
        case .copy: [.copy]
        case .alias: [.link]
        case .open: [.generic, .copy, .link]
        case .ask: [.generic, .move, .copy, .link]
        case .none: []
        }
        guard let first = wanted.first else { return [] }
        return wanted.first(where: { mask.contains($0) }) ?? first
    }

    @discardableResult
    func performDrop(_ info: NSDraggingInfo, onto target: URL) -> Bool {
        springLoad(nil)
        hideDropTip()
        if info.draggingSource is BrowserWindowController { DragState.droppedInFolio = true }
        let urls = draggedURLs(info)
        let action = dropAction(info, onto: target)
        if urls.isEmpty {
            let receivers = promises(info)
            guard action == .copy, !receivers.isEmpty else { return false }
            receivePromises(receivers, into: target)
            return true
        }
        let point = info.draggingLocation
        switch action {
        case .none:
            return false
        case .ask:
            let plain = DropRules.plainAction(dropping: urls, onto: target)
            // After the drag session has ended, so the menu tracks the mouse on its own.
            DispatchQueue.main.async { [weak self] in self?.showDropMenu(urls, onto: target, plain: plain, at: point) }
            return true
        default:
            run(action, urls, onto: target)
            return true
        }
    }

    func run(_ action: DropAction, _ urls: [URL], onto target: URL) {
        switch action {
        case .move: OperationCenter.shared.start(.move, sources: urls, into: target, near: window)
        case .copy: OperationCenter.shared.start(.copy, sources: urls, into: target, near: window)
        case .alias: OperationCenter.shared.makeLinks(.alias, to: urls, in: target, window: window)
        case .open:
            NSWorkspace.shared.open(urls, withApplicationAt: target, configuration: NSWorkspace.OpenConfiguration())
        case .ask, .none: break
        }
    }

    private func receivePromises(_ receivers: [NSFilePromiseReceiver], into folder: URL) {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) { url, error in
                let path = url.path
                DispatchQueue.main.async {
                    if let error { OperationCenter.shared.present(error, window: nil) }
                    OperationCenter.shared.postChanged(select: [URL(fileURLWithPath: path)])
                }
            }
        }
    }

    /// Explorer's right-drag menu: Move here, Copy here, Create alias here, Cancel; the plain drop in bold.
    func showDropMenu(_ urls: [URL], onto target: URL, plain: DropAction, at windowPoint: NSPoint) {
        guard let content = window?.contentView else { return }
        let menu = NSMenu(title: "Drop")
        menu.autoenablesItems = false
        menu.font = Typeface.mono(13)
        let choices: [(String, DropAction)] = [("Move here", .move), ("Copy here", .copy), ("Create alias here", .alias)]
        for (title, action) in choices {
            let item = NSMenuItem(title: title, action: #selector(dropMenuChose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = DropChoice(action: action, urls: urls, target: target)
            item.isEnabled = action != .move || DropRules.canMove(urls, into: target)
            if action == plain {
                item.attributedTitle = NSAttributedString(string: title, attributes: [.font: Typeface.mono(13, weight: 700)])
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let cancel = NSMenuItem(title: "Cancel", action: nil, keyEquivalent: "")
        cancel.isEnabled = true
        menu.addItem(cancel)
        menu.popUp(positioning: nil, at: content.convert(windowPoint, from: nil), in: content)
    }

    @objc func dropMenuChose(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? DropChoice else { return }
        run(choice.action, choice.urls, onto: choice.target)
    }

    // MARK: Badge and spring-loading

    func showDropTip(_ action: DropAction, target: URL, info: NSDraggingInfo) {
        let name = action == .open ? target.deletingPathExtension().lastPathComponent : displayName(target)
        guard let text = DropRules.badge(action, into: name) else { hideDropTip(); return }
        showTip(text, accentFrom: text.count - name.count, info: info)
    }

    func showTip(_ text: String, accentFrom: Int, info: NSDraggingInfo) {
        let tip = dropTip
        if tip.superview == nil { chassis.addSubview(tip) }
        tip.accentFrom = accentFrom
        tip.text = text
        let p = chassis.convert(info.draggingLocation, from: nil)
        let size = tip.fittingSize(for: text)
        tip.frame = NSRect(x: min(p.x + 16, chassis.bounds.width - size.width - 4), y: p.y + 18,
                           width: size.width, height: size.height)
        tip.isHidden = false
    }

    func hideDropTip() {
        dropTip.isHidden = true
    }

    func springLoad(_ folder: URL?) {
        guard folder != springTarget else { return }
        springTimer?.invalidate()
        springTimer = nil
        springTarget = folder
        guard let folder else { return }
        let timer = Timer(timeInterval: 0.8, repeats: false) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, self.springTarget == folder else { return }
                self.springTarget = nil
                self.navigate(to: folder)
            }
        }
        // Common modes: the timer must fire while the drag runs its own event loop.
        RunLoop.main.add(timer, forMode: .common)
        springTimer = timer
    }
}

/// One choice of the drop menu.
final class DropChoice: NSObject {
    let action: DropAction
    let urls: [URL]
    let target: URL

    init(action: DropAction, urls: [URL], target: URL) {
        self.action = action
        self.urls = urls
        self.target = target
    }
}
