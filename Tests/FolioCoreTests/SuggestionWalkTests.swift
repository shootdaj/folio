import Darwin
import Foundation
import Testing
@testable import FolioCore

/// A fake home in a temp folder, with files dated by age. Nothing here reads the real home.
private struct FakeHome {
    let t: TestTree
    let home: URL
    let now = Date()

    init() throws {
        t = try TestTree()
        home = try t.folder("Home")
    }

    func close() { t.close() }

    func url(_ path: String) -> URL { home.appendingPathComponent(path) }

    @discardableResult
    func folder(_ path: String) throws -> URL { try t.folder("Home/" + path) }

    /// A file of `kb` thousand bytes. All its dates are `days` days old unless one is given.
    @discardableResult
    func file(_ path: String, kb: Int = 200, fill: UInt8 = 0x41, days: Double = 400, added: Double? = nil,
              accessed: Double? = nil, modified: Double? = nil) throws -> URL {
        let u = try t.file("Home/" + path, bytes: kb * 1000, fill: fill)
        age(u, days: days, added: added, accessed: accessed, modified: modified)
        return u
    }

    func age(_ u: URL, days: Double, added: Double? = nil, accessed: Double? = nil, modified: Double? = nil) {
        func date(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }
        let a = date(accessed ?? days), m = date(modified ?? days)
        var times = [timeval(tv_sec: Int(a.timeIntervalSince1970), tv_usec: 0), timeval(tv_sec: Int(m.timeIntervalSince1970), tv_usec: 0)]
        #expect(utimes(u.path, &times) == 0)
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_ADDEDTIME)
        var stamp = timespec(tv_sec: Int(date(added ?? days).timeIntervalSince1970), tv_nsec: 0)
        #expect(setattrlist(u.path, &request, &stamp, MemoryLayout<timespec>.size, 0) == 0)
    }

    /// Dates every folder under home, the deepest first, so a new child does not move a parent's date.
    func ageFolders(days: Double) {
        var folders: [URL] = []
        if let walker = FileManager.default.enumerator(at: home, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let u as URL in walker where (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                folders.append(u)
            }
        }
        for u in folders.sorted(by: { $0.path.count > $1.path.count }) { age(u, days: days) }
        age(home, days: days)
    }

    func config(_ edit: (inout SuggestionConfig) -> Void = { _ in }) -> SuggestionConfig {
        var c = SuggestionConfig(home: home, now: now)
        c.largeFileMin = 100_000
        c.duplicateMin = 100_000
        c.cacheMin = 100_000
        c.buildFolderMin = 100_000
        edit(&c)
        return c
    }

    func scan(fs: any ScanFileSystem = LiveScanFileSystem(), ignores: SuggestionIgnores.Snapshot = .init(),
              _ edit: (inout SuggestionConfig) -> Void = { _ in }) -> WalkResult {
        SuggestionWalk(config: config(edit), fs: fs, ignores: ignores, isCancelled: { false }).run()
    }

    /// The paths of the first item of each suggestion of a kind, below home, sorted.
    func rels(_ r: WalkResult, _ kind: SuggestionKind) -> [String] {
        r.suggestions.filter { $0.kind == kind }.compactMap { $0.items.first?.url.path }
            .map { String($0.dropFirst(home.path.count + 1)) }.sorted()
    }
}

