import Foundation

/// A saved search: Folio's take on Windows' .search-ms (an XML `persistedQuery` with the scope, the
/// query and the view). Opening it runs the query again live; it is not a snapshot.
public struct SavedSearch: Sendable, Equatable {
    public static let fileExtension = "foliosearch"

    public var text: String
    public var location: SearchLocation
    public var recursive: Bool
    /// The view the results showed in (ViewMode raw value), its sort and grouping, when saved.
    public var view: String?
    public var sort: [SortTerm]
    public var group: GroupSpec?

    public init(text: String, location: SearchLocation, recursive: Bool = true, view: String? = nil,
                sort: [SortTerm] = [], group: GroupSpec? = nil) {
        self.text = text
        self.location = location
        self.recursive = recursive
        self.view = view
        self.sort = sort
        self.group = group
    }

    /// ~/Library/Application Support/Folio/Searches, Explorer's %USERPROFILE%\Searches.
    public static func folder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Folio/Searches", isDirectory: true)
    }

    /// The file name a save starts with: the query, made safe for a file name.
    public static func suggestedName(for text: String) -> String {
        var name = text.trimmingCharacters(in: .whitespaces)
        for bad in ["/", ":", "\\", "\0"] { name = name.replacingOccurrences(of: bad, with: "-") }
        if name.isEmpty { name = "Search" }
        if name.count > 80 { name = String(name.prefix(80)) }
        return name + "." + fileExtension
    }

    // MARK: XML

    public func xml() -> String {
        let root = XMLElement(name: "persistedQuery")
        root.addAttribute(attr("version", "1.0"))
        root.addAttribute(attr("app", "Folio"))
        let viewInfo = XMLElement(name: "viewInfo")
        if let view { viewInfo.addAttribute(attr("viewMode", view)) }
        if let group {
            let g = XMLElement(name: "groupBy")
            g.addAttribute(attr("viewField", group.key.rawValue))
            g.addAttribute(attr("direction", group.ascending ? "ascending" : "descending"))
            viewInfo.addChild(g)
        }
        if !sort.isEmpty {
            let list = XMLElement(name: "sortList")
            for t in sort.prefix(4) {
                let s = XMLElement(name: "sort")
                s.addAttribute(attr("viewField", t.key.rawValue))
                s.addAttribute(attr("direction", t.ascending ? "ascending" : "descending"))
                list.addChild(s)
            }
            viewInfo.addChild(list)
        }
        root.addChild(viewInfo)
        let query = XMLElement(name: "query")
        let scope = XMLElement(name: "scope")
        let include = XMLElement(name: "include")
        switch location {
        case .folder(let url): include.addAttribute(attr("path", url.path))
        case .home: include.addAttribute(attr("knownFolder", "home"))
        case .thisPC: include.addAttribute(attr("knownFolder", "thisPC"))
        }
        include.addAttribute(attr("nonRecursive", recursive ? "false" : "true"))
        scope.addChild(include)
        query.addChild(scope)
        let text = XMLElement(name: "text", stringValue: self.text)
        query.addChild(text)
        root.addChild(query)
        let doc = XMLDocument(rootElement: root)
        doc.version = "1.0"
        doc.characterEncoding = "UTF-8"
        return doc.xmlString(options: [.nodePrettyPrint])
    }

    private func attr(_ name: String, _ value: String) -> XMLNode {
        XMLNode.attribute(withName: name, stringValue: value) as! XMLNode
    }

    public enum ReadError: Error, Equatable { case notASavedSearch }

    public init(xml: String) throws {
        let doc = try XMLDocument(xmlString: xml, options: [])
        guard let root = doc.rootElement(), root.name == "persistedQuery",
              let query = root.elements(forName: "query").first,
              let include = query.elements(forName: "scope").first?.elements(forName: "include").first else {
            throw ReadError.notASavedSearch
        }
        let text = query.elements(forName: "text").first?.stringValue ?? ""
        let location: SearchLocation
        if let path = include.attribute(forName: "path")?.stringValue {
            location = .folder(URL(fileURLWithPath: path, isDirectory: true))
        } else if include.attribute(forName: "knownFolder")?.stringValue == "thisPC" {
            location = .thisPC
        } else {
            location = .home
        }
        let recursive = include.attribute(forName: "nonRecursive")?.stringValue != "true"
        let viewInfo = root.elements(forName: "viewInfo").first
        let view = viewInfo?.attribute(forName: "viewMode")?.stringValue
        var sort: [SortTerm] = []
        for s in viewInfo?.elements(forName: "sortList").first?.elements(forName: "sort") ?? [] {
            guard let raw = s.attribute(forName: "viewField")?.stringValue, let key = ColumnID(rawValue: raw) else { continue }
            sort.append(SortTerm(key: key, ascending: s.attribute(forName: "direction")?.stringValue != "descending"))
        }
        var group: GroupSpec?
        if let g = viewInfo?.elements(forName: "groupBy").first, let raw = g.attribute(forName: "viewField")?.stringValue,
           let key = ColumnID(rawValue: raw) {
            group = GroupSpec(key: key, ascending: g.attribute(forName: "direction")?.stringValue != "descending")
        }
        self.init(text: text, location: location, recursive: recursive, view: view, sort: sort, group: group)
    }

    /// Writes the file (making the folder first); returns where it went.
    @discardableResult
    public func write(to url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try xml().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public static func read(from url: URL) throws -> SavedSearch {
        try SavedSearch(xml: String(contentsOf: url, encoding: .utf8))
    }
}

