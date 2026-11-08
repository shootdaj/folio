import Darwin
import Foundation
import Testing
@testable import FolioCore

/// The extended bulk read gives device, inode, links, allocated size and dates that agree with `lstat`.
@Suite struct BulkListingExtendedTests {
    @Test func extendedReadMatchesLstatForDeviceInodeLinksAndBlocks() throws {
        let t = try TestTree()
        defer { t.close() }
        _ = try t.file("fx/small.txt", bytes: 10)
        _ = try t.file("fx/big.bin", bytes: 100_000)
        _ = try t.file("fx/empty", bytes: 0)
        try FileManager.default.linkItem(at: t.url("fx/big.bin"), to: t.url("fx/big-twin.bin"))
        try FileManager.default.createSymbolicLink(atPath: t.url("fx/link").path, withDestinationPath: "small.txt")
        _ = try t.folder("fx/sub")
        let raws = try BulkListing.readExtended(t.url("fx").path)
        #expect(raws.count == 6)
        for raw in raws {
            var st = stat()
            #expect(lstat(t.url("fx/" + raw.name).path, &st) == 0, "lstat \(raw.name)")
            #expect(raw.device == UInt32(truncatingIfNeeded: st.st_dev), "device of \(raw.name)")
            #expect(raw.inode == UInt64(st.st_ino), "inode of \(raw.name)")
            if raw.type == VREG.rawValue || raw.type == VLNK.rawValue {
                #expect(raw.linkCount == UInt32(st.st_nlink), "links of \(raw.name)")
                #expect(raw.allocated == Int64(st.st_blocks) * 512, "allocated of \(raw.name)")
            }
        }
        let big = try #require(raws.first { $0.name == "big.bin" })
        let twin = try #require(raws.first { $0.name == "big-twin.bin" })
        #expect(big.inode == twin.inode)
        #expect(big.linkCount == 2 && twin.linkCount == 2)
        #expect(big.allocated == twin.allocated && (big.allocated ?? 0) >= 100_000)
        #expect(try #require(raws.first { $0.name == "small.txt" }).linkCount == 1)
    }

    @Test func extendedReadGivesAccessAndAddedDates() throws {
        let t = try TestTree()
        defer { t.close() }
        let file = try t.file("fx/dated.txt")
        let accessed = Date(timeIntervalSince1970: 1_600_000_000)
        let added = Date(timeIntervalSince1970: 1_500_000_000)
        var times = [timeval(tv_sec: 1_600_000_000, tv_usec: 0), timeval(tv_sec: 1_600_000_100, tv_usec: 0)]
        #expect(utimes(file.path, &times) == 0)
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_ADDEDTIME)
        var stamp = timespec(tv_sec: 1_500_000_000, tv_nsec: 0)
        #expect(setattrlist(file.path, &request, &stamp, MemoryLayout<timespec>.size, 0) == 0)
        let raw = try #require(try BulkListing.readExtended(t.url("fx").path).first)
        #expect(raw.accessed == accessed)
        #expect(raw.added == added)
        // The plain read does not ask for them.
        let plain = try #require(BulkListing.read(t.url("fx").path)?.first)
        #expect(plain.accessed == nil && plain.added == nil && plain.inode == 0)
    }

    @Test func extendedReadSaysDeniedForAFolderWithNoReadRight() throws {
        let t = try TestTree()
        defer { t.close() }
        let locked = try t.folder("fx/locked")
        _ = try t.file("fx/locked/inside.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        #expect(throws: ScanReadError.denied) { try BulkListing.readExtended(locked.path) }
    }

    @Test func extendedReadSaysMissingAndUnsupported() throws {
        #expect(throws: ScanReadError.missing) { try BulkListing.readExtended("/private/tmp/folio-tests/nope-\(UUID())") }
        #expect(throws: ScanReadError.unsupported) { try BulkListing.readExtended("/") }
    }
}
