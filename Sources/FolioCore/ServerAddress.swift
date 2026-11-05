import Foundation

/// A network place typed in the address bar or Connect to server: the share to mount and the folders
/// to open inside it once it is mounted.
public struct ServerTarget: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case smb, afp, nfs, webDAV, ftp }

    /// The server and share (smb://nas/media), or just the server (macOS then asks for a share).
    public let share: URL
    /// Folders below the share (\\nas\media\films gives ["films"]).
    public let rest: [String]
    public let kind: Kind
}

/// Explorer's UNC paths and the Mac's server URLs: \\server\share\folder, smb://, afp://, nfs://,
/// http(s):// for WebDAV (read and write) and ftp:// (read-only), all mounted under /Volumes.
public enum ServerAddress {
    public static func parse(_ text: String) -> ServerTarget? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        if typed.hasPrefix(#"\\"#) {
            let parts = typed.dropFirst(2).split(separator: "\\", omittingEmptySubsequences: true).map(String.init)
            guard let server = parts.first else { return nil }
            return make(scheme: "smb", user: nil, host: server, parts: Array(parts.dropFirst()), kind: .smb, shareDepth: 1)
        }
        guard let url = URL(string: typed) ?? URL(string: typed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? ""),
              let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        switch scheme {
        case "smb", "cifs": return make(scheme: "smb", user: url.user, host: host, port: url.port, parts: parts, kind: .smb, shareDepth: 1)
        case "afp": return make(scheme: "afp", user: url.user, host: host, port: url.port, parts: parts, kind: .afp, shareDepth: 1)
        // An NFS export is a whole path; folders inside it are opened after mounting.
        case "nfs": return make(scheme: "nfs", user: nil, host: host, port: url.port, parts: parts, kind: .nfs, shareDepth: parts.count)
        case "http", "https", "webdav", "webdavs":
            let s = scheme.hasSuffix("s") ? "https" : "http"
            return make(scheme: s, user: url.user, host: host, port: url.port, parts: parts, kind: .webDAV, shareDepth: parts.count)
        case "ftp": return make(scheme: "ftp", user: url.user, host: host, port: url.port, parts: parts, kind: .ftp, shareDepth: parts.count)
        default: return nil
        }
    }

    public static func isServerAddress(_ text: String) -> Bool { parse(text) != nil }

    private static func make(scheme: String, user: String?, host: String, port: Int? = nil, parts: [String],
                             kind: ServerTarget.Kind, shareDepth: Int) -> ServerTarget? {
        var c = URLComponents()
        c.scheme = scheme
        c.user = user
        c.host = host
        c.port = port
        let share = Array(parts.prefix(shareDepth))
        c.path = share.isEmpty ? "" : "/" + share.joined(separator: "/")
        guard let url = c.url else { return nil }
        return ServerTarget(share: url, rest: Array(parts.dropFirst(shareDepth)), kind: kind)
    }
}

/// Map network drive: shares remembered (as URL strings) and mounted again when Folio starts.
public struct MappedShares {
    public static let key = "mappedShares"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var urls: [String] { defaults.stringArray(forKey: Self.key) ?? [] }

    public func contains(_ url: String) -> Bool { urls.contains(url) }

    public mutating func add(_ url: String) {
        guard !contains(url) else { return }
        defaults.set(urls + [url], forKey: Self.key)
    }

    public mutating func remove(_ url: String) {
        defaults.set(urls.filter { $0 != url }, forKey: Self.key)
    }
}
