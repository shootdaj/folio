import Foundation

/// How the navigation pane follows the folder the window shows. After a move the tree opens down to the
/// folder (Explorer's "Expand to open folder"), but the pane scrolls only when no row for that folder is
/// in view: a click on a Quick access pin keeps the pin where it is instead of jumping to the same
/// folder under This PC.
public enum SidebarFollow {
    /// `currentRows` are the rows drawn as the current folder (a pin, an iCloud row, a tree row),
    /// `visibleRows` the rows in view. `forced` (Ctrl+Shift+E) always scrolls to the tree row.
    public static func shouldScroll(currentRows: [Int], visibleRows: Range<Int>, forced: Bool) -> Bool {
        if forced { return true }
        return !currentRows.contains(where: visibleRows.contains)
    }
}
