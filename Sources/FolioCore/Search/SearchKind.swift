import Foundation
import UniformTypeIdentifiers

/// Explorer's 23 kinds (System.Kind), as the Search options Kind menu lists them. Spotlight's type trees
/// are broader than Windows' KindMap (public.archive matched a raw .bin), so an extension table decides
/// a file's kind and the types only find candidates and cover extensions the table does not know.
public enum SearchKind: String, CaseIterable, Sendable {
    case calendar, communication, contact, document, email, feed, folder, game, instantMessage, journal, link
    case movie, music, note, picture, playlist, program, recordedTV, savedSearch, task, video, webHistory, unknown

    /// The menu text.
    public var title: String {
        switch self {
        case .calendar: "Calendar"
        case .communication: "Communication"
        case .contact: "Contact"
        case .document: "Document"
        case .email: "E-mail"
        case .feed: "Feed"
        case .folder: "Folder"
        case .game: "Game"
        case .instantMessage: "Instant Message"
        case .journal: "Journal"
        case .link: "Link"
        case .movie: "Movie"
        case .music: "Music"
        case .note: "Note"
        case .picture: "Picture"
        case .playlist: "Playlist"
        case .program: "Program"
        case .recordedTV: "Recorded TV"
        case .savedSearch: "Saved Search"
        case .task: "Task"
        case .video: "Video"
        case .webHistory: "Web History"
        case .unknown: "Unknown"
        }
    }

    /// What the menu writes after `kind:=`.
    public var keyword: String {
        switch self {
        case .instantMessage: "im"
        case .recordedTV: "tv"
        case .savedSearch: "search"
        case .webHistory: "webhistory"
        default: rawValue.lowercased()
        }
    }

    /// The System.Kind mnemonics `kind:` accepts (multi-word ones also joined).
    public var mnemonics: [String] {
        switch self {
        case .calendar: ["calendar", "calendars", "meeting", "meetings", "appointment", "appointments"]
        case .communication: ["communication", "communications"]
        case .contact: ["contact", "contacts", "person", "people"]
        case .document: ["document", "documents", "doc", "docs"]
        case .email: ["email", "emails", "e-mail", "e-mails", "message", "messages", "mail"]
        case .feed: ["feed", "feeds"]
        case .folder: ["folder", "folders"]
        case .game: ["game", "games"]
        case .instantMessage: ["instant message", "instant messages", "instantmessage", "instantmessages", "im", "ims"]
        case .journal: ["journal", "journals"]
        case .link: ["link", "links", "shortcut", "shortcuts"]
        case .movie: ["movie", "movies", "film", "films"]
        case .music: ["music", "song", "songs"]
        case .note: ["note", "notes"]
        case .picture: ["picture", "pictures", "pic", "pics", "image", "images", "photo", "photos"]
        case .playlist: ["playlist", "playlists"]
        case .program: ["program", "programs", "app", "apps", "application", "applications"]
        case .recordedTV: ["tv", "recorded tv", "recordedtv"]
        case .savedSearch: ["saved search", "savedsearch", "search", "searches"]
        case .task: ["task", "tasks"]
        case .video: ["video", "videos"]
        case .webHistory: ["web history", "webhistory", "history", "webpage", "webpages"]
        case .unknown: ["unknown"]
        }
    }

    public static func named(_ name: String) -> SearchKind? {
        let n = name.lowercased()
        return allCases.first { $0.mnemonics.contains(n) }
    }

