import Foundation

/// Explorer's names for copies, kept copies, new items and batch renames.
public enum FileNaming {
    /// Splits "report.final.txt" into ("report.final", ".txt"). Folders and dot files have no extension.
    public static func split(_ name: String, isFolder: Bool) -> (base: String, ext: String) {
        guard !isFolder else { return (name, "") }
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, name.count > ext.count + 1 else { return (name, "") }
        return (String(name.dropLast(ext.count + 1)), "." + ext)
    }

    /// Paste into the same folder: "report - Copy.txt", then "report - Copy (2).txt".
    public static func copyName(for name: String, isFolder: Bool, exists: (String) -> Bool) -> String {
        let (base, ext) = split(name, isFolder: isFolder)
        let first = base + " - Copy" + ext
        if !exists(first) { return first }
        var n = 2
        while exists(base + " - Copy (\(n))" + ext) { n += 1 }
        return base + " - Copy (\(n))" + ext
    }

    /// Keep both: the incoming item becomes "name (1).ext", or the next number free. A name that already
    /// ends in " (n)" counts on from its base.
    public static func keepBothName(for name: String, isFolder: Bool, exists: (String) -> Bool) -> String {
        let (raw, ext) = split(name, isFolder: isFolder)
        let base = strippingNumber(raw)
        var n = 1
        while exists(base + " (\(n))" + ext) { n += 1 }
        return base + " (\(n))" + ext
    }

    /// Ctrl+Shift+N: "New folder", then "New folder (2)".
    public static func newFolderName(exists: (String) -> Bool) -> String {
        numbered("New folder", ext: "", exists: exists)
    }

    /// New > Text document: "New Text Document.txt", then "New Text Document (2).txt".
    public static func newTextDocumentName(exists: (String) -> Bool) -> String {
        numbered("New Text Document", ext: ".txt", exists: exists)
    }

    /// Batch rename (select several, F2, type one name): "Base (1).ext", "Base (2).ext", ... in view order,
    /// each keeping its own extension and skipping numbers already taken by other items.
    public static func batchNames(base: String, items: [(name: String, isFolder: Bool)],
                                  exists: (String) -> Bool) -> [String] {
        var out: [String] = []
        var used = Set<String>()
        var n = 1
        for item in items {
            let ext = split(item.name, isFolder: item.isFolder).ext
            while true {
                let candidate = base + " (\(n))" + ext
                n += 1
                if !exists(candidate) && !used.contains(candidate.lowercased()) {
                    out.append(candidate)
                    used.insert(candidate.lowercased())
                    break
                }
            }
        }
        return out
    }

    /// F2 selects the base name only, so the extension stays (in UTF-16 units, as NSText counts).
    public static func baseNameRange(_ name: String, isFolder: Bool) -> Range<Int> {
        0..<(split(name, isFolder: isFolder).base as NSString).length
    }

    public enum Problem: Equatable, Sendable {
        case empty, reserved, tooLong
        case forbiddenCharacter(String)

        public var message: String {
            switch self {
            case .empty: "A name can't be empty."
            case .reserved: "That name is reserved."
            case .tooLong: "That name is too long."
            case .forbiddenCharacter(let c): "A file name can't contain \(c)"
            }
        }
    }

    /// Why a typed name can't be used: a Mac rejects "/", and Finder shows ":" as "/", so both are out.
    public static func problem(with name: String) -> Problem? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return .empty }
        if name == "." || name == ".." { return .reserved }
        for c in ["/", ":"] where name.contains(c) { return .forbiddenCharacter(c) }
        if name.utf8.count > 255 { return .tooLong }
        return nil
    }

    /// True when a rename changes a file's extension (not just its case): Explorer asks first.
    public static func changesExtension(from old: String, to new: String, isFolder: Bool) -> Bool {
        guard !isFolder else { return false }
        return split(old, isFolder: false).ext.lowercased() != split(new, isFolder: false).ext.lowercased()
    }

    private static func numbered(_ base: String, ext: String, exists: (String) -> Bool) -> String {
        if !exists(base + ext) { return base + ext }
        var n = 2
        while exists(base + " (\(n))" + ext) { n += 1 }
        return base + " (\(n))" + ext
    }

    private static func strippingNumber(_ base: String) -> String {
        guard base.hasSuffix(")"), let open = base.range(of: " (", options: .backwards) else { return base }
        let digits = base[open.upperBound..<base.index(before: base.endIndex)]
        return !digits.isEmpty && digits.allSatisfy(\.isNumber) ? String(base[..<open.lowerBound]) : base
    }
}
