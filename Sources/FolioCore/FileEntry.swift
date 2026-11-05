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

    public init(url: URL, name: String, isFolder: Bool, modified: Date?, size: Int64?, kind: String, isCloudOnly: Bool = false,
                isHidden: Bool = false, isLink: Bool = false) {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.modified = modified
        self.size = size
        self.kind = kind
        self.isCloudOnly = isCloudOnly
        self.isHidden = isHidden
        self.isLink = isLink
    }

    /// The name as listed: without its extension when View > File name extensions is off (folders and
    /// names that are only an extension, like ".zshrc", keep theirs).
    public func displayName(extensions: Bool) -> String {
        guard !extensions, !isFolder else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        return ext.isEmpty || base.isEmpty ? name : base
    }
}
