import AppKit
import FolioCore

/// D4's window grid: the 44 pt title bar with the tabs, the 52 pt frosted toolbar, the body and the
/// 28 pt status bar. The body is the sidebar of spotlight cards (248 pt unless resized from its right
/// edge, hidden from View > Navigation pane) and the list edge to edge beside it, or Home in its place.
final class ChassisView: NSView {
    static let toolH: CGFloat = 52
    /// Native has no title bar band and a thinner status bar. The tab row is 28 pt plus a 1 pt rule, shown from two tabs.
    private static var native: Bool { ThemeController.shared.look == .native }
    static var titleH: CGFloat { native ? 0 : 44 }
    static var statusH: CGFloat { native ? 22 : 28 }
    static let nativeTabH: CGFloat = 29
    static let sideW: CGFloat = 248
    static let sideMin: CGFloat = 180, sideMax: CGFloat = 480

    let titleBar: TitleBarView
    let tabStrip = TabStripView(frame: .zero)
    let toolbar: ToolbarView
    let sidebar = SidebarView(frame: .zero)
    let pane = ListPaneView(frame: .zero)
    let home = HomePaneView(frame: .zero)
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
    /// Folder Options > Show status bar.
    var statusShown = true {
        didSet {
            guard statusShown != oldValue else { return }
            status.isHidden = !statusShown
            needsLayout = true
        }
    }
    private var statusHeight: CGFloat { statusShown ? Self.statusH : 0 }
    /// Native only: the tab row has a height only while the window has two or more tabs.
    private var tabRowShown = false
    func setTabRowVisible(_ shown: Bool) {
        guard Self.native, shown != tabRowShown else { return }
        tabRowShown = shown
        tabStrip.isHidden = !shown
        needsLayout = true
    }
    var sidePaneKind: ListOptions.SidePane = .none {
        didSet {
            guard sidePaneKind != oldValue else { return }
            sidePane.kind = sidePaneKind
            needsLayout = true
        }
    }
    /// Home instead of the file list.
    var showsHome = false {
        didSet {
            guard showsHome != oldValue else { return }
            pane.isHidden = showsHome
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
        for view in [sidebar, pane, home, toolbar, status, titleBar, tabStrip, handle, sidePane, searchOptions] as [NSView] { addSubview(view) }
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
        windowWidth - sideW
    }

    static var bodyTop: CGFloat { titleH + toolH }

    /// Native: the body starts under the toolbar and, with two tabs or more, the tab row.
    private var top: CGFloat { Self.native ? Self.toolH + (tabRowShown ? Self.nativeTabH : 0) : Self.bodyTop }

    /// Native layout: the sidebar runs the full height above the status bar and the rest starts at its edge.
    private func layoutNative() {
        let w = bounds.width, h = bounds.height
        let side = sidebarShown ? sideWidth : 0
        let top = self.top
        let bodyH = max(0, h - top - statusHeight)
        titleBar.isHidden = true
        titleBar.frame = NSRect(x: 0, y: 0, width: w, height: 0)
        toolbar.frame = NSRect(x: side, y: 0, width: max(0, w - side), height: Self.toolH)
        // With the navigation pane hidden the traffic lights and their glass sit over the toolbar's left
        // end: clear them.
        toolbar.leadingInset = sidebarShown ? 0 : 98
        tabStrip.isHidden = !tabRowShown
        tabStrip.frame = NSRect(x: side, y: Self.toolH, width: max(0, w - side), height: tabRowShown ? Self.nativeTabH : 0)
        sidebar.isHidden = !sidebarShown
        handle.isHidden = !sidebarShown
        sidebar.frame = NSRect(x: 0, y: 0, width: side, height: max(0, h - statusHeight))
        handle.frame = NSRect(x: side - 3, y: 0, width: 6, height: max(0, h - statusHeight))
        let showsSide = sidePaneKind != .none && !showsHome
        let sideW = showsSide ? min(SidePaneView.width, max(0, (w - side) / 2 - 40)) : 0
        sidePane.isHidden = !showsSide
        let mainW = max(0, w - side - sideW)
        let optsH = showsSearchOptions && !showsHome ? searchOptions.preferredHeight(width: mainW) : 0
        searchOptions.frame = NSRect(x: side, y: top, width: mainW, height: optsH)
        pane.frame = NSRect(x: side, y: top + optsH, width: mainW, height: max(0, bodyH - optsH))
        sidePane.frame = NSRect(x: side + mainW, y: top, width: sideW, height: bodyH)
        home.frame = NSRect(x: side, y: top, width: max(0, w - side), height: bodyH)
        status.frame = NSRect(x: side, y: h - Self.statusH, width: max(0, w - side), height: Self.statusH)
        (window as? BrowserWindow)?.placeTrafficLights()
    }

    override func layout() {
        super.layout()
        if Self.native { layoutNative(); return }
        let w = bounds.width, h = bounds.height
        titleBar.frame = NSRect(x: 0, y: 0, width: w, height: Self.titleH)
        titleBar.layoutSubtreeIfNeeded()
        tabStrip.frame = titleBar.tabsFrame
        toolbar.frame = NSRect(x: 0, y: Self.titleH, width: w, height: Self.toolH)
        let top = Self.bodyTop
        let bodyH = max(0, h - top - statusHeight)
        let side = sidebarShown ? sideWidth : 0
        sidebar.isHidden = !sidebarShown
        handle.isHidden = !sidebarShown
        sidebar.frame = NSRect(x: 0, y: top, width: side, height: bodyH)
        handle.frame = NSRect(x: side - 3, y: top, width: 6, height: bodyH)
        // The right-hand pane takes its width from the list, never more than half of what is left.
        let showsSide = sidePaneKind != .none && !showsHome
        let sideW = showsSide ? min(SidePaneView.width, max(0, (w - side) / 2 - 40)) : 0
        sidePane.isHidden = !showsSide
        let mainW = max(0, w - side - sideW)
        // D4's `.opts` row heads the results, the list right under it.
        let optsH = showsSearchOptions && !showsHome ? searchOptions.preferredHeight(width: mainW) : 0
        searchOptions.frame = NSRect(x: side, y: top, width: mainW, height: optsH)
        pane.frame = NSRect(x: side, y: top + optsH, width: mainW, height: max(0, bodyH - optsH))
        sidePane.frame = NSRect(x: side + mainW, y: top, width: sideW, height: bodyH)
        home.frame = NSRect(x: side, y: top, width: max(0, w - side), height: bodyH)
        status.frame = NSRect(x: 0, y: h - Self.statusH, width: w, height: Self.statusH)
    }

    override func draw(_ dirtyRect: NSRect) {
        if Self.native {
            // The sidebar draws its own material, the rest is the window's content color.
            // Under the sidebar, below it, the window color shows beside the status bar.
            let side = sidebarShown ? sideWidth : 0
            NSColor.windowBackgroundColor.setFill()
            NSRect(x: 0, y: 0, width: side, height: bounds.height).fill()
            NSColor.controlBackgroundColor.setFill()
            NSRect(x: side, y: 0, width: bounds.width - side, height: bounds.height).fill()
            return
        }
        fillRect(bounds, ThemeColors.current.pane)
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
        while let next = MouseTracking.next(window, [.leftMouseDragged, .leftMouseUp], idle: nil) {
            if next.type == .leftMouseUp { break }
            onDrag?(host.convert(next.locationInWindow, from: nil).x)
        }
    }
}
