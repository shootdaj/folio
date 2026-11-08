import Foundation

/// The rows one Move to Trash takes, before the disk is asked.
public struct SuggestionSelection: Sendable {
    /// The suggestions that have at least one item in the selection, with those items.
    public var entries: [(suggestion: Suggestion, items: [SuggestionItem])]
    /// The bytes the move frees. For one item this is the item's size.
    public var bytes: Int64

    public var items: [SuggestionItem] { entries.flatMap(\.items) }
    public var count: Int { entries.reduce(0) { $0 + $1.items.count } }
    public var isEmpty: Bool { entries.isEmpty }
}

/// What a Move to Trash does after the checks.
public struct SuggestionTrashPlan: Sendable {
    /// The URLs to move: no repeats, and none inside another.
    public var urls: [URL]
    /// The ids of every item that the move takes. The page hides these until the files change.
    public var keys: [String]
    /// The bytes the move frees.
    public var bytes: Int64
    /// Items left out because the file is not the one the scan saw.
    public var changed: Int
    /// Duplicate groups left out because the kept copy changed. The app scans these again.
    public var staleGroups: [Suggestion]

    public var isEmpty: Bool { urls.isEmpty }
}

/// Which items a Move to Trash may take, and the checks right before it.
public enum SuggestionActions {
    /// The items of these suggestions that a move may take. It never takes a kept copy, a Trash row,
    /// an item that is pending, an ignored path, or a duplicate with an ignored hash.
    /// With `item`, only that item, and only when it is allowed.
    public static func selection(of suggestions: [Suggestion], item: SuggestionItem? = nil, pending: Set<String>,
                                 ignores: SuggestionIgnores.Snapshot) -> SuggestionSelection {
        var entries: [(suggestion: Suggestion, items: [SuggestionItem])] = []
        var bytes: Int64 = 0
        var seen = Set<String>()
        for s in suggestions where s.kind.canMoveToTrash {
            if case .sameContent(_, let sha, _) = s.reason, ignores.coversHash(sha) { continue }
            var items = s.removable.filter { !pending.contains($0.id) && !ignores.covers($0.id) && seen.insert($0.id).inserted }
            if let item { items = items.filter { $0.id == item.id } }
            guard !items.isEmpty else { continue }
            entries.append((s, items))
            if item != nil {
                bytes += items.reduce(0) { $0 + $1.bytes }
            } else if items.count == s.removable.count {
                bytes += s.bytes
            } else {
                bytes += items.reduce(0) { $0 + $1.bytes }
            }
        }
        return SuggestionSelection(entries: entries, bytes: bytes)
    }

    /// The plan for a move: the selection, then only items whose stamp is still the scan's. A duplicate
    /// group also needs the kept copy to be unchanged. If it is not, the group is refused.
    public static func trashPlan(of suggestions: [Suggestion], item: SuggestionItem? = nil, pending: Set<String>,
                                 ignores: SuggestionIgnores.Snapshot, fs: any ScanFileSystem) -> SuggestionTrashPlan {
        let chosen = selection(of: suggestions, item: item, pending: pending, ignores: ignores)
        var verified: [SuggestionItem] = []
        var changed = 0
        var stale: [Suggestion] = []
        var bytes: Int64 = 0
        for (s, items) in chosen.entries {
            if s.kind == .duplicates {
                guard let keep = s.items.first(where: { $0.url == s.keep }), fs.stamp(keep.url) == keep.stamp else {
                    stale.append(s)
                    continue
                }
            }
            let ok = SuggestionVerify.current(items, fs: fs)
            changed += items.count - ok.count
            verified += ok
            bytes += ok.reduce(0) { $0 + $1.bytes }
        }
        if item == nil, changed == 0, stale.isEmpty { bytes = chosen.bytes }
        let urls = SuggestionReport.outermost(verified.map(\.url))
        return SuggestionTrashPlan(urls: urls, keys: verified.map(\.id), bytes: bytes, changed: changed, staleGroups: stale)
    }
}

/// Where the keyboard focus goes on the page. It only moves between rows that can have focus.
public enum SuggestionFocus {
    /// Rows a Page Up or Page Down key moves.
    public static let pageStep = 6

    public enum Move: Sendable, Equatable {
        case by(Int), first, last
    }

    /// The id that gets the focus. With no focus, a step forward starts at the first row and a step back at the last.
    /// A focus that is not in the list counts as no focus. The focus stops at both ends.
    public static func next(ids: [String], current: String?, move: Move) -> String? {
        guard !ids.isEmpty else { return nil }
        switch move {
        case .first: return ids.first
        case .last: return ids.last
        case .by(let step):
            guard let current, let at = ids.firstIndex(of: current) else { return step > 0 ? ids.first : ids.last }
            return ids[min(max(0, at + step), ids.count - 1)]
        }
    }
}
