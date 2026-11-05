import Foundation
import Testing
@testable import FolioCore

/// The session file: every window (its frame and the display it was on, its tabs, the tree's open
/// folders) and every tab (folder, Back and Forward, sort, grouping, selection, scroll place, a search
/// shown), plus the one view, written as they change and read back on the next launch. A damaged file
/// is moved aside and the app starts fresh.
@Suite struct SessionStoreTests {
    private func withStore(_ body: (SessionStore, URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/session-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let file = dir.appendingPathComponent("Folio/session.json")
        try body(SessionStore(url: file), file)
    }

    private func url(_ p: String) -> URL { URL(fileURLWithPath: p, isDirectory: true) }

    /// A session where every field differs from its default.
    private func fullSession() -> Session {
        var first = BrowserTab(folder: url("/tmp/s/a"))
        first.history.push(url("/tmp/s/a/b"))
        first.history.push(url("/tmp/s/a/b/c"))
        _ = first.history.goBack()
        first.sort = SortSpec(key: .size, ascending: false, then: [SortTerm(key: .name, ascending: true)])
        first.group = GroupSpec(key: .kind, ascending: false)
        first.selection = ["/tmp/s/a/b/x.txt", "/tmp/s/a/b/y.txt"]
        first.scrollRow = 42
        var searching = BrowserTab(folder: url("/tmp/s/work"))
        searching.history.push(url("/tmp/s/work"), search: HistorySearch(text: "bert kind:document", recursive: false, everywhere: false))
        var home = BrowserTab(folder: url("/tmp/s/c"))
        home.history.push(NavigationHistory.home)
        return Session(windows: [
            WindowSession(frame: SessionFrame(x: 10, y: 20, width: 900, height: 600),
                          display: SessionDisplay(name: "Studio Display", frame: SessionFrame(x: 0, y: 0, width: 2560, height: 1440)),
                          tabs: [TabSession(first), TabSession(searching), TabSession(home)], active: 1,
                          expandedFolders: ["/", "/tmp/s", "/tmp/s/a"]),
            WindowSession(frame: SessionFrame(x: 2600, y: 50, width: 700, height: 500),
                          display: SessionDisplay(name: "Built-in Retina Display", frame: SessionFrame(x: 2560, y: 0, width: 1512, height: 982)),
                          tabs: [TabSession(BrowserTab(folder: url("/tmp/s/z")))], active: 0, expandedFolders: []),
        ], viewMode: "largeIcons")
    }

    @Test func everyFieldRoundTripsThroughTheFile() throws {
        try withStore { store, file in
            let session = fullSession()
            try store.save(session)
            #expect(FileManager.default.fileExists(atPath: file.path), "the folder is made on the first save")
            guard case .session(let back) = SessionStore(url: file).load() else {
                Issue.record("no session read back")
                return
            }
            #expect(back == session)
            let w = back.windows[0]
            #expect(w.frame == SessionFrame(x: 10, y: 20, width: 900, height: 600))
            #expect(w.display?.name == "Studio Display")
            #expect(w.active == 1)
            #expect(w.expandedFolders == ["/", "/tmp/s", "/tmp/s/a"])
            let t = w.tabs[0]
            #expect(t.path == "/tmp/s/a/b")
            #expect(t.back == ["/tmp/s/a"] && t.forward == ["/tmp/s/a/b/c"])
            #expect(t.sortKey == "size" && !t.ascending && t.thenKeys == [SortTerm(key: .name, ascending: true)])
            #expect(t.group == GroupSpec(key: .kind, ascending: false))
            #expect(t.selection == ["/tmp/s/a/b/x.txt", "/tmp/s/a/b/y.txt"])
            #expect(t.scrollRow == 42)
            #expect(w.tabs[1].search == SearchSession(text: "bert kind:document", recursive: false, everywhere: false))
            #expect(w.tabs[2].path == NavigationHistory.homePath)
            #expect(back.viewMode == "largeIcons")
            #expect(back.windows[1].display?.name == "Built-in Retina Display")
        }
    }

    @Test func aRestoredTabHasItsFolderHistorySortSelectionScrollAndSearch() {
        let session = fullSession()
        let restored = session.windows[0].tabs[0].tab(exists: { _ in true })
        #expect(restored.current.path == "/tmp/s/a/b")
        #expect(restored.history.backList.map(\.path) == ["/tmp/s/a"])
        #expect(restored.history.forwardList.map(\.path) == ["/tmp/s/a/b/c"])
        #expect(restored.sort == SortSpec(key: .size, ascending: false, then: [SortTerm(key: .name, ascending: true)]))
        #expect(restored.group == GroupSpec(key: .kind, ascending: false))
        #expect(restored.selection == ["/tmp/s/a/b/x.txt", "/tmp/s/a/b/y.txt"])
        #expect(restored.scrollRow == 42)
        #expect(restored.history.search == nil)
        var search = session.windows[0].tabs[1].tab(exists: { _ in true })
        #expect(search.history.search == HistorySearch(text: "bert kind:document", recursive: false, everywhere: false))
        #expect(search.current.path == "/tmp/s/work")
        _ = search.history.goBack()
        #expect(search.history.search == nil && search.current.path == "/tmp/s/work", "Back from the results is the plain folder")
        let home = session.windows[0].tabs[2].tab(exists: { _ in false })
        #expect(home.history.isHome, "Home never goes missing")
    }

    @Test func aFolderThatIsGoneOpensItsNearestParentWithoutItsSelectionOrSearch() {
        var tab = BrowserTab(folder: url("/tmp/s/gone/deeper"))
        tab.selection = ["/tmp/s/gone/deeper/a"]
        tab.scrollRow = 9
        tab.history.push(url("/tmp/s/gone/deeper"), search: HistorySearch(text: "x"))
        let restored = TabSession(tab).tab(exists: { $0 == "/tmp/s" || $0 == "/tmp" || $0 == "/" })
        #expect(restored.current.path == "/tmp/s")
        #expect(restored.selection.isEmpty && restored.scrollRow == 0 && restored.history.search == nil)
    }

    @Test func sessionsWrittenBeforeMilestone9StillRead() throws {
        try withStore { store, file in
            let old = #"{"windows":[{"frame":{"x":1,"y":2,"width":800,"height":500},"tabs":[{"path":"/tmp","back":[],"forward":[],"sortKey":"name","ascending":true}],"active":0}]}"#
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(old.utf8).write(to: file)
            guard case .session(let s) = store.load() else { Issue.record("old session not read"); return }
            #expect(s.windows[0].tabs[0].path == "/tmp")
            #expect(s.windows[0].display == nil && s.windows[0].expandedFolders == nil && s.viewMode == nil)
            #expect(s.windows[0].tabs[0].selection == nil && s.windows[0].tabs[0].scrollRow == nil)
        }
    }

    @Test func aCorruptFileIsMovedAsideAndTheAppStartsFresh() throws {
        try withStore { store, file in
            #expect(store.load() == .none, "no file yet: nothing to restore")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("garbage\n".utf8).write(to: file)
            let result = store.load(now: Date(timeIntervalSince1970: 1_800_000_000))
            guard case .corrupt(let aside) = result, let aside else {
                Issue.record("garbage was not reported as corrupt: \(result)")
                return
            }
            #expect(!FileManager.default.fileExists(atPath: file.path), "the bad file is out of the way")
            #expect(aside.deletingLastPathComponent() == file.deletingLastPathComponent())
            #expect(aside.lastPathComponent.hasPrefix("session.corrupt-") && aside.pathExtension == "json")
            #expect(try String(contentsOf: aside, encoding: .utf8) == "garbage\n", "kept for a look, not deleted")
            #expect(store.load() == .none, "the next launch starts fresh")
            try store.save(fullSession())
            #expect(store.load() == .session(fullSession()), "and the next save writes a good file again")
        }
    }

    @Test func anEmptyOrTruncatedFileIsCorruptToo() throws {
        try withStore { store, file in
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            for bad in ["", "{\"windows\":[{\"frame\":", "{\"windows\":\"no\"}"] {
                try Data(bad.utf8).write(to: file)
                guard case .corrupt = store.load() else { Issue.record("[\(bad)] read as a session"); continue }
            }
        }
    }

    @Test func clearRemovesTheFile() throws {
        try withStore { store, file in
            try store.save(Session(windows: []))
            store.clear()
            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(store.load() == .none)
        }
    }

    @Test func activeIndexOutOfRangeIsClamped() {
        let w = WindowSession(frame: SessionFrame(x: 0, y: 0, width: 1, height: 1),
                              tabs: [TabSession(BrowserTab(folder: url("/tmp")))], active: 7)
        #expect(w.clampedActive == 0)
    }

    @Test func savesWaitHalfASecond() {
        #expect(SessionStore.coalesce == 0.5)
        #expect(SessionStore.defaultURL(home: url("/Users/x")).path == "/Users/x/Library/Application Support/Folio/session.json")
    }
}

/// Window frames per display: a window goes back to the screen it was on, follows that screen when the
/// arrangement moved it, and comes onto the main screen when its screen is gone.
@Suite struct WindowPlacementTests {
    let studio = ScreenInfo(name: "Studio Display", frame: SessionFrame(x: 0, y: 0, width: 2560, height: 1440),
                            visible: SessionFrame(x: 0, y: 0, width: 2560, height: 1415))
    let laptop = ScreenInfo(name: "Built-in Retina Display", frame: SessionFrame(x: 2560, y: 0, width: 1512, height: 982),
                            visible: SessionFrame(x: 2560, y: 0, width: 1512, height: 950))