@Suite struct SuggestionWalkSkipTests {
    @Test func libraryIsSkippedExceptKnownCaches() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Library/Foo/big.bin")
        try h.file("Library/Caches/org.x/blob.bin")
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .largeUnused).isEmpty)
        #expect(h.rels(r, .appCaches) == ["Library/Caches/org.x"])
        #expect(r.skips.count(.library) == 1)
    }

    @Test func packagesAreNotEnteredButCountAsContent() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Parent/X.app/Contents/big.bin")
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .largeUnused).isEmpty)
        #expect(h.rels(r, .emptyFolders).isEmpty)
        #expect(r.skips.count(.package) == 1)
    }

    @Test func symlinkedFoldersAreNotFollowed() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("real/big.bin")
        try FileManager.default.createSymbolicLink(atPath: h.url("link").path, withDestinationPath: h.url("real").path)
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .largeUnused) == ["real/big.bin"])
        #expect(r.skips.count(.symlink) == 1)
    }

    @Test func dotFoldersAreSkippedButBuildDotFoldersMatch() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file(".hidden/big.bin")
        try h.file("proj/Package.swift", kb: 1, days: 60)
        try h.file("proj/.build/x.bin")
        h.ageFolders(days: 60)
        let r = h.scan()
        #expect(h.rels(r, .largeUnused).isEmpty)
        #expect(h.rels(r, .buildFolders) == ["proj/.build"])
        #expect(r.skips.count(.dotFolder) == 1)
    }

    @Test func gitFoldersAreNeverEntered() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("proj/.git/objects/big.bin")
        try h.file("proj/readme.txt", kb: 1, days: 60)
        h.ageFolders(days: 60)
        let fs = PatchedFS()
        let r = h.scan(fs: fs)
        #expect(h.rels(r, .largeUnused).isEmpty)
        #expect(r.skips.count(.gitFolder) == 1)
        #expect(fs.listed.values.allSatisfy { !$0.contains("/.git") })
    }

    @Test func cloudOnlyFilesAreSkippedAndDatalessFoldersNeverListed() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("cloud.bin")
        try h.file("Cloud/inside.bin")
        h.ageFolders(days: 30)
        var fs = PatchedFS()
        fs.patch[h.url("cloud.bin").path] = { $0.isDataless = true }
        fs.patch[h.url("Cloud").path] = { $0.isDataless = true }
        let r = h.scan(fs: fs)
        #expect(h.rels(r, .largeUnused).isEmpty)
        #expect(fs.listed.count(of: h.url("Cloud").path) == 0)
        #expect(r.skips.count(.cloudOnly) == 2)
    }

    @Test func mountPointsAndOtherDevicesStopTheWalk() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Mnt/big.bin")
        try h.file("Other/big.bin")
        h.ageFolders(days: 30)
        var fs = PatchedFS()
        fs.patch[h.url("Mnt").path] = { $0.isMountPoint = true }
        fs.patch[h.url("Other").path] = { $0.device = 999_999 }
        let r = h.scan(fs: fs)
        #expect(h.rels(r, .largeUnused).isEmpty)
        #expect(fs.listed.count(of: h.url("Mnt").path) == 0 && fs.listed.count(of: h.url("Other").path) == 0)
        #expect(r.skips.count(.mountPoint) == 1 && r.skips.count(.otherDevice) == 1)
    }

    @Test func deniedFolderIsCountedAndNotCalledEmpty() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.folder("Outer/Locked")
        h.ageFolders(days: 30)
        var fs = PatchedFS()
        fs.denied = [h.url("Outer/Locked").path]
        let r = h.scan(fs: fs)
        #expect(r.skips.count(.denied) == 1)
        #expect(r.skips.samples[.denied] == [h.url("Outer/Locked").path])
        #expect(h.rels(r, .emptyFolders).isEmpty)
    }

    @Test func managedMediaFilesAreNotLooseSuggestions() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Pictures/big.bin")
        try h.file("Music/Music/song.bin")
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(r.suggestions.isEmpty)
        #expect(r.duplicateCandidates.isEmpty)
        #expect(r.skips.count(.managedMedia) == 2)
    }

    @Test func lockedFilesAreNeverOffered() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("locked.bin")
        try h.file("free.bin", fill: 0x42)
        h.ageFolders(days: 30)
        var fs = PatchedFS()
        fs.patch[h.url("locked.bin").path] = { $0.isLocked = true }
        let r = h.scan(fs: fs)
        #expect(h.rels(r, .largeUnused) == ["free.bin"])
        #expect(r.skips.count(.locked) == 1)
        #expect(r.duplicateCandidates.map { $0.item.url.lastPathComponent } == ["free.bin"])
    }

    @Test func ignoredPathsAndTheirSubtreesAreNeverSuggested() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("ign.bin", fill: 0x41)
        try h.file("IgnDir/big.bin", fill: 0x42)
        try h.file("IgnDirX/big.bin", fill: 0x43)
        h.ageFolders(days: 30)
        let ignores = SuggestionIgnores.Snapshot(paths: [FilePaths.itemKey(h.url("ign.bin")), FilePaths.itemKey(h.url("IgnDir"))])
        let r = h.scan(ignores: ignores)
        #expect(h.rels(r, .largeUnused) == ["IgnDirX/big.bin"])
        #expect(r.skips.count(.ignored) == 2)
    }

    @Test func depthCapSkipsDeeperFoldersAndLogsThem() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("a/b/c/big.bin")
        h.ageFolders(days: 30)
        let r = h.scan { $0.maxDepth = 2 }
        #expect(h.rels(r, .largeUnused).isEmpty)
        #expect(r.skips.count(.depthCap) == 1)
        #expect(h.rels(r, .emptyFolders).isEmpty)
    }

    @Test func theEntryCapStopsTheWalkAndMarksItPartial() throws {
        let h = try FakeHome()
        defer { h.close() }
        for i in 0..<20 { try h.file("f\(i).bin", kb: 1) }
        let r = h.scan { $0.maxEntries = 5 }
        #expect(r.isPartial)
        #expect(r.skips.count(.entryCap) >= 1)
        #expect(r.stats.entries <= 6)
    }

    @Test func theTimeBudgetUsesTheInjectedClock() throws {
        let h = try FakeHome()
        defer { h.close() }
        for i in 0..<20 { try h.file("f\(i).bin", kb: 1) }
        let ticks = LockedCounter()
        let r = h.scan {
            $0.timeBudget = 10
            $0.elapsed = { ticks.increment(); return Double(ticks.value) }
        }
        #expect(r.isPartial)
        #expect(r.skips.count(.timeBudget) >= 1)
    }

    @Test func theThreadPolicyIsSetDuringTheScanAndPutBack() {
        // A plain thread, as the scan runs on: the kernel refuses the disk policy on a thread with a quality of service.
        final class Seen: @unchecked Sendable { var values: [Int32] = [] }
        let seen = Seen()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            let type = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
            let before = [getiopolicy_np(type, IOPOL_SCOPE_THREAD), getiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD)]
            var during: [Int32] = []
            IOPolicy.scoped {
                during = [getiopolicy_np(type, IOPOL_SCOPE_THREAD), getiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD)]
            }
            let after = [getiopolicy_np(type, IOPOL_SCOPE_THREAD), getiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD)]
            seen.values = before + during + after
            done.signal()
        }
        thread.start()
        done.wait()
        #expect(seen.values.count == 6)
        guard seen.values.count == 6 else { return }
        #expect(seen.values[2] == IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        #expect(seen.values[3] == IOPOL_UTILITY)
        #expect(Array(seen.values[4...]) == Array(seen.values[..<2]))
    }
}

