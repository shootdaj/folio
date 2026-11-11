import AppKit
import Darwin

/// Timing for the VM speed harness (Tests/vm/perf.sh). Off unless Folio is started with
/// `-perfTrace <file>` (a launch argument, never a saved setting); then each mark is one line in that file,
/// "<wall-clock seconds> <name> key=value ...", which the script subtracts from its own clock or from
/// another mark. A run-loop observer writes "stall ms=..." for every turn that kept the main thread busy
/// for 16 ms or more (a dropped frame at 60 Hz). Nothing here runs when the argument is absent.
@MainActor
enum PerfTrace {
    private static let handle: FileHandle? = {
        guard let path = UserDefaults.standard.string(forKey: "perfTrace"), !path.isEmpty else { return nil }
        // Appended to, never emptied: the script counts lines across launches.
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        let h = FileHandle(forWritingAtPath: path)
        h?.seekToEndOfFile()
        return h
    }()

    static var isOn: Bool { handle != nil }

    /// Seconds on the wall clock, for marks and for the script's own `now`.
    static var now: Double { Date().timeIntervalSince1970 }

    static func mark(_ name: String, _ fields: String = "") {
        guard let handle else { return }
        let line = String(format: "%.4f ", now) + name + (fields.isEmpty ? "" : " " + fields) + "\n"
        handle.write(Data(line.utf8))
    }

    /// Milliseconds since `start` (a `now` value), one decimal.
    static func ms(since start: Double) -> String { String(format: "%.1f", (now - start) * 1000) }

    /// The process's physical footprint in MB (what Activity Monitor calls Memory).
    static var footprintMB: String {
        var info = rusage_info_v4()
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        return kr == 0 ? String(format: "%.1f", Double(info.ri_phys_footprint) / 1_048_576) : "-1"
    }

    private static var busySince = 0.0
    private static var observers: [CFRunLoopObserver] = []

    /// Starts the main-thread stall monitor (once, at launch, when tracing).
    static func start() {
        guard isOn, observers.isEmpty else { return }
        mark("launched", "launch_ms=" + String(format: "%.1f", (now - processStartDate.timeIntervalSince1970) * 1000))
        busySince = now
        // Woken: the turn starts. The first observer of all (lowest order).
        let woke = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { _, _ in
            MainActor.assumeIsolated { busySince = now }
        }
        // About to sleep: the turn ends, after Core Animation's commit (layout, drawing) has run (highest order).
        let sleeps = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { _, _ in
            MainActor.assumeIsolated {
                let busy = (now - busySince) * 1000
                if busy >= 16 { mark("stall", String(format: "ms=%.1f", busy)) }
                busySince = now
            }
        }
        for o in [woke, sleeps].compactMap({ $0 }) {
            CFRunLoopAddObserver(CFRunLoopGetMain(), o, .commonModes)
            observers.append(o)
        }
    }
}
