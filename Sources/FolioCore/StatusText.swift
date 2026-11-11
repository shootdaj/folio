import Foundation

/// What is selected, reduced to what the status bar prints.
public struct SelectionSummary: Sendable, Equatable {
    public let count: Int
    public let firstName: String?
    public let firstIsFolder: Bool
    /// Sum of file sizes in the selection; folders count as nothing.
    public let bytes: Int64
    /// True when at least one selected item has a size (a file).
    public let hasSize: Bool

    /// The items at `rows` of `entries`, read in place (Cmd+A in a big folder copies nothing).
    public init(_ entries: [FileEntry], rows: IndexSet) {
        var count = 0, total: Int64 = 0, any = false
        for range in rows.rangeView {
            let r = range.clamped(to: entries.indices)
            count += r.count
            for i in r {
                if let size = entries[i].size { total += size; any = true }
            }
        }
        self.count = count
        let first = rows.first.flatMap { entries.indices.contains($0) ? entries[$0] : nil }
        firstName = first?.name
        firstIsFolder = first?.isFolder ?? false
        bytes = total
        hasSize = any
    }

    public init(_ selected: [FileEntry]) {
        count = selected.count
        firstName = selected.first?.name
        firstIsFolder = selected.first?.isFolder ?? false
        var total: Int64 = 0
        var any = false
        for item in selected {
            if let size = item.size { total += size; any = true }
        }
        bytes = total
        hasSize = any
    }
}

public enum SortLabel {
    /// "Name, A to Z"; Shift+click keys follow as "then Type, Name".
    public static func label(_ spec: SortSpec) -> String {
        let first = term(spec.key, spec.ascending)
        return spec.then.isEmpty ? first : first + ", then " + spec.then.map(\.key.title).joined(separator: ", ")
    }

    /// Short form: the first key and how many more ("Date modified, newest first +2").
    public static func short(_ spec: SortSpec) -> String {
        term(spec.key, spec.ascending) + (spec.then.isEmpty ? "" : " +\(spec.then.count)")
    }

    /// "Date modified, newest first".
    public static func term(_ key: SortKey, _ ascending: Bool) -> String {
        let way: String = if key.isDate {
            ascending ? "oldest first" : "newest first"
        } else if key == .size {
            ascending ? "smallest first" : "largest first"
        } else if key == .duration || key == .bitRate || key == .frameRate || key == .dimensions {
            ascending ? "lowest first" : "highest first"
        } else {
            ascending ? "A to Z" : "Z to A"
        }
        return key.title + ", " + way
    }

    /// "Sorted by Name, A to Z", as the status bar shows it.
    public static func sentence(_ spec: SortSpec) -> String { "Sorted by " + label(spec) }
}

public enum StatusText {
    /// The status bar after Enter on an address that is not a folder.
    public static let noSuchFolder = "No such folder"

    /// The left of the status bar: "28 items, 1 selected", plus the selected files' size when there is one.
    /// With a header filter on, `total` is the folder's count: "3 items (filtered from 12), 0 selected".
    public static func count(items: Int, selection: SelectionSummary, total: Int? = nil) -> String {
        var text = ByteText.grouped(items) + (items == 1 ? " item" : " items")
        if let total { text += " (filtered from " + ByteText.grouped(total) + ")" }
        text += ", " + ByteText.grouped(selection.count) + " selected"
        if selection.hasSize { text += ", " + ByteText.kilobytes(selection.bytes) }
        return text
    }
}

/// The status bar's readouts (D4's `.status`): the count and the selection on the left; the sort, the
/// volume's free space and the view on the right. The Control room's HUD figures (items, selected,
/// sort) live here now.
public struct StatusReadout: Sendable, Equatable {
    /// "28 items, 1 selected" ("3 items (filtered from 12), 0 selected"); "Searching work" while a search
    /// is still gathering its first results.
    public let count: String
    /// After the count: the one selected item's name (with its size for a file), or the size of several
    /// files; nil when there is nothing to add.
    public let selected: String?
    /// "Sorted by Name, A to Z", or "Sorted by relevance" for search results in relevance order.
    public let sort: String
    /// "Macintosh HD" and "81.0 GB" (drawn "Macintosh HD, 81.0 GB free"); nil when the volume is unknown.
    public let volumeName: String?
    public let volumeFree: String?
    /// The view's name ("Details"), the toggle at the right end.
    public let view: String
    /// A search is gathering: the light pulses in the accent.
    public let busy: Bool

