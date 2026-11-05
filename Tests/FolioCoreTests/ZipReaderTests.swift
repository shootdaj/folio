import Foundation
import Testing
@testable import FolioCore

/// Browsing a zip like a folder: its central directory read in Swift, folders it only implies, paths
/// inside it, copying entries out, and the search walk looking inside zips.
@Suite(.serialized) struct ZipReaderTests {
    private func makeZip(_ t: TestTree) async throws -> URL {
        try t.file("src/pack/readme.txt", bytes: 11, fill: 0x72)
        try t.file("src/pack/docs/guide.md", bytes: 2048, fill: 0x67)
        try t.file("src/pack/docs/deep/notes.txt", bytes: 5, fill: 0x6E)
        try t.file("src/pack/bert-report.txt", bytes: 9)
        try FileManager.default.createDirectory(at: t.url("work"), withIntermediateDirectories: true)
        let zip = t.url("work/pack.zip")
        let r = await ArchiveJob(compress: [t.url("src/pack")], format: .zip, to: zip).run()
        #expect(r.state == .done)
        return zip
    }

    @Test func readsEveryEntryWithItsSizeAndDate() async throws {
        let t = try TestTree()
        defer { t.close() }
        let zip = try await makeZip(t)
        let archive = try ZipArchive(url: zip)
        let guide = try #require(archive.entries.first { $0.path == "pack/docs/guide.md" })
        #expect(guide.size == 2048 && !guide.isDirectory)
        #expect(abs((guide.modified ?? .distantPast).timeIntervalSinceNow) < 600)
        #expect(archive.entries.contains { $0.path == "pack/docs/" && $0.isDirectory })
    }

    @Test func listsAFolderInsideTheZipWithFoldersItOnlyImplies() throws {
        // A zip that lists files only (no directory entries), as many tools write them.
        let t = try TestTree()
        defer { t.close() }
        let zip = try ZipFixture.write(to: t.url("work/flat.zip"), files: ["a/b/c.txt": 3, "a/top.txt": 4, "root.txt": 1])
        let archive = try ZipArchive(url: zip)
        #expect(archive.children(of: "").map(\.name) == ["a", "root.txt"])
        #expect(archive.children(of: "a").map(\.name) == ["b", "top.txt"])
        #expect(archive.children(of: "a").first?.isDirectory == true)
        #expect(archive.children(of: "a/b").map(\.name) == ["c.txt"])
        #expect(archive.children(of: "nope").isEmpty)
    }

    @Test func folderListingGivesRowsWhoseURLsSitUnderTheZip() async throws {
        let t = try TestTree()
        defer { t.close() }
        let zip = try await makeZip(t)
        let rows = try ZipFolder.list(zip.appendingPathComponent("pack/docs"))
        #expect(rows.map(\.name).sorted() == ["deep", "guide.md"])
        let deep = try #require(rows.first { $0.name == "deep" })
        #expect(deep.isFolder && deep.size == nil && deep.kind == "Folder")
        let guide = try #require(rows.first { $0.name == "guide.md" })
        #expect(guide.url.path == zip.path + "/pack/docs/guide.md")
        #expect(guide.size == 2048)
    }

    @Test func splitsAPathIntoTheArchiveAndThePlaceInsideIt() async throws {
        let t = try TestTree()
        defer { t.close() }
        let zip = try await makeZip(t)
        #expect(ZipPath.split(zip)?.inner == "")
        #expect(ZipPath.split(zip.appendingPathComponent("pack/docs"))?.archive.path == zip.path)
        #expect(ZipPath.split(zip.appendingPathComponent("pack/docs"))?.inner == "pack/docs")
        #expect(ZipPath.split(t.url("work")) == nil, "a plain folder is not in a zip")
        #expect(ZipPath.split(t.url("src/pack/readme.txt")) == nil)
    }

    @Test func copiesSelectedEntriesOutAsTopLevelItems() async throws {
        let t = try TestTree()
        defer { t.close() }
        let zip = try await makeZip(t)
        let out = try t.folder("out")
        let urls = try ZipFolder.extract([zip.appendingPathComponent("pack/docs/guide.md"), zip.appendingPathComponent("pack/docs/deep")],
                                         to: out)
        #expect(urls.map(\.lastPathComponent).sorted() == ["deep", "guide.md"])
        #expect(t.names("out") == ["deep", "guide.md"])
        #expect(t.data("out/deep/notes.txt") == Data(repeating: 0x6E, count: 5))
        #expect(t.data("out/guide.md")?.count == 2048)
    }

    @Test func aFileThatIsNotAZipFailsToOpen() throws {
        let t = try TestTree()
        defer { t.close() }
        let fake = try t.file("work/fake.zip", bytes: 64, fill: 0x20)
        #expect(throws: (any Error).self) { try ZipArchive(url: fake) }
    }

    @Test func theSearchWalkLooksInsideZipsOnlyWithZippedFoldersOn() async throws {
        let t = try TestTree()
        defer { t.close() }
        _ = try await makeZip(t)
        let query = try SearchQuery.parse("bert")
        var options = SearchWalk.Options()
        options.includeHidden = false
        let off = SearchWalk(roots: [t.url("work")], matcher: SearchMatcher(query), options: options).collect()
        #expect(off.isEmpty)
        options.zippedFolders = true
        let on = SearchWalk(roots: [t.url("work")], matcher: SearchMatcher(query), options: options).collect()
        #expect(on.map(\.entry.name) == ["bert-report.txt"])
        #expect(on.first?.entry.url.path.hasSuffix("work/pack.zip/pack/bert-report.txt") == true)
    }
}

/// Writes small stored (uncompressed) zips with file entries only, to test folders a zip only implies.
enum ZipFixture {
    static func write(to url: URL, files: [String: Int]) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var out = Data()
        var central = Data()
        func le16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
        func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        for (name, size) in files.sorted(by: { $0.key < $1.key }) {
            let body = Data(repeating: 0x41, count: size)
            let crc = CRC32.checksum(body)
            let offset = out.count
            let n = Data(name.utf8)
            out += le32(0x04034b50) + le16(10) + le16(0x0800) + le16(0) + le16(0) + le16(0x5821)
            out += le32(Int(crc)) + le32(size) + le32(size) + le16(n.count) + le16(0) + n + body
            central += le32(0x02014b50) + le16(0x031E) + le16(10) + le16(0x0800) + le16(0) + le16(0) + le16(0x5821)
            central += le32(Int(crc)) + le32(size) + le32(size) + le16(n.count) + le16(0) + le16(0) + le16(0) + le16(0)
            central += le32(0o100644 << 16) + le32(offset) + n
        }
        let cdOffset = out.count
        out += central
        out += le32(0x06054b50) + le16(0) + le16(0) + le16(files.count) + le16(files.count) + le32(central.count) + le32(cdOffset) + le16(0)
        try out.write(to: url)
        return url
    }
}

enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
        }
        return ~crc
    }
}
