import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FolioCore

/// The Dock icon: a warm manila folder (a sheet and a blue index tab inside) on a slate tile with the
/// Mac's continuous corners, drawn at every size an iconset needs (iconutil makes Folio.icns from them).
@Suite struct AppIconTests {
    /// The pixel at (x, y) in 1024-unit icon coordinates, y up (as AppIcon draws).
    private func pixel(_ image: CGImage, _ x: CGFloat, _ y: CGFloat) -> (r: Int, g: Int, b: Int, a: Int) {
        let s = CGFloat(image.width) / AppIcon.canvas
        var data = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let px = (x * s).rounded(.down), py = (y * s).rounded(.down)
        ctx.draw(image, in: CGRect(x: -px, y: -py, width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Int(data[0]), Int(data[1]), Int(data[2]), Int(data[3]))
    }

    @Test func theIconsetHasAllTenSizesAtTheirPixelSizes() throws {
        let dir = URL(fileURLWithPath: "/private/tmp/folio-tests/iconset-\(UUID().uuidString)/Folio.iconset", isDirectory: true)
        defer { try? FileManager.default.trashItem(at: dir.deletingLastPathComponent(), resultingItemURL: nil) }
        let written = try AppIcon.writeIconset(to: dir)
        #expect(written.count == 10)
        let expected: [String: Int] = [
            "icon_16x16.png": 16, "icon_16x16@2x.png": 32, "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
            "icon_128x128.png": 128, "icon_128x128@2x.png": 256, "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
            "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
        ]
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == expected.keys.sorted(), "exactly the names iconutil wants, nothing else")
        for (name, px) in expected {
            let source = try #require(CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil))
            #expect(CGImageSourceGetType(source) as String? == "public.png", "\(name) is a PNG")
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            #expect(props[kCGImagePropertyPixelWidth] as? Int == px, "\(name) is \(px) wide")
            #expect(props[kCGImagePropertyPixelHeight] as? Int == px, "\(name) is \(px) high")
        }
    }

    /// macOS 26 boxes an icon in grey when it does not fill the icon shape, so the tile must be opaque
    /// everywhere inside the shape and clear outside it.
    @Test func theTileFillsTheContinuousCornerShapeExactly() throws {
        let image = try #require(AppIcon.render(pixels: 256))
        let shape = AppIcon.tilePath()
        var inside = 0, outside = 0
        for gy in stride(from: CGFloat(4), to: 1024, by: 8) {
            for gx in stride(from: CGFloat(4), to: 1024, by: 8) {
                let p = CGPoint(x: gx, y: gy)
                // Skip the antialiased edge: a pixel here is 4 icon units, so 10 units either side of the outline.
                let deep = [CGPoint(x: -10, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: -10), CGPoint(x: 0, y: 10)]
                    .map { shape.contains(CGPoint(x: p.x + $0.x, y: p.y + $0.y)) }
                if deep.allSatisfy({ $0 }) {
                    #expect(pixel(image, gx, gy).a == 255, "opaque inside the tile at \(p)"); inside += 1
                } else if deep.allSatisfy({ !$0 }) {
                    #expect(pixel(image, gx, gy).a == 0, "clear outside the tile at \(p)"); outside += 1
                }
            }
        }
        #expect(inside > 9000 && outside > 5000)
    }

    @Test func theCornersAreContinuousNotCircular() {
        // A continuous corner starts bending 1.53 radii from the corner, a circular one at 1 radius:
        // one radius in, the circle's edge is still straight but the continuous edge has dropped 3.3 units.
        let shape = AppIcon.tilePath()
        let r = AppIcon.radius, b = AppIcon.base
        #expect(shape.contains(CGPoint(x: b.midX, y: b.maxY - 1)), "the straight top edge")
        #expect(shape.contains(CGPoint(x: b.maxX - r * 1.6, y: b.maxY - 0.5)), "straight until 1.53 radii")
        #expect(!shape.contains(CGPoint(x: b.maxX - r, y: b.maxY - 1.5)), "bending already at one radius")
        #expect(!shape.contains(CGPoint(x: b.minX + r, y: b.minY + 1.5)), "all four corners")
        #expect(shape.contains(CGPoint(x: b.midX, y: b.midY)))
    }

    @Test func aManilaFolderWithABlueTabOnASlateTile() throws {
        for pixels in [1024, 256, 64] {
            let image = try #require(AppIcon.render(pixels: pixels))
            let tile = pixel(image, 512, 890)
            #expect(tile.a == 255 && tile.b > tile.r && tile.b > tile.g - 4, "slate tile at \(pixels): \(tile)")
            let folder = pixel(image, 400, 430)
            #expect(folder.r > 220 && folder.r > folder.g && folder.g > folder.b && folder.b < 200,
                    "manila front at \(pixels): \(folder)")
        }
        let large = try #require(AppIcon.render(pixels: 512))
        let tab = pixel(large, AppIcon.tabMark.x, AppIcon.tabMark.y)
        #expect(tab.b > tab.r + 60, "the blue index tab: \(tab)")
    }

    @Test func thePictureInTheRepoIsTheOneTheRendererDraws() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try #require(CGImageSourceCreateWithURL(repo.appendingPathComponent("Resources/AppIcon.png") as CFURL, nil))
        let committed = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let drawn = try #require(AppIcon.render(pixels: 1024))
        #expect(committed.width == 1024 && committed.height == 1024)
        // Sampled colour by colour; a little slack for CoreGraphics differences between macOS versions.
        var worst = 0
        for y in stride(from: CGFloat(3), to: 1024, by: 16) {
            for x in stride(from: CGFloat(3), to: 1024, by: 16) {
                let a = pixel(committed, x, y), b = pixel(drawn, x, y)
                worst = max(worst, abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b), abs(a.a - b.a))
            }
        }
        #expect(worst <= 6, "Resources/AppIcon.png is regenerated with `folio-icon --png Resources/AppIcon.png` (worst \(worst))")
    }
}
