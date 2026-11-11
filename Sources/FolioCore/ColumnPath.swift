import Foundation

/// The Columns view (Finder's column view, in Folio's look): which folders stand side by side. Paths are
/// standardized file paths ("/" for the startup disk's root); a zip browsed as a folder is a folder here.
public enum ColumnPath {
    /// `path` is `folder` or somewhere inside it.
    public static func contains(_ folder: String, _ path: String) -> Bool {
        let f = clean(folder)
        return f == path || f == "/" || path.hasPrefix(f + "/")
    }

    /// Where the columns start for `folder`. A move inside the columns (to a folder on screen, `shown`, or
    /// into one: Right, Left, a click, Back) keeps `previous`, the first column, while it still holds the
    /// folder, so Right adds a column instead of starting again. Any other move (the sidebar, the address
    /// bar) starts at the deepest of `anchors` (home, Quick access, volume roots) that holds the folder, else "/".
    public static func root(for folder: String, previous: String?, shown: [String] = [], anchors: [String]) -> String {
        if let previous, contains(previous, folder) {
            let parent = (folder as NSString).deletingLastPathComponent
            if shown.contains(folder) || shown.contains(parent.isEmpty ? "/" : parent) { return clean(previous) }
        }
        let holding = anchors.map(clean).filter { contains($0, folder) }
        return holding.max { depth($0) < depth($1) } ?? "/"
    }

    /// The columns' folders, `root` first and `folder` last (the folder alone when `root` does not hold it).
    public static func folders(from root: String, to folder: String) -> [String] {
        let root = clean(root)
        guard contains(root, folder) else { return [folder] }
        var out = [root]
        var at = root
        while at != folder, let next = child(of: at, toward: folder) {
            out.append(next)
            at = next
        }
        return out
    }

    /// The item of `ancestor` on the way down to `descendant` (its child folder), nil when `descendant`
    /// is not inside `ancestor`.
    public static func child(of ancestor: String, toward descendant: String) -> String? {
        let a = clean(ancestor)
        guard a != descendant, contains(a, descendant) else { return nil }
        let rest = descendant.dropFirst(a == "/" ? 1 : a.count + 1)
        guard let name = rest.split(separator: "/").first else { return nil }
        return (a == "/" ? "" : a) + "/" + name
    }

    /// Back, Forward or Up landing on `arriving` from `from`: the folder that leads back there is selected
    /// (Right, Right, Back shows the column before with the folder just left selected); nil otherwise.
    public static func selection(arriving: String, from: String) -> String? {
        child(of: arriving, toward: from)
    }

    private static func depth(_ path: String) -> Int { path == "/" ? 0 : path.split(separator: "/").count }

    private static func clean(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

/// What the columns show for a current folder and its selection.
public struct ColumnPlan: Equatable, Sendable {
    /// After the current folder's column: a selected folder's contents, a selected file's preview, or nothing.
    public enum Tail: Equatable, Sendable {
        case none
        case folder(String)
        case preview(String)
    }

    /// The first column's folder to the current folder.
    public let folders: [String]
    /// The name lit in each column but the current one: the item the next column opens.
    public let highlighted: [String]
    public let tail: Tail

    public static func make(root: String, current: String, selected: [(path: String, isFolder: Bool)]) -> ColumnPlan {
        let folders = ColumnPath.folders(from: root, to: current)
        let highlighted = folders.dropFirst().map { ($0 as NSString).lastPathComponent }
        var tail = Tail.none
        if selected.count == 1, let one = selected.first {
            tail = one.isFolder ? .folder(one.path) : .preview(one.path)
        }
        return ColumnPlan(folders: folders, highlighted: highlighted, tail: tail)
    }
}

/// What Left and Right do in the Columns view.
public enum ColumnStep: Equatable, Sendable {
    /// Into this folder, its first item selected.
    case enter(String)
    /// Out to this folder (the column before), with `select`, the folder left, selected in it.
    case leave(to: String, select: String)
    case none
}

public enum ColumnKeys {
    /// Right: into the one selected folder; a file, several items or nothing go nowhere.
    public static func right(selected: [(path: String, isFolder: Bool)]) -> ColumnStep {
        guard selected.count == 1, let one = selected.first, one.isFolder else { return .none }
        return .enter(one.path)
    }

    /// Left: the column before, with this folder selected. In the first column it goes up a folder anyway,
    /// and the columns then start there.
    public static func left(current: String) -> ColumnStep {
        guard current != "/", current.hasPrefix("/") else { return .none }
        let parent = (current as NSString).deletingLastPathComponent
        return .leave(to: parent.isEmpty ? "/" : parent, select: current)
    }
}

/// The columns' width: one for every column, kept in the defaults (no folder keeps its own). A divider
/// dragged sets it; a divider double-clicked fits that column to its widest name.
public enum ColumnWidth {
    public static let key = "columnViewWidth"
    public static let standard: Double = 240
    public static let minimum: Double = 140
    public static let maximum: Double = 640

    public static func clamp(_ width: Double) -> Double { min(maximum, max(minimum, width.rounded())) }

    public static func load(_ defaults: UserDefaults) -> Double {
        guard let saved = defaults.object(forKey: key) as? Double else { return standard }
        return clamp(saved)
    }

    public static func save(_ width: Double, _ defaults: UserDefaults) {
        defaults.set(clamp(width), forKey: key)
    }

    /// Room for the widest name plus `chrome` (the icon, the gaps and the folder chevron).
    public static func fit(widest: Double, chrome: Double) -> Double { clamp(widest.rounded(.up) + chrome) }
}

/// The preview column's lines for a selected file (Finder's preview column): Kind, Size, Created,
/// Modified and Tags. Created and Tags wait for the item's metadata.
public enum ColumnPreview {
    public static func fields(_ entry: FileEntry, _ meta: ItemMetadata?) -> [(key: String, value: String)] {
        var out: [(key: String, value: String)] = [("Kind", entry.isFolder ? "Folder" : entry.kind)]
        if !entry.isFolder { out.append(("Size", ColumnValues.text(entry, .size, meta))) }
        if let created = meta?.created { out.append(("Created", ColumnValues.dateText(created))) }
        if let modified = entry.modified { out.append(("Modified", ColumnValues.dateText(modified))) }
        if let meta { out.append(("Tags", meta.tags.isEmpty ? "None" : meta.tags.joined(separator: ", "))) }
        return out
    }
}
