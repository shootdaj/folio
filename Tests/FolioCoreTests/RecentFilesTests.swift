import Foundation
import Testing
@testable import FolioCore

/// Home's Recent files (the last 30 files Folio opened, plus the system's recent documents) and
/// Favorites (Add to Favorites, Remove from Favorites).
@Suite struct RecentFilesTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/recent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let defaults = try #require(UserDefaults(suiteName: dir.appendingPathComponent("prefs").path))
        try body(defaults)
    }

    @Test func newestFirstAndCappedAtThirty() throws {
        try withDefaults { d in
            let recent = RecentFiles(defaults: d)
            for i in 1...35 { recent.record("/tmp/r/file\(i).txt") }
            #expect(recent.paths.count == 30)
            #expect(recent.paths.first == "/tmp/r/file35.txt")
            #expect(recent.paths.last == "/tmp/r/file6.txt")
            #expect(RecentFiles(defaults: d).paths == recent.paths, "kept across launches")
        }
    }

    @Test func openingAFileAgainMovesItUpInsteadOfListingItTwice() throws {
        try withDefaults { d in
            let recent = RecentFiles(defaults: d)
            recent.record("/tmp/r/a.txt")
            recent.record("/tmp/r/b.txt")
            recent.record("/tmp/r/a.txt")
            #expect(recent.paths == ["/tmp/r/a.txt", "/tmp/r/b.txt"])
            recent.remove("/tmp/r/b.txt")
            #expect(recent.paths == ["/tmp/r/a.txt"])
        }
    }

    @Test func mergingWithTheSystemListDedupesAndCaps() {
        let own = (1...20).map { "/tmp/r/own\($0)" }
        let system = ["/tmp/r/own3", "/tmp/r/sys1"] + (1...20).map { "/tmp/r/sys-x\($0)" }
        let merged = RecentFiles.merged(own: own, system: system)
        #expect(merged.count == 30)
        #expect(Array(merged.prefix(20)) == own, "Folio's own log comes first")
        #expect(merged[20] == "/tmp/r/sys1", "own3 was already there")
        #expect(Set(merged).count == merged.count)
    }

    @Test func favoritesAddRemoveAndToggle() throws {
        try withDefaults { d in
            var favorites = FavoritesStore(defaults: d)
            #expect(favorites.paths.isEmpty)
            favorites.add("/tmp/f/a.txt")
            favorites.add("/tmp/f/b")
            favorites.add("/tmp/f/a.txt")
            #expect(favorites.paths == ["/tmp/f/b", "/tmp/f/a.txt"], "newest first, no doubles")
            #expect(favorites.contains("/tmp/f/b"))
            favorites.toggle("/tmp/f/b")
            #expect(!favorites.contains("/tmp/f/b"))
            favorites.remove("/tmp/f/a.txt")
            #expect(FavoritesStore(defaults: d).paths.isEmpty)
        }
    }
}
