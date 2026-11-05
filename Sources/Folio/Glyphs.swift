import AppKit
import FolioCore

/// D1's stroke icons (24-unit viewBox, 1.75 stroke, round caps), from the `I` table in the design.
enum Glyph: Hashable {
    case back, forward, up, chevron, chevronDown, sort, refresh, search, close
    case sun, moon, star, pc, drive, download, desktop, docs, pics, movies
    // Milestone 3: D1's copy window icons, and the command bar's (Lucide, like the rest of D1's set).
    case copy, pause, play, check, arrow, replace, skip, both, compare, minus
    case cut, paste, rename, trash, newFolder, share, more, sortLines, view
    // Milestone 5: tabs, the navigation pane's places and Home.
    case plus, home, eject, globe, server, link, cloud, clock, mapPin, tabs

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
        case .download: [.path("M12 4v11"), .path("m7 10 5 5 5-5"), .path("M20 15v4a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-4")]
        case .desktop: [.rect(2.5, 3.5, 19, 13, 1.5), .path("M8 20.5h8M12 16.5v4")]
        case .docs: [
            .path("M14 2.5H6.5A1.5 1.5 0 0 0 5 4v16a1.5 1.5 0 0 0 1.5 1.5h11A1.5 1.5 0 0 0 19 20V7.5z"),
            .path("M14 2.5v5h5M9 13h6M9 17h6"),
        ]
        case .pics: [.rect(3, 3, 18, 18, 2), .circle(9, 9, 2), .path("m21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21")]
        case .movies: [.rect(3, 3, 18, 18, 2), .path("M7 3v18M17 3v18M3 7.5h4M3 12h18M3 16.5h4M17 7.5h4M17 16.5h4")]
        case .copy: [.rect(8, 8, 13, 13, 2), .path("M4 16a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2")]
        case .pause: [.path("M9 5v14M15 5v14")]
        case .play: [.path("M7 4.5v15l12-7.5z")]
        case .check: [.path("M20 6 9 17l-5-5")]
        case .arrow: [.path("M4 12h15"), .path("m13 6 6 6-6 6")]
        case .replace: [.path("M4 7h13l-3-3"), .path("M20 17H7l3 3")]
        case .skip: [.path("m6 5 9 7-9 7z"), .path("M18 5v14")]
        case .both: [.rect(3, 6, 10, 14, 1.5), .path("M8 3h10.5A1.5 1.5 0 0 1 20 4.5V16")]
        case .compare: [.rect(3, 4, 18, 16, 1.5), .path("M12 4v16")]
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

/// D1's folder and file icons, drawn in code from the design's SVG.
@MainActor
enum ItemIcon {
    private static func path(_ d: String) -> CGPath {
        let p = CGMutablePath(); p.addSVG(d); return p
    }
    private static let folderBack = path("M1.5 3a1 1 0 0 1 1-1h4.8l1.7 2h8.5a1 1 0 0 1 1 1v8.5a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1z")
    private static let folderTab = path("M2.5 2h4.8l1.7 2H1.5V3a1 1 0 0 1 1-1z")
    private static let folderFront = path("M1.5 6.2h17v7.3a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1z")
    private static let folderSlot = path("M13.4 9.6h3")
    private static let page = path("M3.2 1.5h5.9l3.7 3.7v9.3H3.2z")
    private static let pageFold = path("M9.1 1.5v3.7h3.7")
    private static let badge = CGPath(roundedRect: CGRect(x: 5, y: 9.2, width: 6, height: 2.3),
                                      cornerWidth: 0.6, cornerHeight: 0.6, transform: nil)
    private static let brand = path("M2 5h6l2 2.4h8V17H2z")

    /// Folder, 18 x 15 in the list. `lit` turns the slot on the front to the accent (selected rows).
    static func drawFolder(in rect: NSRect, palette p: Palette, lit: Bool) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.applyViewBox(rect, units: 20, unitsHigh: 16)
        fillStroke(ctx, folderBack, fill: p.foldBack, stroke: p.foldLine, width: 0.9)
        ctx.addPath(folderTab); ctx.setFillColor(p.accent.cg); ctx.fillPath()
        fillStroke(ctx, folderFront, fill: p.foldFront, stroke: p.foldLine, width: 0.9)
        ctx.addPath(folderSlot)
        ctx.setStrokeColor((lit ? p.accent : p.foldLine).cg)
        ctx.setLineWidth(1.4); ctx.setLineCap(.round); ctx.strokePath()
        ctx.restoreGState()
    }

