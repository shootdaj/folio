import Foundation

/// Turns a parsed query into a Spotlight query string (MDQuery syntax, for `NSPredicate(fromMetadataQueryString:)`),
/// with the fixes found by testing on this Mac (docs/research/explorer-search.md, sections 10 and 11):
/// - a bare word is `(* == "x*"cdw || kMDItemTextContent == "x*"cdw)`, Spotlight's own menu query;
/// - dates go as `>= start && < end` with `$time.iso(...)` bounds the app computes (`== $time.today`
///   and InRange on dates return nothing);
/// - sizes go as `>=` and `<=` pairs (InRange fails in mdfind);
/// - `?` goes as `*`, multi-word phrases in contents go as their words, and `folder:` is left out:
///   Spotlight cannot do them, so the results are checked again (SearchMatcher).
/// A term Spotlight can only approximate is sent as a superset where it counts positively and dropped
/// (everything passes) where it sits under NOT, so no true result is lost; the check after decides.
public enum SpotlightPredicate {
    /// Every item in scope (`kMDItemFSName == "*"` returns nothing; DisplayName works).
    public static let everything = "kMDItemDisplayName == \"*\""

    /// The query string, or nil when Spotlight cannot have any result (the live walk alone answers).
    public static func compile(_ node: QueryNode) -> String? {
        switch build(node, negated: false) {
        case .always: everything
        case .never: nil
        case .expr(let s): s
        }
    }

    enum Part: Equatable {
        case always, never
        case expr(String)
    }

    static func build(_ node: QueryNode, negated: Bool) -> Part {
        switch node {
        case .all: return .always
        case .not(let x):
            switch build(x, negated: !negated) {
            case .always: return .never
            case .never: return .always
            case .expr(let s): return .expr("!(" + s + ")")
            }
        case .and(let xs):
            var parts: [String] = []
            for x in xs {
                switch build(x, negated: negated) {
                case .never: return .never
                case .always: continue
                case .expr(let s): parts.append(s)
                }
            }
            return join(parts, "&&", empty: .always)
        case .or(let xs):
            var parts: [String] = []
            for x in xs {
                switch build(x, negated: negated) {
                case .always: return .always
                case .never: continue
                case .expr(let s): parts.append(s)
                }
            }
            return join(parts, "||", empty: .never)
        case .term(let t):
            return term(t, negated: negated)
        }
    }

    static func join(_ parts: [String], _ op: String, empty: Part) -> Part {
        if parts.isEmpty { return empty }
        if parts.count == 1 { return .expr(parts[0]) }
        return .expr("(" + parts.joined(separator: " " + op + " ") + ")")
    }

    /// A string literal with its modifiers: `"bert*"cdw`.
    static func lit(_ s: String, _ mods: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\"" + mods
    }

    static func eq(_ attr: String, _ s: String, _ mods: String) -> String { attr + " == " + lit(s, mods) }

    /// `?` as `*`, and the implicit `*` after.
    static func wildcardText(_ s: String) -> String {
        let star = s.replacingOccurrences(of: "?", with: "*")
        return star.hasSuffix("*") ? star : star + "*"
    }

