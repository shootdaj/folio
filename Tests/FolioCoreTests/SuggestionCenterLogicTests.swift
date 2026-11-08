import Foundation
import Testing
@testable import FolioCore

/// The decisions of the Suggestions center: when a scan starts, and how rows leave and come back.
@Suite struct SuggestionCenterLogicTests {
    private let home = URL(fileURLWithPath: "/private/tmp/folio-tests/center-home", isDirectory: true)
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func item(_ path: String, bytes: Int64 = 100, ino: UInt64 = 1) -> SuggestionItem {
        SuggestionItem(url: URL(fileURLWithPath: path), isFolder: false, bytes: bytes, logicalBytes: bytes,
                       stamp: ItemStamp(device: 1, inode: ino, logical: bytes, modified: nil))
    }

    private func single(_ kind: SuggestionKind, _ path: String, bytes: Int64) -> Suggestion {
        let i = item(path, bytes: bytes)
        return Suggestion(kind: kind, id: i.id, items: [i], bytes: bytes, reason: .emptyFolder)
    }

    private func group(_ paths: [String], sha: String = "abc") -> Suggestion {
        let items = paths.enumerated().map { item($1, ino: UInt64($0 + 1)) }
        let reason = SuggestionReason.sameContent(copies: items.count, sha256: sha, mayShareBlocks: false)
        return Suggestion(kind: .duplicates, id: "dup:" + sha, items: items, keep: items[0].url,
                          bytes: Suggestion.saving(items, keep: items[0].url, reason: reason), reason: reason)
    }

    // MARK: Schedule

    @Test func anAutomaticScanNeedsEveryCondition() {
        func go(allowed: Bool = true, viewing: Bool = true, shown: TimeInterval = 0.5, state: SuggestionState = .idle,
                last: Date? = nil) -> Bool {
            SuggestionSchedule.shouldStartAutomatically(allowed: allowed, viewing: viewing, shownFor: shown,
                                                        state: state, lastScan: last, now: now)
        }
        #expect(go())
        #expect(!go(allowed: false), "launch and session restore never scan")
        #expect(!go(viewing: false))
        #expect(!go(shown: 0.49), "an arrow key that passes the row does not scan")
        #expect(!go(state: .scanning))
        #expect(!go(state: .needsAccess), "nothing is read before the click")
        #expect(!go(state: .failed), "a failure waits for the user")
        #expect(go(state: .done, last: now.addingTimeInterval(-31 * 60)))
        #expect(!go(state: .done, last: now.addingTimeInterval(-29 * 60)))
        #expect(!go(state: .done, last: now.addingTimeInterval(-30 * 60)), "exactly 30 minutes is still fresh")
    }

    @Test func theGateOpensForAFixtureHomeAndForAGrant() {
        #expect(SuggestionSchedule.initialState(granted: false, isRealHome: true) == .needsAccess)
        #expect(SuggestionSchedule.initialState(granted: true, isRealHome: true) == .idle)
        #expect(SuggestionSchedule.initialState(granted: false, isRealHome: false) == .idle)
    }

    // MARK: Ledger

    @Test func aRowWhoseFileIsGoneLeavesAndComesBackWhenTheFileDoes() {
        let big = single(.largeUnused, "/private/tmp/folio-tests/c/big.bin", bytes: 900)
        let old = single(.oldDownloads, "/private/tmp/folio-tests/c/old.zip", bytes: 50)
        let report = SuggestionReport(suggestions: [big, old], home: home)

        let gone = SuggestionLedger().reconciled(report, exists: [big.items[0].id: false, old.items[0].id: true])
        #expect(gone.report.suggestions.map(\.id) == [old.id])
        #expect(gone.report.totalBytes == 50)
        #expect(gone.ledger.count == 1)

        let back = gone.ledger.reconciled(gone.report, exists: [big.items[0].id: true])
        #expect(Set(back.report.suggestions.map(\.id)) == [big.id, old.id])
        #expect(back.report.totalBytes == 950)
        #expect(back.ledger.isEmpty)
    }

    @Test func aRowThatWasNotCheckedStaysWhereItIs() {
        let big = single(.largeUnused, "/private/tmp/folio-tests/c/big.bin", bytes: 900)
        let report = SuggestionReport(suggestions: [big], home: home)
        let same = SuggestionLedger().reconciled(report, exists: [:])
        #expect(same.report.suggestions.count == 1)
        #expect(same.ledger.isEmpty)
        let gone = SuggestionLedger().reconciled(report, exists: [big.items[0].id: false])
        let still = gone.ledger.reconciled(gone.report, exists: [:])
        #expect(still.report.suggestions.isEmpty, "no answer for a missing file is no return")
        #expect(still.ledger.count == 1)
    }

