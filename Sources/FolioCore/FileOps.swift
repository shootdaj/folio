import Darwin
import Foundation

/// The quick file operations (rename, trash, delete, new folder, new file) and undo and redo of
/// every recorded operation. Synchronous: the app calls them off the main thread.
public enum FileOps {
    // MARK: Rename

    /// Renames in place. Refuses names a Mac can't hold and names already taken; a case-only change
    /// ("notes.txt" to "Notes.txt") works on case-insensitive volumes too.
    @discardableResult
    public static func rename(_ url: URL, to newName: String) throws -> URL {
        if let problem = FileNaming.problem(with: newName) { throw FileOpError.invalidName(problem) }
        let target = url.deletingLastPathComponent().appendingPathComponent(newName)
        try move(url, to: target)
        return target
    }

    /// Batch rename: "Base (1).ext", "Base (2).ext", ... in the order given. Returns the pairs done, in
    /// order; stops at the first failure (pairs done so far are still renamed, and returned in the error).
    public static func batchRename(_ urls: [URL], base: String) throws -> [Pair] {
        if let problem = FileNaming.problem(with: base) { throw FileOpError.invalidName(problem) }
        guard let parent = urls.first?.deletingLastPathComponent() else { return [] }
        let batch = Set(urls.map { $0.lastPathComponent.lowercased() })
        let names = FileNaming.batchNames(base: base, items: urls.map { ($0.lastPathComponent, FileJob.kind($0) == .folder) }) {
            !batch.contains($0.lowercased()) && FileJob.kind(parent.appendingPathComponent($0)) != .missing
        }
        var done: [Pair] = []
        for (url, name) in zip(urls, names) {
            let target = url.deletingLastPathComponent().appendingPathComponent(name)
            do { try move(url, to: target) } catch { throw BatchRenameError(done: done, underlying: error) }
            done.append(Pair(from: url, to: target))
        }
        return done
    }

    public struct BatchRenameError: Error {
        public let done: [Pair]
        public let underlying: Error
    }

    // MARK: Delete

    /// Moves each item to the Trash. Items trashed before a failure stay trashed and are in the error.
    public static func trash(_ urls: [URL], using trasher: any Trasher) throws -> [TrashedItem] {
        var out: [TrashedItem] = []
        for url in urls {
            do {
                out.append(TrashedItem(original: url, inTrash: try trasher.trash(url)))
            } catch {
                throw TrashError(done: out, underlying: error)
            }
        }
        return out
    }

    public struct TrashError: Error {
        public let done: [TrashedItem]
        public let underlying: Error
    }

    /// Shift+Delete, after the app has asked: gone for good, no Trash, no undo.
    public static func deletePermanently(_ urls: [URL]) throws {
        for url in urls { try FileManager.default.removeItem(at: url) }
    }

    // MARK: New

    /// Ctrl+Shift+N: "New folder" (or the next free number) in `folder`.
    public static func newFolder(in folder: URL) throws -> URL {
        let name = FileNaming.newFolderName { FileJob.kind(folder.appendingPathComponent($0)) != .missing }
        let url = folder.appendingPathComponent(name, isDirectory: true)
        if mkdir(url.path, 0o755) != 0 { throw FileOpError.posix(errno, url) }
        return url
    }

    /// New > Text document: an empty "New Text Document.txt".
    public static func newTextDocument(in folder: URL) throws -> URL {
        let name = FileNaming.newTextDocumentName { FileJob.kind(folder.appendingPathComponent($0)) != .missing }
        let url = folder.appendingPathComponent(name)
        try createEmptyFile(url)
        return url
    }

    // MARK: Undo and redo

    /// Reverses a recorded operation. Returns the items now back in place (the app selects them).
    @discardableResult
    public static func undo(_ record: OperationRecord, trash trasher: any Trasher) throws -> [URL] {
        switch record {
        case .copy(let copied, let replaced):
            for pair in copied.reversed() where FileJob.kind(pair.to) != .missing {
                _ = try trasher.trash(pair.to)
            }
            try restore(replaced)
            return replaced.map(\.original)
        case .move(let moved, let created, _, let replaced):
            for pair in moved.reversed() {
                try ensureParent(of: pair.from)
                try move(pair.to, to: pair.from, allowCopy: true)
            }
            for folder in created.reversed() { rmdir(folder.path) }
            try restore(replaced)
            return topLevel(moved.map(\.from))
        case .rename(let pairs):
            for pair in pairs.reversed() { try move(pair.to, to: pair.from) }
            return pairs.map(\.from)
        case .trash(let items):
            try restore(items)
            return items.map(\.original)
        case .newFolder(let url), .newFile(let url):
            if FileJob.kind(url) != .missing { _ = try trasher.trash(url) }
            return []
        case .links(let items):
            for item in items.reversed() where FileJob.kind(item.url) != .missing { _ = try trasher.trash(item.url) }
            return []
        }
    }

