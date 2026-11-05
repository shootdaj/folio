import Foundation

/// One sort key and its direction.
public struct SortTerm: Sendable, Equatable, Codable {
    public var key: SortKey
    public var ascending: Bool

    public init(key: SortKey, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }
}

/// The list's sort: a primary column and, from Shift+clicks, up to three more (Explorer's GUI allows
/// four keys in all).
public struct SortSpec: Sendable, Equatable {
    public var key: SortKey
    public var ascending: Bool
    /// The Shift+click keys after the first, in the order they were added.
    public var then: [SortTerm]

    public static let maxKeys = 4

    public init(key: SortKey, ascending: Bool, then: [SortTerm] = []) {
        self.key = key
        self.ascending = ascending
        self.then = Array(then.filter { $0.key != key }.prefix(Self.maxKeys - 1))
    }

    public static let standard = SortSpec(key: .name, ascending: true)

    public var terms: [SortTerm] { [SortTerm(key: key, ascending: ascending)] + then }

    /// Header click: the primary column reverses (keeping any Shift+click keys); another column becomes
    /// the only key, in its default direction.
    public func clicking(_ column: SortKey) -> SortSpec {
        column == key
            ? SortSpec(key: key, ascending: !ascending, then: then)
            : SortSpec(key: column, ascending: column.defaultAscending)
    }

    /// Shift+click: a column not yet sorted on becomes the next key (the fourth key is replaced when
    /// all four are taken); a column already among the keys reverses.
    public func shiftClicking(_ column: SortKey) -> SortSpec {
        if column == key { return SortSpec(key: key, ascending: !ascending, then: then) }
        var rest = then
        if let i = rest.firstIndex(where: { $0.key == column }) {
            rest[i].ascending.toggle()
        } else {
            if rest.count >= Self.maxKeys - 1 { rest.removeLast() }
            rest.append(SortTerm(key: column, ascending: column.defaultAscending))
        }
        return SortSpec(key: key, ascending: ascending, then: rest)
    }

    /// 1 for the primary column, 2 for the first Shift+click key...; nil when not sorted on.
    public func rank(of column: SortKey) -> Int? {
        terms.firstIndex { $0.key == column }.map { $0 + 1 }
    }

    public func isAscending(_ column: SortKey) -> Bool? {
        terms.first { $0.key == column }?.ascending
    }
}

/// Where folders go among files.
public enum FolderPlacement: Sendable {
    /// Explorer's list: folders on top when the first key is ascending, at the bottom when descending.
    case followSort
    /// Inside a Group by group Explorer puts files first.
    case filesFirst
}

public enum SortEngine {
    /// Folders form a block (on top ascending, at the bottom descending); then each key in turn, each in
    /// its own direction; ties break on Name in the first key's direction (Explorer's Type ties break by
    /// Name and reverse with it), then on the path, so the order is total.
    public static func sort(_ entries: [FileEntry], by spec: SortSpec, folders: FolderPlacement = .followSort,
                            metadata: (FileEntry) -> ItemMetadata? = { _ in nil }) -> [FileEntry] {
        let terms = spec.terms
        let wantsMeta = terms.contains { $0.key.needsMetadata }
        let keyed = entries.map { e -> (FileEntry, [ColumnValue]) in
            let meta = wantsMeta ? metadata(e) : nil
            return (e, terms.map { ColumnValues.value(e, $0.key, meta) })
        }
        let up = spec.ascending
        return keyed.sorted { a, b in
            let (ea, eb) = (a.0, b.0)
            if ea.isFolder != eb.isFolder {
                switch folders {
                case .followSort: return up ? ea.isFolder : eb.isFolder
                case .filesFirst: return eb.isFolder
                }
            }
            for (i, term) in terms.enumerated() {
                let c = ColumnValue.compare(a.1[i], b.1[i])
                if c != 0 { return term.ascending ? c < 0 : c > 0 }
            }
            switch ea.name.localizedStandardCompare(eb.name) {
            case .orderedAscending: return up
            case .orderedDescending: return !up
            case .orderedSame: return up ? ea.url.path < eb.url.path : ea.url.path > eb.url.path
            }
        }.map(\.0)
    }
}
