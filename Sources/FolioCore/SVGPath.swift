import CoreGraphics
import Foundation

/// Parses the SVG path data D1's icons are written in (M L H V C A Z, upper and lower case)
/// into absolute moves, lines and cubic curves that AppKit can stroke. Arcs become cubics.
public enum SVGPath {
    public enum Element: Sendable, Equatable {
        case move(CGPoint)
        case line(CGPoint)
        case curve(CGPoint, CGPoint, CGPoint)
        case close
    }

    public static func parse(_ data: String) -> [Element] {
        var scanner = Tokens(Array(data.utf8))
        var out: [Element] = []
        var current = CGPoint.zero
        var start = CGPoint.zero
        var command: UInt8 = 0

        while true {
            if let c = scanner.command() {
                command = c
            } else if command == 0 || !scanner.hasNumber() {
                break
            } else if command == UInt8(ascii: "M") {
                command = UInt8(ascii: "L")  // extra pairs after a move are lines
            } else if command == UInt8(ascii: "m") {
                command = UInt8(ascii: "l")
            }
            let relative = command >= UInt8(ascii: "a")
            let base = relative ? current : .zero
            switch command | 0x20 {  // lower-case
            case UInt8(ascii: "m"):
                guard let x = scanner.number(), let y = scanner.number() else { return out }
                current = CGPoint(x: base.x + x, y: base.y + y)
                start = current
                out.append(.move(current))
            case UInt8(ascii: "l"):
                guard let x = scanner.number(), let y = scanner.number() else { return out }
                current = CGPoint(x: base.x + x, y: base.y + y)
                out.append(.line(current))
            case UInt8(ascii: "h"):
                guard let x = scanner.number() else { return out }
                current = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
                out.append(.line(current))
            case UInt8(ascii: "v"):
                guard let y = scanner.number() else { return out }
                current = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
                out.append(.line(current))
            case UInt8(ascii: "c"):
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return out }
                let end = CGPoint(x: base.x + x, y: base.y + y)
                out.append(.curve(CGPoint(x: base.x + x1, y: base.y + y1),
                                  CGPoint(x: base.x + x2, y: base.y + y2), end))
                current = end
            case UInt8(ascii: "a"):
                guard let rx = scanner.number(), let ry = scanner.number(), let rot = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(),
                      let x = scanner.number(), let y = scanner.number() else { return out }
                let end = CGPoint(x: base.x + x, y: base.y + y)
                out += arc(from: current, to: end, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                current = end
            case UInt8(ascii: "z"):
                out.append(.close)
                current = start
                command = 0
            default:
                return out
            }
        }
        return out
    }

    /// SVG arc (endpoint form) to cubics, at most 90 degrees each (SVG 1.1 appendix F.6).
    static func arc(from p0: CGPoint, to p1: CGPoint, rx rxIn: Double, ry ryIn: Double,
                    rotation: Double, large: Bool, sweep: Bool) -> [Element] {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 || p0 == p1 { return [.line(p1)] }
        let phi = rotation * .pi / 180
        let (cosP, sinP) = (cos(phi), sin(phi))
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosP * dx + sinP * dy
        let y1p = -sinP * dx + cosP * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den == 0 ? 0 : (max(0, num) / den).squareRoot()
        if large == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let pieces = max(1, Int((abs(delta) / (.pi / 2) - 1e-9).rounded(.up)))
        let step = delta / Double(pieces)
        let k = 4.0 / 3.0 * tan(step / 4)
        func point(_ t: Double) -> (CGPoint, CGPoint) {
            let (c, s) = (cos(t), sin(t))
            let p = CGPoint(x: cx + rx * c * cosP - ry * s * sinP, y: cy + rx * c * sinP + ry * s * cosP)
            let d = CGPoint(x: -rx * s * cosP - ry * c * sinP, y: -rx * s * sinP + ry * c * cosP)
            return (p, d)
        }
        var out: [Element] = []
        var t = theta1
        for i in 0..<pieces {
            let (a, da) = point(t)
            let (b, db) = point(t + step)
            let end = i == pieces - 1 ? p1 : b
            out.append(.curve(CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
                              CGPoint(x: b.x - k * db.x, y: b.y - k * db.y), end))
            t += step
        }
        return out
    }

    private struct Tokens {
        let bytes: [UInt8]
        var i = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func skipSeparators() {
            while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x2C || bytes[i] == 0x0A
                || bytes[i] == 0x09 || bytes[i] == 0x0D { i += 1 }
        }

        mutating func command() -> UInt8? {
            skipSeparators()
            guard i < bytes.count else { return nil }
            let c = bytes[i]
            let isLetter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
            guard isLetter && c != UInt8(ascii: "e") && c != UInt8(ascii: "E") else { return nil }
            i += 1
            return c
        }

        mutating func hasNumber() -> Bool {
            skipSeparators()
            guard i < bytes.count else { return false }
            let c = bytes[i]
            return (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E
        }

        /// Arc flags are single digits and may be packed ("011").
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < bytes.count, bytes[i] == 0x30 || bytes[i] == 0x31 else { return nil }
            defer { i += 1 }
            return bytes[i] == 0x31
        }

        mutating func number() -> Double? {
            skipSeparators()
            let begin = i
            if i < bytes.count, bytes[i] == 0x2D || bytes[i] == 0x2B { i += 1 }
            var sawDot = false, sawDigit = false
            while i < bytes.count {
                let c = bytes[i]
                if c >= 0x30 && c <= 0x39 { sawDigit = true; i += 1 }
                else if c == 0x2E && !sawDot { sawDot = true; i += 1 }
                else { break }
            }
            if i < bytes.count, bytes[i] == 0x65 || bytes[i] == 0x45 {  // exponent
                var j = i + 1
                if j < bytes.count, bytes[j] == 0x2D || bytes[j] == 0x2B { j += 1 }
                if j < bytes.count, bytes[j] >= 0x30 && bytes[j] <= 0x39 {
                    i = j
                    while i < bytes.count, bytes[i] >= 0x30 && bytes[i] <= 0x39 { i += 1 }
                }
            }
            guard sawDigit, let s = String(bytes: bytes[begin..<i], encoding: .ascii) else {
                i = begin
                return nil
            }
            return Double(s)
        }
    }
}
