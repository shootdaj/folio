import Foundation

/// One line of a card on the Suggestions page.
public struct SuggestionRow: Sendable, Hashable, Identifiable {
    public enum Role: Sendable, Hashable {
        /// A suggestion of one item.
        case single
        /// The head of a duplicate group. It has no item and no buttons.
        case groupHead
        /// One copy in a duplicate group.
        case member
    }

    /// The item id, or the suggestion id for a group head.
    public let id: String
    public let role: Role
    public let suggestion: Suggestion
    public let item: SuggestionItem?
    public let name: String
    /// The parent folder, with the home folder as "~".
    public let place: String
    /// Why the item is suggested. A group head says how many copies and how much is freed. A kept copy says "Keep".
    public let detail: String
    /// The size shown on the right, or nil when the kind has no size (empty folders, broken links).
    public let size: Int64?
    public let isKept: Bool

    /// A row the keyboard can focus. A group head cannot be focused.
    public var isFocusable: Bool { role != .groupHead }
}

/// One card of the page, cut to the rows that show.
public struct SuggestionSection: Sendable, Hashable, Identifiable {
    public let kind: SuggestionKind
    public let title: String
    /// All suggestions of the kind, also those not shown.
    public let count: Int
    public let bytes: Int64
    public let rows: [SuggestionRow]
    /// The suggestions that have rows. A card button acts on these and on no others.
    public let shown: [Suggestion]
    /// Suggestions left out of the rows.
    public let hidden: Int
    public let isExpanded: Bool

    public var id: SuggestionKind { kind }
    /// True when the card has more suggestions than the page can show at all.
    public var isCapped: Bool { isExpanded && hidden > 0 }
}

/// What the Suggestions page shows and says. The window gives the data, the view only draws it.
public enum SuggestionPage {
    /// Rows a card shows before "Show all".
    public static let collapsedLimit = 5
    /// Rows a card shows at most.
    public static let expandedLimit = 500

    // MARK: Sections

    /// The sections for these cards, in the order given. `expanded` kinds show up to `expandedLimit` suggestions.
    public static func sections(cards: [SuggestionCard], home: URL, expanded: Set<SuggestionKind> = [],
                                locale: Locale = Locale(identifier: "en_US"), timeZone: TimeZone = .current) -> [SuggestionSection] {
        cards.map { card in
            let open = expanded.contains(card.kind)
            let shown = Array(card.suggestions.prefix(open ? expandedLimit : collapsedLimit))
            var rows: [SuggestionRow] = []
            for s in shown { rows += self.rows(for: s, home: home, locale: locale, timeZone: timeZone) }
            return SuggestionSection(kind: card.kind, title: SuggestionText.title(card.kind), count: card.suggestions.count,
                                     bytes: card.bytes, rows: rows, shown: shown, hidden: card.suggestions.count - shown.count,
                                     isExpanded: open)
        }
    }

    /// The cards to show while a scan runs. A finished report wins over the early cards of the fixed places.
    public static func cards(report: SuggestionReport?, early: [Suggestion]) -> [SuggestionCard] {
        if let report { return report.cards() }
        guard !early.isEmpty else { return [] }
        return SuggestionReport(suggestions: early, home: URL(fileURLWithPath: "/")).cards()
    }

    public static func rows(for s: Suggestion, home: URL, locale: Locale = Locale(identifier: "en_US"),
                            timeZone: TimeZone = .current) -> [SuggestionRow] {
        let sized = s.kind != .emptyFolders && s.kind != .brokenLinks
        guard s.kind == .duplicates, s.items.count > 1 else {
            guard let item = s.items.first else { return [] }
            return [SuggestionRow(id: item.id, role: .single, suggestion: s, item: item, name: item.url.lastPathComponent,
                                  place: place(of: item.url, home: home),
                                  detail: SuggestionText.reason(s, locale: locale, timeZone: timeZone),
                                  size: sized ? item.bytes : nil, isKept: false)]
        }
        let kept = s.items.first { $0.url == s.keep } ?? s.items[0]
        var out = [SuggestionRow(id: s.id, role: .groupHead, suggestion: s, item: nil, name: kept.url.lastPathComponent, place: "",
                                 detail: groupText(s), size: nil, isKept: false)]
        for item in s.items {
            let isKept = item.url == kept.url
            out.append(SuggestionRow(id: item.id, role: .member, suggestion: s, item: item, name: item.url.lastPathComponent,
                                     place: place(of: item.url, home: home), detail: isKept ? "Keep" : "", size: item.bytes,
                                     isKept: isKept))
        }
        return out
    }

