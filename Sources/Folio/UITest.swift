import AppKit
import FolioCore

/// `Folio --uitest <folder|new> --shot <file> [--theme dark|light|system] [--accent <hue 0-359>] [--look native|obsidian]
///   [--tabs N] [--view <mode>] [--extra options|properties|preview|home|suggestions|suggestions-empty|suggestions-access]...`
///
/// Runs inside the test VM only (docs/plan/RULES.md, rule 0). Opens one window off-screen on a test
/// folder, waits for it to render, then from inside the app:
///   1. writes `<shot>-1-open.png` (its own window, via CGWindowListCreateImage of its window number),
///   2. clicks the Name header with a synthesized mouse down and up, writes `<shot>-2-name-sorted.png`,
///   3. clicks row index 3 the same way, writes `<shot>-3-row-selected.png`,
/// Optional flags show more than the Details list. Without them the run is exactly the three steps above.
///   --tabs N      opens N-1 more tabs on the same folder first, so the tab row shows (N from 1 to 12).
///   --view <v>    switches the view first: details, list, tiles, content, gallery, icons (medium icons),
///                 extraLargeIcons, largeIcons, mediumIcons or smallIcons. The choice goes to the
///                 throwaway preferences only. In a view with no table the sort and the row selection
///                 go straight to the window controller, since there is no header or row to click.
///   --extra <s>   after step 3, opens a surface off-screen, shoots it as `<shot>-4-<s>.png`, closes it.
///                 Repeat the flag for more. options is the Folder Options window, properties is the
///                 Properties window of the selected row, preview is the Preview pane on the first file,
///                 home is the Home page. The two windows are moved off every screen as well.
/// Any preference can be set for one run as a launch argument, which macOS keeps in the argument domain
/// and never saves: `-detailsSize large` shoots Details at the Large size.
/// prints what it saw, and exits 0 when every step worked (1 otherwise, 2 for bad arguments, 3 on a
/// 90 s timeout).
/// `new` makes /private/tmp/folio-tests/<run id>/Code (40 folders, 8 files) and trashes it afterwards.
struct UITestConfig {
    var folder: URL
    var madeFixture: Bool
    var shotBase: String
    /// Forced for this run only (the app itself follows the Mac); nil is the system's.
    var appearance: Appearance?
    var hue: Int
    /// D4 Obsidian unless `--look native`: the VM proofs were made in D4.
    var look: LookTheme
    var defaults: UserDefaults
    /// `--tabs N`: how many tabs the window has for the shots.
    var tabs = 1
    /// `--view`: the view mode for the shots, nil is the throwaway store's (Details).
    var view: ViewMode?
    /// `--extra`: the surfaces shot after step 3, in the order given.
    var extras: [String] = []
    /// The run folder that holds the Suggestions fake homes `Home` and `Empty`, made when a suggestions extra is asked for.
    var cleanupRun: URL?
    /// The clock of the fake home: the sample dates and the scan agree on it.
    var cleanupNow = Date()
    /// Each file of the samples is this many bytes times its units.
    static let cleanupUnit = 256 * 1024

    var cleanupHome: URL? { cleanupRun?.appendingPathComponent("Home", isDirectory: true) }
    var emptyHome: URL? { cleanupRun?.appendingPathComponent("Empty", isDirectory: true) }
    var asksForSuggestions: Bool { extras.contains { $0.hasPrefix("suggestions") } }

    static let extraNames = ["options", "properties", "preview", "home", "suggestions", "suggestions-empty", "suggestions-access"]
    static let viewNames: [String: ViewMode] = [
        "details": .details, "list": .list, "tiles": .tiles, "content": .content, "gallery": .gallery,
        "icons": .mediumIcons, "extraLargeIcons": .extraLargeIcons, "largeIcons": .largeIcons,
        "mediumIcons": .mediumIcons, "smallIcons": .smallIcons,
    ]

    static let usage = "usage: Folio --uitest <folder under /private/tmp/folio-tests/ | new> --shot <file.png> "
        + "[--theme dark|light|system] [--accent <hue 0-359>] [--look native|obsidian] "
        + "[--tabs N] [--view details|list|tiles|content|gallery|icons|extraLargeIcons|largeIcons|mediumIcons|smallIcons] "
        + "[--extra options|properties|preview|home|suggestions|suggestions-empty|suggestions-access]..."

