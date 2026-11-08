import Darwin
import Foundation

// MARK: - Access keys (Alt)

/// The command bar's buttons, left to right.
public enum CommandKey: String, CaseIterable, Sendable {
    case new, cut, copy, paste, rename, share, delete, sort, view, more
}

/// Explorer's Alt access keys on the command bar: tap Option and each button shows its letter; the
/// letter then presses it.
public enum AccessKeys {
    public static func letter(for key: CommandKey) -> String {
        switch key {
        case .new: "N"
        case .cut: "X"
        case .copy: "C"
        case .paste: "V"
        case .rename: "R"
        case .share: "S"
        case .delete: "D"
        case .sort: "O"
        case .view: "W"
        case .more: "M"
        }
    }

    public static func command(for typed: String) -> CommandKey? {
        guard typed.count == 1 else { return nil }
        return CommandKey.allCases.first { letter(for: $0).caseInsensitiveCompare(typed) == .orderedSame }
    }
}

/// Option pressed and let go on its own, quickly, with no key in between: Explorer's Alt tap.
public struct OptionTap: Sendable {
    private var downAt: Double?
    public static let longest = 0.8

    public init() {}

    /// Returns true when this change ends a tap.
    public mutating func flagsChanged(option: Bool, others: Bool, at time: Double) -> Bool {
        if others { downAt = nil; return false }
        if option {
            if downAt == nil { downAt = time }
            return false
        }
        defer { downAt = nil }
        guard let start = downAt else { return false }
        return time - start <= Self.longest
    }

    /// Any key while Option is down makes it a shortcut, not a tap.
    public mutating func keyDown() { downAt = nil }
}

// MARK: - Full screen

/// macOS gives F11 to Show Desktop, so Ctrl+Cmd+F is the key; F11 is offered as well when the Mac's
/// function keys send F1 to F12 (System Settings > Keyboard, `com.apple.keyboard.fnState`).
public enum FullScreenKeys {
    public static func offersF11(fnState: Bool?) -> Bool { fnState == true }
}

// MARK: - Restore previous versions: Time Machine's local snapshots

public struct LocalSnapshot: Sendable, Equatable {
    public let name: String
    public let date: Date
}

public enum TimeMachineSnapshots {
    /// `tmutil listlocalsnapshots /`: one com.apple.TimeMachine.<date>.local line per snapshot, newest first here.
    public static func parse(_ output: String) -> [LocalSnapshot] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        var out: [LocalSnapshot] = []
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("com.apple.TimeMachine."), line.hasSuffix(".local") else { continue }
            let stamp = line.dropFirst("com.apple.TimeMachine.".count).dropLast(".local".count)
            if let d = f.date(from: String(stamp)) { out.append(LocalSnapshot(name: line, date: d)) }
        }
        return out.sorted { $0.date > $1.date }
    }

    public static func list(volume: String = "/") -> [LocalSnapshot] {
        parse(ArchiveJob.capture(["/usr/bin/tmutil", "listlocalsnapshots", volume]))
    }

    /// The file inside a snapshot of the Data volume mounted at `mountPoint`.
    public static func pathInSnapshot(_ path: String, mountPoint: String) -> String {
        var p = path
        if p.hasPrefix("/System/Volumes/Data/") { p = String(p.dropFirst("/System/Volumes/Data".count)) }
        return mountPoint + p
    }

    /// mount_apfs's arguments to show a snapshot read-only (it needs an administrator).
    public static func mountArguments(snapshot: String, mountPoint: String) -> [String] {
        ["-o", "nobrowse,rdonly", "-s", snapshot, "/System/Volumes/Data", mountPoint]
    }
}

// MARK: - Customize this folder: columns per kind (Explorer's Optimize this folder for)

/// Optimize this folder for: here it picks the Details columns for that kind of folder, for every
/// folder (there is one view for every folder).
public enum ColumnPreset: String, CaseIterable, Sendable {
    case general, documents, pictures, music, videos

    public var title: String {
        switch self {
        case .general: "General items"
        case .documents: "Documents"
        case .pictures: "Pictures"
        case .music: "Music"
        case .videos: "Videos"
        }
    }

