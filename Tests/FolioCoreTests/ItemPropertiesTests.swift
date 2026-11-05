import AVFoundation
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FolioCore

/// The Properties window's model on temp files: General (size, size on disk, dates, counts, Locked and
/// Hidden), Permissions (owner, group, mode, read-only), Details (extended attributes, quarantine,
/// tags, image size, media length), Open with, and multi-selection totals.
@Suite(.serialized) struct ItemPropertiesTests {
    @Test func generalFactsOfAFile() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/notes.txt", bytes: 10_000)
        let info = ItemInfo.read(f)
        #expect(info.name == "notes.txt")
        #expect(FilePaths.folderKey(URL(fileURLWithPath: info.location)) == FilePaths.folderKey(t.url("work")))
        #expect(!info.kind.isEmpty)
        #expect(!info.isFolder)
        #expect(info.size == 10_000)
        let onDisk = try #require(info.sizeOnDisk)
        #expect(onDisk >= 10_000 && onDisk % 512 == 0)
        #expect(info.created != nil && info.modified != nil)
        #expect(!info.isLocked && !info.isHidden && !info.isQuarantined)
        #expect(info.owner == NSUserName())
        #expect(!info.group.isEmpty)
        #expect(info.link == nil)
        #expect(ItemInfo.read(t.url("work")).isFolder)
        #expect(ItemInfo.read(t.url("work")).kind == "Folder")
    }

    @Test func sizeOnDiskIsTheAllocatedSpaceNotTheLength() throws {
        let t = try TestTree()
        defer { t.close() }
        let sparse = t.url("work/sparse.bin")
        try FileManager.default.createDirectory(at: sparse.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sparse.path, contents: nil)
        let h = try FileHandle(forWritingTo: sparse)
        try h.truncate(atOffset: 50_000_000)
        try h.close()
        let info = ItemInfo.read(sparse)
        #expect(info.size == 50_000_000)
        #expect((info.sizeOnDisk ?? .max) < 1_000_000)
    }

    @Test func aFolderCountsItsFilesAndFoldersAndTheCountTicksUp() throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("work/Docs/a.txt", bytes: 100)
        try t.file("work/Docs/b.txt", bytes: 200)
        try t.file("work/Docs/sub/c.txt", bytes: 300)
        try t.folder("work/Docs/empty")
        var ticks: [FolderTally] = []
        let tally = FolderCounter.count([t.url("work/Docs")], includeRoots: false, every: 1, report: { ticks.append($0) })
        #expect(tally.files == 3 && tally.folders == 2 && tally.bytes == 600)
        #expect(tally.allocated >= 600)
        #expect(ticks.count >= 3)
        #expect(zip(ticks, ticks.dropFirst()).allSatisfy { $0.files + $0.folders <= $1.files + $1.folders })
        // A selection counts its own items too.
        let both = FolderCounter.count([t.url("work/Docs"), t.url("work/Docs/a.txt")], includeRoots: true)
        #expect(both.folders == 3 && both.files == 4)
    }

    @Test func countingStopsWhenCancelled() throws {
        let t = try TestTree()
        defer { t.close() }
        for i in 0..<50 { try t.file("work/many/f\(i).txt") }
        var seen = 0
        let tally = FolderCounter.count([t.url("work/many")], includeRoots: false, every: 1,
                                        isCancelled: { seen >= 5 }) { _ in seen += 1 }
        #expect(tally.files < 50)
    }

    @Test func aLockedFileCannotBeDeletedUntilItIsUnlocked() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/keep.txt")
        try ItemFlags.setLocked(true, f)
        #expect(ItemInfo.read(f).isLocked)
        #expect(throws: (any Error).self) { try FileManager.default.removeItem(at: f) }
        try ItemFlags.setLocked(false, f)
        #expect(!ItemInfo.read(f).isLocked)
        try FileManager.default.removeItem(at: f)
        #expect(!t.exists("work/keep.txt"))
    }

    @Test func aHiddenFileLeavesTheListAndComesBack() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/secret.txt")
        try t.file("work/plain.txt")
        try ItemFlags.setHidden(true, f)
        #expect(ItemInfo.read(f).isHidden)
        #expect(try FolderListing.list(t.url("work")).map(\.name) == ["plain.txt"])
        try ItemFlags.setHidden(false, f)
        #expect(try FolderListing.list(t.url("work")).map(\.name).sorted() == ["plain.txt", "secret.txt"])
    }

    @Test func permissionsReadAsTicksAndWriteBack() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/run.sh")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.path)
        let p = ItemInfo.read(f).permissions
        #expect(p.symbolic == "rw-r--r--" && p.octal == "644")
        #expect(p.allows(.owner, .write) && p.allows(.group, .read) && !p.allows(.others, .execute))
        try ItemFlags.setPermissions(p.setting(.owner, .execute, true).setting(.others, .read, false), f)
        let after = ItemInfo.read(f).permissions
        #expect(after.octal == "740")
        #expect(FileManager.default.isExecutableFile(atPath: f.path))
    }

    @Test func readOnlyStopsWritingAndClearingItAllowsItAgain() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/doc.txt")
        try ItemFlags.setPermissions(ItemInfo.read(f).permissions.readOnly(true), f)
        #expect(ItemInfo.read(f).permissions.isReadOnly)
        #expect(throws: (any Error).self) { _ = try FileHandle(forWritingTo: f) }
        try ItemFlags.setPermissions(ItemInfo.read(f).permissions.readOnly(false), f)
        #expect(!ItemInfo.read(f).permissions.isReadOnly)
        let h = try FileHandle(forWritingTo: f)
        try h.close()
    }

    @Test func extendedAttributesAreListedAndUnblockClearsTheQuarantine() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/download.zip")
        let value = Array("0081;5f0a0000;Safari;".utf8)
        #expect(setxattr(f.path, "com.apple.quarantine", value, value.count, 0, XATTR_NOFOLLOW) == 0)
        #expect(setxattr(f.path, "com.example.note", "hello", 5, 0, XATTR_NOFOLLOW) == 0)
        let attrs = ExtendedAttributes.list(f)
        #expect(attrs.contains(XAttr(name: "com.example.note", size: 5)))
        #expect(attrs.contains { $0.name == "com.apple.quarantine" })
        #expect(ItemInfo.read(f).isQuarantined)
        try ItemFlags.unblock(f)
        #expect(!ItemInfo.read(f).isQuarantined)
        #expect(!ExtendedAttributes.list(f).contains { $0.name == "com.apple.quarantine" })
        #expect(ExtendedAttributes.list(f).contains { $0.name == "com.example.note" })
    }

    @Test func tagsAreReadAndWritten() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/tagged.txt")
        try ItemFlags.setTags(["Work", "Red"], f)
        #expect(ItemInfo.read(f).tags.sorted() == ["Red", "Work"])
        try ItemFlags.setTags([], f)
        #expect(ItemInfo.read(f).tags.isEmpty)
    }

    @Test func multiSelectionAddsUpAndShowsMixedFlags() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt", bytes: 1000)
        let b = try t.file("work/b.txt", bytes: 2000)
        let docs = try t.folder("work/Docs")
        try t.file("work/Docs/c.txt", bytes: 500)
        try ItemFlags.setHidden(true, b)
        let infos = [a, b, docs].map(ItemInfo.read)
        #expect(Tri.of(infos.map(\.isHidden)) == .mixed)
        #expect(Tri.of(infos.map(\.isLocked)) == .off)
        #expect(Tri.of([true, true]) == .on)
        let tally = FolderCounter.count([a, b, docs], includeRoots: true)
        #expect(tally.files == 3 && tally.folders == 1 && tally.bytes == 3500)
        #expect(SelectionText.contains(tally) == "3 files, 1 folder")
        #expect(SelectionText.contains(FolderTally(files: 1, folders: 0, bytes: 0, allocated: 0)) == "1 file, 0 folders")
    }

    @Test func imagesReportTheirPixelSize() throws {
        let t = try TestTree()
        defer { t.close() }
        let png = t.url("work/shot.png")
        try FileManager.default.createDirectory(at: png.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ctx = try #require(CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        let dest = try #require(CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        #expect(MediaInfo.pixelSize(png) == PixelSize(width: 40, height: 30))
        #expect(MediaInfo.pixelSize(try t.file("work/not-an-image.txt")) == nil)
    }

    @Test func mediaReportsItsLength() async throws {
        let t = try TestTree()
        defer { t.close() }
        let wav = t.url("work/tone.wav")
        try FileManager.default.createDirectory(at: wav.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.wavData(seconds: 1.5).write(to: wav)
        let seconds = try #require(await MediaInfo.duration(wav))
        #expect(abs(seconds - 1.5) < 0.05)
        #expect(MediaInfo.durationText(1.5) == "0:01")
        #expect(MediaInfo.durationText(65) == "1:05")
        #expect(MediaInfo.durationText(3723) == "1:02:03")
        #expect(await MediaInfo.duration(try t.file("work/plain.txt")) == nil)
    }

    @Test func openWithListsTheAppsForTheTypeWithTheDefaultFirst() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/readme.txt")
        let apps = OpenWith.apps(for: f)
        #expect(apps.contains { $0.name == "TextEdit" })
        let first = try #require(OpenWith.defaultApp(for: f))
        #expect(apps.first == first)
        #expect(Set(apps.map(\.url.path)).count == apps.count)
    }

    @Test func anAliasNamesWhatItPointsAt() throws {
        let t = try TestTree()
        defer { t.close() }
        let target = try t.file("work/target.txt")
        let alias = try Aliases.make(.alias, to: target, in: try t.folder("elsewhere"))
        let info = ItemInfo.read(alias)
        #expect(info.link == .alias)
        #expect(info.linkTarget.map(FilePaths.itemKey) == FilePaths.itemKey(target))
    }

    /// A 16-bit mono 8 kHz WAV of silence.
    static func wavData(seconds: Double) -> Data {
        let rate: UInt32 = 8000
        let samples = UInt32(Double(rate) * seconds)
        let dataBytes = samples * 2
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        d.append(Data(count: Int(dataBytes)))
        return d
    }
}
