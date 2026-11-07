import AppKit
import FolioCore
import UniformTypeIdentifiers

/// Explorer's Properties dialog (Alt+Enter, here Option+Return, Cmd+I or Option+double-click), drawn
/// as a D4 panel: General, Permissions, Details, Open with and, for aliases and links, Shortcut.
/// Changes apply at once, as in Finder's Get Info. Several items show their totals and shared flags.
@MainActor
final class PropertiesWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private static var open: [PropertiesWindowController] = []

    static func show(_ urls: [URL], near anchor: NSWindow?, tab: Tab? = nil) {
        let keys = urls.map(FilePaths.itemKey)
        if let existing = open.first(where: { $0.urls.map(FilePaths.itemKey) == keys }) {
            if let tab, existing.tabs.contains(tab) { existing.select(tab) }
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = PropertiesWindowController(urls: urls)
        if let tab, controller.tabs.contains(tab) { controller.select(tab) }
        open.append(controller)
        if let w = controller.window {
            if let anchor {
                let f = anchor.frame
                let offset = CGFloat(open.count - 1) * 24
                w.setFrameTopLeftPoint(NSPoint(x: f.midX - w.frame.width / 2 + offset, y: f.maxY - 70 - offset))
            } else {
                w.center()
            }
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    enum Tab: String, CaseIterable { case general = "General", permissions = "Permissions", details = "Details",
                                         openWith = "Open with", customize = "Customize", shortcut = "Shortcut",
                                         versions = "Previous Versions" }

    private(set) var urls: [URL]
    private var infos: [ItemInfo] = []
    private let sheet = PropertySheet()
    private let header = PropertiesHeader()
    private let nameField = NSTextField(string: "")
    private var tabButtons: [Tab: SegmentButton] = [:]
    private let closeButton = OSButton("Close", glyph: .check, style: .primary)
    private var tab = Tab.general
    private var tally: FolderTally?
    private var counting = false
    private var cancel = CancelFlag()
    private var duration: Double?
    private var versionLines: [PropertySheet.Line]?
    private var tabs: [Tab] {
        guard infos.count == 1, let info = infos.first else { return [.general, .details] }
        var out: [Tab] = [.general, .permissions, .details]
        if !info.isFolder { out.append(.openWith) }
        if info.isFolder && driveVolume == nil { out.append(.customize) }
        if info.link != nil { out.append(.shortcut) }
        out.append(.versions)
        return out
    }

    private init(urls: [URL]) {
        self.urls = urls
        let window = PropertiesWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
                                      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                      backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.backgroundColor = ThemeColors.current.s2.ns
        super.init(window: window)
        window.delegate = self
        let content = PropertiesContentView()
        window.contentView = content
        content.addSubview(header)
        content.addSubview(nameField)
        content.addSubview(sheet)
        content.addSubview(closeButton)
        closeButton.onPress = { [weak self] in self?.window?.performClose(nil) }
        nameField.delegate = self
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.font = Typeface.ui(15, weight: 650)
        nameField.setAccessibilityLabel("Name")
        for t in Tab.allCases {
            let b = SegmentButton(t.rawValue) { [weak self] in self?.select(t) }
            tabButtons[t] = b
            content.addSubview(b)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged(_:)), name: ThemeController.didChange, object: nil)
        reload()
        startCounting()
        loadDuration()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Model

    private func reload() {
        infos = urls.map(ItemInfo.read)
        let title = urls.count == 1 ? (infos.first?.name ?? "") : "\(urls.count) items"
        window?.title = title + " Properties"
        header.title = title + " Properties"
        header.infos = infos
        nameField.stringValue = urls.count == 1 ? (infos.first?.name ?? "") : "\(urls.count) items selected"
        nameField.isEditable = urls.count == 1
        nameField.textColor = ThemeColors.current.text.ns
        if !tabs.contains(tab) { tab = .general }
        layout()
        build()
    }

    /// Folder contents and multi-selection totals, counted off the main thread; the numbers tick up.
    private func startCounting() {
        let needs = infos.count > 1 || infos.first?.isFolder == true
        // A whole drive is not walked: its used and free space come from the volume.
        guard needs, driveVolume == nil else { return }
        counting = true
        let roots = urls
        let single = infos.count == 1
        let flag = cancel
        Task.detached(priority: .userInitiated) { [weak self] in
            var last = 0.0
            let total = FolderCounter.count(roots, includeRoots: !single, every: 64, isCancelled: { flag.isCancelled }) { t in
                let now = ProcessInfo.processInfo.systemUptime
                guard now - last > 0.05 else { return }
                last = now
                DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.tick(t, done: false) } }
            }
            await self?.tick(total, done: true)
        }
    }

    private func tick(_ t: FolderTally, done: Bool) {
        guard !cancel.isCancelled else { return }
        if !done && !counting { return }
        tally = t
        counting = !done
        if tab == .general { build() }
    }

    private func loadDuration() {
        guard infos.count == 1, let info = infos.first, !info.isFolder,
              let type = UTType(filenameExtension: info.url.pathExtension),
              type.conforms(to: .audiovisualContent) else { return }
        let url = info.url
        Task { [weak self] in
            let d = await MediaInfo.duration(url)
            self?.duration = d
            if self?.tab == .details { self?.build() }
        }
    }

    // MARK: Layout

    private func layout() {
        guard let content = window?.contentView else { return }
        let w = content.bounds.width, h = content.bounds.height
        header.frame = NSRect(x: 0, y: 0, width: w, height: 126)
        nameField.frame = NSRect(x: 100, y: 62, width: w - 100 - 24, height: 24)
        var x: CGFloat = 24
        for t in Tab.allCases {
            guard let b = tabButtons[t] else { continue }
            b.isHidden = !tabs.contains(t)
            b.isOn = t == tab
            guard !b.isHidden else { continue }
            let bw = b.fit()
            b.frame = NSRect(x: x, y: 138, width: bw, height: 34)
            x += bw - 1
        }
        sheet.frame = NSRect(x: 0, y: 186, width: w, height: h - 186 - 72)
        let cw = closeButton.fit(minimum: 112)
        closeButton.frame = NSRect(x: w - 24 - cw, y: h - 24 - 40, width: cw, height: 40)
        content.needsDisplay = true
    }

    fileprivate func select(_ t: Tab) {
        tab = t
        layout()
        build()
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private func date(_ d: Date?) -> String { d.map(Self.dateFormatter.string(from:)) ?? "None" }

    // MARK: Tabs

    private func build() {
        switch tab {
        case .general: sheet.lines = infos.count == 1 ? general(infos[0]) : generalMulti()
        case .permissions: sheet.lines = infos.first.map(permissions) ?? []
        case .details: sheet.lines = details()
        case .openWith: sheet.lines = infos.first.map(openWith) ?? []
        case .shortcut: sheet.lines = infos.first.map(shortcut) ?? []
        case .customize: sheet.lines = infos.first.map(customize) ?? []
        case .versions: sheet.lines = infos.first.map(versions) ?? []
        }
    }

    // MARK: Customize (folders): columns per kind, and the folder's icon

    private func customize(_ info: ItemInfo) -> [PropertySheet.Line] {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = Typeface.menu()
        for preset in ColumnPreset.allCases {
            popup.addItem(withTitle: preset.title)
            popup.lastItem?.representedObject = preset.rawValue
        }
        if let now = ColumnPreset.matching(ColumnCenter.shared.set), let i = ColumnPreset.allCases.firstIndex(of: now) {
            popup.selectItem(at: i)
        }
        popup.setAccessibilityLabel("Optimize this folder for")
        let applyColumns = OSButton("Apply columns") {
            guard let raw = popup.selectedItem?.representedObject as? String, let preset = ColumnPreset(rawValue: raw) else { return }
            ColumnCenter.shared.update { $0 = preset.applied(to: $0) }
        }
        let custom = FolderIcon.hasCustomIcon(info.url)
        let change = OSButton("Change Icon...", glyph: .pics) { [weak self] in self?.chooseIcon(for: info.url) }
        let restore = OSButton("Restore Default") { [weak self] in self?.apply { try FolderIcon.clear($0) } }
        restore.isEnabled = custom
        let columns = ColumnPreset.matching(ColumnCenter.shared.set).map { $0.title } ?? "Your own columns"
        return [
            .init("Optimize for", "", control: popup, controlWidth: 220),
            .init("", "", control: applyColumns, controlWidth: applyColumns.fit(minimum: 140)),
            .init("", "Folio has one view for every folder, so this picks the Details columns for that kind of folder "
                  + "everywhere. Now: " + columns + ".", mono: false, wraps: true),
            .separator,
            .init("Folder icon", custom ? "Custom icon" : "Default folder icon", mono: false),
            .init("", "", control: change, controlWidth: change.fit(minimum: 150)),
            .init("", "", control: restore, controlWidth: restore.fit(minimum: 150)),
        ]
    }

    private func chooseIcon(for folder: URL) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use as Icon"
        panel.message = "Choose a picture for \u{201C}\(folder.lastPathComponent)\u{201D}"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let image = panel.url else { return }
            MainActor.assumeIsolated { self?.apply { try FolderIcon.set(imageAt: image, on: $0) } }
        }
    }

    // MARK: Previous Versions: saved document versions and Time Machine's local snapshots

    private func versions(_ info: ItemInfo) -> [PropertySheet.Line] {
        if let versionLines { return versionLines }
        var lines: [PropertySheet.Line] = []
        let docs = DocumentVersions.list(info.url)
        let snaps = TimeMachineSnapshots.list()
        for v in docs {
            let copy = OSButton("Copy...") { [weak self] in self?.copyVersion(from: v.url, name: info.name) }
            lines.append(.init(date(v.date), "Saved version, " + v.source, mono: false, control: copy, controlWidth: copy.fit(minimum: 90)))
        }
        for snap in snaps {
            let copy = OSButton("Copy...") { [weak self] in self?.copyFromSnapshot(snap, item: info.url) }
            lines.append(.init(date(snap.date), "Time Machine snapshot", mono: false, control: copy, controlWidth: copy.fit(minimum: 90)))
        }
        if lines.isEmpty {
            lines = [.init("", "There are no previous versions available.", mono: false),
                     .init("", "Versions apps save (Versions) and Time Machine's local snapshots show here.", mono: false, wraps: true)]
        }
        versionLines = lines
        return lines
    }

    private func copyVersion(from source: URL, name: String) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let dest = panel.url else { return }
            MainActor.assumeIsolated {
                do { try FileManager.default.copyItem(at: source, to: dest) } catch {
                    OperationCenter.shared.present(error, window: window)
                }
                OperationCenter.shared.postChanged(select: [dest])
            }
        }
    }

    /// A snapshot is mounted read-only (an administrator's password), the file copied out, unmounted.
    private func copyFromSnapshot(_ snap: LocalSnapshot, item: URL) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Copy Here"
        panel.message = "Copy \u{201C}\(item.lastPathComponent)\u{201D} as it was " + date(snap.date)
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let dest = panel.url else { return }
            let mount = "/private/tmp/folio-snapshot-\(UUID().uuidString)"
            let inside = TimeMachineSnapshots.pathInSnapshot(FilePaths.itemKey(item), mountPoint: mount)
            func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            let args = TimeMachineSnapshots.mountArguments(snapshot: snap.name, mountPoint: mount).map(q).joined(separator: " ")
            let shell = "mkdir -p \(q(mount)) && /sbin/mount_apfs \(args) && cp -Rp \(q(inside)) \(q(dest.path)); "
                + "/sbin/umount \(q(mount)); rmdir \(q(mount))"
            MainActor.assumeIsolated {
                AdminTool.run("/bin/sh", ["-c", shell], window: window, done: "Copied the version from " + snap.name + ".")
            }
        }
    }

    private func flagChecks(_ items: [ItemInfo]) -> NSView {
        let row = FlowView()
        let locked = OSCheck("Locked") { [weak self] on in self?.apply { try ItemFlags.setLocked(on, $0) } }
        let hidden = OSCheck("Hidden") { [weak self] on in self?.apply { try ItemFlags.setHidden(on, $0) } }
        for (box, tri) in [(locked, Tri.of(items.map(\.isLocked))), (hidden, Tri.of(items.map(\.isHidden)))] {
            box.isChecked = tri == .on
            box.isMixed = tri == .mixed
            box.setAccessibilityLabel(box.title)
            row.add(box, width: box.fit())
        }
        return row
    }

    private func sizeLines(file info: ItemInfo?) -> [PropertySheet.Line] {
        if let info, !info.isFolder {
            return [.init("Size", info.size.map(SelectionText.size) ?? "Unknown"),
                    .init("Size on disk", info.sizeOnDisk.map(SelectionText.size) ?? "Unknown")]
        }
        let suffix = counting ? "  counting" : ""
        guard let t = tally else { return [.init("Size", "Counting"), .init("Size on disk", "Counting"), .init("Contains", "Counting")] }
        return [.init("Size", SelectionText.size(t.bytes) + suffix),
                .init("Size on disk", SelectionText.size(t.allocated) + suffix),
                .init("Contains", SelectionText.contains(t) + suffix, live: counting)]
    }

    /// The drive when the one item is a volume's root (Explorer's drive Properties).
    private var driveVolume: VolumeCapacity? {
        guard infos.count == 1, let info = infos.first, info.isFolder, let v = VolumeCapacity.read(info.url) else { return nil }
        return v.path == info.url.standardizedFileURL.path || v.path == FilePaths.folderKey(info.url) ? v : nil
    }

    private func driveLines(_ v: VolumeCapacity) -> [PropertySheet.Line] {
        let kind = v.isNetwork ? "Network share" : v.isRoot ? "Startup disk" : v.isEjectable || v.isRemovable ? "Removable drive" : "Local disk"
        return [.init("Type", kind, mono: false), .separator,
                .init("Used space", ByteText.storage(v.used) + "  (" + ByteText.grouped(v.used) + " bytes)"),
                .init("Free space", ByteText.storage(v.free) + "  (" + ByteText.grouped(v.free) + " bytes)"),
                .init("Capacity", ByteText.storage(v.total)),
                .init("", "", control: DriveChartView(volume: v), controlWidth: 320), .separator,
                .init("Location", v.path)]
    }

    private func general(_ info: ItemInfo) -> [PropertySheet.Line] {
        if let v = driveVolume { return driveLines(v) }
        var lines: [PropertySheet.Line] = [.init("Type", info.link == .alias ? "Alias" : info.kind, mono: false)]
        if !info.isFolder {
            let app = OpenWith.defaultApp(for: info.url)?.name ?? "No app"
            let change = OSButton("Change...") { [weak self] in self?.select(.openWith) }
            lines.append(.init("Opens with", app, mono: false, control: change, controlWidth: change.fit(minimum: 96)))
        }
        lines.append(.separator)
        lines.append(.init("Location", info.location))
        lines += sizeLines(file: info.isFolder ? nil : info)
        lines.append(.separator)
        lines += [.init("Created", date(info.created)), .init("Modified", date(info.modified)),
                  .init("Last opened", date(info.lastOpened))]
        lines.append(.separator)
        lines.append(.init("Attributes", "", control: flagChecks([info]), controlWidth: 260))
        if info.isQuarantined {
            let unblock = OSCheck("Unblock") { [weak self] on in
                if on { self?.apply { try ItemFlags.unblock($0) } }
            }
            lines.append(.init("Security", "This file came from another computer and might be blocked to help protect this Mac.",
                               mono: false, wraps: true))
            lines.append(.init("", "", control: unblock, controlWidth: unblock.fit()))
        }
        return lines
    }

    private func generalMulti() -> [PropertySheet.Line] {
        let kinds = Set(infos.map(\.kind))
        let folders = Set(infos.map { FilePaths.folderKey(URL(fileURLWithPath: $0.location)) })
        var lines: [PropertySheet.Line] = [
            .init("Type", kinds.count == 1 ? "All of type " + (kinds.first ?? "") : "Multiple types", mono: false),
            .init("Location", folders.count == 1 ? "All in " + (infos.first?.location ?? "") : "Various folders"),
        ]
        lines += sizeLines(file: nil)
        lines.append(.separator)
        lines.append(.init("Attributes", "", control: flagChecks(infos), controlWidth: 260))
        return lines
    }

    private func permissions(_ info: ItemInfo) -> [PropertySheet.Line] {
        var lines: [PropertySheet.Line] = [.init("Owner", info.owner), .init("Group", info.group), .separator]
        let header = FlowView()
        for title in ["Read", "Write", "Execute"] {
            let label = LabelView(title, font: Typeface.ui(12, weight: 650), color: { $0.text2 })
            header.add(label, width: 90)
        }
        lines.append(.init("", "", control: header, controlWidth: 270))
        let p = info.permissions
        for (who, name) in [(Permissions.Who.owner, "Owner"), (.group, "Group"), (.others, "Everyone")] {
            let row = FlowView()
            for access in Permissions.Access.allCases {
                let box = OSCheck("") { [weak self] on in
                    guard let self, let current = self.infos.first?.permissions else { return }
                    self.apply { try ItemFlags.setPermissions(current.setting(who, access, on), $0) }
                }
                box.isChecked = p.allows(who, access)
                box.setAccessibilityLabel("\(name) \(["read", "write", "execute"][access.rawValue])")
                row.add(box, width: 90)
            }
            lines.append(.init(name, "", control: row, controlWidth: 270))
        }
        lines.append(.init("Mode", p.symbolic + "  (" + p.octal + ")"))
        lines.append(.separator)
        let readOnly = OSCheck("Read-only (nobody can write)") { [weak self] on in
            guard let self, let current = self.infos.first?.permissions else { return }
            self.apply { try ItemFlags.setPermissions(current.readOnly(on), $0) }
        }
        readOnly.isChecked = p.isReadOnly
        readOnly.setAccessibilityLabel("Read-only")
        lines.append(.init("", "", control: readOnly, controlWidth: readOnly.fit()))
        lines.append(.init("Access list", ACLText.entries(info.url) ?? "No access control entries", wraps: true))
        return lines
    }

    private func details() -> [PropertySheet.Line] {
        var lines: [PropertySheet.Line] = []
        if infos.count == 1, let info = infos.first {
            if let size = MediaInfo.pixelSize(info.url) {
                lines.append(.init("Dimensions", "\(size.width) \u{00D7} \(size.height) pixels"))
            }
            if let duration { lines.append(.init("Length", MediaInfo.durationText(duration))) }
            for (k, v) in MediaInfo.exif(info.url) + Spotlight.details(info.url) { lines.append(.init(k, v, wraps: true)) }
            if !lines.isEmpty { lines.append(.separator) }
        }
        let shared = infos.map { Set($0.tags) }.reduce(Set(infos.first?.tags ?? [])) { $0.intersection($1) }
        let tags = TagField(string: shared.sorted().joined(separator: ", "))
        tags.placeholderString = infos.count > 1 ? "Tags for all \(infos.count) items" : "Add tags, comma separated"
        tags.onCommit = { [weak self] text in
            let list = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            self?.apply { try ItemFlags.setTags(list, $0) }
        }
        lines.append(.init("Tags", "", control: tags, controlWidth: 320))
        if infos.count == 1, let info = infos.first, !info.isFolder {
            let remove = OSButton("Remove properties and personal information") { [weak self] in self?.removeProperties(info.url) }
            lines.append(.init("", "", control: remove, controlWidth: remove.fit()))
        }
        if infos.count == 1, let info = infos.first {
            lines.append(.separator)
            let attrs = ExtendedAttributes.list(info.url)
            if attrs.isEmpty {
                lines.append(.init("Extended attributes", "None"))
            } else {
                for (i, a) in attrs.enumerated() {
                    lines.append(.init(i == 0 ? "Extended attributes" : "", a.name + "  " + ByteText.grouped(a.size) + " B"))
                }
            }
        }
        return lines
    }

    private func openWith(_ info: ItemInfo) -> [PropertySheet.Line] {
        let apps = OpenWith.apps(for: info.url)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = Typeface.menu()
        for app in apps {
            popup.addItem(withTitle: app.name)
            let icon = NSWorkspace.shared.icon(forFile: app.url.path)
            icon.size = NSSize(width: 16, height: 16)
            popup.lastItem?.image = icon
            popup.lastItem?.representedObject = app.url
        }
        popup.setAccessibilityLabel("Open with")
        popup.target = self
        popup.action = #selector(chooseApp(_:))
        let all = OSButton("Change all...") { [weak self] in self?.changeAll(popup) }
        return [
            .init("Open with", "", control: popup, controlWidth: 300),
            .init("", "", control: all, controlWidth: all.fit(minimum: 120)),
            .init("", "Change all makes the app the Mac default for every " + info.kind + ".", mono: false, wraps: true),
        ]
    }

    private func shortcut(_ info: ItemInfo) -> [PropertySheet.Line] {
        let target = info.linkTarget
        let open = OSButton("Open file location", glyph: .forward) {
            guard let target else { return }
            (NSApp.delegate as? AppDelegate)?.openWindow(at: target.deletingLastPathComponent())
        }
        open.isEnabled = target != nil
        return [
            .init("Kind", info.link == .alias ? "Finder alias" : "Symbolic link", mono: false),
            .init("Target", target?.path ?? "Missing (the original was moved or deleted)", wraps: true),
            .init("", "", control: open, controlWidth: open.fit(minimum: 160)),
        ]
    }

    /// Explorer's Remove Properties: a clean copy, or the properties taken out of this file.
    private func removeProperties(_ url: URL) {
        guard let window else { return }
        let found = PersonalInfo.properties(of: url)
        let alert = NSAlert()
        alert.messageText = "Remove Properties"
        alert.informativeText = found.isEmpty ? "This file has no personal properties Folio can remove."
            : "Found: " + found.map { $0.name + " (" + $0.value + ")" }.joined(separator: "; ")
        let copy = NSButton(radioButtonWithTitle: "Create a copy with all possible properties removed", target: nil, action: nil)
        let here = NSButton(radioButtonWithTitle: "Remove the properties from this file", target: nil, action: nil)
        copy.state = .on
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 48))
        copy.frame = NSRect(x: 0, y: 26, width: 380, height: 20)
        here.frame = NSRect(x: 0, y: 2, width: 380, height: 20)
        // Same target and action: AppKit keeps the two radios to one choice.
        for b in [copy, here] {
            b.target = self
            b.action = #selector(radioPicked(_:))
        }
        box.addSubview(copy)
        box.addSubview(here)
        alert.accessoryView = box
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let clean = copy.state == .on
            MainActor.assumeIsolated {
                do {
                    if clean {
                        let made = try PersonalInfo.cleanCopy(of: url)
                        OperationCenter.shared.record(.created([made], title: "Remove Properties"))
                        OperationCenter.shared.postChanged(select: [made])
                    } else {
                        try PersonalInfo.remove(from: url)
                        MetadataCache.shared.invalidate(url)
                        OperationCenter.shared.postChanged(select: [url])
                    }
                } catch {
                    OperationCenter.shared.present(error, window: window)
                }
                self?.reload()
            }
        }
    }

    @objc private func radioPicked(_ sender: Any?) {}

    // MARK: Changes

    /// Runs a change on every item, reports a failure, then reads everything again.
    private func apply(_ change: (URL) throws -> Void) {
        for url in urls {
            do { try change(url) } catch {
                OperationCenter.shared.present(error, window: window)
                break
            }
        }
        reload()
        OperationCenter.shared.postChanged(select: [])
    }

    @objc private func chooseApp(_ sender: NSPopUpButton) {
        guard let app = sender.selectedItem?.representedObject as? URL, let file = urls.first else { return }
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenFileAt: file) { _ in }
    }

    private func changeAll(_ popup: NSPopUpButton) {
        guard let app = popup.selectedItem?.representedObject as? URL, let file = urls.first, let window else { return }
        let alert = NSAlert()
        alert.messageText = "Open every \(infos.first?.kind ?? "file like this") with \(popup.titleOfSelectedItem ?? "this app")?"
        alert.informativeText = "This changes the Mac default for all documents of this type."
        alert.addButton(withTitle: "Change all")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            NSWorkspace.shared.setDefaultApplication(at: app, toOpenContentTypeOfFileAt: file) { _ in }
        }
    }

    /// The name box: Enter renames (with undo), as typing a new name in Explorer's General tab does.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard urls.count == 1, let url = urls.first else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != url.lastPathComponent else { nameField.stringValue = url.lastPathComponent; return }
        do {
            let to = try FileOps.rename(url, to: name)
            OperationCenter.shared.record(.rename([Pair(from: url, to: to)]))
            urls = [to]
            OperationCenter.shared.postChanged(select: [to])
            reload()
        } catch {
            nameField.stringValue = url.lastPathComponent
            OperationCenter.shared.present(error, window: window)
        }
    }

    @objc private func themeChanged(_ note: Notification) {
        window?.backgroundColor = ThemeColors.current.s2.ns
        nameField.textColor = ThemeColors.current.text.ns
        if let content = window?.contentView { refreshTheme(in: content) }
    }

    func windowWillClose(_ notification: Notification) {
        cancel.cancel()
        NotificationCenter.default.removeObserver(self)
        Self.open.removeAll { $0 === self }
    }
}

