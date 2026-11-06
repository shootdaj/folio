import Foundation

/// The Details view's column pass: Name takes whatever the fixed columns leave, so the four columns
/// always fit the list and no horizontal scroller appears, overlay or always-visible scrollbars alike.
public enum ColumnFit {
    /// Each NSTableView column is its width plus `gap` (D4's 10 pt cell padding on each side); `trailing`
    /// stays clear on the right (D4's 44 pt `--gut-r`, where the scroller sits).
    public static func nameWidth(clipWidth: Double, otherWidths: [Double], gap: Double, trailing: Double, minimum: Double) -> Double {
        let columns = Double(otherWidths.count + 1)
        let free = clipWidth - otherWidths.reduce(0, +) - gap * columns - trailing
        return max(minimum, free.rounded(.down))
    }
}
