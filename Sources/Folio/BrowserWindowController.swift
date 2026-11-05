import AppKit
import FolioCore

/// Sees key presses before the table does, so Option+arrows work wherever focus is.
final class BrowserWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let controller = windowController as? BrowserWindowController,
           controller.handleKeyDown(event) {
            return
        }
        super.sendEvent(event)
    }
}

/// One window showing one folder in a Details view.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {

    private var history: NavigationHistory
    private var entries: [FileEntry] = []
    private var sortSpec = SortSpec.standard
    private var isLoading = false
    private var loadError: String?
    /// Bumped on every load or re-sort; results for an older value are dropped.
    private var requestID = 0

    private let tableView = NSTableView()
    private let pathField = NSTextField(string: "")
    private let statusField = NSTextField(labelWithString: "")
    private lazy var backButton = navButton("chevron.left", "Back", #selector(goBack(_:)))
    private lazy var forwardButton = navButton("chevron.right", "Forward", #selector(goForward(_:)))
    private lazy var upButton = navButton("arrow.up", "Up", #selector(goUp(_:)))

    private static let columns: [(key: SortKey, title: String, width: CGFloat)] = [
        (.name, "Name", 320), (.modified, "Date modified", 150), (.kind, "Type", 170), (.size, "Size", 90),
    ]
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    init(folder: URL) {
        history = NavigationHistory(start: folder)
        let window = BrowserWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 280)
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        load()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    private func buildContent(in window: NSWindow) {
        pathField.isEditable = false
        pathField.isSelectable = true
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byTruncatingTail

        for column in Self.columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.key.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = 40
            tableColumn.sortDescriptorPrototype = descriptor(for: SortSpec(key: column.key, ascending: column.key.defaultAscending))
            tableView.addTableColumn(tableColumn)
        }
        tableView.style = .fullWidth
        tableView.rowHeight = 24
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
        // After the columns exist, so saved widths and order are applied to them.
        tableView.autosaveName = "DetailsColumns"
        tableView.autosaveTableColumns = true

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let bar = NSStackView(views: [backButton, forwardButton, upButton, pathField])
        bar.orientation = .horizontal
        bar.spacing = 6

        let content = NSView()
        for view in [bar, scrollView, statusField] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusField.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 4),
            statusField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            statusField.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -10),
            statusField.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -5),
        ])
        window.contentView = content
        window.initialFirstResponder = tableView
    }

    private func navButton(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .toolbar
        button.toolTip = label
        return button
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
            let result = Result { SortEngine.sort(try FolderListing.list(folder), by: spec) }
            await self?.finishLoad(result, id: id, spec: spec, folder: folder, started: started)
        }
    }

    private func finishLoad(_ result: Result<[FileEntry], any Error>, id: Int, spec: SortSpec,
                            folder: URL, started: Date) {
        guard id == requestID else { return }
        isLoading = false
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
        Task.detached(priority: .userInitiated) { [weak self] in
            let sorted = SortEngine.sort(current, by: spec)
            await self?.finishResort(sorted, id: id, selecting: selected)
        }
    }

    private func finishResort(_ sorted: [FileEntry], id: Int, selecting selected: Set<URL>) {
        guard id == requestID else { return }
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
    }

    private func updateChrome() {
        let folder = history.current
        window?.title = FileManager.default.displayName(atPath: folder.path)
        pathField.stringValue = folder.path
        backButton.isEnabled = history.canGoBack
        forwardButton.isEnabled = history.canGoForward
        upButton.isEnabled = history.canGoUp
        updateStatus()
    }

    private func updateStatus() {
        if let loadError {
            statusField.stringValue = loadError
            return
        }
        if isLoading {
            statusField.stringValue = "Loading…"
            return
        }
        var text = entries.count == 1 ? "1 item" : "\(entries.count.formatted()) items"
        let rows = tableView.selectedRowIndexes
        if !rows.isEmpty {
            text += "     \(rows.count.formatted()) selected"
            let sizes = rows.compactMap { entries[$0].size }
            if !sizes.isEmpty {
                text += ", " + ByteCountFormatter.string(fromByteCount: sizes.reduce(0, +), countStyle: .file)
            }
        }
        statusField.stringValue = text
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
        switch (event.keyCode, modifiers) {
        case (126, .option): goUp(nil)                          // Option+Up
        case (123, .option): goBack(nil)                        // Option+Left
        case (124, .option): goForward(nil)                     // Option+Right
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

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let key = SortKey(rawValue: tableColumn.identifier.rawValue) else { return nil }
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView
            ?? makeCell(tableColumn.identifier, key: key)
        let entry = entries[row]
        switch key {
        case .name:
            cell.textField?.stringValue = entry.name
            cell.imageView?.image = NSWorkspace.shared.icon(forFile: entry.url.path)
        case .modified:
            cell.textField?.stringValue = entry.modified.map(Self.dateFormatter.string(from:)) ?? ""
        case .kind:
            cell.textField?.stringValue = entry.kind
        case .size:
            cell.textField?.stringValue = entry.size.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            } ?? "--"
        }
        return cell
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier, key: SortKey) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        if key != .name { text.textColor = .secondaryLabelColor }
        if key == .size { text.alignment = .right }
        cell.addSubview(text)
        cell.textField = text
        var leading = text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4)
        if key == .name {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
            ])
            leading = text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6)
        }
        NSLayoutConstraint.activate([
            leading,
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
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
        resort()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateStatus()
    }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.windowClosed(self)
    }
}
