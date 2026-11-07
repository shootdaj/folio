import AppKit
import FolioCore

/// D4's stroke icons (24-unit viewBox, 1.75 stroke, round caps; Lucide shapes, from the `P` table).
enum Glyph: Hashable {
    case back, forward, up, chevron, chevronDown, sort, refresh, search, close
    case sun, moon, star, pc, drive, download, desktop, docs, pics, movies
    // Milestone 3: the copy window's icons, and the command bar's (Lucide, like the rest of the set).
    case copy, pause, play, check, arrow, replace, skip, both, compare, minus
    case cut, paste, rename, trash, newFolder, share, more, sortLines, view
    // Milestone 5: tabs, the navigation pane's places and Home.
    case plus, home, eject, globe, server, link, cloud, clock, mapPin, tabs
    // Milestone 7: the Search options chips (cal, kind, size).
    case calendar, kind, size
    // D4: the sort arrow, the copy window's alert, undo and stop, several selected, and the code folder.
    case sortUp, alert, undo, stop, stack, code

    fileprivate enum Part {
        case path(String)
        case rect(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
        case circle(CGFloat, CGFloat, CGFloat)
    }

    fileprivate var parts: [Part] {
        switch self {
        case .back: [.path("M19 12H5"), .path("m12 19-7-7 7-7")]
        case .forward: [.path("M5 12h14"), .path("m12 5 7 7-7 7")]
        case .up: [.path("M12 19V5"), .path("m5 12 7-7 7 7")]
        case .chevron: [.path("m9 6 6 6-6 6")]
        case .chevronDown: [.path("m6 9 6 6 6-6")]
        case .sort: [.path("m7 14 5-5 5 5")]
        case .refresh: [
            .path("M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"), .path("M21 3v5h-5"),
            .path("M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"), .path("M8 16H3v5"),
        ]
        case .search: [.circle(11, 11, 7), .path("m20 20-3.5-3.5")]
        case .close: [.path("M18 6 6 18"), .path("m6 6 12 12")]
        case .sun: [
            .circle(12, 12, 4),
            .path("M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"),
        ]
        case .moon: [.path("M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z")]
        case .star: [.path("M12 3.5l2.6 5.3 5.9.9-4.25 4.1 1 5.8L12 16.9l-5.25 2.7 1-5.8L3.5 9.7l5.9-.9z")]
        case .pc: [.rect(3, 4, 18, 12, 1.5), .path("M8 20h8M12 16v4")]
        case .drive: [
            .path("M22 12H2"),
            .path("M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"),
            .path("M6 16h.01M10 16h.01"),
        ]
        case .download: [.path("M12 15V3"), .path("m7 10 5 5 5-5"), .path("M5 21h14")]
        case .desktop: [.rect(2, 3, 20, 14, 2), .path("M8 21h8M12 17v4")]
        case .docs: [
            .path("M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"),
            .path("M14 2v4a2 2 0 0 0 2 2h4"), .path("M16 13H8M16 17H8M10 9H8"),
        ]
        case .pics: [.rect(3, 3, 18, 18, 2), .circle(9, 9, 2), .path("m21 15-3.09-3.09a2 2 0 0 0-2.82 0L6 21")]
        case .movies: [.rect(2, 2, 20, 20, 2.18), .path("M7 2v20M17 2v20M2 12h20M2 7h5M2 17h5M17 17h5M17 7h5")]
        case .copy: [.rect(8, 8, 14, 14, 2), .path("M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2")]
        case .pause: [.rect(6, 4, 4, 16, 1), .rect(14, 4, 4, 16, 1)]
        case .play: [.path("M7 4.5v15l12-7.5z")]
        case .check: [.path("M20 6 9 17l-5-5")]
        case .arrow: [.path("M4 12h15"), .path("m13 6 6 6-6 6")]
        case .replace: [.path("M4 7h13l-3-3"), .path("M20 17H7l3 3")]
        case .skip: [.path("m6 5 9 7-9 7z"), .path("M18 5v14")]
        case .both: [.rect(3, 6, 10, 14, 1.5), .path("M8 3h10.5A1.5 1.5 0 0 1 20 4.5V16")]
        case .compare: [.circle(18, 18, 3), .circle(6, 6, 3), .path("M13 6h3a2 2 0 0 1 2 2v7"), .path("M11 18H8a2 2 0 0 1-2-2V9")]
        case .minus: [.path("M5 12h14")]
        case .cut: [.circle(6, 6, 3), .path("M8.12 8.12 12 12"), .path("M20 4 8.12 15.88"), .circle(6, 18, 3),
                    .path("M14.8 14.8 20 20")]
        case .paste: [.rect(8, 2, 8, 4, 1),
                      .path("M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2")]
        case .rename: [.path("M12 20h9"), .path("M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z")]
        case .trash: [.path("M3 6h18"), .path("M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"),
                      .path("M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"), .path("M10 11v6M14 11v6")]
        case .newFolder: [.path("M12 10v6M9 13h6"),
                          .path("M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z")]
        case .share: [.path("M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"), .path("m16 6-4-4-4 4"), .path("M12 2v13")]
        case .more: [.circle(5, 12, 1), .circle(12, 12, 1), .circle(19, 12, 1)]
        case .sortLines: [.path("m21 16-4 4-4-4"), .path("M17 20V4"), .path("m3 8 4-4 4 4"), .path("M7 4v16")]
        case .view: [.path("M3 6h.01M3 12h.01M3 18h.01"), .path("M8 6h13M8 12h13M8 18h13")]
        case .plus: [.path("M12 5v14M5 12h14")]
        case .home: [.path("M3 10.5 12 3l9 7.5"), .path("M5 9v11a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9")]
        case .eject: [.path("m12 5 7 9H5z"), .path("M5 18.5h14")]
        case .globe: [.circle(12, 12, 9), .path("M3 12h18"), .path("M12 3a14 14 0 0 1 0 18a14 14 0 0 1 0-18")]
        case .server: [.rect(3, 4, 18, 7, 1.5), .rect(3, 13, 18, 7, 1.5), .path("M7 7.5h.01M7 16.5h.01")]
        case .link: [.path("M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"),
                     .path("M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71")]
        case .cloud: [.path("M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z")]
        case .clock: [.circle(12, 12, 9), .path("M12 7v5l3 2")]
        case .mapPin: [.path("M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 0 1 16 0Z"), .circle(12, 10, 3)]
        case .tabs: [.rect(3, 6, 18, 14, 1.5), .path("M3 10h18M9 6v4")]
        case .calendar: [.rect(3, 5, 18, 16, 1.5), .path("M3 10h18M8 3v4M16 3v4")]
        case .kind: [.rect(4, 4, 7, 7, 1), .rect(13, 13, 7, 7, 1), .circle(16.5, 7.5, 3.5), .path("m4 20 3.5-6 3.5 6z")]
        case .size: [.path("M4 20V10M10 20V4M16 20v-7M2 20h20")]
        case .sortUp: [.path("M12 19V5"), .path("m6 11 6-6 6 6")]
        case .alert: [.path("m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"), .path("M12 9v4M12 17h.01")]
        case .undo: [.path("M9 14 4 9l5-5"), .path("M4 9h10.5a5.5 5.5 0 0 1 0 11H11")]
        case .stop: [.rect(5, 5, 14, 14, 2)]
        case .stack: [.rect(3, 7, 14, 14, 2), .path("M7 3h12a2 2 0 0 1 2 2v12")]
        case .code: [.path("M10 10.5 8 13l2 2.5"), .path("m14 10.5 2 2.5-2 2.5"),
                     .path("M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z")]
        }
    }

    @MainActor private static var cache: [Glyph: CGPath] = [:]

    @MainActor fileprivate var cgPath: CGPath {
        if let path = Self.cache[self] { return path }
        let path = CGMutablePath()
        for part in parts {
            switch part {
            case .path(let d): path.addSVG(d)
            case .rect(let x, let y, let w, let h, let r):
                path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r)
            case .circle(let cx, let cy, let r):
                path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
            }
        }
        Self.cache[self] = path
        return path
    }