    public var columns: [ColumnID] {
        switch self {
        case .general: ColumnSet.standardColumns
        case .documents: [.name, .modified, .kind, .size, .title, .tags]
        case .pictures: [.name, .dateTaken, .kind, .size, .dimensions, .tags]
        case .music: [.name, .title, .artist, .album, .duration, .bitRate]
        case .videos: [.name, .modified, .kind, .size, .duration, .dimensions, .frameRate]
        }
    }

    public func applied(to set: ColumnSet) -> ColumnSet { ColumnSet(visible: columns, widths: set.widths) }

    /// The preset the columns now match, if any.
    public static func matching(_ set: ColumnSet) -> ColumnPreset? { allCases.first { $0.columns == set.visible } }
}

// MARK: - Drives: hide empty drives, drive letters, Format, Check, sharing

extension VolumeList {
    /// Hide empty drives: a drive with no media (a card reader with no card) reports no capacity.
    public static func arrange(_ volumes: [VolumeCapacity], hideEmpty: Bool) -> (drives: [VolumeCapacity], network: [VolumeCapacity]) {
        let (drives, network) = arrange(volumes)
        return (hideEmpty ? drives.filter { $0.total > 0 } : drives, network)
    }

    /// Show drive letters: a Mac has none, so the mount path stands in, "USB (/Volumes/USB)".
    public static func label(_ v: VolumeCapacity, showPath: Bool) -> String {
        showPath ? v.name + " (" + v.path + ")" : v.name
    }
}

public enum DriveTools {
    public enum Format: String, CaseIterable, Sendable {
        case apfs = "APFS", macExtended = "JHFS+", exfat = "ExFAT", fat32 = "MS-DOS FAT32"
        public var title: String {
            switch self {
            case .apfs: "APFS"
            case .macExtended: "Mac OS Extended (Journaled)"
            case .exfat: "ExFAT"
            case .fat32: "MS-DOS (FAT32)"
            }
        }
        var diskutilName: String { self == .fat32 ? "FAT32" : rawValue }
    }

    /// Format...: `diskutil eraseVolume <format> <name> <volume>` after a confirm.
    public static func formatArguments(volume: String, name: String, format: Format) -> [String] {
        ["eraseVolume", format.diskutilName, cleanName(name), volume]
    }

    /// Check for errors: `diskutil verifyVolume`, the check behind Disk Utility's First Aid.
    public static func verifyArguments(volume: String) -> [String] { ["verifyVolume", volume] }

    /// A volume name diskutil takes: no slashes or colons, trimmed.
    public static func cleanName(_ name: String) -> String {
        name.filter { $0 != "/" && $0 != ":" }.trimmingCharacters(in: .whitespaces)
    }

    /// Give access to > Share on the network: `sharing -a <path> -S <name>` (File Sharing, SMB).
    public static func shareArguments(folder: String, name: String) -> [String] { ["-a", folder, "-S", name] }
    public static func unshareArguments(name: String) -> [String] { ["-r", name] }

    /// `sharing -l`: each shared folder's path and its share name.
    public static func sharedNames(_ output: String) -> [String: String] {
        var out: [String: String] = [:]
        var name: String?
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("name:") { name = line.dropFirst(5).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("path:"), let n = name {
                out[line.dropFirst(5).trimmingCharacters(in: .whitespaces)] = n
                name = nil
            }
        }
        return out
    }
}

// MARK: - Pop-up descriptions (info tips)

/// Explorer's hover tip: type, dimensions, size and date for a file; for a folder its size (with
/// Display file size information in folder tips) and the first folders and files in it.
public enum InfoTip {
    public struct FolderSummary: Sendable, Equatable {
        public var folders: [String] = []
        public var files: [String] = []
        public var bytes: Int64 = 0
    }

