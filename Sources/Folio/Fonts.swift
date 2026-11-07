import AppKit
import CoreText
import FolioCore

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

    private static var look: LookTheme { ThemeController.shared.look }

    /// Geist (D4); SF Pro in Native.
    static func ui(_ size: CGFloat, weight: CGFloat = 400) -> NSFont {
        if look.usesSystemFont { return NSFont.systemFont(ofSize: size, weight: system(weight)) }
        return font("Geist", size, weight)
            ?? NSFont.systemFont(ofSize: size, weight: weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular)
    }

    /// Geist Mono (its digits are tabular, as D4's `.num` asks); in Native, SF Pro with tabular digits.
    static func mono(_ size: CGFloat, weight: CGFloat = 400) -> NSFont {
        if look.usesSystemFont { return NSFont.monospacedDigitSystemFont(ofSize: size, weight: system(weight)) }
        return font("Geist Mono", size, weight)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular)
    }

    /// Menus Folio builds: Geist Mono 13 in D4, the system menu font in Native.
    static func menu() -> NSFont { look.usesSystemFont ? NSFont.menuFont(ofSize: 0) : mono(13) }

    /// `.os-label`'s tracking (.12em) and the column heads' (.08em), in points for a size; 0 in Native.
    static func labelKern(_ size: CGFloat) -> CGFloat { CGFloat(look.labelKern(Double(size))) }
    static func headKern(_ size: CGFloat) -> CGFloat { CGFloat(look.headKern(Double(size))) }

    /// A label's words: uppercase in D4, as written in Native.
    static func caption(_ text: String) -> String { look.caption(text) }

    private static func system(_ weight: CGFloat) -> NSFont.Weight {
        switch SystemWeight(css: Double(weight)) {
        case .regular: .regular
        case .semibold: .semibold
        case .bold: .bold
        }
    }

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