    /// "2 copies, 24 MB to free", or "2 copies, may share space" when a clone saves nothing.
    public static func groupText(_ s: Suggestion) -> String {
        let copies = s.items.count
        if case .sameContent(_, _, true) = s.reason { return "\(copies) copies, may share space" }
        return "\(copies) copies, \(size(s.bytes)) to free"
    }

    // MARK: Text

    /// The folder of an item, with the home folder as "~". A folder named like the home folder plus letters is not shortened.
    public static func place(of url: URL, home: URL) -> String {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let base = home.standardizedFileURL.path
        if parent == base { return "~" }
        if parent.hasPrefix(base + "/") { return "~" + parent.dropFirst(base.count) }
        return parent
    }

    /// A size as Finder writes it, with kilobytes below 1 MB.
    public static func size(_ bytes: Int64) -> String {
        bytes < 1_000_000 ? ByteText.kilobytes(bytes) : ByteText.storage(bytes)
    }

    /// "4.2 GB", or "3 items" for a card that has no size.
    public static func sectionTotal(_ section: SuggestionSection) -> String {
        if section.bytes == 0 { return section.count == 1 ? "1 item" : "\(ByteText.grouped(section.count)) items" }
        return size(section.bytes)
    }

    /// "Move 5 to Trash".
    public static func moveTitle(count: Int) -> String { "Move \(ByteText.grouped(count)) to Trash" }

    /// "Show all 37".
    public static func showAllTitle(count: Int) -> String { "Show all \(ByteText.grouped(count))" }

    /// "Show 4 ignored items again".
    public static func ignoredTitle(count: Int) -> String {
        count == 1 ? "Show 1 ignored item again" : "Show \(ByteText.grouped(count)) ignored items again"
    }

    /// "500 of 1,234 shown".
    public static func cappedText(section: SuggestionSection) -> String {
        "\(ByteText.grouped(section.shown.count)) of \(ByteText.grouped(section.count)) shown"
    }

    /// "4.2 GB can be freed", or the count when nothing has a size.
    public static func freeableText(_ report: SuggestionReport) -> String {
        if report.reclaimableBytes > 0 { return size(report.reclaimableBytes) + " can be freed" }
        return countText(report.suggestions.count)
    }

    /// "1 suggestion", "23 suggestions".
    public static func countText(_ n: Int) -> String { n == 1 ? "1 suggestion" : "\(ByteText.grouped(n)) suggestions" }

    /// "Checked just now", "Checked 2 min ago", "Checked 3 h ago", "Checked 2 days ago".
    public static func checkedText(_ date: Date?, now: Date) -> String {
        guard let date else { return "Not checked yet" }
        let s = max(0, now.timeIntervalSince(date))
        if s < 60 { return "Checked just now" }
        if s < 3_600 { return "Checked \(Int(s / 60)) min ago" }
        if s < 86_400 { return "Checked \(Int(s / 3_600)) h ago" }
        let days = Int(s / 86_400)
        return days == 1 ? "Checked 1 day ago" : "Checked \(days) days ago"
    }

    /// The line under the title while a scan runs: "Checking Documents. 48,210 items".
    public static func progressText(_ progress: ScanProgress?) -> String {
        guard let progress else { return "Starting" }
        switch progress.phase {
        case .fixedPlaces: return "Measuring the Trash and the caches"
        case .walking:
            let folder = (progress.current as NSString).lastPathComponent
            let items = ByteText.grouped(progress.entries) + (progress.entries == 1 ? " item" : " items")
            return folder.isEmpty ? "Checking " + items : "Checking \(folder), \(items)"
        case .lastUsed: return "Looking up when files were last used"
        case .hashing: return "Comparing files for duplicates"
        case .done: return "Finishing"
        }
    }

    /// The status bar text for each phase of the page.
    public static func statusText(state: SuggestionState, report: SuggestionReport?, progress: ScanProgress?,
                                  failure: String?) -> String {
        switch state {
        case .idle:
            guard let report else { return "Ready to scan" }
            return doneText(report)
        case .needsAccess: return "Suggestions need Full Disk Access"
        case .scanning:
            guard let progress, progress.phase == .walking else { return progressText(progress) }
            let folder = (progress.current as NSString).lastPathComponent
            let items = ByteText.grouped(progress.entries) + " items checked"
            return folder.isEmpty ? "Scanning: " + items : "Scanning \(folder): " + items
        case .done: return report.map(doneText) ?? "Ready to scan"
        case .failed: return failure ?? "The scan did not finish"
        }
    }

    private static func doneText(_ report: SuggestionReport) -> String {
        guard !report.suggestions.isEmpty else { return "Nothing to clean up" }
        let freed = report.reclaimableBytes > 0 ? ", " + size(report.reclaimableBytes) + " to free" : ""
        return countText(report.suggestions.count) + freed + (report.isPartial ? " (partial scan)" : "")
    }
}
