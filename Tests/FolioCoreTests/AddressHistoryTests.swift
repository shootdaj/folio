import Foundation
import Testing
@testable import FolioCore

/// The address bar's history dropdown (F4): a real UserDefaults whose plist lives in a temp folder.
@Suite struct AddressHistoryTests {
    private func withTempDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let suite = dir.appendingPathComponent("prefs").path
        let defaults = try #require(UserDefaults(suiteName: suite))
        try body(defaults, suite)
    }

    @Test func startsEmpty() throws {
        try withTempDefaults { defaults, _ in
            #expect(AddressHistory(defaults: defaults).paths.isEmpty)
        }
    }

    @Test func mostRecentComesFirst() throws {
        try withTempDefaults { defaults, _ in
            let history = AddressHistory(defaults: defaults)
            for path in ["/a", "/b", "/c"] { history.record(path) }
            #expect(history.paths == ["/c", "/b", "/a"])
        }
    }

    @Test func revisitingMovesAPathToTheTopWithoutADuplicate() throws {
        try withTempDefaults { defaults, _ in
            let history = AddressHistory(defaults: defaults)
            for path in ["/a", "/b", "/c", "/a"] { history.record(path) }
            #expect(history.paths == ["/a", "/c", "/b"])
        }
    }

    @Test func theSameFolderWrittenTwoWaysIsOneEntry() throws {
        try withTempDefaults { defaults, _ in
            let history = AddressHistory(defaults: defaults)
            history.record("/private/tmp/x/")
            history.record("/private//tmp/./x")
            #expect(history.paths == ["/private/tmp/x"])
        }
    }

    @Test func keepsTheLastTwenty() throws {
        try withTempDefaults { defaults, _ in
            let history = AddressHistory(defaults: defaults)
            for i in 1...25 { history.record("/f\(i)") }
            #expect(AddressHistory.limit == 20)
            #expect(history.paths.count == 20)
            #expect(history.paths.first == "/f25")
            #expect(history.paths.last == "/f6")
        }
    }

    @Test func persistsAcrossLaunches() throws {
        try withTempDefaults { defaults, suite in
            AddressHistory(defaults: defaults).record("/x")
            AddressHistory(defaults: defaults).record("/y")
            let again = AddressHistory(defaults: try #require(UserDefaults(suiteName: suite)))
            #expect(again.paths == ["/y", "/x"])
            #expect(defaults.stringArray(forKey: AddressHistory.key) == ["/y", "/x"])
        }
    }

    @Test func recentLocationsAreTheSameList() throws {
        try withTempDefaults { defaults, _ in
            let history = AddressHistory(defaults: defaults)
            history.record("/x")
            history.record("/y")
            #expect(history.recentLocations.map(\.path) == ["/y", "/x"])
        }
    }

    @Test func emptyPathsAreIgnored() throws {
        try withTempDefaults { defaults, _ in
            let history = AddressHistory(defaults: defaults)
            history.record("")
            history.record("   ")
            #expect(history.paths.isEmpty)
        }
    }
}
