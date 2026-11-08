import AppKit
import FolioCore

// MARK: - Suggestions

extension SuggestionsState {
    /// What the center knows now.
    @MainActor
    init(center: SuggestionsCenter) {
        self.init(phase: center.state, report: center.report, early: center.earlyCards, progress: center.progress,
                  failure: center.failure, lastScan: center.lastScan, pending: center.pending,
                  ignoredCount: center.ignoredCount, home: center.home)
    }
}

extension BrowserWindowController {
    /// Connects the page's controls to this window. Called beside `wireHome()`.
    func wireSuggestions() {
        let page = chassis.suggestions.page
        let center = SuggestionsCenter.shared
        page.onRescan = { center.rescan() }
        page.onScan = { center.rescan() }
        page.onStop = { center.stop() }
        page.onOpenAccessSettings = { DiskAccessPrompt.openSettings() }
        page.onScanAnyway = { center.scanAnyway() }
        page.onShowIgnored = { center.showIgnoredAgain() }
        page.onTrash = { [weak self] suggestion, item in self?.suggestionsTrash(suggestion, item: item) }
        page.onReveal = { [weak self] suggestion, item in self?.suggestionsReveal(suggestion, item: item) }
        page.onIgnore = { [weak self] suggestion, item in self?.suggestionsIgnore(suggestion, item: item) }
        page.onCard = { [weak self] section in self?.suggestionsCard(section) }
        page.menuProvider = { [weak self] suggestion, item in self?.suggestionsMenu(suggestion, item: item) }
    }

    /// The tab shows Suggestions: no listing, the list pane swaps for the Suggestions page.
    func showSuggestions() {
        requestID += 1
        isLoading = false
        loadError = nil
        statusMessage = nil
        pendingSelect = nil
        renamer.cancel()
        dropdown.close()
        let listHadFocus = window?.firstResponder === listView
        showEmptyList()
        chassis.page = .suggestions
        chassis.suggestions.page.state = SuggestionsState(center: SuggestionsCenter.shared)
        chassis.suggestions.needsLayout = true
        // If the list had the keys, the page takes them.
        if listHadFocus { window?.makeFirstResponder(chassis.suggestions.page) }
        updateChrome()
        didNavigate()
    }

    /// The status bar text of the page, for the phase the scan is in.
    var suggestionsStatusText: String {
        let center = SuggestionsCenter.shared
        return SuggestionPage.statusText(state: center.state, report: center.report, progress: center.progress, failure: center.failure)
    }

    /// F5 on the page: a new scan.
    func rescanSuggestions() { SuggestionsCenter.shared.rescan() }

    /// The center changed (progress, a report, a row that left): the page shows the new state.
    @objc func suggestionsChanged(_ note: Notification) {
        guard history.isSuggestions else { return }
        chassis.suggestions.page.state = SuggestionsState(center: SuggestionsCenter.shared)
        updateStatus()
    }

    /// The page is in front of the list: not a search that started from it.
    var showsSuggestionsPage: Bool { history.isSuggestions && !isSearching }

    // MARK: Actions

    /// Move to Trash for one row. The checks run first; nothing moves that changed since the scan.
    func suggestionsTrash(_ suggestion: Suggestion, item: SuggestionItem) {
        moveSuggestionsToTrash([suggestion], item: item)
    }

