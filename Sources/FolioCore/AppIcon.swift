import Accelerate
import CoreGraphics
import Foundation
import ImageIO

/// Folio's app icon: a frosted white glass folder on a cyan-to-blue ground. Two sheets stand in the folder
/// and show softly blurred through its glass front, as the system's own glass icons do.
///
/// macOS 26 puts an icon in a grey frame at 16 and 32 px when its picture leaves part of the square clear,
/// so the picture is full bleed: opaque to every edge. macOS cuts its own continuous-corner shape, shrinks
/// the square into its icon grid and adds the glass rim and the shadow. One set of numbers drives the
/// iconset `make app` turns into Folio.icns and Resources/AppIcon.png.
public enum AppIcon {
    public static let canvas: CGFloat = 1024
    /// macOS's icon grid: an 824 pt tile inside the 1024 pt canvas (for `masked(pixels:)`).
    static let base = CGRect(x: 100, y: 100, width: 824, height: 824)
    /// The corner radius of the continuous corners (a corner bends over 1.53 radii, as the system's does).
    static let radius: CGFloat = 185
    /// The folder is drawn in its own units and enlarged by `folderScale` about `folderCentre`, which
    /// keeps it inside the middle of the square that macOS's corners do not cut.
    static let folderCentre = CGPoint(x: 512, y: 517)
    static let folderScale: CGFloat = 1.10
    /// Points on the canvas (y up) for the tests: on the glass front, and on the front sheet above it.
    static let glassMark = CGPoint(x: 400, y: 440)
    static let sheetMark = CGPoint(x: 741, y: 779)

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

