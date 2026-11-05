import Foundation

/// The sortable Details columns. Raw values double as column identifiers.
public enum SortKey: String, Sendable, CaseIterable {
    case name, modified, kind, size

    /// Direction of the first click on this column (Windows Explorer: dates newest first).
    public var defaultAscending: Bool { self != .modified }
}

public struct SortSpec: Sendable, Equatable {
    public var key: SortKey
    public var ascending: Bool

    public init(key: SortKey, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    public static let standard = SortSpec(key: .name, ascending: true)

    /// Header click: the same column reverses, a new column starts in its default direction.
    public func clicking(_ column: SortKey) -> SortSpec {
        column == key
            ? SortSpec(key: key, ascending: !ascending)
            : SortSpec(key: column, ascending: column.defaultAscending)
    }
}

public enum SortEngine {
    /// Ascending keeps folders on top; descending is the exact reverse, so folders end up at the bottom.
    public static func sort(_ entries: [FileEntry], by spec: SortSpec) -> [FileEntry] {
        let ascending = entries.sorted { inAscendingOrder($0, $1, by: spec.key) }
        return spec.ascending ? ascending : ascending.reversed()
    }

    static func inAscendingOrder(_ a: FileEntry, _ b: FileEntry, by key: SortKey) -> Bool {
        if a.isFolder != b.isFolder { return a.isFolder }
        switch key {
        case .name:
            break
        case .modified:
            let (da, db) = (a.modified ?? .distantPast, b.modified ?? .distantPast)
            if da != db { return da < db }
        case .kind:
            let order = a.kind.localizedStandardCompare(b.kind)
            if order != .orderedSame { return order == .orderedAscending }
        case .size:
            let (sa, sb) = (a.size ?? -1, b.size ?? -1)
            if sa != sb { return sa < sb }
        }
        let order = a.name.localizedStandardCompare(b.name)
        if order != .orderedSame { return order == .orderedAscending }
        return a.url.path < b.url.path
    }
}