    private static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "qt", "avi", "wmv", "mkv", "webm", "mpg", "mpeg",
                                                         "m2ts", "mts", "3gp", "3g2", "flv", "ogv", "vob", "asf"]

    /// Windows' KindMap, as extensions (lowercased, no dot).
    public var extensions: Set<String> {
        switch self {
        case .calendar: ["ics", "ical", "icalendar", "vcs", "ifb"]
        case .communication: Self.email.extensions.union(Self.instantMessage.extensions)
        case .contact: ["vcf", "vcard", "contact", "abcdp"]
        case .document: ["txt", "text", "md", "markdown", "rtf", "rtfd", "doc", "docx", "docm", "dot", "dotx", "odt", "ott",
                         "pdf", "xps", "oxps", "wpd", "wps", "wri", "pages", "key", "numbers", "xls", "xlsx", "xlsm",
                         "xlsb", "csv", "tsv", "ods", "ppt", "pptx", "pptm", "pps", "ppsx", "odp", "epub", "log", "tex"]
        case .email: ["eml", "emlx", "msg", "mbox", "mbx"]
        case .feed: ["rss", "atom"]
        case .folder, .game, .task, .unknown: []
        case .instantMessage: ["ichat"]
        case .journal: ["jnt", "journal"]
        case .link: ["url", "webloc", "inetloc", "lnk", "fileloc"]
        case .movie, .video: Self.videoExtensions
        case .music: ["mp3", "m4a", "m4b", "m4p", "aac", "wav", "aif", "aiff", "aifc", "flac", "alac", "wma", "ogg", "oga",
                      "opus", "mid", "midi", "caf", "ape"]
        case .note: ["one", "onetoc2", "note"]
        case .picture: ["jpg", "jpeg", "jpe", "jfif", "png", "gif", "bmp", "dib", "tif", "tiff", "heic", "heif", "webp",
                        "ico", "icns", "svg", "psd", "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "jxl",
                        "avif", "tga", "exr"]
        case .playlist: ["m3u", "m3u8", "pls", "wpl", "xspf", "asx"]
        case .program: ["app", "exe", "com", "bat", "cmd", "msi", "pkg", "mpkg", "command", "tool"]
        case .recordedTV: ["dvr-ms", "wtv"]
        case .savedSearch: ["foliosearch", "savedsearch", "search-ms"]
        case .webHistory: ["htm", "html", "mht", "mhtml", "webarchive"]
        }
    }

    /// Uniform types whose trees mark this kind, for the Spotlight query and for files with extensions
    /// the table does not know.
    public var contentTypes: [String] {
        switch self {
        case .calendar: ["public.calendar-event"]
        case .contact: ["public.vcard"]
        case .document: ["public.composite-content", "com.adobe.pdf", "public.spreadsheet", "public.presentation", "public.plain-text"]
        case .email: ["public.email-message", "com.apple.mail.emlx"]
        case .folder: ["public.folder"]
        case .link: ["com.apple.alias-file", "public.symlink", "public.url", "com.apple.web-internet-location"]
        case .movie, .video: ["public.movie"]
        case .music: ["public.audio"]
        case .picture: ["public.image"]
        case .playlist: ["public.playlist", "public.m3u-playlist"]
        case .program: ["com.apple.application"]
        case .communication: Self.email.contentTypes
        default: []
        }
    }

    /// Types that decide the kind of a file the table does not know (media and apps, not "text").
    private var fallbackTypes: [UTType] {
        switch self {
        case .picture: [.image]
        case .music: [.audio]
        case .movie, .video: [.movie]
        case .program: [.application]
        case .contact: [.vCard]
        case .calendar: [.calendarEvent]
        case .link: [.aliasFile, .symbolicLink, .internetShortcut]
        case .playlist: [.playlist]
        default: []
        }
    }

    /// The kinds of one item: Folder for a folder; else the kinds whose table lists its extension; else
    /// the kinds its type falls under; else Unknown. Aliases and symlinks are Links.
    public static func kinds(name: String, isFolder: Bool, isLink: Bool = false, contentType: String? = nil) -> Set<SearchKind> {
        if isFolder { return isLink ? [.folder, .link] : [.folder] }
        let ext = (name as NSString).pathExtension.lowercased()
        var out = Set<SearchKind>()
        if !ext.isEmpty { out = Set(allCases.filter { $0.extensions.contains(ext) }) }
        if out.isEmpty, let id = contentType, let type = UTType(id) {
            out = Set(allCases.filter { kind in kind.fallbackTypes.contains { type.conforms(to: $0) } })
        }
        if isLink { out.insert(.link) }
        return out.isEmpty ? [.unknown] : out
    }
}
