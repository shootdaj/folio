import AppKit
import CoreText

/// Archivo (wdth and wght axes) and Chivo Mono ship in Contents/Resources/Fonts under the OFL,
/// each next to its OFL.txt, and are registered for this process only.
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

/// D1's type: `--font-ui` Archivo with its width axis (100 body, 116 column heads, 124 headings)
/// and `--font-mono` Chivo Mono for dates, sizes, counts and paths.
@MainActor
enum Typeface {
    private static var cache: [String: NSFont] = [:]
    private static let weightAxis = NSNumber(value: 0x7767_6874)  // 'wght'
    private static let widthAxis = NSNumber(value: 0x7764_7468)   // 'wdth'

    /// Archivo. The font's default weight is 600, so weight is always set explicitly.
    static func ui(_ size: CGFloat, weight: CGFloat = 400, width: CGFloat = 100) -> NSFont {
        font("Archivo", size, [weightAxis: weight, widthAxis: width])
            ?? NSFont.systemFont(ofSize: size, weight: weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular)
    }

    /// Chivo Mono.
    static func mono(_ size: CGFloat, weight: CGFloat = 400) -> NSFont {
        font("Chivo Mono", size, [weightAxis: weight])
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular)
    }

    private static func font(_ family: String, _ size: CGFloat, _ axes: [NSNumber: CGFloat]) -> NSFont? {
        let key = family + "|\(size)|" + axes.keys.sorted { $0.intValue < $1.intValue }
            .map { "\($0)=\(axes[$0]!)" }.joined(separator: ",")
        if let cached = cache[key] { return cached }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
            .addingAttributes([.variation: axes])
        guard let font = NSFont(descriptor: descriptor, size: size), font.familyName == family else { return nil }
        cache[key] = font
        return font
    }
}
