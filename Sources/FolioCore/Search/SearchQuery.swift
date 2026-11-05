import Foundation

/// The property an AQS term looks at. English keywords only, as Windows reads them in an English UI.
public enum SearchProperty: String, Sendable, CaseIterable {
    /// A bare term: the name, tags, authors and title, and contents where they can be read.
    case any
    case name, ext, type, kind, size
    /// `date:`, Explorer's main date; on a Mac the date modified.
    case date
    case modified, created
    /// `folder:` and `path:`: the path of the folder an item is in.
    case folder
    case tag, author, title, content

    /// Keyword spellings, lowercased with spaces removed (`Date Modified:` is `datemodified:`).
    static let aliases: [String: SearchProperty] = [
        "name": .name, "filename": .name, "file": .name, "system.filename": .name, "system.itemnamedisplay": .name,
        "ext": .ext, "fileext": .ext, "extension": .ext, "system.fileextension": .ext,
        "type": .type, "system.itemtypetext": .type,
        "kind": .kind, "system.kind": .kind,
        "size": .size, "system.size": .size,
        "date": .date, "system.itemdate": .date,
        "datemodified": .modified, "modified": .modified, "system.datemodified": .modified,
        "datecreated": .created, "created": .created, "system.datecreated": .created,
        "folder": .folder, "folderpath": .folder, "path": .folder, "under": .folder, "in": .folder, "foldername": .folder,
        "system.itemfolderpathdisplay": .folder,
        "tag": .tag, "tags": .tag, "keywords": .tag, "system.keywords": .tag,
        "author": .author, "authors": .author, "by": .author, "system.author": .author,
        "title": .title, "subject": .title, "about": .title, "system.title": .title,
        "content": .content, "contents": .content, "system.search.contents": .content,
    ]

    public static func named(_ raw: String) -> SearchProperty? {
        aliases[raw.lowercased().replacingOccurrences(of: " ", with: "")]
    }

    /// The keyword the Search options menu writes.
    public var keyword: String {
        switch self {
        case .any: ""
        case .modified: "datemodified"
        case .created: "datecreated"
        default: rawValue
        }
    }

    public var isDate: Bool { self == .date || self == .modified || self == .created }

    /// Properties whose values are words: name, tags, contents and the like.
    var isText: Bool {
        switch self {
        case .any, .name, .ext, .type, .folder, .tag, .author, .title, .content: true
        default: false
        }
    }
}

/// How a text value matches.
public enum TextMatch: Sendable, Equatable {
    /// The default: a word starts with it (`bert` finds Bert and my_bert, not Albert).
    case word(String)
    /// `$=`: a whole word equals it.
    case wordEqual(String)
    /// `*` and `?` (DOS wildcards); an implicit `*` follows, as with a plain word.
    case wildcard(String)
    /// Quoted: these words, whole and in this order.
    case phrase(String)
    /// `~=` or `~~`: anywhere, even inside a word.
    case contains(String)
    /// `~<`: the whole value starts with it.
    case valueStarts(String)
    /// `~>`: the whole value ends with it.
    case valueEnds(String)
    /// `=`: the whole value is it.
    case exact(String)

    public var text: String {
        switch self {
        case .word(let s), .wordEqual(let s), .wildcard(let s), .phrase(let s), .contains(let s),
             .valueStarts(let s), .valueEnds(let s), .exact(let s): s
        }
    }
}

/// Bytes from `lower` to `upper`, both inclusive; nil is open.
public struct SizeRange: Sendable, Equatable {
    public var lower: Int64?
    public var upper: Int64?

    public init(_ lower: Int64?, _ upper: Int64?) {
        self.lower = lower
        self.upper = upper
    }

    public func contains(_ bytes: Int64) -> Bool {
        if let lower, bytes < lower { return false }
        if let upper, bytes > upper { return false }
        return true
    }
}

/// From `start` (inclusive) to `end` (exclusive); nil is open.
public struct DateBounds: Sendable, Equatable {
    public var start: Date?
    public var end: Date?

    public init(_ start: Date?, _ end: Date?) {
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool {
        if let start, date < start { return false }
        if let end, date >= end { return false }
        return true
    }
}

public enum QueryValue: Sendable, Equatable {
    case text(TextMatch)
    /// `[]`: the property has no value (untagged, no author, no extension).
    case empty
    case size(SizeRange)
    case date(DateBounds)
    case kind(SearchKind)
}

public struct QueryTerm: Sendable, Equatable {
    public var property: SearchProperty
    public var value: QueryValue

