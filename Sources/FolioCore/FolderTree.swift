import Darwin
import Foundation

/// One folder in the navigation pane's tree.
public struct TreeFolder: Sendable, Equatable {
    public let name: String
    /// The folder's path through its parent (a symlinked folder keeps the link's path).
    public let path: String
    /// A dot name or the hidden flag.
    public let isHidden: Bool
    /// A symlink to a folder: shown, opened like the folder, never walked by Expand all.
    public let isLink: Bool
}

/// The navigation pane's folder tree under each volume. A node's children are read the first time it
/// opens and kept until something changes in that folder. Only folders show (no files, no packages),
/// in natural order (File2 before File10); hidden folders only with hidden items on, or when they lead
/// to the folder the window is in (Expand to current folder).
public final class FolderTree {
    /// View > Hidden items. Changing it reads every folder again.
    public var showHidden: Bool {
        didSet {
            guard showHidden != oldValue else { return }
            cache.removeAll()
            primed.removeAll()
        }
    }
    /// Hidden folders that led to a current folder: they stay in the tree once revealed.
    public private(set) var revealed: Set<String> = []
    /// How many folders have been read from disk (the tests check the laziness with it).
    public private(set) var listCount = 0
    private var cache: [String: [TreeFolder]] = [:]
    /// Folders read off the main thread (`prime`), all of their subfolders, waiting for `children(of:)`.
    private var primed: [String: [TreeFolder]] = [:]

    public init(showHidden: Bool = false) {
        self.showHidden = showHidden
    }

    public func isLoaded(_ path: String) -> Bool { cache[path] != nil }

    /// The node's subfolders, read from disk on the first ask.
    public func children(of path: String) -> [TreeFolder] {
        if let known = cache[path] { return known }
        listCount += 1
        let kids = shown(primed.removeValue(forKey: path) ?? Self.subfolders(of: path))
        cache[path] = kids
        return kids
    }

    /// The folders of a read that the tree shows: hidden ones only when shown or revealed.
    public func shown(_ all: [TreeFolder]) -> [TreeFolder] {
        all.filter { showHidden || !$0.isHidden || revealed.contains($0.path) }
    }

    /// Hands over folders read off the main thread (`subfolders(of:)`, every subfolder): the next
    /// `children(of:)` of each uses them instead of the disk. Folders already in the tree are left alone.
    public func prime(_ lists: [String: [TreeFolder]]) {
        for (path, list) in lists where cache[path] == nil { primed[path] = list }
    }

    /// The cached children, without reading anything.
    public func cachedChildren(of path: String) -> [TreeFolder]? { cache[path] }

    /// Something changed in `path`: its children are read again the next time.
    public func invalidate(_ path: String) {
        cache[path] = nil
        primed[path] = nil
    }

    public func invalidateAll() {
        cache.removeAll()
        primed.removeAll()
    }

    /// Makes the hidden folders on `chain` (from a root down to the current folder) part of the tree.
    /// Returns the loaded nodes that now have a child they did not list, in chain order, for reloading.
    @discardableResult
    public func reveal(_ chain: [String]) -> [String] {
        var changed: [String] = []
        for (parent, child) in zip(chain, chain.dropFirst()) {
            guard !showHidden, !revealed.contains(child) else { continue }
            let name = (child as NSString).lastPathComponent
            if let known = cache[parent], known.contains(where: { $0.path == child }) { continue }
            guard Self.isHiddenFolder(child, name: name) else { continue }
            revealed.insert(child)
            if cache[parent] != nil {
                cache[parent] = nil
                changed.append(parent)
            }
        }
        return changed
    }

    /// Numpad * and Option+Right: every folder below `path` to expand, breadth first, `path` first,
    /// at most `limit` of them (so * on a whole disk stops in time). Links are shown, never walked.
    public func descendants(of path: String, limit: Int) -> [String] {
        var out: [String] = []
        var queue = [path]
        var seen: Set<String> = []
        while !queue.isEmpty, out.count < limit {
            let next = queue.removeFirst()
            guard seen.insert(next).inserted else { continue }
            out.append(next)
            for kid in children(of: next) where !kid.isLink { queue.append(kid.path) }
        }
        return out
    }

    // MARK: Paths

    /// The volume a path lives on: the deepest of `roots` that holds it, "/" when none does.
    public static func root(for path: String, roots: [String]) -> String {
        roots.filter { $0 != "/" && (path == $0 || path.hasPrefix($0 + "/")) }
            .max { $0.count < $1.count } ?? "/"
    }

    /// Every node from `root` down to `target`, both included; nil when `target` is not under `root`.
    public static func chain(from root: String, to target: String) -> [String]? {
        let r = Breadcrumbs.normalized(root), t = Breadcrumbs.normalized(target)
        guard t == r || t.hasPrefix(r == "/" ? "/" : r + "/") else { return nil }
        var out = [r]
        var prefix = r == "/" ? "" : r
        for part in Breadcrumbs.components(of: String(t.dropFirst(prefix.count))) {
            prefix += "/" + part
            out.append(prefix)
        }
        return out
    }

    // MARK: Reading folders

    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey]
    private static let keySet = Set(keys)

    /// Every folder in `path` (hidden ones marked), natural order. Files and packages are left out.
    ///
    /// `readdir` gives each entry's type with its name, so the files of a large folder cost nothing: a
    /// folder costs one `lstat` (the hidden flag) and one `getxattr` (Finder's bundle bit), and only links
    /// and entries of unknown type (some network drives) go through URL values.
    public static func subfolders(of path: String) -> [TreeFolder] {
        guard let dir = opendir(path) else { return [] }
        defer { closedir(dir) }
        let fd = dirfd(dir)
        let parent = path == "/" ? "" : path
        var out: [TreeFolder] = []
        var info = [UInt8](repeating: 0, count: 32)
        while let entry = readdir(dir) {
            let type = Int32(entry.pointee.d_type)
            guard type == DT_DIR || type == DT_LNK || type == DT_UNKNOWN else { continue }
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            guard name != ".", name != ".." else { continue }
            let full = parent + "/" + name
            if type == DT_DIR {
                var st = stat()
                let flagged = fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 && st.st_flags & UInt32(UF_HIDDEN) != 0
                // A package: the bundle bit, or an extension Launch Services calls a package (asked once each).
                let got = getxattr(full, "com.apple.FinderInfo", &info, 32, 0, XATTR_NOFOLLOW)
                let bundleBit = got >= 10 && info[8] & 0x20 != 0
                if bundleBit || PackageExtensions.isPackage((name as NSString).pathExtension) { continue }
                out.append(TreeFolder(name: name, path: full, isHidden: flagged || name.hasPrefix("."), isLink: false))
                continue
            }
            let url = URL(fileURLWithPath: full)
            guard let values = try? url.resourceValues(forKeys: keySet) else { continue }
            var isDirectory = values.isDirectory ?? false
            var isPackage = values.isPackage ?? false
            let isLink = values.isSymbolicLink ?? false
            if isLink {
                let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                isDirectory = target?.isDirectory ?? false
                isPackage = target?.isPackage ?? false
            }
            guard isDirectory && !isPackage else { continue }
            out.append(TreeFolder(name: name, path: full, isHidden: (values.isHidden ?? false) || name.hasPrefix("."), isLink: isLink))
        }
        let names = out.map { StandardOrder.key($0.name) }
        let order = StandardOrder()
        return out.indices.sorted { order.compare(names[$0], names[$1]) < 0 }.map { out[$0] }
    }

    private static func isHiddenFolder(_ path: String, name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden ?? false
    }
}
