import CoreGraphics
import Foundation
import ImageIO

/// Folio's app icon in D1's language: the near-black rounded square with the sidebar's blueprint grid,
/// the accent corner brackets of a selected item, and D1's folder (its tab in the accent) with a
/// phosphor light glowing on its front. Dark is the Dock icon; light is drawn for a light Mac. One set
/// of numbers drives both the CoreGraphics drawing (the iconset `make app` turns into Folio.icns) and
/// the SVG in Resources/.
public enum AppIcon {
    public static let canvas: CGFloat = 1024
    /// macOS's icon grid: an 824 pt rounded square inside the 1024 pt canvas.
    static let base = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let radius: CGFloat = 185
    /// D1's folder (viewBox 0 0 20 16), 26 times its size, centred a little low.
    static let folderOrigin = CGPoint(x: 252, y: 315.5)
    static let folderScale: CGFloat = 26
    static let backPath = "M1.5 3a1 1 0 0 1 1-1h4.8l1.7 2h8.5a1 1 0 0 1 1 1v8.5a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1z"
    static let tabPath = "M2.5 2h4.8l1.7 2H1.5V3a1 1 0 0 1 1-1z"
    static let frontPath = "M1.5 6.2h17v7.3a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1z"
    static let folderStroke: CGFloat = 0.5
    /// The phosphor light on the folder's front (where D1's folder has its line), in folder units.
    static let light = CGPoint(x: 14.9, y: 10.35)
    static let lightR: CGFloat = 1.05
    static let ringR: CGFloat = 1.7
    /// The brackets around the folder, as D1 marks a selected item.
    static let bracketBox = CGRect(x: 243, y: 320, width: 538, height: 420)
    static let bracketArm: CGFloat = 70
    static let bracketWidth: CGFloat = 12
    static let glowBlur: CGFloat = 40

    /// The iconset iconutil wants: file name and pixel size.
    public static let iconset: [(name: String, pixels: Int, scale: Int)] = [16, 32, 128, 256, 512].flatMap { pt in
        [("icon_\(pt)x\(pt).png", pt, 1), ("icon_\(pt)x\(pt)@2x.png", pt * 2, 2)]
    }

    struct Colors {
        var top, bottom, hairline, gridMinor, gridMajor, bracket, accent, back, front, line: RGBA
        var glows: Bool
    }

    static func colors(_ appearance: Appearance) -> Colors {
        let p = Theme.palette(appearance, accent: .green)
        let dark = appearance == .dark
        return Colors(top: dark ? p.s2 : p.s1, bottom: p.bg, hairline: p.line,
                      gridMinor: p.accent.withAlpha(dark ? 0.05 : 0.06), gridMajor: p.accent.withAlpha(dark ? 0.11 : 0.12),
                      bracket: p.accent.withAlpha(0.70), accent: p.accent,
                      back: p.foldBack, front: p.foldFront, line: p.foldLine, glows: p.glows)
    }

    /// The light's centre at a pixel size, from the top left.
    public static func lightCentre(pixels: Int) -> (Int, Int) {
        let s = CGFloat(pixels) / canvas
        let x = (folderOrigin.x + light.x * folderScale) * s, y = (folderOrigin.y + light.y * folderScale) * s
        return (Int(x.rounded()), Int(y.rounded()))
    }

    // MARK: Drawing

    public static func render(pixels: Int, appearance: Appearance) -> CGImage? {
        guard pixels > 0, let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(pixels) / canvas
        let c = colors(appearance)
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        // SVG coordinates: 1024 units, y down.
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: 0, y: canvas)
        ctx.scaleBy(x: 1, y: -1)

