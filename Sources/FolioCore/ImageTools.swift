import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Explorer's image commands: Rotate right and Rotate left. A JPEG (and HEIC, TIFF) gets a new
/// orientation through ImageIO's lossless copy, so no pixel is re-encoded; other images are redrawn
/// turned, which loses nothing for PNG.
public enum ImageTools {
    /// Formats ImageIO can copy with a new orientation without decoding the pixels.
    static let orientable: Set<String> = [UTType.jpeg.identifier, UTType.heic.identifier, UTType.tiff.identifier, "public.heif"]

    public static func canRotate(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()), type.conforms(to: .image) else { return false }
        return type != .svg && type != .pdf && type != .gif && type != .ico
    }

    /// Width and height as the image shows (EXIF orientations 5 to 8 turn it on its side).
    public static func orientedSize(_ url: URL) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
        let o = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(o) ? (h, w) : (w, h)
    }

    /// EXIF orientation as (mirrored, quarter turns clockwise), and back.
    private static let table: [Int: (Bool, Int)] = [1: (false, 0), 6: (false, 1), 3: (false, 2), 8: (false, 3),
                                                     2: (true, 0), 7: (true, 1), 4: (true, 2), 5: (true, 3)]

    /// The orientation after a quarter turn of what is shown.
    public static func rotated(orientation: Int, clockwise: Bool) -> Int {
        let (mirror, turns) = table[orientation] ?? (false, 0)
        let next = (turns + (clockwise ? 1 : 3)) % 4
        return table.first { $0.value == (mirror, next) }?.key ?? 1
    }

    public static func rotate(_ url: URL, clockwise: Bool) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) else {
            throw FileOpError.system("\(url.lastPathComponent) is not an image Folio can turn.")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let current = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let next = rotated(orientation: current, clockwise: clockwise)
        if orientable.contains(type as String) {
            try write(to: url, type: type) { dest in
                let options: [CFString: Any] = [kCGImageDestinationOrientation: next]
                var error: Unmanaged<CFError>?
                guard CGImageDestinationCopyImageSource(dest, source, options as CFDictionary, &error) else {
                    throw FileOpError.system(error?.takeRetainedValue().localizedDescription ?? "Could not turn the image.")
                }
            }
            return
        }
        // Redraw turned: the stored pixels change, the orientation tag goes back to upright.
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw FileOpError.system("Could not read the image.") }
        let turned = try turn(image, clockwise: clockwise)
        var keep = props
        keep[kCGImagePropertyOrientation] = 1
        keep[kCGImagePropertyPixelWidth] = nil
        keep[kCGImagePropertyPixelHeight] = nil
        try write(to: url, type: type) { dest in
            CGImageDestinationAddImage(dest, turned, keep as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw FileOpError.system("Could not write the image.") }
        }
    }

    private static func turn(_ image: CGImage, clockwise: Bool) throws -> CGImage {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw FileOpError.system("Could not turn the image.")
        }
        if clockwise {
            ctx.translateBy(x: 0, y: CGFloat(w))
            ctx.rotate(by: -.pi / 2)
        } else {
            ctx.translateBy(x: CGFloat(h), y: 0)
            ctx.rotate(by: .pi / 2)
        }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { throw FileOpError.system("Could not turn the image.") }
        return out
    }

    /// Writes beside the file, then swaps it in, keeping the original's attributes (tags, dates made).
    static func write(to url: URL, type: CFString, _ body: (CGImageDestination) throws -> Void) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".folio-\(UUID().uuidString)." + url.pathExtension)
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil) else {
            throw FileOpError.system("Could not write \(url.lastPathComponent).")
        }
        do {
            try body(dest)
            if FileManager.default.fileExists(atPath: temp.path) == false, !CGImageDestinationFinalize(dest) {
                throw FileOpError.system("Could not write \(url.lastPathComponent).")
            }
        } catch {
            unlink(temp.path)
            throw error
        }
        copyfile(url.path, temp.path, nil, copyfile_flags_t(COPYFILE_XATTR))
        if rename(temp.path, url.path) != 0 {
            let code = errno
            unlink(temp.path)
            throw FileOpError.posix(code, url)
        }
    }
}

/// One property Remove properties and personal information can take away.
public struct PersonalProperty: Sendable, Equatable {
    public let name: String
    public let value: String
}

