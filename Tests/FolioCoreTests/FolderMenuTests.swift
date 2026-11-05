import Foundation
import Testing
@testable import FolioCore

/// The dropdown behind each crumb's arrow: the folders inside that crumb, with the one on the
/// current path marked (so the arrow after Code lists agent-expert and its siblings).
@Suite struct FolderMenuTests {
    private func makeTree() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ff-menu-\(UUID().uuidString)", isDirectory: true)
        let code = root.appendingPathComponent("Code", isDirectory: true)
        for name in ["agent-expert/sub", "beta", "Alpha", "AX10", "ax2", ".cache"] {
            try fm.createDirectory(at: code.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try fm.createDirectory(at: code.appendingPathComponent("Tool.app/Contents"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: code.appendingPathComponent("notes.txt"))
        return root
    }

    private func trash(_ url: URL) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }

    @Test func listsTheFoldersInsideTheCrumbNaturallyWithThePathOneMarked() throws {
        let root = try makeTree()
        defer { trash(root) }
        let code = root.appendingPathComponent("Code")
        let items = FolderMenu.items(in: code, current: code.appendingPathComponent("agent-expert/sub"))
        #expect(items.map(\.name) == ["agent-expert", "Alpha", "ax2", "AX10", "beta"])
        #expect(items.filter(\.isOnPath).map(\.name) == ["agent-expert"])
        #expect(items.first?.path == code.path + "/agent-expert")
    }

    @Test func theLastCrumbMarksNothing() throws {
        let root = try makeTree()
        defer { trash(root) }
        let code = root.appendingPathComponent("Code")
        let items = FolderMenu.items(in: code, current: code)
        #expect(items.count == 5)
        #expect(items.filter(\.isOnPath).isEmpty)
    }

    @Test func filesPackagesAndHiddenFoldersAreLeftOut() throws {
        let root = try makeTree()
        defer { trash(root) }
        let names = FolderMenu.items(in: root.appendingPathComponent("Code"), current: root).map(\.name)
        #expect(!names.contains("notes.txt"))
        #expect(!names.contains("Tool.app"))
        #expect(!names.contains(".cache"))
    }

    @Test func aHiddenFolderOnThePathIsStillListed() throws {
        let root = try makeTree()
        defer { trash(root) }
        let code = root.appendingPathComponent("Code")
        let items = FolderMenu.items(in: code, current: code.appendingPathComponent(".cache"))
        #expect(items.filter(\.isOnPath).map(\.name) == [".cache"])
        #expect(items.count == 6)
    }

    @Test func aMissingFolderGivesNothing() {
        let missing = URL(fileURLWithPath: "/definitely/not/here-\(UUID().uuidString)")
        #expect(FolderMenu.items(in: missing, current: missing).isEmpty)
    }
}

/// Crumbs that do not fit collapse from the left behind a « button.
@Suite struct CrumbFitTests {
    @Test func everythingFitsShowsEveryCrumb() {
        #expect(CrumbFit.firstVisible(widths: [50, 60, 70], available: 200, overflowWidth: 30) == 0)
        #expect(CrumbFit.firstVisible(widths: [100, 100], available: 200, overflowWidth: 30) == 0)
    }

    @Test func collapsesFromTheLeftLeavingRoomForTheOverflowButton() {
        // 300 wide in 200: the « takes 30, so 170 is left; 90 + 70 fit, 60 more does not.
        #expect(CrumbFit.firstVisible(widths: [80, 60, 70, 90], available: 200, overflowWidth: 30) == 2)
        #expect(CrumbFit.firstVisible(widths: [80, 60, 70, 90], available: 250, overflowWidth: 30) == 1)
    }

    @Test func theCurrentCrumbAlwaysStays() {
        #expect(CrumbFit.firstVisible(widths: [50, 400], available: 100, overflowWidth: 30) == 1)
        #expect(CrumbFit.firstVisible(widths: [50, 60, 400], available: 100, overflowWidth: 30) == 2)
    }

    @Test func aSingleCrumbNeverCollapses() {
        #expect(CrumbFit.firstVisible(widths: [400], available: 100, overflowWidth: 30) == 0)
        #expect(CrumbFit.firstVisible(widths: [], available: 100, overflowWidth: 30) == 0)
    }
}