@Suite struct SuggestionWalkRuleTests {
    @Test func bigFileNotUsedForSixMonthsIsSuggested() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Documents/old.bin", fill: 0x41)
        try h.file("Documents/newish.bin", fill: 0x42, days: 100)
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .largeUnused) == ["Documents/old.bin"])
        let s = try #require(r.suggestions.first { $0.kind == .largeUnused })
        guard case .notUsedSince = s.reason else { Issue.record("reason \(s.reason)"); return }
        #expect(s.bytes >= 200_000 && s.items[0].bytes == s.bytes)
        #expect(s.id == s.items[0].id)
    }

    @Test func spotlightRecentLastUsedKeepsAnOldFileOff() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("used.bin", fill: 0x41)
        try h.file("unused.bin", fill: 0x42)
        h.ageFolders(days: 30)
        var fs = PatchedFS()
        fs.lastUsedDates[h.url("used.bin").path] = h.now.addingTimeInterval(-2 * 86_400)
        fs.lastUsedDates[h.url("unused.bin").path] = h.now.addingTimeInterval(-300 * 86_400)
        let r = h.scan(fs: fs)
        #expect(h.rels(r, .largeUnused) == ["unused.bin"])
        let s = try #require(r.suggestions.first)
        guard case .notUsedSince(_, let source) = s.reason else { Issue.record("reason"); return }
        #expect(source == .lastUsed)
    }

    @Test func anyRecentAccessModifiedOrAddedDateKeepsAFileOff() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("accessed.bin", fill: 0x41, accessed: 3)
        try h.file("modified.bin", fill: 0x42, modified: 3)
        try h.file("added.bin", fill: 0x43, added: 3)
        try h.file("ok.bin", fill: 0x44)
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .largeUnused) == ["ok.bin"])
    }

    @Test func spotlightIsAskedOnlyForPrefilteredCandidates() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("a.bin", fill: 0x41)
        try h.file("b.bin", fill: 0x42)
        try h.file("recent.bin", fill: 0x43, days: 5)
        try h.file("small.bin", kb: 1, fill: 0x44)
        try h.file("hard.bin", fill: 0x45)
        try FileManager.default.linkItem(at: h.url("hard.bin"), to: h.url("hard2.bin"))
        h.ageFolders(days: 30)
        let fs = PatchedFS()
        let r = h.scan(fs: fs)
        #expect(fs.lookups.value == 2)
        #expect(r.stats.spotlightLookups == 2)
    }

    @Test func theLookupBudgetStopsSpotlightAndCountsTheRest() throws {
        let h = try FakeHome()
        defer { h.close() }
        for i in 0..<4 { try h.file("f\(i).bin", fill: UInt8(0x41 + i)) }
        h.ageFolders(days: 30)
        let r = h.scan { $0.maxSpotlightLookups = 2 }
        #expect(h.rels(r, .largeUnused).count == 2)
        #expect(r.skips.count(.spotlightCap) == 2)
    }

    @Test func thresholdUsesAllocatedSizeNotLogical() throws {
        let h = try FakeHome()
        defer { h.close() }
        let u = h.url("sparse.bin")
        FileManager.default.createFile(atPath: u.path, contents: nil)
        let handle = try FileHandle(forWritingTo: u)
        try handle.truncate(atOffset: 2_000_000_000)
        try handle.close()
        h.age(u, days: 400)
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .largeUnused).isEmpty)
    }

    @Test func hardlinkedBigFilesAreNotLargeUnused() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("one.bin")
        try FileManager.default.linkItem(at: h.url("one.bin"), to: h.url("two.bin"))
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .largeUnused).isEmpty)
        #expect(r.skips.count(.hardlink) == 2)
    }

    @Test func hashedByFolioDoesNotCountAsUse() throws {
        let h = try FakeHome()
        defer { h.close() }
        let u = try h.file("read.bin", accessed: 1)
        h.ageFolders(days: 30)
        #expect(h.rels(h.scan(), .largeUnused).isEmpty)
        // Folio read the file a moment before the access date: its own read, not a use.
        let id = try #require(LiveScanFileSystem().stamp(u)?.fileID)
        let r = h.scan { $0.hashedAt = [id: h.now.addingTimeInterval(-2 * 86_400)] }
        #expect(h.rels(r, .largeUnused) == ["read.bin"])
        // A later use still counts.
        let later = h.scan { $0.hashedAt = [id: h.now.addingTimeInterval(1 * 86_400)] }
        #expect(h.rels(later, .largeUnused).isEmpty)
    }

    @Test func oldDownloadsUseDateAddedNotModified() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Downloads/fresh-added.txt", kb: 1, days: 400, added: 1)
        try h.file("Downloads/old-added.txt", kb: 1, days: 1, added: 100, accessed: 1)
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .oldDownloads) == ["Downloads/old-added.txt"])
        let s = try #require(r.suggestions.first)
        guard case .inDownloadsSince = s.reason else { Issue.record("reason"); return }
    }

    @Test func oldDownloadFolderIsOneItemWithItsSize() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Downloads/Proj/a.bin", fill: 0x41, days: 100)
        try h.file("Downloads/Proj/sub/b.bin", fill: 0x42, days: 100)
        h.ageFolders(days: 100)
        let r = h.scan()
        #expect(r.suggestions.count == 1)
        let s = try #require(r.suggestions.first)
        #expect(s.kind == .oldDownloads && s.items[0].isFolder)
        #expect(s.bytes >= 400_000)
        #expect(r.duplicateCandidates.isEmpty)
    }

    @Test func installersAnywhereAfterTwoWeeksZipOnlyInDownloadsAndDesktop() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Apps/a.dmg", kb: 1, days: 20)
        try h.file("Apps/b.dmg", kb: 1, days: 5)
        try h.file("Apps/c.zip", kb: 1, days: 20)
        try h.file("Downloads/d.zip", kb: 1, days: 20)
        try h.file("Desktop/e.zip", kb: 1, days: 20)
        try h.file("Desktop/f.pkg", kb: 1, days: 20)
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .installers) == ["Apps/a.dmg", "Desktop/e.zip", "Desktop/f.pkg", "Downloads/d.zip"])
        guard case .installer(let ext, _) = try #require(r.suggestions.first { $0.items[0].url.lastPathComponent == "a.dmg" }).reason
        else { Issue.record("reason"); return }
        #expect(ext == "dmg")
    }

    @Test func trashSizeCountsHardlinksOnce() throws {
        let h = try FakeHome()
        defer { h.close() }
        let a = try h.file(".Trash/a.bin")
        try FileManager.default.linkItem(at: a, to: h.url(".Trash/b.bin"))
        var st = stat()
        #expect(stat(a.path, &st) == 0)
        let r = h.scan()
        let s = try #require(r.suggestions.first { $0.kind == .trash })
        #expect(s.bytes == Int64(st.st_blocks) * 512)
        #expect(s.reason == .trash(items: 2))
        #expect(!r.needsFullDiskAccess)
    }

    @Test func trashDeniedSetsNeedsFullDiskAccess() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file(".Trash/a.bin")
        var fs = PatchedFS()
        fs.denied = [h.url(".Trash").path]
        let r = h.scan(fs: fs)
        #expect(r.needsFullDiskAccess)
        #expect(r.denied == [h.url(".Trash")])
        #expect(!r.suggestions.contains { $0.kind == .trash })
    }

    @Test func appCachesAreOnePerAppAboveTheFloorAndSkipApple() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Library/Caches/org.big/blob.bin", fill: 0x41)
        try h.file("Library/Caches/org.small/blob.bin", kb: 1)
        try h.file("Library/Caches/com.apple.thing/blob.bin", fill: 0x42)
        try h.file("Library/Caches/com.anshul.folio/blob.bin", fill: 0x43)
        try h.file(".cache/tool/blob.bin", fill: 0x44)
        try h.file(".npm/_cacache/blob.bin", fill: 0x45)
        let r = h.scan()
        #expect(h.rels(r, .appCaches) == [".cache", ".npm/_cacache", "Library/Caches/org.big"])
        let big = try #require(r.suggestions.first { $0.items[0].url.lastPathComponent == "org.big" })
        #expect(big.reason == .cache(appID: "org.big"))
    }

    @Test func derivedDataIsOneCard() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Library/Developer/Xcode/DerivedData/App-abc/Build/x.bin", fill: 0x41)
        try h.file("Library/Developer/Xcode/DerivedData/Other-def/y.bin", fill: 0x42)
        let r = h.scan()
        #expect(h.rels(r, .derivedData) == ["Library/Developer/Xcode/DerivedData"])
        #expect(r.suggestions.first { $0.kind == .derivedData }?.reason == .derivedData(projects: 2))
    }

    @Test func nodeModulesOfAnIdleProjectIsSuggestedOutermostOnly() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("proj/package.json", kb: 1, days: 60)
        try h.file("proj/node_modules/a/node_modules/x.bin", fill: 0x41, days: 1)
        try h.file("proj/node_modules/y.bin", fill: 0x42, days: 1)
        h.ageFolders(days: 60)
        let r = h.scan()
        #expect(h.rels(r, .buildFolders) == ["proj/node_modules"])
        #expect(r.suggestions.count == 1)
        guard case .buildFolder(let name, _) = r.suggestions[0].reason else { Issue.record("reason"); return }
        #expect(name == "node_modules")
        #expect(r.suggestions[0].items[0].isFolder && r.suggestions[0].bytes >= 400_000)
    }

    @Test func nodeModulesOfAnActiveProjectIsSkippedNotWalked() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("proj/package.json", kb: 1, days: 1)
        try h.file("proj/node_modules/x.bin", days: 400)
        h.ageFolders(days: 60)
        let fs = PatchedFS()
        let r = h.scan(fs: fs)
        #expect(r.suggestions.isEmpty)
        #expect(r.skips.count(.activeBuildFolder) == 1)
        #expect(fs.listed.count(of: h.url("proj/node_modules").path) == 0)
    }

    @Test func buildFoldersNeedTheirProjectMarker() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("b/target/x.bin", fill: 0x41)
        try h.file("c/Cargo.toml", kb: 1, days: 60)
        try h.file("c/target/y.bin", fill: 0x42)
        h.ageFolders(days: 60)
        let r = h.scan()
        #expect(h.rels(r, .buildFolders) == ["c/target"])
        #expect(h.rels(r, .largeUnused) == ["b/target/x.bin"])
    }

    @Test func emptyFoldersReportTopmostOnly() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Stuff/keep.txt", kb: 1)
        try h.folder("Stuff/e1/e2")
        try h.folder("Other/e3")
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .emptyFolders) == ["Other", "Stuff/e1"])
        #expect(r.suggestions.first { $0.kind == .emptyFolders }?.reason == .emptyFolder)
    }

    @Test func dsStoreAndLocalizedDoNotMakeAFolderNonEmpty() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Empty/.DS_Store", kb: 1)
        try h.file("Empty/.localized", kb: 1)
        try h.file("Full/.DS_Store", kb: 1)
        try h.file("Full/note.txt", kb: 1)
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .emptyFolders) == ["Empty"])
    }

    @Test func standardHiddenRecentAndCustomIconFoldersAreNeverEmptySuggestions() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.folder("Desktop")
        try h.folder(".hid")
        try h.folder("Recent")
        try h.folder("Custom")
        try h.folder("Documents/inner")
        h.ageFolders(days: 30)
        h.age(h.url("Recent"), days: 1)
        var fs = PatchedFS()
        fs.patch[h.url("Custom").path] = { $0.finderFlags |= 0x0400 }
        let r = h.scan(fs: fs)
        // Documents is a standard folder, but a folder inside it is not.
        #expect(h.rels(r, .emptyFolders) == ["Documents/inner"])
    }

    @Test func brokenSymlinkIsSuggestedWorkingOneIsNot() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("real.txt", kb: 1)
        try FileManager.default.createSymbolicLink(atPath: h.url("good").path, withDestinationPath: "real.txt")
        try FileManager.default.createSymbolicLink(atPath: h.url("bad").path, withDestinationPath: "nothing.txt")
        let r = h.scan()
        #expect(h.rels(r, .brokenLinks) == ["bad"])
        guard case .brokenLink(let target) = try #require(r.suggestions.first { $0.kind == .brokenLinks }).reason
        else { Issue.record("reason"); return }
        #expect(target == h.url("nothing.txt").path)
    }

    @Test func brokenAliasIsSuggested() throws {
        let h = try FakeHome()
        defer { h.close() }
        let target = try h.file("target.txt", kb: 1, days: 1)
        let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(bookmark, to: h.url("target alias"))
        #expect(h.rels(h.scan(), .brokenLinks).isEmpty)
        try FileManager.default.removeItem(at: target)
        #expect(h.rels(h.scan(), .brokenLinks) == ["target alias"])
    }

    @Test func linkToAnUnmountedVolumeIsNotBroken() throws {
        let h = try FakeHome()
        defer { h.close() }
        try FileManager.default.createSymbolicLink(
            atPath: h.url("far").path, withDestinationPath: "/Volumes/folio-no-such-volume-\(UUID().uuidString)/x")
        #expect(h.rels(h.scan(), .brokenLinks).isEmpty)
    }

    @Test func eachFileAppearsInOneSuggestionOnly() throws {
        let h = try FakeHome()
        defer { h.close() }
        // Old, large, an installer and in Downloads: it qualifies for three kinds.
        try h.file("Downloads/big.dmg", fill: 0x41, days: 100)
        try h.file("Downloads/big.bin", fill: 0x42, days: 400)
        try h.file("Docs/big.bin", fill: 0x43, days: 400)
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .installers) == ["Downloads/big.dmg"])
        #expect(h.rels(r, .oldDownloads) == ["Downloads/big.bin"])
        #expect(h.rels(r, .largeUnused) == ["Docs/big.bin"])
        let ids = r.suggestions.flatMap { $0.items.map(\.id) }
        #expect(ids.count == Set(ids).count)
    }

    @Test func nothingInsideAClaimedFolderIsSuggestedAgain() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("Downloads/Proj/Setup.dmg", days: 100)
        try h.file("Downloads/Proj/sub/big.bin", fill: 0x42, days: 400)
        try h.file("Downloads/Proj/node_modules/z.bin", fill: 0x43, days: 400)
        h.ageFolders(days: 100)
        let r = h.scan()
        #expect(r.suggestions.count == 1 && r.suggestions[0].kind == .oldDownloads)
    }

    @Test func duplicateCandidatesAreTheFilesAtOrAboveTheFloor() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("a/one.bin", fill: 0x41, days: 5)
        try h.file("b/one.bin", fill: 0x41, days: 5)
        try h.file("b/tiny.bin", kb: 1)
        try h.file("Library/Foo/skipped.bin")
        try h.file("c/hard.bin", fill: 0x42, days: 5)
        try FileManager.default.linkItem(at: h.url("c/hard.bin"), to: h.url("c/hard2.bin"))
        h.ageFolders(days: 30)
        let r = h.scan()
        let names = r.duplicateCandidates.map { $0.item.url.path.dropFirst(h.home.path.count + 1) }.sorted()
        #expect(names == ["a/one.bin", "b/one.bin", "c/hard.bin", "c/hard2.bin"])
        #expect(r.duplicateCandidates.first { $0.item.url.lastPathComponent == "hard.bin" }?.linkCount == 2)
    }

    @Test func excludingDropsTheItemsADuplicateGroupClaims() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file("a.bin", fill: 0x41)
        try h.file("b.bin", fill: 0x42)
        h.ageFolders(days: 30)
        let r = h.scan()
        #expect(h.rels(r, .largeUnused) == ["a.bin", "b.bin"])
        let kept = r.excluding(keys: [FilePaths.itemKey(h.url("a.bin"))])
        #expect(h.rels(kept, .largeUnused) == ["b.bin"])
        #expect(kept.duplicateCandidates.count == 2)
    }

    @Test func fixedPlaceCardsAreSentBeforeTheWalk() throws {
        let h = try FakeHome()
        defer { h.close() }
        try h.file(".Trash/a.bin")
        try h.file("old.bin", fill: 0x42)
        h.ageFolders(days: 30)
        var early: [SuggestionKind] = []
        let r = SuggestionWalk(config: h.config(), fs: LiveScanFileSystem(), ignores: .init(), isCancelled: { false })
            .run(onFixedPlaces: { early = $0.map(\.kind) })
        #expect(early == [.trash])
        #expect(r.suggestions.map(\.kind).contains(.largeUnused))
    }
}
