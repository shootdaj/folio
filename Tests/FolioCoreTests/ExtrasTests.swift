import Foundation
import Testing
@testable import FolioCore

/// The smaller pieces of milestone 8: access keys, previous versions, folder column presets, protected
/// files, drives, info tips, drive and sharing commands, cloud files, the folder merge question.
@Suite struct ExtrasTests {
    // MARK: Access keys (Alt)

    @Test func everyCommandBarButtonHasItsOwnLetter() {
        #expect(CommandKey.allCases.map { AccessKeys.letter(for: $0) } == ["N", "X", "C", "V", "R", "S", "D", "O", "W", "M"])
        #expect(Set(CommandKey.allCases.map { AccessKeys.letter(for: $0) }).count == CommandKey.allCases.count)
        #expect(AccessKeys.command(for: "n") == .new)
        #expect(AccessKeys.command(for: "D") == .delete)
        #expect(AccessKeys.command(for: "q") == nil)
        #expect(AccessKeys.command(for: "") == nil)
    }

    @Test func tappingOptionAloneShowsTheKeysAndAShortcutDoesNot() {
        var tap = OptionTap()
        let pressed = tap.flagsChanged(option: true, others: false, at: 0)
        #expect(!pressed)
        let tapped = tap.flagsChanged(option: false, others: false, at: 0.2)
        #expect(tapped, "down and up alone: a tap")
        // Option held for a shortcut (Option+Left) is not a tap.
        _ = tap.flagsChanged(option: true, others: false, at: 1)
        tap.keyDown()
        let afterShortcut = tap.flagsChanged(option: false, others: false, at: 1.1)
        #expect(!afterShortcut)
        // Option with Shift is not a tap either.
        _ = tap.flagsChanged(option: true, others: false, at: 2)
        _ = tap.flagsChanged(option: true, others: true, at: 2.05)
        let withShift = tap.flagsChanged(option: false, others: false, at: 2.1)
        #expect(!withShift)
        // Held too long: not a tap.
        _ = tap.flagsChanged(option: true, others: false, at: 3)
        let heldLong = tap.flagsChanged(option: false, others: false, at: 4.5)
        #expect(!heldLong)
    }

    // MARK: Previous versions