/// Esc closes Properties.
final class PropertiesWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

/// Stops a background count when its window closes.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isCancelled: Bool { lock.withLock { flag } }
    func cancel() { lock.withLock { flag = true } }
}

/// The panel: --pop over the bg with a line-2 hairline at radius 12, drawn above everything else in it.
final class PropertiesContentView: NSView {
    private let overlay = Overlay()

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        overlay.frame = bounds
        addSubview(overlay, positioned: .above, relativeTo: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        fillRect(bounds, p.pop.over(p.bg))
    }

    private final class Overlay: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            strokeRounded(bounds, radius: 12, ThemeColors.current.line2)
        }
    }
}

/// The top of the panel: the title strip under the window's own buttons, then the big icon and the kind.
final class PropertiesHeader: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var infos: [ItemInfo] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        fillRect(NSRect(x: 0, y: 0, width: bounds.width, height: 44), p.chrome)
        fillRect(NSRect(x: 0, y: 43, width: bounds.width, height: 1), p.line)
        drawLine(title, font: Typeface.ui(14, weight: 700), color: p.text, x: 82, midY: 22,
                 maxWidth: bounds.width - 82 - 16)
        let icon = NSRect(x: 26, y: 56, width: 56, height: 56)
        if let info = infos.first {
            if infos.count > 1 {
                ItemIcon.drawFile(named: info.name, in: icon.offsetBy(dx: 8, dy: -6), palette: p)
                ItemIcon.drawFile(named: info.name, in: icon, palette: p)
            } else if info.isFolder {
                ItemIcon.drawFolder(in: NSRect(x: 22, y: 60, width: 60, height: 48), palette: p, lit: true)
            } else {
                ItemIcon.drawFile(named: info.name, in: icon, palette: p)
            }
        }
        let kind = infos.count == 1 ? (infos.first.map { $0.link == .alias ? "Alias" : $0.link == .symlink ? "Symbolic link" : $0.kind } ?? "")
            : "\(infos.count) items"
        drawLine(kind, font: Typeface.mono(12), color: p.text2, x: 102, midY: 102, maxWidth: bounds.width - 126)
        // The name box under it (the field sits on top).
        strokeRounded(NSRect(x: 94, y: 58, width: bounds.width - 94 - 18, height: 32), radius: 8, p.line2)
    }
}

