import Foundation
import Testing
@testable import FolioCore

@Suite struct FileNamingTests {
    private func taken(_ names: String...) -> (String) -> Bool {
        let set = Set(names.map { $0.lowercased() })
        return { set.contains($0.lowercased()) }
    }

    @Test func pasteIntoTheSameFolderMakesNameDashCopyThenNumbers() {
        #expect(FileNaming.copyName(for: "report.txt", isFolder: false, exists: taken("report.txt")) == "report - Copy.txt")
        #expect(FileNaming.copyName(for: "report.txt", isFolder: false,
                                    exists: taken("report.txt", "report - Copy.txt")) == "report - Copy (2).txt")
        #expect(FileNaming.copyName(for: "report.txt", isFolder: false,
                                    exists: taken("report.txt", "report - Copy.txt", "report - Copy (2).txt")) == "report - Copy (3).txt")
        #expect(FileNaming.copyName(for: "Photos", isFolder: true, exists: taken("Photos")) == "Photos - Copy")
        #expect(FileNaming.copyName(for: "v1.2", isFolder: true, exists: taken("v1.2")) == "v1.2 - Copy",
                "a folder name has no extension")
        #expect(FileNaming.copyName(for: "Makefile", isFolder: false, exists: taken("Makefile")) == "Makefile - Copy")
    }

    @Test func keepBothNumbersTheIncomingCopyAndKeepsTheExtension() {
        #expect(FileNaming.keepBothName(for: "a-video.mov", isFolder: false, exists: taken("a-video.mov")) == "a-video (1).mov")
        #expect(FileNaming.keepBothName(for: "a-video.mov", isFolder: false,
                                        exists: taken("a-video.mov", "a-video (1).mov")) == "a-video (2).mov")
        #expect(FileNaming.keepBothName(for: "a (1).txt", isFolder: false, exists: taken("a (1).txt")) == "a (2).txt",
                "an existing number is counted on, not doubled")
        #expect(FileNaming.keepBothName(for: "notes", isFolder: true, exists: taken("notes")) == "notes (1)")
    }

    @Test func newFolderAndNewTextDocumentNamesFollowExplorer() {
        #expect(FileNaming.newFolderName(exists: taken()) == "New folder")
        #expect(FileNaming.newFolderName(exists: taken("New folder")) == "New folder (2)")
        #expect(FileNaming.newFolderName(exists: taken("new folder", "New folder (2)")) == "New folder (3)",
                "names clash without regard to case, as on a Mac volume")
        #expect(FileNaming.newTextDocumentName(exists: taken()) == "New Text Document.txt")
        #expect(FileNaming.newTextDocumentName(exists: taken("New Text Document.txt")) == "New Text Document (2).txt")
    }

    @Test func batchRenameNumbersEveryItemAndKeepsEachExtension() {
        let plan = FileNaming.batchNames(base: "Trip", items: [("IMG_1.jpg", false), ("IMG_2.JPG", false),
                                                                 ("clip.mov", false), ("Extras", true)],
                                         exists: taken())
        #expect(plan == ["Trip (1).jpg", "Trip (2).JPG", "Trip (3).mov", "Trip (4)"])
    }

    @Test func batchRenameSkipsNumbersAlreadyTakenOutsideTheBatch() {
        let plan = FileNaming.batchNames(base: "Trip", items: [("a.jpg", false), ("b.jpg", false)],
                                         exists: taken("Trip (1).jpg"))
        #expect(plan == ["Trip (2).jpg", "Trip (3).jpg"])
    }

    @Test func renameSelectsTheBaseNameOnly() {
        #expect(FileNaming.baseNameRange("report.final.txt", isFolder: false) == 0..<12)
        #expect(FileNaming.baseNameRange("Makefile", isFolder: false) == 0..<8)
        #expect(FileNaming.baseNameRange(".bashrc", isFolder: false) == 0..<7, "a dot file is all base name")
        #expect(FileNaming.baseNameRange("v1.2", isFolder: true) == 0..<4, "a folder name is all base name")
    }

    @Test func renameRejectsSlashColonAndEmptyNames() {
        #expect(FileNaming.problem(with: "a/b") == .forbiddenCharacter("/"))
        #expect(FileNaming.problem(with: "a:b") == .forbiddenCharacter(":"))
        #expect(FileNaming.problem(with: "   ") == .empty)
        #expect(FileNaming.problem(with: "..") == .reserved)
        #expect(FileNaming.problem(with: String(repeating: "x", count: 256)) == .tooLong)
        #expect(FileNaming.problem(with: "fine name.txt") == nil)
    }

    @Test func anExtensionChangeIsCaughtButACaseChangeIsNot() {
        #expect(FileNaming.changesExtension(from: "a.txt", to: "a.md", isFolder: false))
        #expect(FileNaming.changesExtension(from: "a.txt", to: "a", isFolder: false))
        #expect(!FileNaming.changesExtension(from: "a.txt", to: "b.TXT", isFolder: false))
        #expect(!FileNaming.changesExtension(from: "Makefile", to: "Rakefile", isFolder: false))
        #expect(!FileNaming.changesExtension(from: "v1.2", to: "v1.3", isFolder: true))
    }
}
