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
    ///
    /// Each item's keys are worked out once into flat arrays (names and text as Core Foundation strings,
    /// numbers and dates as doubles), the comparisons read them by index without copying items, and a
    /// large list is sorted in parts on every core, then merged.
    public static func sort(_ entries: [FileEntry], by spec: SortSpec, folders: FolderPlacement = .followSort,
                            metadata: (FileEntry) -> ItemMetadata? = { _ in nil }) -> [FileEntry] {
        guard entries.count > 1 else { return entries }
        let terms = spec.terms
        let wantsMeta = terms.contains { $0.key.needsMetadata }
        var cells: [SortCell] = []
        cells.reserveCapacity(entries.count * terms.count)
        for e in entries {
            let meta = wantsMeta ? metadata(e) : nil
            for t in terms { cells.append(SortCell(ColumnValues.value(e, t.key, meta))) }
        }
        let keys = SortKeys(entries: entries, cells: cells, ascending: terms.map(\.ascending), up: spec.ascending, folders: folders)
        return keys.sortedIndices().map { entries[$0] }
    }

    /// Below this many items one thread sorts; above it, every core takes a part.
    static let parallelThreshold = 8_192
}

/// One sort key of one item: no value, a number or date (as a double), or text.
struct SortCell: @unchecked Sendable {
    /// ColumnValue.compare's order between kinds: none, number, date, text.
    let rank: UInt8
    let number: Double
    let text: CFString?

    init(_ v: ColumnValue) {
        switch v {
        case .none: (rank, number, text) = (0, 0, nil)
        case .number(let x): (rank, number, text) = (1, x, nil)
        case .date(let d): (rank, number, text) = (2, d.timeIntervalSinceReferenceDate, nil)
        case .text(let t): (rank, number, text) = (3, 0, StandardOrder.key(t))
        }
    }
}

/// Everything a comparison reads, made once per sort; read from several threads at once, never written.
struct SortKeys: @unchecked Sendable {
    let entries: [FileEntry]
    let cells: [SortCell]
    let stride: Int
    let ascending: [Bool]
    let names: [CFString]
    let isFolder: [Bool]
    let up: Bool
    let filesFirst: Bool
    let order = StandardOrder()

    init(entries: [FileEntry], cells: [SortCell], ascending: [Bool], up: Bool, folders: FolderPlacement) {
        self.entries = entries
        self.cells = cells
        stride = ascending.count
        self.ascending = ascending
        names = entries.map { StandardOrder.key($0.name) }
        isFolder = entries.map(\.isFolder)
        self.up = up
        filesFirst = folders == .filesFirst
    }

    /// The sort's order: true when item `a` goes before item `b`.
    func less(_ a: Int, _ b: Int) -> Bool {
        let fa = isFolder[a], fb = isFolder[b]
        if fa != fb { return filesFirst ? fb : (up ? fa : fb) }
        let ra = a * stride, rb = b * stride
        for i in 0..<stride {
            let x = cells[ra + i], y = cells[rb + i]
            let c: Int
            if x.rank != y.rank {
                c = x.rank < y.rank ? -1 : 1
            } else if x.rank == 3, let tx = x.text, let ty = y.text {
                c = order.compare(tx, ty)
            } else {
                c = x.number < y.number ? -1 : (x.number > y.number ? 1 : 0)
            }
            if c != 0 { return ascending[i] ? c < 0 : c > 0 }
        }
        switch order.compare(names[a], names[b]) {
        case -1: return up
        case 1: return !up
        default:
            let pa = entries[a].url.path, pb = entries[b].url.path
            return up ? pa < pb : pa > pb
        }
    }

    /// The items' indices in sorted order.
    func sortedIndices() -> [Int] {
        let n = entries.count
        var idx = Array(0..<n)
        let parts = min(ProcessInfo.processInfo.activeProcessorCount, 16, n / (SortEngine.parallelThreshold / 2))
        guard n >= SortEngine.parallelThreshold, parts > 1 else {
            idx.sort(by: less)
            return idx
        }
        // Each part sorted on its own core, then neighbouring runs merged, a round at a time.
        var bounds = (0...parts).map { $0 * n / parts }
        idx.withUnsafeMutableBufferPointer { buf in
            let base = UnsafeSendable(buf)
            let edges = bounds
            DispatchQueue.concurrentPerform(iterations: parts) { p in
                var part = UnsafeMutableBufferPointer(rebasing: base.value[edges[p]..<edges[p + 1]])
                part.sort(by: less)
            }
        }
        var other = [Int](repeating: 0, count: n)
        while bounds.count > 2 {
            let runs = bounds.count - 1
            let pairs = runs / 2
            idx.withUnsafeBufferPointer { src in
                other.withUnsafeMutableBufferPointer { dst in
                    let s = UnsafeSendable(src), d = UnsafeSendable(dst), edges = bounds
                    DispatchQueue.concurrentPerform(iterations: (runs + 1) / 2) { p in
                        let lo = edges[2 * p], mid = edges[min(2 * p + 1, runs)], hi = edges[min(2 * p + 2, runs)]
                        merge(s.value, lo, mid, hi, into: d.value)
                    }
                }
            }
            swap(&idx, &other)
            var next: [Int] = []
            for p in 0...pairs where 2 * p <= runs { next.append(bounds[2 * p]) }
            if next.last != n { next.append(n) }
            bounds = next
        }
        return idx
    }

    /// Merges the sorted runs src[lo..<mid] and src[mid..<hi] into dst[lo..<hi]; the left run wins ties.
    private func merge(_ src: UnsafeBufferPointer<Int>, _ lo: Int, _ mid: Int, _ hi: Int, into dst: UnsafeMutableBufferPointer<Int>) {
        var i = lo, j = mid, k = lo
        while i < mid && j < hi {
            if less(src[j], src[i]) { dst[k] = src[j]; j += 1 } else { dst[k] = src[i]; i += 1 }
            k += 1
        }
        while i < mid { dst[k] = src[i]; i += 1; k += 1 }
        while j < hi { dst[k] = src[j]; j += 1; k += 1 }
    }
}

/// A buffer handed to `concurrentPerform`, whose parts each touch their own range.
private struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// `localizedStandardCompare` (Finder's name order) on strings made into Core Foundation strings once:
/// case- and width-insensitive, numbers by value, forced to a total order, in the current locale.
public struct StandardOrder: @unchecked Sendable {
    private static let flags: CFStringCompareFlags = [.compareCaseInsensitive, .compareNumerically,
                                                       .compareWidthInsensitive, .compareForcedOrdering]
    private let locale = CFLocaleCopyCurrent()

    public init() {}

    /// A real Core Foundation copy of `s` (a bridged Swift string is slow to compare).
    public static func key(_ s: String) -> CFString {
        CFStringCreateCopy(nil, NSString(string: s)) ?? (s as CFString)
    }

    /// -1, 0 or 1.
    public func compare(_ a: CFString, _ b: CFString) -> Int {
        switch CFStringCompareWithOptionsAndLocale(a, b, CFRange(location: 0, length: CFStringGetLength(a)), Self.flags, locale) {
        case .compareLessThan: -1
        case .compareGreaterThan: 1
        default: 0
        }
    }
}