    /// The card button: the Trash card empties the Trash; any other card moves the rows shown, and no others.
    func suggestionsCard(_ section: SuggestionSection) {
        if section.kind == .trash { confirmEmptyTrash(); return }
        let center = SuggestionsCenter.shared
        let chosen = center.selection(of: section.shown)
        guard !chosen.isEmpty, let window else { NSSound.beep(); return }
        // With "Display delete confirmation" on, the trash call asks by itself, so this sheet would ask twice.
        if ListOptions.folder.confirmDelete {
            moveSuggestionsToTrash(section.shown)
            return
        }
        let alert = NSAlert()
        alert.messageText = chosen.count == 1 ? "Move 1 item to the \(PlaceNames.recycleBin)?"
            : "Move \(ByteText.grouped(chosen.count)) items to the \(PlaceNames.recycleBin)?"
        let freed = chosen.bytes > 0 ? " This frees about \(SuggestionPage.size(chosen.bytes))." : ""
        alert.informativeText = "Only the items shown in this list go." + freed + " You can undo it."
        alert.addButton(withTitle: "Move to " + PlaceNames.recycleBin)
        alert.addButton(withTitle: "Cancel")
        let shown = section.shown
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { self?.moveSuggestionsToTrash(shown) }
        }
    }

    /// The one path to the Trash: verify against the disk, take the outermost items, hide them as pending,
    /// then one undo step through the operation center.
    private func moveSuggestionsToTrash(_ suggestions: [Suggestion], item: SuggestionItem? = nil) {
        let center = SuggestionsCenter.shared
        let plan = center.trashPlan(of: suggestions, item: item)
        guard !plan.isEmpty else {
            NSSound.beep()
            // A changed file or kept copy: the page is out of date, so it scans again.
            if plan.changed > 0 || !plan.staleGroups.isEmpty { center.rescan() }
            return
        }
        let keys = plan.keys
        center.markTrashing(keys)
        OperationCenter.shared.trash(plan.urls, window: window, cancelled: { center.unmarkTrashing(keys) }, recheck: {
            // The confirmation sheet may have been open a long time: check the files again before they move.
            let again = center.trashPlan(of: suggestions, item: item, allowing: keys)
            let left = Set(again.keys)
            let dropped = keys.filter { !left.contains($0) }
            if !dropped.isEmpty { center.unmarkTrashing(dropped) }
            if again.isEmpty { NSSound.beep() }
            if again.changed > 0 || !again.staleGroups.isEmpty { center.rescan() }
            return again.urls
        })
        let count = plan.urls.count
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: count == 1 ? "Moved 1 item to the \(PlaceNames.recycleBin)"
                : "Moved \(count) items to the \(PlaceNames.recycleBin)",
            .priority: NSAccessibilityPriorityLevel.low.rawValue,
        ])
    }

    /// Reveal shows the item in its folder, selected. The Trash row opens the Trash. Return never opens a file.
    func suggestionsReveal(_ suggestion: Suggestion, item: SuggestionItem) {
        if suggestion.kind == .trash { navigate(to: item.url); return }
        navigate(to: item.url.deletingLastPathComponent(), selecting: item.id)
    }

    func suggestionsIgnore(_ suggestion: Suggestion, item: SuggestionItem) {
        guard suggestion.kind.canIgnore else { NSSound.beep(); return }
        SuggestionsCenter.shared.ignore(suggestion, item: item)
    }

    /// The right-click menu of a row. Items that do not apply to the row are left out.
    func suggestionsMenu(_ suggestion: Suggestion, item: SuggestionItem) -> NSMenu? {
        let menu = NSMenu(title: "Suggestion")
        menu.font = Typeface.menu()
        let native = ThemeController.shared.isNative
        let kept = suggestion.keep == item.url
        func add(_ title: String, symbol: String, _ run: @escaping @MainActor () -> Void) {
            let entry = NSMenuItem(title: title, action: #selector(runSuggestionMenuBlock(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = SuggestionMenuBlock(run)
            if native { entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(entry)
        }
        let busy = SuggestionsCenter.shared.pending.contains(item.id)
        if suggestion.kind.canMoveToTrash && !kept && !busy {
            add("Move to Trash", symbol: "trash") { [weak self] in self?.suggestionsTrash(suggestion, item: item) }
        }
        add(PlaceNames.reveal, symbol: "folder") { [weak self] in self?.suggestionsReveal(suggestion, item: item) }
        let folder = item.isFolder ? item.url : item.url.deletingLastPathComponent()
        add("Open in new tab", symbol: "plus.square.on.square") { [weak self] in self?.openInNewTab(folder, activate: false) }
        if suggestion.kind == .duplicates, !kept {
            add("Keep this copy instead", symbol: "checkmark.circle") { SuggestionsCenter.shared.keep(suggestion, copy: item.url) }
        }
        if suggestion.kind.canIgnore && !busy {
            add("Ignore", symbol: "eye.slash") { [weak self] in self?.suggestionsIgnore(suggestion, item: item) }
        }
        menu.addItem(.separator())
        add("Copy as path", symbol: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(PathText.quoted([item.url]), forType: .string)
        }
        add("Properties", symbol: "info.circle") { [weak self] in PropertiesWindowController.show([item.url], near: self?.window) }
        return menu
    }

    @objc func runSuggestionMenuBlock(_ sender: NSMenuItem) {
        (sender.representedObject as? SuggestionMenuBlock)?.run()
    }
}

/// A menu item's action, kept on the item.
@MainActor
final class SuggestionMenuBlock: NSObject {
    let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) { self.run = run }
}
