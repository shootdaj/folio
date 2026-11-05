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

    public init(url: URL, name: String, isFolder: Bool, modified: Date?, size: Int64?, kind: String, isCloudOnly: Bool = false) {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.modified = modified
        self.size = size
        self.kind = kind
        self.isCloudOnly = isCloudOnly
    }
}
