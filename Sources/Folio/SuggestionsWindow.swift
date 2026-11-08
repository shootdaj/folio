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

    // MARK: Actions. Slice B6 fills these in; until then they only beep.

    func suggestionsTrash(_ suggestion: Suggestion, item: SuggestionItem) { NSSound.beep() }
    func suggestionsReveal(_ suggestion: Suggestion, item: SuggestionItem) { NSSound.beep() }
    func suggestionsIgnore(_ suggestion: Suggestion, item: SuggestionItem) { NSSound.beep() }
    func suggestionsCard(_ section: SuggestionSection) { NSSound.beep() }
    func suggestionsMenu(_ suggestion: Suggestion, item: SuggestionItem) -> NSMenu? { nil }
}
