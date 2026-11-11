import AppKit
import FolioCore
import NetFS
import Network

/// Drives and network places for every window: the mounted volumes (read again when macOS mounts,
/// unmounts or renames one), Eject, Rename (diskutil), opening disk images (hdiutil attach), network
/// shares mounted through NetFS (which asks for a password and offers to keep it in the Keychain),
/// mapped shares mounted again at launch, and Bonjour's SMB servers for Browse network.
@MainActor
final class VolumeCenter {
    static let shared = VolumeCenter()
    static let didChange = Notification.Name("FolioVolumesChanged")
    static let serversChanged = Notification.Name("FolioServersChanged")

    private(set) var volumes: [VolumeCapacity] = []
    private(set) var servers: [String] = []
    /// Shown in the Network group when browsing could not run (Local Network permission denied).
    private(set) var browseNotice: String?
    private(set) var browseStatus = "Browse network"
    private var started = false
    private var browser: NWBrowser?
    private var requests: [AsyncRequestID] = []

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { VolumeCenter.shared.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        Task.detached(priority: .utility) {
            let list = VolumeCapacity.mounted()
            await MainActor.run {
                VolumeCenter.shared.volumes = list
                NotificationCenter.default.post(name: VolumeCenter.didChange, object: nil)
            }
        }
    }

    // MARK: Eject, rename

    /// The sidebar's Eject button, File > Eject and the drive's menu: unmount and eject (a disk image
    /// detaches, a share disconnects). Windows on the drive go Home.
    func eject(_ volume: VolumeCapacity, window: NSWindow?) {
        let url = URL(fileURLWithPath: volume.path, isDirectory: true)
        Task.detached(priority: .userInitiated) {
            // A mounted disk image is detached (hdiutil), as Explorer's Eject unmounts an ISO; anything
            // else is unmounted and ejected by macOS.
            let result = Result {
                if Self.imageMountPoints().contains(volume.path) {
                    try Self.detachImage(at: volume.path)
                } else {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                }
            }
            await MainActor.run {
                if case .failure(let error) = result {
                    OperationCenter.shared.present(error, window: window)
                }
                VolumeCenter.shared.refresh()
            }
        }
    }