    @Test func sameScreenSameFrame() {
        let f = SessionFrame(x: 100, y: 200, width: 900, height: 600)
        let placed = WindowPlacement.place(f, display: SessionDisplay(name: "Studio Display", frame: studio.frame),
                                           screens: [studio, laptop])
        #expect(placed == f)
        let onLaptop = SessionFrame(x: 2700, y: 100, width: 800, height: 500)
        #expect(WindowPlacement.place(onLaptop, display: SessionDisplay(name: "Built-in Retina Display", frame: laptop.frame),
                                      screens: [studio, laptop]) == onLaptop)
    }

    @Test func aScreenThatMovedTakesItsWindowsAlong() {
        // The laptop is now left of the studio display.
        let movedLaptop = ScreenInfo(name: laptop.name, frame: SessionFrame(x: -1512, y: 0, width: 1512, height: 982),
                                     visible: SessionFrame(x: -1512, y: 0, width: 1512, height: 950))
        let f = SessionFrame(x: 2700, y: 100, width: 800, height: 500)
        let placed = WindowPlacement.place(f, display: SessionDisplay(name: laptop.name, frame: laptop.frame),
                                           screens: [studio, movedLaptop])
        #expect(placed == SessionFrame(x: -1372, y: 100, width: 800, height: 500))
    }

    @Test func aScreenThatIsGoneSendsItsWindowsToTheMainScreenCentred() {
        let f = SessionFrame(x: 2700, y: 100, width: 800, height: 500)
        let placed = WindowPlacement.place(f, display: SessionDisplay(name: laptop.name, frame: laptop.frame), screens: [studio])
        #expect(placed == SessionFrame(x: 880, y: 457.5, width: 800, height: 500))
        // Too big for the screen left: it shrinks to fit.
        let big = SessionFrame(x: 2560, y: 0, width: 3000, height: 2000)
        let fitted = WindowPlacement.place(big, display: nil, screens: [laptop])
        #expect(fitted == SessionFrame(x: 2560, y: 0, width: 1512, height: 950))
    }

    @Test func noDisplayRecordedKeepsAFrameThatIsOnAScreen() {
        let f = SessionFrame(x: 100, y: 100, width: 600, height: 400)
        #expect(WindowPlacement.place(f, display: nil, screens: [studio, laptop]) == f)
    }
}