    /// One level of the folder, as Explorer's tip reads it (it does not walk the whole tree).
    public static func summarize(folder: URL, limit: Int = 400) -> FolderSummary {
        var s = FolderSummary()
        // One bulk read: names, types and sizes come together (the hover asks on the main thread).
        if let raws = BulkListing.read(folder.path) {
            let shown = raws.lazy.filter { !$0.name.hasPrefix(".") && $0.flags & UInt32(UF_HIDDEN) == 0 }.prefix(limit)
            let order = StandardOrder()
            let sorted = shown.map { ($0, StandardOrder.key($0.name)) }.sorted { order.compare($0.1, $1.1) < 0 }.map(\.0)
            for raw in sorted {
                if raw.type == VDIR.rawValue { s.folders.append(raw.name) } else {
                    s.files.append(raw.name)
                    s.bytes += raw.size ?? 0
                }
            }
            return s
        }
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        for url in urls.prefix(limit).sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if v?.isDirectory == true { s.folders.append(url.lastPathComponent) } else {
                s.files.append(url.lastPathComponent)
                s.bytes += Int64(v?.fileSize ?? 0)
            }
        }
        return s
    }

    public static func text(for entry: FileEntry, metadata: ItemMetadata?, folder: FolderSummary?, sizes: Bool = true,
                            formatter: (Date) -> String) -> String {
        var lines: [String] = []
        if entry.isFolder {
            if let folder {
                if sizes { lines.append("Size: " + size(folder.bytes)) }
                if !folder.folders.isEmpty { lines.append("Folders: " + list(folder.folders)) }
                if !folder.files.isEmpty { lines.append("Files: " + list(folder.files)) }
                if folder.folders.isEmpty && folder.files.isEmpty { lines.append("Empty folder") }
            }
            if let d = entry.modified { lines.insert("Date modified: " + formatter(d), at: 0) }
            return lines.joined(separator: "\n")
        }
        if !entry.kind.isEmpty { lines.append("Type: " + entry.kind) }
        if let w = metadata?.pixelWidth, let h = metadata?.pixelHeight { lines.append("Dimensions: \(w) \u{00D7} \(h)") }
        if let s = entry.size { lines.append("Size: " + size(s)) }
        if let d = entry.modified { lines.append("Date modified: " + formatter(d)) }
        return lines.joined(separator: "\n")
    }

    private static func list(_ names: [String]) -> String {
        names.count > 6 ? names.prefix(6).joined(separator: ", ") + ", ..." : names.joined(separator: ", ")
    }

    /// Explorer's tip sizes: binary units, three significant digits, cut off rather than rounded.
    public static func size(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) bytes" }
        let units = ["KB", "MB", "GB", "TB"]
        var v = Double(bytes) / 1024
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1024; i += 1 }
        let digits = v >= 100 ? 0 : v >= 10 ? 1 : 2
        let p = pow(10, Double(digits))
        let cut = (v * p).rounded(.down) / p
        return String(format: "%.\(digits)f ", cut) + units[i]
    }
}

// MARK: - Cloud files: Always keep on this device, Free up space

public enum CloudFiles {
    /// Downloads an iCloud Drive or provider file (or a folder's files) to keep it here.
    public static func keep(_ url: URL) throws { try FileManager.default.startDownloadingUbiquitousItem(at: url) }

    /// Removes the local copy; the file stays in the cloud and comes back when opened.
    public static func freeUp(_ url: URL) throws { try FileManager.default.evictUbiquitousItem(at: url) }

    public static func isUbiquitous(_ url: URL) -> Bool { FileManager.default.isUbiquitousItem(at: url) }
}

// MARK: - Restore previous versions: saved document versions

public struct SavedVersion: Sendable, Equatable {
    public let date: Date
    public let source: String
    public let url: URL
}

public enum DocumentVersions {
    /// Versions apps saved with NSFileVersion (Versions in TextEdit, Pages, Numbers...).
    public static func list(_ url: URL) -> [SavedVersion] {
        (NSFileVersion.otherVersionsOfItem(at: url) ?? []).compactMap { v in
            guard let d = v.modificationDate else { return nil }
            return SavedVersion(date: d, source: v.localizedNameOfSavingComputer ?? "This Mac", url: v.url)
        }.sorted { $0.date > $1.date }
    }
}
