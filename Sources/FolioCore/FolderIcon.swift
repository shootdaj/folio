import CoreGraphics
import Darwin
import Foundation
import ImageIO

/// Properties > Customize > Change Icon: a folder's custom icon, written as Finder's Get Info writes it,
/// an invisible `Icon\r` file whose resource fork holds one 'icns' resource (id -16455), and the
/// folder's has-custom-icon Finder flag. Restore Default takes both away.
public enum FolderIcon {
    static let iconFile = "Icon\r"
    static let finderInfo = "com.apple.FinderInfo"
    static let resourceFork = "com.apple.ResourceFork"
    static let hasCustomIconFlag: UInt16 = 0x0400
    static let invisibleFlag: UInt16 = 0x4000

    public static func hasCustomIcon(_ folder: URL) -> Bool {
        let info = attribute(finderInfo, of: folder.path) ?? Data()
        guard info.count >= 10 else { return false }
        let flags = UInt16(info[info.startIndex + 8]) << 8 | UInt16(info[info.startIndex + 9])
        return flags & hasCustomIconFlag != 0 && FileManager.default.fileExists(atPath: folder.appendingPathComponent(iconFile).path)
    }

    /// Any picture ImageIO reads, fitted into a square and stored at the icon sizes Finder uses.
    public static func set(imageAt image: URL, on folder: URL) throws {
        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FileOpError.system("\(image.lastPathComponent) is not a picture Folio can read.")
        }
        try set(icns: icns(from: picture), on: folder)
    }

    public static func set(icns: Data, on folder: URL) throws {
        let icon = folder.appendingPathComponent(iconFile)
        if !FileManager.default.fileExists(atPath: icon.path) {
            guard FileManager.default.createFile(atPath: icon.path, contents: Data()) else { throw FileOpError.posix(errno, icon) }
        }
        try setAttribute(resourceFork, resourceFork(icns: icns), on: icon.path)
        // The icon file: type 'icon', creator 'MACS', invisible.
        var fileInfo = Data(count: 32)
        fileInfo.replaceSubrange(0..<8, with: Data("iconMACS".utf8))
        fileInfo[8] = UInt8(invisibleFlag >> 8)
        fileInfo[9] = UInt8(invisibleFlag & 0xFF)
        try setAttribute(finderInfo, fileInfo, on: icon.path)
        chflags(icon.path, UInt32(UF_HIDDEN))
        try setFlag(true, on: folder)
    }

    public static func clear(_ folder: URL) throws {
        let icon = folder.appendingPathComponent(iconFile)
        if FileManager.default.fileExists(atPath: icon.path), unlink(icon.path) != 0 { throw FileOpError.posix(errno, icon) }
        try setFlag(false, on: folder)
    }

    private static func setFlag(_ on: Bool, on folder: URL) throws {
        var info = attribute(finderInfo, of: folder.path) ?? Data(count: 32)
        if info.count < 32 { info.append(Data(count: 32 - info.count)) }
        var flags = UInt16(info[info.startIndex + 8]) << 8 | UInt16(info[info.startIndex + 9])
        flags = on ? flags | hasCustomIconFlag : flags & ~hasCustomIconFlag
        info[info.startIndex + 8] = UInt8(flags >> 8)
        info[info.startIndex + 9] = UInt8(flags & 0xFF)
        if info.allSatisfy({ $0 == 0 }) {
            if removexattr(folder.path, finderInfo, XATTR_NOFOLLOW) != 0 && errno != ENOATTR { throw FileOpError.posix(errno, folder) }
        } else {
            try setAttribute(finderInfo, info, on: folder.path)
        }
        // Finder and the icon cache notice the change when the folder's date moves.
        utimes(folder.path, nil)
    }

    /// The icns: the picture fitted into squares of 512 down to 16 points.
    static func icns(from picture: CGImage) throws -> Data {
        let data = NSMutableData()
        let sizes = [512, 256, 128, 32, 16]
        guard let dest = CGImageDestinationCreateWithData(data, "com.apple.icns" as CFString, sizes.count, nil) else {
            throw FileOpError.system("Could not make an icon.")
        }
        for size in sizes {
            guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            let scale = min(Double(size) / Double(picture.width), Double(size) / Double(picture.height))
            let w = Double(picture.width) * scale, h = Double(picture.height) * scale
            ctx.interpolationQuality = .high
            ctx.draw(picture, in: CGRect(x: (Double(size) - w) / 2, y: (Double(size) - h) / 2, width: w, height: h))
            if let image = ctx.makeImage() { CGImageDestinationAddImage(dest, image, nil) }
        }
        guard CGImageDestinationFinalize(dest) else { throw FileOpError.system("Could not make an icon.") }
        return data as Data
    }

    /// A classic resource fork with one resource: 'icns' -16455 (Inside Macintosh's layout: a 256-byte
    /// header area, the data, then the map).
    static func resourceFork(icns: Data) -> Data {
        func be16(_ v: Int) -> Data { Data([UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]) }
        func be32(_ v: Int) -> Data { Data([UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]) }
        let dataOffset = 256
        let dataLength = 4 + icns.count
        let mapOffset = dataOffset + dataLength
        let mapLength = 28 + 2 + 8 + 12
        let header = be32(dataOffset) + be32(mapOffset) + be32(dataLength) + be32(mapLength)
        var out = header + Data(count: dataOffset - header.count)
        out += be32(icns.count) + icns
        var map = header
        map += be32(0) + be16(0) + be16(0)          // next map handle, file reference, attributes
        map += be16(28) + be16(mapLength)           // type list and name list offsets from the map's start
        map += be16(0)                              // one type, counted from zero
        map += Data("icns".utf8) + be16(0) + be16(10) // one resource of it; its reference list 10 bytes into the type list
        map += be16(-16455 & 0xFFFF) + be16(0xFFFF) // id, no name
        map += Data([0, 0, 0, 0])                   // attributes and data offset 0
        map += be32(0)                              // handle
        out += map
        return out
    }

    private static func attribute(_ name: String, of path: String) -> Data? {
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let n = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        return n > 0 ? data : nil
    }

    private static func setAttribute(_ name: String, _ value: Data, on path: String) throws {
        let r = value.withUnsafeBytes { setxattr(path, name, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) }
        if r != 0 { throw FileOpError.posix(errno, URL(fileURLWithPath: path)) }
    }
}

/// Files the Mac keeps for itself: Folder Options' Hide protected operating system files leaves them
/// out even while hidden items are shown (Explorer's desktop.ini and thumbs.db).
public enum ProtectedFiles {
    static let names: Set<String> = [
        ".DS_Store", ".localized", ".Spotlight-V100", ".fseventsd", ".Trashes", ".TemporaryItems", ".DocumentRevisions-V100",
        ".VolumeIcon.icns", "Icon\r", ".com.apple.timemachine.donotpresent", ".com.apple.timemachine.supported",
        ".PKInstallSandboxManager", ".PKInstallSandboxManager-SystemSoftware", ".file", ".vol", ".hotfiles.btree",
        ".apdisk", ".AppleDouble", ".AppleDB", ".AppleDesktop", ".MobileBackups", ".DocumentRevisions-V100-bad-1",
    ]

    public static func isProtected(name: String) -> Bool { names.contains(name) || name.hasPrefix("._") }

    public static func filter(_ rows: [FileEntry]) -> [FileEntry] { rows.filter { !isProtected(name: $0.name) } }
}
