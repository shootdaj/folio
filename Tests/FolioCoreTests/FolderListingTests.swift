import Foundation
import Testing
@testable import FolioCore

/// Builds a throwaway folder and moves it to the Trash afterwards (never deletes).
private func makeTempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ff-listing-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func trash(_ url: URL) {
    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
}

@Suite struct FolderListingTests {
    @Test func listsFilesAndFoldersWithTheirDetails() throws {
        let dir = try makeTempFolder()
        defer { trash(dir) }
        try Data(repeating: 7, count: 1234).write(to: dir.appendingPathComponent("report.txt"))
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Photos"), withIntermediateDirectories: false)

        let entries = try FolderListing.list(dir)

        #expect(entries.map(\.name).sorted() == ["Photos", "report.txt"])
        let file = try #require(entries.first { $0.name == "report.txt" })
        #expect(file.isFolder == false)
        #expect(file.size == 1234)
        #expect(file.modified != nil)
        #expect(!file.kind.isEmpty)
        let folder = try #require(entries.first { $0.name == "Photos" })
        #expect(folder.isFolder == true)
        #expect(folder.size == nil)
        #expect(!folder.kind.isEmpty)
    }

    @Test func skipsHiddenFiles() throws {
        let dir = try makeTempFolder()
        defer { trash(dir) }
        try Data().write(to: dir.appendingPathComponent(".secret"))
        try Data().write(to: dir.appendingPathComponent("visible"))

        let entries = try FolderListing.list(dir)

        #expect(entries.map(\.name) == ["visible"])
    }

    @Test func treatsAppBundlesAsFilesAndFolderSymlinksAsFolders() throws {
        let dir = try makeTempFolder()
        defer { trash(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Tool.app/Contents"), withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("Real")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("Link"), withDestinationURL: target)

        let entries = try FolderListing.list(dir)

        #expect(entries.first { $0.name == "Tool.app" }?.isFolder == false)
        #expect(entries.first { $0.name == "Link" }?.isFolder == true)
    }

    @Test func kindMatchesTheSystemKindForEveryFile() throws {
        let dir = try makeTempFolder()
        defer { trash(dir) }
        for name in ["a.txt", "b.txt", "notes.md", "main.swift", "archive.zip", "noextension", "data.weird"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Sub"), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Tool.app/Contents"), withIntermediateDirectories: true)

        let entries = try FolderListing.list(dir)

        #expect(entries.count == 9)
        for entry in entries {
            let system = try entry.url.resourceValues(forKeys: [.localizedTypeDescriptionKey])
            #expect(entry.kind == system.localizedTypeDescription, "kind of \(entry.name)")
        }
    }

    @Test func sortedListingPutsFoldersFirstWithNaturalNames() throws {
        let dir = try makeTempFolder()
        defer { trash(dir) }
        for name in ["file10.txt", "file2.txt", "File1.txt"] {
            try Data().write(to: dir.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("zebra"), withIntermediateDirectories: false)

        let rows = try FolderListing.list(dir, sortedBy: .standard)

        #expect(rows.map(\.name) == ["zebra", "File1.txt", "file2.txt", "file10.txt"])
    }

    @Test func emptyFolderGivesNoEntries() throws {
        let dir = try makeTempFolder()
        defer { trash(dir) }
        #expect(try FolderListing.list(dir).isEmpty)
    }

    @Test func missingFolderThrows() {
        let missing = URL(fileURLWithPath: "/definitely/not/here-\(UUID().uuidString)")
        #expect(throws: (any Error).self) { try FolderListing.list(missing) }
    }
}
