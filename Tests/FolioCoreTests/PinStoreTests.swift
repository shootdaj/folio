import Foundation
import Testing
@testable import FolioCore

/// Quick access pins: D1's favourites until something is pinned, drop-to-pin at a place, drag to
/// reorder, unpin, and the order kept across launches.
@Suite struct PinStoreTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/pins-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let defaults = try #require(UserDefaults(suiteName: dir.appendingPathComponent("prefs").path))
        try body(defaults)
    }

    @Test func startsWithD1sFavourites() throws {
        try withDefaults { d in
            let store = PinStore(defaults: d, home: home)
            #expect(store.paths == QuickAccess.defaults.map { "/Users/someone/" + $0 })
            #expect(store.places.first == QuickAccessPlace(title: "Code", prefix: "Anshul/", path: "/Users/someone/Anshul/Code"))
        }
    }

    @Test func pinningAddsAtTheEndOrAtTheDropPlace() throws {
        try withDefaults { d in
            var store = PinStore(defaults: d, home: home)
            store.replace(with: ["/a", "/b"])
            store.pin("/c")
            #expect(store.paths == ["/a", "/b", "/c"])
            store.pin("/d", at: 1)
            #expect(store.paths == ["/a", "/d", "/b", "/c"])
            store.pin("/e", at: 99)
            #expect(store.paths.last == "/e")
            #expect(store.isPinned("/d"))
        }
    }

    @Test func pinningAPinnedFolderMovesItInsteadOfAddingTwice() throws {
        try withDefaults { d in
            var store = PinStore(defaults: d, home: home)
            store.replace(with: ["/a", "/b", "/c"])
            store.pin("/c", at: 0)
            #expect(store.paths == ["/c", "/a", "/b"])
            store.pin("/a/")
            #expect(store.paths == ["/c", "/b", "/a"])
        }
    }

    @Test func dragToReorderUsesTheInsertionPlace() throws {
        try withDefaults { d in
            var store = PinStore(defaults: d, home: home)
            store.replace(with: ["/a", "/b", "/c", "/d"])
            store.move(from: 0, to: 3)        // drop a between c and d
            #expect(store.paths == ["/b", "/c", "/a", "/d"])
            store.move(from: 3, to: 0)        // d to the top
            #expect(store.paths == ["/d", "/b", "/c", "/a"])
            store.move(from: 1, to: 4)        // b to the end
            #expect(store.paths == ["/d", "/c", "/a", "/b"])
            store.move(from: 2, to: 2)        // dropped where it was
            #expect(store.paths == ["/d", "/c", "/a", "/b"])
        }
    }

    @Test func unpinRemovesAndTheOrderSurvivesARelaunch() throws {
        try withDefaults { d in
            var store = PinStore(defaults: d, home: home)
            store.replace(with: ["/a", "/b", "/c"])
            store.unpin("/b")
            store.move(from: 1, to: 0)
            #expect(PinStore(defaults: d, home: home).paths == ["/c", "/a"])
            store.unpin("/a")
            store.unpin("/c")
            // Unpinning everything leaves Quick access empty, not back at the favourites.
            #expect(PinStore(defaults: d, home: home).paths.isEmpty)
        }
    }

    @Test func placesNameTheFolderAndShowItsParentInsideHome() throws {
        try withDefaults { d in
            var store = PinStore(defaults: d, home: home)
            store.replace(with: ["/Users/someone/Downloads", "/Users/someone/Work/Site", "/Volumes/Scratch/raw", "/"])
            #expect(store.places.map(\.title) == ["Downloads", "Site", "raw", "/"])
            #expect(store.places.map(\.prefix) == ["", "Work/", "Scratch/", ""])
        }
    }
}