    /// F2 on a drive: diskutil rename, then the list reads the new name.
    func rename(_ volume: VolumeCapacity, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Rename \u{201C}\(volume.name)\u{201D}"
        alert.informativeText = "The new name for this drive:"
        let field = NSTextField(string: volume.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard response == .alertFirstButtonReturn, !name.isEmpty, name != volume.name else { return }
            Self.run("/usr/sbin/diskutil", ["rename", volume.path, name]) { status, output in
                if status != 0 { OperationCenter.shared.present(FileOpError.system(output), window: window) }
                VolumeCenter.shared.refresh()
            }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: finish) } else { finish(alert.runModal()) }
    }

    // MARK: Disk images

    static let imageExtensions: Set<String> = ["dmg", "iso", "img", "cdr", "sparseimage", "sparsebundle", "toast"]

    static func isDiskImage(_ url: URL) -> Bool { imageExtensions.contains(url.pathExtension.lowercased()) }

    /// Opening a .dmg or .iso mounts it with hdiutil and opens the new drive; Eject detaches it.
    func mountImage(_ url: URL, window: NSWindow?, then open: @escaping (URL) -> Void) {
        Self.run("/usr/bin/hdiutil", ["attach", "-plist", "-noverify", url.path]) { status, output in
            guard status == 0, let data = output.data(using: .utf8),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let entities = plist["system-entities"] as? [[String: Any]],
                  let mount = entities.compactMap({ $0["mount-point"] as? String }).first else {
                OperationCenter.shared.present(FileOpError.system(status == 0 ? "The image has no volume to open." : output), window: window)
                return
            }
            VolumeCenter.shared.refresh()
            open(URL(fileURLWithPath: mount, isDirectory: true))
        }
    }

    // MARK: Network

    /// \\server\share, smb://, afp://, nfs://, WebDAV and FTP: mounted under /Volumes, then `open` gets
    /// the folder inside it. NetFS shows the password prompt with "Remember this password in my
    /// keychain", and the share chooser when only a server was given.
    func mount(_ target: ServerTarget, window: NSWindow?, quiet: Bool = false, then open: ((URL) -> Void)? = nil) {
        let options = NSMutableDictionary()
        options[kNAUIOptionKey] = quiet ? kNAUIOptionNoUI : kNAUIOptionAllowUI
        var request: AsyncRequestID?
        let rest = target.rest
        let status = NetFSMountURLAsync(target.share as CFURL, nil, nil, nil, options, nil, &request, .main) { status, _, mounts in
            let points = (mounts as? [String]) ?? []
            MainActor.assumeIsolated {
                // ECANCELED (89) or a user cancel: nothing to say.
                if status != 0 || points.isEmpty {
                    if !quiet && status != 89 && status != -128 {
                        let text = "Could not connect to \(target.share.absoluteString) (error \(status))."
                        OperationCenter.shared.present(FileOpError.system(text), window: window)
                    }
                    return
                }
                VolumeCenter.shared.refresh()
                var url = URL(fileURLWithPath: points[0], isDirectory: true)
                for part in rest { url.appendPathComponent(part, isDirectory: true) }
                open?(url)
            }
        }
        if status != 0, !quiet {
            OperationCenter.shared.present(FileOpError.system("Could not start connecting to \(target.share.absoluteString)."), window: window)
        }
        if let request { requests.append(request) }
    }

    /// Connect to server... (and Map network drive with Reconnect at sign-in ticked).
    func connectToServer(window: NSWindow?, then open: @escaping (URL) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Connect to server"
        alert.informativeText = "A share or a server: \\\\server\\share, smb://server/share, afp://, nfs://, "
            + "https:// (WebDAV, read and write) or ftp:// (read-only)."
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 56))
        let field = NSTextField(string: "")
        field.placeholderString = "smb://server/share"
        field.frame = NSRect(x: 0, y: 30, width: 320, height: 24)
        let remember = NSButton(checkboxWithTitle: "Reconnect at sign-in (map this share)", target: nil, action: nil)
        remember.frame = NSRect(x: 0, y: 0, width: 320, height: 22)
        box.addSubview(field)
        box.addSubview(remember)
        alert.accessoryView = box
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            guard let target = ServerAddress.parse(field.stringValue) else {
                OperationCenter.shared.present(FileOpError.system("\u{201C}\(field.stringValue)\u{201D} is not a server address."), window: window)
                return
            }
            if remember.state == .on {
                var mapped = MappedShares(defaults: .standard)
                mapped.add(target.share.absoluteString)
            }
            VolumeCenter.shared.mount(target, window: window, then: open)
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: finish) } else { finish(alert.runModal()) }
    }

    /// At launch: every mapped share that is not mounted yet, quietly (Keychain passwords only).
    func remountMappedShares() {
        // At launch `volumes` is still being read: ask the mount table itself (no disk read).
        let mounted = Set((FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []).map(\.path))
        for raw in MappedShares(defaults: .standard).urls {
            guard let target = ServerAddress.parse(raw) else { continue }
            let name = target.share.lastPathComponent
            if !name.isEmpty, mounted.contains("/Volumes/" + name) { continue }
            mount(target, window: nil, quiet: true)
        }
    }

    /// Disconnect a share: unmount it and forget its mapping.
    func disconnect(_ volume: VolumeCapacity, window: NSWindow?) {
        var mapped = MappedShares(defaults: .standard)
        for raw in mapped.urls where ServerAddress.parse(raw)?.share.lastPathComponent == volume.name { mapped.remove(raw) }
        eject(volume, window: window)
    }

    /// Browse network: Bonjour's SMB servers, as Finder's Network sidebar finds them. macOS asks for
    /// Local Network permission the first time; denied, the group says so.
    func browse() {
        browser?.cancel()
        let b = NWBrowser(for: .bonjour(type: "_smb._tcp", domain: "local."), using: .tcp)
        browseStatus = "Searching the network..."
        NotificationCenter.default.post(name: Self.serversChanged, object: nil)
        b.browseResultsChangedHandler = { results, _ in
            let names = results.compactMap { result -> String? in
                if case .service(let name, _, _, _) = result.endpoint { return name }
                return nil
            }.sorted()
            Task { @MainActor in
                VolumeCenter.shared.servers = names
                VolumeCenter.shared.browseStatus = names.isEmpty ? "No servers found" : "Browse network"
                NotificationCenter.default.post(name: VolumeCenter.serversChanged, object: nil)
            }
        }
        b.stateUpdateHandler = { state in
            Task { @MainActor in
                switch state {
                case .failed(let error), .waiting(let error):
                    let denied = "\(error)".contains("-65570") || "\(error)".lowercased().contains("policy")
                    VolumeCenter.shared.browseNotice = denied ? "Local network access is off" : "Network browsing failed"
                    VolumeCenter.shared.browseStatus = "Browse network"
                case .ready:
                    VolumeCenter.shared.browseNotice = nil
                default:
                    break
                }
                NotificationCenter.default.post(name: VolumeCenter.serversChanged, object: nil)
            }
        }
        b.start(queue: .main)
        browser = b
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            MainActor.assumeIsolated {
                if VolumeCenter.shared.servers.isEmpty, VolumeCenter.shared.browseStatus.hasPrefix("Searching") {
                    VolumeCenter.shared.browseStatus = "No servers found"
                    NotificationCenter.default.post(name: VolumeCenter.serversChanged, object: nil)
                }
            }
        }
    }

    // MARK: Helpers

    /// Where the attached disk images are mounted (`hdiutil info`).
    nonisolated static func imageMountPoints() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return [] }
        var points: Set<String> = []
        for image in images {
            for entity in (image["system-entities"] as? [[String: Any]]) ?? [] {
                if let mount = entity["mount-point"] as? String { points.insert(mount) }
            }
        }
        return points
    }

    nonisolated static func detachImage(at mountPoint: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let text = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw FileOpError.system(text.isEmpty ? "hdiutil could not detach \(mountPoint)." : text)
        }
    }

    /// Runs a tool off the main thread; `done` gets its exit status and output (stdout, or stderr).
    nonisolated static func run(_ tool: String, _ args: [String], done: @escaping @MainActor (Int32, String) -> Void) {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = args
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            var status: Int32 = -1
            var text = ""
            do {
                try process.run()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                status = process.terminationStatus
                text = String(decoding: status == 0 ? data : errData, as: UTF8.self)
                if status != 0 && text.isEmpty { text = String(decoding: data, as: UTF8.self) }
            } catch {
                text = error.localizedDescription
            }
            let result = (status, text)
            await MainActor.run { done(result.0, result.1) }
        }
    }
}

