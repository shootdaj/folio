import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FolioCore

/// The Dock icon: D1's folder with its phosphor light on the near-black square, drawn at every size an
/// iconset needs (iconutil makes Folio.icns from them), in dark and light.
@Suite struct AppIconTests {
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var data = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // (x, y) from the top left, as in the SVG.
        ctx.draw(image, in: CGRect(x: -CGFloat(x), y: -CGFloat(image.height - 1 - y), width: CGFloat(image.width), height: CGFloat(image.height)))
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

    @Test func darkIsTheNearBlackSquareWithAGreenLightLightIsPale() throws {
        let dark = try #require(AppIcon.render(pixels: 256, appearance: .dark))
        let light = try #require(AppIcon.render(pixels: 256, appearance: .light))
        #expect(dark.width == 256 && dark.height == 256)
        // Outside the rounded square: clear, as macOS icons are.
        #expect(pixel(dark, 2, 2).a == 0)
        #expect(pixel(light, 2, 2).a == 0)
        // Inside the square near its top edge, away from the folder: near-black in dark, pale in light.
        let d = pixel(dark, 128, 40), l = pixel(light, 128, 40)
        #expect(d.a == 255 && d.r < 40 && d.g < 40 && d.b < 45, "dark square: \(d)")
        #expect(l.a == 255 && l.r > 220 && l.g > 220 && l.b > 220, "light square: \(l)")
        // The phosphor light on the folder front is the accent: green leads.
        let (lx, ly) = AppIcon.lightCentre(pixels: 256)
        let led = pixel(dark, lx, ly)
        #expect(led.g > 200 && led.g > led.r && led.g > led.b, "the light is D1 green: \(led)")
        let ledLight = pixel(light, lx, ly)
        #expect(ledLight.g > ledLight.r && ledLight.g > ledLight.b && ledLight.g < 160, "light theme uses the darker green: \(ledLight)")
    }

    @Test func theSVGInTheRepoIsTheOneTheRendererDraws() throws {
        let svg = AppIcon.svg(.dark)
        #expect(svg.hasPrefix("<svg") && svg.contains("viewBox=\"0 0 1024 1024\""))
        #expect(svg.contains("#9BFF57") && svg.contains("#0C0E11"), "D1's green and near-black")
        #expect(AppIcon.svg(.light).contains("#2F7D1E"))
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (file, appearance) in [("AppIcon.svg", Appearance.dark), ("AppIcon-light.svg", .light)] {
            let committed = try String(contentsOf: repo.appendingPathComponent("Resources/\(file)"), encoding: .utf8)
            #expect(committed == AppIcon.svg(appearance), "Resources/\(file) is regenerated with `folio-icon --svg Resources`")
        }
    }
}
