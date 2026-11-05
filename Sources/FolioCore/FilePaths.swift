import Darwin
import Foundation

/// One spelling per file for comparing paths: /tmp/x and /private/tmp/x are the same item, and a
/// window on /tmp lists URLs that read /private/tmp. Selection after a paste, rename or undo, the dimmed
/// cut items and job refreshes all match on these keys.
public enum FilePaths {
    /// A folder, fully resolved (symlinks and /private included).
    public static func folderKey(_ url: URL) -> String {
        resolved(url.standardizedFileURL.path) ?? url.standardizedFileURL.path
    }

    /// An item: its folder resolved, its own name kept (so a symlink stays the link, not its target).
    public static func itemKey(_ url: URL) -> String {
        let std = url.standardizedFileURL
        guard std.path != "/" else { return "/" }
        let parent = folderKey(std.deletingLastPathComponent())
        return (parent == "/" ? "" : parent) + "/" + std.lastPathComponent
    }

    /// The folder key of the item's folder, for "is this item in that window's folder".
    public static func parentKey(ofItemKey key: String) -> String {
        let parent = (key as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    private static func resolved(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }
}
