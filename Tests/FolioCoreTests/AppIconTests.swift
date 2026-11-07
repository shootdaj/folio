import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FolioCore

/// The Dock icon: a frosted white glass folder (two sheets seen through its front) on a cyan-to-blue
/// ground, drawn full bleed at every size an iconset needs (iconutil makes Folio.icns from them).
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

    /// macOS 26 puts an icon whose picture leaves part of the square clear in a grey frame at 16 and
    /// 32 px (tested on macOS 26.4). The picture is opaque to every edge at every size; macOS cuts its own
    /// shape and adds the rim and the shadow.
    @Test func everySizeIsOpaqueToTheEdges() throws {
        for pixels in [16, 32, 64, 128, 256, 512, 1024] {
            let image = try #require(AppIcon.render(pixels: pixels))
            let step = AppIcon.canvas / CGFloat(pixels)
            var clear: [CGPoint] = []
            for i in 0..<pixels {
                let t = (CGFloat(i) + 0.5) * step
                for p in [CGPoint(x: t, y: step / 2), CGPoint(x: t, y: AppIcon.canvas - step / 2),
                          CGPoint(x: step / 2, y: t), CGPoint(x: AppIcon.canvas - step / 2, y: t)]
                where pixel(image, p.x, p.y).a != 255 {
                    clear.append(p)
                }
            }
            #expect(clear.isEmpty, "the edge is opaque at \(pixels) px; clear at \(clear.prefix(3))")
            #expect(pixel(image, 512, 512).a == 255)
        }
    }

    /// Outside the bundle (`swift run`) nothing masks the picture, so the Dock gets it in the tile:
    /// opaque inside the continuous-corner shape and clear outside it.
    @Test func theMaskedPictureFillsTheTileExactly() throws {
        let image = try #require(AppIcon.masked(pixels: 256))
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

    @Test func aWhiteGlassFolderOnABlueGround() throws {
        for pixels in [1024, 256, 64, 32, 16] {
            let image = try #require(AppIcon.render(pixels: pixels))
            for (x, y) in [(40.0, 40.0), (984.0, 984.0), (512.0, 990.0)] {
                let ground = pixel(image, x, y)
                #expect(ground.b > 200 && ground.b > ground.r + 90, "blue ground at (\(x), \(y)), \(pixels) px: \(ground)")
            }
            let glass = pixel(image, AppIcon.glassMark.x, AppIcon.glassMark.y)
            #expect(glass.r > 170 && glass.g > 200 && glass.b > 230 && glass.b >= glass.r,
                    "white glass front at \(pixels) px: \(glass)")
        }
        let large = try #require(AppIcon.render(pixels: 512))
        let sheet = pixel(large, AppIcon.sheetMark.x, AppIcon.sheetMark.y)
        #expect(sheet.r > 225 && sheet.g > 225 && sheet.b > 235, "the white sheet above the glass: \(sheet)")
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
