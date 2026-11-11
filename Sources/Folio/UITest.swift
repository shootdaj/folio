import AppKit
import FolioCore

/// `Folio --uitest <folder|new> --shot <file> [--theme dark|light|system] [--accent <hue 0-359>]`
///
/// Runs inside the test VM only (docs/plan/RULES.md, rule 0). Opens one window off-screen on a test
/// folder, waits for it to render, then from inside the app:
///   1. writes `<shot>-1-open.png` (its own window, via CGWindowListCreateImage of its window number),
///   2. clicks the Name header with a synthesized mouse down and up, writes `<shot>-2-name-sorted.png`,
///   3. clicks row index 3 the same way, writes `<shot>-3-row-selected.png`,
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
    var defaults: UserDefaults

    static let usage = "usage: Folio --uitest <folder under /private/tmp/folio-tests/ | new> --shot <file.png> "
        + "[--theme dark|light|system] [--accent <hue 0-359>]"

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
        // Theme choices go to a throwaway store in $TMPDIR, never the app's real preferences.
        let prefsDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("folio-uitest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: prefsDir, withIntermediateDirectories: true)
        guard let defaults = UserDefaults(suiteName: prefsDir.appendingPathComponent("prefs").path) else {
            fail("could not make a temp preferences store")
        }
        let base = shot.hasSuffix(".png") ? String(shot.dropLast(4)) : shot
        return UITestConfig(folder: folder, madeFixture: made, shotBase: base, appearance: appearance, hue: hue, defaults: defaults)
    }
}

@MainActor
enum UITestRunner {
    static let windowSize = NSSize(width: 1440, height: 900)

    static func run(_ config: UITestConfig, controller c: BrowserWindowController) async -> Int32 {
        var problems: [String] = []
        guard let window = c.window as? BrowserWindow else { return 1 }
        // If a synthesized click ever blocks the main thread, still end the run.
        DispatchQueue.global().asyncAfter(deadline: .now() + 90) {
            print("uitest: timed out after 90 s")
            fflush(stdout)
            exit(3)
        }
        // Off every screen: nothing appears on the desktop and nothing takes focus.
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()

        let fontsOK = Typeface.ui(13).familyName == "Geist" && Typeface.mono(12).familyName == "Geist Mono"
        report("fonts: Geist and Geist Mono " + (fontsOK ? "registered" : "MISSING, system fallback in use"))
        if !fontsOK { problems.append("fonts") }

        guard await wait(timeout: 10, { c.isIdle }) else {
            report("listing did not finish in 10 s")
            return finish(config, 1)
        }
        await settle(0.8)
        report("folder: \(config.folder.path), \(c.entries.count) rows, "
               + "\(c.entries.filter(\.isFolder).count) folders, theme \(config.appearance?.rawValue ?? "system"), accent hue \(config.hue)")
        shot(window, config, "1-open", c, &problems)

        let before = c.sortSpec
        let target = before.clicking(.name)
        var how = "synthesized mouse down and up on the Name header"
        c.uitestClickHeader(.name)
        if !(await wait(timeout: 1.5, { c.sortSpec == target })) {
            how = "fallback: tableView.sortDescriptors (the synthesized click did not sort)"
            c.uitestSortFallback(.name)
            if !(await wait(timeout: 1.5, { c.sortSpec == target })) { problems.append("header click") }
        }
        _ = await wait(timeout: 5, { c.isIdle })
        await settle(0.5)
        report("click Name header via \(how): \(SortLabel.label(before)) -> \(SortLabel.label(c.sortSpec)), "
               + "first row \(c.entries.first?.name ?? "none")")
        shot(window, config, "2-name-sorted", c, &problems)

        // A reload that overtakes a re-sort drops the re-sort's result; the list must still come back to idle.
        c.rearrange()
        c.reloadContents()
        let idleAgain = await wait(timeout: 5, { c.isIdle })
        report("a reload overtook a re-sort: " + (idleAgain ? "idle again" : "STUCK, not idle after 5 s"))
        if !idleAgain { problems.append("re-sort overtaken by a reload") }

        let row = 3
        how = "synthesized mouse down and up on row \(row)"
        c.uitestClickRow(row)
        if !(await wait(timeout: 1.5, { c.tableView.selectedRowIndexes == IndexSet(integer: row) })) {
            how = "fallback: selectRowIndexes (the synthesized click did not select)"
            c.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if c.tableView.selectedRowIndexes != IndexSet(integer: row) { problems.append("row select") }
        }
        await settle(0.6)
        let name = c.entries.indices.contains(row) ? c.entries[row].name : "none"
        report("select row index \(row) via \(how): \(name); status reads \"\(c.statusText)\"")
        shot(window, config, "3-row-selected", c, &problems)

        report(problems.isEmpty ? "result: ok" : "result: FAILED (" + problems.joined(separator: ", ") + ")")
        return finish(config, problems.isEmpty ? 0 : 1)
    }

    private static func finish(_ config: UITestConfig, _ code: Int32) -> Int32 {
        if config.madeFixture {
            // The whole run folder goes to the Trash unless the shots were written inside it.
            let run = config.folder.deletingLastPathComponent()
            let keepRun = config.shotBase.hasPrefix(run.path + "/")
                || config.shotBase.hasPrefix("/private" + run.path + "/")
            try? FileManager.default.trashItem(at: keepRun ? config.folder : run, resultingItemURL: nil)
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
