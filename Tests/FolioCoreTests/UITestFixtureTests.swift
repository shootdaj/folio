import Foundation
import Testing
@testable import FolioCore

@Suite struct UITestFixtureTests {
    @Test func makesFortyFoldersAndEightFilesWithFixedDates() throws {
        let run = URL(fileURLWithPath: "/private/tmp/folio-tests/fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.trashItem(at: run, resultingItemURL: nil) }
        let folder = try UITestFixture.make(at: run.appendingPathComponent("Code", isDirectory: true))

        let rows = try FolderListing.list(folder, sortedBy: .standard)
        #expect(rows.count == 48)
        #expect(rows.filter(\.isFolder).count == 40)
        #expect(rows.filter { !$0.isFolder }.count == 8)
        // Name order puts D1's selected row, ai-harness, fourth.
        #expect(rows.prefix(4).map(\.name) == ["agent-expert", "agent-expert-tests", "ai-crypto-alpha", "ai-harness"])
        let md = try #require(rows.first { $0.name == "airbnb-bangkok-search.md" })
        #expect(md.size == 3917)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: try #require(md.modified))
        #expect([parts.year, parts.month, parts.day, parts.hour, parts.minute] == [2026, 1, 9, 8, 42])
    }

    @Test func refusesAnythingOutsideTheTestRoots() {
        #expect(UITestFixture.isAllowed(URL(fileURLWithPath: "/private/tmp/folio-tests/run1/Code")))
        #expect(UITestFixture.isAllowed(URL(fileURLWithPath: "/tmp/folio-tests/run1")))
        #expect(UITestFixture.isAllowed(URL(fileURLWithPath: "/Volumes/FolioScratch/a")))
        #expect(!UITestFixture.isAllowed(URL(fileURLWithPath: "/private/tmp/folio-tests")))
        #expect(!UITestFixture.isAllowed(URL(fileURLWithPath: "/private/tmp/folio-tests/../../Users/x")))
        #expect(!UITestFixture.isAllowed(URL(fileURLWithPath: "/Users/anshul/Anshul/Code")))
        #expect(!UITestFixture.isAllowed(URL(fileURLWithPath: "/Volumes/Backup/Code")))
        #expect(throws: UITestFixture.FixtureError.self) {
            try UITestFixture.make(at: URL(fileURLWithPath: "/private/tmp/not-a-test-root/x"))
        }
    }
}