    /// Strokes the glyph into `rect` (square), in either a flipped or unflipped view.
    @MainActor
    func draw(in rect: NSRect, color: NSColor, lineWidth: CGFloat = 1.75, rotation: CGFloat = 0) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.applyViewBox(rect, units: 24, rotation: rotation)
        ctx.addPath(cgPath)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

extension CGMutablePath {
    func addSVG(_ d: String) {
        for element in SVGPath.parse(d) {
            switch element {
            case .move(let p): move(to: p)
            case .line(let p): addLine(to: p)
            case .curve(let c1, let c2, let p): addCurve(to: p, control1: c1, control2: c2)
            case .close: closeSubpath()
            }
        }
    }
}

extension CGContext {
    /// Maps an SVG viewBox (y down, `units` wide) onto `rect`, whatever the view's flippedness.
    @MainActor
    func applyViewBox(_ rect: NSRect, units: CGFloat, unitsHigh: CGFloat? = nil, rotation: CGFloat = 0) {
        let flipped = NSGraphicsContext.current?.isFlipped ?? false
        let scale = min(rect.width / units, rect.height / (unitsHigh ?? units))
        let drawnH = (unitsHigh ?? units) * scale, drawnW = units * scale
        let ox = rect.minX + (rect.width - drawnW) / 2
        if flipped {
            translateBy(x: ox, y: rect.minY + (rect.height - drawnH) / 2)
            scaleBy(x: scale, y: scale)
        } else {
            translateBy(x: ox, y: rect.maxY - (rect.height - drawnH) / 2)
            scaleBy(x: scale, y: -scale)
        }
        if rotation != 0 {
            translateBy(x: units / 2, y: (unitsHigh ?? units) / 2)
            rotate(by: rotation)
            translateBy(x: -units / 2, y: -(unitsHigh ?? units) / 2)
        }
    }
}

/// D4's folder and file glyphs (`.fi`, a 16-unit viewBox), drawn in code from the design's SVG. Each
/// takes its type's neon hue (folders the accent); hovered and selected rows add a soft glow.
@MainActor
enum ItemIcon {
    private static func path(_ d: String) -> CGPath {
        let p = CGMutablePath(); p.addSVG(d); return p
    }
    private static let folderBack = path("M1.75 3.6c0-.55.45-1 1-1h3.03c.3 0 .58.13.77.36l1.03 1.24h5.67c.55 0 1 .45 1 1v6.8c0 .55-.45 1-1 1H2.75c-.55 0-1-.45-1-1z")
    private static let folderFront = path("M1.75 6.4c0-.55.45-1 1-1h10.5c.55 0 1 .45 1 1v5.6c0 .55-.45 1-1 1H2.75c-.55 0-1-.45-1-1z")
    private static let folderLine = path("M3.9 7.6h2.6")
    private static let page = path("M4 1.75h5.1l2.9 2.9v9.6H4z")
    private static let pageFold = path("M9.1 1.75v2.9H12")
    private static let pageLines = path("M6 8.1h4M6 10.6h2.6")