        let square = CGPath(roundedRect: base, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.addPath(square)
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: cs, colors: [cg(c.top), cg(c.bottom)] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: base.minY), end: CGPoint(x: 0, y: base.maxY), options: [])
        }
        if pixels >= 64 {
            for (step, color) in [(CGFloat(32), c.gridMinor), (CGFloat(128), c.gridMajor)] {
                ctx.setFillColor(cg(color))
                var v = base.minX + step
                while v < base.maxX {
                    ctx.fill(CGRect(x: v - 1, y: base.minY, width: 2, height: base.height))
                    ctx.fill(CGRect(x: base.minX, y: v - 1, width: base.width, height: 2))
                    v += step
                }
            }
        }
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: base.insetBy(dx: 2, dy: 2), cornerWidth: radius - 2, cornerHeight: radius - 2, transform: nil))
        ctx.setStrokeColor(cg(c.hairline))
        ctx.setLineWidth(4)
        ctx.strokePath()

        if pixels >= 32 {
            ctx.setFillColor(cg(c.bracket))
            for r in bracketRects() { ctx.fill(r) }
        }

        let t = CGAffineTransform(translationX: folderOrigin.x, y: folderOrigin.y).scaledBy(x: folderScale, y: folderScale)
        func shape(_ d: String) -> CGPath { cgPath(d, transform: t) }
        let stroke = max(folderStroke * folderScale, 1 / s)
        ctx.addPath(shape(backPath))
        ctx.setFillColor(cg(c.back))
        ctx.setStrokeColor(cg(c.line))
        ctx.setLineWidth(stroke)
        ctx.drawPath(using: .fillStroke)
        ctx.saveGState()
        if c.glows { ctx.setShadow(offset: .zero, blur: glowBlur * s, color: cg(c.accent.withAlpha(0.62))) }
        ctx.addPath(shape(tabPath))
        ctx.setFillColor(cg(c.accent))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(shape(frontPath))
        ctx.setFillColor(cg(c.front))
        ctx.setStrokeColor(cg(c.line))
        ctx.setLineWidth(stroke)
        ctx.drawPath(using: .fillStroke)

        let centre = light.applying(t)
        let ring = ringR * folderScale, dot = lightR * folderScale
        ctx.setFillColor(cg(c.accent.withAlpha(0.18)))
        ctx.fillEllipse(in: CGRect(x: centre.x - ring, y: centre.y - ring, width: ring * 2, height: ring * 2))
        ctx.saveGState()
        if c.glows { ctx.setShadow(offset: .zero, blur: glowBlur * s, color: cg(c.accent.withAlpha(0.62))) }
        ctx.setFillColor(cg(c.accent))
        ctx.fillEllipse(in: CGRect(x: centre.x - dot, y: centre.y - dot, width: dot * 2, height: dot * 2))
        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// The eight bars of the four corner brackets.
    static func bracketRects() -> [CGRect] {
        let b = bracketBox, a = bracketArm, w = bracketWidth
        return [
            CGRect(x: b.minX, y: b.minY, width: a, height: w), CGRect(x: b.minX, y: b.minY, width: w, height: a),
            CGRect(x: b.maxX - a, y: b.minY, width: a, height: w), CGRect(x: b.maxX - w, y: b.minY, width: w, height: a),
            CGRect(x: b.minX, y: b.maxY - w, width: a, height: w), CGRect(x: b.minX, y: b.maxY - a, width: w, height: a),
            CGRect(x: b.maxX - a, y: b.maxY - w, width: a, height: w), CGRect(x: b.maxX - w, y: b.maxY - a, width: w, height: a),
        ]
    }

    private static func cg(_ c: RGBA) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a) }

    private static func cgPath(_ d: String, transform t: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        for e in SVGPath.parse(d) {
            switch e {
            case .move(let p): path.move(to: p, transform: t)
            case .line(let p): path.addLine(to: p, transform: t)
            case .curve(let a, let b, let p): path.addCurve(to: p, control1: a, control2: b, transform: t)
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    // MARK: Files

    public struct WriteError: Error, CustomStringConvertible {
        public let description: String
    }

    /// Writes the ten PNGs of Folio.iconset (the dark icon) into `dir`; returns them.
    @discardableResult
    public static func writeIconset(to dir: URL, appearance: Appearance = .dark) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try iconset.map { entry in
            guard let image = render(pixels: entry.pixels, appearance: appearance) else {
                throw WriteError(description: "could not draw \(entry.name)")
            }
            let url = dir.appendingPathComponent(entry.name)
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
                throw WriteError(description: "could not write \(url.path)")
            }
            let dpi = Double(72 * entry.scale)
            CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw WriteError(description: "could not finish \(url.path)") }
            return url
        }
    }

    // MARK: SVG

    /// The same icon as SVG (Resources/AppIcon.svg and AppIcon-light.svg).
    public static func svg(_ appearance: Appearance) -> String {
        let c = colors(appearance)
        func n(_ v: CGFloat) -> String {
            let r = (v * 100).rounded() / 100
            return r == r.rounded() ? String(Int(r)) : String(format: "%.2f", Double(r)).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
        }
        func fill(_ color: RGBA) -> String {
            color.a == 1 ? "fill=\"\(color.hex)\"" : "fill=\"\(color.hex)\" fill-opacity=\"\(n(CGFloat(color.a)))\""
        }
        var lines: [String] = []
        lines.append("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" width=\"1024\" height=\"1024\">")
        lines.append("  <title>Folio</title>")
        lines.append("  <defs>")
        lines.append("    <linearGradient id=\"bg\" x1=\"0\" y1=\"\(n(base.minY))\" x2=\"0\" y2=\"\(n(base.maxY))\" gradientUnits=\"userSpaceOnUse\">")
        lines.append("      <stop offset=\"0\" stop-color=\"\(c.top.hex)\"/><stop offset=\"1\" stop-color=\"\(c.bottom.hex)\"/>")
        lines.append("    </linearGradient>")
        lines.append("    <clipPath id=\"sq\"><rect x=\"\(n(base.minX))\" y=\"\(n(base.minY))\" width=\"\(n(base.width))\" height=\"\(n(base.height))\" rx=\"\(n(radius))\"/></clipPath>")
        if c.glows {
            lines.append("    <filter id=\"glow\" x=\"-60%\" y=\"-60%\" width=\"220%\" height=\"220%\">")
            lines.append("      <feGaussianBlur in=\"SourceGraphic\" stdDeviation=\"\(n(glowBlur / 2 / folderScale))\" result=\"b\"/>")
            lines.append("      <feComponentTransfer in=\"b\" result=\"g\"><feFuncA type=\"linear\" slope=\"0.62\"/></feComponentTransfer>")
            lines.append("      <feMerge><feMergeNode in=\"g\"/><feMergeNode in=\"SourceGraphic\"/></feMerge>")
            lines.append("    </filter>")
        }
        lines.append("  </defs>")
        lines.append("  <rect x=\"\(n(base.minX))\" y=\"\(n(base.minY))\" width=\"\(n(base.width))\" height=\"\(n(base.height))\" rx=\"\(n(radius))\" fill=\"url(#bg)\"/>")
        lines.append("  <g clip-path=\"url(#sq)\">")
        for (step, color) in [(CGFloat(32), c.gridMinor), (CGFloat(128), c.gridMajor)] {
            var v = base.minX + step
            var rects: [String] = []
            while v < base.maxX {
                rects.append("<rect x=\"\(n(v - 1))\" y=\"\(n(base.minY))\" width=\"2\" height=\"\(n(base.height))\"/>")
                rects.append("<rect x=\"\(n(base.minX))\" y=\"\(n(v - 1))\" width=\"\(n(base.width))\" height=\"2\"/>")
                v += step
            }
            lines.append("    <g \(fill(color))>" + rects.joined() + "</g>")
        }
        lines.append("  </g>")
        let inner = base.insetBy(dx: 2, dy: 2)
        lines.append("  <rect x=\"\(n(inner.minX))\" y=\"\(n(inner.minY))\" width=\"\(n(inner.width))\" height=\"\(n(inner.height))\" rx=\"\(n(radius - 2))\" fill=\"none\" stroke=\"\(c.hairline.hex)\" stroke-opacity=\"\(n(CGFloat(c.hairline.a)))\" stroke-width=\"4\"/>")
        lines.append("  <g \(fill(c.bracket))>" + bracketRects().map {
            "<rect x=\"\(n($0.minX))\" y=\"\(n($0.minY))\" width=\"\(n($0.width))\" height=\"\(n($0.height))\"/>"
        }.joined() + "</g>")
        lines.append("  <g transform=\"translate(\(n(folderOrigin.x)) \(n(folderOrigin.y))) scale(\(n(folderScale)))\" stroke-linejoin=\"round\">")
        lines.append("    <path d=\"\(backPath)\" fill=\"\(c.back.hex)\" stroke=\"\(c.line.hex)\" stroke-width=\"\(n(folderStroke))\"/>")
        lines.append("    <path d=\"\(tabPath)\" fill=\"\(c.accent.hex)\"" + (c.glows ? " filter=\"url(#glow)\"" : "") + "/>")
        lines.append("    <path d=\"\(frontPath)\" fill=\"\(c.front.hex)\" stroke=\"\(c.line.hex)\" stroke-width=\"\(n(folderStroke))\"/>")
        lines.append("    <circle cx=\"\(n(light.x))\" cy=\"\(n(light.y))\" r=\"\(n(ringR))\" fill=\"\(c.accent.hex)\" fill-opacity=\"0.18\"/>")
        lines.append("    <circle cx=\"\(n(light.x))\" cy=\"\(n(light.y))\" r=\"\(n(lightR))\" fill=\"\(c.accent.hex)\"" + (c.glows ? " filter=\"url(#glow)\"" : "") + "/>")
        lines.append("  </g>")
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }
}
