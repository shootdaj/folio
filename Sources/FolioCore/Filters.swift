import Foundation

/// Days picked on a date filter's calendar: from `first` to `last`, both whole days, in local time.
public struct DayRange: Sendable, Equatable {
    public var first: Date
    public var last: Date

    /// Either order; both are taken to the start of their day.
    public init(_ a: Date, _ b: Date, calendar: Calendar = .current) {
        let x = calendar.startOfDay(for: a), y = calendar.startOfDay(for: b)
        first = min(x, y)
        last = max(x, y)
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let end = calendar.date(byAdding: .day, value: 1, to: last) else { return false }
        return date >= first && date < end
    }
}

/// One column's filter: the ticked buckets and, for a date column, the days picked on the calendar.
/// Everything ticked is ORed.
public struct ColumnFilter: Sendable, Equatable {
    public var buckets: Set<String>
    public var days: DayRange?

    public init(buckets: Set<String> = [], days: DayRange? = nil) {
        self.buckets = buckets
        self.days = days
    }

    public var isEmpty: Bool { buckets.isEmpty && days == nil }
}

/// A filter token in the address bar ("Type: Folder"), with the column it clears.
public struct FilterToken: Sendable, Equatable {
    public let column: ColumnID
    public let text: String
}

/// The header filters of a list: ORed within a column, ANDed across columns. Transient by design: a
/// filter belongs to the folder on screen and is never saved.
public struct FilterSet: Sendable, Equatable {
    /// In the order the columns were first filtered, which is the order of the tokens.
    public private(set) var columns: [ColumnID] = []
    private var filters: [ColumnID: ColumnFilter] = [:]

    public init() {}

    public var isEmpty: Bool { columns.isEmpty }

    public func filter(for column: ColumnID) -> ColumnFilter { filters[column] ?? ColumnFilter() }

    public func isFiltered(_ column: ColumnID) -> Bool { filters[column] != nil }

    /// Ticks or unticks one bucket; the last untick clears the column.
    public mutating func toggle(_ bucket: String, in column: ColumnID) {
        var f = filter(for: column)
        if f.buckets.contains(bucket) { f.buckets.remove(bucket) } else { f.buckets.insert(bucket) }
        set(f, for: column)
    }

    /// The calendar's day or range (nil takes it off).
    public mutating func setDays(_ days: DayRange?, in column: ColumnID) {
        var f = filter(for: column)
        f.days = days
        set(f, for: column)
    }

    public mutating func set(_ f: ColumnFilter, for column: ColumnID) {
        if f.isEmpty {
            clear(column)
            return
        }
        if filters[column] == nil { columns.append(column) }
        filters[column] = f
    }

    public mutating func clear(_ column: ColumnID) {
        filters[column] = nil
        columns.removeAll { $0 == column }
    }

    public mutating func clearAll() { self = FilterSet() }

    /// True when the item passes every filtered column.
    public func matches(_ entry: FileEntry, meta: ItemMetadata?, context: BucketContext) -> Bool {
        for column in columns {
            guard let f = filters[column] else { continue }
            var hit = false
            if let days = f.days, let date = ColumnValues.date(entry, column, meta), days.contains(date, calendar: context.calendar) {
                hit = true
            }
            if !hit, !f.buckets.isEmpty {
                hit = Buckets.buckets(entry, column, meta, context).contains { f.buckets.contains($0.id) }
            }
            if !hit { return false }
        }
        return true
    }

    /// The items that pass, in their order.
    public func apply(_ entries: [FileEntry], context: BucketContext,
                      metadata: (FileEntry) -> ItemMetadata? = { _ in nil }) -> [FileEntry] {
        guard !isEmpty else { return entries }
        let wantsMeta = columns.contains { $0.needsMetadata }
        return entries.filter { matches($0, meta: wantsMeta ? metadata($0) : nil, context: context) }
    }

    /// "Type: Folder", "Size: Small, Medium", "Date modified: Today, 2026-11-02 - 2026-11-04".
    /// `known` gives a ticked bucket's title in list order (buckets of discrete values carry their text).
    public func tokens(known: (ColumnID) -> [Bucket] = { _ in [] }) -> [FilterToken] {
        columns.compactMap { column in
            guard let f = filters[column] else { return nil }
            let order = known(column)
            var parts: [String] = order.filter { f.buckets.contains($0.id) }.map(\.title)
            let listed = Set(order.map(\.id))
            parts += f.buckets.subtracting(listed).sorted().map(Self.title(ofBucket:))
            if let days = f.days { parts.append(Self.text(days)) }
            return FilterToken(column: column, text: column.title + ": " + parts.joined(separator: ", "))
        }
    }

    /// A bucket's title from its id alone (a discrete value's id is "=" and the value).
    static func title(ofBucket id: String) -> String {
        if id.hasPrefix("=") { return String(id.dropFirst()) }
        if id == Bucket.unspecified.id { return Bucket.unspecified.title }
        let all = Buckets.nameBuckets + Buckets.sizeBuckets.map(\.bucket) + Buckets.dateBuckets + Buckets.durationBuckets.map(\.bucket)
        return all.first { $0.id == id }?.title ?? id
    }

    nonisolated(unsafe) private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func text(_ days: DayRange) -> String {
        let a = dayFormatter.string(from: days.first), b = dayFormatter.string(from: days.last)
        return a == b ? a : a + " - " + b
    }
}
