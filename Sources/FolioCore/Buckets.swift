import Foundation

/// One checkbox in a header filter and one group under Group by. The same buckets serve both.
public struct Bucket: Sendable, Hashable {
    /// Stable within its column ("small", "today", "A-H", or "=PNG image" for a discrete value).
    public let id: String
    /// Group headers and filter tokens: "Small", "Today", "A - H", "PNG image".
    public let title: String
    /// The filter's checkbox line: "Small (16 KB - 1 MB)".
    public let label: String
    /// Order from smallest, oldest or first; discrete values all share 0 and order by title.
    public let rank: Int

    public init(id: String, title: String, label: String? = nil, rank: Int) {
        self.id = id
        self.title = title
        self.label = label ?? title
        self.rank = rank
    }

    /// Items with no value: folders under Size, files without a date or a tag. Always listed last.
    public static let unspecified = Bucket(id: "unspecified", title: "Unspecified", rank: Int.max)

    public var isUnspecified: Bool { id == Self.unspecified.id }

    /// Ascending bucket order: rank, then title for discrete values, Unspecified last either way.
    public static func ascending(_ a: Bucket, _ b: Bucket) -> Bool {
        if a.rank != b.rank { return a.rank < b.rank }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}

/// What "today" and "this week" mean when bucketing dates: now, and the user's calendar (time zone
/// and first day of the week).
public struct BucketContext: Sendable {
    public var now: Date { didSet { edges = DateEdges(now: now, calendar: calendar) } }
    public var calendar: Calendar { didSet { edges = DateEdges(now: now, calendar: calendar) } }
    /// The date buckets' edges, worked out once for `now` instead of once per item.
    private(set) var edges: DateEdges

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        edges = DateEdges(now: now, calendar: calendar)
    }
}

/// Where each date bucket starts, for one moment: midnight splits days and the week starts on the
/// calendar's first weekday.
struct DateEdges: Sendable {
    let today, tomorrow, dayAfterTomorrow, yesterday: Date
    let week, weekPlus7, weekPlus14, weekMinus7: Date
    let month, monthPlus1, monthMinus1: Date
    let year, yearPlus1: Date

    init(now: Date, calendar cal: Calendar) {
        func add(_ unit: Calendar.Component, _ n: Int, _ to: Date) -> Date { cal.date(byAdding: unit, value: n, to: to)! }
        today = cal.startOfDay(for: now)
        tomorrow = add(.day, 1, today)
        dayAfterTomorrow = add(.day, 1, tomorrow)
        yesterday = add(.day, -1, today)
        week = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        weekPlus7 = add(.day, 7, week)
        weekPlus14 = add(.day, 14, week)
        weekMinus7 = add(.day, -7, week)
        month = cal.dateInterval(of: .month, for: now)?.start ?? today
        monthPlus1 = add(.month, 1, month)
        monthMinus1 = add(.month, -1, month)
        year = cal.dateInterval(of: .year, for: now)?.start ?? today
        yearPlus1 = add(.year, 1, year)
    }
}

/// Explorer's buckets: Name ranges, Size ranges (Windows 10 1809 and later), the date periods measured
/// on Windows 11, duration ranges and one bucket per discrete value.
public enum Buckets {
    // MARK: Name

    private static let posix = Locale(identifier: "en_US_POSIX")

    public static let nameBuckets: [Bucket] = [
        Bucket(id: "0-9", title: "0 - 9", rank: 0),
        Bucket(id: "A-H", title: "A - H", rank: 1),
        Bucket(id: "I-P", title: "I - P", rank: 2),
        Bucket(id: "Q-Z", title: "Q - Z", rank: 3),
        Bucket(id: "other", title: "Other", rank: 4),
    ]

