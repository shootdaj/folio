import Foundation

/// Details view's folders that open in place, as in the Finder's list view: an open folder's items
/// follow its row, one level deeper. Folders are keyed by `FilePaths.itemKey` (for a folder that is
/// not a link, the same as its `folderKey`), the key the list already keeps for each row.
public enum ListTree {
    /// A real folder: a file, a package (already not a folder) or a link does not open in place.
    /// A link is left out because it can point back up the tree.
    public static func canExpand(_ e: FileEntry) -> Bool { e.isFolder && !e.isLink }

    /// The top level as given, with the items of each open folder after its row, one level deeper.
    /// `children` holds each listed folder's items as listed; `arrange` filters and sorts one level
    /// (the list's own filters and sort), so a child stays under its parent. A folder already on the
    /// path does not open again.
    public static func flatten(_ top: [FileEntry], children: [String: [FileEntry]], expanded: Set<String>,
                               arrange: ([FileEntry]) -> [FileEntry]) -> (items: [FileEntry], depths: [Int]) {
        guard !expanded.isEmpty else { return (top, Array(repeating: 0, count: top.count)) }
        var items: [FileEntry] = []
        var depths: [Int] = []
        items.reserveCapacity(top.count)
        depths.reserveCapacity(top.count)
        func add(_ level: [FileEntry], depth: Int, path: Set<String>) {
            for e in level {
                items.append(e)
                depths.append(depth)
                guard canExpand(e) else { continue }
                let key = FilePaths.itemKey(e.url)
                guard expanded.contains(key), !path.contains(key), let rows = children[key] else { continue }
                add(arrange(rows), depth: depth + 1, path: path.union([key]))
            }
        }
        add(top, depth: 0, path: [])
        return (items, depths)
    }

    /// The folder and its subfolders, listed for an Option+click: `maxDepth` levels (1 is the folder
    /// alone) and at most `maxFolders` folders, breadth first. A folder that cannot be listed is left out.
    public static func descendants(of folder: URL, list: (URL) throws -> [FileEntry], maxDepth: Int = 8,
                                   maxFolders: Int = 2000) -> [String: [FileEntry]] {
        var out: [String: [FileEntry]] = [:]
        var level = [folder]
        var depth = 1
        while !level.isEmpty, depth <= maxDepth {
            var next: [URL] = []
            for url in level {
                guard out.count < maxFolders else { return out }
                let key = FilePaths.itemKey(url)
                guard out[key] == nil, let rows = try? list(url) else { continue }
                out[key] = rows
                next += rows.filter(canExpand).map(\.url)
            }
            level = next
            depth += 1
        }
        return out
    }

    /// The items with none of the others' folders above them, repeats removed, in order: with folders open
    /// in place a selection can hold a folder and its own items, and an operation must take the folder alone.
    public static func outermost(_ urls: [URL]) -> [URL] {
        let keys = urls.map { FilePaths.itemKey($0) }
        let all = Set(keys)
        var seen = Set<String>()
        var out: [URL] = []
        for (url, key) in zip(urls, keys) where !seen.contains(key) {
            seen.insert(key)
            var parent = FilePaths.parentKey(ofItemKey: key)
            var nested = false
            while parent != "/" && !parent.isEmpty {
                if all.contains(parent) { nested = true; break }
                parent = FilePaths.parentKey(ofItemKey: parent)
            }
            if !nested { out.append(url) }
        }
        return out
    }

    /// The row of item `i`'s parent folder: the nearest earlier row one level up; nil at the top level.
    public static func parent(of i: Int, depths: [Int]) -> Int? {
        guard depths.indices.contains(i), depths[i] > 0 else { return nil }
        var j = i - 1
        while j >= 0 {
            if depths[j] < depths[i] { return j }
            j -= 1
        }
        return nil
    }
}