/// A drive's Properties: the used and free ring (Explorer's pie), in the accent (red when nearly
/// full) over the free share, with the 24-segment bar and a legend beside it.
final class DriveChartView: NSView {
    let volume: VolumeCapacity

    init(volume: VolumeCapacity) {
        self.volume = volume
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("\(volume.percentText) used, \(volume.freeText)")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        let tone = volume.isNearlyFull ? p.miss : p.accent
        let center = NSPoint(x: 50, y: 50), radius: CGFloat = 38
        let ring = NSBezierPath()
        ring.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        ring.lineWidth = 14
        p.line2.ns.setStroke()
        ring.stroke()
        let used = NSBezierPath()
        // From the top, clockwise (the view is flipped, so angles run clockwise).
        used.appendArc(withCenter: center, radius: radius, startAngle: -90, endAngle: -90 + 360 * CGFloat(volume.usedFraction), clockwise: false)
        used.lineWidth = 14
        tone.ns.setStroke()
        used.stroke()
        drawLine(volume.percentText, font: Typeface.mono(13, weight: 600), color: tone, x: center.x - textWidth(volume.percentText, font: Typeface.mono(13, weight: 600)) / 2, midY: center.y)
        let x: CGFloat = 112
        fillRounded(NSRect(x: x, y: 18, width: 10, height: 10), radius: 2, tone)
        drawLine("Used  " + ByteText.storage(volume.used), font: Typeface.mono(12), color: p.text, x: x + 18, midY: 23)
        fillRounded(NSRect(x: x, y: 40, width: 10, height: 10), radius: 2, p.line2)
        drawLine("Free  " + ByteText.storage(volume.free), font: Typeface.mono(12), color: p.text, x: x + 18, midY: 45)
        let barW = bounds.width - x - 8
        let segW = (barW - 23 * 2) / 24
        for i in 0..<24 {
            let seg = NSRect(x: x + CGFloat(i) * (segW + 2), y: 66, width: segW, height: 10)
            fillRounded(seg, radius: 1, i < volume.litSegments() ? tone : p.line2)
        }
        drawLine(volume.totalText, font: Typeface.mono(11), color: p.muted, x: x, midY: 90)
    }
}