    /// By the first character: digits, then Latin letters in three ranges (accents folded), else Other.
    public static func name(_ name: String) -> Bucket {
        guard let first = name.first else { return nameBuckets[4] }
        // Plain ASCII needs no folding (most names start so).
        if let a = first.asciiValue {
            switch a {
            case 0x30...0x39: return nameBuckets[0]
            case 0x41...0x48, 0x61...0x68: return nameBuckets[1]
            case 0x49...0x50, 0x69...0x70: return nameBuckets[2]
            case 0x51...0x5A, 0x71...0x7A: return nameBuckets[3]
            default: return nameBuckets[4]
            }
        }
        let folded = String(first).folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                           locale: posix).uppercased()
        guard let scalar = folded.unicodeScalars.first, folded.unicodeScalars.count == 1 else { return nameBuckets[4] }
        switch scalar.value {
        case 0x30...0x39: return nameBuckets[0]
        case 0x41...0x48: return nameBuckets[1]
        case 0x49...0x50: return nameBuckets[2]
        case 0x51...0x5A: return nameBuckets[3]
        default: return nameBuckets[4]
        }
    }

    // MARK: Size

    public static let kib: Int64 = 1024
    public static let mib: Int64 = 1024 * 1024
    public static let gib: Int64 = 1024 * 1024 * 1024

    /// Upper edges, inclusive: Empty 0, Tiny to 16 KB, Small to 1 MB, Medium to 128 MB, Large to 1 GB,
    /// Huge to 4 GB, Gigantic beyond.
    public static let sizeBuckets: [(top: Int64, bucket: Bucket)] = [
        (0, Bucket(id: "empty", title: "Empty", label: "Empty (0 KB)", rank: 0)),
        (16 * kib, Bucket(id: "tiny", title: "Tiny", label: "Tiny (0 - 16 KB)", rank: 1)),
        (mib, Bucket(id: "small", title: "Small", label: "Small (16 KB - 1 MB)", rank: 2)),
        (128 * mib, Bucket(id: "medium", title: "Medium", label: "Medium (1 - 128 MB)", rank: 3)),
        (gib, Bucket(id: "large", title: "Large", label: "Large (128 MB - 1 GB)", rank: 4)),
        (4 * gib, Bucket(id: "huge", title: "Huge", label: "Huge (1 - 4 GB)", rank: 5)),
        (Int64.max, Bucket(id: "gigantic", title: "Gigantic", label: "Gigantic (> 4 GB)", rank: 6)),
    ]

    /// Folders (no size) go under Unspecified.
    public static func size(_ bytes: Int64?) -> Bucket {
        guard let bytes else { return .unspecified }
        return sizeBuckets.first { bytes <= $0.top }?.bucket ?? sizeBuckets[sizeBuckets.count - 1].bucket
    }

    // MARK: Dates

    /// Rank is chronological: A long time ago 0 up to Sometime in the future 13.
    public static let dateBuckets: [Bucket] = [
        Bucket(id: "longAgo", title: "A long time ago", rank: 0),
        Bucket(id: "earlierThisYear", title: "Earlier this year", rank: 1),
        Bucket(id: "lastMonth", title: "Last month", rank: 2),
        Bucket(id: "earlierThisMonth", title: "Earlier this month", rank: 3),
        Bucket(id: "lastWeek", title: "Last week", rank: 4),
        Bucket(id: "earlierThisWeek", title: "Earlier this week", rank: 5),
        Bucket(id: "yesterday", title: "Yesterday", rank: 6),
        Bucket(id: "today", title: "Today", rank: 7),
        Bucket(id: "tomorrow", title: "Tomorrow", rank: 8),
        Bucket(id: "laterThisWeek", title: "Later this week", rank: 9),
        Bucket(id: "nextWeek", title: "Next week", rank: 10),
        Bucket(id: "laterThisMonth", title: "Later this month", rank: 11),
        Bucket(id: "laterThisYear", title: "Later this year", rank: 12),
        Bucket(id: "future", title: "Sometime in the future", rank: 13),
    ]

    private static let dateBucketsByID = Dictionary(uniqueKeysWithValues: dateBuckets.map { ($0.id, $0) })
    private static func dateBucket(_ id: String) -> Bucket { dateBucketsByID[id]! }

    /// Checked in order, first match wins; midnight splits days and the week starts on the calendar's
    /// first weekday. There is no Last year: before 1 January is A long time ago.
    public static func date(_ date: Date?, _ context: BucketContext) -> Bucket {
        guard let date else { return .unspecified }
        let e = context.edges
        if date >= e.tomorrow {
            if date < e.dayAfterTomorrow { return dateBucket("tomorrow") }
            if date < e.weekPlus7 { return dateBucket("laterThisWeek") }
            if date < e.weekPlus14 { return dateBucket("nextWeek") }
            if date < e.monthPlus1 { return dateBucket("laterThisMonth") }
            if date < e.yearPlus1 { return dateBucket("laterThisYear") }
            return dateBucket("future")
        }
        if date >= e.today { return dateBucket("today") }
        if date >= e.yesterday { return dateBucket("yesterday") }
        if date >= e.week { return dateBucket("earlierThisWeek") }
        if date >= e.weekMinus7 { return dateBucket("lastWeek") }
        if date >= e.month { return dateBucket("earlierThisMonth") }
        if date >= e.monthMinus1 { return dateBucket("lastMonth") }
        if date >= e.year { return dateBucket("earlierThisYear") }
        return dateBucket("longAgo")
    }

    // MARK: Duration

    public static let durationBuckets: [(top: Double, bucket: Bucket)] = [
        (60, Bucket(id: "veryShort", title: "Very short", label: "Very short (under 1 min)", rank: 0)),
        (300, Bucket(id: "short", title: "Short", label: "Short (1 - 5 min)", rank: 1)),
        (1800, Bucket(id: "mediumLength", title: "Medium", label: "Medium (5 - 30 min)", rank: 2)),
        (3600, Bucket(id: "long", title: "Long", label: "Long (30 - 60 min)", rank: 3)),
        (Double.infinity, Bucket(id: "veryLong", title: "Very long", label: "Very long (over 60 min)", rank: 4)),
    ]

    public static func duration(_ seconds: Double?) -> Bucket {
        guard let seconds else { return .unspecified }
        return durationBuckets.first { seconds < $0.top }?.bucket ?? durationBuckets[durationBuckets.count - 1].bucket
    }

    // MARK: Discrete values

    public static func discrete(_ value: String) -> Bucket {
        value.isEmpty ? .unspecified : Bucket(id: "=" + value, title: value, rank: 0)
    }

    // MARK: Any column

    /// The buckets one item falls in for `column` (several for each of its tags, one otherwise).
    public static func buckets(_ entry: FileEntry, _ column: ColumnID, _ meta: ItemMetadata?,
                               _ context: BucketContext) -> [Bucket] {
        switch column.bucketStyle {
        case .alphanumeric: return [name(entry.name)]
        case .size: return [size(entry.size)]
        case .date: return [date(ColumnValues.date(entry, column, meta), context)]
        case .duration: return [duration(meta?.duration)]
        case .multiValue:
            let tags = meta?.tags ?? []
            return tags.isEmpty ? [.unspecified] : Array(Set(tags)).sorted().map(discrete)
        case .discrete: return [discrete(ColumnValues.text(entry, column, meta))]
        }
    }

    /// The buckets present among `entries`, in the order the filter lists them: newest first for dates
    /// (Today at the top), otherwise ascending; Unspecified last. Each with how many items it holds.
    public static func present(_ entries: [FileEntry], _ column: ColumnID, context: BucketContext,
                               metadata: (FileEntry) -> ItemMetadata? = { _ in nil }) -> [(bucket: Bucket, count: Int)] {
        var counts: [Bucket: Int] = [:]
        for e in entries {
            for b in buckets(e, column, column.needsMetadata ? metadata(e) : nil, context) { counts[b, default: 0] += 1 }
        }
        let newestFirst = column.bucketStyle == .date
        return counts.keys.sorted { a, b in
            if a.isUnspecified != b.isUnspecified { return b.isUnspecified }
            return newestFirst ? Bucket.ascending(b, a) : Bucket.ascending(a, b)
        }.map { ($0, counts[$0]!) }
    }
}
