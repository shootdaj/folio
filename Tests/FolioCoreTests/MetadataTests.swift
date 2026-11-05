import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FolioCore

/// Counts reads; returns a title naming the path so a test can tell whose metadata it got.
private final class CountingReader: @unchecked Sendable {
    let lock = NSLock()
    var paths: [String] = []
    func read(_ url: URL) -> ItemMetadata {
        lock.withLock { paths.append(url.path) }
        var m = ItemMetadata()
        m.title = url.lastPathComponent
        return m
    }
}

private func entry(_ path: String, modified: Date?) -> FileEntry {
    FileEntry(url: URL(fileURLWithPath: path), name: (path as NSString).lastPathComponent, isFolder: false,
              modified: modified, size: 1, kind: "Plain Text")
}

@Suite struct MetadataCacheTests {
    @Test func readsOnceAndServesTheCache() {
        let counter = CountingReader()
        let cache = MetadataCache { counter.read($0) }
        let a = entry("/x/a.txt", modified: Date(timeIntervalSince1970: 100))
        #expect(cache.cached(a) == nil)
        #expect(cache.metadata(a).title == "a.txt")
        #expect(cache.metadata(a).title == "a.txt")
        #expect(cache.cached(a)?.title == "a.txt")
        #expect(cache.reads == 1)
    }

    @Test func aNewModificationDateReadsAgainAndInvalidateDropsIt() {
        let counter = CountingReader()
        let cache = MetadataCache { counter.read($0) }
        let old = entry("/x/a.txt", modified: Date(timeIntervalSince1970: 100))
        let new = entry("/x/a.txt", modified: Date(timeIntervalSince1970: 200))
        _ = cache.metadata(old)
        #expect(cache.cached(new) == nil)
        _ = cache.metadata(new)
        #expect(cache.reads == 2)
        cache.invalidate(new.url)
        #expect(cache.cached(new) == nil)
        _ = cache.metadata(new)
        #expect(cache.reads == 3)
    }

    @Test func fillReadsOnlyWhatIsMissingFromManyThreads() async {
        let counter = CountingReader()
        let cache = MetadataCache { counter.read($0) }
        let entries = (0..<200).map { entry("/x/f\($0).txt", modified: Date(timeIntervalSince1970: 1)) }
        await withTaskGroup(of: Void.self) { group in
            for chunk in stride(from: 0, to: 200, by: 50) {
                let slice = Array(entries[chunk..<chunk + 50])
                group.addTask { cache.fill(slice) }
            }
        }
        #expect(cache.hasAll(entries))
        #expect(cache.reads == 200)
        #expect(cache.fill(entries) == 0)
        #expect(cache.metadata(entries[42]).title == "f42.txt")
    }

    @Test func aFullCacheStartsOver() {
        let counter = CountingReader()
        let cache = MetadataCache(limit: 3) { counter.read($0) }
        let entries = (0..<4).map { entry("/x/\($0)", modified: nil) }
        cache.fill(entries)
        #expect(cache.cached(entries[3]) != nil)
        #expect(cache.cached(entries[0]) == nil)
    }
}

@Suite struct MetadataReaderTests {
    /// A real PNG of 37 x 21 pixels, written with ImageIO into the test's own temp tree.
    private func png(_ url: URL, width: Int, height: Int) throws {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    @Test func imageDimensionsTypePermissionsAndDates() throws {
        let tree = try TestTree()
        defer { tree.close() }
        let url = tree.url("photo.png")
        try png(url, width: 37, height: 21)
        chmod(url.path, 0o640)
        let m = MetadataReader.read(url)
        #expect(m.pixelWidth == 37)
        #expect(m.pixelHeight == 21)
        #expect(m.uti == "public.png")
        #expect(m.permissions == "rw-r-----")
        #expect(m.created != nil)
        #expect(m.owner == NSUserName())
        let e = FolderListing.entry(for: url, kinds: &kindCache)
        #expect(ColumnValues.text(e, .dimensions, m) == "37 x 21")
        #expect(ColumnValues.text(e, .ext, m) == ".png")
        #expect(ColumnValues.text(e, .folderPath, m) == tree.root.path)
    }

    @Test func tagsAndCommentsWriteAndReadBack() throws {
        let tree = try TestTree()
        defer { tree.close() }
        let url = try tree.file("notes.txt")
        try MetadataWriter.setTags(["Work", "Red"], of: url)
        try MetadataWriter.setComment("Quarterly numbers", of: url)
        var m = MetadataReader.read(url)
        #expect(Set(m.tags) == ["Work", "Red"])
        #expect(m.comments == "Quarterly numbers")
        try MetadataWriter.setComment("", of: url)
        try MetadataWriter.setTags([], of: url)
        m = MetadataReader.read(url)
        #expect(m.comments == nil)
        #expect(m.tags.isEmpty)
    }

    @Test func symlinkTargetAndHiddenAttribute() throws {
        let tree = try TestTree()
        defer { tree.close() }
        let target = try tree.file("real.txt")
        let link = tree.url("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(MetadataReader.read(link).linkTarget == target.path)
        let hidden = try tree.file(".secret")
        let m = MetadataReader.read(hidden)
        #expect(m.isHidden)
        let e = FolderListing.entry(for: hidden, kinds: &kindCache)
        #expect(ColumnValues.text(e, .attributes, m) == "Hidden")
        #expect(e.isHidden)
        #expect(FolderListing.entry(for: link, kinds: &kindCache).isLink)
    }

    @Test func tagTextSplitsOnCommasAndSemicolons() {
        #expect(MetadataWriter.parseTags(" Work, Red;;red ; Work ") == ["Work", "Red", "red"])
        #expect(MetadataWriter.parseTags("   ").isEmpty)
    }

    @Test func mediaTextFormats() {
        #expect(ColumnValues.durationText(187) == "00:03:07")
        #expect(ColumnValues.durationText(3725.4) == "01:02:05")
        #expect(ColumnValues.frameRateText(30) == "30 frames/second")
        #expect(ColumnValues.frameRateText(29.97002997) == "29.97 frames/second")
        #expect(MetadataReader.permissionText(0o755) == "rwxr-xr-x")
    }
}

nonisolated(unsafe) private var kindCache: [String: String] = [:]

@Suite struct FilteredStatusTests {
    @Test func statusCountsTheFilteredItemsAndSaysFromHowMany() {
        let s = SelectionSummary([])
        #expect(StatusText.count(items: 3, selection: s, total: 12) == "3 items (filtered from 12), 0 selected")
        #expect(StatusText.count(items: 12, selection: s) == "12 items, 0 selected")
    }

    @Test func extensionsHideOnlyFromFiles() {
        let file = FileEntry(url: URL(fileURLWithPath: "/a/report.txt"), name: "report.txt", isFolder: false, modified: nil, size: 1, kind: "")
        let dot = FileEntry(url: URL(fileURLWithPath: "/a/.zshrc"), name: ".zshrc", isFolder: false, modified: nil, size: 1, kind: "")
        let folder = FileEntry(url: URL(fileURLWithPath: "/a/v1.2"), name: "v1.2", isFolder: true, modified: nil, size: nil, kind: "")
        #expect(file.displayName(extensions: false) == "report")
        #expect(file.displayName(extensions: true) == "report.txt")
        #expect(dot.displayName(extensions: false) == ".zshrc")
        #expect(folder.displayName(extensions: false) == "v1.2")
    }
}
