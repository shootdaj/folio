import Foundation
import Testing
@testable import FolioCore

/// Folder Options > General > Open "Show in Finder" from other apps in Folio: the NSFileViewer default
/// in the global domain, which AppKit reads for other apps' reveals. A fake store stands in for the Mac.
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

    @Test func offUntilTurnedOn() {
        #expect(!FileViewerSetting.isFolio(bundleID: folio, defaults: FakeDefaults()), "a new install leaves reveals on Finder")
    }

    @Test func turningItOnNamesFolioAndTurningItOffRemovesTheKey() {
        let d = FakeDefaults()
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
        #expect(d.values["NSFileViewer"] == folio)
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
        #expect(on.problem == "macOS did not keep the setting. \u{201C}Show in Finder\u{201D} in other apps still goes to Finder.")
        let stuck = FakeDefaults(["NSFileViewer": folio])
        stuck.ignoresWrites = true
        let off = FileViewerSetting.apply(on: false, bundleID: folio, defaults: stuck)
        #expect(off.problem == "macOS did not keep the setting. \u{201C}Show in Finder\u{201D} in other apps still goes to Folio.")
    }
}
