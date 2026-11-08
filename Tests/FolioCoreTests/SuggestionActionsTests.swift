import Foundation
import Testing
@testable import FolioCore

/// Which rows a Move to Trash may take, and the checks before it. A fake disk stands in for lstat.
@Suite struct SuggestionActionsTests {
    private struct FakeFS: ScanFileSystem {
        var stamps: [String: ItemStamp]
        func list(_ dir: URL) throws(ScanReadError) -> [ScanEntry] { [] }
        func lastUsed(_ url: URL) -> Date? { nil }
        func linkTarget(_ url: URL, alias: Bool) -> LinkTarget { .exists }
        func mayShareBlocks(_ url: URL) -> Bool { false }
        func stamp(_ url: URL) -> ItemStamp? { stamps[url.path] }
    }

    private func item(_ path: String, bytes: Int64 = 100, ino: UInt64 = 1) -> SuggestionItem {
        SuggestionItem(url: URL(fileURLWithPath: path), isFolder: false, bytes: bytes, logicalBytes: bytes,
                       stamp: ItemStamp(device: 1, inode: ino, logical: bytes, modified: nil))
    }

    private func single(_ kind: SuggestionKind, _ path: String, bytes: Int64 = 100, ino: UInt64 = 1) -> Suggestion {
        let i = item(path, bytes: bytes, ino: ino)
        return Suggestion(kind: kind, id: i.id, items: [i], bytes: bytes, reason: .emptyFolder)
    }

    private func group(_ paths: [String], sha: String = "abc", share: Bool = false) -> Suggestion {
        let items = paths.enumerated().map { item($1, ino: UInt64($0 + 10)) }
        let reason = SuggestionReason.sameContent(copies: items.count, sha256: sha, mayShareBlocks: share)
        return Suggestion(kind: .duplicates, id: "dup:" + sha, items: items, keep: items[0].url,
                          bytes: Suggestion.saving(items, keep: items[0].url, reason: reason), reason: reason)
    }

    private func disk(_ suggestions: [Suggestion]) -> FakeFS {
        var stamps: [String: ItemStamp] = [:]
        for s in suggestions { for i in s.items { stamps[i.url.path] = i.stamp } }
        return FakeFS(stamps: stamps)
    }

    private let none = SuggestionIgnores.Snapshot()

    // MARK: Selection

    @Test func aBatchTakesTheRowsAndNeverAKeptCopyOrTheTrash() {
        let a = single(.largeUnused, "/t/a.bin", bytes: 500, ino: 1)
        let g = group(["/t/k/one.txt", "/t/k/two.txt", "/t/k/three.txt"])
        let trash = single(.trash, "/t/.Trash", bytes: 900, ino: 5)
        let chosen = SuggestionActions.selection(of: [a, g, trash], pending: [], ignores: none)
        let urls = chosen.items.map(\.url.path)
        #expect(urls == ["/t/a.bin", "/t/k/two.txt", "/t/k/three.txt"])
        #expect(!urls.contains("/t/k/one.txt"), "the kept copy stays")
        #expect(!urls.contains("/t/.Trash"))
        #expect(chosen.count == 3)
        #expect(chosen.bytes == 500 + g.bytes)
    }

    @Test func pendingAndIgnoredRowsAreLeftOut() {
        let a = single(.largeUnused, "/t/a.bin", ino: 1)
        let b = single(.oldDownloads, "/t/Downloads/b.zip", ino: 2)
        let c = single(.oldDownloads, "/t/Downloads/inner/c.zip", ino: 3)
        let ignored = SuggestionIgnores.Snapshot(paths: [FilePaths.itemKey(URL(fileURLWithPath: "/t/Downloads/inner"))])
        let chosen = SuggestionActions.selection(of: [a, b, c], pending: [a.items[0].id], ignores: ignored)
        #expect(chosen.items.map(\.url.path) == ["/t/Downloads/b.zip"])
    }

    @Test func aGroupWithAnIgnoredHashIsLeftOut() {
        let g = group(["/t/x/1", "/t/x/2"], sha: "deadbeef")
        let chosen = SuggestionActions.selection(of: [g], pending: [], ignores: SuggestionIgnores.Snapshot(hashes: ["deadbeef"]))
        #expect(chosen.isEmpty)
    }

    @Test func oneItemIsTakenOnlyWhenItIsAllowed() {
        let g = group(["/t/x/1", "/t/x/2", "/t/x/3"])
        let kept = SuggestionActions.selection(of: [g], item: g.items[0], pending: [], ignores: none)
        #expect(kept.isEmpty, "the kept copy never goes")
        let other = SuggestionActions.selection(of: [g], item: g.items[1], pending: [], ignores: none)
        #expect(other.items.map(\.url.path) == ["/t/x/2"])
        #expect(other.bytes == 100)
        let trash = single(.trash, "/t/.Trash", ino: 9)
        #expect(SuggestionActions.selection(of: [trash], item: trash.items[0], pending: [], ignores: none).isEmpty)
    }

