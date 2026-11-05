import Foundation
import Testing
@testable import FolioCore

/// A Gregorian calendar in UTC with a chosen first weekday (1 Sunday, 2 Monday).
func calendar(firstWeekday: Int) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    cal.firstWeekday = firstWeekday
    return cal
}

/// A UTC moment: 2026-10-04 12:00 is `day(2026, 10, 4, 12)`.
func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    var c = DateComponents()
    (c.year, c.month, c.day, c.hour, c.minute) = (y, m, d, h, min)
    return calendar(firstWeekday: 2).date(from: c)!
}

private func file(_ name: String, size: Int64? = 10, modified: Date? = nil, folder: Bool = false, kind: String = "Plain Text") -> FileEntry {
    FileEntry(url: URL(fileURLWithPath: "/fixture/" + name), name: name, isFolder: folder, modified: modified,
              size: folder ? nil : size, kind: folder ? "Folder" : kind)
}

@Suite struct NameBucketTests {
    @Test func digitsAndThreeLetterRanges() {
        #expect(Buckets.name("2026 report.txt").title == "0 - 9")
        #expect(Buckets.name("apple").title == "A - H")
        #expect(Buckets.name("Hotel").title == "A - H")
        #expect(Buckets.name("india").title == "I - P")
        #expect(Buckets.name("Papa").title == "I - P")
        #expect(Buckets.name("quebec").title == "Q - Z")
        #expect(Buckets.name("Zulu").title == "Q - Z")
    }

    @Test func accentsFoldAndEverythingElseIsOther() {
        #expect(Buckets.name("Éclair").title == "A - H")
        #expect(Buckets.name("über").title == "Q - Z")
        #expect(Buckets.name("_draft").title == "Other")
        #expect(Buckets.name(".zshrc").title == "Other")
        #expect(Buckets.name("日本語").title == "Other")
        #expect(Buckets.name("").title == "Other")
    }
}

@Suite struct SizeBucketTests {
    @Test func exactByteEdges() {
        let kib: Int64 = 1024, mib = 1024 * kib, gib = 1024 * mib
        let cases: [(Int64, String)] = [
            (0, "Empty"), (1, "Tiny"), (16 * kib, "Tiny"), (16 * kib + 1, "Small"),
            (mib, "Small"), (mib + 1, "Medium"), (128 * mib, "Medium"), (128 * mib + 1, "Large"),
            (gib, "Large"), (gib + 1, "Huge"), (4 * gib, "Huge"), (4 * gib + 1, "Gigantic"), (Int64.max, "Gigantic"),
        ]
        for (bytes, title) in cases { #expect(Buckets.size(bytes).title == title, "\(bytes) bytes") }
    }

    @Test func foldersAreUnspecifiedAndLabelsCarryTheRange() {
        #expect(Buckets.size(nil) == .unspecified)
        #expect(Buckets.size(300_000).label == "Small (16 KB - 1 MB)")
        #expect(Buckets.size(0).label == "Empty (0 KB)")
        #expect(Buckets.size(5_000_000_000).label == "Gigantic (> 4 GB)")
    }
}

@Suite struct DateBucketTests {
    /// Prism's Windows 11 measurement: today Sunday 4 October, weeks starting Monday.
    @Test func mondayWeekFromSundayFourthOctober() {
        let ctx = BucketContext(now: day(2026, 10, 4, 15), calendar: calendar(firstWeekday: 2))
        func t(_ d: Date) -> String { Buckets.date(d, ctx).title }
        #expect(t(day(2026, 10, 4, 0, 0)) == "Today")
        #expect(t(day(2026, 10, 4, 23, 59)) == "Today")
        #expect(t(day(2026, 10, 3, 23, 59)) == "Yesterday")
        #expect(t(day(2026, 10, 3, 0, 0)) == "Yesterday")
        #expect(t(day(2026, 10, 2)) == "Earlier this week")
        #expect(t(day(2026, 9, 28, 0, 0)) == "Earlier this week")
        #expect(t(day(2026, 9, 27, 23, 59)) == "Last week")
        #expect(t(day(2026, 9, 21, 0, 0)) == "Last week")
        #expect(t(day(2026, 9, 20)) == "Last month")
        #expect(t(day(2026, 9, 1, 0, 0)) == "Last month")
        #expect(t(day(2026, 8, 31)) == "Earlier this year")
        #expect(t(day(2026, 1, 1, 0, 0)) == "Earlier this year")
        #expect(t(day(2025, 12, 31, 23, 59)) == "A long time ago")
        #expect(t(day(2001, 5, 5)) == "A long time ago")
    }

