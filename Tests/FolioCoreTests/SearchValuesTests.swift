import Foundation
import Testing
@testable import FolioCore

@Suite struct SearchSizeTests {
    let kib: Int64 = 1024, mib: Int64 = 1_048_576, gib: Int64 = 1_073_741_824

    @Test func theSevenWindows11WordsOnTheFilterBuckets() {
        #expect(SearchValues.sizeWord("empty") == SizeRange(0, 0))
        #expect(SearchValues.sizeWord("tiny") == SizeRange(1, 16 * kib))
        #expect(SearchValues.sizeWord("small") == SizeRange(16 * kib + 1, mib))
        #expect(SearchValues.sizeWord("Medium") == SizeRange(mib + 1, 128 * mib))
        #expect(SearchValues.sizeWord("large") == SizeRange(128 * mib + 1, gib))
        #expect(SearchValues.sizeWord("huge") == SizeRange(gib + 1, 4 * gib))
        #expect(SearchValues.sizeWord("GIGANTIC") == SizeRange(4 * gib + 1, nil))
        #expect(SearchValues.sizeWord("enormous") == nil)
        // Every byte count falls in exactly the bucket the Size filter puts it in.
        for bytes: Int64 in [0, 1, 16 * kib, 16 * kib + 1, mib, mib + 1, 128 * mib, 128 * mib + 1, gib, 4 * gib, 4 * gib + 1] {
            let word = SearchValues.sizeWords.first { $0.range.contains(bytes) }?.word
            #expect(word == Buckets.size(bytes).id, "\(bytes)")
        }
    }

    @Test func unitsAreBinaryAndNoUnitIsBytes() {
        #expect(SearchValues.bytes("500") == 500)
        #expect(SearchValues.bytes("10kb") == 10 * kib)
        #expect(SearchValues.bytes("10KB") == 10 * kib)
        #expect(SearchValues.bytes("1.5mb") == Int64(1.5 * Double(mib)))
        #expect(SearchValues.bytes("2g") == 2 * gib)
        #expect(SearchValues.bytes("3b") == 3)
        #expect(SearchValues.bytes("mb") == nil)
        #expect(SearchValues.bytes("-1kb") == nil)
        #expect(SearchValues.bytes("ten") == nil)
    }

    @Test func comparisonsAndRanges() {
        #expect(SearchValues.size("50mb", op: ">") == SizeRange(50 * mib + 1, nil))
        #expect(SearchValues.size("50mb", op: ">=") == SizeRange(50 * mib, nil))
        #expect(SearchValues.size("1kb", op: "<") == SizeRange(nil, 1023))
        #expect(SearchValues.size("1kb", op: "<=") == SizeRange(nil, 1024))
        #expect(SearchValues.size("500", op: "") == SizeRange(500, 500))
        #expect(SearchValues.size("5kb..10kb", op: "") == SizeRange(5 * kib, 10 * kib))
        #expect(SearchValues.size("small..medium", op: "") == SizeRange(16 * kib + 1, 128 * mib))
        #expect(SearchValues.size("medium", op: ">") == SizeRange(128 * mib + 1, nil))
        #expect(SearchValues.size("5kb..", op: "") == nil)
    }
}

@Suite struct SearchDateTests {
    /// [start, end) of a parsed date value, in UTC.
    func bounds(_ raw: String, _ op: String = "") -> (Date?, Date?) {
        let b = SearchValues.date(raw, op: op, context: searchContext)
        return (b?.start, b?.end)
    }

    @Test func daysAreMidnightToMidnight() {
        #expect(bounds("today") == (day(2026, 11, 5, 0), day(2026, 11, 6, 0)))
        #expect(bounds("yesterday") == (day(2026, 11, 4, 0), day(2026, 11, 5, 0)))
        #expect(bounds("Tomorrow") == (day(2026, 11, 6, 0), day(2026, 11, 7, 0)))
    }

    @Test func weeksAreCalendarWeeksFromTheFirstWeekday() {
        // Monday 2 November to Monday 9 November.
        #expect(bounds("thisweek") == (day(2026, 11, 2, 0), day(2026, 11, 9, 0)))
        #expect(bounds("lastweek") == (day(2026, 10, 26, 0), day(2026, 11, 2, 0)))
        #expect(bounds("nextweek") == (day(2026, 11, 9, 0), day(2026, 11, 16, 0)))
        // A Sunday-first calendar starts the week on 1 November.
        let sunday = BucketContext(now: day(2026, 11, 5, 12), calendar: calendar(firstWeekday: 1))
        let b = SearchValues.date("thisweek", op: "", context: sunday)
        #expect(b?.start == day(2026, 11, 1, 0) && b?.end == day(2026, 11, 8, 0))
    }

    @Test func monthsAndYearsAreWhole() {
        #expect(bounds("thismonth") == (day(2026, 11, 1, 0), day(2026, 12, 1, 0)))
        #expect(bounds("lastmonth") == (day(2026, 10, 1, 0), day(2026, 11, 1, 0)))
        #expect(bounds("pastmonth") == (day(2026, 10, 1, 0), day(2026, 11, 1, 0)))
        #expect(bounds("thisyear") == (day(2026, 1, 1, 0), day(2027, 1, 1, 0)))
        #expect(bounds("lastyear") == (day(2025, 1, 1, 0), day(2026, 1, 1, 0)))
        #expect(bounds("comingyear") == (day(2027, 1, 1, 0), day(2028, 1, 1, 0)))
    }

