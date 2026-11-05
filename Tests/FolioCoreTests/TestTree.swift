import Foundation
@testable import FolioCore

/// A throwaway tree under /private/tmp/folio-tests/unit-<id>/ (docs/plan/RULES.md, rule 1), with its
/// own stand-in Trash. `close()` moves the whole tree to the Trash; nothing is ever deleted outright.
final class TestTree: @unchecked Sendable {
    let root: URL
    let trash: FolderTrash

    init() throws {
        root = URL(fileURLWithPath: "/private/tmp/folio-tests/unit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        trash = FolderTrash(folder: root.appendingPathComponent(".trash", isDirectory: true))
        // Every test copies or moves into "dest".
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dest"), withIntermediateDirectories: true)
    }

    func close() {
        try? FileManager.default.trashItem(at: root, resultingItemURL: nil)
    }

    func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    @discardableResult
    func folder(_ path: String) throws -> URL {
        let u = url(path)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// A file of `bytes` bytes filled with `fill`, optionally dated.
    @discardableResult
    func file(_ path: String, bytes: Int = 16, fill: UInt8 = 0x41, modified: Date? = nil) throws -> URL {
        let u = url(path)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: bytes).write(to: u)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: u.path) }
        return u
    }

    /// Visible and hidden names in a folder, sorted.
    func names(_ path: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url(path).path)) ?? []).sorted()
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: url(path).path) }

    func data(_ path: String) -> Data? { try? Data(contentsOf: url(path)) }

    func options(_ edit: (inout JobOptions) -> Void = { _ in }) -> JobOptions {
        var o = JobOptions()
        o.trash = trash
        o.problemPolicy = .skip
        edit(&o)
        return o
    }
}

/// Polls until `condition` holds or `timeout` passes.
func waitUntil(_ timeout: Double = 5, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
