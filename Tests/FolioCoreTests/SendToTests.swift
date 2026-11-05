import Foundation
import Testing
@testable import FolioCore

/// Send to targets (your own folder of aliases, like shell:sendto), Print's route to lp or the app,
/// and the address bar's commands (terminal, cmd, an app name).
@Suite(.serialized) struct SendToTests {
    @Test func sendToListsFoldersAndAppsInItsFolderAndFollowsAliases() throws {
        let t = try TestTree()
        defer { t.close() }
        let box = try t.folder("sendto")
        let backups = try t.folder("disks/Backups")
        let app = try t.folder("apps/Editor.app")
        try Aliases.make(.alias, to: backups, in: box)
        try Aliases.make(.symlink, to: app, in: box)
        try t.folder("sendto/Inbox")
        try t.file("sendto/readme.txt")
        let targets = SendTo.targets(in: box)
        #expect(targets.map(\.name) == ["Backups alias", "Editor.app symlink", "Inbox"])
        #expect(targets.map(\.isApp) == [false, true, false])
        #expect(FilePaths.folderKey(targets[0].url) == FilePaths.folderKey(backups))
        #expect(SendTo.targets(in: t.url("missing")).isEmpty)
    }

    @Test func printSendsPDFsTextAndImagesToLpAndTheRestToTheirApp() {
        func route(_ name: String) -> PrintRoute { PrintRoute.route(for: URL(fileURLWithPath: "/x/" + name)) }
        #expect(route("a.pdf") == .lp)
        #expect(route("a.txt") == .lp)
        #expect(route("a.png") == .lp)
        #expect(route("a.jpg") == .lp)
        #expect(route("a.docx") == .app)
        #expect(route("a.pages") == .app)
        #expect(route("Folder") == .app)
        #expect(PrintRoute.lpArguments([URL(fileURLWithPath: "/x/a b.pdf")]) == ["--", "/x/a b.pdf"])
    }

    @Test func theAddressBarRunsTerminalAndAppNames() {
        #expect(AddressCommand.parse("cmd") == .terminal)
        #expect(AddressCommand.parse("Terminal") == .terminal)
        #expect(AddressCommand.parse(" wt ") == .terminal)
        #expect(AddressCommand.parse("powershell") == .terminal)
        #expect(AddressCommand.parse("notepad") == .app("TextEdit"))
        #expect(AddressCommand.parse("calc") == .app("Calculator"))
        #expect(AddressCommand.parse("TextEdit") == .app("TextEdit"))
        #expect(AddressCommand.parse("/usr/bin") == nil)
        #expect(AddressCommand.parse("~/Documents") == nil)
        #expect(AddressCommand.parse("two words") == nil)
        #expect(AddressCommand.parse("") == nil)
    }

    @Test func anAppIsFoundByNameWhateverTheCase() throws {
        let t = try TestTree()
        defer { t.close() }
        let apps = try t.folder("Applications")
        try t.folder("Applications/TextEdit.app")
        try t.folder("Applications/Utilities/Terminal.app")
        #expect(AddressCommand.findApp(named: "textedit", in: [apps])?.lastPathComponent == "TextEdit.app")
        #expect(AddressCommand.findApp(named: "Terminal", in: [apps])?.lastPathComponent == "Terminal.app")
        #expect(AddressCommand.findApp(named: "Nothing", in: [apps]) == nil)
    }
}
