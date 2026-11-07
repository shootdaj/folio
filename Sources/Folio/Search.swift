import AppKit
import FolioCore

/// Search options' persistent toggles (Explorer's Folder Options > Search behind them) and the Recent
/// searches setting.
@MainActor
enum SearchSettings {
    static let fileContentsKey = "searchFileContents"
    static let systemFilesKey = "searchSystemFiles"
    static let recentKey = "searchRecentDropdown"

    /// Advanced options > File contents: the walk reads files in places Spotlight does not index.
    static var fileContents: Bool {
        get { UserDefaults.standard.bool(forKey: fileContentsKey) }
        set { UserDefaults.standard.set(newValue, forKey: fileContentsKey); ListOptions.reload() }
    }

    /// Advanced options > System files: the walk goes into system folders.
    static var systemFiles: Bool {
        get { UserDefaults.standard.bool(forKey: systemFilesKey) }
        set { UserDefaults.standard.set(newValue, forKey: systemFilesKey); ListOptions.reload() }
    }

    /// Advanced options > Zipped (compressed) folders, Folder Options' Include compressed files: the
    /// walk looks inside zips.
    static var zippedFolders: Bool {
        get { UserDefaults.standard.bool(forKey: "searchZippedFolders") }
        set { UserDefaults.standard.set(newValue, forKey: "searchZippedFolders"); ListOptions.reload() }
    }

    /// Windows 11 dropped the Recent searches dropdown when live results came; here it is a setting, on.
    static var recentDropdown: Bool {
        get { UserDefaults.standard.object(forKey: recentKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: recentKey) }
    }

    static let debounce: TimeInterval = 0.3
}

/// Milestone 7 in the window: the search box, results as you type, Search Results in <folder> with its
/// progress bar, the Search options row, the Folder column, Open file location, Save search, Recent searches.
extension BrowserWindowController {
    var isSearching: Bool { history.search != nil }

    /// Results start in relevance order until a header is clicked.
    var isRelevanceOrder: Bool { isSearching && searchSort == nil }

    var searchLocation: SearchLocation {
        if history.search?.everywhere == true { return .thisPC }
        if history.isHome { return .home }
        return .folder(history.current)
    }

    /// "work", "Home", "This PC".
    var searchScopeName: String {
        history.search?.everywhere == true ? "This PC" : displayName(history.current)
    }

    var searchTitle: String { "Search Results in " + searchScopeName }

    var recentSearches: RecentSearches { RecentSearches(defaults: options.historyDefaults) }

    // MARK: Wiring

    func wireSearch() {
        let box = toolbar.search
        box.dropdown = dropdown
        box.onChange = { [weak self] text in self?.searchTextChanged(text) }
        box.onEnter = { [weak self] text in self?.commitSearchNow(text, record: true) }
        box.onClear = { [weak self] in self?.closeSearch() }
        box.onFocus = { [weak self] in self?.searchBoxFocused() }
        box.onDown = { [weak self] in self?.showRecentSearches() }
        let bar = chassis.searchOptions
        bar.onChip = { [weak self] chip in self?.showOptionsMenu(for: chip) }
        bar.onScope = { [weak self] recursive in self?.setSearchScope(recursive: recursive) }
        let footer = chassis.pane.searchFooter
        footer.thisPC.onPress = { [weak self] in self?.searchAgain(everywhere: true) }
        footer.home.onPress = { [weak self] in self?.searchAgain(everywhere: false) }
    }

    // MARK: Focus (Cmd+E, Cmd+F, F3)

    @objc func focusSearch(_ sender: Any?) {
        if toolbar.address.isEditing { toolbar.address.endEditing(focus: .stay) }
        toolbar.search.focus()
    }

    private func searchBoxFocused() {
        if toolbar.search.text.isEmpty { showRecentSearches(onlyIfAny: true) }
    }