/// One tab of the Properties window, a D4 tab: text-2, the chosen one in text on the thumb with the 2 pt
/// accent underline. Accessibility sees a button with its name.
final class SegmentButton: NSButton {
    var isOn = false { didSet { needsDisplay = true; setAccessibilityValue(isOn ? 1 : 0) } }
    private let onPress: () -> Void

    init(_ title: String, onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(pressed(_:))
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    @objc private func pressed(_ sender: Any?) { onPress() }

    func fit() -> CGFloat { textWidth(title, font: Typeface.ui(13, weight: 600)) + 24 }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        if isOn { fillRect(r, p.thumb) }
        if isHighlighted { fillRect(r, p.text.withAlpha(0.08)) }
        let font = Typeface.ui(13, weight: 500)
        let tw = textWidth(title, font: font)
        drawLine(title, font: font, color: isOn ? p.text : p.muted, x: (bounds.width - tw) / 2, midY: bounds.midY)
        if isOn { fillRounded(NSRect(x: 10, y: bounds.height - 2, width: bounds.width - 20, height: 2), radius: 1, p.accent) }
    }
}

/// The tab's rows: D4's `.kv` (the key as a mono uppercase label, the value in Geist Mono 12), hairlines between
/// groups, and controls (check boxes, buttons, fields) placed in the value column.
final class PropertySheet: NSView {
    struct Line {
        var key: String
        var value: String
        var mono = true
        var control: NSView?
        var controlWidth: CGFloat = 0
        var wraps = false
        var live = false
        var isSeparator = false

