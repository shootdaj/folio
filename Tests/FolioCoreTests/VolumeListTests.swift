import Foundation
import Testing
@testable import FolioCore

/// This PC and Network: every mounted volume, the startup disk first; an Eject button only on what can
/// be ejected; network shares in their own group; a bar that turns red when nearly full.
@Suite struct VolumeListTests {
    private let gb: Int64 = 1_000_000_000

    private func volume(_ name: String, _ path: String, root: Bool = false, removable: Bool = false,
                        ejectable: Bool = false, local: Bool = true, inside: Bool = true,
                        total: Int64 = 100, free: Int64 = 50) -> VolumeCapacity {
        VolumeCapacity(name: name, path: path, total: total * gb, free: free * gb, isRoot: root,
                       isRemovable: removable, isEjectable: ejectable, isLocal: local, isInternal: inside)
    }

    @Test func startupDiskFirstThenInternalThenTheRestByName() {
        let all = [
            volume("Zip", "/Volumes/Zip", removable: true, ejectable: true, inside: false),
            volume("NAS", "/Volumes/NAS", local: false, inside: false),
            volume("Macintosh HD", "/", root: true),
            volume("Backup", "/Volumes/Backup", inside: false),
            volume("Data2", "/Volumes/Data2"),
        ]
        let (drives, network) = VolumeList.arrange(all)
        #expect(drives.map(\.name) == ["Macintosh HD", "Data2", "Backup", "Zip"])
        #expect(network.map(\.name) == ["NAS"])
    }

    @Test func ejectShowsForRemovableAndDiskImagesNeverForTheStartupDisk() {
        #expect(!volume("Macintosh HD", "/", root: true, ejectable: true).canEject)
        #expect(volume("USB", "/Volumes/USB", removable: true, inside: false).canEject)
        #expect(volume("FolioScratch", "/Volumes/FolioScratch", ejectable: true, inside: false).canEject)
        #expect(!volume("Internal", "/Volumes/Internal").canEject)
        let share = volume("NAS", "/Volumes/NAS", local: false, inside: false)
        #expect(share.isNetwork && share.canEject, "a share is disconnected the same way")
    }

    @Test func nearlyFullFromNinetyPercentUsed() {
        #expect(!volume("a", "/Volumes/a", total: 100, free: 11).isNearlyFull)
        #expect(volume("b", "/Volumes/b", total: 100, free: 10).isNearlyFull)
        #expect(volume("c", "/Volumes/c", total: 100, free: 0).isNearlyFull)
        #expect(!volume("d", "/Volumes/d", total: 0, free: 0).isNearlyFull, "unknown size is never red")
    }

    @Test func theOldInitialiserStillMakesALocalVolume() {
        let v = VolumeCapacity(name: "X", path: "/Volumes/X", total: 10, free: 5)
        #expect(v.isLocal && !v.isRoot && !v.canEject)
    }

    @Test func theMountedListHasTheStartupDiskFirstWithItsFlags() throws {
        let volumes = VolumeCapacity.mounted()
        let (drives, _) = VolumeList.arrange(volumes)
        let first = try #require(drives.first)
        #expect(first.path == "/")
        #expect(first.isRoot)
        #expect(!first.canEject)
        #expect(first.total > 0 && first.free > 0)
    }
}
