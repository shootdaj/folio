import Foundation
import UniformTypeIdentifiers

/// Reads one folder into `FileEntry` values. Pure Foundation; call it off the main thread.
public enum FolderListing {
    /// `.localizedTypeDescriptionKey` costs ~170 µs per file (8.5 s for 50,000), so it is not
    /// prefetched. The kind depends only on the content type, so it is read once per type instead.
    public static let resourceKeys: [URLResourceKey] = [
        .nameKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
        .contentModificationDateKey, .fileSizeKey, .contentTypeKey,
    ]

    public static func list(_ folder: URL) throws -> [FileEntry] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles])
        var kinds: [String: String] = [:]
        return urls.map { entry(for: $0, kinds: &kinds) }
    }

    /// What a window shows: the listing in display order. `Folio --selftest` uses the same call.
    public static func list(_ folder: URL, sortedBy spec: SortSpec) throws -> [FileEntry] {
        SortEngine.sort(try list(folder), by: spec)
    }

    static func entry(for url: URL, kinds: inout [String: String]) -> FileEntry {
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        var isDirectory = values?.isDirectory ?? false
        var isPackage = values?.isPackage ?? false
        // A symlink to a folder behaves like the folder (e.g. "iCloud Drive" in home).
        if values?.isSymbolicLink == true,
           let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) {
            isDirectory = target.isDirectory ?? false
            isPackage = target.isPackage ?? false
        }
        return FileEntry(
            url: url,
            name: values?.name ?? url.lastPathComponent,
            isFolder: isDirectory && !isPackage,
            modified: values?.contentModificationDate,
            size: isDirectory ? nil : values?.fileSize.map(Int64.init),
            kind: kind(of: url, type: values?.contentType?.identifier, cache: &kinds))
    }

    private static func kind(of url: URL, type: String?, cache: inout [String: String]) -> String {
        if let type, let known = cache[type] { return known }
        let kind = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription ?? ""
        if let type { cache[type] = kind }
        return kind
    }
}
