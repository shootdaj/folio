import Darwin
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

@Suite struct CleanupSamplesTests {
    private func newRoot() -> URL {
        URL(fileURLWithPath: "/private/tmp/folio-tests/cleanup-\(UUID().uuidString)/Home", isDirectory: true)
    }

    private func close(_ root: URL) {
        try? FileManager.default.trashItem(at: root.deletingLastPathComponent(), resultingItemURL: nil)
    }

    @Test func cleanupSamplesAreOnlyMadeUnderATestRoot() {
        #expect(throws: UITestFixture.FixtureError.self) {
            try UITestFixture.makeCleanupSamples(at: URL(fileURLWithPath: "/private/tmp/not-a-test-root/Home"), unit: 1024)
        }
        #expect(throws: UITestFixture.FixtureError.self) {
            try UITestFixture.makeCleanupSamples(at: URL(fileURLWithPath: "/Users/someone/Home"), unit: 1024)
        }
        #expect(!FileManager.default.fileExists(atPath: "/private/tmp/not-a-test-root"))
    }

    @Test func cleanupSamplesHaveTheirSizesDatesAndBrokenLink() throws {
        let root = newRoot()
        defer { close(root) }
        let now = Date()
        try UITestFixture.makeCleanupSamples(at: root, unit: 1024, now: now)

        func info(_ path: String) throws -> Darwin.stat {
            var st = Darwin.stat()
            #expect(lstat(root.appendingPathComponent(path).path, &st) == 0, "\(path)")
            return st
        }
        func bytes(_ path: String) -> Data? { try? Data(contentsOf: root.appendingPathComponent(path)) }

        // Sizes: units of 1024 bytes of real data, not sparse.
        #expect(try info("Movies/old-trip-4k.mov").st_size == 64 * 1024)
        #expect(try info("Documents/archive/backup-2023.zip").st_size == 56 * 1024)
        #expect(try info("Downloads/Install Tool 2.1.dmg").st_size == 40 * 1024)
        #expect(try info("Applications/Tool.app/Contents/Resources/big.bin").st_size == 60 * 1024)
        #expect(try info("Movies/old-trip-4k.mov").st_blocks * 512 >= 64 * 1024)

        // The duplicates are equal and the decoys differ.
        let a = try #require(bytes("Documents/report-final.mov"))
        #expect(a.count == 24 * 1024)
        #expect(a == bytes("Desktop/report-final copy.mov"))
        #expect(bytes("Documents/notes-a.bin")?.count == 24 * 1024)
        #expect(bytes("Documents/notes-a.bin") != bytes("Desktop/notes-b.bin"))
        #expect(bytes("Movies/old-trip-4k.mov") != bytes("Movies/new-edit.mov"))
        #expect(bytes("Movies/old-trip-4k.mov")?.count == bytes("Movies/new-edit.mov")?.count)

        // The broken link is a link whose target is missing.
        let link = try info("Desktop/Old Shortcut")
        #expect((link.st_mode & S_IFMT) == S_IFLNK)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent("Desktop/Old Shortcut").path)
                == root.appendingPathComponent("Documents/moved-away.txt").path)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Desktop/Old Shortcut").path))

        // The folders and files that stay are there.
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Documents/Empty Project").path, isDirectory: &isDir) && isDir.boolValue)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Documents/Empty Project").path).isEmpty)
        #expect(try info("Library/Preferences/com.example.plist").st_size > 0)
        #expect(try info(".Trash/old-draft.mov").st_size == 30 * 1024)

        // Dates: modified, accessed and added agree, and a folder is old too.
        func seconds(_ ts: timespec) -> Int { ts.tv_sec }
        let old = try info("Movies/old-trip-4k.mov")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let want = Int(try #require(formatter.date(from: "2024-03-10 00:00")).timeIntervalSince1970)
        #expect(seconds(old.st_mtimespec) == want)
        #expect(seconds(old.st_atimespec) == want)
        let added = try root.appendingPathComponent("Movies/old-trip-4k.mov").resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate
        #expect(Int(try #require(added).timeIntervalSince1970) == want)

        let recent = try info("Movies/new-edit.mov")
        #expect(abs(Double(seconds(recent.st_mtimespec)) - now.addingTimeInterval(-86_400).timeIntervalSince1970) < 2)
        #expect(abs(Double(seconds(recent.st_atimespec)) - now.addingTimeInterval(-86_400).timeIntervalSince1970) < 2)

        // Folders were dated last, so they are old, not the time the samples were written.
        let folder = try info("Documents/Empty Project")
        #expect(Double(seconds(folder.st_mtimespec)) < now.addingTimeInterval(-30 * 86_400).timeIntervalSince1970)
        #expect(Double(seconds(try info("Documents").st_mtimespec)) < now.addingTimeInterval(-30 * 86_400).timeIntervalSince1970)
    }
}
