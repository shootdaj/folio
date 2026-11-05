import Foundation

/// Windows' text matching: case and accents ignored; words split on spaces and punctuation only (not
/// on CamelCase or digits, which Spotlight's `w` mode also splits), so `bert` finds Bert, Bertie and
/// my_bert but not Albert or MyBertFile; `*` and `?` are DOS wildcards with an implicit `*` after.
public enum TextMatcher {
    /// Lowercased with accents folded, as unicode scalars.
    static func fold(_ s: String) -> [Unicode.Scalar] {
        Array(s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).unicodeScalars)
    }

    static func isWordChar(_ c: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(c)
    }

    /// True where a word starts: the first scalar, or one after a non-word scalar.
    static func isBoundary(_ t: [Unicode.Scalar], _ i: Int) -> Bool {
        i == 0 || !isWordChar(t[i - 1])
    }

    static func hasPrefix(_ t: [Unicode.Scalar], at i: Int, _ p: [Unicode.Scalar]) -> Bool {
        guard i + p.count <= t.count else { return false }
        for k in 0..<p.count where t[i + k] != p[k] { return false }
        return true
    }

    /// Word ranges (runs of letters and digits).
    static func words(_ t: [Unicode.Scalar]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start: Int?
        for (i, c) in t.enumerated() {
            if isWordChar(c) { if start == nil { start = i } } else if let s = start { out.append(s..<i); start = nil }
        }
        if let s = start { out.append(s..<t.count) }
        return out
    }

    public static func matches(_ m: TextMatch, _ text: String) -> Bool {
        !ranges(m, fold(text), first: true).isEmpty
    }

    /// Where `m` matches in folded `t` (scalar offsets); `first` stops at one.
    static func ranges(_ m: TextMatch, _ t: [Unicode.Scalar], first: Bool) -> [Range<Int>] {
        let p = fold(m.text)
        guard !p.isEmpty else { return [] }
        var out: [Range<Int>] = []
        switch m {
        case .word(let raw):
            // A word starts with it; a pattern that starts with punctuation may sit anywhere.
            let anywhere = !isWordChar(p[0])
            _ = raw
            var i = 0
            while i + p.count <= t.count {
                if (anywhere || isBoundary(t, i)) && hasPrefix(t, at: i, p) {
                    out.append(i..<(i + p.count))
                    if first { return out }
                    i += p.count
                } else {
                    i += 1
                }
            }
        case .wordEqual, .phrase:
            // These words, whole, in this order.
            let pw = words(p).map { Array(p[$0]) }
            let tw = words(t)
            guard !pw.isEmpty, pw.count <= tw.count else { return [] }
            for s in 0...(tw.count - pw.count) {
                var ok = true
                for k in 0..<pw.count where Array(t[tw[s + k]]) != pw[k] { ok = false; break }
                if ok {
                    out.append(tw[s].lowerBound..<tw[s + pw.count - 1].upperBound)
                    if first { return out }
                }
            }
        case .contains:
            var i = 0
            while i + p.count <= t.count {
                if hasPrefix(t, at: i, p) {
                    out.append(i..<(i + p.count))
                    if first { return out }
                    i += p.count
                } else {
                    i += 1
                }
            }
        case .valueStarts:
            if hasPrefix(t, at: 0, p) { out.append(0..<p.count) }
        case .valueEnds:
            if t.count >= p.count, Array(t[(t.count - p.count)...]) == p { out.append((t.count - p.count)..<t.count) }
        case .exact:
            if t == p { out.append(0..<t.count) }
        case .wildcard:
            // The pattern, with an implicit * after it, from the start of a word (or anywhere once it
            // begins with *).
            let pattern = p.last == "*" ? p : p + ["*"]
            for i in 0..<max(1, t.count) where i == 0 || (pattern.first != "*" && isBoundary(t, i)) {
                if let end = glob(pattern, t, from: i) {
                    out.append(i..<end)
                    if first { return out }
                }
            }
        }
        return out
    }

    /// DOS wildcard match of `p` against `t` from `start`; the end of the match (the whole rest when
    /// `p` ends with `*`), or nil.
    static func glob(_ p: [Unicode.Scalar], _ t: [Unicode.Scalar], from start: Int) -> Int? {
        var pi = 0, ti = start
        var starP = -1, starT = 0
        while ti < t.count {
            if pi < p.count, p[pi] == "?" || (p[pi] != "*" && p[pi] == t[ti]) {
                pi += 1; ti += 1
            } else if pi < p.count, p[pi] == "*" {
                starP = pi; starT = ti; pi += 1
            } else if starP >= 0 {
                pi = starP + 1; starT += 1; ti = starT
            } else {
                return nil
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count ? t.count : nil
    }

    /// The parts of `name` a highlight covers for these terms, as ranges of the original string.
    public static func highlights(_ terms: [TextMatch], in name: String) -> [Range<String.Index>] {
        guard !terms.isEmpty, !name.isEmpty else { return [] }
        // Fold character by character so offsets map back to the name.
        var folded: [Unicode.Scalar] = []
        var owner: [String.Index] = []
        for idx in name.indices {
            for s in fold(String(name[idx])) {
                folded.append(s)
                owner.append(idx)
            }
        }
        var out: [Range<String.Index>] = []
        for term in terms {
            var spans: [Range<Int>]
            if case .wildcard(let raw) = term {
                // The literal runs between the wildcards.
                let literals = raw.split(whereSeparator: { $0 == "*" || $0 == "?" }).map(String.init).filter { !$0.isEmpty }
                spans = literals.flatMap { ranges(.contains($0), folded, first: false) }
            } else {
                spans = ranges(term, folded, first: false)
            }
            for r in spans where r.lowerBound < owner.count && r.upperBound > r.lowerBound {
                let lo = owner[r.lowerBound]
                let hiChar = owner[min(r.upperBound, owner.count) - 1]
                out.append(lo..<name.index(after: hiChar))
            }
        }
        return out.sorted { $0.lowerBound < $1.lowerBound }
    }
}

/// Three-valued truth for checking results: `unknown` where only Spotlight knows (contents of a file the
/// app cannot read), so a Spotlight result is kept when the rest of the query does not rule it out.
public enum Truth: Sendable, Equatable {
    case yes, no, unknown

    static func and(_ a: Truth, _ b: () -> Truth) -> Truth {
        if a == .no { return .no }
        let y = b()
        if y == .no { return .no }
        return a == .yes && y == .yes ? .yes : .unknown
    }

    static func or(_ a: Truth, _ b: () -> Truth) -> Truth {
        if a == .yes { return .yes }
        let y = b()
        if y == .yes { return .yes }
        return a == .no && y == .no ? .no : .unknown
    }

    var negated: Truth { self == .yes ? .no : (self == .no ? .yes : .unknown) }
}

/// A file's contents as the matcher sees them.
public enum SearchContent: Sendable {
    case text(String)
    /// No contents to match (a folder, or contents that are not searched here).
    case none
    /// Contents only Spotlight knows.
    case unknown
}

/// What a query is checked against. Everything past name and path is read only when a term asks.
public protocol SearchSubject: AnyObject {
    var name: String { get }
    var path: String { get }
    var isFolder: Bool { get }
    var isLink: Bool { get }
    var size: Int64? { get }
    var modified: Date? { get }
    var created: Date? { get }
    var contentType: String? { get }
    /// The Type column's text, "Plain Text Document".
    var typeText: String { get }
    var tags: [String] { get }
    var authors: [String] { get }
    var title: String? { get }
    var content: SearchContent { get }
}

/// Checks a parsed query against one item: the post-filter on Spotlight's results (Windows tokenizer,
/// `?`, phrases, `folder:`, exact kinds) and the whole test for the live walk.
public struct SearchMatcher: Sendable {
    public let query: QueryNode

    public init(_ query: QueryNode) { self.query = query }

    public func evaluate(_ s: SearchSubject) -> Truth { eval(query, s) }

    /// `trustUnknown`: a Spotlight result whose contents decide it (Spotlight said it matches).
    public func matches(_ s: SearchSubject, trustUnknown: Bool) -> Bool {
        switch evaluate(s) {
        case .yes: true
        case .no: false
        case .unknown: trustUnknown
        }
    }

    private func eval(_ node: QueryNode, _ s: SearchSubject) -> Truth {
        switch node {
        case .all: return .yes
        case .not(let x): return eval(x, s).negated
        case .and(let xs):
            var acc = Truth.yes
            for x in xs {
                acc = Truth.and(acc) { eval(x, s) }
                if acc == .no { return .no }
            }
            return acc
        case .or(let xs):
            var acc = Truth.no
            for x in xs {
                acc = Truth.or(acc) { eval(x, s) }
                if acc == .yes { return .yes }
            }
            return acc
        case .term(let t): return term(t, s)
        }
    }

    private func text(_ m: TextMatch, _ value: String?) -> Truth {
        guard let value else { return .no }
        return TextMatcher.matches(m, value) ? .yes : .no
    }

    private func anyText(_ m: TextMatch, _ values: [String]) -> Truth {
        values.contains { TextMatcher.matches(m, $0) } ? .yes : .no
    }

    private func contentTruth(_ m: TextMatch, _ s: SearchSubject) -> Truth {
        switch s.content {
        case .text(let body): TextMatcher.matches(m, body) ? .yes : .no
        case .none: .no
        case .unknown: .unknown
        }
    }

    private func term(_ t: QueryTerm, _ s: SearchSubject) -> Truth {
        switch (t.property, t.value) {
        case (.any, .text(let m)):
            if TextMatcher.matches(m, s.name) { return .yes }
            if anyText(m, s.tags) == .yes || text(m, s.title) == .yes || anyText(m, s.authors) == .yes { return .yes }
            return s.isFolder ? .no : contentTruth(m, s)
        case (.name, .text(let m)): return text(m, s.name)
        case (.ext, .text(let m)):
            let ext = (s.name as NSString).pathExtension
            return !s.isFolder && !ext.isEmpty ? text(m, ext) : .no
        case (.ext, .empty): return (s.name as NSString).pathExtension.isEmpty || s.isFolder ? .yes : .no
        case (.type, .text(let m)):
            if text(m, s.typeText) == .yes { return .yes }
            let ext = (s.name as NSString).pathExtension
            return !s.isFolder && !ext.isEmpty && TextMatcher.matches(.exact(m.text.hasPrefix(".") ? String(m.text.dropFirst()) : m.text), ext)
                ? .yes : .no
        case (.kind, .kind(let k)):
            let kinds = SearchKind.kinds(name: s.name, isFolder: s.isFolder, isLink: s.isLink, contentType: s.contentType)
            if k == .communication { return kinds.contains(.email) || kinds.contains(.instantMessage) || kinds.contains(.communication) ? .yes : .no }
            return kinds.contains(k) ? .yes : .no
        case (.size, .size(let r)):
            guard !s.isFolder, let size = s.size else { return .no }
            return r.contains(size) ? .yes : .no
        case (.size, .empty): return s.isFolder || s.size == nil ? .yes : .no
        case (.date, .date(let b)), (.modified, .date(let b)):
            guard let d = s.modified else { return .no }
            return b.contains(d) ? .yes : .no
        case (.created, .date(let b)):
            guard let d = s.created else { return .no }
            return b.contains(d) ? .yes : .no
        case (.date, .empty), (.modified, .empty): return s.modified == nil ? .yes : .no
        case (.created, .empty): return s.created == nil ? .yes : .no
        case (.folder, .text(let m)):
            return text(m, (s.path as NSString).deletingLastPathComponent)
        case (.tag, .text(let m)): return anyText(m, s.tags)
        case (.tag, .empty): return s.tags.isEmpty ? .yes : .no
        case (.author, .text(let m)): return anyText(m, s.authors)
        case (.author, .empty): return s.authors.isEmpty ? .yes : .no
        case (.title, .text(let m)): return text(m, s.title)
        case (.title, .empty): return (s.title ?? "").isEmpty ? .yes : .no
        case (.content, .text(let m)): return s.isFolder ? .no : contentTruth(m, s)
        case (.content, .empty): return .unknown
        case (.any, .empty), (.name, .empty), (.folder, .empty): return .no
        default: return .no
        }
    }

    // MARK: Relevance

    /// Explorer's relevance order, scored by the app: a match in the name first (more when the name
    /// starts with it), then in tags, title or authors, then contents only. Filter-only queries score 0.
    public func score(_ s: SearchSubject) -> Int {
        var best = 0
        for m in query.positiveTextTerms {
            let folded = TextMatcher.fold(s.name)
            let hits = TextMatcher.ranges(m, folded, first: true)
            if let r = hits.first {
                best = max(best, 300 + (r.lowerBound == 0 ? 50 : 0))
            } else if s.tags.contains(where: { TextMatcher.matches(m, $0) }) || (s.title.map { TextMatcher.matches(m, $0) } ?? false) {
                best = max(best, 200)
            } else {
                best = max(best, 100)
            }
        }
        return best
    }
}

extension QueryNode {
    /// Bare, name and content text terms outside any NOT (what relevance weighs).
    var positiveTextTerms: [TextMatch] {
        switch self {
        case .term(let t):
            guard t.property == .any || t.property == .name || t.property == .content, case .text(let m) = t.value else { return [] }
            return [m]
        case .and(let xs), .or(let xs): return xs.flatMap(\.positiveTextTerms)
        case .not, .all: return []
        }
    }
}