        init(_ key: String, _ value: String, mono: Bool = true, control: NSView? = nil, controlWidth: CGFloat = 0,
             wraps: Bool = false, live: Bool = false) {
            self.key = key
            self.value = value
            self.mono = mono
            self.control = control
            self.controlWidth = controlWidth
            self.wraps = wraps
            self.live = live
        }

        static var separator: Line {
            var l = Line("", "")
            l.isSeparator = true
            return l
        }
    }

    var lines: [Line] = [] {
        didSet {
            oldValue.compactMap(\.control).forEach { $0.removeFromSuperview() }
            lines.compactMap(\.control).forEach { addSubview($0) }
            needsLayout = true
            needsDisplay = true
            rebuildAccessibility()
        }
    }

    private static let keyX: CGFloat = 28, valueX: CGFloat = 156
    private var axElements: [NSAccessibilityElement] = []

    override var isFlipped: Bool { true }

    private func height(_ line: Line) -> CGFloat {
        if line.isSeparator { return 13 }
        if line.wraps, !line.value.isEmpty {
            let w = bounds.width - Self.valueX - 28
            let font = line.mono ? Typeface.mono(12) : Typeface.ui(13)
            let r = (line.value as NSString).boundingRect(with: NSSize(width: max(40, w), height: 400),
                                                          options: [.usesLineFragmentOrigin], attributes: [.font: font])
            return max(28, ceil(r.height) + 10)
        }
        if line.control is DriveChartView { return 112 }
        return line.control is OSButton || line.control is NSPopUpButton || line.control is TagField ? 40 : 28
    }