/// Properties > Details > Remove properties and personal information: EXIF, GPS, TIFF and XMP in
/// images (copied without them, losslessly), and on any file where it was downloaded from and the
/// Finder comment. In place, or as a clean copy beside it.
public enum PersonalInfo {
    static let whereFromsAttribute = "com.apple.metadata:kMDItemWhereFroms"

    public static func properties(of url: URL) -> [PersonalProperty] {
        var out: [PersonalProperty] = []
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
           let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            if let v = exif[kCGImagePropertyExifDateTimeOriginal] { out.append(PersonalProperty(name: "Date taken", value: "\(v)")) }
            if let v = tiff[kCGImagePropertyTIFFModel] { out.append(PersonalProperty(name: "Camera model", value: "\(v)")) }
            if let v = tiff[kCGImagePropertyTIFFMake] { out.append(PersonalProperty(name: "Camera maker", value: "\(v)")) }
            if let v = tiff[kCGImagePropertyTIFFArtist] { out.append(PersonalProperty(name: "Authors", value: "\(v)")) }
            if let v = exif[kCGImagePropertyExifUserComment] { out.append(PersonalProperty(name: "Image comment", value: "\(v)")) }
            if let gps = p[kCGImagePropertyGPSDictionary] as? [CFString: Any], !gps.isEmpty {
                let lat = gps[kCGImagePropertyGPSLatitude].map { "\($0)" } ?? ""
                let lon = gps[kCGImagePropertyGPSLongitude].map { "\($0)" } ?? ""
                out.append(PersonalProperty(name: "GPS position", value: lat + ", " + lon))
            }
        }
        if let froms = whereFroms(url), !froms.isEmpty { out.append(PersonalProperty(name: "Where from", value: froms.joined(separator: ", "))) }
        if let c = MetadataReader.finderComment(url) { out.append(PersonalProperty(name: "Comments", value: c)) }
        return out
    }

    public static func whereFroms(_ url: URL) -> [String]? {
        let size = getxattr(url.path, whereFromsAttribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let n = data.withUnsafeMutableBytes { getxattr(url.path, whereFromsAttribute, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        guard n > 0 else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String]
    }

    /// For tests and the VM fixture: where a download came from, as Safari records it.
    public static func setWhereFroms(_ urls: [String], of url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: urls, format: .binary, options: 0)
        let r = data.withUnsafeBytes { setxattr(url.path, whereFromsAttribute, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
        if r != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    public static func remove(from url: URL) throws {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source),
           CGImageSourceGetCount(source) > 0, ImageTools.orientable.contains(type as String) || type as String == UTType.png.identifier {
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            try ImageTools.write(to: url, type: type) { dest in
                // Only the orientation stays, so the picture still shows the right way up.
                let meta = CGImageMetadataCreateMutable()
                if orientation != 1 {
                    CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation,
                                                                 orientation as CFNumber)
                }
                let options: [CFString: Any] = [
                    kCGImageDestinationMetadata: meta,
                    kCGImageDestinationMergeMetadata: false,
                    kCGImageMetadataShouldExcludeGPS: true,
                    kCGImageMetadataShouldExcludeXMP: true,
                ]
                var error: Unmanaged<CFError>?
                guard CGImageDestinationCopyImageSource(dest, source, options as CFDictionary, &error) else {
                    throw FileOpError.system(error?.takeRetainedValue().localizedDescription ?? "Could not remove the properties.")
                }
            }
        }
        for name in [whereFromsAttribute, MetadataReader.commentAttribute, "com.apple.metadata:kMDItemDownloadedDate"] {
            if removexattr(url.path, name, XATTR_NOFOLLOW) != 0 && errno != ENOATTR {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        }
    }

    /// "Create a copy with all possible properties removed": "photo - Copy.jpg" beside it.
    public static func cleanCopy(of url: URL) throws -> URL {
        let folder = url.deletingLastPathComponent()
        let name = FileNaming.copyName(for: url.lastPathComponent, isFolder: false) {
            FileJob.kind(folder.appendingPathComponent($0)) != .missing
        }
        let copy = folder.appendingPathComponent(name)
        if copyfile(url.path, copy.path, nil, copyfile_flags_t(COPYFILE_DATA | COPYFILE_STAT)) != 0 { throw FileOpError.posix(errno, copy) }
        try remove(from: copy)
        return copy
    }
}
