import Foundation

/// Group by: a column and the order of its groups (independent of the sort inside each group).
public struct GroupSpec: Sendable, Equatable, Codable {
    public var key: ColumnID
    public var ascending: Bool

    public init(key: ColumnID, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }
}

/// One group: its bucket and its items in display order.
public struct ItemGroup: Sendable, Equatable {
    public let bucket: Bucket
    public let items: [FileEntry]

    public init(bucket: Bucket, items: [FileEntry]) {
        self.bucket = bucket
        self.items = items
    }

    /// The header text: "Today (3)".
    public var title: String { "\(bucket.title) (\(items.count))" }
}

public enum GroupBuilder {
    /// Groups on the same buckets the filters use. Groups follow `spec.ascending` (dates oldest first
    /// ascending, newest first descending); Unspecified always comes last; empty buckets are left out.
    /// Inside a group items follow `sort`, files before folders, as Explorer measured. An item with
    /// several tags appears in each tag's group.
    public static func build(_ entries: [FileEntry], by spec: GroupSpec, sort: SortSpec, context: BucketContext,
                             metadata: (FileEntry) -> ItemMetadata? = { _ in nil }) -> [ItemGroup] {
        let wantsMeta = spec.key.needsMetadata
        var members: [Bucket: [FileEntry]] = [:]
        for e in entries {
            for b in Buckets.buckets(e, spec.key, wantsMeta ? metadata(e) : nil, context) { members[b, default: []].append(e) }
        }
        let order = members.keys.sorted { a, b in
            if a.isUnspecified != b.isUnspecified { return b.isUnspecified }
            return spec.ascending ? Bucket.ascending(a, b) : Bucket.ascending(b, a)
        }
        return order.map { b in
            ItemGroup(bucket: b, items: SortEngine.sort(members[b]!, by: sort, folders: .filesFirst, metadata: metadata))
        }
    }
}

/// A row on screen: a group header, or an item (its index among the shown items).
public enum ListRow: Sendable, Equatable {
    case header(Int)
    case item(Int)
}

/// What the list shows: the items in order (collapsed groups' items left out) and, when grouped, the
/// header rows between them. Selection and the keyboard work on `items`; views map rows to items.
public struct ListLayout: Sendable {
    public let groups: [ItemGroup]
    public let collapsed: Set<String>
    public let items: [FileEntry]
    public let rows: [ListRow]
    /// The row of each item.
    public let rowOfItem: [Int]
    /// The first item of each group and how many of its items are shown (0 when collapsed).
    public let groupRanges: [Range<Int>]
    /// How deep each item sits under an open folder in Details view (ListTree); 0 at the top level.
    public let depths: [Int]
    /// The items at the top level: the folder's own items, as the status bar counts them.
    public let topLevelCount: Int

    public var isGrouped: Bool { !groups.isEmpty }

    /// Ungrouped: one row per item.
    public init(items: [FileEntry]) {
        self.init(items: items, depths: Array(repeating: 0, count: items.count))
    }

    /// Ungrouped, with open folders' items flattened in (ListTree.flatten): one row per item.
    public init(items: [FileEntry], depths: [Int]) {
        precondition(depths.count == items.count, "one depth per item")
        groups = []
        collapsed = []
        self.items = items
        rows = items.indices.map(ListRow.item)
        rowOfItem = Array(items.indices)
        groupRanges = []
        self.depths = depths
        topLevelCount = depths.reduce(0) { $0 + ($1 == 0 ? 1 : 0) }
    }

    public init(groups: [ItemGroup], collapsed: Set<String>) {
        self.groups = groups
        self.collapsed = collapsed
        var items: [FileEntry] = []
        var rows: [ListRow] = []
        var rowOfItem: [Int] = []
        var ranges: [Range<Int>] = []
        for (g, group) in groups.enumerated() {
            rows.append(.header(g))
            let start = items.count
            if !collapsed.contains(group.bucket.id) {
                for e in group.items {
                    rowOfItem.append(rows.count)
                    rows.append(.item(items.count))
                    items.append(e)
                }
            }
            ranges.append(start..<items.count)
        }
        self.items = items
        self.rows = rows
        self.rowOfItem = rowOfItem
        groupRanges = ranges
        depths = Array(repeating: 0, count: items.count)
        topLevelCount = groups.reduce(0) { $0 + $1.items.count }
    }

    /// How deep item `i` sits (0 for a row past the end).
    public func depth(ofItem i: Int) -> Int { depths.indices.contains(i) ? depths[i] : 0 }

    /// The item on a row, nil for a header or a row past the end.
    public func item(atRow row: Int) -> Int? {
        guard rows.indices.contains(row), case .item(let i) = rows[row] else { return nil }
        return i
    }

    public func group(atRow row: Int) -> Int? {
        guard rows.indices.contains(row), case .header(let g) = rows[row] else { return nil }
        return g
    }

    /// The group an item belongs to.
    public func group(ofItem i: Int) -> Int? { groupRanges.firstIndex { $0.contains(i) } }

    public func isCollapsed(_ group: Int) -> Bool {
        groups.indices.contains(group) && collapsed.contains(groups[group].bucket.id)
    }
}
