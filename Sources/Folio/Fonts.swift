import AppKit
import CoreText

/// Geist and Geist Mono (weight axis) ship in Contents/Resources/Fonts under the OFL, each next to its
/// OFL.txt, and are registered for this process only.
enum Fonts {
    @discardableResult
    static func registerBundled(in bundle: Bundle = .main) -> Int {
        guard let dir = bundle.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
              let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        else { return 0 }
        var registered = 0
        for case let url as URL in files where url.pathExtension.lowercased() == "ttf" {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                registered += 1
            } else {
                error?.release()
            }
        }
        return registered
    }
}

/// D4's type: `--font` Geist for the interface and `--mono` Geist Mono for dates, sizes, counts, paths
/// and the uppercase labels (`.os-label`: 600, 12, tracked .12em).
@MainActor
enum Typeface {
    private static var cache: [String: NSFont] = [:]
    private static let weightAxis = NSNumber(value: 0x7767_6874)  // 'wght'

    /// Geist.
    static func ui(_ size: CGFloat, weight: CGFloat = 400) -> NSFont {
        font("Geist", size, weight)
            ?? NSFont.systemFont(ofSize: size, weight: weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular)
    }

    /// Geist Mono (its digits are tabular, as D4's `.num` asks).
    static func mono(_ size: CGFloat, weight: CGFloat = 400) -> NSFont {
        font("Geist Mono", size, weight)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular)
    }

    /// `.os-label`'s tracking (.12em) and the column heads' (.08em), in points for a size.
    static func labelKern(_ size: CGFloat) -> CGFloat { size * 0.12 }
    static func headKern(_ size: CGFloat) -> CGFloat { size * 0.08 }

    private static func font(_ family: String, _ size: CGFloat, _ weight: CGFloat) -> NSFont? {
        let key = family + "|\(size)|\(weight)"
        if let cached = cache[key] { return cached }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
            .addingAttributes([.variation: [weightAxis: weight]])
        guard let font = NSFont(descriptor: descriptor, size: size), font.familyName == family else { return nil }
        cache[key] = font
        return font
    }
}
