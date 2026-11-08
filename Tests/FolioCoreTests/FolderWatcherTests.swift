import Foundation
import Testing
@testable import FolioCore

/// Auto-refresh: a folder watched with kqueue (and FSEvents for changes to the files in it), changes
/// coalesced over 200 ms so a burst of writes means one or two reloads, not fifty.
@Suite(.serialized) struct FolderWatcherTests {
    final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [Set<String>] = []
        func add(_ s: Set<String>) { lock.withLock { calls.append(s) } }
        var n: Int { lock.withLock { calls.count } }
        var all: Set<String> { lock.withLock { calls.reduce(into: Set<String>()) { $0.formUnion($1) } } }
    }

    @Test func fiftyNewFilesMeanAFewReloadsNotFifty() async throws {
        let t = try TestTree()
        defer { t.close() }
        let work = try t.folder("work")
        let count = Count()
        let watcher = FolderWatcher(latency: 0.2, queue: DispatchQueue(label: "test.watch")) { count.add($0) }
        watcher.watch([work.path])
        try await Task.sleep(for: .milliseconds(150))
        for i in 0..<50 { try Data([UInt8(i)]).write(to: work.appendingPathComponent("f\(i).txt")) }
        #expect(await waitUntil(8) { count.n >= 1 })
        try await Task.sleep(for: .milliseconds(700))
        #expect(count.n >= 1 && count.n <= 3, "\(count.n) reloads for 50 files")
        #expect(count.all == [FilePaths.folderKey(work)])
        watcher.stop()
    }

    @Test func aChangeToAFileInTheFolderIsSeenToo() async throws {
        let t = try TestTree()
        defer { t.close() }
        let work = try t.folder("work")
        let f = try t.file("work/notes.txt", bytes: 3)
        let count = Count()
        let watcher = FolderWatcher(latency: 0.2, queue: DispatchQueue(label: "test.watch2")) { count.add($0) }
        watcher.watch([work.path])
        try await Task.sleep(for: .milliseconds(300))
        let h = try FileHandle(forWritingTo: f)
        h.seekToEndOfFile()
        h.write(Data("more".utf8))
        try h.close()
        #expect(await waitUntil(10) { count.n >= 1 }, "writing into a file the folder lists")
        watcher.stop()
    }

    @Test func stoppedOrMovedOnWatchersStayQuiet() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.folder("a"), b = try t.folder("b")
        let count = Count()
        let watcher = FolderWatcher(latency: 0.1, queue: DispatchQueue(label: "test.watch3")) { count.add($0) }
        watcher.watch([a.path])
        watcher.watch([b.path])
        try await Task.sleep(for: .milliseconds(600))
        let start = count.n
        try Data().write(to: a.appendingPathComponent("x"))
        try await Task.sleep(for: .milliseconds(500))
        #expect(count.n == start, "only b is watched now")
        try Data().write(to: b.appendingPathComponent("y"))
        #expect(await waitUntil(8) { count.n > start })
        try await Task.sleep(for: .milliseconds(500))
        watcher.stop()
        let stopped = count.n
        try Data().write(to: b.appendingPathComponent("z"))
        try await Task.sleep(for: .milliseconds(500))
        #expect(count.n == stopped, "nothing after stop")
    }

    @Test func theTreeWatcherReportsFoldersChangedAnywhereUnderItsRoots() async throws {
        let t = try TestTree()
        defer { t.close() }
        let deep = try t.folder("r/one/two")
        let count = Count()
        let watcher = TreeWatcher(latency: 0.2, queue: DispatchQueue(label: "test.tree")) { count.add($0) }
        watcher.watch(roots: [t.url("r").path])
        try await Task.sleep(for: .milliseconds(300))
        try FileManager.default.createDirectory(at: deep.appendingPathComponent("three"), withIntermediateDirectories: true)
        #expect(await waitUntil(10) { count.all.contains(FilePaths.folderKey(deep)) })
        watcher.stop()
    }
}
