import Foundation
import Testing
@testable import FolioCore

@Suite struct VolumeCapacityTests {
    private let gb: Int64 = 1_000_000_000

    @Test func usedShareFillsTwentyFourSegments() {
        let v = VolumeCapacity(name: "Macintosh HD", path: "/", total: 1000 * gb, free: 880 * gb)
        #expect(v.used == 120 * gb)
        #expect(v.percentText == "12%")
        #expect(v.litSegments() == 3)          // 12% of 24 is 2.88
        #expect(v.freeText == "880 GB free")
        #expect(v.totalText == "of 1.0 TB")
    }

    @Test func aNearlyEmptyDiskStillLightsOneSegmentAndAFullOneLightsAll() {
        let empty = VolumeCapacity(name: "USB", path: "/Volumes/USB", total: 64 * gb, free: 64 * gb - 1)
        #expect(empty.litSegments() == 1)
        #expect(empty.percentText == "0%")
        let full = VolumeCapacity(name: "Full", path: "/Volumes/Full", total: 500 * gb, free: 0)
        #expect(full.litSegments() == 24)
        #expect(full.percentText == "100%")
    }

    @Test func unknownCapacityLightsNothing() {
        let v = VolumeCapacity(name: "Net", path: "/Volumes/Net", total: 0, free: 0)
        #expect(v.litSegments() == 0)
        #expect(v.percentText == "0%")
    }

    @Test func gigabyteTextUsesDecimalUnitsLikeFinder() {
        #expect(ByteText.storage(81_400_000_000) == "81.4 GB")
        #expect(ByteText.storage(926_000_000_000) == "926 GB")
        #expect(ByteText.storage(2_000_000_000_000) == "2.0 TB")
        #expect(ByteText.storage(512_000_000) == "512 MB")
    }

    @Test func readsTheVolumeHoldingATempFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ff-vol-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.trashItem(at: dir, resultingItemURL: nil) }
        let v = try #require(VolumeCapacity.read(dir))
        #expect(v.total > 0)
        #expect(v.free > 0 && v.free <= v.total)
        #expect(!v.name.isEmpty)
    }
}

@Suite struct QuickAccessTests {
    @Test func codeComesFirstThenTheStandardFolders() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let places = QuickAccess.places(home: home)
        #expect(places.map(\.title) == ["Code", "Downloads", "Desktop", "Documents", "Pictures", "Movies"])
        #expect(places[0].prefix == "Anshul/")
        #expect(places[0].path == "/Users/someone/Anshul/Code")
        #expect(places[1].prefix == "")
        #expect(places[1].path == "/Users/someone/Downloads")
    }
}