    /// The same day with weeks starting Sunday (the user's locale decides).
    @Test func sundayWeekMovesTheWeekEdges() {
        let ctx = BucketContext(now: day(2026, 10, 4, 15), calendar: calendar(firstWeekday: 1))
        func t(_ d: Date) -> String { Buckets.date(d, ctx).title }
        #expect(t(day(2026, 10, 3)) == "Yesterday")
        #expect(t(day(2026, 10, 2)) == "Last week")
        #expect(t(day(2026, 9, 27, 0, 0)) == "Last week")
        #expect(t(day(2026, 9, 26)) == "Last month")
    }

    @Test func earlierThisMonthAndTheFuture() {
        let ctx = BucketContext(now: day(2026, 11, 19, 9), calendar: calendar(firstWeekday: 2))
        func t(_ d: Date) -> String { Buckets.date(d, ctx).title }
        #expect(t(day(2026, 11, 16, 0, 0)) == "Earlier this week")
        #expect(t(day(2026, 11, 15)) == "Last week")
        #expect(t(day(2026, 11, 9, 0, 0)) == "Last week")
        #expect(t(day(2026, 11, 8)) == "Earlier this month")
        #expect(t(day(2026, 11, 1, 0, 0)) == "Earlier this month")
        #expect(t(day(2026, 10, 31)) == "Last month")
        #expect(t(day(2026, 11, 20)) == "Tomorrow")
        #expect(t(day(2026, 11, 22)) == "Later this week")
        #expect(t(day(2026, 11, 23)) == "Next week")
        #expect(t(day(2026, 11, 30)) == "Later this month")
        #expect(t(day(2026, 12, 25)) == "Later this year")
        #expect(t(day(2027, 1, 2)) == "Sometime in the future")
        #expect(Buckets.date(nil, ctx) == .unspecified)
    }
}

@Suite struct PresentBucketTests {
    @Test func listsOnlyBucketsWithItemsDatesNewestFirstUnspecifiedLast() {
        let ctx = BucketContext(now: day(2026, 10, 4, 15), calendar: calendar(firstWeekday: 2))
        let entries = [
            file("a.txt", modified: day(2026, 10, 4)), file("b.txt", modified: day(2025, 1, 1)),
            file("c.txt", modified: day(2026, 10, 4, 9)), file("d", modified: nil, folder: true),
        ]
        let dates = Buckets.present(entries, .modified, context: ctx)
        #expect(dates.map(\.bucket.title) == ["Today", "A long time ago", "Unspecified"])
        #expect(dates.map(\.count) == [2, 1, 1])
        let sizes = Buckets.present([file("x", size: 0), file("y", size: 2_000_000), file("z", folder: true), file("w", size: 5)],
                                    .size, context: ctx)
        #expect(sizes.map(\.bucket.title) == ["Empty", "Tiny", "Medium", "Unspecified"])
    }

    @Test func typeListsEachTypePresentAlphabetically() {
        let entries = [file("a.png", kind: "PNG image"), file("b", folder: true), file("c.txt"), file("d.png", kind: "PNG image")]
        let types = Buckets.present(entries, .kind, context: BucketContext())
        #expect(types.map(\.bucket.title) == ["Folder", "Plain Text", "PNG image"])
        #expect(types.map(\.count) == [1, 1, 2])
    }

    @Test func durationRanges() {
        #expect(Buckets.duration(59).title == "Very short")
        #expect(Buckets.duration(60).title == "Short")
        #expect(Buckets.duration(1799).title == "Medium")
        #expect(Buckets.duration(3600).title == "Very long")
        #expect(Buckets.duration(nil) == .unspecified)
    }
}
