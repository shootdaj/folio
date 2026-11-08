import Foundation
@testable import FolioCore

/// A counter that any thread may bump.
final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var number = 0

    var value: Int { lock.withLock { number } }

    func increment() { lock.withLock { number += 1 } }
}

/// A list that any thread may add to.
final class LockedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []

    var values: [String] { lock.withLock { list } }

    func add(_ value: String) { lock.withLock { list.append(value) } }

    func count(of value: String) -> Int { lock.withLock { list.filter { $0 == value }.count } }
}

/// The real disk, with the few values that a temp folder cannot make faked: dataless, mount point, device,
/// locked, denied folders and Spotlight dates. Files and sizes are real.
struct PatchedFS: ScanFileSystem {
    var live = LiveScanFileSystem()
    /// Edits the entry at this path (the folder's path plus the name) after the real listing.
    var patch: [String: @Sendable (inout ScanEntry) -> Void] = [:]
    /// Spotlight's last-used date by path.
    var lastUsedDates: [String: Date] = [:]
    /// Folders whose listing throws `.denied`.
    var denied: Set<String> = []
    /// How many times Spotlight was asked.
    let lookups = LockedCounter()
    /// The path of every folder that was listed.
    let listed = LockedLog()

    func list(_ dir: URL) throws(ScanReadError) -> [ScanEntry] {
        listed.add(dir.path)
        if denied.contains(dir.path) { throw .denied }
        var entries = try live.list(dir)
        for i in entries.indices {
            if let edit = patch[dir.appendingPathComponent(entries[i].name).path] { edit(&entries[i]) }
        }
        return entries
    }

    func lastUsed(_ url: URL) -> Date? {
        lookups.increment()
        return lastUsedDates[url.path]
    }

    func linkTarget(_ url: URL, alias: Bool) -> LinkTarget { live.linkTarget(url, alias: alias) }
    func mayShareBlocks(_ url: URL) -> Bool { live.mayShareBlocks(url) }
    func stamp(_ url: URL) -> ItemStamp? { live.stamp(url) }
}
