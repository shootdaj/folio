import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FolioCore

/// Image commands and Remove properties: rotate left and right (a JPEG only gets a new orientation, so no
/// pixel is re-encoded; a PNG is redrawn, which is lossless), and EXIF, GPS and the download origin stripped.
@Suite(.serialized) struct ImageToolsTests {
    /// A 40 x 20 image with a camera, a date taken, a GPS position and the given orientation.
    static func makeImage(_ url: URL, type: UTType = .jpeg, orientation: Int = 1) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let w = 40, h = 20
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 10, height: h))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 10, y: 0, width: 30, height: h))
        let image = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        let props: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:05:01 10:20:30",
                                             kCGImagePropertyExifUserComment: "secret"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "TestCam 9", kCGImagePropertyTIFFArtist: "Anshul"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 13.75, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 100.5, kCGImagePropertyGPSLongitudeRef: "E"],
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
    }

    static func properties(_ url: URL) -> [CFString: Any] {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] ?? [:]
    }

    @Test func rotatingAJPEGRightSwapsItsDimensionsByOrientationAlone() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = t.url("work/photo.jpg")
        try Self.makeImage(f)
        let before = try Data(contentsOf: f)
        #expect(ImageTools.orientedSize(f)! == (40, 20))
        try ImageTools.rotate(f, clockwise: true)
        #expect(ImageTools.orientedSize(f)! == (20, 40))
        #expect(Self.properties(f)[kCGImagePropertyOrientation] as? Int == 6)
        // Lossless: the stored pixels are as they were, only the orientation tag moved.
        #expect((Self.properties(f)[kCGImagePropertyPixelWidth] as? Int) == 40)
        #expect(try Data(contentsOf: f).count < before.count + 200)
        let meta = MetadataReader.read(f)
        #expect(meta.pixelWidth == 20 && meta.pixelHeight == 40, "the Dimensions column follows the orientation")
        try ImageTools.rotate(f, clockwise: false)
        #expect(ImageTools.orientedSize(f)! == (40, 20))
        #expect(Self.properties(f)[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
    }

    @Test func fourRightTurnsComeBackToTheStartAndMirroredOrientationsComposeToo() {
        var o = 1
        for _ in 0..<4 { o = ImageTools.rotated(orientation: o, clockwise: true) }
        #expect(o == 1)
        #expect(ImageTools.rotated(orientation: 1, clockwise: true) == 6)
        #expect(ImageTools.rotated(orientation: 6, clockwise: true) == 3)
        #expect(ImageTools.rotated(orientation: 1, clockwise: false) == 8)
        #expect(ImageTools.rotated(orientation: 2, clockwise: true) == 7)
        #expect(ImageTools.rotated(orientation: 5, clockwise: true) == 2)
    }

    @Test func aPNGIsRedrawnTurned() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = t.url("work/shot.png")
        try Self.makeImage(f, type: .png)
        try ImageTools.rotate(f, clockwise: true)
        #expect((Self.properties(f)[kCGImagePropertyPixelWidth] as? Int) == 20)
        #expect((Self.properties(f)[kCGImagePropertyPixelHeight] as? Int) == 40)
        #expect(ImageTools.canRotate(f) && !ImageTools.canRotate(t.url("work/a.txt")))
    }

    @Test func removePropertiesStripsEXIFGPSAndTheCameraButKeepsTheImage() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = t.url("work/photo.jpg")
        try Self.makeImage(f, orientation: 6)
        let found = PersonalInfo.properties(of: f).map(\.name)
        #expect(found.contains("Date taken") && found.contains("Camera model") && found.contains("GPS position"))
        try PersonalInfo.remove(from: f)
        let p = Self.properties(f)
        #expect(p[kCGImagePropertyGPSDictionary] == nil)
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil && exif[kCGImagePropertyExifUserComment] == nil)
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFModel] == nil && tiff[kCGImagePropertyTIFFArtist] == nil)
        #expect(ImageTools.orientedSize(f)! == (20, 40), "the picture still shows the right way up")
        #expect(PersonalInfo.properties(of: f).isEmpty)
    }

    @Test func removePropertiesClearsWhereFromAndTheCommentOnAnyFile() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = try t.file("work/download.pdf", bytes: 30)
        try PersonalInfo.setWhereFroms(["https://example.com/download.pdf"], of: f)
        try MetadataWriter.setComment("from the web", of: f)
        #expect(PersonalInfo.properties(of: f).map(\.name).sorted() == ["Comments", "Where from"])
        try PersonalInfo.remove(from: f)
        #expect(PersonalInfo.properties(of: f).isEmpty)
        #expect(MetadataReader.finderComment(f) == nil)
    }

    @Test func aCleanCopySitsBesideTheOriginalWhichKeepsItsProperties() throws {
        let t = try TestTree()
        defer { t.close() }
        let f = t.url("work/photo.jpg")
        try Self.makeImage(f)
        let copy = try PersonalInfo.cleanCopy(of: f)
        #expect(copy.lastPathComponent == "photo - Copy.jpg")
        #expect(PersonalInfo.properties(of: copy).isEmpty)
        #expect(!PersonalInfo.properties(of: f).isEmpty)
    }
}