    static func words(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// One text match on one attribute: (expression, is it exact).
    static func textOn(_ attr: String, _ m: TextMatch) -> (String, Bool) {
        switch m {
        case .word(let w): return (eq(attr, w + "*", "cdw"), true)
        case .wordEqual(let w):
            let ws = words(w)
            return ws.count <= 1 ? (eq(attr, w, "cdw"), true) : (eq(attr, "*" + w + "*", "cd"), false)
        case .wildcard(let w): return (eq(attr, wildcardText(w), "cd"), !w.contains("?"))
        case .phrase(let w): return (eq(attr, "*" + w + "*", "cd"), false)
        case .contains(let w): return (eq(attr, "*" + w + "*", "cd"), true)
        case .valueStarts(let w): return (eq(attr, w + "*", "cd"), true)
        case .valueEnds(let w): return (eq(attr, "*" + w, "cd"), true)
        case .exact(let w): return (eq(attr, w, "cd"), true)
        }
    }

    /// A text match in contents: a phrase goes as its words (Spotlight returns 0 for phrases in contents).
    static func contentOn(_ m: TextMatch) -> (String, Bool) {
        switch m {
        case .phrase(let w), .wordEqual(let w) where words(w).count > 1:
            let ws = words(w).map { eq("kMDItemTextContent", $0 + "*", "cdw") }
            return (ws.count == 1 ? ws[0] : "(" + ws.joined(separator: " && ") + ")", false)
        default:
            return textOn("kMDItemTextContent", m)
        }
    }

    /// Positive: the superset Spotlight can find. Under NOT: nothing, so the NOT lets every item through
    /// to the check after (a superset under NOT would drop true results).
    static func approx(_ s: String, exact: Bool, negated: Bool) -> Part {
        exact || !negated ? .expr(s) : .never
    }

    /// A term Spotlight knows nothing about: everything, or nothing under NOT.
    static func unknown(_ negated: Bool) -> Part { negated ? .never : .always }

    static func term(_ t: QueryTerm, negated: Bool) -> Part {
        switch (t.property, t.value) {
        case (.any, .text(let m)):
            let (name, nameExact) = textOn("*", m)
            let (body, bodyExact) = contentOn(m)
            return approx("(" + name + " || " + body + ")", exact: nameExact && bodyExact, negated: negated)
        case (.name, .text(let m)):
            let (s, exact) = textOn("kMDItemFSName", m)
            return approx(s, exact: exact, negated: negated)
        case (.ext, .text(let m)):
            switch m {
            case .wildcard(let w): return approx(eq("kMDItemFSName", "*." + w.replacingOccurrences(of: "?", with: "*"), "c"),
                                                 exact: !w.contains("?"), negated: negated)
            default: return .expr(eq("kMDItemFSName", "*." + m.text, "c"))
            }
        case (.type, .text(let m)):
            let (kind, _) = textOn("kMDItemKind", m)
            let ext = m.text.hasPrefix(".") ? String(m.text.dropFirst()) : m.text
            return approx("(" + kind + " || " + eq("kMDItemFSName", "*." + ext, "c") + ")", exact: false, negated: negated)
        case (.kind, .kind(let k)):
            if k == .folder { return .expr("kMDItemContentType == \"public.folder\"") }
            let types = k.contentTypes.map { "kMDItemContentTypeTree == " + lit($0, "") }
            let exts = k.extensions.sorted().map { eq("kMDItemFSName", "*." + $0, "c") }
            let all = types + exts
            // No Mac type or extension (game, task, unknown): only the check after can tell.
            if all.isEmpty { return k == .unknown ? unknown(negated) : .never }
            return approx(all.count == 1 ? all[0] : "(" + all.joined(separator: " || ") + ")", exact: false, negated: negated)
        case (.size, .size(let r)):
            let a = "kMDItemFSSize"
            var parts: [String] = []
            if let lo = r.lower, let hi = r.upper, lo == hi {
                parts.append("\(a) == \(lo)")
            } else {
                if let lo = r.lower { parts.append("\(a) >= \(lo)") }
                if let hi = r.upper { parts.append("\(a) <= \(hi)") }
            }
            parts.append("kMDItemContentType != \"public.folder\"")
            return .expr("(" + parts.joined(separator: " && ") + ")")
        case (.date, .date(let b)), (.modified, .date(let b)):
            return dates("kMDItemFSContentChangeDate", b)
        case (.created, .date(let b)):
            return dates("kMDItemFSCreationDate", b)
        case (.folder, _):
            // kMDItemPath is not searchable (tested): checked on the result paths.
            return unknown(negated)
        case (.tag, .text(let m)):
            let (a, ea) = textOn("kMDItemUserTags", m)
            let (b, _) = textOn("kMDItemKeywords", m)
            return approx("(" + a + " || " + b + ")", exact: ea, negated: negated)
        case (.tag, .empty): return .expr("kMDItemUserTags != \"*\"")
        case (.author, .text(let m)):
            let (s, exact) = textOn("kMDItemAuthors", m)
            return approx(s, exact: exact, negated: negated)
        case (.author, .empty): return .expr("kMDItemAuthors != \"*\"")
        case (.title, .text(let m)):
            let (s, exact) = textOn("kMDItemTitle", m)
            return approx(s, exact: exact, negated: negated)
        case (.title, .empty): return .expr("kMDItemTitle != \"*\"")
        case (.content, .text(let m)):
            let (s, exact) = contentOn(m)
            return approx(s, exact: exact, negated: negated)
        case (.size, .empty), (.ext, .empty), (.content, .empty), (.date, .empty), (.modified, .empty), (.created, .empty):
            return unknown(negated)
        default:
            // Nothing matches (SearchMatcher says no).
            return .never
        }
    }

    static func dates(_ attr: String, _ b: DateBounds) -> Part {
        var parts: [String] = []
        if let s = b.start { parts.append("\(attr) >= $time.iso(\(iso(s)))") }
        if let e = b.end { parts.append("\(attr) < $time.iso(\(iso(e)))") }
        if parts.isEmpty { return .always }
        return .expr(parts.count == 1 ? parts[0] : "(" + parts.joined(separator: " && ") + ")")
    }

    nonisolated(unsafe) private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    static func iso(_ d: Date) -> String { isoFormatter.string(from: d) }
}
