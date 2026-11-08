import Foundation
import Testing
@testable import FolioCore

/// "Reveal in Folio instead of Finder": the NSFileViewer default in the global domain, and how Folio
/// tells a reveal of a folder from an open of it (both arrive as the same open-documents event).
@Suite struct FileViewerTests {
    final class FakeDefaults: GlobalDefaults {
        var values: [String: String]
        var ignoresWrites = false
        init(_ values: [String: String] = [:]) { self.values = values }
        func string(for key: String) -> String? { values[key] }
        func set(_ value: String?, for key: String) {
            guard !ignoresWrites else { return }
            values[key] = value
        }
    }

    let folio = "com.anshul.folio"

    @Test func turningItOnNamesFolioAndTurningItOffRemovesTheKey() {
        let d = FakeDefaults()
        #expect(!FileViewerSetting.isFolio(bundleID: folio, defaults: d))
        let on = FileViewerSetting.apply(on: true, bundleID: folio, defaults: d)
        #expect(d.values["NSFileViewer"] == folio)
        #expect(on.problem == nil && on.replaced == nil)
        #expect(FileViewerSetting.isFolio(bundleID: folio, defaults: d))
        let off = FileViewerSetting.apply(on: false, bundleID: folio, defaults: d)
        #expect(d.values["NSFileViewer"] == nil, "off removes the key, so AppKit uses Finder again")
        #expect(off.problem == nil)
        #expect(!FileViewerSetting.isFolio(bundleID: folio, defaults: d))
    }

    @Test func onSaysWhichAppItReplacedAndCaseDoesNotMatter() {
        let d = FakeDefaults(["NSFileViewer": "com.binarynights.ForkLift"])
        let on = FileViewerSetting.apply(on: true, bundleID: folio, defaults: d)
        #expect(on.replaced == "com.binarynights.ForkLift")
        #expect(FileViewerSetting.isFolio(bundleID: folio, defaults: FakeDefaults(["NSFileViewer": "COM.ANSHUL.FOLIO"])))
    }

    @Test func offLeavesAnotherAppsChoiceAlone() {
        let d = FakeDefaults(["NSFileViewer": "com.binarynights.ForkLift"])
        let off = FileViewerSetting.apply(on: false, bundleID: folio, defaults: d)
        #expect(d.values["NSFileViewer"] == "com.binarynights.ForkLift")
        #expect(off.problem == nil)
    }

    @Test func aWriteThatDoesNotStickIsAProblem() {
        let d = FakeDefaults()
        d.ignoresWrites = true
        let on = FileViewerSetting.apply(on: true, bundleID: folio, defaults: d)
        #expect(on.problem == "macOS did not keep the setting. Reveals from other apps still go to Finder.")
    }

    // MARK: Reveal or open

    func reveal(sender: String?, viewer: String? = "com.anshul.folio", volumeRoot: Bool = false) -> Bool {
        FileViewerSetting.isReveal(sender: sender, ownBundleID: folio, fileViewer: viewer, isVolumeRoot: volumeRoot)
    }

    /// Measured on macOS 26.4.1: a reveal from an app and `open -a` send byte-identical odoc events.
    /// Only the sender differs: the revealing app, or no app for a command-line tool.
    @Test func aFolderFromAnotherAppIsARevealWhileFolioIsTheFileViewer() {
        #expect(reveal(sender: "com.microsoft.VSCode"))
        #expect(reveal(sender: "COM.MICROSOFT.VSCODE"))
    }

    @Test func commandLineDockFinderAndFolioItselfStillOpenTheFolder() {
        #expect(!reveal(sender: nil), "open -a Folio <folder> and other tools have no app")
        #expect(!reveal(sender: "com.apple.dock"), "a folder dropped on Folio's Dock icon")
        #expect(!reveal(sender: "com.apple.finder"), "Finder's Open With > Folio")
        #expect(!reveal(sender: folio))
    }

    @Test func withoutTheSettingOrForADriveEverythingOpens() {
        #expect(!reveal(sender: "com.microsoft.VSCode", viewer: nil))
        #expect(!reveal(sender: "com.microsoft.VSCode", viewer: "com.binarynights.ForkLift"))
        #expect(!reveal(sender: "com.apple.DiskUtility", volumeRoot: true), "a drive opens in Folio as its default")
    }
}
