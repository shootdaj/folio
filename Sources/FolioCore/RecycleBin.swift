import Foundation

/// Where each item Folio put in the Trash came from (the Trash itself does not say in a way apps can
/// read), keyed by its path in the Trash. The Recycle Bin view's Original location and Restore use it.
public struct TrashOrigins {
    public static let key = "trashOrigins"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private var map: [String: String] { (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:] }

    public func record(_ items: [TrashedItem]) {
        var m = map
        for item in items { m[item.inTrash.path] = item.original.path }
        defaults.set(m, forKey: Self.key)
    }

    public func original(of trashPath: String) -> String? { map[trashPath] }

    public func forget(_ trashPath: String) {
        var m = map
        m[trashPath] = nil
        defaults.set(m, forKey: Self.key)
    }
}

/// Explorer's Recycle Bin in the Details view: Date modified becomes Date deleted and Type becomes
/// Original location; Restore puts an item back in the folder it came from.
public enum RecycleBin {
    public static let unknownLocation = "Unknown (deleted outside Folio)"

    /// The list's rows for the Trash: `kind` carries the original folder, `modified` the date deleted.
    public static func rows(_ entries: [FileEntry], original: (String) -> String?, deleted: (URL) -> Date?) -> [FileEntry] {
        entries.map { e in
            let from = original(e.url.path).map { ($0 as NSString).deletingLastPathComponent } ?? unknownLocation
            return FileEntry(url: e.url, name: e.name, isFolder: e.isFolder, modified: deleted(e.url), size: e.size,
                             kind: from, isCloudOnly: e.isCloudOnly, finderFlags: e.finderFlags, bsdFlags: e.bsdFlags)
        }
    }

    public static func restoreFolder(original: String?) -> URL? {
        original.map { URL(fileURLWithPath: ($0 as NSString).deletingLastPathComponent, isDirectory: true) }
    }

    /// The signed-in user's Trash (~/.Trash), however the path is spelled.
    public static func isTrash(_ url: URL, home: URL) -> Bool {
        Breadcrumbs.normalized(url.path) == Breadcrumbs.normalized(home.path) + "/.Trash"
    }

    public static func trashFolder(home: URL) -> URL { home.appendingPathComponent(".Trash", isDirectory: true) }
}

/// A cloud folder for the navigation pane.
public struct CloudPlace: Sendable, Equatable {
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// iCloud Drive and the File Provider folders (Dropbox, Google Drive, OneDrive, Box) under
/// ~/Library/CloudStorage.
public enum CloudFolders {
    public static func locations(home: URL) -> [CloudPlace] {
        let fm = FileManager.default
        var out: [CloudPlace] = []
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var dir: ObjCBool = false
        if fm.fileExists(atPath: icloud.path, isDirectory: &dir), dir.boolValue {
            out.append(CloudPlace(name: "iCloud Drive", path: icloud.path))
        }
        let storage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let names = ((try? fm.contentsOfDirectory(atPath: storage.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for name in names {
            let path = storage.appendingPathComponent(name).path
            guard fm.fileExists(atPath: path, isDirectory: &dir), dir.boolValue else { continue }
            out.append(CloudPlace(name: displayName(name), path: path))
        }
        return out
    }

    /// GoogleDrive-a@b.com is "Google Drive (a@b.com)", OneDrive-Personal is "OneDrive - Personal".
    static func displayName(_ folder: String) -> String {
        let parts = folder.split(separator: "-", maxSplits: 1).map(String.init)
        let provider = parts[0] == "GoogleDrive" ? "Google Drive" : parts[0]
        guard parts.count == 2, parts[1] != parts[0] else { return provider }
        return provider == "OneDrive" ? "OneDrive - " + parts[1] : provider + " (" + parts[1] + ")"
    }

    /// Inside iCloud Drive or a CloudStorage folder: the list asks which files are online only.
    public static func isCloud(_ url: URL, home: URL) -> Bool {
        let p = Breadcrumbs.normalized(url.path), h = Breadcrumbs.normalized(home.path)
        return p.hasPrefix(h + "/Library/CloudStorage/") || p.hasPrefix(h + "/Library/Mobile Documents/")
    }
}
