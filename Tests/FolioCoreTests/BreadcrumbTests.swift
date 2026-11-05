import Foundation
import Testing
@testable import FolioCore

@Suite struct BreadcrumbTests {
    @Test func pathBecomesOneCrumbPerFolderWithTheLastCurrent() {
        let crumbs = Breadcrumbs.crumbs(for: URL(fileURLWithPath: "/Users/anshul/Anshul/Code"))
        #expect(crumbs.map(\.title) == ["Macintosh HD", "Users", "anshul", "Anshul", "Code"])
        #expect(crumbs.map(\.path) == ["/", "/Users", "/Users/anshul", "/Users/anshul/Anshul", "/Users/anshul/Anshul/Code"])
        #expect(crumbs.map(\.isCurrent) == [false, false, false, false, true])
    }

    @Test func crumbsLeadBackToTheSamePath() {
        for path in ["/", "/private/tmp", "/private/tmp/folio-tests/run 1", "/Volumes/FolioScratch/a b/c"] {
            let crumbs = Breadcrumbs.crumbs(for: URL(fileURLWithPath: path))
            #expect(Breadcrumbs.path(of: crumbs) == path)
            // Clicking any crumb lands on that folder, a prefix of the path.
            for crumb in crumbs { #expect(path.hasPrefix(crumb.path)) }
        }
    }

    @Test func rootIsTheStartupDiskByName() {
        let crumbs = Breadcrumbs.crumbs(for: URL(fileURLWithPath: "/"))
        #expect(crumbs == [Crumb(title: "Macintosh HD", path: "/", isCurrent: true, isVolume: true)])
    }

    @Test func trailingSlashesAndDotsAreStandardized() {
        let crumbs = Breadcrumbs.crumbs(for: URL(fileURLWithPath: "/private/tmp/./x/../y/"))
        #expect(crumbs.map(\.title) == ["Macintosh HD", "private", "tmp", "y"])
    }

    @Test func typedPathsResolveAgainstHomeAndTheCurrentFolder() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let current = URL(fileURLWithPath: "/private/tmp/run")
        #expect(Breadcrumbs.resolve(typed: "  /private/tmp/  ", current: current, home: home)?.path == "/private/tmp")
        #expect(Breadcrumbs.resolve(typed: "~", current: current, home: home)?.path == "/Users/someone")
        #expect(Breadcrumbs.resolve(typed: "~/Downloads", current: current, home: home)?.path == "/Users/someone/Downloads")
        #expect(Breadcrumbs.resolve(typed: "sub/inner", current: current, home: home)?.path == "/private/tmp/run/sub/inner")
        #expect(Breadcrumbs.resolve(typed: "..", current: current, home: home)?.path == "/private/tmp")
        #expect(Breadcrumbs.resolve(typed: "   ", current: current, home: home) == nil)
    }

    private let volumes = [
        VolumeCapacity(name: "Startup", path: "/", total: 0, free: 0),
        VolumeCapacity(name: "FolioScratch", path: "/Volumes/FolioScratch", total: 0, free: 0),
    ]

    @Test func theRootCrumbShowsTheVolume() {
        let crumbs = Breadcrumbs.crumbs(for: URL(fileURLWithPath: "/Users/someone"), volumes: volumes)
        #expect(crumbs.map(\.title) == ["Startup", "Users", "someone"])
        #expect(crumbs.map(\.isVolume) == [true, false, false])
    }

    @Test func aPathOnAnotherVolumeStartsAtThatVolume() {
        let crumbs = Breadcrumbs.crumbs(for: URL(fileURLWithPath: "/Volumes/FolioScratch/a b/c"), volumes: volumes)
        #expect(crumbs.map(\.title) == ["FolioScratch", "a b", "c"])
        #expect(crumbs.map(\.path) == ["/Volumes/FolioScratch", "/Volumes/FolioScratch/a b", "/Volumes/FolioScratch/a b/c"])
        let top = Breadcrumbs.crumbs(for: URL(fileURLWithPath: "/Volumes/FolioScratch"), volumes: volumes)
        #expect(top == [Crumb(title: "FolioScratch", path: "/Volumes/FolioScratch", isCurrent: true, isVolume: true)])
        // A name that only starts like a volume is not on it.
        let other = Breadcrumbs.crumbs(for: URL(fileURLWithPath: "/Volumes/FolioScratch2/x"), volumes: volumes)
        #expect(other.map(\.title) == ["Startup", "Volumes", "FolioScratch2", "x"])
    }
}
