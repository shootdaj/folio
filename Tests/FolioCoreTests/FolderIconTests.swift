import AppKit
import Foundation
import Testing
@testable import FolioCore

/// Customize this folder > Change Icon: the custom icon written the way Finder's Get Info writes it (an
/// invisible Icon\r file holding an icns resource, and the folder's has-custom-icon flag), then cleared.
@Suite(.serialized) struct FolderIconTests {
    @Test func setsAndClearsACustomFolderIconTheWayTheSystemWritesIt() async throws {
        let t = try TestTree()
        defer { t.close() }
        let folder = try t.folder("work/Projects")
        let png = t.url("work/icon.png")
        try ImageToolsTests.makeImage(png, type: .png)
        #expect(!FolderIcon.hasCustomIcon(folder))
        try FolderIcon.set(imageAt: png, on: folder)
        #expect(FolderIcon.hasCustomIcon(folder))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Icon\r").path))
        // The same resource map NSWorkspace.setIcon writes (Finder's Get Info), handles aside.
        let ours = try #require(Self.fork(folder))
        let system = try await Self.systemFork(t)
        #expect(Self.map(ours).dropLast(4) == Self.map(system).dropLast(4))
        // Icon\r stays out of the listing even with hidden items shown.
        #expect(ProtectedFiles.isProtected(name: "Icon\r"))
        try FolderIcon.clear(folder)
        #expect(!FolderIcon.hasCustomIcon(folder))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Icon\r").path))
    }

    @Test func readsAndClearsAnIconTheSystemSet() async throws {
        let t = try TestTree()
        defer { t.close() }
        let folder = try t.folder("work/Theirs")
        let ok = await MainActor.run { NSWorkspace.shared.setIcon(Self.redSquare(), forFile: folder.path, options: []) }
        #expect(ok)
        #expect(FolderIcon.hasCustomIcon(folder))
        try FolderIcon.clear(folder)
        #expect(!FolderIcon.hasCustomIcon(folder))
    }

    @MainActor static func redSquare() -> NSImage {
        let img = NSImage(size: NSSize(width: 64, height: 64))
        img.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        img.unlockFocus()
        return img
    }

    static func fork(_ folder: URL) -> Data? {
        let path = folder.appendingPathComponent("Icon\r").path
        let size = getxattr(path, "com.apple.ResourceFork", nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var d = Data(count: size)
        _ = d.withUnsafeMutableBytes { getxattr(path, "com.apple.ResourceFork", $0.baseAddress, size, 0, 0) }
        return d
    }

    static func systemFork(_ t: TestTree) async throws -> Data {
        let other = try t.folder("work/System")
        _ = await MainActor.run { NSWorkspace.shared.setIcon(redSquare(), forFile: other.path, options: []) }
        return try #require(fork(other))
    }

    /// The resource map from its type list on (the header copy, next-map handle and file number vary).
    static func map(_ fork: Data) -> Data {
        let at = fork[4..<8].reduce(0) { $0 << 8 | Int($1) }
        return fork.subdata(in: (at + 24)..<fork.count)
    }

    @Test func theResourceForkHoldsOneIcnsResource() throws {
        let icns = Data([0x69, 0x63, 0x6E, 0x73, 0, 0, 0, 8])
        let fork = FolderIcon.resourceFork(icns: icns)
        func be32(_ at: Int) -> Int { fork[at..<at + 4].reduce(0) { $0 << 8 | Int($1) } }
        #expect(be32(0) == 256)
        #expect(be32(8) == icns.count + 4)
        #expect(fork[256 + 4..<256 + 4 + icns.count] == icns)
        let map = be32(4)
        #expect(String(decoding: fork[map + 30..<map + 34], as: UTF8.self) == "icns")
        #expect(fork.count == map + be32(12))
    }
}