    private func frames() -> [NSRect] {
        var y: CGFloat = 0
        return lines.map { line in
            let h = height(line)
            defer { y += h }
            return NSRect(x: 0, y: y, width: bounds.width, height: h)
        }
    }

    /// Where a row's control starts: the value column, or after the value when the row has both
    /// ("Opens with  TextEdit  [Change...]").
    private func controlX(_ line: Line) -> CGFloat {
        guard !line.value.isEmpty else { return Self.valueX - 2 }
        let font = line.mono ? Typeface.mono(12) : Typeface.ui(13)
        return Self.valueX + ceil(textWidth(line.value, font: font)) + 16
    }

    override func layout() {
        super.layout()
        for (line, r) in zip(lines, frames()) {
            guard let c = line.control else { continue }
            let h: CGFloat = c is DriveChartView ? 100 : c is OSButton || c is NSPopUpButton || c is TagField ? 32 : 22
            let x = controlX(line)
            c.frame = NSRect(x: x, y: r.midY - h / 2, width: min(line.controlWidth, bounds.width - x - 24), height: h)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        for (line, r) in zip(lines, frames()) {
            if line.isSeparator {
                fillRect(NSRect(x: Self.keyX, y: r.midY, width: bounds.width - 2 * Self.keyX, height: 1), p.line)
                continue
            }
            let top = line.wraps ? r.minY + 14 : r.midY
            drawLine(Typeface.caption(line.key), font: Typeface.mono(11, weight: 600), color: p.muted, x: Self.keyX, midY: top,
                     maxWidth: Self.valueX - Self.keyX - 10, kern: Typeface.labelKern(11))
            guard !line.value.isEmpty else { continue }
            let font = line.mono ? Typeface.mono(12) : Typeface.ui(13)
            let color = line.live ? p.accent : p.text
            if line.wraps {
                let w = bounds.width - Self.valueX - 28
                (line.value as NSString).draw(with: NSRect(x: Self.valueX, y: r.minY + 6, width: w, height: r.height - 6),
                                              options: [.usesLineFragmentOrigin],
                                              attributes: [.font: font, .foregroundColor: color.ns])
            } else {
                drawLine(line.value, font: font, color: color, x: Self.valueX, midY: r.midY,
                         maxWidth: bounds.width - Self.valueX - 24)
            }
        }
    }

    /// Each row reads as "Key: value" to VoiceOver and to the VM scripts.
    private func rebuildAccessibility() {
        axElements = zip(lines, frames()).compactMap { line, r in
            guard !line.isSeparator, !line.key.isEmpty || !line.value.isEmpty, line.control == nil || !line.value.isEmpty else { return nil }
            let e = NSAccessibilityElement()
            e.setAccessibilityRole(.staticText)
            e.setAccessibilityLabel(line.key)
            e.setAccessibilityValue(line.value)
            e.setAccessibilityParent(self)
            e.setAccessibilityFrameInParentSpace(r)
            return e
        }
    }

    override func accessibilityChildren() -> [Any]? {
        axElements + lines.compactMap(\.control)
    }
}

/// Controls side by side in one row.
final class FlowView: NSView {
    private var widths: [CGFloat] = []
    override var isFlipped: Bool { true }

