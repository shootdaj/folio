import Foundation

/// The Details view's columns: which are shown, left to right, and their widths. One set for every
/// folder (no folder keeps its own), saved as it changes.
public struct ColumnSet: Sendable, Equatable, Codable {
    /// Shown columns, left to right. Name is always among them.
    public private(set) var visible: [ColumnID]
    /// Widths the user gave columns; the others use their default.
    public private(set) var widths: [String: Double]

    public static let standardColumns: [ColumnID] = [.name, .modified, .kind, .size]
    public static let standard = ColumnSet(visible: standardColumns)

    public init(visible: [ColumnID], widths: [String: Double] = [:]) {
        var seen = Set<ColumnID>()
        var list = visible.filter { seen.insert($0).inserted }
        if !list.contains(.name) { list.insert(.name, at: 0) }
        self.visible = list
        self.widths = widths
    }

    public func isVisible(_ column: ColumnID) -> Bool { visible.contains(column) }

    public func width(of column: ColumnID) -> Double { widths[column.rawValue] ?? column.defaultWidth }

    public mutating func setWidth(_ width: Double, of column: ColumnID) { widths[column.rawValue] = width }

    /// The header menu's ticks: a hidden column appears at the right end; Name cannot be hidden.
    public mutating func toggle(_ column: ColumnID) {
        guard column != .name else { return }
        if let i = visible.firstIndex(of: column) { visible.remove(at: i) } else { visible.append(column) }
    }

    /// A column dragged to a new place in the header.
    public mutating func move(_ column: ColumnID, to index: Int) {
        guard let from = visible.firstIndex(of: column) else { return }
        visible.remove(at: from)
        visible.insert(column, at: min(max(0, index), visible.count))
    }

    /// Choose details' list: the shown columns in their order, then every other column alphabetically.
    public var chooserOrder: [ColumnID] {
        visible + ColumnID.allCases.filter { !visible.contains($0) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// OK in Choose details: the ticked columns, in the dialog's order.
    public mutating func apply(order: [ColumnID], checked: Set<ColumnID>) {
        self = ColumnSet(visible: order.filter { checked.contains($0) || $0 == .name }, widths: widths)
    }
}

/// Choose details' working list: the order Move Up and Move Down change and the ticks, before OK.
public struct ColumnChooser: Sendable, Equatable {
    public private(set) var order: [ColumnID]
    public private(set) var checked: Set<ColumnID>

    public init(_ set: ColumnSet) {
        order = set.chooserOrder
        checked = Set(set.visible)
    }

    public mutating func setChecked(_ column: ColumnID, _ on: Bool) {
        guard column != .name else { return }
        if on { checked.insert(column) } else { checked.remove(column) }
    }

    @discardableResult
    public mutating func moveUp(_ column: ColumnID) -> Bool {
        guard let i = order.firstIndex(of: column), i > 0 else { return false }
        order.swapAt(i, i - 1)
        return true
    }

    @discardableResult
    public mutating func moveDown(_ column: ColumnID) -> Bool {
        guard let i = order.firstIndex(of: column), i < order.count - 1 else { return false }
        order.swapAt(i, i + 1)
        return true
    }

    public func applied(to set: ColumnSet) -> ColumnSet {
        var out = set
        out.apply(order: order, checked: checked)
        return out
    }
}

/// Where the column set lives in the defaults. A missing or unreadable value is the standard set.
public struct ColumnSetStore {
    public static let key = "detailsColumns"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> ColumnSet {
        guard let data = defaults.data(forKey: Self.key),
              let raw = try? JSONDecoder().decode(Saved.self, from: data) else { return .standard }
        // Columns this build does not know are dropped.
        let visible = raw.visible.compactMap(ColumnID.init(rawValue:))
        return visible.isEmpty ? .standard : ColumnSet(visible: visible, widths: raw.widths)
    }

    public func save(_ set: ColumnSet) {
        let saved = Saved(visible: set.visible.map(\.rawValue), widths: set.widths)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.key) }
    }

    private struct Saved: Codable {
        var visible: [String]
        var widths: [String: Double]
    }
}