    /// nil when `--uitest` is absent. Exits with code 2 on bad arguments.
    static func parse(_ args: [String]) -> UITestConfig? {
        guard let flag = args.firstIndex(of: "--uitest") else { return nil }
        func value(_ name: String) -> String? {
            args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        func fail(_ message: String) -> Never {
            print("uitest: " + message)
            print(usage)
            exit(2)
        }
        guard args.indices.contains(flag + 1) else { fail("missing folder") }
        guard let shot = value("--shot") else { fail("missing --shot") }
        var appearance: Appearance? = .dark
        if let raw = value("--theme") {
            switch raw {
            case "system": appearance = nil
            case "dark", "light": appearance = Appearance(rawValue: raw)
            default: fail("bad --theme \(raw)")
            }
        }
        var hue = Accent.defaultHue
        if let raw = value("--accent") {
            guard let n = Double(raw) else { fail("bad --accent \(raw)") }
            hue = Accent.normalized(n)
        }

        var look = LookTheme.obsidian
        if let raw = value("--look") {
            guard let l = LookTheme(rawValue: raw) else { fail("bad --look \(raw)") }
            look = l
        }

        var tabs = 1
        if let raw = value("--tabs") {
            guard let n = Int(raw), (1...12).contains(n) else { fail("bad --tabs \(raw)") }
            tabs = n
        }
        var view: ViewMode?
        if let raw = value("--view") {
            guard let mode = viewNames[raw] else { fail("bad --view \(raw)") }
            view = mode
        }
        var extras: [String] = []
        for (i, arg) in args.enumerated() where arg == "--extra" {
            guard args.indices.contains(i + 1), extraNames.contains(args[i + 1]) else {
                fail("bad --extra " + (args.indices.contains(i + 1) ? args[i + 1] : "(missing)"))
            }
            extras.append(args[i + 1])
        }

        var folder: URL
        var made = false
        if args[flag + 1] == "new" {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
            folder = URL(fileURLWithPath: "/private/tmp/folio-tests/uitest-\(stamp)-\(getpid())/Code", isDirectory: true)
            do { try UITestFixture.make(at: folder) } catch { fail("could not make the fixture: \(error)") }
            made = true
        } else {
            folder = URL(fileURLWithPath: (args[flag + 1] as NSString).expandingTildeInPath, isDirectory: true)
            guard UITestFixture.isAllowed(folder) else {
                fail("refusing \(folder.path): --uitest only opens folders under " + UITestFixture.allowedRoots.joined(separator: ", "))
            }
        }
        // The Suggestions fake homes live in the run folder next to Code, so one trash clears both.
        var cleanupRun: URL?
        let now = Date()
        if extras.contains(where: { $0.hasPrefix("suggestions") }) {
            let run = made ? folder.deletingLastPathComponent() : URL(fileURLWithPath:
                "/private/tmp/folio-tests/uitest-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: ""))-\(getpid())",
                isDirectory: true)
            do {
                try UITestFixture.makeCleanupSamples(at: run.appendingPathComponent("Home", isDirectory: true),
                                                     unit: cleanupUnit, now: now)
                try FileManager.default.createDirectory(at: run.appendingPathComponent("Empty", isDirectory: true),
                                                        withIntermediateDirectories: true)
            } catch { fail("could not make the clean-up samples: \(error)") }
            cleanupRun = run
        }
        // Theme choices go to a throwaway store in $TMPDIR, never the app's real preferences.
        let prefsDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("folio-uitest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: prefsDir, withIntermediateDirectories: true)
        guard let defaults = UserDefaults(suiteName: prefsDir.appendingPathComponent("prefs").path) else {
            fail("could not make a temp preferences store")
        }
        let base = shot.hasSuffix(".png") ? String(shot.dropLast(4)) : shot
        return UITestConfig(folder: folder, madeFixture: made, shotBase: base, appearance: appearance, hue: hue, look: look,
                            defaults: defaults, tabs: tabs, view: view, extras: extras,
                            cleanupRun: cleanupRun, cleanupNow: now)
    }
}

@MainActor
enum UITestRunner {
    static let windowSize = NSSize(width: 1440, height: 900)

    static func run(_ config: UITestConfig, controller c: BrowserWindowController) async -> Int32 {
        var problems: [String] = []
        guard let window = c.window as? BrowserWindow else { return 1 }
        // If a synthesized click ever blocks the main thread, still end the run.
        // A suggestions extra writes the samples, scans up to three times and shoots up to six times: longer.
        let limit: Double = config.asksForSuggestions ? 240 : 90
        DispatchQueue.global().asyncAfter(deadline: .now() + limit) {
            print("uitest: timed out after \(Int(limit)) s")
            fflush(stdout)
            exit(3)
        }
        // Off every screen: nothing appears on the desktop and nothing takes focus.
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()

        // Geist ships in the bundle for D4 either way; Native draws in the system font (SF Pro).
        let geist = NSFontManager.shared.availableMembers(ofFontFamily: "Geist") != nil
            && NSFontManager.shared.availableMembers(ofFontFamily: "Geist Mono") != nil
        let fontsOK: Bool
        switch config.look {
        case .obsidian:
            fontsOK = Typeface.ui(13).familyName == "Geist" && Typeface.mono(12).familyName == "Geist Mono"
            report("fonts: Geist and Geist Mono " + (fontsOK ? "registered" : "MISSING, system fallback in use"))
        case .native:
            let system = NSFont.systemFont(ofSize: 13).familyName
            fontsOK = geist && Typeface.ui(13).familyName == system
            report("fonts: Native in \(Typeface.ui(13).familyName ?? "?"), Geist " + (geist ? "registered" : "MISSING"))
        }
        if !fontsOK { problems.append("fonts") }

        guard await wait(timeout: 10, { c.isIdle }) else {
            report("listing did not finish in 10 s")
            return finish(config, 1)
        }
        await settle(0.8)
        // The optional setup: more tabs, then another view. Neither runs by default.
        for n in 1..<max(config.tabs, 1) {
            c.newTab(nil)
            _ = await wait(timeout: 10, { c.isIdle })
            report("tab \(n + 1) of \(config.tabs) opened on the same folder")
        }
        if config.tabs > 1 { await settle(0.5) }
        if let mode = config.view {
            // ViewCenter keeps this in the throwaway store, so nothing reaches the real preferences.
            c.chooseView(mode)
            _ = await wait(timeout: 10, { c.isIdle })
            await settle(0.8)
            report("view: \(c.viewMode.title)" + (c.viewMode == mode ? "" : " (asked for \(mode.title))"))
            if c.viewMode != mode { problems.append("view") }
        }
        report("folder: \(config.folder.path), \(c.entries.count) rows, "
               + "\(c.entries.filter(\.isFolder).count) folders, theme \(config.appearance?.rawValue ?? "system"), accent hue \(config.hue)")
        shot(window, config, "1-open", c, &problems)

        let before = c.sortSpec
        let target = before.clicking(.name)
        var how = "synthesized mouse down and up on the Name header"
        // Only Details has a header to click. Another view sorts as the header would.
        if c.viewMode.usesTable { c.uitestClickHeader(.name) }
        let headerSorted = c.viewMode.usesTable ? await wait(timeout: 1.5, { c.sortSpec == target }) : false
        if !headerSorted {
            how = c.viewMode.usesTable ? "fallback: tableView.sortDescriptors (the synthesized click did not sort)"
                : "applySort (this view has no header)"
            c.uitestSortFallback(.name)
            if !(await wait(timeout: 1.5, { c.sortSpec == target })) { problems.append("header click") }
        }
        _ = await wait(timeout: 5, { c.isIdle })
        await settle(0.5)
        report("click Name header via \(how): \(SortLabel.label(before)) -> \(SortLabel.label(c.sortSpec)), "
               + "first row \(c.entries.first?.name ?? "none")")
        shot(window, config, "2-name-sorted", c, &problems)

        let row = 3
        how = "synthesized mouse down and up on row \(row)"
        if !c.viewMode.usesTable {
            how = "selection.click and applySelection (this view has no table row)"
            c.selection.click(row)
            c.applySelection(scrollTo: row)
            if c.selection.rows != IndexSet(integer: row) { problems.append("row select") }
        } else {
            c.uitestClickRow(row)
        }
        if c.viewMode.usesTable, !(await wait(timeout: 1.5, { c.tableView.selectedRowIndexes == IndexSet(integer: row) })) {
            how = "fallback: selectRowIndexes (the synthesized click did not select)"
            c.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if c.tableView.selectedRowIndexes != IndexSet(integer: row) { problems.append("row select") }
        }
        await settle(0.6)
        let name = c.entries.indices.contains(row) ? c.entries[row].name : "none"
        report("select row index \(row) via \(how): \(name); status reads \"\(c.statusText)\"")
        shot(window, config, "3-row-selected", c, &problems)

        for extra in config.extras { await shootExtra(extra, window, config, c, &problems) }

        report(problems.isEmpty ? "result: ok" : "result: FAILED (" + problems.joined(separator: ", ") + ")")
        return finish(config, problems.isEmpty ? 0 : 1)
    }

    /// Step 4: one more surface, shot window-only like the others. Dialogs go off-screen and close again.
    private static func shootExtra(_ name: String, _ window: BrowserWindow, _ config: UITestConfig,
                                   _ c: BrowserWindowController, _ problems: inout [String]) async {
        let suffix = "4-" + name
        switch name {
        case "options":
            let known = Set(NSApp.windows.map(ObjectIdentifier.init))
            FolderOptionsWindowController.show(near: window)
            await shootDialog(known, suffix, config, c, &problems)
        case "properties":
            let urls = c.selectedEntries.map(\.url)
            guard !urls.isEmpty else {
                report("extra properties: no row is selected")
                problems.append("extra properties")
                return
            }
            let known = Set(NSApp.windows.map(ObjectIdentifier.init))
            PropertiesWindowController.show(urls, near: window)
            await shootDialog(known, suffix, config, c, &problems)
        case "preview":
            // ListOptions.sidePane would write the real preferences, so the pane is set on the chassis alone.
            guard let index = c.entries.firstIndex(where: { !$0.isFolder }) else {
                report("extra preview: the folder has no file")
                problems.append("extra preview")
                return
            }
            c.selection.click(index)
            c.applySelection(scrollTo: index)
            c.chassis.sidePaneKind = .preview
            c.chassis.sidePane.show(selection: c.selectedEntries, folder: c.history.current,
                                    folderName: c.displayName(c.history.current), itemCount: c.shownCount, meta: nil)
            await settle(1.5)
            report("extra preview: \(c.entries[index].name) in the Preview pane")
            shot(window, config, suffix, c, &problems)
            c.chassis.sidePaneKind = c.shownSidePane
        case "home":
            c.goHome(nil)
            await settle(1.0)
            report("extra home: \(c.homeStatusText)")
            shot(window, config, suffix, c, &problems)
            c.navigate(to: config.folder)
            _ = await wait(timeout: 10, { c.isIdle })
        case "suggestions":
            await shootSuggestions(suffix, window, config, c, &problems)
        case "suggestions-empty":
            await shootSuggestionsEmpty(suffix, window, config, c, &problems)
        case "suggestions-access":
            await shootSuggestionsAccess(suffix, window, config, c, &problems)
        default:
            break
        }
    }

    // MARK: Suggestions

    /// A path relative to the fake home. Only the folder is resolved, so a broken link keeps its own name.
    private static func relative(_ url: URL, to home: URL) -> String {
        let folder = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
        let base = home.resolvingSymlinksInPath().path
        return folder.hasPrefix(base + "/") ? String(folder.dropFirst(base.count + 1)) : folder
    }

    private static func openSuggestions(_ c: BrowserWindowController) async {
        if !c.history.isSuggestions {
            c.goSuggestions(nil)
            await settle(0.8)
        }
    }

    private static func leaveSuggestions(_ config: UITestConfig, _ c: BrowserWindowController) async {
        c.navigate(to: config.folder)
        _ = await wait(timeout: 10, { c.isIdle })
    }

    private static func shootSuggestions(_ suffix: String, _ window: BrowserWindow, _ config: UITestConfig,
                                         _ c: BrowserWindowController, _ problems: inout [String]) async {
        let center = SuggestionsCenter.shared
        guard let home = config.cleanupHome, configureSuggestions(home: home, config) else {
            report("extra suggestions: the fake home was refused")
            problems.append("extra suggestions")
            return
        }
        center.autoScanAllowed = true
        await openSuggestions(c)
        // The report must be for the fake home: a run that showed the empty home first scans again.
        if center.report?.home != center.home, center.state != .scanning { center.rescan() }
        guard await wait(timeout: 40, { center.state == .done && center.report?.home == center.home }) else {
            report("extra suggestions: the scan did not finish in 40 s (state \(center.state))")
            problems.append("suggestions scan")
            shot(window, config, suffix, c, &problems)
            await leaveSuggestions(config, c)
            return
        }
        await settle(0.8)
        guard let result = center.report else { return }
        var seen: [SuggestionKind: Set<String>] = [:]
        for s in result.suggestions { seen[s.kind, default: []].formUnion(s.items.map { relative($0.url, to: home) }) }
        for expectation in UITestFixture.cleanupExpected {
            let want = Set(expectation.paths)
            let got = seen[expectation.kind] ?? []
            if got != want {
                report("extra suggestions: \(expectation.kind.rawValue) missing \(want.subtracting(got).sorted()) extra \(got.subtracting(want).sorted())")
                problems.append("suggestions \(expectation.kind.rawValue)")
            }
        }
        if seen.values.contains(where: { $0.contains { $0.contains("Tool.app/") } }) { problems.append("suggestions inside an app") }
        let counts = SuggestionKind.allCases.map { "\($0.rawValue) \(seen[$0]?.count ?? 0)" }.joined(separator: ", ")
        report("extra suggestions: \(c.suggestionsStatusText); \(counts)")
        shot(window, config, suffix, c, &problems)

        // Move one large unused row to the Trash, then bring it back with Undo.
        if ListOptions.folder.confirmDelete {
            report("extra suggestions: Display delete confirmation is on, so the Trash and Undo steps are skipped")
            await leaveSuggestions(config, c)
            return
        }
        guard let suggestion = result.suggestions.first(where: { $0.kind == .largeUnused }), let item = suggestion.items.first else {
            problems.append("suggestions trash row")
            await leaveSuggestions(config, c)
            return
        }
        func listed() -> Bool { center.report?.suggestions.contains { $0.id == suggestion.id } ?? false }
        c.suggestionsTrash(suggestion, item: item)
        let left = await wait(timeout: 15, { !listed() })
        await settle(0.6)
        report("extra suggestions: Move to Trash on \(item.url.lastPathComponent): the row " + (left ? "left" : "did not leave"))
        if !left { problems.append("suggestions trash") }
        shot(window, config, suffix + "-trashed", c, &problems)

        OperationCenter.shared.undo(window: window)
        let back = await wait(timeout: 15, { listed() })
        await settle(0.6)
        report("extra suggestions: Undo: the row " + (back ? "returned" : "did not return"))
        if !back { problems.append("suggestions undo") }
        shot(window, config, suffix + "-undone", c, &problems)
        await leaveSuggestions(config, c)
    }

    private static func shootSuggestionsEmpty(_ suffix: String, _ window: BrowserWindow, _ config: UITestConfig,
                                              _ c: BrowserWindowController, _ problems: inout [String]) async {
        let center = SuggestionsCenter.shared
        guard let empty = config.emptyHome, configureSuggestions(home: empty, config) else {
            report("extra suggestions-empty: the empty home was refused")
            problems.append("extra suggestions-empty")
            return
        }
        center.autoScanAllowed = true
        let before = center.lastScan
        await openSuggestions(c)
        // A first scan starts by itself after the page has been shown; otherwise ask for one.
        if center.state != .scanning, center.report?.home != center.home { center.rescan() }
        guard await wait(timeout: 40, { center.state == .done && center.report?.home == center.home && center.lastScan != before }) else {
            report("extra suggestions-empty: the scan did not finish in 40 s (state \(center.state))")
            problems.append("suggestions-empty scan")
            await leaveSuggestions(config, c)
            return
        }
        await settle(0.8)
        let count = center.report?.suggestions.count ?? -1
        report("extra suggestions-empty: \(c.suggestionsStatusText), \(count) suggestions")
        if count != 0 { problems.append("suggestions-empty not empty") }
        shot(window, config, suffix, c, &problems)
        await leaveSuggestions(config, c)
        // Later extras find the sample home again.
        if let home = config.cleanupHome { _ = configureSuggestions(home: home, config) }
    }

    private static func shootSuggestionsAccess(_ suffix: String, _ window: BrowserWindow, _ config: UITestConfig,
                                               _ c: BrowserWindowController, _ problems: inout [String]) async {
        let center = SuggestionsCenter.shared
        if center.isRealHome, let home = config.cleanupHome { _ = configureSuggestions(home: home, config) }
        await openSuggestions(c)
        center.uitestForceAccessGate(true)
        await settle(0.8)
        report("extra suggestions-access: \(c.suggestionsStatusText)")
        if center.state != .needsAccess { problems.append("suggestions-access gate") }
        shot(window, config, suffix, c, &problems)
        center.uitestForceAccessGate(false)
        await leaveSuggestions(config, c)
    }

    /// Points the center at a fake home of this run, with floors the 256 KiB samples can meet.
    private static func configureSuggestions(home: URL, _ config: UITestConfig) -> Bool {
        let settings = SuggestionConfig.uitest(home: home, now: config.cleanupNow, unit: Int64(UITestConfig.cleanupUnit))
        return SuggestionsCenter.shared.configure(home: home, config: settings, defaults: config.defaults)
    }

    private static func shootDialog(_ known: Set<ObjectIdentifier>, _ suffix: String, _ config: UITestConfig,
                                    _ c: BrowserWindowController, _ problems: inout [String]) async {
        guard let dialog = NSApp.windows.first(where: { !known.contains(ObjectIdentifier($0)) && $0.isVisible }) else {
            report("shot \(suffix): no window opened")
            problems.append("shot \(suffix)")
            return
        }
        // Off every screen, like the browser window. Setting the origin after ordering front skips the screen clamp.
        dialog.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        await settle(0.8)
        report("extra \(suffix): \"\(dialog.title)\" \(Int(dialog.frame.width))x\(Int(dialog.frame.height)) pt")
        shot(dialog, config, suffix, c, &problems)
        dialog.close()
        await settle(0.2)
    }

    private static func finish(_ config: UITestConfig, _ code: Int32) -> Int32 {
        if config.madeFixture {
            // The whole run folder goes to the Trash unless the shots were written inside it.
            let run = config.folder.deletingLastPathComponent()
            let keepRun = config.shotBase.hasPrefix(run.path + "/")
                || config.shotBase.hasPrefix("/private" + run.path + "/")
            var gone = keepRun ? [config.folder] : [run]
            if keepRun { gone += [config.cleanupHome, config.emptyHome].compactMap { $0 } }
            for url in gone { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        } else if let run = config.cleanupRun {
            try? FileManager.default.trashItem(at: run, resultingItemURL: nil)
        }
        return code
    }

    private static func report(_ line: String) {
        print("uitest: " + line)
        fflush(stdout)
    }

    private static func shot(_ window: NSWindow, _ config: UITestConfig, _ suffix: String,
                             _ c: BrowserWindowController, _ problems: inout [String]) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        let path = config.shotBase + "-" + suffix + ".png"
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                                  [.boundsIgnoreFraming, .bestResolution]),
              image.width > 0,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else {
            report("shot \(suffix): CGWindowListCreateImage returned nothing")
            problems.append("shot \(suffix)")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            report("shot \(suffix): \(path) (\(image.width)x\(image.height) px)")
        } catch {
            report("shot \(suffix): could not write \(path): \(error.localizedDescription)")
            problems.append("shot \(suffix)")
        }
    }

    private static func wait(timeout: Double, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private static func settle(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }
}

extension BrowserWindowController {
    var statusText: String { (window?.contentView as? ChassisView)?.status.countText ?? "" }

    /// A click on a header cell, delivered straight to the header view (no window server, no System Events).
    func uitestClickHeader(_ key: SortKey) {
        guard let header = tableView.headerView,
              let col = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == key.rawValue }) else { return }
        let rect = header.headerRect(ofColumn: col)
        click(header, at: header.convert(NSPoint(x: rect.midX, y: ListMetrics.headerHeight / 2), to: nil))
    }

    /// What NSTableView does after a header click, for when the synthesized click is swallowed.
    func uitestSortFallback(_ key: SortKey) {
        applySort(sortSpec.clicking(key))
    }

    func uitestClickRow(_ row: Int) {
        guard row < tableView.numberOfRows else { return }
        let rect = tableView.frameOfCell(atColumn: 0, row: row)
        click(tableView, at: tableView.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil))
    }

    private func click(_ view: NSView, at point: NSPoint) {
        guard let window else { return }
        let t = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: t,
                                            windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                                            clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: t + 0.05,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 2,
                                          clickCount: 1, pressure: 0)
        else { return }
        // The view's tracking loop pulls the mouse-up from the app's own queue.
        NSApp.postEvent(up, atStart: true)
        view.mouseDown(with: down)
    }
}
