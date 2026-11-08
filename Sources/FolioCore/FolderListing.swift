import Foundation
import UniformTypeIdentifiers

/// Reads one folder into `FileEntry` values. Pure Foundation; call it off the main thread.
public enum FolderListing {
    /// `.localizedTypeDescriptionKey` costs ~170 µs per file (8.5 s for 50,000), so it is not
    /// prefetched. The kind depends only on the content type, so it is read once per type instead.
    public static let resourceKeys: [URLResourceKey] = [
        .nameKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
        .contentModificationDateKey, .fileSizeKey, .contentTypeKey, .isHiddenKey, .isAliasFileKey,
    ]

    /// `includeHidden` is View > Hidden items: dot files and items with the hidden flag too.
    /// `cloud` (a folder in iCloud Drive or ~/Library/CloudStorage) also reads which files are online only.
    /// `hideProtected` is Folder Options' Hide protected operating system files (.DS_Store and the like).
    private static let resourceKeySet = Set(resourceKeys)

    ///
    /// The folder is read with `getattrlistbulk` (BulkListing); a folder that cannot be read that way is
    /// read through URL resource values, as before.
    public static func list(_ folder: URL, includeHidden: Bool = false, cloud: Bool = false, hideProtected: Bool = false) throws -> [FileEntry] {
        var kinds = KindCache.shared.snapshot()
        let known = kinds.count
        let entries = try BulkListing.entries(folder, includeHidden: includeHidden, hideProtected: hideProtected, kinds: &kinds)
            ?? listByURL(folder, includeHidden: includeHidden, hideProtected: hideProtected, kinds: &kinds)
        if kinds.count != known { KindCache.shared.merge(kinds) }
        guard cloud else { return entries }
        return entries.map { e in
            let status = (try? e.url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
            guard let status, status != .current, status != .downloaded else { return e }
            return FileEntry(url: e.url, name: e.name, isFolder: e.isFolder, modified: e.modified, size: e.size, kind: e.kind,
                             isCloudOnly: true, isHidden: e.isHidden, isLink: e.isLink)
        }
    }

    /// The folder through `contentsOfDirectory` and URL resource values: the fallback, and what the tests
    /// hold the bulk read to.
    static func listByURL(_ folder: URL, includeHidden: Bool, hideProtected: Bool, kinds: inout [String: String]) throws -> [FileEntry] {
        var urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: resourceKeys, options: includeHidden ? [] : [.skipsHiddenFiles])
        if hideProtected { urls.removeAll { ProtectedFiles.isProtected(name: $0.lastPathComponent) } }
        return urls.map { entry(for: $0, kinds: &kinds) }
    }

    /// A name's extension as Foundation splits it ("" for ".zshrc" and "Makefile").
    static func pathExtension(_ name: String) -> String { (name as NSString).pathExtension }

    /// What a window shows: the listing in display order. `Folio --selftest` uses the same call.
    public static func list(_ folder: URL, sortedBy spec: SortSpec, includeHidden: Bool = false, cloud: Bool = false) throws -> [FileEntry] {
        SortEngine.sort(try list(folder, includeHidden: includeHidden, cloud: cloud), by: spec)
    }

    static func entry(for url: URL, kinds: inout [String: String]) -> FileEntry {
        let values = try? url.resourceValues(forKeys: resourceKeySet)
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
            kind: kind(of: url, key: values?.contentType?.identifier, cache: &kinds),
            isHidden: values?.isHidden ?? false,
            isLink: values?.isSymbolicLink == true || values?.isAliasFile == true)
    }

    /// The kind of `url`, read once per `key` (a content type, or what BulkListing knows decides it).
    static func kind(of url: URL, key: String?, cache: inout [String: String]) -> String {
        if let key, let known = cache[key] { return known }
        let kind = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription ?? ""
        if let key { cache[key] = kind }
        return kind
    }
}

/// Each content type's kind ("PNG image"), kept while Folio runs: reading one costs ~170 µs, and every
/// folder has the same few types. Any thread.
final class KindCache: @unchecked Sendable {
    static let shared = KindCache()
    private let lock = NSLock()
    private var kinds: [String: String] = [:]

    func snapshot() -> [String: String] { lock.withLock { kinds } }

    func merge(_ more: [String: String]) {
        lock.withLock {
            // A language change would need a relaunch anyway; the size stays bounded all the same.
            if kinds.count > 4096 { kinds.removeAll() }
            kinds.merge(more) { old, _ in old }
        }
    }
}