    @Test func aDuplicateGroupReturnsOnlyWhenEveryLostCopyIsBack() {
        let trio = group(["/private/tmp/folio-tests/c/a", "/private/tmp/folio-tests/c/b", "/private/tmp/folio-tests/c/c"])
        let report = SuggestionReport(suggestions: [trio], home: home)
        let a = trio.items[0].id, b = trio.items[1].id, c = trio.items[2].id

        let one = SuggestionLedger().reconciled(report, exists: [b: false])
        #expect(one.report.suggestions.first?.items.count == 2)
        let two = one.ledger.reconciled(one.report, exists: [c: false])
        #expect(two.report.suggestions.isEmpty, "one copy left is not a group")

        let half = two.ledger.reconciled(two.report, exists: [b: true])
        #expect(half.report.suggestions.isEmpty, "copy c is still gone")
        let all = half.ledger.reconciled(half.report, exists: [c: true, a: true])
        #expect(all.report.suggestions.first?.items.count == 3)
        #expect(all.ledger.isEmpty)
    }

    @Test func onlyRowsInTheChangedFoldersAreChecked() {
        let a = single(.largeUnused, "/private/tmp/folio-tests/c/x/a.bin", bytes: 10)
        let b = single(.largeUnused, "/private/tmp/folio-tests/c/y/b.bin", bytes: 10)
        let report = SuggestionReport(suggestions: [a, b], home: home)
        let ledger = SuggestionLedger()
        #expect(ledger.itemsToCheck(in: report, folders: ["/private/tmp/folio-tests/c/x"]).map(\.id) == [a.items[0].id])
        #expect(ledger.itemsToCheck(in: report, folders: nil).count == 2)
        #expect(ledger.itemsToCheck(in: report, folders: []).isEmpty)

        let gone = ledger.reconciled(report, exists: [a.items[0].id: false])
        let again = gone.ledger.itemsToCheck(in: gone.report, folders: ["/private/tmp/folio-tests/c/x"])
        #expect(again.map(\.id) == [a.items[0].id], "a row that left is checked again so Undo finds it")
    }

    @Test func theTrashRowIsReplacedByANewMeasure() {
        let big = single(.largeUnused, "/private/tmp/folio-tests/c/big.bin", bytes: 900)
        let trash = Suggestion(kind: .trash, id: "trash", items: [item("/private/tmp/folio-tests/c/.Trash", bytes: 300)],
                               bytes: 300, reason: .trash(items: 4))
        let report = SuggestionReport(suggestions: [big, trash], home: home)
        #expect(report.totalBytes == 1200)

        let bigger = Suggestion(kind: .trash, id: "trash", items: trash.items, bytes: 700, reason: .trash(items: 9))
        let more = report.replacingTrash(with: bigger)
        #expect(more.totalBytes == 1600)
        #expect(more.suggestions.map(\.kind) == [.trash, .largeUnused], "kind order holds")

        let empty = report.replacingTrash(with: nil)
        #expect(empty.suggestions.map(\.kind) == [.largeUnused])
        #expect(empty.totalBytes == 900)

        let added = SuggestionReport(suggestions: [big], home: home).replacingTrash(with: trash)
        #expect(added.suggestions.count == 2)
        #expect(added.totalBytes == 1200)
    }

    @Test func ignoredPathsFoldersAndHashesLeaveTheReport() {
        let a = single(.largeUnused, "/private/tmp/folio-tests/c/keep/a.bin", bytes: 10)
        let b = single(.largeUnused, "/private/tmp/folio-tests/c/skip/b.bin", bytes: 20)
        let c = single(.largeUnused, "/private/tmp/folio-tests/c/skipper/c.bin", bytes: 40)
        let trio = group(["/private/tmp/folio-tests/c/p", "/private/tmp/folio-tests/c/q"], sha: "h1")
        let report = SuggestionReport(suggestions: [a, b, c, trio], home: home)

        let folder = report.excluding(.init(paths: ["/private/tmp/folio-tests/c/skip"]))
        #expect(Set(folder.suggestions.map(\.id)) == [a.id, c.id, trio.id], "skip does not cover skipper")
        let hash = report.excluding(.init(hashes: ["h1"]))
        #expect(!hash.suggestions.contains { $0.id == trio.id })
        #expect(hash.totalBytes == 70)
        #expect(report.excluding(.init()).suggestions.count == 4)
    }
}
