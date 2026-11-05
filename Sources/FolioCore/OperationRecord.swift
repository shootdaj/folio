import Foundation

/// An item that went somewhere: a move, a rename, a copy (source to the copy).
public struct Pair: Sendable, Equatable {
    public let from: URL
    public let to: URL

    public init(from: URL, to: URL) {
        self.from = from
        self.to = to
    }
}

/// An item in the Trash and where it came from, so undo can put it back.
public struct TrashedItem: Sendable, Equatable {
    public let original: URL
    public let inTrash: URL

    public init(original: URL, inTrash: URL) {
        self.original = original
        self.inTrash = inTrash
    }
}

/// What one finished operation changed, enough to undo and redo it.
public enum OperationRecord: Sendable, Equatable {
    /// `copied` runs source to copy; `replaced` are the items Replace sent to the Trash.
    case copy(copied: [Pair], replaced: [TrashedItem])
    /// `moved` at the level each item went (whole items, or files inside merged folders), the folders the
    /// move made in the destination and the emptied source folders it removed.
    case move(moved: [Pair], createdFolders: [URL], removedFolders: [URL], replaced: [TrashedItem])
    case rename([Pair])
    case trash([TrashedItem])
    case newFolder(URL)
    case newFile(URL)
    /// Create alias, Create symbolic link, Paste shortcut, Send to Desktop, a link drop.
    case links([LinkItem])

    /// The Edit menu names the action: Undo Rename, Redo Move.
    public var title: String {
        switch self {
        case .copy: "Copy"
        case .move: "Move"
        case .rename: "Rename"
        case .trash: "Delete"
        case .newFolder: "New Folder"
        case .newFile: "New Text Document"
        case .links(let items): items.first?.kind == .symlink ? "Create Symbolic Link" : "Create Alias"
        }
    }
}

/// Many steps of undo and redo, newest last. A new operation clears the redo steps.
public struct UndoHistory: Sendable, Equatable {
    public private(set) var undoSteps: [OperationRecord] = []
    public private(set) var redoSteps: [OperationRecord] = []
    public let limit: Int

    public init(limit: Int = 100) { self.limit = limit }

    public mutating func record(_ step: OperationRecord) {
        undoSteps.append(step)
        if undoSteps.count > limit { undoSteps.removeFirst(undoSteps.count - limit) }
        redoSteps.removeAll()
    }

    public var undoTitle: String? { undoSteps.last.map { "Undo " + $0.title } }
    public var redoTitle: String? { redoSteps.last.map { "Redo " + $0.title } }

    /// Takes the step to undo; call `didUndo` once it is undone (or drop it if undo failed).
    public mutating func takeUndo() -> OperationRecord? { undoSteps.popLast() }
    public mutating func didUndo(_ step: OperationRecord) { redoSteps.append(step) }

    /// Takes the step to redo; `didRedo` gets the record of the redone work (new Trash places).
    public mutating func takeRedo() -> OperationRecord? { redoSteps.popLast() }
    public mutating func didRedo(_ step: OperationRecord) { undoSteps.append(step) }
}

/// Where deleted items go. The app uses the macOS Trash; tests use a folder in their temp tree.
public protocol Trasher: Sendable {
    /// Moves the item to the Trash and returns where it now is.
    func trash(_ url: URL) throws -> URL
}

/// The macOS Trash (`FileManager.trashItem`), per volume, like Explorer's Recycle Bin.
public struct SystemTrash: Trasher {
    public init() {}

    public func trash(_ url: URL) throws -> URL {
        var out: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &out)
        return (out as URL?) ?? url
    }
}

/// A stand-in Trash: a folder (inside a test's own temp tree) that keeps each item under a fresh id.
public struct FolderTrash: Trasher {
    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    public func trash(_ url: URL) throws -> URL {
        let slot = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
        let target = slot.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }
}

/// Bytes per second over the last second of a job, and the readouts built from it.
public struct SpeedMeter: Sendable, Equatable {
    public let window: Double
    private var samples: [Sample] = []

    struct Sample: Sendable, Equatable { let t: Double; let bytes: Int64 }

    public init(window: Double = 1) { self.window = window }

    public mutating func record(bytes: Int64, at t: Double) {
        samples.append(Sample(t: t, bytes: bytes))
        // Keep one sample at or before the window's start as the baseline.
        while samples.count > 2, samples[1].t <= t - window { samples.removeFirst() }
    }

    /// After a pause or a wait, the gap must not count as slow copying.
    public mutating func restart(bytes: Int64, at t: Double) {
        samples = [Sample(t: t, bytes: bytes)]
    }

    /// Bytes per second from the baseline to `now`; 0 until there is 0.1 s of history.
    public func bytesPerSecond(at now: Double) -> Double {
        guard let last = samples.last else { return 0 }
        let base = samples.last(where: { $0.t <= now - window }) ?? samples[0]
        let span = now - base.t
        guard span >= 0.1 else { return 0 }
        return Double(last.bytes - base.bytes) / span
    }
}

public enum ProgressText {
    /// D1's speed readout: "412 MB/s", "4.2 MB/s", "850 KB/s".
    public static func speed(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        if v >= 1e9 { return String(format: "%.1f GB/s", v / 1e9) }
        if v >= 1e7 { return String(format: "%.0f MB/s", v / 1e6) }
        if v >= 1e6 { return String(format: "%.1f MB/s", v / 1e6) }
        return String(format: "%.0f KB/s", v / 1e3)
    }

    /// "6 s", "1 min 5 s", "2 h 3 min".
    public static func timeLeft(_ seconds: Double) -> String {
        let s = max(1, Int(seconds.rounded(.up)))
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min" + (s % 60 > 0 ? " \(s % 60) s" : "") }
        return "\(s / 3600) h" + ((s % 3600) / 60 > 0 ? " \((s % 3600) / 60) min" : "")
    }

    /// D1's graph readout, "2.21 GB of 4.83 GB"; smaller jobs in MB or KB.
    public static func bytesOf(_ done: Int64, _ total: Int64) -> String {
        "\(amount(done, scale: total)) of \(amount(total, scale: total))"
    }

    private static func amount(_ b: Int64, scale: Int64) -> String {
        let v = Double(max(0, b))
        if scale >= 1_000_000_000 { return String(format: "%.2f GB", v / 1e9) }
        if scale >= 1_000_000 { return String(format: "%.1f MB", v / 1e6) }
        return String(format: "%.0f KB", (v / 1e3).rounded(.up))
    }
}
