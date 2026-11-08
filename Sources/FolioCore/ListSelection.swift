import Foundation

/// The list's selection the Explorer way: an anchor for Shift ranges, a focus row the keyboard moves,
/// and the selected rows. Pure row indices; the table applies `rows`.
public struct ListSelection: Equatable, Sendable {
    public private(set) var rows = IndexSet()
    /// Where Shift+click and Shift+arrows ranges start.
    public private(set) var anchor: Int?
    /// The row the keyboard is on (Explorer's focus rectangle).
    public private(set) var focus: Int?
    public private(set) var count: Int

    public enum Move: Equatable, Sendable {
        case up, down, home, end
        case pageUp(Int), pageDown(Int)
    }

    public init(count: Int) { self.count = max(0, count) }

    /// The list got shorter or longer: rows past the end are dropped, anchor and focus clamped.
    public mutating func setCount(_ n: Int) {
        count = max(0, n)
        rows = rows.filteredIndexSet { $0 < count }
        if count == 0 { anchor = nil; focus = nil; return }
        if let f = focus, f >= count { focus = rows.last ?? count - 1 }
        if let a = anchor, a >= count { anchor = focus }
    }

    /// Click: only this row.
    public mutating func click(_ row: Int) {
        guard valid(row) else { return }
        rows = IndexSet(integer: row)
        anchor = row
        focus = row
    }

    /// Cmd+click (Explorer's Ctrl+click): in or out, and the row becomes the anchor.
    public mutating func toggle(_ row: Int) {
        guard valid(row) else { return }
        if rows.contains(row) { rows.remove(row) } else { rows.insert(row) }
        anchor = row
        focus = row
    }

    /// Shift+click: the range from the anchor to `row`, and nothing else.
    public mutating func extend(to row: Int) {
        guard valid(row) else { return }
        let a = anchor ?? row
        anchor = a
        rows = IndexSet(min(a, row)...max(a, row))
        focus = row
    }

    /// Cmd+Shift+click: adds the range from the anchor to `row` and keeps what was selected.
    public mutating func addRange(to row: Int) {
        guard valid(row) else { return }
        let a = anchor ?? row
        anchor = a
        rows.insert(integersIn: min(a, row)...max(a, row))
        focus = row
    }

    /// Arrows, Home, End, Page Up, Page Down; with Shift the range runs from the anchor to the new focus.
    public mutating func move(_ key: Move, extend: Bool) {
        guard count > 0 else { return }
        let target = destination(key)
        if extend {
            if anchor == nil { anchor = focus ?? target }
            self.extend(to: target)
        } else {
            click(target)
        }
    }

    /// Ctrl+arrows: the focus moves, the selection stays.
    public mutating func moveFocus(_ key: Move) {
        guard count > 0 else { return }
        focus = destination(key)
    }

    /// Ctrl+Space: toggles the focused row.
    public mutating func toggleFocused() {
        guard let f = focus else { return }
        toggle(f)
    }

    public mutating func selectAll() {
        rows = count > 0 ? IndexSet(0..<count) : IndexSet()
    }

    public mutating func selectNone() { rows = IndexSet() }

    /// Every row that was not selected, and none that was.
    public mutating func invert() {
        rows = count > 0 ? IndexSet(0..<count).subtracting(rows) : IndexSet()
    }

    /// A selection made elsewhere (type to select, a rubber band, the table itself) becomes the truth;
    /// `focus` is also the anchor for the next range.
    public mutating func adopt(_ newRows: IndexSet, focus newFocus: Int?) {
        rows = newRows.filteredIndexSet { $0 < count }
        if let f = newFocus, valid(f) {
            focus = f
            anchor = f
        } else if rows.isEmpty == false, focus == nil || !rows.contains(focus!) {
            focus = rows.first
            anchor = rows.first
        }
    }

    private func valid(_ row: Int) -> Bool { row >= 0 && row < count }

    private func destination(_ key: Move) -> Int {
        let last = count - 1
        // Nothing focused yet: End lands on the last row, every other key on the first.
        guard let f = focus else { return key == .end ? last : 0 }
        let next: Int = switch key {
        case .up: f - 1
        case .down: f + 1
        case .home: 0
        case .end: last
        case .pageUp(let n): f - max(1, n)
        case .pageDown(let n): f + max(1, n)
        }
        return min(max(next, 0), last)
    }
}

/// The rubber band drawn from the list's empty space (Explorer's marquee). Hit testing is on rows of
/// equal height laid from y = 0 down, in the table's flipped coordinates.
public enum RubberBand {
    public struct Rect: Equatable, Sendable {
        public var x, y, width, height: Double
    }

    /// The band between where the drag started and where the mouse is now, whichever way it went.
    public static func rect(from a: (x: Double, y: Double), to b: (x: Double, y: Double)) -> Rect {
        Rect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Rows whose band [i*h, (i+1)*h) the vertical span touches. A span ending exactly on a row's top
    /// edge does not touch that row.
    public static func rows(fromY a: Double, toY b: Double, rowHeight h: Double, count: Int) -> IndexSet {
        guard count > 0, h > 0 else { return IndexSet() }
        let top = min(a, b), bottom = max(a, b)
        guard bottom > 0, top < Double(count) * h else { return IndexSet() }
        let first = max(0, Int((top / h).rounded(.down)))
        var last = Int((bottom / h).rounded(.down))
        if bottom == Double(last) * h, last > first { last -= 1 }
        last = min(count - 1, last)
        guard first <= last else { return IndexSet() }
        return IndexSet(first...last)
    }

    /// Cmd+drag adds to what was selected; a plain drag replaces it.
    public static func selection(base: IndexSet, hit: IndexSet, adding: Bool) -> IndexSet {
        adding ? base.union(hit) : hit
    }
}

/// When a loop that follows a mouse press must stop without its button-up event. Mission Control,
/// Exposé or a Space switch can take the release, and the window would stay stuck in the press.
public enum PressTracking {
    /// `pressedButtons` is `NSEvent.pressedMouseButtons` (bit 0 left, bit 1 right); `button` is the
    /// one pressed. `idle` is the time since the last event; `limit` nil means no idle limit.
    public static func shouldStop(pressedButtons: Int, button: Int, idle: Double, limit: Double?) -> Bool {
        if pressedButtons & (1 << button) == 0 { return true }
        if let limit, idle >= limit { return true }
        return false
    }
}
