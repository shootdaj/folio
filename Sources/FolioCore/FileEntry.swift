import Foundation

/// One row of a folder listing. A plain value so it can cross threads.
public struct FileEntry: Sendable, Hashable {
    public let url: URL
    public let name: String
    /// True for folders you navigate into. Packages such as .app bundles are files.
    public let isFolder: Bool
    public let modified: Date?
    /// Size in bytes for files; nil for folders and packages.
    public let size: Int64?
    /// Localized kind, e.g. "Folder" or "PNG image".
    public let kind: String
    /// A cloud file that is not on this Mac yet (the list draws a cloud after its name).
    public let isCloudOnly: Bool
    /// A dot file or an item with the hidden flag (drawn faded when hidden items are shown).
    public let isHidden: Bool
    /// An alias or a symbolic link (its icon gets Explorer's shortcut arrow).
    public let isLink: Bool
    /// Finder flags (custom icon, alias, bundle) and BSD flags (locked, compressed), when the listing
    /// read them with the item (BulkListing); nil means not known, so ask the disk.
    public let finderFlags: UInt16?
    public let bsdFlags: UInt32?

    public init(url: URL, name: String, isFolder: Bool, modified: Date?, size: Int64?, kind: String, isCloudOnly: Bool = false,
                isHidden: Bool = false, isLink: Bool = false, finderFlags: UInt16? = nil, bsdFlags: UInt32? = nil) {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.modified = modified
        self.size = size
        self.kind = kind
        self.isCloudOnly = isCloudOnly
        self.isHidden = isHidden
        self.isLink = isLink
        self.finderFlags = finderFlags
        self.bsdFlags = bsdFlags
    }

    /// Finder's "has custom icon" flag: false when known to be off, nil when the listing did not read it.
    public var mayHaveCustomIcon: Bool { finderFlags.map { $0 & FolderIcon.hasCustomIconFlag != 0 } ?? true }

    /// The name as listed: without its extension when View > File name extensions is off (folders and
    /// names that are only an extension, like ".zshrc", keep theirs).
    public func displayName(extensions: Bool) -> String {
        guard !extensions, !isFolder else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        return ext.isEmpty || base.isEmpty ? name : base
    }
}