    @Test func dayAndMonthNames() {
        #expect(bounds("monday") == (day(2026, 11, 2, 0), day(2026, 11, 3, 0)))
        #expect(bounds("Wed") == (day(2026, 11, 4, 0), day(2026, 11, 5, 0)))
        #expect(bounds("february") == (day(2026, 2, 1, 0), day(2026, 3, 1, 0)))
    }

    @Test func explicitDatesInTheLocalesOrder() {
        #expect(bounds("2024-03-01") == (day(2024, 3, 1, 0), day(2024, 3, 2, 0)))
        #expect(bounds("2024-03") == (day(2024, 3, 1, 0), day(2024, 4, 1, 0)))
        #expect(bounds("2024") == (day(2024, 1, 1, 0), day(2025, 1, 1, 0)))
        #expect(bounds("2024-03-01T10:00:00") == (day(2024, 3, 1, 0), day(2024, 3, 2, 0)))
        // en_US reads month first, en_GB day first; dots always day first.
        #expect(bounds("1/26/2010") == (day(2010, 1, 26, 0), day(2010, 1, 27, 0)))
        #expect(bounds("11/13/21") == (day(2021, 11, 13, 0), day(2021, 11, 14, 0)))
        var gb = calendar(firstWeekday: 2)
        gb.locale = Locale(identifier: "en_GB")
        let b = SearchValues.date("26/1/2010", op: "", context: BucketContext(now: day(2026, 11, 5), calendar: gb))
        #expect(b?.start == day(2010, 1, 26, 0))
        #expect(bounds("26.1.2010") == (day(2010, 1, 26, 0), day(2010, 1, 27, 0)))
        #expect(bounds("13/45/2020").0 == nil)
        #expect(bounds("2026-02-30").0 == nil)
    }

    @Test func comparisonsAndRangesTakeWholePeriods() {
        #expect(bounds("11/13/21", ">") == (day(2021, 11, 14, 0), nil))
        #expect(bounds("today", ">=") == (day(2026, 11, 5, 0), nil))
        #expect(bounds("today", "<") == (nil, day(2026, 11, 5, 0)))
        #expect(bounds("yesterday", "<=") == (nil, day(2026, 11, 5, 0)))
        #expect(bounds("1/7/2010..1/8/2010") == (day(2010, 1, 7, 0), day(2010, 1, 9, 0)))
        #expect(bounds("lastweek..today") == (day(2026, 10, 26, 0), day(2026, 11, 6, 0)))
    }
}

@Suite struct SearchKindTests {
    @Test func theMenuListsTwentyThreeKinds() {
        #expect(SearchKind.allCases.count == 23)
        #expect(SearchKind.allCases.map(\.title).prefix(5) == ["Calendar", "Communication", "Contact", "Document", "E-mail"])
        #expect(SearchKind.allCases.last?.title == "Unknown")
    }

    @Test func mnemonics() {
        #expect(SearchKind.named("pics") == .picture)
        #expect(SearchKind.named("Photos") == .picture)
        #expect(SearchKind.named("docs") == .document)
        #expect(SearchKind.named("e-mail") == .email)
        #expect(SearchKind.named("im") == .instantMessage)
        #expect(SearchKind.named("instant message") == .instantMessage)
        #expect(SearchKind.named("tv") == .recordedTV)
        #expect(SearchKind.named("films") == .movie)
        #expect(SearchKind.named("webpage") == .webHistory)
        #expect(SearchKind.named("spaceship") == nil)
    }

    @Test func theExtensionTableDecidesNotTheBroaderTypeTree() {
        #expect(SearchKind.kinds(name: "notes.txt", isFolder: false) == [.document])
        #expect(SearchKind.kinds(name: "Bertie.md", isFolder: false) == [.document])
        #expect(SearchKind.kinds(name: "my_bert.log", isFolder: false) == [.document])
        #expect(SearchKind.kinds(name: "photo.PNG", isFolder: false) == [.picture])
        #expect(SearchKind.kinds(name: "clip.mp4", isFolder: false) == [.movie, .video])
        #expect(SearchKind.kinds(name: "song.mp3", isFolder: false) == [.music])
        #expect(SearchKind.kinds(name: "work", isFolder: true) == [.folder])
        #expect(SearchKind.kinds(name: "Safari.app", isFolder: false) == [.program])
        // A source file is plain text to UTType, but no document to Windows.
        #expect(SearchKind.kinds(name: "main.swift", isFolder: false, contentType: "public.swift-source") == [.unknown])
        // public.archive also matched a raw .bin on this Mac; no kind here.
        #expect(SearchKind.kinds(name: "big.bin", isFolder: false, contentType: "public.data") == [.unknown])
        // An image type the table does not list still is a picture.
        #expect(SearchKind.kinds(name: "scan.pbm", isFolder: false, contentType: "public.image") == [.picture])
        #expect(SearchKind.kinds(name: "alias", isFolder: false, isLink: true).contains(.link))
    }
}
