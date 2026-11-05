import AppKit
import FolioCore

/// D1's window grid: title 44, toolbar 56, HUD 30, body, status 32. The body is the 248 pt sidebar,
/// the list pane (8 pt margin top, left and bottom) and the 34 pt tick strip.
final class ChassisView: NSView {
    static let titleH: CGFloat = 44, toolH: CGFloat = 56, hudH: CGFloat = 30, statusH: CGFloat = 32
    static let sideW: CGFloat = 248, railW: CGFloat = 34, paneMargin: CGFloat = 8
    /// Space between the list's vertical scroller and the tick strip, so neither sits on the other.
    static let railGutter: CGFloat = 14

    let titleBar: TitleBarView
    let toolbar: ToolbarView
    let hud = HudView(frame: .zero)
    let sidebar = SidebarView(frame: .zero)
    let pane = ListPaneView(frame: .zero)
    let rail = TickStripView(frame: .zero)
    let status = StatusBarView(frame: .zero)

    init(titleBar: TitleBarView, toolbar: ToolbarView) {
        self.titleBar = titleBar
        self.toolbar = toolbar
        super.init(frame: .zero)
        for view in [sidebar, pane, rail, hud, toolbar, status, titleBar] as [NSView] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Width the list's columns can fill for a window of this width.
    static func listWidth(windowWidth: CGFloat) -> CGFloat {
        windowWidth - sideW - paneMargin - railGutter - railW - 2
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleBar.frame = NSRect(x: 0, y: 0, width: w, height: Self.titleH)
        toolbar.frame = NSRect(x: 0, y: Self.titleH, width: w, height: Self.toolH)
        hud.frame = NSRect(x: 0, y: Self.titleH + Self.toolH, width: w, height: Self.hudH)
        let top = Self.titleH + Self.toolH + Self.hudH
        let bodyH = max(0, h - top - Self.statusH)
        sidebar.frame = NSRect(x: 0, y: top, width: Self.sideW, height: bodyH)
        rail.frame = NSRect(x: w - Self.railW, y: top, width: Self.railW, height: bodyH)
        pane.frame = NSRect(x: Self.sideW + Self.paneMargin, y: top + Self.paneMargin,
                            width: max(0, w - Self.sideW - Self.paneMargin - Self.railGutter - Self.railW),
                            height: max(0, bodyH - 2 * Self.paneMargin))
        status.frame = NSRect(x: 0, y: h - Self.statusH, width: w, height: Self.statusH)
    }

    override func draw(_ dirtyRect: NSRect) {
        fillRect(bounds, Palette.current.bg)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        ThemeController.shared.systemAppearanceMayHaveChanged()
    }
}