    /// Does an undone operation again. Returns its new record (Trash places change each time).
    public static func redo(_ record: OperationRecord, trash trasher: any Trasher) throws -> (record: OperationRecord, items: [URL]) {
        switch record {
        case .copy(let copied, let replaced):
            let again = try trash(replaced.map(\.original), using: trasher)
            for pair in copied { try FileManager.default.copyItem(at: pair.from, to: pair.to) }
            return (.copy(copied: copied, replaced: again), topLevel(copied.map(\.to)))
        case .move(let moved, let created, let removed, let replaced):
            let again = try trash(replaced.map(\.original), using: trasher)
            for pair in moved {
                try ensureParent(of: pair.to)
                try move(pair.from, to: pair.to, allowCopy: true)
            }
            for folder in removed.sorted(by: { $0.path.count > $1.path.count }) { rmdir(folder.path) }
            return (.move(moved: moved, createdFolders: created, removedFolders: removed, replaced: again),
                    topLevel(moved.map(\.to)))
        case .rename(let pairs):
            for pair in pairs { try move(pair.from, to: pair.to) }
            return (record, pairs.map(\.to))
        case .trash(let items):
            let again = try trash(items.map(\.original), using: trasher)
            return (.trash(again), [])
        case .newFolder(let url):
            if mkdir(url.path, 0o755) != 0 { throw FileOpError.posix(errno, url) }
            return (record, [url])
        case .newFile(let url):
            try createEmptyFile(url)
            return (record, [url])
        case .links(let items):
            for item in items { try Aliases.write(item.kind, to: item.target, at: item.url) }
            return (record, items.map(\.url))
        }
    }

    // MARK: Helpers

    /// Puts Trash items back where they were, making missing parent folders (Explorer's Restore).
    private static func restore(_ items: [TrashedItem]) throws {
        for item in items.reversed() {
            try ensureParent(of: item.original)
            try move(item.inTrash, to: item.original, allowCopy: true)
        }
    }

    /// Renames without ever replacing: a taken name is an error unless it is the same file (a case change).
    static func move(_ src: URL, to dst: URL, allowCopy: Bool = false) throws {
        if src.path == dst.path { return }
        guard FileJob.kind(src) != .missing else { throw FileOpError.missing(src.lastPathComponent) }
        if FileJob.kind(dst) != .missing {
            guard sameFile(src, dst) else { throw FileOpError.exists(dst.lastPathComponent) }
            if Darwin.rename(src.path, dst.path) != 0 { throw FileOpError.posix(errno, src) }
            return
        }
        if renamex_np(src.path, dst.path, UInt32(RENAME_EXCL)) == 0 { return }
        let code = errno
        guard code == EXDEV, allowCopy else { throw FileOpError.posix(code, src) }
        try FileManager.default.moveItem(at: src, to: dst)
    }

    private static func sameFile(_ a: URL, _ b: URL) -> Bool {
        var sa = stat(), sb = stat()
        guard lstat(a.path, &sa) == 0, lstat(b.path, &sb) == 0 else { return false }
        return sa.st_dev == sb.st_dev && sa.st_ino == sb.st_ino
    }

    private static func ensureParent(of url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private static func createEmptyFile(_ url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard fd >= 0 else { throw FileOpError.posix(errno, url) }
        close(fd)
    }

    /// The items with no other item of the list above them (a merge's files fold into their folder).
    private static func topLevel(_ urls: [URL]) -> [URL] {
        let paths = Set(urls.map(\.path))
        return urls.filter { url in
            var parent = url.deletingLastPathComponent()
            while parent.path.count > 1 {
                if paths.contains(parent.path) { return false }
                parent = parent.deletingLastPathComponent()
            }
            return true
        }
    }
}
