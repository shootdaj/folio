import Foundation

/// Where the Suggestions page is in its work.
public enum SuggestionState: Sendable, Equatable {
    case idle, needsAccess, scanning, done, failed
}

/// When a scan starts and when it stops. The app-wide center asks these questions and does the work.
public enum SuggestionSchedule {
    /// The page must be shown this long before an automatic scan starts.
    public static let shownDelay: TimeInterval = 0.5
    /// A report younger than this is not scanned again by itself.
    public static let freshFor: TimeInterval = 30 * 60
    /// A scan that nobody watches stops after this long.
    public static let viewGrace: TimeInterval = 10

    /// The first state. The real home needs Full Disk Access before anything is read. A fixture home does not.
    public static func initialState(granted: Bool, isRealHome: Bool) -> SuggestionState {
        granted || !isRealHome ? .idle : .needsAccess
    }

    /// True when a scan starts by itself now. It never starts while access is missing, while a scan runs,
    /// after a failure (the user clicks Rescan then), or before launch and session restore end.
    public static func shouldStartAutomatically(allowed: Bool, viewing: Bool, shownFor: TimeInterval,
                                                state: SuggestionState, lastScan: Date?, now: Date) -> Bool {
        guard allowed, viewing, shownFor >= shownDelay else { return false }
        guard state == .idle || state == .done else { return false }
        guard let lastScan else { return true }
        return now.timeIntervalSince(lastScan) > freshFor
    }
}

/// What the page remembers about rows that left the report because the file went away, so Undo can bring them back.
public struct SuggestionLedger: Sendable {
    struct Entry: Sendable {
        /// The suggestion as it was before the first row left it.
        var original: Suggestion
        /// The item ids that left.
        var keys: Set<String>
    }

    var entries: [String: Entry] = [:]

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// The ids of the items in the report that a change in `folders` can reach, and every id in the ledger.
    /// With no folders, the change is not known, so all of them.
    public func itemsToCheck(in report: SuggestionReport, folders: Set<String>?) -> [SuggestionItem] {
        var seen = Set<String>()
        var out: [SuggestionItem] = []
        func take(_ item: SuggestionItem) {
            guard seen.insert(item.id).inserted else { return }
            if let folders, !folders.contains(FilePaths.parentKey(ofItemKey: item.id)) { return }
            out.append(item)
        }
        for s in report.suggestions { for item in s.items { take(item) } }
        for entry in entries.values { for item in entry.original.items where entry.keys.contains(item.id) { take(item) } }
        return out
    }

    /// The report and the ledger after a look at the disk. `exists` holds the answer for each item that was
    /// checked. Items that are gone leave the report and enter the ledger. An entry whose items all exist again
    /// goes back into the report.
    public func reconciled(_ report: SuggestionReport, exists: [String: Bool]) -> (report: SuggestionReport, ledger: SuggestionLedger) {
        var ledger = self
        var gone = Set<String>()
        for s in report.suggestions {
            let lost = Set(s.items.map(\.id).filter { exists[$0] == false })
            guard !lost.isEmpty else { continue }
            gone.formUnion(lost)
            if var entry = ledger.entries[s.id] {
                entry.keys.formUnion(lost)
                ledger.entries[s.id] = entry
            } else {
                ledger.entries[s.id] = Entry(original: s, keys: lost)
            }
        }
        var out = report.removing(keys: gone)
        var back: [Suggestion] = []
        for (id, var entry) in ledger.entries {
            entry.keys = entry.keys.filter { exists[$0] != true }
            if entry.keys.isEmpty {
                ledger.entries[id] = nil
                back.append(entry.original)
            } else {
                ledger.entries[id] = entry
            }
        }
        out = out.restoring(back)
        return (out, ledger)
    }

    /// A new scan replaces the report, so the old ledger means nothing.
    public mutating func reset() { entries = [:] }
}

extension SuggestionReport {
    /// The report with its Trash row replaced by a new measure (nil: the Trash is empty or cannot be read).
    public func replacingTrash(with trash: Suggestion?) -> SuggestionReport {
        var out = self
        let old = suggestions.filter { $0.kind == .trash }.reduce(Int64(0)) { $0 + $1.bytes }
        out.suggestions = Self.sorted(suggestions.filter { $0.kind != .trash } + (trash.map { [$0] } ?? []))
        out.totalBytes = totalBytes - old + (trash?.bytes ?? 0)
        return out
    }
}

extension SuggestionReport {
    /// The report without the rows the user ignores: a row with an ignored path (or inside an ignored folder),
    /// and a whole duplicate group with an ignored hash. The ignored paths of a group's copies leave the group.
    public func excluding(_ ignores: SuggestionIgnores.Snapshot) -> SuggestionReport {
        var keys = Set<String>()
        for s in suggestions {
            if case .sameContent(_, let sha, _) = s.reason, ignores.coversHash(sha) {
                keys.formUnion(s.items.map(\.id))
            } else {
                keys.formUnion(s.items.map(\.id).filter(ignores.covers))
            }
        }
        return removing(keys: keys)
    }
}
