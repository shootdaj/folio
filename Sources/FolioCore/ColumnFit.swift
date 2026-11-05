import Foundation

/// The Details view's column pass: Name takes whatever the fixed columns leave, so the four columns
/// always fit the list and no horizontal scroller appears, overlay or always-visible scrollbars alike.
public enum ColumnFit {
    /// Each NSTableView column is its width plus `gap`; D1 also keeps half a gap clear on the right.
    public static func nameWidth(clipWidth: Double, otherWidths: [Double], gap: Double, minimum: Double) -> Double {
        let columns = Double(otherWidths.count + 1)
        let free = clipWidth - otherWidths.reduce(0, +) - gap * columns - gap / 2
        return max(minimum, free.rounded(.down))
    }
}
