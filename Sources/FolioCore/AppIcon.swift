import CoreGraphics
import Foundation
import ImageIO

/// Folio's app icon: a warm manila folder, a sheet and a blue index tab inside it, on a cool slate tile
/// with the Mac's continuous corners, lit from the top like the system's own icons. macOS 26 shows an
/// icon file as it is only when it fills the icon shape, so the tile is opaque to its edge. One set of
/// numbers drives the iconset `make app` turns into Folio.icns and Resources/AppIcon.png.
public enum AppIcon {
    public static let canvas: CGFloat = 1024
    /// macOS's icon grid: an 824 pt tile inside the 1024 pt canvas.
    static let base = CGRect(x: 100, y: 100, width: 824, height: 824)
    /// The corner radius of the continuous corners (a corner bends over 1.53 radii, as the system's does).
    static let radius: CGFloat = 185
    /// The folder is drawn in its own units and shrunk to 0.9 about this point, which leaves the tile a margin.
    static let folderCentre = CGPoint(x: 512, y: 500)
    static let folderScale: CGFloat = 0.9
    /// A point in the middle of the index tab's visible part (icon units, y up), for the tests.
    static let tabMark = CGPoint(x: 681, y: 634)

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

    /// A rectangle with one radius for its top corners and one for its bottom corners.
    static func panel(_ r: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX + bottom, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - bottom, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + bottom), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - top))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - top), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + bottom, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }

    /// The folder's back with its tab on the left and a sloped shoulder (folder units).
    static func backPath() -> CGPath {
        let l: CGFloat = 168, r: CGFloat = 856, bot: CGFloat = 250, top: CGFloat = 702, tabTop: CGFloat = 796, tabR: CGFloat = 470
        let p = CGMutablePath()
        p.move(to: CGPoint(x: l + 40, y: bot))
        p.addLine(to: CGPoint(x: r - 40, y: bot))
        p.addQuadCurve(to: CGPoint(x: r, y: bot + 40), control: CGPoint(x: r, y: bot))
        p.addLine(to: CGPoint(x: r, y: top - 36))
        p.addQuadCurve(to: CGPoint(x: r - 36, y: top), control: CGPoint(x: r, y: top))
        p.addLine(to: CGPoint(x: tabR + 60, y: top))
        p.addCurve(to: CGPoint(x: tabR, y: tabTop - 16), control1: CGPoint(x: tabR + 30, y: top), control2: CGPoint(x: tabR + 22, y: tabTop - 8))
        p.addQuadCurve(to: CGPoint(x: tabR - 36, y: tabTop), control: CGPoint(x: tabR - 8, y: tabTop))
        p.addLine(to: CGPoint(x: l + 44, y: tabTop))
        p.addQuadCurve(to: CGPoint(x: l, y: tabTop - 44), control: CGPoint(x: l, y: tabTop))
        p.addLine(to: CGPoint(x: l, y: bot + 40))
        p.addQuadCurve(to: CGPoint(x: l + 40, y: bot), control: CGPoint(x: l, y: bot))
        p.closeSubpath()
        return p
    }

    static let frontRect = CGRect(x: 146, y: 196, width: 732, height: 424)
    static let sheetRect = CGRect(x: 218, y: 400, width: 590, height: 340)
    static let tabRect = CGRect(x: 612, y: 560, width: 176, height: 118)

    // MARK: Drawing

    public static func render(pixels: Int) -> CGImage? {
        guard pixels > 0, let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(pixels) / canvas
        // The fine detail (paper sheen, crease, inner rims) is left out where it would only blur.
        let detailed = pixels >= 64
        ctx.scaleBy(x: s, y: s)
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high

        func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: a)
        }
        func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
            CGGradient(colorsSpace: cs, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
        }
        func shadow(_ dy: CGFloat, _ blur: CGFloat, _ a: CGFloat) {
            ctx.setShadow(offset: CGSize(width: 0, height: -dy * s), blur: blur * s, color: color(0x0A1220, a))
        }
        func fill(_ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }

        let tile = tilePath()
        ctx.saveGState()
        ctx.addPath(tile)
        ctx.clip()

        // The tile: slate blue, lighter at the top, a soft glow up top and a little shade at the foot.
        ctx.drawLinearGradient(gradient([(0, color(0x9DB2C9)), (0.5, color(0x6B819C)), (1, color(0x3F5069))]),
                               start: CGPoint(x: 512, y: base.maxY), end: CGPoint(x: 512, y: base.minY), options: [])
        ctx.drawRadialGradient(gradient([(0, color(0xFFFFFF, 0.28)), (1, color(0xFFFFFF, 0))]),
                               startCenter: CGPoint(x: 460, y: 960), startRadius: 0,
                               endCenter: CGPoint(x: 460, y: 960), endRadius: 560, options: [])
        fill(CGPath(rect: base, transform: nil), gradient([(0, color(0x0B1626, 0.30)), (1, color(0x0B1626, 0))]),
             from: CGPoint(x: 0, y: base.minY), to: CGPoint(x: 0, y: 330))

        ctx.saveGState()
        ctx.translateBy(x: folderCentre.x, y: folderCentre.y)
        ctx.scaleBy(x: folderScale, y: folderScale)
        ctx.translateBy(x: -folderCentre.x, y: -folderCentre.y)

        // The folder's back, darker amber, casting a shadow on the tile.
        let back = backPath()
        ctx.saveGState()
        shadow(16, 34, 0.40)
        ctx.addPath(back)
        ctx.setFillColor(color(0xC98A2B))
        ctx.fillPath()
        ctx.restoreGState()
        fill(back, gradient([(0, color(0xE7AE4A)), (1, color(0xB97A22))]), from: CGPoint(x: 0, y: 796), to: CGPoint(x: 0, y: 250))
        ctx.saveGState()
        ctx.addPath(back)
        ctx.clip()
        ctx.setStrokeColor(color(0xFFF1C9, 0.55))
        ctx.setLineWidth(5)
        ctx.addPath(back)
        ctx.strokePath()
        fill(CGPath(rect: CGRect(x: 168, y: 560, width: 700, height: 150), transform: nil),
             gradient([(0, color(0x6E4308, 0)), (1, color(0x6E4308, 0.35))]), from: CGPoint(x: 0, y: 560), to: CGPoint(x: 0, y: 700))
        ctx.restoreGState()

        // A sheet of paper standing in it, turned a little.
        ctx.saveGState()
        ctx.translateBy(x: 512, y: 660)
        ctx.rotate(by: -0.03)
        ctx.translateBy(x: -512, y: -660)
        let sheet = panel(sheetRect, top: 18, bottom: 0)
        ctx.saveGState()
        shadow(6, 14, 0.30)
        ctx.addPath(sheet)
        ctx.setFillColor(color(0xFBF8F0))
        ctx.fillPath()
        ctx.restoreGState()
        fill(sheet, gradient([(0, color(0xFFFFFF)), (1, color(0xE9E4D6))]), from: CGPoint(x: 0, y: 740), to: CGPoint(x: 0, y: 400))
        ctx.restoreGState()

        // The blue index tab behind the front's edge, on the right.
        let tab = panel(tabRect, top: 26, bottom: 0)
        ctx.saveGState()
        shadow(5, 12, 0.35)
        ctx.addPath(tab)
        ctx.setFillColor(color(0x2F7BEF))
        ctx.fillPath()
        ctx.restoreGState()
        fill(tab, gradient([(0, color(0x6FB0FF)), (1, color(0x1F63D6))]), from: CGPoint(x: 0, y: 678), to: CGPoint(x: 0, y: 560))
        if detailed {
            ctx.saveGState()
            ctx.addPath(tab)
            ctx.clip()
            ctx.setStrokeColor(color(0xFFFFFF, 0.5))
            ctx.setLineWidth(3)
            ctx.addPath(tab)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // The manila front, top-lit, with a lit top edge.
        let front = panel(frontRect, top: 44, bottom: 50)
        ctx.saveGState()
        shadow(-14, 36, 0.45)
        ctx.addPath(front)
        ctx.setFillColor(color(0xF3C466))
        ctx.fillPath()
        ctx.restoreGState()
        fill(front, gradient([(0, color(0xFFEBB8)), (0.45, color(0xF9D27E)), (1, color(0xEBA93A))]),
             from: CGPoint(x: 0, y: frontRect.maxY), to: CGPoint(x: 0, y: frontRect.minY))
        ctx.saveGState()
        ctx.addPath(front)
        ctx.clip()
        if detailed {
            // A faint diagonal sheen for paper, and a soft crease.
            ctx.drawLinearGradient(gradient([(0, color(0xFFFFFF, 0)), (0.35, color(0xFFFFFF, 0.16)), (0.7, color(0xFFFFFF, 0)),
                                             (1, color(0x8A5A10, 0.10))]),
                                   start: CGPoint(x: frontRect.minX, y: frontRect.maxY), end: CGPoint(x: frontRect.maxX, y: frontRect.minY), options: [])
            ctx.setFillColor(color(0xA66D12, 0.20))
            ctx.fill(CGRect(x: frontRect.minX, y: 316, width: frontRect.width, height: 8))
            ctx.setFillColor(color(0xFFF4D2, 0.45))
            ctx.fill(CGRect(x: frontRect.minX, y: 308, width: frontRect.width, height: 6))
        }
        fill(CGPath(rect: CGRect(x: frontRect.minX, y: frontRect.minY, width: frontRect.width, height: 70), transform: nil),
             gradient([(0, color(0x8A5208, 0.30)), (1, color(0x8A5208, 0))]),
             from: CGPoint(x: 0, y: frontRect.minY), to: CGPoint(x: 0, y: frontRect.minY + 70))
        ctx.setStrokeColor(color(0xFFFFFF, 0.85))
        ctx.setLineWidth(7)
        ctx.addPath(front)
        ctx.strokePath()
        ctx.restoreGState()
        if detailed {
            ctx.saveGState()
            ctx.addPath(front)
            ctx.clip()
            ctx.setStrokeColor(color(0xB87818, 0.35))
            ctx.setLineWidth(4)
            ctx.translateBy(x: 0, y: -4)
            ctx.addPath(front)
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.restoreGState()

        // The tile's rim: light along the top, a little dark along the foot.
        ctx.setLineWidth(6)
        ctx.addPath(tile)
        ctx.replacePathWithStrokedPath()
        if let rim = ctx.path {
            ctx.beginPath()
            ctx.saveGState()
            ctx.addPath(rim)
            ctx.clip()
            ctx.drawLinearGradient(gradient([(0, color(0xFFFFFF, 0.55)), (0.35, color(0xFFFFFF, 0.08)), (1, color(0x000000, 0.25))]),
                                   start: CGPoint(x: 0, y: base.maxY), end: CGPoint(x: 0, y: base.minY), options: [])
            ctx.restoreGState()
        }
        ctx.restoreGState()
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