    /// A polygon whose corners each have their own radius: (x, y, radius).
    static func roundedPolygon(_ pts: [(CGFloat, CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        let points = pts.map { CGPoint(x: $0.0, y: $0.1) }
        let last = points[points.count - 1], first = points[0]
        p.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for i in points.indices {
            p.addArc(tangent1End: points[i], tangent2End: points[(i + 1) % points.count], radius: pts[i].2)
        }
        p.closeSubpath()
        return p
    }

    static let backBottom: CGFloat = 226, backTop: CGFloat = 870

    /// The folder's back (folder units): a round tab on the left with one smooth S shoulder.
    static func backPath() -> CGPath {
        let l: CGFloat = 168, r: CGFloat = 868, bot = backBottom, top: CGFloat = 740, tabTop = backTop
        let p = CGMutablePath()
        p.move(to: CGPoint(x: l + 72, y: bot))
        p.addLine(to: CGPoint(x: r - 72, y: bot))
        p.addArc(tangent1End: CGPoint(x: r, y: bot), tangent2End: CGPoint(x: r, y: top), radius: 72)
        p.addArc(tangent1End: CGPoint(x: r, y: top), tangent2End: CGPoint(x: l, y: top), radius: 60)
        p.addLine(to: CGPoint(x: 734, y: top))
        p.addCurve(to: CGPoint(x: 440, y: tabTop), control1: CGPoint(x: 624, y: top), control2: CGPoint(x: 556, y: tabTop))
        p.addArc(tangent1End: CGPoint(x: l, y: tabTop), tangent2End: CGPoint(x: l, y: bot), radius: 104)
        p.addArc(tangent1End: CGPoint(x: l, y: bot), tangent2End: CGPoint(x: r, y: bot), radius: 72)
        p.closeSubpath()
        return p
    }

    /// The glass front (folder units).
    static func frontPath() -> CGPath {
        roundedPolygon([(146, 186, 74), (878, 186, 74), (878, 604, 66), (146, 604, 66)])
    }

    // MARK: Drawing

    /// Core Graphics' shadow blur gives slightly different pixels when two renders run at once (tested:
    /// up to 119 levels on 16 threads), and the picture kept in the repo must be the one the renderer draws.
    private static let renderLock = NSLock()

    /// The full-bleed picture at `pixels` square: what the iconset holds.
    public static func render(pixels: Int) -> CGImage? {
        renderLock.lock()
        defer { renderLock.unlock() }
        return draw(pixels: pixels)
    }

    private static func draw(pixels: Int) -> CGImage? {
        guard pixels > 0, let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        func newContext() -> CGContext? {
            CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let ctx = newContext() else { return nil }
        let s = CGFloat(pixels) / canvas
        // The fine detail (sheets, sheen, frost, side light) is left out where it would only blur.
        let detailed = pixels >= 64

        func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: a)
        }
        func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
            CGGradient(colorsSpace: cs, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
        }
        /// Fills `path` with a vertical gradient from y0 (first stop) to y1 (last stop).
        func fill(_ c: CGContext, _ path: CGPath, _ g: CGGradient, _ y0: CGFloat, _ y1: CGFloat) {
            c.saveGState()
            c.addPath(path)
            c.clip()
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1),
                                 options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            c.restoreGState()
        }
        /// Fills `path` with `fill` and a navy shadow `dy` units below it.
        func shadowed(_ c: CGContext, _ path: CGPath, dy: CGFloat, blur: CGFloat, alpha: CGFloat, fill: CGColor) {
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -dy * s), blur: blur * s, color: color(0x021C6B, alpha))
            c.addPath(path)
            c.setFillColor(fill)
            c.fillPath()
            c.restoreGState()
        }
        /// An inner light or shadow: a feathered sliver along the inside of `path`, from a copy moved by (dx, dy).
        func innerGlow(_ c: CGContext, _ path: CGPath, dx: CGFloat = 0, dy: CGFloat, blur: CGFloat, glow: CGColor, sliver: CGColor) {
            c.saveGState()
            c.addPath(path)
            c.clip()
            c.addRect(CGRect(x: -200, y: -200, width: canvas + 476, height: canvas + 476))
            c.addPath(path.copy(using: [CGAffineTransform(translationX: dx, y: dy)])!)
            c.setShadow(offset: .zero, blur: blur * s, color: glow)
            c.setFillColor(sliver)
            c.fillPath(using: .evenOdd)
            c.restoreGState()
        }
        func enlargeFolder(_ c: CGContext) {
            c.translateBy(x: 512, y: 512)
            c.scaleBy(x: folderScale, y: folderScale)
            c.translateBy(x: -folderCentre.x, y: -folderCentre.y)
        }

        // What lies behind the glass front: the ground, the folder's back and the sheets. It is drawn once
        // into the icon and once more off screen, where it is blurred for the frost.
        func scene(_ c: CGContext) {
            c.saveGState()
            c.scaleBy(x: s, y: s)
            c.interpolationQuality = .high
            c.drawLinearGradient(gradient([(0, color(0x2FD0FF)), (0.42, color(0x0C8EFF)), (1, color(0x0452F0))]),
                                 start: CGPoint(x: 512, y: canvas), end: CGPoint(x: 512, y: 0), options: [])
            c.drawRadialGradient(gradient([(0, color(0xFFFFFF, 0.34)), (1, color(0xFFFFFF, 0))]),
                                 startCenter: CGPoint(x: 380, y: 1010), startRadius: 0,
                                 endCenter: CGPoint(x: 380, y: 1010), endRadius: 720, options: [])
            enlargeFolder(c)

            // The back: tinted glass over the sky, with a warm white top edge.
            let back = backPath()
            shadowed(c, back, dy: 16, blur: 36, alpha: 0.38, fill: color(0xFFFFFF, 0.3))
            if detailed {
                fill(c, back, gradient([(0, color(0xFFFFFF, 0.70)), (0.5, color(0xBFE3FF, 0.55)), (1, color(0x7CC4FF, 0.45))]),
                     backTop, backBottom)
                // Frost: a diagonal sheen, a warm haze, a cool underside and a fine speckle.
                c.saveGState()
                c.addPath(back)
                c.clip()
                c.drawLinearGradient(gradient([(0, color(0xFFFFFF, 0)), (0.3, color(0xFFFFFF, 0.28)), (0.6, color(0xFFFFFF, 0))]),
                                     start: CGPoint(x: 168, y: backTop), end: CGPoint(x: 700, y: backBottom), options: [])
                c.drawRadialGradient(gradient([(0, color(0xFFF8EC, 0.30)), (1, color(0xFFF8EC, 0))]),
                                     startCenter: CGPoint(x: 330, y: 828), startRadius: 0,
                                     endCenter: CGPoint(x: 330, y: 828), endRadius: 300, options: [])
                c.restoreGState()
                innerGlow(c, back, dy: 40, blur: 40, glow: color(0x1E6FE0, 0.35), sliver: color(0x1E6FE0, 0))
                c.saveGState()
                c.addPath(back)
                c.clip()
                c.setFillColor(color(0xFFFFFF, 0.10))
                var seed: UInt64 = 7
                for _ in 0..<900 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    c.fill(CGRect(x: 168 + CGFloat((seed >> 33) % 700), y: backBottom + CGFloat((seed >> 17) % 644),
                                  width: 2.4, height: 2.4))
                }
                c.restoreGState()
            } else {
                fill(c, back, gradient([(0, color(0xCDEBFF)), (1, color(0x7CC0FF))]), backTop, backBottom)
            }
            innerGlow(c, back, dy: -7, blur: 9, glow: color(0xFFF9EE, 0.9), sliver: color(0xFFF9EE, 0.9))

            if detailed {
                // Two sheets, a pale blue one behind and a white one in front, standing above the glass.
                c.saveGState()
                c.translateBy(x: 512, y: 540)
                c.rotate(by: 0.05)
                c.translateBy(x: -512, y: -540)
                let behind = roundedPolygon([(290, 360, 0), (520, 360, 0), (520, 806, 28), (290, 806, 28)])
                shadowed(c, behind, dy: 8, blur: 22, alpha: 0.28, fill: color(0xFFFFFF, 0.9))
                fill(c, behind, gradient([(0, color(0xDDF4FF)), (1, color(0x9CD6FF))]), 806, 360)
                c.restoreGState()
                c.saveGState()
                c.translateBy(x: 512, y: 540)
                c.rotate(by: -0.012)
                c.translateBy(x: -512, y: -540)
                let front = roundedPolygon([(598, 360, 0), (838, 360, 0), (838, 826, 28), (598, 826, 28)])
                shadowed(c, front, dy: 9, blur: 24, alpha: 0.32, fill: color(0xFFFFFF, 0.95))
                fill(c, front, gradient([(0, color(0xFFFFFF)), (1, color(0xCFE9FF))]), 826, 360)
                innerGlow(c, front, dy: -4, blur: 4, glow: color(0xFFFFFF, 0.9), sliver: color(0xFFFFFF, 0.9))
                c.restoreGState()
            } else if pixels >= 32 {
                // One bold sheet keeps the folder's outline at 32 px.
                let sheet = roundedPolygon([(590, 400, 0), (840, 400, 0), (840, 826, 40), (590, 826, 40)])
                fill(c, sheet, gradient([(0, color(0xFFFFFF)), (1, color(0xD6ECFF))]), 826, 400)
            }
            c.restoreGState()
        }

        scene(ctx)

        // The glass front.
        ctx.saveGState()
        ctx.scaleBy(x: s, y: s)
        enlargeFolder(ctx)
        let front = frontPath()
        let frame = front.boundingBox
        // A soft shadow on the layers behind.
        shadowed(ctx, front, dy: -4, blur: 8, alpha: 0.85, fill: color(0xFFFFFF, 0.5))
        shadowed(ctx, front, dy: -14, blur: 44, alpha: 0.62, fill: color(0xFFFFFF, 0.5))
        if !detailed { shadowed(ctx, front, dy: 14, blur: 12, alpha: 0.55, fill: color(0xFFFFFF, 0.5)) }
        // The frost: the scene blurred and lightened, seen through the glass.
        if let behind = newContext() {
            scene(behind)
            if let frost = frosted(behind, radius: 30 * s) {
                ctx.saveGState()
                ctx.addPath(front)
                ctx.clip()
                ctx.concatenate(ctx.ctm.inverted())
                ctx.draw(frost, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
                ctx.restoreGState()
            }
        }
        // The glass's tint: warm milky white at the top, cooler and clearer toward the foot.
        fill(ctx, front, gradient([(0, color(0xFFFCF4, 0.66)), (0.35, color(0xEEF8FF, 0.42)), (0.75, color(0xB4DAFF, 0.26)),
                                   (1, color(0x8EC4FF, 0.26))]), frame.maxY, frame.minY)
        if detailed {
            ctx.saveGState()
            ctx.addPath(front)
            ctx.clip()
            ctx.drawLinearGradient(gradient([(0, color(0xFFFFFF, 0)), (0.35, color(0xFFFFFF, 0.30)), (0.65, color(0xFFFFFF, 0))]),
                                   start: CGPoint(x: frame.minX, y: frame.maxY), end: CGPoint(x: frame.maxX * 0.75, y: frame.minY), options: [])
            ctx.restoreGState()
            // Deeper where the glass thickens at the foot; a feathered top edge, a lit lower lip, lit sides.
            innerGlow(ctx, front, dy: 30, blur: 36, glow: color(0x1156D0, 0.55), sliver: color(0x1156D0, 0))
            innerGlow(ctx, front, dy: -10, blur: 16, glow: color(0xFFFAEE, 0.95), sliver: color(0xFFFAEE, 0.95))
            innerGlow(ctx, front, dy: 8, blur: 9, glow: color(0xFFFFFF, 0.55), sliver: color(0xFFFFFF, 0.55))
            innerGlow(ctx, front, dx: 7, dy: 0, blur: 8, glow: color(0xFFFFFF, 0.35), sliver: color(0xFFFFFF, 0.3))
        } else {
            innerGlow(ctx, front, dy: -12, blur: 8, glow: color(0xFFFFFF), sliver: color(0xFFFFFF))
            innerGlow(ctx, front, dy: 22, blur: 24, glow: color(0x1773E6, 0.4), sliver: color(0x1773E6, 0))
        }
        // A fine rim: bright at the top, fainter in the middle.
        ctx.saveGState()
        ctx.addPath(front)
        ctx.setLineWidth(detailed ? 4 : 8)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(gradient([(0, color(0xFFFFFF)), (0.55, color(0xFFFFFF, 0.5)), (1, color(0xFFFFFF, 0.75))]),
                               start: CGPoint(x: 0, y: frame.maxY), end: CGPoint(x: 0, y: frame.minY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
        ctx.restoreGState()
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
        for y in 0..<height {
            for x in 0..<width {
                let o = y * rowBytes + x * 4
                let r = Float(px[o]) / 255, g = Float(px[o + 1]) / 255, bl = Float(px[o + 2]) / 255
                let luma = 0.2125 * r + 0.7154 * g + 0.0721 * bl
                for (k, c) in [r, g, bl].enumerated() {
                    let v = ((luma + (c - luma) * 1.15 + 0.06) - 0.5) * 0.92 + 0.5
                    px[o + k] = UInt8(max(0, min(255, (v * 255).rounded())))
                }
            }
        }
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let out = CGContext(data: scratch, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        return out.makeImage()
    }

    /// The picture shrunk into the 824 tile and cut to its continuous corners, clear outside: the Dock
    /// image for a build run outside the bundle, where nothing masks the picture.
    public static func masked(pixels: Int) -> CGImage? {
        guard let picture = render(pixels: pixels), let cs = CGColorSpace(name: CGColorSpace.sRGB),
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
    public static func writePNG(to url: URL, pixels: Int, scale: Int = 1) throws {
        guard let image = render(pixels: pixels) else { throw WriteError(description: "could not draw \(url.lastPathComponent)") }
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
}
