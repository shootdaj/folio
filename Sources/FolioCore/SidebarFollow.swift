import Foundation

/// How the navigation pane follows a folder it opens the tree to (Explorer's "Expand to open folder",
/// New folder from a node's menu). The tree opens down to the folder, but the pane scrolls only when no
/// row for that folder is in view: a click on a Quick access pin keeps the pin where it is instead of
/// jumping to the same folder under This PC.
public enum SidebarFollow {
    /// `target` is the folder being revealed, resolved (FilePaths.folderKey). `visiblePaths` are the
    /// paths of the rows in view (nil for a row with none: Home, a heading); `key` resolves one the
    /// same way, and runs only for a row whose path is not already `target`. `forced` (Ctrl+Shift+E)
    /// always scrolls to the tree row.
    public static func shouldScroll(to target: String, visiblePaths: [String?], forced: Bool,
                                    key: (String) -> String) -> Bool {
        if forced { return true }
        return !visiblePaths.contains { path in path.map { $0 == target || key($0) == target } ?? false }
    }
}
