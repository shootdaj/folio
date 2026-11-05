import Foundation
import Testing
@testable import FolioCore

/// Compress to ZIP, 7z and TAR and Extract all through bsdtar, on temp trees: Explorer's names, the
/// conflict number, what lands in the archive and back out, progress and undo records.
@Suite(.serialized) struct ArchiveTests {
    // MARK: Names

    @Test func oneFileIsNamedAfterItselfWithoutItsExtension() {
        let a = URL(fileURLWithPath: "/w/report.txt")
        #expect(ArchiveNaming.archiveName(for: [a], format: .zip) { _ in false } == "report.zip")
        #expect(ArchiveNaming.archiveName(for: [a], format: .sevenZip) { _ in false } == "report.7z")
        #expect(ArchiveNaming.archiveName(for: [a], format: .tar) { _ in false } == "report.tar")
    }

    @Test func aFolderKeepsItsWholeNameDotsIncluded() {
        let f = URL(fileURLWithPath: "/w/my.project", isDirectory: true)
        #expect(ArchiveNaming.archiveName(for: [f], format: .zip, isFolder: { _ in true }) { _ in false } == "my.project.zip")
    }

    @Test func severalItemsAreNamedAfterTheFirst() {
        let items = [URL(fileURLWithPath: "/w/b.txt"), URL(fileURLWithPath: "/w/a.txt")]
        #expect(ArchiveNaming.archiveName(for: items, format: .zip) { _ in false } == "b.zip")
    }

    @Test func aTakenNameGetsTheFirstFreeNumber() {
        let a = URL(fileURLWithPath: "/w/report.txt")
        var taken: Set<String> = ["report.zip"]
        #expect(ArchiveNaming.archiveName(for: [a], format: .zip) { taken.contains($0) } == "report (1).zip")
        taken.insert("report (1).zip")
        #expect(ArchiveNaming.archiveName(for: [a], format: .zip) { taken.contains($0) } == "report (2).zip")
    }

    @Test func extractAllProposesTheArchiveNameWithoutItsArchiveExtensions() {
        #expect(ArchiveNaming.extractFolderName(for: URL(fileURLWithPath: "/w/photos.zip")) == "photos")
        #expect(ArchiveNaming.extractFolderName(for: URL(fileURLWithPath: "/w/src.tar.gz")) == "src")
        #expect(ArchiveNaming.extractFolderName(for: URL(fileURLWithPath: "/w/src.tgz")) == "src")
        #expect(ArchiveNaming.extractFolderName(for: URL(fileURLWithPath: "/w/v1.2.7z")) == "v1.2")
    }

    @Test func extractAllIsOfferedForTheArchiveKindsLibarchiveReads() {
        for name in ["a.zip", "a.7z", "a.tgz", "a.tar.gz", "a.tar", "a.tar.bz2", "a.tar.xz", "a.rar", "A.ZIP"] {
            #expect(ArchiveNaming.isExtractable(URL(fileURLWithPath: "/w/" + name)), "\(name)")
        }
        for name in ["a.txt", "a.gz.txt", "zip", "a.dmg"] {
            #expect(!ArchiveNaming.isExtractable(URL(fileURLWithPath: "/w/" + name)), "\(name)")
        }
        #expect(ArchiveNaming.isBrowsable(URL(fileURLWithPath: "/w/a.zip")))
        #expect(!ArchiveNaming.isBrowsable(URL(fileURLWithPath: "/w/a.7z")))
    }

    // MARK: Jobs

