import Foundation
import Testing
@testable import FolioCore

/// Everything Folio keeps outside the session file, each written by its store and read back by a fresh
/// store on the same defaults (what a relaunch does): the accent hue, the default view, the Details
/// columns, Folder Options, the sidebar's width and folded sections, pins, favorites, recent files,
/// address history, recent searches and a saved search file.
@Suite struct PersistenceTests {
    private func defaults() -> UserDefaults {
        let name = "folio-persist-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func everyPreferenceComesBackAfterARelaunch() throws {
        let d = defaults()
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

        AccentSettings(defaults: d).hue = 55
        var view = ViewSettings(defaults: d)
        view.set(.tiles)
        view.makeDefault(in: d)
        var columns = ColumnSet.standard
        columns.toggle(.created)
        columns.setWidth(222, of: .size)
        ColumnSetStore(defaults: d).save(columns)
        var options = FolderOptions()
        options.reopenWindows = false
        options.showHidden = true
        FolderOptionsStore(defaults: d).save(options)
        SidebarStore(defaults: d).setWidth(301)
        SidebarStore(defaults: d).setCollapsed(["network", "thisPC"])
        var pins = PinStore(defaults: d, home: home)
        pins.replace(with: ["/tmp/p1", "/tmp/p2"])
        var favorites = FavoritesStore(defaults: d)
        favorites.add("/tmp/fav.txt")
        RecentFiles(defaults: d).record("/tmp/recent.txt")
        AddressHistory(defaults: d).record("/tmp/visited")
        RecentSearches(defaults: d).record("bert kind:document")

        // A relaunch: new stores, same defaults.
        #expect(AccentSettings(defaults: d).hue == 55)
        #expect(ViewSettings(defaults: d).current == .tiles)
        #expect(ColumnSetStore(defaults: d).load() == columns)
        #expect(FolderOptionsStore(defaults: d).load() == options)
        #expect(SidebarStore(defaults: d).width == 301)
        #expect(SidebarStore(defaults: d).collapsed == ["network", "thisPC"])
        #expect(PinStore(defaults: d, home: home).paths == ["/tmp/p1", "/tmp/p2"])
        #expect(FavoritesStore(defaults: d).paths == ["/tmp/fav.txt"])
        #expect(RecentFiles(defaults: d).paths.first == "/tmp/recent.txt")
        #expect(AddressHistory(defaults: d).paths.first == "/tmp/visited")
        #expect(RecentSearches(defaults: d).items == ["bert kind:document"])
    }

    @Test func aFreshMacStartsWithTheDefaults() {
        let d = defaults()
        #expect(SidebarStore(defaults: d).width == nil)
        #expect(SidebarStore(defaults: d).collapsed.isEmpty)
        let o = FolderOptionsStore(defaults: d).load()
        #expect(o.reopenWindows && o.keepRunning && o.externalFoldersInNewTab)
    }

    @Test func aSavedSearchFileComesBack() throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/saved-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let saved = SavedSearch(text: "size:large ext:mov", location: .folder(URL(fileURLWithPath: "/tmp/movies", isDirectory: true)),
                                recursive: false, view: "details", sort: [SortTerm(key: .size, ascending: false)])
        let file = try saved.write(to: dir.appendingPathComponent("Large movies.foliosearch"))
        #expect(try SavedSearch.read(from: file) == saved)
    }
}
