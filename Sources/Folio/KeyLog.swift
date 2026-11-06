import AppKit

/// Appends one line per key event the window receives to ~/Library/Logs/Folio/keys.log, so a key that
/// "does nothing" can be traced: what arrived (after Karabiner and BetterTouchTool), who had focus, and
/// whether Folio's handler took it. Cheap enough to leave on.
enum KeyLog {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Folio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("keys.log")
    }()
    private static let queue = DispatchQueue(label: "folio.keylog")
    private static let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

    static func mods(_ event: NSEvent) -> String {
        let f = event.modifierFlags
        var m = [String]()
        if f.contains(.command) { m.append("cmd") }
        if f.contains(.option) { m.append("opt") }
        if f.contains(.control) { m.append("ctrl") }
        if f.contains(.shift) { m.append("shift") }
        if f.contains(.function) { m.append("fn") }
        return m.isEmpty ? "-" : m.joined(separator: "+")
    }

    static func write(_ line: String) {
        let text = "\(stamp.string(from: Date())) \(line)\n"
        queue.async {
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
            else { try? text.write(to: url, atomically: true, encoding: .utf8) }
        }
    }
}
