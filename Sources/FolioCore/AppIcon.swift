import Accelerate
import CoreGraphics
import Foundation
import ImageIO

/// Folio's app icon: three folder-shaped glass leaves fanned like cards (a folio is a leaf). The light look
/// has a blue front leaf on a white tile, the dark look a white front leaf on a graphite tile, with a cyan
/// leaf on the left and a pink one on the right in both.
///
/// macOS 26 puts an icon in a grey frame at 16 and 32 px when its picture leaves part of the square clear,
/// so each picture is full bleed: opaque to every edge. macOS cuts its own continuous-corner shape, shrinks
/// the square into its icon grid and adds the glass rim and the shadow. `make app` turns the light iconset
/// into Folio.icns, and the Icon Composer file (`writeIconFile`) into Assets.car, where macOS 26 takes the
/// dark picture in its dark icon style. Resources/AppIcon.png and AppIcon-dark.png are the 1024 pictures.
public enum AppIcon {
    /// The two looks: `light` for the default icon style, `dark` for macOS 26's dark icon style.
    public enum Look: String, CaseIterable, Sendable { case light, dark }

    public static let canvas: CGFloat = 1024
    /// macOS's icon grid: an 824 pt tile inside the 1024 pt canvas (for `masked(pixels:)`).
    static let base = CGRect(x: 100, y: 100, width: 824, height: 824)
    /// The corner radius of the continuous corners (a corner bends over 1.53 radii, as the system's does).
    static let radius: CGFloat = 185
    /// Points on the canvas (y up) for the tests: on the front leaf, and on the left and right leaves
    /// where the front leaf does not cover them (at every size, the small renders spread wider).
    static let frontMark = CGPoint(x: 512, y: 470)
    static let leftMark = CGPoint(x: 246, y: 520)
    static let rightMark = CGPoint(x: 778, y: 520)

    /// The iconset iconutil wants: file name and pixel size.
    public static let iconset: [(name: String, pixels: Int, scale: Int)] = [16, 32, 128, 256, 512].flatMap { pt in
        [("icon_\(pt)x\(pt).png", pt, 1), ("icon_\(pt)x\(pt)@2x.png", pt * 2, 2)]
    }

    // MARK: Shapes (icon units, y up)

