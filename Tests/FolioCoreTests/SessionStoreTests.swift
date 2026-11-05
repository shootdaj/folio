import Foundation
import Testing
@testable import FolioCore

/// The session store: every window's frame and tabs (each tab's folder, history and sort) saved to the
/// defaults and read back on the next launch.
@Suite struct SessionStoreTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let defaults = try #require(UserDefaults(suiteName: dir.appendingPathComponent("prefs").path))
        try body(defaults)
    }

    private func url(_ p: String) -> URL { URL(fileURLWithPath: p, isDirectory: true) }

    @Test func windowsTabsAndFramesRoundTrip() throws {
        try withDefaults { d in
            var first = BrowserTab(folder: url("/tmp/s/a"))
            first.history.push(url("/tmp/s/a/b"))
            first.sort = SortSpec(key: .modified, ascending: false)
            var home = BrowserTab(folder: url("/tmp/s/c"))
            home.history.push(NavigationHistory.home)
            let session = Session(windows: [
                WindowSession(frame: SessionFrame(x: 10, y: 20, width: 900, height: 600),
                              tabs: [TabSession(first), TabSession(home)], active: 1),
                WindowSession(frame: SessionFrame(x: 400, y: 50, width: 700, height: 500),
                              tabs: [TabSession(BrowserTab(folder: url("/tmp/s/z")))], active: 0),
            ])
            let store = SessionStore(defaults: d)
            store.save(session)
            let back = try #require(SessionStore(defaults: d).load())
            #expect(back == session)
            #expect(back.windows[0].frame.width == 900)
            #expect(back.windows[0].tabs[0].path == "/tmp/s/a/b")
            #expect(back.windows[0].tabs[0].back == ["/tmp/s/a"])
            #expect(back.windows[0].tabs[1].path == NavigationHistory.homePath)
            #expect(back.windows[0].active == 1)
        }
    }

    @Test func aRestoredTabHasItsFolderHistoryAndSort() throws {
        var tab = BrowserTab(folder: url("/tmp/s/a"))
        tab.history.push(url("/tmp/s/b"))
        tab.history.push(url("/tmp/s/c"))
        _ = tab.history.goBack()
        tab.sort = SortSpec(key: .size, ascending: true)
        let restored = TabSession(tab).tab(exists: { _ in true })
        #expect(restored.current.path == "/tmp/s/b")
        #expect(restored.history.backList.map(\.path) == ["/tmp/s/a"])
        #expect(restored.history.forwardList.map(\.path) == ["/tmp/s/c"])
        #expect(restored.sort == SortSpec(key: .size, ascending: true))
        let home = TabSession(BrowserTab(folder: NavigationHistory.home)).tab(exists: { _ in false })
        #expect(home.history.isHome, "Home never goes missing")
    }

    @Test func aFolderThatIsGoneOpensItsNearestParent() {
        let tab = BrowserTab(folder: url("/tmp/s/gone/deeper"))
        let restored = TabSession(tab).tab(exists: { $0 == "/tmp/s" || $0 == "/tmp" || $0 == "/" })
        #expect(restored.current.path == "/tmp/s")
    }

    @Test func anEmptyStoreHasNoSessionAndClearForgetsIt() throws {
        try withDefaults { d in
            let store = SessionStore(defaults: d)
            #expect(store.load() == nil)
            store.save(Session(windows: [WindowSession(frame: SessionFrame(x: 0, y: 0, width: 1, height: 1),
                                                       tabs: [TabSession(BrowserTab(folder: url("/tmp")))], active: 0)]))
            #expect(store.load() != nil)
            store.clear()
            #expect(store.load() == nil)
            d.set(Data("not json".utf8), forKey: SessionStore.key)
            #expect(store.load() == nil, "a damaged session is ignored, not a crash")
        }
    }

    @Test func activeIndexOutOfRangeIsClamped() {
        let w = WindowSession(frame: SessionFrame(x: 0, y: 0, width: 1, height: 1),
                              tabs: [TabSession(BrowserTab(folder: url("/tmp")))], active: 7)
        #expect(w.clampedActive == 0)
    }
}
