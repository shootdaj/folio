import Foundation
import Testing
@testable import FolioCore

/// The words and the cut of the Suggestions page: rows per card, duplicate groups, totals and status text.
@Suite struct SuggestionPageTests {
    private let home = URL(fileURLWithPath: "/private/tmp/folio-tests/page-home", isDirectory: true)
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func item(_ path: String, bytes: Int64 = 100, ino: UInt64 = 1) -> SuggestionItem {
        SuggestionItem(url: URL(fileURLWithPath: path), isFolder: false, bytes: bytes, logicalBytes: bytes,
                       stamp: ItemStamp(device: 1, inode: ino, logical: bytes, modified: nil))
    }

    private func single(_ kind: SuggestionKind, _ path: String, bytes: Int64, reason: SuggestionReason = .emptyFolder) -> Suggestion {
        let i = item(path, bytes: bytes)
        return Suggestion(kind: kind, id: i.id, items: [i], bytes: bytes, reason: reason)
    }

    private func group(_ paths: [String], bytes: Int64 = 24_000_000, share: Bool = false) -> Suggestion {
        let items = paths.enumerated().map { item($1, bytes: bytes, ino: UInt64($0 + 1)) }
        let reason = SuggestionReason.sameContent(copies: items.count, sha256: "abc", mayShareBlocks: share)
        return Suggestion(kind: .duplicates, id: "dup:abc", items: items, keep: items[0].url,
                          bytes: Suggestion.saving(items, keep: items[0].url, reason: reason), reason: reason)
    }

    private func many(_ n: Int) -> [Suggestion] {
        (0..<n).map { single(.largeUnused, home.path + "/Movies/f\($0).mov", bytes: Int64(1_000_000_000 - $0)) }
    }

    @Test func aCardShowsFiveRowsUntilShowAll() {
        let report = SuggestionReport(suggestions: many(12), home: home)
        let closed = SuggestionPage.sections(cards: report.cards(), home: home)
        #expect(closed.count == 1)
        #expect(closed[0].rows.count == 5)
        #expect(closed[0].shown.count == 5)
        #expect(closed[0].count == 12)
        #expect(closed[0].hidden == 7)
        let open = SuggestionPage.sections(cards: report.cards(), home: home, expanded: [.largeUnused])
        #expect(open[0].rows.count == 12)
        #expect(open[0].hidden == 0)
        #expect(!open[0].isCapped)
    }

    @Test func anExpandedCardStopsAtFiveHundred() {
        let report = SuggestionReport(suggestions: many(620), home: home)
        let open = SuggestionPage.sections(cards: report.cards(), home: home, expanded: [.largeUnused])[0]
        #expect(open.rows.count == 500)
        #expect(open.hidden == 120)
        #expect(open.isCapped)
        #expect(SuggestionPage.cappedText(section: open) == "500 of 620 shown")
    }

    @Test func theCardButtonActsOnTheShownSuggestionsOnly() {
        let report = SuggestionReport(suggestions: many(8), home: home)
        let s = SuggestionPage.sections(cards: report.cards(), home: home)[0]
        #expect(s.shown.map(\.id) == report.suggestions.prefix(5).map(\.id))
    }

    @Test func aDuplicateGroupHasAHeadAndItsCopiesWithOneKept() {
        let g = group([home.path + "/Documents/report-final.mov", home.path + "/Desktop/report-final copy.mov"])
        let rows = SuggestionPage.rows(for: g, home: home)
        #expect(rows.map(\.role) == [.groupHead, .member, .member])
        #expect(rows[0].name == "report-final.mov")
        #expect(rows[0].detail == "2 copies, 24 MB to free")
        #expect(!rows[0].isFocusable)
        #expect(rows[1].isKept && rows[1].detail == "Keep")
        #expect(!rows[2].isKept && rows[2].detail == "")
        #expect(rows[2].place == "~/Desktop")
        #expect(rows[1].id != rows[2].id && rows[1].id != rows[0].id)
    }

    @Test func aGroupWhoseCopiesMayShareBlocksSaysSo() {
        let g = group([home.path + "/a.bin", home.path + "/b.bin"], share: true)
        #expect(SuggestionPage.groupText(g) == "2 copies, may share space")
    }

    @Test func theKeptCopyFollowsKeepThisCopyInstead() {
        let g = group([home.path + "/a.bin", home.path + "/b.bin"])
        let other = g.keeping(g.items[1].url)
        let rows = SuggestionPage.rows(for: other, home: home)
        #expect(rows[0].name == "b.bin")
        #expect(rows[2].isKept)
    }