    /// The folder: its back at 40% of the hue, the front tinted 20% over the pane and outlined, a short line.
    static func drawFolder(in rect: NSRect, hue: NSColor, palette p: ThemeColors, glow: Bool = false) {
        withGlow(glow ? hue : nil) { ctx in
            ctx.applyViewBox(rect, units: 16)
            ctx.addPath(folderBack); ctx.setFillColor(hue.withAlpha(0.40).cg); ctx.fillPath()
            ctx.addPath(folderFront); ctx.setFillColor(hue.mixed(0.20, with: p.pane).cg); ctx.fillPath()
            stroke(ctx, folderFront, hue, 1.1)
            ctx.setAlpha(0.85)
            stroke(ctx, folderLine, hue, 1.1)
        }
    }

    /// The accent folder (tabs, the address bar, places without a glyph). `lit` adds the glow.
    static func drawFolder(in rect: NSRect, palette p: ThemeColors, lit: Bool) {
        drawFolder(in: rect, hue: p.accent, palette: p, glow: lit)
    }

    /// The page: tinted 9% of the hue, its outline and fold mixed toward muted, two lines in the hue.
    static func drawFile(in rect: NSRect, hue: NSColor, palette p: ThemeColors, glow: Bool = false) {
        withGlow(glow ? hue : nil) { ctx in
            ctx.applyViewBox(rect, units: 16)
            let edge = hue.mixed(0.62, with: p.muted)
            ctx.addPath(page); ctx.setFillColor(hue.mixed(0.09, with: p.pane).cg); ctx.fillPath()
            stroke(ctx, page, edge, 1.1)
            stroke(ctx, pageFold, edge, 1.1)
            stroke(ctx, pageLines, hue, 1.3)
        }
    }

    /// A file in its type's hue.
    static func drawFile(named name: String, in rect: NSRect, palette p: ThemeColors, glow: Bool = false) {
        drawFile(in: rect, hue: p.typeHue(name: name, isFolder: false), palette: p, glow: glow)
    }

    /// Folder or file for an item, in its hue.
    static func draw(name: String, isFolder: Bool, in rect: NSRect, palette p: ThemeColors, glow: Bool = false) {
        if isFolder {
            drawFolder(in: rect, hue: p.accent, palette: p, glow: glow)
        } else {
            drawFile(named: name, in: rect, palette: p, glow: glow)
        }
    }

    /// Explorer's shortcut arrow on an alias or symbolic link: a small boxed arrow at the icon's corner.
    static func drawLinkBadge(in rect: NSRect, palette p: ThemeColors) {
        fillRounded(rect, radius: max(1.5, rect.width / 6), p.s1)
        strokeRounded(rect, radius: max(1.5, rect.width / 6), p.outline, width: max(0.75, rect.width / 12))
        Glyph.arrow.draw(in: rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12), color: p.accent.ns,
                         lineWidth: rect.width >= 20 ? 2.2 : 3, rotation: -.pi / 4)
    }