    // MARK: Plan

    @Test func aChangedFileIsNotMoved() {
        let a = single(.largeUnused, "/t/a.bin", ino: 1)
        let b = single(.largeUnused, "/t/b.bin", ino: 2)
        var fs = disk([a, b])
        fs.stamps["/t/b.bin"] = ItemStamp(device: 1, inode: 77, logical: 100, modified: nil)
        let plan = SuggestionActions.trashPlan(of: [a, b], pending: [], ignores: none, fs: fs)
        #expect(plan.urls.map(\.path) == ["/t/a.bin"])
        #expect(plan.keys == [a.items[0].id])
        #expect(plan.changed == 1)
        #expect(plan.bytes == 100)
    }

    @Test func aFileThatIsGoneIsNotMoved() {
        let a = single(.largeUnused, "/t/a.bin", ino: 1)
        let plan = SuggestionActions.trashPlan(of: [a], pending: [], ignores: none, fs: FakeFS(stamps: [:]))
        #expect(plan.isEmpty)
        #expect(plan.changed == 1)
    }

    @Test func aChangedKeptCopyRefusesTheGroup() {
        let g = group(["/t/x/1", "/t/x/2", "/t/x/3"])
        var fs = disk([g])
        fs.stamps["/t/x/1"] = ItemStamp(device: 1, inode: 10, logical: 999, modified: nil)
        let plan = SuggestionActions.trashPlan(of: [g], pending: [], ignores: none, fs: fs)
        #expect(plan.isEmpty)
        #expect(plan.staleGroups.map(\.id) == [g.id])
    }

    @Test func aGoneKeptCopyRefusesTheGroup() {
        let g = group(["/t/x/1", "/t/x/2"])
        var fs = disk([g])
        fs.stamps["/t/x/1"] = nil
        let plan = SuggestionActions.trashPlan(of: [g], item: g.items[1], pending: [], ignores: none, fs: fs)
        #expect(plan.isEmpty)
        #expect(plan.staleGroups.count == 1)
    }

    @Test func aStaleGroupDoesNotStopTheOthers() {
        let a = single(.largeUnused, "/t/a.bin", ino: 1)
        let g = group(["/t/x/1", "/t/x/2"])
        var fs = disk([a, g])
        fs.stamps["/t/x/1"] = nil
        let plan = SuggestionActions.trashPlan(of: [a, g], pending: [], ignores: none, fs: fs)
        #expect(plan.urls.map(\.path) == ["/t/a.bin"])
        #expect(plan.staleGroups.count == 1)
    }

    @Test func aFolderAndWhatIsInsideItGoTogetherOnce() {
        let folder = single(.buildFolders, "/t/proj/node_modules", ino: 1)
        let inner = single(.largeUnused, "/t/proj/node_modules/big.bin", ino: 2)
        let plan = SuggestionActions.trashPlan(of: [folder, inner], pending: [], ignores: none, fs: disk([folder, inner]))
        #expect(plan.urls.map(\.path) == ["/t/proj/node_modules"])
        #expect(Set(plan.keys) == [folder.items[0].id, inner.items[0].id], "both rows are hidden")
    }

    @Test func aPendingKeyIsNotSentAgain() {
        let a = single(.largeUnused, "/t/a.bin", ino: 1)
        let plan = SuggestionActions.trashPlan(of: [a], pending: [a.items[0].id], ignores: none, fs: disk([a]))
        #expect(plan.isEmpty)
    }

    // MARK: Focus

    @Test func theFocusMovesAndStopsAtTheEnds() {
        let ids = ["a", "b", "c", "d"]
        func go(_ current: String?, _ move: SuggestionFocus.Move) -> String? {
            SuggestionFocus.next(ids: ids, current: current, move: move)
        }
        #expect(go(nil, .by(1)) == "a")
        #expect(go(nil, .by(-1)) == "d")
        #expect(go("b", .by(1)) == "c")
        #expect(go("d", .by(1)) == "d")
        #expect(go("a", .by(-1)) == "a")
        #expect(go("a", .by(SuggestionFocus.pageStep)) == "d")
        #expect(go("c", .first) == "a")
        #expect(go("a", .last) == "d")
        #expect(go("gone", .by(1)) == "a", "a focus that left the list counts as none")
        #expect(SuggestionFocus.next(ids: [], current: nil, move: .first) == nil)
    }
}
