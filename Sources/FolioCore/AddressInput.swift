import Foundation

/// The places an address can name besides plain paths: home, the temp folder and the environment.
public struct AddressEnvironment: Sendable {
    public var home: URL
    public var temp: URL
    public var variables: [String: String]

    public init(home: URL, temp: URL, variables: [String: String]) {
        self.home = home
        self.temp = temp
        self.variables = variables
    }

    /// This process's home, $TMPDIR and environment.
    public static var current: AddressEnvironment {
        AddressEnvironment(home: FileManager.default.homeDirectoryForCurrentUser,
                           temp: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
                           variables: ProcessInfo.processInfo.environment)
    }
}

/// Typed or pasted addresses, read leniently the way Explorer reads them: quotes around a pasted
/// path, doubled slashes, `~`, `%appdata%`-style and `$HOME`-style variables and `shell:` names.
public enum AddressInput {
    /// The text with quotes dropped and every shorthand expanded. A trailing slash is kept (the
    /// completer reads it as "list what is inside"). Nil for an empty field or a Windows-only `shell:` name.
    public static func expand(_ text: String, env: AddressEnvironment) -> String? {
        var s = unquote(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("shell:") {
            guard let mapped = shellFolder(String(s.dropFirst(6)), env: env) else { return nil }
            s = mapped
        }
        s = percentVariables(s, env: env)
        s = dollarVariables(s, env: env)
        if s == "~" {
            s = trimmed(env.home.path)
        } else if s.hasPrefix("~/") {
            s = trimmed(env.home.path) + s.dropFirst(1)
        }
        return s
    }

    /// The folder the address points at, with `.` and `..` worked out on the text (so `/private/tmp`
    /// stays as typed). Relative addresses start at `current`. Whether it exists is the caller's check.
    public static func resolve(_ text: String, current: URL, env: AddressEnvironment) -> URL? {
        guard let expanded = expand(text, env: env) else { return nil }
        let absolute = expanded.hasPrefix("/") ? expanded : trimmed(current.path) + "/" + expanded
        return URL(fileURLWithPath: "/" + Breadcrumbs.components(of: absolute).joined(separator: "/"), isDirectory: true)
    }

    // MARK: Pieces

    private static let quotePairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("\u{201C}", "\u{201D}"), ("\u{2018}", "\u{2019}")]

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, let first = s.first, let last = s.last,
              quotePairs.contains(where: { $0.0 == first && $0.1 == last }) else { return s }
        return String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// `shell:` names that have a Mac place. Keys are lowercased with spaces removed.
    private static func shellFolder(_ rest: String, env: AddressEnvironment) -> String? {
        let slash = rest.firstIndex(of: "/")
        let name = String(slash.map { rest[..<$0] } ?? rest[...]).lowercased().replacingOccurrences(of: " ", with: "")
        let tail = slash.map { String(rest[$0...]) } ?? ""
        let home = trimmed(env.home.path)
        let places: [String: String] = [
            "desktop": home + "/Desktop",
            "downloads": home + "/Downloads",
            "personal": home + "/Documents", "mydocuments": home + "/Documents", "documentslibrary": home + "/Documents",
            "mypictures": home + "/Pictures", "pictureslibrary": home + "/Pictures",
            "mymusic": home + "/Music", "musiclibrary": home + "/Music",
            "myvideo": home + "/Movies", "videoslibrary": home + "/Movies",
            "profile": home, "usersfilesfolder": home,
            "userprofiles": "/Users", "public": "/Users/Shared",
            "appdata": home + "/Library/Application Support",
            "localappdata": home + "/Library",
            "cache": home + "/Library/Caches",
            "fonts": home + "/Library/Fonts",
            "startup": home + "/Library/LaunchAgents", "commonstartup": "/Library/LaunchAgents",
            "appsfolder": "/Applications", "programfiles": "/Applications", "programfilesx86": "/Applications",
            "recyclebinfolder": home + "/.Trash",
            "mycomputerfolder": "/Volumes",
            "windows": "/System", "system": "/System/Library",
        ]
        return places[name].map { $0 + tail }
    }

    /// `%name%`, case-insensitive. Windows names map to Mac places; others come from the environment;
    /// unknown ones stay as typed.
    private static func percentVariables(_ s: String, env: AddressEnvironment) -> String {
        guard s.contains("%") else { return s }
        let home = trimmed(env.home.path)
        let known: [String: String] = [
            "userprofile": home, "homepath": home, "homedrive": "", "systemdrive": "",
            "appdata": home + "/Library/Application Support", "localappdata": home + "/Library",
            "temp": trimmed(env.temp.path), "tmp": trimmed(env.temp.path),
            "public": "/Users/Shared", "programfiles": "/Applications",
            "systemroot": "/System", "windir": "/System",
        ]
        var out = ""
        var rest = Substring(s)
        while let open = rest.firstIndex(of: "%") {
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "%") else { break }
            let name = String(rest[afterOpen..<close])
            let value = name.isEmpty ? nil : known[name.lowercased()] ?? env.variables[name] ?? env.variables[name.uppercased()]
            out += rest[..<open]
            if let value {
                out += value
                rest = rest[rest.index(after: close)...]
            } else {
                // Not a variable: keep the first % and look again from the second.
                out += "%" + rest[afterOpen..<close]
                rest = rest[close...]
            }
        }
        return out + rest
    }

    /// `$NAME` and `${NAME}`. HOME and TMPDIR come from the environment model; unknown names stay.
    private static func dollarVariables(_ s: String, env: AddressEnvironment) -> String {
        guard s.contains("$") else { return s }
        func value(_ name: String) -> String? {
            switch name {
            case "HOME": trimmed(env.home.path)
            case "TMPDIR": trimmed(env.temp.path)
            default: env.variables[name].map(trimmed)
            }
        }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            guard s[i] == "$" else { out.append(s[i]); i = s.index(after: i); continue }
            let start = s.index(after: i)
            if start < s.endIndex, s[start] == "{", let close = s[start...].firstIndex(of: "}") {
                let name = String(s[s.index(after: start)..<close])
                if let v = value(name) { out += v; i = s.index(after: close); continue }
            } else {
                var end = start
                while end < s.endIndex, s[end].isLetter || s[end].isNumber || s[end] == "_" { end = s.index(after: end) }
                if end > start, let v = value(String(s[start..<end])) { out += v; i = end; continue }
            }
            out.append("$")
            i = start
        }
        return out
    }
}