    func add(_ view: NSView, width: CGFloat) {
        addSubview(view)
        widths.append(width)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for (v, w) in zip(subviews, widths) {
            v.frame = NSRect(x: x, y: 0, width: w, height: bounds.height)
            x += w + 18
        }
    }
}

/// A line of text in a D4 face.
final class LabelView: NSView {
    private let text: String
    private let font: NSFont
    private let color: (ThemeColors) -> NSColor

    init(_ text: String, font: NSFont, color: @escaping (ThemeColors) -> NSColor) {
        self.text = text
        self.font = font
        self.color = color
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawLine(text, font: font, color: color(ThemeColors.current), x: 0, midY: bounds.midY, maxWidth: bounds.width)
    }
}

/// The Tags box: D4's field (--field, line-2, radius 8); Enter applies.
final class TagField: NSTextField, NSTextFieldDelegate {
    var onCommit: ((String) -> Void)?

    init(string: String) {
        super.init(frame: .zero)
        stringValue = string
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = Typeface.mono(12)
        textColor = ThemeColors.current.text.ns
        delegate = self
        setAccessibilityLabel("Tags")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let p = ThemeColors.current
        fillRounded(bounds, radius: 8, p.field)
        strokeRounded(bounds.insetBy(dx: 0.5, dy: 0.5), radius: 8, p.line2)
        super.draw(dirtyRect)
    }

    func controlTextDidEndEditing(_ obj: Notification) { onCommit?(stringValue) }
}

/// The access control list as text (`acl_to_text`), for the Permissions tab.
enum ACLText {
    static func entries(_ url: URL) -> String? {
        guard let acl = acl_get_link_np(url.path, ACL_TYPE_EXTENDED) else { return nil }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard let text = acl_to_text(acl, nil) else { return nil }
        defer { acl_free(text) }
        let lines = String(cString: text).split(separator: "\n").dropFirst().map { line -> String in
            // "user:UUID:name:uid:allow:read,write" -> "name allow read,write"
            let parts = line.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count >= 6 else { return String(line) }
            return "\(parts[2]) \(parts[4]) \(parts[5])"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
