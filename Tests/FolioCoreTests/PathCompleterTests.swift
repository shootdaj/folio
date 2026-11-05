import Foundation
import Testing
@testable import FolioCore

/// The typeahead under the address bar, run against real folders the test makes in $TMPDIR.
@Suite struct PathCompleterTests {
    /// root/Code with folders, files, a package, a hidden folder and a folder symlink.
    private func makeTree() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ff-complete-\(UUID().uuidString)", isDirectory: true)
        let code = root.appendingPathComponent("Code", isDirectory: true)
        for name in ["agent-expert/sub", "agent-expert-tests", "ai-harness", "alpha", "Apple", "beta", "ax2", "AX10", ".agent-cache"] {
            try fm.createDirectory(at: code.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try fm.createDirectory(at: code.appendingPathComponent("App.app/Contents"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: code.appendingPathComponent("a-file.txt"))
        try Data("x".utf8).write(to: code.appendingPathComponent("ab.md"))
        try fm.createSymbolicLink(at: code.appendingPathComponent("beta-link"),
                                  withDestinationURL: code.appendingPathComponent("beta"))
        return root
    }

    private func trash(_ url: URL) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }

    private func env(home: URL) -> AddressEnvironment {
        AddressEnvironment(home: home, temp: FileManager.default.temporaryDirectory, variables: [:])
    }

    private func complete(_ text: String, root: URL, current: URL? = nil) -> Completion {
        PathCompleter.complete(text, current: current ?? root, env: env(home: root))
    }

    @Test func listsFoldersStartingWithTheLastSegmentInNaturalOrder() throws {
        let root = try makeTree()
        defer { trash(root) }
        let c = complete(root.path + "/Code/a", root: root)
        #expect(c.directory.path == root.path + "/Code")
        #expect(c.prefix == "a")
        #expect(c.names == ["agent-expert", "agent-expert-tests", "ai-harness", "alpha", "Apple", "ax2", "AX10"])
        #expect(c.total == 7)
    }

    @Test func matchingIgnoresCase() throws {
        let root = try makeTree()
        defer { trash(root) }
        #expect(complete(root.path + "/Code/AG", root: root).names == ["agent-expert", "agent-expert-tests"])
        #expect(complete(root.path + "/Code/aX", root: root).names == ["ax2", "AX10"])
    }

    @Test func onlyFoldersAreListed() throws {
        let root = try makeTree()
        defer { trash(root) }
        let names = complete(root.path + "/Code/a", root: root).names
        #expect(!names.contains("a-file.txt"))
        #expect(!names.contains("ab.md"))
        #expect(!names.contains("App.app"))
        // A symlink to a folder is a folder.
        #expect(complete(root.path + "/Code/beta", root: root).names == ["beta", "beta-link"])
    }

    @Test func showsAtMostEight() throws {
        let root = try makeTree()
        defer { trash(root) }
        let many = root.appendingPathComponent("many", isDirectory: true)
        for i in 1...12 {
            try FileManager.default.createDirectory(at: many.appendingPathComponent("f\(i)"), withIntermediateDirectories: true)
        }
        let c = complete(many.path + "/f", root: root)
        #expect(c.names == ["f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8"])
        #expect(c.total == 12)
        #expect(PathCompleter.limit == 8)
    }

    @Test func trailingSlashListsTheFoldersInside() throws {
        let root = try makeTree()
        defer { trash(root) }
        let c = complete(root.path + "/Code/", root: root)
        #expect(c.directory.path == root.path + "/Code")
        #expect(c.prefix == "")
        #expect(c.total == 9) // 8 folders and the folder symlink; no hidden folder, no package
        #expect(c.names.count == 8)
        #expect(c.names.first == "agent-expert")
        #expect(complete(root.path + "/Code/agent-expert/", root: root).names == ["sub"])
    }

    @Test func tildeExpandsToHome() throws {
        let root = try makeTree()
        defer { trash(root) }
        let c = complete("~/Code/al", root: root)
        #expect(c.directory.path == root.path + "/Code")
        #expect(c.names == ["alpha"])
    }

    @Test func dotsAreWorkedOutBeforeListing() throws {
        let root = try makeTree()
        defer { trash(root) }
        let c = complete(root.path + "/Code/alpha/../agent-expert/../ai", root: root)
        #expect(c.directory.path == root.path + "/Code")
        #expect(c.names == ["ai-harness"])
    }

    @Test func hiddenFoldersOnlyForADotPrefix() throws {
        let root = try makeTree()
        defer { trash(root) }
        #expect(complete(root.path + "/Code/.", root: root).names == [".agent-cache"])
        #expect(!complete(root.path + "/Code/", root: root).names.contains(".agent-cache"))
    }

    @Test func aMissingFolderGivesNoMatches() throws {
        let root = try makeTree()
        defer { trash(root) }
        let c = complete(root.path + "/nope/a", root: root)
        #expect(c.names.isEmpty)
        #expect(c.total == 0)
        #expect(complete(root.path + "/Code/zzz", root: root).names.isEmpty)
    }

    @Test func relativeTextCompletesInTheCurrentFolder() throws {
        let root = try makeTree()
        defer { trash(root) }
        let c = complete("al", root: root, current: root.appendingPathComponent("Code"))
        #expect(c.names == ["alpha"])
    }

    @Test func rowsShowTheFullPathWithTheTypedPartBold() throws {
        let root = try makeTree()
        defer { trash(root) }
        let c = complete("~/Code/AG", root: root)
        #expect(c.rows.map(\.path) == [root.path + "/Code/agent-expert", root.path + "/Code/agent-expert-tests"])
        // Bold covers the folder typed so far plus the matched start of the name.
        #expect(c.rows.first?.boldLength == (root.path + "/Code/ag").count)
    }

    @Test func fillingAMatchAppendsASlash() throws {
        let root = try makeTree()
        defer { trash(root) }
        let c = complete("~/Code/ag", root: root)
        #expect(c.filled(1) == root.path + "/Code/agent-expert-tests/")
        #expect(c.filled(nil) == root.path + "/Code/agent-expert/")
        #expect(complete("~/Code/zzz", root: root).filled(nil) == nil)
    }

    @Test func rootFolderRowsHaveOneSlash() {
        let c = Completion(directory: URL(fileURLWithPath: "/"), prefix: "pri", names: ["private"], total: 1)
        #expect(c.rows.first?.path == "/private")
        #expect(c.rows.first?.boldLength == 4)
        #expect(c.filled(0) == "/private/")
    }
}
