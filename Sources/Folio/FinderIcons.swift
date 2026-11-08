import AppKit
import FolioCore
import UniformTypeIdentifiers

/// Native draws files with the icons Finder shows, from `NSWorkspace`.
/// Folders share one icon and files share one icon per extension.
@MainActor
final class FinderIconCache {
    static let shared = FinderIconCache()
    /// Posted when an app or custom icon has loaded, so views redraw.
    static let didUpgrade = Notification.Name("FolioFinderIconDidUpgrade")

    private var byType: [String: NSImage] = [:]
    private var byPath: [String: NSImage] = [:]
    private var pending: Set<String> = []
    /// One didUpgrade for every icon that lands in the same turn of the run loop, not one per icon.
    private var upgradePosted = false

    /// The type icon for a folder or a file name. It is quick and never reads the disk.
    func icon(name: String, isDir: Bool) -> NSImage {
        let ext = isDir ? "" : (name as NSString).pathExtension.lowercased()
        let key = isDir ? "/folder" : ext
        if let hit = byType[key] { return hit }
        let type = isDir ? UTType.folder : (UTType(filenameExtension: ext) ?? .data)
        let image = NSWorkspace.shared.icon(for: type)
        byType[key] = image
        return image
    }

    /// The icon for an item on disk. Apps and packages show their type icon first,
    /// then the real icon replaces it when it has loaded off the main thread. `modified` is the item's
    /// date from the listing (it keys the cache, so a changed app shows its new icon); the draw itself
    /// reads nothing from the disk.
    func icon(url: URL, isDir: Bool, modified: Date?) -> NSImage {
        guard Self.needsFile(url) else { return icon(name: url.lastPathComponent, isDir: isDir) }
        let key = "\(url.path)|\(modified?.timeIntervalSince1970 ?? 0)"
        if let hit = byPath[key] { return hit }
        if pending.insert(key).inserted {
            let path = url.path
            DispatchQueue.global(qos: .utility).async {
                let image = NSWorkspace.shared.icon(forFile: path)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let cache = FinderIconCache.shared
                        cache.byPath[key] = image
                        cache.pending.remove(key)
                        cache.postUpgradeOnce()
                    }
                }
            }
        }
        return icon(name: url.lastPathComponent, isDir: isDir)
    }

    private func postUpgradeOnce() {
        guard !upgradePosted else { return }
        upgradePosted = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                FinderIconCache.shared.upgradePosted = false
                NotificationCenter.default.post(name: FinderIconCache.didUpgrade, object: nil)
            }
        }
    }

    private static func needsFile(_ url: URL) -> Bool {
        ["app", "pkg", "framework", "bundle", "prefpane"].contains(url.pathExtension.lowercased())
    }
}

enum FinderIcon {
    /// Draws the Finder icon for a name into `rect`. `isLink` adds the alias arrow.
    @MainActor
    static func draw(name: String, isDir: Bool, isLink: Bool, in rect: NSRect) {
        draw(FinderIconCache.shared.icon(name: name, isDir: isDir), isLink: isLink, in: rect)
    }

    /// Draws the Finder icon for an item on disk.
    @MainActor
    static func draw(url: URL, isDir: Bool, modified: Date?, isLink: Bool, in rect: NSRect) {
        draw(FinderIconCache.shared.icon(url: url, isDir: isDir, modified: modified), isLink: isLink, in: rect)
    }

    @MainActor
    private static func draw(_ image: NSImage, isLink: Bool, in rect: NSRect) {
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
        if isLink {
            let b = max(6, rect.width * 0.4)
            ItemIcon.drawLinkBadge(in: NSRect(x: rect.minX, y: rect.maxY - b, width: b, height: b), palette: ThemeController.shared.colors)
        }
    }
}
