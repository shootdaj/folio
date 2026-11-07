import Foundation
import Testing
@testable import FolioCore

/// "Open folders in Folio instead of Finder": what Folio asks Launch Services for, and how it reports
/// what macOS actually kept (read back after asking), with a registry that can be told to refuse.
@Suite struct DefaultHandlerTests {
    /// Launch Services as a dictionary; `refuses` keeps the old handler for a type and returns an error.
    final class FakeRegistry: HandlerRegistry {
        var handlers: [String: String]
        var refuses: Set<String> = []
        var ignoresSilently: Set<String> = []
        /// macOS 26: a protected type keeps its handler and returns -50 for every app, Finder too.
        var protected: Set<String> = []
        var asked: [(String, String)] = []

        init(_ handlers: [String: String] = ["public.folder": "com.apple.finder"]) { self.handlers = handlers }

        func defaultHandler(for contentType: String) -> String? { handlers[contentType] }

        func setDefaultHandler(_ bundleID: String, for contentType: String) -> Int32 {
            asked.append((contentType, bundleID))
            if protected.contains(contentType) { return -50 }
            if refuses.contains(contentType) { return -54 }
            if !ignoresSilently.contains(contentType) { handlers[contentType] = bundleID }
            return 0
        }
    }

    @Test func turningItOnAsksForFoldersAndDrivesAndReportsWhatStuck() {
        let reg = FakeRegistry()
        let report = DefaultFolderHandler.apply(on: true, bundleID: "com.anshul.folio", registry: reg)
        #expect(reg.asked.map(\.0) == ["public.folder", "public.volume"])
        #expect(reg.asked.allSatisfy { $0.1 == "com.anshul.folio" })
        #expect(report.allAccepted)
        #expect(report.lines.map(\.now) == ["com.anshul.folio", "com.anshul.folio"])
        #expect(report.headline == "macOS now opens folders and drives in Folio")
        #expect(report.details.contains("Folders (public.folder): Folio"))
        #expect(report.note.contains("Reveal in Finder"), "the known limit is always said")
        #expect(DefaultFolderHandler.isFolio(bundleID: "com.anshul.folio", registry: reg))
    }

    @Test func aRefusalOrASilentNoIsReportedAsFinderKept() {
        let reg = FakeRegistry(["public.folder": "com.apple.finder", "public.volume": "com.apple.finder"])
        reg.refuses = ["public.volume"]
        reg.ignoresSilently = ["public.folder"]
        let report = DefaultFolderHandler.apply(on: true, bundleID: "com.anshul.folio", registry: reg)
        #expect(!report.allAccepted)
        #expect(report.lines.allSatisfy { !$0.accepted })
        #expect(report.headline == "macOS kept Finder for folders and drives")
        #expect(report.details.contains("asked for Folio, macOS still reports Finder (com.apple.finder)"))
        #expect(report.details.contains("error -54"))
        #expect(!DefaultFolderHandler.isFolio(bundleID: "com.anshul.folio", registry: reg))
    }

    @Test func partlyAcceptedSaysWhichOne() {
        let reg = FakeRegistry()
        reg.ignoresSilently = ["public.volume"]
        let report = DefaultFolderHandler.apply(on: true, bundleID: "com.anshul.folio", registry: reg)
        #expect(report.headline == "macOS opens folders in Folio but kept drives on another app")
        #expect(report.details.contains("Drives (public.volume): asked for Folio, macOS still reports no app"))
    }

    /// Measured on macOS 26.4.1: public.folder returns -50 (paramErr) for every app, and the log says
    /// "scheme or content type is protected". public.volume still changes.
    @Test func aProtectedFolderTypeIsExplainedNotShownAsABareError() {
        let reg = FakeRegistry(["public.folder": "com.apple.finder", "public.volume": "com.apple.finder"])
        reg.protected = ["public.folder"]
        let report = DefaultFolderHandler.apply(on: true, bundleID: "com.anshul.folio", registry: reg)
        #expect(report.lines[0].protected)
        #expect(!report.lines[1].protected)
        #expect(report.headline == "macOS opens drives in Folio, but it does not let apps open folders")
        #expect(report.details.contains("Folders (public.folder): macOS keeps Finder."))
        #expect(report.details.contains("only Finder can change it (error -50)"))
        #expect(report.details.contains("Drives (public.volume): Folio"))
        #expect(!report.details.contains("asked for Folio"))
    }

    @Test func drivesInFolioCountAsOnSoTheBoxCanTurnThemOffAgain() {
        let reg = FakeRegistry(["public.folder": "com.apple.finder", "public.volume": "com.apple.finder"])
        reg.protected = ["public.folder"]
        _ = DefaultFolderHandler.apply(on: true, bundleID: "com.anshul.folio", registry: reg)
        #expect(DefaultFolderHandler.isFolio(bundleID: "com.anshul.folio", registry: reg))

        let off = DefaultFolderHandler.apply(on: false, bundleID: "com.anshul.folio", registry: reg)
        #expect(off.allAccepted, "Finder keeps folders, and drives go back to Finder")
        #expect(off.headline == "macOS opens folders and drives in Finder again")
        #expect(reg.handlers["public.volume"] == "com.apple.finder")
        #expect(!DefaultFolderHandler.isFolio(bundleID: "com.anshul.folio", registry: reg))
    }

    @Test func turningItOffHandsFoldersBackToFinder() {
        let reg = FakeRegistry(["public.folder": "com.anshul.folio", "public.volume": "com.anshul.folio"])
        let report = DefaultFolderHandler.apply(on: false, bundleID: "com.anshul.folio", registry: reg)
        #expect(reg.asked.allSatisfy { $0.1 == "com.apple.finder" })
        #expect(report.allAccepted)
        #expect(report.headline == "macOS opens folders and drives in Finder again")
        #expect(!DefaultFolderHandler.isFolio(bundleID: "com.anshul.folio", registry: reg))
    }

    @Test func bundleIDsReadAsAppNamesAndCaseDoesNotMatter() {
        #expect(DefaultFolderHandler.appName("com.apple.finder") == "Finder")
        #expect(DefaultFolderHandler.appName("com.anshul.folio") == "Folio")
        #expect(DefaultFolderHandler.appName("com.cocoatech.PathFinder") == "com.cocoatech.PathFinder")
        #expect(DefaultFolderHandler.appName(nil) == "no app")
        let reg = FakeRegistry(["public.folder": "COM.ANSHUL.FOLIO"])
        #expect(DefaultFolderHandler.isFolio(bundleID: "com.anshul.folio", registry: reg))
    }
}
