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

    /// `itemKey` for many items at once: each folder is resolved once, not once per item, and a plain
    /// path is split as text instead of through `standardizedFileURL`.
    public static func itemKeys(_ urls: [URL]) -> [String] {
        var folders: [Substring: String] = [:]
        return urls.map { url in
            let path = url.path
            // "." or ".." parts, a double slash or the root: the careful way.
            guard isPlain(path), let slash = path.lastIndex(of: "/") else { return itemKey(url) }
            let parentPath = slash == path.startIndex ? Substring("/") : path[..<slash]
            let parent: String
            if let known = folders[parentPath] {
                parent = known
            } else {
                parent = folderKey(URL(fileURLWithPath: String(parentPath), isDirectory: true))
                folders[parentPath] = parent
            }
            return (parent == "/" ? "" : parent) + path[slash...]
        }
    }

    /// An absolute path with no "." or ".." part, no double slash and no slash at the end (not the root).
    static func isPlain(_ path: String) -> Bool {
        let slash = UInt8(ascii: "/"), dot = UInt8(ascii: ".")
        var bytes = path.utf8.makeIterator()
        guard bytes.next() == slash else { return false }
        // How the current part looks so far: 0 just after a slash, 1 ".", 2 "..", 3 anything else.
        var part = 0
        while let b = bytes.next() {
            if b == slash {
                if part != 3 { return false }
                part = 0
            } else if b == dot, part < 2 {
                part += 1
            } else {
                part = 3
            }
        }
        return part == 3
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