    /// The tile: the 824 square with continuous corners (the cubic approximation of the system's squircle).
    static func tilePath() -> CGPath {
        let r = radius, b = base
        let p = CGMutablePath()
        // One corner as offsets from that corner, from along the first edge round to along the second.
        let corner: [(CGFloat, CGFloat)] = [
            (1.528665, 0), (1.088493, 0), (0.868407, 0.0220851), (0.631494, 0.0749114),
            (0.372824, 0.169059), (0.169059, 0.372824), (0.0749114, 0.631494),
            (0.0220851, 0.868407), (0, 1.088493), (0, 1.528665),
        ]
        // Each corner: its point, and the directions of the edge coming in (u) and the edge going out (v).
        let corners: [(CGPoint, CGVector, CGVector)] = [
            (CGPoint(x: b.maxX, y: b.minY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1)),
            (CGPoint(x: b.maxX, y: b.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0)),
            (CGPoint(x: b.minX, y: b.maxY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1)),
            (CGPoint(x: b.minX, y: b.minY), CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0)),
        ]
        for (i, (c, u, v)) in corners.enumerated() {
            let pts = corner.map { CGPoint(x: c.x + (u.dx * $0.0 + v.dx * $0.1) * r, y: c.y + (u.dy * $0.0 + v.dy * $0.1) * r) }
            if i == 0 { p.move(to: pts[0]) } else { p.addLine(to: pts[0]) }
            p.addCurve(to: pts[3], control1: pts[1], control2: pts[2])
            p.addCurve(to: pts[6], control1: pts[4], control2: pts[5])
            p.addCurve(to: pts[9], control1: pts[7], control2: pts[8])
        }
        p.closeSubpath()
        return p
    }

    /// One leaf (leaf units): a card with a round tab on the left and one smooth S shoulder, like a folder's back.
    static func leafPath() -> CGPath {
        let l: CGFloat = 318, r: CGFloat = 706, bot: CGFloat = 230, top: CGFloat = 700, rad: CGFloat = 46
        let tabTop: CGFloat = 760, tabStart: CGFloat = 470, tabEnd: CGFloat = 560
        let p = CGMutablePath()
        p.move(to: CGPoint(x: l + rad, y: bot))
        p.addLine(to: CGPoint(x: r - rad, y: bot))
        p.addArc(tangent1End: CGPoint(x: r, y: bot), tangent2End: CGPoint(x: r, y: top), radius: rad)
        p.addArc(tangent1End: CGPoint(x: r, y: top), tangent2End: CGPoint(x: l, y: top), radius: rad * 0.8)
        p.addLine(to: CGPoint(x: tabEnd, y: top))
        let k = (tabEnd - tabStart) * 0.38
        p.addCurve(to: CGPoint(x: tabStart, y: tabTop), control1: CGPoint(x: tabEnd - k, y: top),
                   control2: CGPoint(x: tabStart + k, y: tabTop))
        p.addArc(tangent1End: CGPoint(x: l, y: tabTop), tangent2End: CGPoint(x: l, y: bot), radius: rad * 1.25)
        p.addArc(tangent1End: CGPoint(x: l, y: bot), tangent2End: CGPoint(x: r, y: bot), radius: rad)
        p.closeSubpath()
        return p
    }

    /// The three leaves on the canvas, back to front: left, right, front. Each is the leaf enlarged by 1.1
    /// and lifted 22 units, narrowed, then turned about a point below the tile. Below 64 px the leaves are
    /// narrower and spread wider, so each one still shows.
    static func leafPaths(small: Bool) -> [CGPath] {
        let lift: CGFloat = 22, pivot = CGPoint(x: 512, y: 140 + lift)
        let enlarge = CGAffineTransform(translationX: 512, y: 512 + lift).scaledBy(x: 1.1, y: 1.1).translatedBy(x: -512, y: -512)
        let leaf = leafPath()
        return [(CGFloat(0.26), CGFloat(0.94)), (-0.26, 0.94), (0, 0.88)].map { turn, width in
            let narrow = small ? (turn == 0 ? 0.84 : 0.92) : width
            let angle = turn * (small ? 1.35 : 1.2)
            let t = enlarge
                .concatenating(CGAffineTransform(translationX: 512, y: 0).scaledBy(x: narrow, y: 1).translatedBy(x: -512, y: 0))
                .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y).rotated(by: angle).translatedBy(x: -pivot.x, y: -pivot.y))
            return leaf.copy(using: [t])!
        }
    }

    // MARK: Drawing

    /// Core Graphics' shadow blur gives slightly different pixels when two renders run at once (tested:
    /// up to 119 levels on 16 threads), and the pictures kept in the repo must be the ones the renderer draws.
    private static let renderLock = NSLock()

    /// The full-bleed picture at `pixels` square: what the iconset holds.
    public static func render(pixels: Int, look: Look = .light) -> CGImage? {
        renderLock.lock()
        defer { renderLock.unlock() }
        return draw(pixels: pixels, look: look)
    }

    private struct Palette {
        let ground: (UInt32, UInt32)
        /// Left, right and front leaf: top colour, bottom colour, opacity above 32 px.
        let leaves: [(UInt32, UInt32, CGFloat)]
        let shade: (UInt32, CGFloat)
        /// The tile colour between the leaves, and its width above 32 px and at 32 px and below.
        let gap: UInt32
        let gapWidth: (CGFloat, CGFloat)
    }

    private static func palette(_ look: Look) -> Palette {
        switch look {
        case .light:
            return Palette(ground: (0xFFFFFF, 0xE6E9EE),
                           leaves: [(0x7FE3FF, 0x22B0F0, 0.96), (0xFF9AD8, 0xC04BE8, 0.96), (0x6CCBFF, 0x1680F4, 0.96)],
                           shade: (0x14306E, 0.26), gap: 0xF1F3F6, gapWidth: (14, 28))
        case .dark:
            return Palette(ground: (0x3C3C3F, 0x141415),
                           leaves: [(0x7FE3FF, 0x2AA6F5, 0.92), (0xFF9AD8, 0xC04BE8, 0.92), (0xFFFFFF, 0xE2E6FF, 0.90)],
                           shade: (0x000000, 0.5), gap: 0x29292B, gapWidth: (8, 22))
        }
    }

    private static func draw(pixels: Int, look: Look) -> CGImage? {
        guard pixels > 0, let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(pixels) / canvas
        // At 32 px and below the leaves are opaque, with no frost, and the gaps between them are wider.
        let small = pixels < 64
        let look = palette(look)

        func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: a)
        }
        func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
            CGGradient(colorsSpace: cs, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
        }
        /// Fills `path` with a vertical gradient over its height.
        func fill(_ path: CGPath, _ g: CGGradient) {
            let b = path.boundingBox
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: b.maxY), end: CGPoint(x: 0, y: b.minY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
        /// A shadow `dy` units below `path`, outside it only, so the glass does not show it through.
        func shadow(_ path: CGPath, dy: CGFloat, blur: CGFloat, _ k: CGColor) {
            ctx.saveGState()
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.setShadow(offset: CGSize(width: 0, height: -dy * s), blur: blur * s, color: k)
            ctx.addPath(path)
            ctx.setFillColor(color(0x000000))
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setBlendMode(.clear)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
        /// A feathered light along the inside of `path`, from a copy moved `dy` units.
        func innerGlow(_ path: CGPath, dy: CGFloat, blur: CGFloat, _ k: CGColor) {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.addRect(CGRect(x: -400, y: -400, width: canvas + 800, height: canvas + 800))
            ctx.addPath(path.copy(using: [CGAffineTransform(translationX: 0, y: dy)])!)
            ctx.setShadow(offset: .zero, blur: blur * s, color: k)
            ctx.setFillColor(k)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
        }
        /// The frost: what is drawn so far, blurred and lightened, seen through `path`.
        func frost(_ path: CGPath, radius: CGFloat) {
            guard let snapshot = ctx.makeImage(),
                  let copy = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            copy.draw(snapshot, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            guard let blurred = frosted(copy, radius: radius * s) else { return }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.concatenate(ctx.ctm.inverted())
            ctx.draw(blurred, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            ctx.restoreGState()
        }

        ctx.scaleBy(x: s, y: s)
        ctx.interpolationQuality = .high
        ctx.drawLinearGradient(gradient([(0, color(look.ground.0)), (1, color(look.ground.1))]),
                               start: CGPoint(x: 512, y: canvas), end: CGPoint(x: 512, y: 0), options: [])
        let shade = color(look.shade.0, look.shade.1)
        let gapWidth = small ? look.gapWidth.1 : look.gapWidth.0
        for (i, (leaf, tint)) in zip(leafPaths(small: small), look.leaves).enumerated() {
            if i > 0 {
                // A gap in the tile colour where this leaf lies over the ones behind, outside the leaf only.
                ctx.saveGState()
                ctx.addRect(CGRect(x: -400, y: -400, width: canvas + 800, height: canvas + 800))
                ctx.addPath(leaf)
                ctx.clip(using: .evenOdd)
                ctx.addPath(leaf)
                ctx.setLineWidth(gapWidth * 2)
                ctx.setLineJoin(.round)
                ctx.setStrokeColor(color(look.gap))
                ctx.strokePath()
                ctx.restoreGState()
            }
            let alpha = small ? 1 : tint.2
            shadow(leaf, dy: small ? 8 : 14, blur: small ? 20 : 36, shade)
            if !small { frost(leaf, radius: 20) }
            fill(leaf, gradient([(0, color(tint.0, alpha)), (1, color(tint.1, alpha))]))
            let edge: CGFloat = small ? 0.6 : 0.75
            innerGlow(leaf, dy: -10, blur: 14, color(0xFFFFFF, edge))
            innerGlow(leaf, dy: 7, blur: 9, color(0xFFFFFF, edge * 0.4))
            // A fine rim, bright at the top, fainter at the foot.
            let b = leaf.boundingBox
            ctx.saveGState()
            ctx.addPath(leaf)
            ctx.clip()
            ctx.addPath(leaf)
            ctx.setLineWidth(small ? 20 : 7)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            ctx.drawLinearGradient(gradient([(0, color(0xFFFFFF, 0.95)), (1, color(0xFFFFFF, 0.45))]),
                                   start: CGPoint(x: 0, y: b.maxY), end: CGPoint(x: 0, y: b.minY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    /// The opaque picture in `ctx` blurred by about `radius` pixels (three box passes, edges extended),
    /// a little more saturated, lighter and softer: frosted glass. Plain arithmetic on the CPU, so every
    /// render is the same to the bit, which the picture kept in the repo relies on.
    static func frosted(_ ctx: CGContext, radius: CGFloat) -> CGImage? {
        guard let data = ctx.data else { return nil }
        let width = ctx.width, height = ctx.height, rowBytes = ctx.bytesPerRow
        var a = vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)
        guard let scratch = malloc(rowBytes * height) else { return nil }
        defer { free(scratch) }
        var b = vImage_Buffer(data: scratch, height: a.height, width: a.width, rowBytes: rowBytes)
        let box = UInt32(max(1, Int((radius * 2).rounded()) | 1))
        for i in 0..<3 {
            let flags = vImage_Flags(kvImageEdgeExtend)
            if i % 2 == 0 {
                vImageBoxConvolve_ARGB8888(&a, &b, nil, 0, 0, box, box, nil, flags)
            } else {
                vImageBoxConvolve_ARGB8888(&b, &a, nil, 0, 0, box, box, nil, flags)
            }
        }
        // After three passes the result is in `b`. Saturation 1.15, brightness +0.06, contrast 0.92.
        let px = scratch.assumingMemoryBound(to: UInt8.self)
        @inline(__always) func adjust(_ c: Float, _ luma: Float) -> UInt8 {
            let v = ((luma + (c - luma) * 1.15 + 0.06) - 0.5) * 0.92 + 0.5
            return UInt8(max(0, min(255, (v * 255).rounded())))
        }
        for y in 0..<height {
            var o = y * rowBytes
            for _ in 0..<width {
                let r = Float(px[o]) / 255, g = Float(px[o + 1]) / 255, bl = Float(px[o + 2]) / 255
                let luma = 0.2125 * r + 0.7154 * g + 0.0721 * bl
                px[o] = adjust(r, luma)
                px[o + 1] = adjust(g, luma)
                px[o + 2] = adjust(bl, luma)
                o += 4
            }
        }
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let out = CGContext(data: scratch, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        return out.makeImage()
    }

    /// The picture shrunk into the 824 tile and cut to its continuous corners, clear outside: the Dock
    /// image for a build run outside the bundle, where nothing masks the picture.
    public static func masked(pixels: Int, look: Look = .light) -> CGImage? {
        guard let picture = render(pixels: pixels, look: look), let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(pixels) / canvas
        ctx.scaleBy(x: s, y: s)
        ctx.addPath(tilePath())
        ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(picture, in: base)
        return ctx.makeImage()
    }

    // MARK: Files

    public struct WriteError: Error, CustomStringConvertible {
        public let description: String
    }

    /// Writes the icon at `pixels` as a PNG marked with the DPI of `scale`.
    public static func writePNG(to url: URL, pixels: Int, scale: Int = 1, look: Look = .light) throws {
        guard let image = render(pixels: pixels, look: look) else { throw WriteError(description: "could not draw \(url.lastPathComponent)") }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw WriteError(description: "could not write \(url.path)")
        }
        let dpi = Double(72 * scale)
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw WriteError(description: "could not finish \(url.path)") }
    }

    /// Writes the ten PNGs of Folio.iconset into `dir`; returns them.
    @discardableResult
    public static func writeIconset(to dir: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try iconset.map { entry in
            let url = dir.appendingPathComponent(entry.name)
            try writePNG(to: url, pixels: entry.pixels, scale: entry.scale)
            return url
        }
    }

    /// Writes the Icon Composer file actool compiles into Assets.car: the light and the dark 1024 pictures
    /// as one layer, with the system's own glass, shadow and specular off (the pictures have their own).
    /// macOS 26 shrinks the one picture for the small sizes; Folio.icns keeps the tuned small renders for
    /// older systems.
    public static func writeIconFile(to dir: URL) throws {
        let assets = dir.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try writePNG(to: assets.appendingPathComponent("light.png"), pixels: Int(canvas), look: .light)
        try writePNG(to: assets.appendingPathComponent("dark.png"), pixels: Int(canvas), look: .dark)
        // A plain "image-name" beside the specializations makes actool use it for every appearance.
        let json = """
        {
          "fill" : "none",
          "groups" : [
            {
              "layers" : [
                {
                  "glass" : false,
                  "image-name-specializations" : [
                    { "value" : "light.png" },
                    { "appearance" : "dark", "value" : "dark.png" }
                  ],
                  "name" : "leaves"
                }
              ],
              "shadow" : { "kind" : "none", "opacity" : 0 },
              "specular" : false,
              "translucency" : { "enabled" : false, "value" : 0 }
            }
          ],
          "supported-platforms" : { "squares" : [ "macOS" ] }
        }

        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("icon.json"))
    }
}