    func showRecentSearches(onlyIfAny: Bool = false) {
        guard SearchSettings.recentDropdown else { return }
        let items = recentSearches.items
        if onlyIfAny && items.isEmpty { return }
        toolbar.search.showRecent(items)
    }

    // MARK: Typing

    /// Each key restarts the wait; 300 ms after the last one the search runs, cancelling the one before.
    func searchTextChanged(_ text: String) {
        searchDebounce?.invalidate()
        searchDebounce = Timer.scheduledTimer(withTimeInterval: SearchSettings.debounce, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.commitSearchText(text) }
        }
    }

    /// Return, a recent search, a Search options pick: no wait.
    func commitSearchNow(_ text: String, record: Bool) {
        searchDebounce?.invalidate()
        commitSearchText(text)
        if record { recentSearches.record(text) }
    }

    func commitSearchText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            closeSearch()
            return
        }
        if let s = history.search {
            guard s.text != text else { return }
            history.updateSearch(HistorySearch(text: text, recursive: s.recursive, everywhere: s.everywhere))
            // The results there are stay until the new query's come in.
            runSearch(keepingState: true)
            updateSearchChrome()
        } else {
            // A search is a place in the tab's history (Explorer's search-ms location).
            history.push(history.current, search: HistorySearch(text: text))
            load()
            sessionChanged()
        }
    }

    /// Esc, the clear button or an empty box: back to the folder.
    func closeSearch() {
        searchDebounce?.invalidate()
        guard isSearching else { return }
        history.closeSearch()
        load()
    }

    // MARK: Entering and leaving the results

    /// Switches the window to results: Details with a Folder column, the Search options row, the footer.
    func enterSearchMode() {
        chassis.showsHome = false
        let tab = tabs.active.id
        if groupsBeforeSearch[tab] == nil {
            groupsBeforeSearch.updateValue(group, forKey: tab)
            group = nil
            collapsedGroups = []
        }
        if searchTabID != tab {
            searchTabID = tab
            searchSort = nil
            searchView = nil
        }
        guard !searchUIShown else { return }
        searchUIShown = true
        isLoading = false
        isTrashView = false
        filters.clearAll()
        collapsedGroups = []
        chassis.showsSearchOptions = true
        chassis.pane.showsSearchFooter = true
        rebuildColumns()
        applyViewMode()
    }

    func leaveSearchMode() {
        guard searchUIShown else { return }
        searchUIShown = false
        searchEngine?.cancel()
        searchEngine = nil
        searchTicker?.invalidate()
        searchTicker = nil
        searchSort = nil
        searchView = nil
        searchTabID = nil
        searchError = nil
        searchTerms = []
        chassis.showsSearchOptions = false
        chassis.pane.showsSearchFooter = false
        toolbar.address.searchTitle = nil
        if !toolbar.search.isEditing { toolbar.search.text = "" }
        rebuildColumns()
        applyViewMode()
    }

    // MARK: Running

    /// Starts the search shown in the history (a new one each time; the one before is cancelled).
    /// `keepingState`: a refresh, so the old results stay until the new ones arrive.
    func runSearch(keepingState: Bool) {
        guard let s = history.search else { return }
        searchEngine?.cancel()
        searchEngine = nil
        searchRun += 1
        let run = searchRun
        let query: QueryNode
        do {
            query = try SearchQuery.parse(s.text)
        } catch {
            // Keep the results there are; the status bar says what is wrong.
            searchError = (error as? SearchQueryError)?.description ?? error.localizedDescription
            searchFinished = true
            searchTicker?.invalidate()
            updateSearchChrome()
            updateStatus()
            return
        }
        searchError = nil
        searchTerms = query.positiveNameTerms
        searchHits = []
        searchReplacePending = keepingState
        if !keepingState {
            listing = []
            arrangedWith = arrangeKey
            show(ListLayout(items: []), selecting: [])
        }
        searchStarted = Date()
        searchFinished = false
        searchEngineProgress = 0
        searchLoggedFirst = false
        var request = SearchRequest(query: query, location: searchLocation)
        request.recursive = s.recursive
        request.includeHidden = ListOptions.showHidden
        request.fileContents = SearchSettings.fileContents
        request.systemFiles = SearchSettings.systemFiles
        request.zippedFolders = SearchSettings.zippedFolders
        request.dontUseIndex = ListOptions.folder.dontUseIndex
        let engine = SearchEngine(request) { [weak self] update in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.searchUpdated(update, run: run) }
            }
        }
        searchEngine = engine
        engine.start()
        searchTicker?.invalidate()
        searchTicker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickSearchProgress() }
        }
        updateSearchChrome()
        updateStatus()
    }

    private func searchUpdated(_ u: SearchUpdate, run: Int) {
        guard run == searchRun, isSearching else { return }
        if searchReplacePending, !u.hits.isEmpty || u.done {
            searchReplacePending = false
        }
        searchHits += u.hits
        searchEngineProgress = u.progress
        let text = history.search?.text ?? ""
        if !u.hits.isEmpty, !searchLoggedFirst {
            searchLoggedFirst = true
            perfLog.notice("""
                search first results: "\(text, privacy: .public)" \(u.hits.count, privacy: .public) hits after \
                \(Int((u.firstHitAfter ?? u.elapsed) * 1000), privacy: .public) ms
                """)
        }
        if u.done {
            searchFinished = true
            searchTicker?.invalidate()
            searchTicker = nil
            perfLog.notice("""
                search done: "\(text, privacy: .public)" \(u.total, privacy: .public) hits in \(Int(u.elapsed * 1000), privacy: .public) ms; \
                first after \(Int((u.firstHitAfter ?? u.elapsed) * 1000), privacy: .public) ms; walk \(u.walked ? "yes" : "no", privacy: .public)
                """)
        }
        if !searchReplacePending, !u.hits.isEmpty || u.done {
            listing = SearchMerger.ranked(searchHits).map(\.entry)
            // The listing changed: arrange it all again (not only the folded groups).
            arrangedWith = nil
            rearrange()
        }
        updateSearchChrome()
        updateStatus()
    }

    private func tickSearchProgress() {
        guard isSearching else { searchTicker?.invalidate(); return }
        toolbar.address.searchProgress = searchDisplayProgress
    }

    /// The bar crawls on time while results stream in (Explorer's creeping bar), never behind the walk's
    /// own progress, and fills when both halves are done.
    var searchDisplayProgress: Double {
        if searchFinished { return 1 }
        let t = Date().timeIntervalSince(searchStarted)
        return max(0.9 * (1 - exp(-t / 1.6)), min(0.95, searchEngineProgress))
    }

    /// The address bar, title, box and options row for the search shown.
    func updateSearchChrome() {
        guard let s = history.search else { return }
        let title = searchTitle
        window?.title = title
        toolbar.address.searchTitle = title
        toolbar.address.searchDone = searchFinished
        toolbar.address.searchProgress = searchDisplayProgress
        toolbar.search.folderName = searchScopeName
        if !toolbar.search.isEditing || toolbar.search.text.isEmpty { toolbar.search.text = s.text }
        let bar = chassis.searchOptions
        bar.recursive = s.recursive
        bar.date.value = SearchBoxText.value(of: .modified, in: s.text)
        bar.kind.value = SearchBoxText.value(of: .kind, in: s.text)
        bar.size.value = SearchBoxText.value(of: .size, in: s.text)
        updateSearchEmpty()
        updateTabStrip()
    }

    /// "No items match your search." once a search ends with nothing shown; "Working on it..." before.
    func updateSearchEmpty() {
        let empty = chassis.pane.searchEmpty
        guard isSearching else { empty.isHidden = true; return }
        empty.isHidden = shownCount != 0
        empty.text = searchError.map { "Search: " + $0 } ?? (searchFinished ? "No items match your search." : "Working on it...")
    }

    /// The status bar while searching: "Searching work" until results come, then the count.
    var searchStatusText: String? {
        guard isSearching else { return nil }
        if let searchError { return "Search: " + searchError }
        if !searchFinished && shownCount == 0 { return "Searching " + searchScopeName }
        return nil
    }

    // MARK: Search options

    private func pick(_ menu: NSMenu, _ title: String, _ action: Selector, _ value: Any?, on: Bool = false, enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
        item.target = self
        item.representedObject = value
        item.state = on ? .on : .off
        menu.addItem(item)
    }

    func showOptionsMenu(for chip: OptionChip) {
        let bar = chassis.searchOptions
        let text = history.search?.text ?? toolbar.search.text
        let menu = NSMenu(title: chip.title)
        menu.font = Typeface.mono(13)
        menu.autoenablesItems = false
        if chip === bar.date {
            let current = SearchBoxText.value(of: .modified, in: text)?.lowercased()
            for (title, value) in [("Today", "today"), ("Yesterday", "yesterday"), ("This week", "this week"), ("Last week", "last week"),
                                   ("This month", "this month"), ("Last month", "last month"), ("This year", "this year"),
                                   ("Last year", "last year")] {
                pick(menu, title, #selector(pickDateModified(_:)), value, on: current == value)
            }
        } else if chip === bar.kind {
            let current = SearchBoxText.value(of: .kind, in: text).flatMap(SearchKind.named)
            for k in SearchKind.allCases { pick(menu, k.title, #selector(pickKind(_:)), k.keyword, on: current == k) }
        } else if chip === bar.size {
            let current = SearchBoxText.value(of: .size, in: text)?.lowercased()
            for (_, bucket) in Buckets.sizeBuckets { pick(menu, bucket.label, #selector(pickSize(_:)), bucket.id, on: current == bucket.id) }
        } else if chip === bar.other {
            for (title, property) in [("Type", SearchProperty.type), ("Name", .name), ("Folder path", .folder), ("Tags", .tag)] {
                pick(menu, title, #selector(pickOtherProperty(_:)), property.rawValue)
            }
        } else if chip === bar.advanced {
            pick(menu, "File contents", #selector(toggleSearchFileContents(_:)), nil, on: SearchSettings.fileContents)
            pick(menu, "System files", #selector(toggleSearchSystemFiles(_:)), nil, on: SearchSettings.systemFiles)
            pick(menu, "Zipped (compressed) folders", #selector(toggleSearchZippedFolders(_:)), nil, on: SearchSettings.zippedFolders)
            menu.addItem(.separator())
            pick(menu, "Recent searches list", #selector(toggleRecentSearchesList(_:)), nil, on: SearchSettings.recentDropdown)
            pick(menu, "Clear search history", #selector(clearSearchHistory(_:)), nil, enabled: !recentSearches.items.isEmpty)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: chip.bounds.height + 4), in: chip)
    }

    /// A pick writes its term into the box (replacing one for the same filter) and runs at once.
    private func writeTerm(_ property: SearchProperty, _ value: String) {
        let text = SearchBoxText.setting(property, to: value, in: toolbar.search.text)
        toolbar.search.text = text
        commitSearchNow(text, record: false)
    }

    @objc func pickDateModified(_ sender: NSMenuItem) { if let v = sender.representedObject as? String { writeTerm(.modified, v) } }
    @objc func pickKind(_ sender: NSMenuItem) { if let v = sender.representedObject as? String { writeTerm(.kind, "=" + v) } }
    @objc func pickSize(_ sender: NSMenuItem) { if let v = sender.representedObject as? String { writeTerm(.size, v) } }

    /// Other properties: the keyword goes in with the caret after its colon, for the value to be typed.
    @objc func pickOtherProperty(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let property = SearchProperty(rawValue: raw) else { return }
        toolbar.search.text = SearchBoxText.appendingKeyword(property, to: toolbar.search.text)
        toolbar.search.focusAtEnd()
    }

    @objc func toggleSearchFileContents(_ sender: Any?) {
        SearchSettings.fileContents.toggle()
        if isSearching { runSearch(keepingState: true) }
    }

    @objc func toggleSearchSystemFiles(_ sender: Any?) {
        SearchSettings.systemFiles.toggle()
        if isSearching { runSearch(keepingState: true) }
    }

    @objc func toggleSearchZippedFolders(_ sender: Any?) {
        SearchSettings.zippedFolders.toggle()
        if isSearching { runSearch(keepingState: true) }
    }

    @objc func toggleRecentSearchesList(_ sender: Any?) { SearchSettings.recentDropdown.toggle() }
    @objc func clearSearchHistory(_ sender: Any?) { recentSearches.clear() }

    /// All subfolders or Current folder: the same search, one level or all.
    func setSearchScope(recursive: Bool) {
        guard var s = history.search, s.recursive != recursive else { return }
        s.recursive = recursive
        history.updateSearch(s)
        runSearch(keepingState: false)
    }

    /// Search again in: This PC (the whole Mac) or Home (the home folder and the indexed places).
    func searchAgain(everywhere: Bool) {
        guard let s = history.search else { return }
        recentSearches.record(s.text)
        if everywhere {
            history.push(URL(fileURLWithPath: "/", isDirectory: true), search: HistorySearch(text: s.text, everywhere: true))
        } else {
            history.push(NavigationHistory.home, search: HistorySearch(text: s.text))
        }
        load()
        sessionChanged()
    }

    // MARK: Results

    /// Right-click a result > Open file location: its folder, with it selected.
    @objc func openFileLocation(_ sender: Any?) {
        guard let entry = selectedEntries.first else { return }
        if let s = history.search { recentSearches.record(s.text) }
        // The folder's list takes the keys (Back, arrows), and the box clears for the new folder.
        window?.makeFirstResponder(listView)
        navigate(to: entry.url.deletingLastPathComponent(), selecting: FilePaths.itemKey(entry.url))
    }

    /// Right-click empty results space > Save search, or File > Save Search: a .foliosearch file in
    /// ~/Library/Application Support/Folio/Searches that runs the search again when opened.
    @objc func saveSearch(_ sender: Any?) {
        guard let s = history.search, let window else { return }
        let folder = SavedSearch.folder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let panel = NSSavePanel()
        panel.title = "Save search"
        panel.prompt = "Save"
        panel.nameFieldStringValue = SavedSearch.suggestedName(for: s.text)
        panel.directoryURL = folder
        panel.isExtensionHidden = false
        let saved = SavedSearch(text: s.text, location: searchLocation, recursive: s.recursive, view: viewMode.rawValue,
                                sort: searchSort?.terms ?? [], group: group)
        recentSearches.record(s.text)
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, var url = panel.url else { return }
                if url.pathExtension.lowercased() != SavedSearch.fileExtension { url.appendPathExtension(SavedSearch.fileExtension) }
                do {
                    try saved.write(to: url)
                    self?.statusMessage = nil
                } catch {
                    self?.statusMessage = "Could not save the search: " + error.localizedDescription
                }
                self?.updateStatus()
            }
        }
    }

    /// The name cell's highlight: the matched word starts in the name shown.
    func searchHighlights(_ name: String) -> [NSRange] {
        guard isSearching, !searchTerms.isEmpty else { return [] }
        return TextMatcher.highlights(searchTerms, in: name).map { NSRange($0, in: name) }
    }

    /// A file operation or a refresh: the search runs again when something changed under its scope.
    func searchFilesChanged(_ folders: Set<String>?) {
        guard case .folder(let url) = searchLocation else { return }
        let scope = FilePaths.folderKey(url)
        if let folders, !folders.contains(where: { $0 == scope || $0.hasPrefix(scope + "/") }) { return }
        runSearch(keepingState: true)
    }
}
