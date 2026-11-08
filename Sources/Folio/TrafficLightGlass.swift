import AppKit

/// Native: a capsule of glass behind the close, minimise and zoom buttons. It lives in the buttons' own
/// title bar view, under them, so it moves with them wherever macOS puts them. It takes no clicks: the
/// buttons keep their hover and their clicks.
final class TrafficLightGlass: NSView {
    static let height: CGFloat = 36
    /// Clear space left and right of the outer buttons.
    static let sidePad: CGFloat = 10

    private let effect: NSView

    override init(frame: NSRect) {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: .zero)
            glass.style = .regular
            glass.cornerRadius = Self.height / 2
            effect = glass
        } else {
            let blur = NSVisualEffectView(frame: .zero)
            blur.material = .hudWindow
            blur.blendingMode = .withinWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = Self.height / 2
            blur.layer?.cornerCurve = .continuous
            blur.layer?.masksToBounds = true
            effect = blur
        }
        super.init(frame: frame)
        effect.frame = bounds
        effect.autoresizingMask = [.width, .height]
        addSubview(effect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