    /// File page with a coloured badge by type, 15 x 15.
    static func drawFile(named name: String, in rect: NSRect, palette p: Palette) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.applyViewBox(rect, units: 16)
        fillStroke(ctx, page, fill: p.fileBg, stroke: p.foldLine, width: 0.9)
        ctx.addPath(pageFold); ctx.setStrokeColor(p.foldLine.cg); ctx.setLineWidth(0.9); ctx.strokePath()
        let tone: RGBA = switch FileTypeCategory(name: name) {
        case .doc: p.typeDoc
        case .code: p.typeCode
        case .web: p.typeWeb
        case .data: p.typeData
        }
        ctx.addPath(badge); ctx.setFillColor(tone.cg); ctx.fillPath()
        ctx.restoreGState()
    }

    /// Explorer's shortcut arrow on an alias or symbolic link: a small boxed arrow at the icon's corner.
    static func drawLinkBadge(in rect: NSRect, palette p: Palette) {
        fillRounded(rect, radius: max(1.5, rect.width / 6), p.s1)
        strokeRounded(rect, radius: max(1.5, rect.width / 6), p.line3, width: max(0.75, rect.width / 12))
        Glyph.arrow.draw(in: rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12), color: p.accent.ns,
                         lineWidth: rect.width >= 20 ? 2.2 : 3, rotation: -.pi / 4)
    }

    /// The Folio mark in the title bar: an outlined folder and a lit dot, 18 x 18.
    static func drawBrand(in rect: NSRect, palette p: Palette) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.applyViewBox(rect, units: 20)
        ctx.addPath(brand); ctx.setStrokeColor(p.accent.cg); ctx.setLineWidth(1.6); ctx.strokePath()
        ctx.addEllipse(in: CGRect(x: 14.5 - 1.8, y: 12.2 - 1.8, width: 3.6, height: 3.6))
        ctx.setFillColor(p.accent.cg); ctx.fillPath()
        ctx.restoreGState()
    }

    private static func fillStroke(_ ctx: CGContext, _ path: CGPath, fill: RGBA, stroke: RGBA, width: CGFloat) {
        ctx.addPath(path); ctx.setFillColor(fill.cg); ctx.fillPath()
        ctx.addPath(path); ctx.setStrokeColor(stroke.cg); ctx.setLineWidth(width); ctx.setLineJoin(.round); ctx.strokePath()
    }
}

/// D1's corner brackets (`.brk::before`): an L of `length` x `width` at each corner of `rect`.
@MainActor
func drawBrackets(_ rect: NSRect, color: NSColor, length: CGFloat, width: CGFloat = 1.5) {
    color.setFill()
    let r = rect
    let bars = [
        NSRect(x: r.minX, y: r.minY, width: length, height: width),
        NSRect(x: r.minX, y: r.minY + width, width: width, height: length - width),
        NSRect(x: r.maxX - length, y: r.minY, width: length, height: width),
        NSRect(x: r.maxX - width, y: r.minY + width, width: width, height: length - width),
        NSRect(x: r.minX, y: r.maxY - width, width: length, height: width),
        NSRect(x: r.minX, y: r.maxY - length, width: width, height: length - width),
        NSRect(x: r.maxX - length, y: r.maxY - width, width: length, height: width),
        NSRect(x: r.maxX - width, y: r.maxY - length, width: width, height: length - width),
    ]
    for bar in bars { bar.fill(using: .sourceOver) }
}

/// Fills a rect with alpha blending (NSRect.fill() alone copies and punches through).
@MainActor
func fillRect(_ rect: NSRect, _ color: RGBA) {
    color.ns.setFill()
    rect.fill(using: .sourceOver)
}

@MainActor
func fillRounded(_ rect: NSRect, radius: CGFloat, _ color: RGBA) {
    color.ns.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

@MainActor
func strokeRounded(_ rect: NSRect, radius: CGFloat, _ color: RGBA, width: CGFloat = 1) {
    color.ns.setStroke()
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2), xRadius: radius, yRadius: radius)
    path.lineWidth = width
    path.stroke()
}

/// One line of text, vertically centred on `midY` the way CSS centres a line box,
/// truncated with an ellipsis past `maxWidth`. Returns the drawn width.
@MainActor
@discardableResult
func drawLine(_ text: String, font: NSFont, color: RGBA, x: CGFloat, midY: CGFloat, maxWidth: CGFloat = .greatestFiniteMagnitude,
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