    public init(_ property: SearchProperty, _ value: QueryValue) {
        self.property = property
        self.value = value
    }
}

/// A parsed query. AND and OR bind left to right with no precedence, so the tree carries the brackets.
public indirect enum QueryNode: Sendable, Equatable {
    case term(QueryTerm)
    case and([QueryNode])
    case or([QueryNode])
    case not(QueryNode)
    /// Matches everything: an empty query, `kind:everything`, a keyword with nothing after it yet.
    case all
}

public enum SearchQueryError: Error, Sendable, Equatable, CustomStringConvertible {
    case unmatchedParenthesis
    /// AND, OR or NOT with nothing on one side.
    case missingOperand(String)
    /// A value a property cannot read, such as `size:abc` or `kind:xyz`.
    case badValue(property: String, value: String)

    public var description: String {
        switch self {
        case .unmatchedParenthesis: "A bracket is not closed"
        case .missingOperand(let op): op == "NOT" ? "NOT needs a term after it" : "\(op) needs a term on each side"
        case .badValue(let p, let v): "\(p): does not understand \u{201C}\(v)\u{201D}"
        }
    }
}

/// Explorer's Advanced Query Syntax: words, quotes, brackets, AND, OR and NOT in capitals (lowercase
/// and, or, not are plain words), a `-` prefix, `property:value` with comparisons and ranges.
public enum SearchQuery {
    public static func parse(_ text: String, context: BucketContext = BucketContext()) throws -> QueryNode {
        var lexer = Lexer(text)
        let tokens = try lexer.tokens()
        var parser = Parser(tokens: tokens, context: context)
        return try parser.parseAll()
    }

    // MARK: Tokens

    enum Token: Equatable {
        case open, close
        case and, or, not
        case minus
        /// A plain word or a quoted phrase.
        case word(String, quoted: Bool)
        /// `property:` and its operator; the value comes next as a word, a phrase, `(`, or `[]`.
        case property(SearchProperty, op: String)
        case emptyValue
        /// `property:` at the end, or followed by a space: nothing typed yet.
        case noValue
    }

    struct Lexer {
        let chars: [Character]
        var i = 0

        init(_ text: String) { chars = Array(text) }

        static let operators = [">=", "<=", "<>", "~=", "~~", "~<", "~>", "~!", "$=", "$$", "$<", ">", "<", "=", "~", "-", "\u{2260}", "\u{2264}", "\u{2265}"]

        mutating func tokens() throws -> [Token] {
            var out: [Token] = []
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace { i += 1; continue }
                if c == "(" { out.append(.open); i += 1; continue }
                if c == ")" { out.append(.close); i += 1; continue }
                if c == "\"" { out.append(.word(readQuoted(), quoted: true)); continue }
                if c == "-", i + 1 < chars.count, !chars[i + 1].isWhitespace {
                    out.append(.minus)
                    i += 1
                    continue
                }
                let start = i
                let word = readWord()
                switch word {
                case "AND": out.append(.and); continue
                case "OR": out.append(.or); continue
                case "NOT": out.append(.not); continue
                default: break
                }
                // property:value
                if let colon = word.firstIndex(of: ":"), colon != word.startIndex,
                   let property = SearchProperty.named(String(word[..<colon])) {
                    i = start + word.distance(from: word.startIndex, to: colon) + 1
                    readPropertyValue(property, into: &out)
                    continue
                }
                out.append(.word(word, quoted: false))
            }
            return out
        }

        /// A run up to whitespace, a bracket or a quote.
        mutating func readWord() -> String {
            var s = ""
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace || c == "(" || c == ")" || c == "\"" { break }
                s.append(c)
                i += 1
            }
            return s
        }

