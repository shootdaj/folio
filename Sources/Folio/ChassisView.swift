import AppKit
import FolioCore

/// D1's window grid: title 44, tabs 36, toolbar 56, HUD 30, body, status 32. The body is the sidebar
/// (248 pt unless resized from its right edge, hidden from View > Navigation pane), the list pane
/// (8 pt margin top, left and bottom) or Home in its place, and the 34 pt tick strip.
final class ChassisView: NSView {
    static let titleH: CGFloat = 44, tabH: CGFloat = 36, toolH: CGFloat = 56, hudH: CGFloat = 30, statusH: CGFloat = 32
    static let sideW: CGFloat = 248, railW: CGFloat = 34, paneMargin: CGFloat = 8
    static let sideMin: CGFloat = 180, sideMax: CGFloat = 480
    /// Space between the list's vertical scroller and the tick strip, so neither sits on the other.
    static let railGutter: CGFloat = 14

    let titleBar: TitleBarView
    let tabStrip = TabStripView(frame: .zero)
    let toolbar: ToolbarView
    let hud = HudView(frame: .zero)
    let sidebar = SidebarView(frame: .zero)
    let pane = ListPaneView(frame: .zero)
    let home = HomePaneView(frame: .zero)
    let rail = TickStripView(frame: .zero)
    /// Option+P's Preview pane or Option+Shift+P's Details pane, right of the list.
    let sidePane = SidePaneView(frame: .zero)
    let status = StatusBarView(frame: .zero)
    /// The Search options row above the results while a search is shown.
    let searchOptions = SearchOptionsBar(frame: .zero)
    private let handle = SidebarHandle(frame: .zero)
    var showsSearchOptions = false {
        didSet {
            guard showsSearchOptions != oldValue else { return }
            searchOptions.isHidden = !showsSearchOptions
            needsLayout = true
        }
    }

    /// The navigation pane's width, dragged at its right edge and kept in the defaults.
    var sideWidth: CGFloat = ChassisView.sideW { didSet { if sideWidth != oldValue { needsLayout = true } } }
    var sidebarShown = true { didSet { if sidebarShown != oldValue { needsLayout = true } } }
    var sidePaneKind: ListOptions.SidePane = .none {
        didSet {
            guard sidePaneKind != oldValue else { return }
            sidePane.kind = sidePaneKind
            needsLayout = true
        }
    }
    /// Home instead of the file list (the tick strip goes with the list).
    var showsHome = false {
        didSet {
            guard showsHome != oldValue else { return }
            pane.isHidden = showsHome
            rail.isHidden = showsHome
            home.isHidden = !showsHome
            needsLayout = true
        }
    }
    /// The sidebar edge was dragged to a new width (saved and the columns refitted by the window).
    var onSidebarResized: ((CGFloat) -> Void)?

    init(titleBar: TitleBarView, toolbar: ToolbarView) {
        self.titleBar = titleBar
        self.toolbar = toolbar
        super.init(frame: .zero)
        home.isHidden = true
        sidePane.isHidden = true
        searchOptions.isHidden = true
        // The sidebar's scroll view comes first and the list's second (the VM scripts find them so).
        for view in [sidebar, pane, home, rail, hud, toolbar, status, tabStrip, titleBar, handle, sidePane, searchOptions] as [NSView] { addSubview(view) }
        handle.onDrag = { [weak self] x in
            guard let self else { return }
            self.sideWidth = min(Self.sideMax, max(Self.sideMin, x))
            self.onSidebarResized?(self.sideWidth)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Width the list's columns can fill for a window of this width.
    static func listWidth(windowWidth: CGFloat) -> CGFloat {
        windowWidth - sideW - paneMargin - railGutter - railW - 2
    }

    static var bodyTop: CGFloat { titleH + tabH + toolH + hudH }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleBar.frame = NSRect(x: 0, y: 0, width: w, height: Self.titleH)
        tabStrip.frame = NSRect(x: 0, y: Self.titleH, width: w, height: Self.tabH)
        toolbar.frame = NSRect(x: 0, y: Self.titleH + Self.tabH, width: w, height: Self.toolH)
        hud.frame = NSRect(x: 0, y: Self.titleH + Self.tabH + Self.toolH, width: w, height: Self.hudH)
        let top = Self.bodyTop
        let bodyH = max(0, h - top - Self.statusH)
        let side = sidebarShown ? sideWidth : 0
        sidebar.isHidden = !sidebarShown
        handle.isHidden = !sidebarShown
        sidebar.frame = NSRect(x: 0, y: top, width: side, height: bodyH)
        handle.frame = NSRect(x: side - 3, y: top, width: 6, height: bodyH)
        rail.frame = NSRect(x: w - Self.railW, y: top, width: Self.railW, height: bodyH)
        // The right-hand pane sits between the list and the tick strip, never narrower than the list allows.
        let showsSide = sidePaneKind != .none && !showsHome
        let sideW = showsSide ? min(SidePaneView.width, max(0, (w - side) / 2 - 40)) : 0
        sidePane.isHidden = !showsSide
        let paneW = max(0, w - side - Self.paneMargin - Self.railGutter - Self.railW - (showsSide ? sideW + Self.paneMargin : 0))
        // D1's `.opts` row sits over the results: 8 pt in, 50 pt high, the pane 8 pt below it.
        let optsH = searchOptions.preferredHeight(width: paneW)
        let opts = showsSearchOptions && !showsHome ? optsH + Self.paneMargin : 0
        searchOptions.frame = NSRect(x: side + Self.paneMargin, y: top + Self.paneMargin, width: paneW, height: optsH)
        pane.frame = NSRect(x: side + Self.paneMargin, y: top + Self.paneMargin + opts, width: paneW,
                            height: max(0, bodyH - 2 * Self.paneMargin - opts))
        sidePane.frame = NSRect(x: pane.frame.maxX + Self.paneMargin, y: top + Self.paneMargin, width: sideW,
                                height: max(0, bodyH - 2 * Self.paneMargin))
        home.frame = NSRect(x: side + Self.paneMargin, y: top + Self.paneMargin,
                            width: max(0, w - side - 2 * Self.paneMargin), height: max(0, bodyH - 2 * Self.paneMargin))
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

/// The navigation pane's right edge: drag it to resize the pane.
final class SidebarHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    override func mouseDown(with event: NSEvent) {
        guard let window, let host = superview else { return }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            onDrag?(host.convert(next.locationInWindow, from: nil).x)
        }
    }
}