    @Test func readsTimeMachineLocalSnapshotsFromTmutil() {
        let out = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-11-04-093015.local
        com.apple.TimeMachine.2026-11-05-101500.local
        com.apple.os.update-ABC
        """
        let snaps = TimeMachineSnapshots.parse(out)
        #expect(snaps.map(\.name) == ["com.apple.TimeMachine.2026-11-05-101500.local", "com.apple.TimeMachine.2026-11-04-093015.local"])
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: snaps[0].date)
        #expect(c.year == 2026 && c.month == 11 && c.day == 5 && c.hour == 10 && c.minute == 15)
        #expect(TimeMachineSnapshots.parse("No snapshots").isEmpty)
    }

    @Test func aFileInsideAMountedSnapshotIsFoundUnderTheSamePath() {
        let p = TimeMachineSnapshots.pathInSnapshot("/Users/a/doc.txt", mountPoint: "/private/tmp/snap")
        #expect(p == "/private/tmp/snap/Users/a/doc.txt")
        #expect(TimeMachineSnapshots.pathInSnapshot("/System/Volumes/Data/Users/a/x", mountPoint: "/m") == "/m/Users/a/x")
        let args = TimeMachineSnapshots.mountArguments(snapshot: "com.apple.TimeMachine.2026-11-05-101500.local", mountPoint: "/m")
        #expect(args == ["-o", "nobrowse,rdonly", "-s", "com.apple.TimeMachine.2026-11-05-101500.local", "/System/Volumes/Data", "/m"])
    }

    // MARK: Customize this folder: columns per kind

    @Test func eachFolderKindHasItsColumns() {
        #expect(ColumnPreset.allCases.map(\.title) == ["General items", "Documents", "Pictures", "Music", "Videos"])
        #expect(ColumnPreset.general.columns == ColumnSet.standardColumns)
        #expect(ColumnPreset.pictures.columns.contains(.dimensions) && ColumnPreset.pictures.columns.contains(.dateTaken))
        #expect(ColumnPreset.music.columns.contains(.album) && ColumnPreset.music.columns.contains(.artist))
        #expect(ColumnPreset.videos.columns.contains(.duration))
        var set = ColumnSet(visible: [.name, .size], widths: ["size": 99])
        set = ColumnPreset.pictures.applied(to: set)
        #expect(set.visible == ColumnPreset.pictures.columns)
        #expect(set.width(of: .size) == 99, "widths the user gave stay")
        #expect(ColumnPreset.matching(set) == .pictures)
        #expect(ColumnPreset.matching(ColumnSet(visible: [.name, .owner])) == nil)
    }

    // MARK: Hide protected operating system files

    @Test func protectedFilesAreTheMacsOwnBookkeeping() {
        for n in [".DS_Store", ".localized", ".Spotlight-V100", ".fseventsd", ".Trashes", ".TemporaryItems",
                  ".DocumentRevisions-V100", ".VolumeIcon.icns", "Icon\r", ".com.apple.timemachine.donotpresent"] {
            #expect(ProtectedFiles.isProtected(name: n), "\(n)")
        }
        for n in [".zshrc", ".git", "DS_Store", "Icon", "notes.txt"] { #expect(!ProtectedFiles.isProtected(name: n), "\(n)") }
        let rows = [FileEntry(url: URL(fileURLWithPath: "/w/.DS_Store"), name: ".DS_Store", isFolder: false, modified: nil, size: 6, kind: "", isHidden: true),
                    FileEntry(url: URL(fileURLWithPath: "/w/.zshrc"), name: ".zshrc", isFolder: false, modified: nil, size: 6, kind: "", isHidden: true)]
        #expect(ProtectedFiles.filter(rows).map(\.name) == [".zshrc"])
    }

    @Test func listingWithHiddenItemsStillLeavesProtectedFilesOutWhenAsked() throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("w/.DS_Store")
        try t.file("w/.zshrc")
        try t.file("w/a.txt")
        let all = try FolderListing.list(t.url("w"), includeHidden: true)
        #expect(all.map(\.name).sorted() == [".DS_Store", ".zshrc", "a.txt"])
        let shown = try FolderListing.list(t.url("w"), includeHidden: true, hideProtected: true)
        #expect(shown.map(\.name).sorted() == [".zshrc", "a.txt"])
    }

    // MARK: Drives

    @Test func hideEmptyDrivesLeavesOutDrivesWithNoMedia() {
        let disk = VolumeCapacity(name: "Macintosh HD", path: "/", total: 500, free: 100, isRoot: true)
        let reader = VolumeCapacity(name: "SD Card", path: "/Volumes/SD Card", total: 0, free: 0, isRemovable: true)
        #expect(VolumeList.arrange([disk, reader]).drives.count == 2)
        #expect(VolumeList.arrange([disk, reader], hideEmpty: true).drives.map(\.name) == ["Macintosh HD"])
    }

    @Test func showDriveLettersShowsTheMountPathAfterTheName() {
        let usb = VolumeCapacity(name: "USB", path: "/Volumes/USB", total: 5, free: 1, isRemovable: true)
        #expect(VolumeList.label(usb, showPath: false) == "USB")
        #expect(VolumeList.label(usb, showPath: true) == "USB (/Volumes/USB)")
    }

    @Test func formatAndCheckRunDiskutil() {
        #expect(DriveTools.formatArguments(volume: "/Volumes/USB", name: "Backup", format: .apfs) == ["eraseVolume", "APFS", "Backup", "/Volumes/USB"])
        #expect(DriveTools.formatArguments(volume: "/Volumes/USB", name: "Card", format: .exfat) == ["eraseVolume", "ExFAT", "Card", "/Volumes/USB"])
        #expect(DriveTools.verifyArguments(volume: "/Volumes/USB") == ["verifyVolume", "/Volumes/USB"])
        #expect(DriveTools.cleanName("  my/disk:1 ") == "mydisk1")
    }

    @Test func sharingAFolderUsesTheSharingTool() {
        #expect(DriveTools.shareArguments(folder: "/Users/a/Public Stuff", name: "Public Stuff") == ["-a", "/Users/a/Public Stuff", "-S", "Public Stuff"])
        #expect(DriveTools.unshareArguments(name: "Public Stuff") == ["-r", "Public Stuff"])
        #expect(DriveTools.sharedNames("""
        List of Share Points
        name:		Public Stuff
        path:		/Users/a/Public Stuff
        name:		Media
        path:		/Volumes/Media
        """) == ["/Users/a/Public Stuff": "Public Stuff", "/Volumes/Media": "Media"])
    }

    // MARK: Pop-up descriptions

    @Test func aFileTipReadsTypeSizeAndDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let e = FileEntry(url: URL(fileURLWithPath: "/w/a.png"), name: "a.png", isFolder: false, modified: date, size: 5000, kind: "PNG image")
        var m = ItemMetadata()
        m.pixelWidth = 900
        m.pixelHeight = 675
        let tip = InfoTip.text(for: e, metadata: m, folder: nil, formatter: { _ in "2023-11-14 22:13" })
        #expect(tip == "Type: PNG image\nDimensions: 900 \u{00D7} 675\nSize: 4.88 KB\nDate modified: 2023-11-14 22:13")
    }

    @Test func aFolderTipListsWhatIsInsideAndItsSizeOnlyWhenAsked() throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("f/one.txt", bytes: 1000)
        try t.file("f/two.txt", bytes: 2000)
        try t.folder("f/Sub")
        let summary = InfoTip.summarize(folder: t.url("f"))
        #expect(summary.files == ["one.txt", "two.txt"] && summary.folders == ["Sub"] && summary.bytes == 3000)
        let e = FileEntry(url: t.url("f"), name: "f", isFolder: true, modified: nil, size: nil, kind: "Folder")
        let with = InfoTip.text(for: e, metadata: nil, folder: summary, sizes: true, formatter: { _ in "" })
        #expect(with == "Size: 2.92 KB\nFolders: Sub\nFiles: one.txt, two.txt")
        let without = InfoTip.text(for: e, metadata: nil, folder: summary, sizes: false, formatter: { _ in "" })
        #expect(without == "Folders: Sub\nFiles: one.txt, two.txt")
    }

    // MARK: Hide folder merge conflicts off: ask before merging

    @Test func withMergeConflictsShownAFolderMergeAsksFirst() async throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("dest/Photos/old.jpg")
        let photos = try t.folder("src/Photos")
        try t.file("src/Photos/new.jpg")
        let job = FileJob(kind: .copy, sources: [photos], into: t.url("dest"), options: t.options { $0.askBeforeMerge = true })
        job.start()
        #expect(await waitUntil(5) { job.snapshot().conflict != nil })
        let c = try #require(job.snapshot().conflict)
        #expect(c.existing.isFolder && c.incoming.isFolder && c.isFolderMerge)
        job.resolve(.replace)
        let r = await job.finished()
        #expect(r.state == .done)
        #expect(t.names("dest/Photos") == ["new.jpg", "old.jpg"], "Yes merges the two folders")
    }

    @Test func declinedMergeSkipsTheFolder() async throws {
        let t = try TestTree()
        defer { t.close() }
        try t.file("dest/Photos/old.jpg")
        let photos = try t.folder("src/Photos")
        try t.file("src/Photos/new.jpg")
        let r = await FileJob(kind: .copy, sources: [photos], into: t.url("dest"),
                              options: t.options { $0.askBeforeMerge = true; $0.conflictPolicy = .skip }).run()
        #expect(r.state == .done)
        #expect(t.names("dest/Photos") == ["old.jpg"])
    }

    // MARK: Full screen

    @Test func f11IsOfferedOnlyWhenTheFunctionKeysAreStandard() {
        #expect(FullScreenKeys.offersF11(fnState: true))
        #expect(!FullScreenKeys.offersF11(fnState: false))
        #expect(!FullScreenKeys.offersF11(fnState: nil))
    }
}