    public var volumeText: String? { volumeName.flatMap { n in volumeFree.map { n + ", " + $0 + " free" } } }

    public static func make(items: Int, total: Int? = nil, selection: SelectionSummary, sort: SortSpec?,
                            volume: VolumeCapacity?, view: String, searchingIn scope: String? = nil) -> StatusReadout {
        let busy = scope != nil
        var count = ByteText.grouped(items) + (items == 1 ? " item" : " items")
        if let total { count += " (filtered from " + ByteText.grouped(total) + ")" }
        if selection.count > 0 { count += ", " + ByteText.grouped(selection.count) + " selected" }
        return StatusReadout(count: busy && items == 0 ? "Searching " + (scope ?? "") : count,
                             selected: selectedDetail(selection),
                             sort: sort.map(SortLabel.sentence) ?? "Sorted by relevance",
                             volumeName: volume?.name, volumeFree: volume.map { ByteText.storage($0.free) },
                             view: view, busy: busy)
    }

    /// The name of one item (and its size when it is a file), or the size of several files.
    static func selectedDetail(_ s: SelectionSummary) -> String? {
        let size = s.hasSize ? ByteText.kilobytes(s.bytes) : nil
        switch s.count {
        case 0: return nil
        case 1: return (s.firstName ?? "") + (size.map { ", " + $0 } ?? "")
        default: return size
        }
    }
}

/// The sidebar's Details card (D4's `.dt`): the selected item's glyph, name and kind with Modified,
/// Size and Where; for several items a stack, "3 items selected", what they are and their size.
public struct DetailsCard: Sendable, Equatable {
    public struct Field: Sendable, Equatable {
        public let key: String
        public let value: String
    }
    public enum Icon: Sendable, Equatable { case item(name: String, isFolder: Bool), stack }

    public let icon: Icon?
    public let title: String
    public let subtitle: String
    public let fields: [Field]
    /// Nothing selected: the card says so instead.
    public var isEmpty: Bool { icon == nil }

    public static let emptyText = "Select an item to see its details here."

    /// The card for the items at `rows` of `entries`: a large selection is counted in place.
    public static func make(_ entries: [FileEntry], rows: IndexSet, timeZone: TimeZone = .current) -> DetailsCard {
        guard rows.count > 1 else { return make(rows.compactMap { entries.indices.contains($0) ? entries[$0] : nil }, timeZone: timeZone) }
        var folders = 0, files = 0
        for range in rows.rangeView {
            for i in range.clamped(to: entries.indices) { if entries[i].isFolder { folders += 1 } else { files += 1 } }
        }
        let what = [folders > 0 ? "\(folders) folder" + (folders == 1 ? "" : "s") : nil,
                    files > 0 ? "\(files) file" + (files == 1 ? "" : "s") : nil].compactMap { $0 }.joined(separator: ", ")
        let summary = SelectionSummary(entries, rows: rows)
        return DetailsCard(icon: .stack, title: ByteText.grouped(folders + files) + " items selected", subtitle: what,
                           fields: summary.bytes > 0 ? [Field(key: "Size", value: ByteText.kilobytes(summary.bytes))] : [])
    }

    public static func make(_ selected: [FileEntry], timeZone: TimeZone = .current) -> DetailsCard {
        guard let first = selected.first else {
            return DetailsCard(icon: nil, title: emptyText, subtitle: "", fields: [])
        }
        if selected.count > 1 {
            let folders = selected.filter(\.isFolder).count, files = selected.count - folders
            let what = [folders > 0 ? "\(folders) folder" + (folders == 1 ? "" : "s") : nil,
                        files > 0 ? "\(files) file" + (files == 1 ? "" : "s") : nil].compactMap { $0 }.joined(separator: ", ")
            let summary = SelectionSummary(selected)
            return DetailsCard(icon: .stack, title: ByteText.grouped(selected.count) + " items selected", subtitle: what,
                               fields: summary.bytes > 0 ? [Field(key: "Size", value: ByteText.kilobytes(summary.bytes))] : [])
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var fields: [Field] = []
        if let date = first.modified { fields.append(Field(key: "Modified", value: formatter.string(from: date))) }
        if let size = first.size, !first.isFolder { fields.append(Field(key: "Size", value: ByteText.kilobytes(size))) }
        fields.append(Field(key: "Where", value: first.url.deletingLastPathComponent().path))
        return DetailsCard(icon: .item(name: first.name, isFolder: first.isFolder), title: first.name, subtitle: first.kind, fields: fields)
    }
}