    @Test func aSingleRowHasNameFolderReasonAndSize() {
        let s = single(.oldDownloads, home.path + "/Downloads/receipt.pdf", bytes: 2_500_000,
                       reason: .inDownloadsSince(Date(timeIntervalSince1970: 1_700_000_000)))
        let row = SuggestionPage.rows(for: s, home: home, timeZone: TimeZone(identifier: "UTC")!)[0]
        #expect(row.name == "receipt.pdf")
        #expect(row.place == "~/Downloads")
        #expect(row.detail == "In Downloads since 14 Nov 2023")
        #expect(row.size == 2_500_000)
    }

    @Test func emptyFoldersAndBrokenLinksHaveNoSize() {
        let empty = single(.emptyFolders, home.path + "/Documents/Empty", bytes: 0)
        #expect(SuggestionPage.rows(for: empty, home: home)[0].size == nil)
        let report = SuggestionReport(suggestions: [empty], home: home)
        let section = SuggestionPage.sections(cards: report.cards(), home: home)[0]
        #expect(SuggestionPage.sectionTotal(section) == "1 item")
    }

    @Test func aPlaceShortensOnlyAtAFolderBoundary() {
        #expect(SuggestionPage.place(of: URL(fileURLWithPath: home.path + "/x.bin"), home: home) == "~")
        #expect(SuggestionPage.place(of: URL(fileURLWithPath: home.path + "/A/B/x.bin"), home: home) == "~/A/B")
        #expect(SuggestionPage.place(of: URL(fileURLWithPath: home.path + "2/A/x.bin"), home: home) == home.path + "2/A")
    }

    @Test func sizesUseKilobytesUnderOneMegabyte() {
        #expect(SuggestionPage.size(12_000) == "12 KB")
        #expect(SuggestionPage.size(64_000_000) == "64 MB")
        #expect(SuggestionPage.size(4_200_000_000) == "4.2 GB")
    }

    @Test func buttonTitlesSayHowMany() {
        #expect(SuggestionPage.moveTitle(count: 5) == "Move 5 to Trash")
        #expect(SuggestionPage.showAllTitle(count: 1_234) == "Show all 1,234")
        #expect(SuggestionPage.ignoredTitle(count: 1) == "Show 1 ignored item again")
        #expect(SuggestionPage.ignoredTitle(count: 4) == "Show 4 ignored items again")
    }

    @Test func theCheckedTimeReadsInWholeUnits() {
        #expect(SuggestionPage.checkedText(nil, now: now) == "Not checked yet")
        #expect(SuggestionPage.checkedText(now.addingTimeInterval(-10), now: now) == "Checked just now")
        #expect(SuggestionPage.checkedText(now.addingTimeInterval(-120), now: now) == "Checked 2 min ago")
        #expect(SuggestionPage.checkedText(now.addingTimeInterval(-3 * 3_600), now: now) == "Checked 3 h ago")
        #expect(SuggestionPage.checkedText(now.addingTimeInterval(-86_400), now: now) == "Checked 1 day ago")
        #expect(SuggestionPage.checkedText(now.addingTimeInterval(-3 * 86_400), now: now) == "Checked 3 days ago")
    }

    @Test func theStatusTextFollowsThePhase() {
        let report = SuggestionReport(suggestions: many(3), home: home)
        let walking = ScanProgress(phase: .walking, fraction: 0.3, entries: 48_210, current: "/Users/x/Documents")
        #expect(SuggestionPage.statusText(state: .idle, report: nil, progress: nil, failure: nil) == "Ready to scan")
        #expect(SuggestionPage.statusText(state: .needsAccess, report: nil, progress: nil, failure: nil) == "Suggestions need Full Disk Access")
        #expect(SuggestionPage.statusText(state: .scanning, report: nil, progress: walking, failure: nil)
                == "Scanning Documents: 48,210 items checked")
        #expect(SuggestionPage.statusText(state: .done, report: report, progress: nil, failure: nil) == "3 suggestions, 3.0 GB to free")
        #expect(SuggestionPage.statusText(state: .done, report: SuggestionReport(home: home), progress: nil, failure: nil)
                == "Nothing to clean up")
        #expect(SuggestionPage.statusText(state: .failed, report: nil, progress: nil, failure: "Folio cannot read /x.") == "Folio cannot read /x.")
        var partial = report
        partial.isPartial = true
        #expect(SuggestionPage.statusText(state: .done, report: partial, progress: nil, failure: nil).hasSuffix("(partial scan)"))
    }

    @Test func earlyCardsShowUntilAReportExists() {
        let early = [single(.trash, home.path + "/.Trash", bytes: 5_000_000, reason: .trash(items: 2))]
        #expect(SuggestionPage.cards(report: nil, early: early).map(\.kind) == [.trash])
        #expect(SuggestionPage.cards(report: nil, early: []).isEmpty)
        let report = SuggestionReport(suggestions: many(1), home: home)
        #expect(SuggestionPage.cards(report: report, early: early).map(\.kind) == [.largeUnused])
    }
}