/// The Recent searches dropdown under the box: the last 10 queries, newest first, no repeats.
public struct RecentSearches {
    public static let key = "recentSearches"
    public static let limit = 10
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public var items: [String] { defaults.stringArray(forKey: Self.key) ?? [] }

    public func record(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var list = items.filter { $0 != t }
        list.insert(t, at: 0)
        defaults.set(Array(list.prefix(Self.limit)), forKey: Self.key)
    }

    public func clear() { defaults.removeObject(forKey: Self.key) }
}

/// The Search options menu writes AQS into the box; the box text is the only filter state. A pick
/// replaces a term for the same property already there, or is added at the end.
public enum SearchBoxText {
    /// Top-level pieces split on spaces outside quotes and brackets.
    static func chunks(_ text: String) -> [String] {
        var out: [String] = [], cur = ""
        var depth = 0, quoted = false
        for c in text {
            if c == "\"" { quoted.toggle() }
            if !quoted { if c == "(" { depth += 1 } else if c == ")" { depth = max(0, depth - 1) } }
            if c.isWhitespace && depth == 0 && !quoted {
                if !cur.isEmpty { out.append(cur); cur = "" }
            } else {
                cur.append(c)
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// The property a chunk sets ("datemodified:today" is .modified), nil for a plain word.
    static func property(of chunk: String) -> SearchProperty? {
        var c = Substring(chunk)
        while c.hasPrefix("-") { c = c.dropFirst() }
        guard let colon = c.firstIndex(of: ":") else { return nil }
        return SearchProperty.named(String(c[..<colon]))
    }

    /// Text with `property:value` in place of any term for the same property (date words written
    /// apart, "this week", go as one).
    public static func setting(_ property: SearchProperty, to value: String, in text: String) -> String {
        var parts = removing(property, from: chunks(text))
        parts.append(property.keyword + ":" + value)
        return parts.joined(separator: " ")
    }

    /// Text with every term for `property` taken out.
    public static func clearing(_ property: SearchProperty, in text: String) -> String {
        removing(property, from: chunks(text)).joined(separator: " ")
    }

    static func removing(_ property: SearchProperty, from parts: [String]) -> [String] {
        var out: [String] = []
        var skipUnit = false
        for p in parts {
            if skipUnit {
                skipUnit = false
                if ["week", "month", "year"].contains(p.lowercased()) { continue }
            }
            if let prop = Self.property(of: p), same(prop, property) {
                let value = p.split(separator: ":", maxSplits: 1).last.map(String.init)?.lowercased() ?? ""
                skipUnit = property.isDate && ["this", "last", "next", "past", "coming"].contains(value)
                continue
            }
            out.append(p)
        }
        return out
    }

    /// Date modified and date are one menu.
    static func same(_ a: SearchProperty, _ b: SearchProperty) -> Bool {
        let dates: Set<SearchProperty> = [.date, .modified]
        return a == b || (dates.contains(a) && dates.contains(b))
    }

    /// The value written for `property`, for the chip ("today", "this week", "=document"); nil when absent.
    public static func value(of property: SearchProperty, in text: String) -> String? {
        let parts = chunks(text)
        for (i, p) in parts.enumerated() {
            guard let prop = Self.property(of: p), same(prop, property), !p.hasPrefix("-") else { continue }
            var value = p.split(separator: ":", maxSplits: 1).count == 2 ? String(p.split(separator: ":", maxSplits: 1)[1]) : ""
            if property.isDate, ["this", "last", "next", "past", "coming"].contains(value.lowercased()), i + 1 < parts.count,
               ["week", "month", "year"].contains(parts[i + 1].lowercased()) {
                value += " " + parts[i + 1]
            }
            if value.hasPrefix("=") { value.removeFirst() }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Other properties: `name:` at the end, the caret after its colon.
    public static func appendingKeyword(_ property: SearchProperty, to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return (trimmed.isEmpty ? "" : trimmed + " ") + property.keyword + ":"
    }
}