        /// From an opening quote to the closing one; `""` inside is a literal quote. An unclosed quote
        /// runs to the end (the box is still being typed into).
        mutating func readQuoted() -> String {
            i += 1
            var s = ""
            while i < chars.count {
                if chars[i] == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { s.append("\""); i += 2; continue }
                    i += 1
                    return s
                }
                s.append(chars[i])
                i += 1
            }
            return s
        }

        /// After `property:`: an operator, then a quoted phrase, a bracket group, `[]`, or a word.
        mutating func readPropertyValue(_ property: SearchProperty, into out: inout [Token]) {
            var op = ""
            for candidate in Self.operators where String(chars[i...].prefix(candidate.count)) == candidate {
                // `-` is an operator only before a value (`kind:-picture`); `size:-5` stays a value.
                if candidate == "-", property == .size { continue }
                op = candidate
                break
            }
            i += op.count
            // `kind:NOT picture`
            if op.isEmpty, String(chars[i...].prefix(4)) == "NOT ", property != .any {
                op = "NOT"
                i += 4
            }
            guard i < chars.count, !chars[i].isWhitespace else {
                out.append(.noValue)
                return
            }
            if chars[i] == ")" {
                out.append(.noValue)
                return
            }
            out.append(.property(property, op: op))
            if chars[i] == "\"" { out.append(.word(readQuoted(), quoted: true)); return }
            if chars[i] == "(" { return }  // the parser reads the group
            if chars[i] == "[", i + 1 < chars.count, chars[i + 1] == "]" {
                i += 2
                out.append(.emptyValue)
                return
            }
            var value = readWord()
            // Date words written apart: `datemodified:this week`, `date:last month`.
            if property.isDate, ["this", "last", "next", "past", "coming"].contains(value.lowercased()) {
                var j = i
                while j < chars.count, chars[j] == " " { j += 1 }
                var k = j, unit = ""
                while k < chars.count, chars[k].isLetter { unit.append(chars[k]); k += 1 }
                if ["week", "month", "year"].contains(unit.lowercased()), k == chars.count || chars[k].isWhitespace || chars[k] == ")" {
                    value += unit
                    i = k
                }
            }
            out.append(.word(value, quoted: false))
        }
    }

    // MARK: Parser

    struct Parser {
        let tokens: [Token]
        let context: BucketContext
        var i = 0

        init(tokens: [Token], context: BucketContext) {
            self.tokens = tokens
            self.context = context
        }

        var peek: Token? { i < tokens.count ? tokens[i] : nil }

        mutating func parseAll() throws -> QueryNode {
            if tokens.isEmpty { return .all }
            let node = try parseSequence(property: .any, inGroup: false)
            if i < tokens.count { throw SearchQueryError.unmatchedParenthesis }
            return node
        }

        /// `a b`, `a AND b`, `a OR b`, folded left to right with no precedence.
        mutating func parseSequence(property: SearchProperty, inGroup: Bool) throws -> QueryNode {
            if let t = peek, t == .and || t == .or { throw SearchQueryError.missingOperand(t == .and ? "AND" : "OR") }
            var acc = try parseUnary(property: property)
            while let t = peek {
                if t == .close {
                    guard inGroup else { throw SearchQueryError.unmatchedParenthesis }
                    break
                }
                var isOr = false
                if t == .and || t == .or {
                    isOr = t == .or
                    i += 1
                    guard let next = peek, next != .close, next != .and, next != .or else {
                        throw SearchQueryError.missingOperand(isOr ? "OR" : "AND")
                    }
                }
                let rhs = try parseUnary(property: property)
                acc = isOr ? Self.or(acc, rhs) : Self.and(acc, rhs)
            }
            return acc
        }

        static func and(_ a: QueryNode, _ b: QueryNode) -> QueryNode {
            if a == .all { return b }
            if b == .all { return a }
            if case .and(let xs) = a { return .and(xs + [b]) }
            return .and([a, b])
        }

        static func or(_ a: QueryNode, _ b: QueryNode) -> QueryNode {
            if a == .all || b == .all { return .all }
            if case .or(let xs) = a { return .or(xs + [b]) }
            return .or([a, b])
        }

        mutating func parseUnary(property: SearchProperty) throws -> QueryNode {
            guard let t = peek else { throw SearchQueryError.missingOperand("NOT") }
            switch t {
            case .not:
                i += 1
                guard let next = peek, next != .close, next != .and, next != .or else { throw SearchQueryError.missingOperand("NOT") }
                return negate(try parseUnary(property: property))
            case .minus:
                i += 1
                // Double negation does not cancel: `- -picture` is `-picture`.
                while peek == .minus { i += 1 }
                guard peek != nil else { throw SearchQueryError.missingOperand("NOT") }
                return negate(try parseUnary(property: property))
            default:
                return try parsePrimary(property: property)
            }
        }

        func negate(_ node: QueryNode) -> QueryNode {
            if node == .all { return .all }
            return .not(node)
        }

        mutating func parsePrimary(property: SearchProperty) throws -> QueryNode {
            guard let t = peek else { throw SearchQueryError.missingOperand("AND") }
            switch t {
            case .open:
                i += 1
                if peek == .close { i += 1; return .all }
                guard peek != nil else { throw SearchQueryError.unmatchedParenthesis }
                let inner = try parseSequence(property: property, inGroup: true)
                guard peek == .close else { throw SearchQueryError.unmatchedParenthesis }
                i += 1
                return inner
            case .close:
                throw SearchQueryError.unmatchedParenthesis
            case .and, .or:
                throw SearchQueryError.missingOperand(t == .and ? "AND" : "OR")
            case .not, .minus:
                return try parseUnary(property: property)
            case .noValue:
                i += 1
                return .all
            case .emptyValue:
                i += 1
                return .term(QueryTerm(property, .empty))
            case .word(let w, let quoted):
                i += 1
                return try term(property, op: "", raw: w, quoted: quoted)
            case .property(let p, let op):
                i += 1
                guard let v = peek else { return .all }
                switch v {
                case .open:
                    // `author:(Charlie OR Herb)`: the group's bare terms are author terms.
                    i += 1
                    let inner = try parseSequence(property: p, inGroup: true)
                    guard peek == .close else { throw SearchQueryError.unmatchedParenthesis }
                    i += 1
                    return applyOp(op, inner)
                case .emptyValue:
                    i += 1
                    return applyOp(op, .term(QueryTerm(p, .empty)))
                case .word(let w, let quoted):
                    i += 1
                    return try term(p, op: op, raw: w, quoted: quoted)
                default:
                    return .all
                }
            }
        }

        /// The negating operators wrap the term; the rest choose how text matches or compare.
        func applyOp(_ op: String, _ node: QueryNode) -> QueryNode {
            ["-", "<>", "NOT", "\u{2260}"].contains(op) ? negate(node) : node
        }

        func term(_ property: SearchProperty, op: String, raw: String, quoted: Bool) throws -> QueryNode {
            let negating = ["-", "<>", "NOT", "\u{2260}"].contains(op)
            let op = negating ? "" : op
            let node: QueryNode
            switch property {
            case .size:
                guard let r = SearchValues.size(raw, op: op) else {
                    throw SearchQueryError.badValue(property: "size", value: op + raw)
                }
                node = .term(QueryTerm(.size, .size(r)))
            case .date, .modified, .created:
                guard let b = SearchValues.date(raw, op: op, context: context) else {
                    throw SearchQueryError.badValue(property: property.keyword, value: op + raw)
                }
                node = .term(QueryTerm(property, .date(b)))
            case .kind:
                let name = raw.lowercased()
                if name == "everything" || name == "*" { return .all }
                guard let k = SearchKind.named(name) else { throw SearchQueryError.badValue(property: "kind", value: raw) }
                node = .term(QueryTerm(.kind, .kind(k)))
            case .ext:
                var v = raw.hasPrefix(".") ? String(raw.dropFirst()) : raw
                v = v.lowercased()
                guard !v.isEmpty else { return .all }
                node = .term(QueryTerm(.ext, .text(v.contains("*") || v.contains("?") ? .wildcard(v) : .exact(v))))
            default:
                guard !raw.isEmpty else { return .all }
                node = .term(QueryTerm(property, .text(Self.textMatch(raw, op: op, quoted: quoted))))
            }
            return negating ? negate(node) : (op == "~!" ? .not(node) : node)
        }

        static func textMatch(_ raw: String, op: String, quoted: Bool) -> TextMatch {
            switch op {
            case "=": return .exact(raw)
            case "~=", "~~", "~!": return .contains(raw)
            case "~<": return .valueStarts(raw)
            case "~>": return .valueEnds(raw)
            case "$=", "$$": return .wordEqual(raw)
            case "~": return .wildcard(raw)
            default: break
            }
            if quoted {
                return raw.contains(where: { $0.isWhitespace }) || raw.contains(where: { !$0.isLetter && !$0.isNumber })
                    ? .phrase(raw) : .wordEqual(raw)
            }
            if raw.contains("*") || raw.contains("?") { return .wildcard(raw) }
            return .word(raw)
        }
    }
}

extension QueryNode {
    /// The text terms a result's name is checked against (for highlighting): the positive bare and
    /// `name:` terms, outside any NOT.
    public var positiveNameTerms: [TextMatch] {
        switch self {
        case .term(let t):
            guard t.property == .any || t.property == .name, case .text(let m) = t.value else { return [] }
            return [m]
        case .and(let xs), .or(let xs): return xs.flatMap(\.positiveNameTerms)
        case .not, .all: return []
        }
    }

    /// Every term, for the Search options chips.
    public var terms: [QueryTerm] {
        switch self {
        case .term(let t): [t]
        case .and(let xs), .or(let xs): xs.flatMap(\.terms)
        case .not(let x): x.terms
        case .all: []
        }
    }
}