    @Test func compressMakesAZipHoldingBothFilesWithTheirContents() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt", bytes: 3000, fill: 0x61)
        let b = try t.file("work/b.txt", bytes: 5, fill: 0x62)
        let out = t.url("work/a.zip")
        let job = ArchiveJob(compress: [a, b], format: .zip, to: out)
        let r = await job.run()
        #expect(r.state == .done)
        #expect(r.placed == [out])
        #expect(r.record == .created([out], title: "Compress"))
        let zip = try ZipArchive(url: out)
        #expect(zip.entries.map(\.path).sorted() == ["a.txt", "b.txt"])
        #expect(zip.entries.first { $0.path == "a.txt" }?.size == 3000)
        let s = job.snapshot()
        #expect(s.kind == .compress && s.state == .done && s.itemsDone == s.itemsTotal && s.fraction == 1)
    }

    @Test func compressKeepsFoldersAndLeavesNoMacMetadataEntries() async throws {
        let t = try TestTree()
        defer { t.close() }
        let photos = try t.folder("work/Photos")
        try t.file("work/Photos/one.jpg", bytes: 10)
        try t.file("work/Photos/Trip/day.jpg", bytes: 20)
        try MetadataWriter.setComment("kept out of the zip", of: t.url("work/Photos/one.jpg"))
        let out = t.url("work/Photos.zip")
        let r = await ArchiveJob(compress: [photos], format: .zip, to: out).run()
        #expect(r.state == .done)
        let names = try ZipArchive(url: out).entries.map(\.path).sorted()
        #expect(names == ["Photos/", "Photos/Trip/", "Photos/Trip/day.jpg", "Photos/one.jpg"])
    }

    @Test func extractAllPutsTheContentsInTheChosenFolder() async throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("src/docs/readme.md", bytes: 40, fill: 0x52)
        try t.file("src/top.txt", bytes: 7)
        let zip = t.url("work/bundle.zip")
        try FileManager.default.createDirectory(at: t.url("work"), withIntermediateDirectories: true)
        _ = await ArchiveJob(compress: [t.url("src/docs"), t.url("src/top.txt")], format: .zip, to: zip).run()
        let dest = t.url("work/bundle")
        let job = ArchiveJob(extract: zip, into: dest)
        let r = await job.run()
        #expect(r.state == .done)
        #expect(t.names("work/bundle") == ["docs", "top.txt"])
        #expect(t.data("work/bundle/docs/readme.md") == Data(repeating: 0x52, count: 40))
        #expect(r.record == .created([dest], title: "Extract"))
        #expect(job.snapshot().kind == .extract)
    }

    @Test(arguments: [ArchiveFormat.sevenZip, .tar])
    func sevenZipAndTarRoundTrip(_ format: ArchiveFormat) async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/data.bin", bytes: 4096, fill: 0x33)
        let out = t.url("work/data." + format.fileExtension)
        #expect(await ArchiveJob(compress: [a], format: format, to: out).run().state == .done)
        #expect(t.exists("work/data." + format.fileExtension))
        let dest = t.url("out")
        #expect(await ArchiveJob(extract: out, into: dest).run().state == .done)
        #expect(t.data("out/data.bin") == Data(repeating: 0x33, count: 4096))
    }

    @Test func extractingATarGzWorksToo() async throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("src/x/y.txt", bytes: 12, fill: 0x79)
        let tgz = t.url("work/x.tar.gz")
        try FileManager.default.createDirectory(at: t.url("work"), withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        p.arguments = ["-czf", tgz.path, "-C", t.url("src").path, "x"]
        try p.run()
        p.waitUntilExit()
        #expect(await ArchiveJob(extract: tgz, into: t.url("out")).run().state == .done)
        #expect(t.data("out/x/y.txt") == Data(repeating: 0x79, count: 12))
    }

    @Test func extractingIntoAFolderThatHasTheFilesKeepsTheOldOnes() async throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("src/a.txt", bytes: 3, fill: 0x4E)
        let zip = t.url("src/a.zip")
        _ = await ArchiveJob(compress: [a], format: .zip, to: zip).run()
        try t.file("out/a.txt", bytes: 2, fill: 0x4F)
        let r = await ArchiveJob(extract: zip, into: t.url("out")).run()
        #expect(r.state == .done)
        #expect(t.data("out/a.txt") == Data(repeating: 0x4F, count: 2), "nothing is overwritten")
        #expect(r.record == nil, "the folder was there before, so undo has nothing to take away")
    }

    @Test func aBrokenArchiveEndsCancelledWithTheToolsMessage() async throws {
        let t = try TestTree()
        defer { t.close() }
        let bad = try t.file("work/bad.zip", bytes: 100, fill: 0x00)
        let job = ArchiveJob(extract: bad, into: t.url("out"))
        let r = await job.run()
        #expect(r.state == .cancelled)
        #expect(job.errorMessage?.isEmpty == false)
        #expect(!t.exists("out"), "a failed extract leaves no empty folder behind")
    }

    @Test func cancellingACompressRemovesThePartialArchive() async throws {
        let t = try TestTree()
        defer { t.close() }
        let files = try (0..<20).map { try randomFile(t, "work/f\($0).bin", bytes: 3_000_000) }
        let out = t.url("work/f0.zip")
        let job = ArchiveJob(compress: files, format: .zip, to: out)
        job.start()
        _ = await waitUntil(5) { job.snapshot().itemsDone >= 2 }
        job.cancel()
        let r = await job.finished()
        #expect(r.state == .cancelled)
        #expect(!t.exists("work/f0.zip"))
    }

    @Test func pauseStopsProgressAndResumeFinishes() async throws {
        let t = try TestTree()
        defer { t.close() }
        let files = try (0..<12).map { try randomFile(t, "work/p\($0).bin", bytes: 3_000_000) }
        let job = ArchiveJob(compress: files, format: .zip, to: t.url("work/p.zip"))
        job.start()
        _ = await waitUntil(5) { job.snapshot().itemsDone >= 1 }
        job.pause()
        #expect(await waitUntil(2) { job.snapshot().state == .paused })
        let held = job.snapshot().itemsDone
        try await Task.sleep(for: .milliseconds(400))
        #expect(job.snapshot().itemsDone <= held + 1, "bsdtar is stopped while paused")
        job.resume()
        let r = await job.finished()
        #expect(r.state == .done)
        #expect(try ZipArchive(url: t.url("work/p.zip")).entries.count == 12)
    }
}

/// A file of random bytes (deflate cannot shrink it, so compressing it takes a moment).
func randomFile(_ t: TestTree, _ path: String, bytes: Int) throws -> URL {
    let u = t.url(path)
    try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    var data = Data(count: bytes)
    data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, bytes) }
    try data.write(to: u)
    return u
}