    private static func stroke(_ ctx: CGContext, _ path: CGPath, _ color: NSColor, _ width: CGFloat) {
        ctx.addPath(path)
        ctx.setStrokeColor(color.cg)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    /// `filter: drop-shadow(0 0 4px <hue> 55%)` around whatever `body` draws.
    private static func withGlow(_ hue: NSColor?, _ body: (CGContext) -> Void) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        if let hue {
            ctx.setShadow(offset: .zero, blur: 4, color: hue.withAlpha(0.55).cg)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        ctx.saveGState()
        body(ctx)
        ctx.restoreGState()
        if hue != nil { ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }
}

/// Draws `body` with a soft glow of `color` around it (D4's `box-shadow: 0 0 <blur> <colour>`).
@MainActor
func withGlow(_ color: NSColor, blur: CGFloat, _ body: () -> Void) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return body() }
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: blur, color: color.cg)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

/// D4's cursor glow (`.os-row::before`): a radial gradient of `color` at `alpha` from `center`, fading
/// out by 72% of `radius`, clipped to `rect`.
@MainActor
func drawCursorGlow(in rect: NSRect, center: NSPoint, radius: CGFloat = 380, color: NSColor, alpha: Double) {
    guard let ctx = NSGraphicsContext.current?.cgContext,
          let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                    colors: [color.withAlpha(alpha).cg, color.withAlpha(0).cg] as CFArray,
                                    locations: [0, 0.72]) else { return }
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    ctx.restoreGState()
}

/// A left edge bar (`.os-row::after`, `.sitem.on::after`): `width` wide in `color`, glowing.
@MainActor
func drawEdgeBar(_ rect: NSRect, color: NSColor, glowAlpha: Double = 0.6, rounded: Bool = false) {
    withGlow(color.withAlpha(glowAlpha), blur: 14) {
        if rounded {
            let path = NSBezierPath()
            let r = min(3, rect.width)
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX - r, y: rect.minY))
            path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: 270, endAngle: 0)
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - r))
            path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: 0, endAngle: 90)
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.close()
            color.ns.setFill()
            path.fill()
        } else {
            fillRect(rect, color)
        }
    }
}

/// RGBA forms of the helpers, for colours that are not theme tokens (the accent picker's swatches).
@MainActor func withGlow(_ color: RGBA, blur: CGFloat, _ body: () -> Void) { withGlow(color.ns, blur: blur, body) }
@MainActor func fillRounded(_ rect: NSRect, radius: CGFloat, _ color: RGBA) { fillRounded(rect, radius: radius, color.ns) }
@MainActor func strokeRounded(_ rect: NSRect, radius: CGFloat, _ color: RGBA, width: CGFloat = 1) {
    strokeRounded(rect, radius: radius, color.ns, width: width)
}

/// Fills a rect with alpha blending (NSRect.fill() alone copies and punches through).
@MainActor
func fillRect(_ rect: NSRect, _ color: NSColor) {
    color.ns.setFill()
    rect.fill(using: .sourceOver)
}

@MainActor
func fillRounded(_ rect: NSRect, radius: CGFloat, _ color: NSColor) {
    color.ns.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

@MainActor
func strokeRounded(_ rect: NSRect, radius: CGFloat, _ color: NSColor, width: CGFloat = 1) {
    color.ns.setStroke()
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2), xRadius: radius, yRadius: radius)
    path.lineWidth = width
    path.stroke()
}

/// One line of text, vertically centred on `midY` the way CSS centres a line box,
/// truncated with an ellipsis past `maxWidth`. Returns the drawn width.
@MainActor
@discardableResult
func drawLine(_ text: String, font: NSFont, color: NSColor, x: CGFloat, midY: CGFloat, maxWidth: CGFloat = .greatestFiniteMagnitude,
              alignRight: Bool = false, kern: CGFloat = 0) -> CGFloat {
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color.ns]
    if kern != 0 { attrs[.kern] = kern }
    let string = NSAttributedString(string: text, attributes: attrs)
    let width = min(ceil(string.size().width), maxWidth)
    drawAttributed(string, x: alignRight ? x - width : x, midY: midY, width: width, font: font)
    return width
}

@MainActor
func drawAttributed(_ string: NSAttributedString, x: CGFloat, midY: CGFloat, width: CGFloat, font: NSFont) {
    let lineHeight = ceil(font.ascender - font.descender)
    let flipped = NSGraphicsContext.current?.isFlipped ?? false
    let y = flipped ? midY - lineHeight / 2 : midY - lineHeight / 2
    let rect = NSRect(x: x, y: y.rounded(), width: width, height: lineHeight)
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    let s = NSMutableAttributedString(attributedString: string)
    s.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: s.length))
    s.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
}

@MainActor
func textWidth(_ text: String, font: NSFont, kern: CGFloat = 0) -> CGFloat {
    var attrs: [NSAttributedString.Key: Any] = [.font: font]
    if kern != 0 { attrs[.kern] = kern }
    return ceil(NSAttributedString(string: text, attributes: attrs).size().width)
}
