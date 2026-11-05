import Foundation
import Testing
@testable import FolioCore

/// What a drop does: Explorer's same-drive move and other-drive copy, macOS's modifiers (Option copies,
/// Cmd moves, Cmd+Option makes an alias), Control or the right button asks, and drops that make no sense.
@Suite struct DropRulesTests {
    private let sameVolume: @Sendable (URL, URL) -> Bool = { _, _ in true }
    private let otherVolume: @Sendable (URL, URL) -> Bool = { _, _ in false }

    @Test func aPlainDropOnTheSameVolumeMovesAndOnAnotherVolumeCopies() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt")
        let target = try t.folder("work/target")
        #expect(DropRules.action(dropping: [a], onto: target, sameVolume: sameVolume) == .move)
        #expect(DropRules.action(dropping: [a], onto: target, sameVolume: otherVolume) == .copy)
        // The real check: two items in one temp tree share a volume, and /dev (devfs) is another one.
        #expect(Volumes.same(a, target))
        #expect(!Volumes.same(a, URL(fileURLWithPath: "/dev")))
        #expect(DropRules.action(dropping: [a], onto: target) == .move)
    }

    @Test func modifiersOverrideTheVolumeRule() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt")
        let target = try t.folder("work/target")
        #expect(DropRules.action(dropping: [a], onto: target, keys: .option, sameVolume: sameVolume) == .copy)
        #expect(DropRules.action(dropping: [a], onto: target, keys: .command, sameVolume: otherVolume) == .move)
        #expect(DropRules.action(dropping: [a], onto: target, keys: [.command, .option], sameVolume: sameVolume) == .alias)
        #expect(DropRules.action(dropping: [a], onto: target, keys: .control, sameVolume: sameVolume) == .ask)
        #expect(DropRules.action(dropping: [a], onto: target, keys: [.control, .option], sameVolume: sameVolume) == .ask)
        #expect(DropRules.action(dropping: [a], onto: target, rightButton: true, sameVolume: otherVolume) == .ask)
    }

    @Test func oneSourceOnAnotherVolumeMakesTheWholeDropACopy() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt"), b = try t.file("elsewhere/b.txt")
        let target = try t.folder("work/target")
        let mixed: @Sendable (URL, URL) -> Bool = { src, _ in src.lastPathComponent != "b.txt" }
        #expect(DropRules.action(dropping: [a, b], onto: target, sameVolume: mixed) == .copy)
    }

    @Test func whatTheSourceForbidsFallsBackToWhatItAllows() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt")
        let target = try t.folder("work/target")
        // A browser or Mail offers copies only: a same-volume drop copies, Cmd+drop too.
        #expect(DropRules.action(dropping: [a], onto: target, allowed: .copy, sameVolume: sameVolume) == .copy)
        #expect(DropRules.action(dropping: [a], onto: target, keys: .command, allowed: .copy, sameVolume: sameVolume) == .copy)
        #expect(DropRules.action(dropping: [a], onto: target, keys: [.command, .option], allowed: .copy,
                                 sameVolume: sameVolume) == DropAction.none)
        #expect(DropRules.action(dropping: [a], onto: target, keys: .option, allowed: .move, sameVolume: sameVolume) == .move)
    }

    @Test func aFolderCannotGoIntoItselfOrItsOwnSubfolder() throws {
        let t = try TestTree()
        defer { t.close() }
        let docs = try t.folder("work/Docs")
        let inner = try t.folder("work/Docs/inner")
        #expect(DropRules.action(dropping: [docs], onto: docs) == DropAction.none)
        #expect(DropRules.action(dropping: [docs], onto: inner) == DropAction.none)
        #expect(DropRules.action(dropping: [docs], onto: inner, keys: .option) == DropAction.none)
        // An alias of a folder may live inside it.
        #expect(DropRules.action(dropping: [docs], onto: inner, keys: [.command, .option]) == .alias)
    }

    @Test func movingItemsIntoTheFolderTheyAreAlreadyInDoesNothingButCopyingDuplicates() throws {
        let t = try TestTree()
        defer { t.close() }
        let work = try t.folder("work")
        let a = try t.file("work/a.txt")
        #expect(DropRules.action(dropping: [a], onto: work) == DropAction.none)
        #expect(DropRules.action(dropping: [a], onto: work, keys: .option) == .copy)
        // /tmp and /private/tmp are the same folder.
        let spelledTmp = URL(fileURLWithPath: work.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/"))
        #expect(DropRules.action(dropping: [a], onto: spelledTmp) == DropAction.none)
    }

    @Test func droppingOnAnAppOpensTheFilesWithIt() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt")
        let app = try t.folder("work/Editor.app")
        #expect(DropRules.isApp(app))
        #expect(!DropRules.isApp(try t.folder("work/plain")))
        #expect(DropRules.action(dropping: [a], onto: app) == .open)
        #expect(DropRules.action(dropping: [a], onto: app, keys: .option) == .open)
        #expect(DropRules.action(dropping: [app], onto: app) == DropAction.none)
    }

    @Test func theAskMenuMarksThePlainDropAsItsDefault() throws {
        let t = try TestTree()
        defer { t.close() }
        let a = try t.file("work/a.txt")
        let target = try t.folder("work/target")
        #expect(DropRules.plainAction(dropping: [a], onto: target, sameVolume: sameVolume) == .move)
        #expect(DropRules.plainAction(dropping: [a], onto: target, sameVolume: otherVolume) == .copy)
        #expect(DropRules.canMove([a], into: target))
        #expect(!DropRules.canMove([a], into: a.deletingLastPathComponent()))
    }

    @Test func theBadgeNamesTheActionAndTheFolder() {
        #expect(DropRules.badge(.move, into: "target") == "Move to target")
        #expect(DropRules.badge(.copy, into: "target") == "Copy to target")
        #expect(DropRules.badge(.alias, into: "target") == "Create link in target")
        #expect(DropRules.badge(.open, into: "TextEdit") == "Open with TextEdit")
        #expect(DropRules.badge(.ask, into: "target") == "Choose what to do in target")
        #expect(DropRules.badge(.none, into: "target") == nil)
    }
}
