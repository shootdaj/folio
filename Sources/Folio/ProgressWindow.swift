import AppKit
import FolioCore

/// The one progress window for every copy and move (Explorer's consolidated dialog), drawn as D4's copy
/// tray: frosted cards (a conflict card above the copy card) on a clear window. Jobs stack in it, each a
/// `JobPanelView`. Title "Progress", so scripts and VoiceOver can find it.
@MainActor
final class ProgressWindowController {
    private var window: ProgressPanel?
    private var content = ProgressContentView()
    /// The look the window and the cards were built for.
    private var builtLook = ThemeController.shared.look
    private var panels: [JobPanelView] = []
    private var lastTick = ProcessInfo.processInfo.systemUptime
    /// Hide was pressed: the window stays away until a job needs an answer or the chip is clicked.
    private var hiddenByUser = false

    /// 680 pt for D4's tray, a plain 520 pt window in Native.
    static var width: CGFloat { ThemeController.shared.isNative ? 520 : 680 }

    init() {
        // The controller lives as long as the app, so the observer is never removed.
        NotificationCenter.default.addObserver(forName: ThemeController.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lookChanged() }
        }
    }

    private func makePanel(for job: any ProgressJob) -> JobPanelView {
        let panel = JobPanelView(job: job)
        panel.onHide = { [weak self] in self?.hide() }
        panel.onClose = { OperationCenter.shared.dismiss(job) }
        panel.onHeightChange = { [weak self] in self?.relayout() }
        return panel
    }

    /// A look switch: build the window and the cards again so the new look's setup runs. The jobs go on.
    private func rebuildForLook() {
        let old = window
        let wasVisible = old?.isVisible ?? false
        let topLeft = old.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) }
        old?.orderOut(nil)
        old?.contentView = nil
        for panel in panels { panel.removeFromSuperview() }
        window = nil
        builtLook = ThemeController.shared.look
        content = ProgressContentView()
        panels = panels.map { makePanel(for: $0.job) }
        for panel in panels { content.addSubview(panel) }
        guard wasVisible, !panels.isEmpty else { return }
        let w = makeWindow()
        relayout()
        if let topLeft { w.setFrameTopLeftPoint(topLeft) }
        relayout()
        w.orderFront(nil)
    }

    private func lookChanged() {
        if builtLook != ThemeController.shared.look { rebuildForLook() }
    }

    func add(_ job: any ProgressJob) {
        if builtLook != ThemeController.shared.look { rebuildForLook() }
        let panel = makePanel(for: job)
        panels.append(panel)
        content.addSubview(panel)
        hiddenByUser = false
        relayout()
    }

    func remove(_ job: any ProgressJob) {
        panels.removeAll { panel in
            guard panel.job === job else { return false }
            panel.removeFromSuperview()
            return true
        }
        relayout()
    }

    func closeIfEmpty() {
        guard panels.isEmpty else { return }
        window?.orderOut(nil)
    }

    func update(_ snapshots: [Int: JobSnapshot]) {
        let t = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, t - lastTick)
        lastTick = t
        var heightChanged = false
        for panel in panels {
            guard let snap = snapshots[panel.job.id] else { continue }
            if snap.conflict != nil || snap.problem != nil, hiddenByUser {
                hiddenByUser = false
                reveal(near: nil)
            }
            heightChanged = panel.update(snap, dt: dt) || heightChanged
        }
        if heightChanged { relayout() }
    }

    /// Shows the window (centred over `near` the first time) unless Hide was pressed.
    func reveal(near anchor: NSWindow?, force: Bool = false) {
        if force { hiddenByUser = false }
        guard !hiddenByUser, !panels.isEmpty else { return }
        let w = makeWindow()
        if !w.isVisible {
            relayout()
            if let anchor {
                let f = anchor.frame
                w.setFrameTopLeftPoint(NSPoint(x: f.midX - w.frame.width / 2, y: f.maxY - 120))
            } else {
                w.center()
            }
            relayout()
            w.orderFront(nil)
        }
    }

    func hide() {
        hiddenByUser = true
        window?.orderOut(nil)
    }

    private func makeWindow() -> ProgressPanel {
        if let window { return window }
        if ThemeController.shared.isNative { return makeNativeWindow() }
        let w = ProgressPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 440),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.title = "Progress"
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        w.becomesKeyOnlyIfNeeded = true
        w.isFloatingPanel = false
        w.level = .normal
        w.contentView = content
        window = w
        return w
    }

    /// Native: a titled window on the default background. Its close button hides it, like Hide.
    private func makeNativeWindow() -> ProgressPanel {
        let w = ProgressPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
                              styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        w.title = "Progress"
        w.backgroundColor = .windowBackgroundColor
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        w.becomesKeyOnlyIfNeeded = true
        w.isFloatingPanel = false
        w.level = .normal
        w.onClose = { [weak self] in self?.hide() }
        w.contentView = content
        window = w
        return w
    }

    private func relayout() {
        let native = ThemeController.shared.isNative
        var y: CGFloat = 0
        let gap: CGFloat = native ? 0 : 10
        for panel in panels {
            let h = panel.preferredHeight
            panel.frame = NSRect(x: 0, y: y, width: Self.width, height: h)
            y += h + gap
        }
        let height = max(1, y - gap)
        content.panelCount = panels.count
        guard let window else { return }
        if native {
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let frameH = min(window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: Self.width, height: height)).height,
                             visible.height)
            var top = min(window.frame.maxY, visible.maxY)
            if top - frameH < visible.minY { top = visible.minY + frameH }
            window.setFrame(NSRect(x: window.frame.minX, y: top - frameH, width: window.frame.width, height: frameH), display: true)
            content.needsDisplay = true
            return
        }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let h = min(height, visible.height)
        // The top stays put as the conflict card comes and goes, unless that would push the bottom off screen.
        var top = min(window.frame.maxY, visible.maxY)
        if top - h < visible.minY { top = visible.minY + h }
        window.setFrame(NSRect(x: window.frame.minX, y: top - h, width: Self.width, height: h), display: true)
        content.needsDisplay = true
        window.invalidateShadow()
    }
}

final class ProgressPanel: NSPanel {
    /// Native: the close button hides the window instead of closing it.
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func close() {
        if let onClose { onClose() } else { super.close() }
    }
}

/// The window's content: clear, the cards draw themselves.
final class ProgressContentView: NSView {
    var panelCount = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.group)
        setAccessibilityLabel("File operations")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {}
}

/// One job as D4's copy cards: on top, while one waits, the conflict card (`.cf`: an amber edge, "name is
/// already in folder", the two copies side by side, Replace, Skip, Keep both, Compare) or a problem card;
/// below, the copy card (`.cc`): badge, "Copying N items", the route, the state, Hide; From and To in a
/// well; the glowing bar; done of total and the percentage; Speed with its sparkline, Time left, Items;
/// the file in flight, Pause and Cancel.
final class JobPanelView: NSView {
    let job: any ProgressJob
    var onHide: (() -> Void)?
    var onClose: (() -> Void)?
    /// Compare opened or closed the tags: the window must grow or shrink with the panel.
    var onHeightChange: (() -> Void)?

    private(set) var snap: JobSnapshot?
    private var shown = 0.0
    private var samples: [(f: Double, v: Double)] = []
    private var lastSample = 0.0
    private var compare = false
    private var armedAt: Double?
    private var applyAll = false
    private var resolution: String?
    private var lastConflictID: Int?

    private let headLight = LedView(diameter: 9)
    private let cardLight = LedView(diameter: 7)
    private let hideButton = OSButton("Hide", glyph: .minus, style: .ghost)
    private let pauseButton = OSButton("Pause", glyph: .pause)
    private let cancelButton = OSButton("Cancel", glyph: .close)
    private let replaceButton = OSButton("Replace", style: .primary)
    private let skipButton = OSButton("Skip")
    private let keepButton = OSButton("Keep both")
    private let compareButton = OSButton("Compare", glyph: .compare)
    private let applyAllCheck = OSCheck("Do this for the next conflicts")
    private let identicalCheck = OSCheck("Skip files with the same date and size")
    private let retryButton = OSButton("Try again", glyph: .refresh, style: .primary)
    private let skipProblemButton = OSButton("Skip")
    private let stopButton = OSButton("Cancel", glyph: .close)
    private let fromLink = LinkArea()
    private let toLink = LinkArea()

    /// The copy card's height.
    static var bodyH: CGFloat { ThemeController.shared.isNative ? 232 : 320 }

    // Native: real subviews. D4 never adds them.
    fileprivate let kindIcon = NSImageView()
    fileprivate let titleLabel = nativeLabel(13, weight: .semibold)
    fileprivate let routeLabel = nativeLabel(11, secondary: true)
    fileprivate let fromKey = nativeLabel(11, secondary: true)
    fileprivate let toKey = nativeLabel(11, secondary: true)
    fileprivate let fromPath = nativeLabel(11, mode: .byTruncatingMiddle)
    fileprivate let toPath = nativeLabel(11, mode: .byTruncatingMiddle)
    fileprivate let bar = NSProgressIndicator()
    fileprivate let doneLabel = nativeLabel(11, secondary: true)
    fileprivate let percentLabel = nativeLabel(11, secondary: true, alignment: .right)
    fileprivate let statKeys = (0..<3).map { _ in nativeLabel(11, secondary: true) }
    fileprivate let statValues = (0..<3).map { _ in nativeLabel(13) }
    fileprivate let noteLabel = nativeLabel(11, secondary: true)
    fileprivate let topIcon = NSImageView()
    fileprivate let topTitle = nativeLabel(13, weight: .semibold)
    fileprivate let topSub = nativeLabel(11, secondary: true)
    fileprivate let topCount = nativeLabel(11, secondary: true, alignment: .right)
    fileprivate let sideKeys = (0..<2).map { _ in nativeLabel(11, secondary: true) }
    fileprivate let sideIcons = (0..<2).map { _ in NSImageView() }
    fileprivate let sideNames = (0..<2).map { _ in nativeLabel(13, weight: .semibold) }
    fileprivate let sideFacts = (0..<2).map { _ in nativeLabel(11, secondary: true) }
    fileprivate let sideTags = (0..<2).map { _ in nativeLabel(11, secondary: true) }
    /// Native: what each side of the conflict draws behind its labels.
    fileprivate var sideBorders: [NSColor] = [.separatorColor, .separatorColor]
    /// Native: the last footer button titles, to lay out again when one changes.
    fileprivate var nativeButtonTitles = ""

    init(job: any ProgressJob) {
        self.job = job
        super.init(frame: NSRect(x: 0, y: 0, width: ProgressWindowController.width, height: Self.bodyH))
        defer { if ThemeController.shared.isNative { setUpNative() } }
        for v in [headLight, cardLight] as [NSView] { addSubview(v); v.isHidden = true }
        cardLight.tone = { $0.part }
        cardLight.blinking = true
        for b in [hideButton, pauseButton, cancelButton, replaceButton, skipButton, keepButton, compareButton,
                  retryButton, skipProblemButton, stopButton] {
            addSubview(b)
        }
        for v in [applyAllCheck, identicalCheck, fromLink, toLink] as [NSView] { addSubview(v) }
        hideButton.onPress = { [weak self] in self?.onHide?() }
        pauseButton.onPress = { [weak self] in self?.togglePause() }
        cancelButton.onPress = { [weak self] in self?.cancelPressed() }
        replaceButton.onPress = { [weak self] in self?.decide(.replace) }
        skipButton.onPress = { [weak self] in self?.decide(.skip) }
        keepButton.onPress = { [weak self] in self?.decide(.keepBoth) }
        compareButton.onPress = { [weak self] in
            guard let self else { return }
            compare.toggle()
            compareButton.isOn = compare
            needsLayout = true
            needsDisplay = true
            onHeightChange?()
        }
        applyAllCheck.onToggle = { [weak self] on in self?.applyAll = on }
        identicalCheck.onToggle = { [weak self] on in self?.job.setSkipIdentical(on) }
        retryButton.onPress = { [weak self] in self?.job.answer(.retry) }
        skipProblemButton.onPress = { [weak self] in self?.job.answer(.skip) }
        stopButton.onPress = { [weak self] in self?.job.answer(.cancel) }
        fromLink.onPress = { [weak self] in self?.open(self?.job.sources.first?.deletingLastPathComponent()) }
        toLink.onPress = { [weak self] in
            guard let job = self?.job else { return }
            // A new archive opens in its folder; everything else is a folder already.
            self?.open(job.kind == .compress ? job.destination.deletingLastPathComponent() : job.destination)
        }
        // An element of its own, labelled with its title ("Copying 3 items", "Copy paused").
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Job")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    // MARK: State

    private var showsConflict: Bool { snap?.conflict != nil }
    private var showsProblem: Bool { snap?.problem != nil && snap?.conflict == nil }
    private var showsResolution: Bool { !showsConflict && !showsProblem && resolution != nil }
    /// A side of the conflict: label, file, facts; Compare adds its tags.
    private var cardH: CGFloat { compare ? 96 : 72 }

    /// The card above the copy card (conflict, problem or what was decided), 0 when there is none.
    private var topH: CGFloat {
        if ThemeController.shared.isNative { return nativeTopH }
        if showsConflict { return 66 + cardH + 12 + 44 + 10 + 20 + 14 }
        if showsProblem { return 66 + 44 + 14 }
        if showsResolution { return 14 + 30 + 14 }
        return 0
    }
    /// Where the copy card starts.
    private var bodyTop: CGFloat { topH > 0 ? topH + 10 : 0 }

    var preferredHeight: CGFloat { bodyTop + Self.bodyH }

    /// Takes a new snapshot; true when the panel's height changed.
    func update(_ s: JobSnapshot, dt: Double) -> Bool {
        let before = preferredHeight
        if let c = s.conflict, c.id != lastConflictID {
            lastConflictID = c.id
            resolution = nil
            applyAllCheck.isChecked = applyAll
        }
        snap = s
        let target = s.state == .done ? 1 : s.fraction
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        shown = reduce ? target : shown + (target - shown) * min(1, dt * 6.5)
        if abs(target - shown) < 0.0004 { shown = target }
        let t = ProcessInfo.processInfo.systemUptime
        if s.state == .running, s.speed > 0, t - lastSample > 0.09 {
            lastSample = t
            samples.append((s.fraction, s.speed))
        }
        if let armedAt, t - armedAt > 3 { self.armedAt = nil }
        applyState(s)
        if ThemeController.shared.isNative { refreshNative(s) }
        needsDisplay = true
        if preferredHeight != before { needsLayout = true; return true }
        return false
    }

    private func applyState(_ s: JobSnapshot) {
        let finished = s.state.isFinished
        switch s.state {
        case .running, .preparing:
            headLight.tone = { $0.accent }; headLight.blinking = false; headLight.pulsing = true
        case .paused, .waitingOnConflict, .waitingOnProblem:
            headLight.tone = { $0.part }; headLight.pulsing = false; headLight.blinking = true
        case .done:
            headLight.tone = { $0.ok }; headLight.pulsing = false; headLight.blinking = false
        case .cancelled:
            headLight.tone = { $0.miss }; headLight.pulsing = false; headLight.blinking = false
        }
        let waiting = s.state == .waitingOnConflict || s.state == .waitingOnProblem
        pauseButton.isHidden = finished
        pauseButton.isEnabled = !waiting
        pauseButton.setTitle(s.state == .paused ? "Resume" : "Pause", glyph: s.state == .paused ? .play : .pause, style: .plain)
        pauseButton.isOn = s.state == .paused
        if finished {
            cancelButton.setTitle("Close", glyph: .check, style: .primary)
        } else if armedAt != nil {
            cancelButton.setTitle("Confirm cancel", glyph: .close, style: .warn)
        } else {
            cancelButton.setTitle("Cancel", glyph: .close, style: .plain)
        }
        let left = max(0, s.conflictsLeft - 1)
        applyAllCheck.title = left == 1 ? "Do this for the next conflict" : "Do this for the next \(left) conflicts"
        applyAllCheck.setAccessibilityLabel(applyAllCheck.title)
        applyAllCheck.isHidden = !showsConflict || left == 0
        identicalCheck.isChecked = s.skipIdentical
        for b in [replaceButton, skipButton, keepButton, compareButton] { b.isHidden = !showsConflict }
        identicalCheck.isHidden = !showsConflict
        for b in [retryButton, skipProblemButton, stopButton] { b.isHidden = !showsProblem }
        retryButton.isEnabled = s.problem?.canRetry ?? false
        cardLight.isLit = showsConflict || showsProblem
        cardLight.tone = showsProblem ? { $0.miss } : { $0.part }
        cardLight.blinking = showsConflict
        setAccessibilityLabel(title(s))
    }

    // MARK: Actions

    private func togglePause() {
        guard let s = snap else { return }
        if s.state == .paused { job.resume() } else { job.pause() }
    }

    private func cancelPressed() {
        guard let s = snap else { return }
        if s.state.isFinished { onClose?(); return }
        if armedAt != nil {
            armedAt = nil
            job.cancel()
        } else {
            armedAt = ProcessInfo.processInfo.systemUptime
        }
        applyState(s)
    }

    private func decide(_ d: ConflictDecision) {
        guard let c = snap?.conflict else { return }
        let name = c.incoming.name
        let folder = c.destination.deletingLastPathComponent().lastPathComponent
        let many = applyAll && (snap?.conflictsLeft ?? 0) > 1
        resolution = switch d {
        case .replace: many ? "Replaced \(snap?.conflictsLeft ?? 0) files with the incoming copies" : "Replaced \(name) with the incoming copy"
        case .skip: many ? "Skipped \(snap?.conflictsLeft ?? 0) files, the copies in \(folder) stay" : "Skipped \(name), the copy in \(folder) stays"
        case .keepBoth: many ? "Kept both copies of \(snap?.conflictsLeft ?? 0) files" : "Kept both copies of \(name)"
        }
        job.resolve(d, applyToAll: applyAll)
        applyAll = false
        applyAllCheck.isChecked = false
    }

    private func open(_ folder: URL?) {
        guard let folder else { return }
        (NSApp.delegate as? AppDelegate)?.openWindow(at: folder)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        if ThemeController.shared.isNative { layoutNative(); return }
        let w = bounds.width
        let y0 = bodyTop
        let hideW = hideButton.fit()
        hideButton.frame = NSRect(x: w - 12 - hideW, y: y0 + 14, width: hideW, height: 40)
        let cancelW = cancelButton.fit(minimum: 104), pauseW = pauseButton.fit(minimum: 104)
        cancelButton.frame = NSRect(x: w - 18 - cancelW, y: y0 + 262, width: cancelW, height: 44)
        pauseButton.frame = NSRect(x: cancelButton.frame.minX - 8 - pauseW, y: y0 + 262, width: pauseW, height: 44)
        let valueX: CGFloat = 18 + 12 + 54
        fromLink.frame = NSRect(x: valueX, y: y0 + 66 + 8, width: w - 18 - 12 - valueX, height: 20)
        toLink.frame = NSRect(x: valueX, y: y0 + 66 + 32, width: w - 18 - 12 - valueX, height: 20)

        var x: CGFloat = 20
        let by = 66 + cardH + 12
        for b in [replaceButton, skipButton, keepButton] {
            let bw = b.fit()
            b.frame = NSRect(x: x, y: by, width: bw, height: 44)
            x += bw + 8
        }
        let cw = compareButton.fit()
        compareButton.frame = NSRect(x: w - 18 - cw, y: by, width: cw, height: 44)
        applyAllCheck.frame = NSRect(x: 20, y: by + 54, width: applyAllCheck.fit(), height: 20)
        let ix = applyAllCheck.isHidden ? 20 : applyAllCheck.frame.maxX + 24
        identicalCheck.frame = NSRect(x: ix, y: by + 54, width: identicalCheck.fit(), height: 20)
        x = 20
        for b in [retryButton, skipProblemButton, stopButton] {
            let bw = b.fit(minimum: 104)
            b.frame = NSRect(x: x, y: 66, width: bw, height: 44)
            x += bw + 8
        }
    }

    // MARK: Drawing

    private func title(_ s: JobSnapshot) -> String {
        let n = ByteText.grouped(s.itemsTotal) + (s.itemsTotal == 1 ? " item" : " items")
        switch s.state {
        case .preparing, .running: return JobWords.doing(s.kind) + " " + n
        case .paused: return JobWords.noun(s.kind) + " paused"
        case .waitingOnConflict:
            return s.conflictsLeft == 1 ? "Waiting on 1 conflict" : "Waiting on \(s.conflictsLeft) conflicts"
        case .waitingOnProblem: return "Waiting on you"
        case .done:
            let done = ByteText.grouped(s.itemsDone) + (s.itemsDone == 1 ? " item" : " items")
            return JobWords.done(s.kind) + " " + done + (s.skipped > 0 ? ", skipped \(s.skipped)" : "")
        case .cancelled: return JobWords.noun(s.kind) + " cancelled"
        }
    }

    /// `.cc-state`: COPYING in the accent, PAUSED amber, STOPPED coral, DONE green.
    private func stateLabel(_ s: JobSnapshot) -> (String, NSColor) {
        let p = ThemeColors.current
        switch s.state {
        case .preparing, .running: return (Typeface.caption(JobWords.doing(s.kind)), p.accent)
        case .paused: return ("PAUSED", p.part)
        case .waitingOnConflict, .waitingOnProblem: return ("WAITING", p.part)
        case .done: return ("DONE", p.ok)
        case .cancelled: return ("STOPPED", p.miss)
        }
    }

    /// A frosted card: --tray over the bg, a line-2 hairline, radius 16.
    private func card(_ r: NSRect, _ p: ThemeColors) {
        fillRounded(r, radius: 16, p.tray.over(p.bg))
        strokeRounded(r, radius: 16, p.line2)
    }

    private func label(_ text: String, x: CGFloat, midY: CGFloat, color: NSColor? = nil, alignRight: Bool = false, _ p: ThemeColors) {
        drawLine(Typeface.caption(text), font: Typeface.mono(12, weight: 600), color: color ?? p.muted, x: x, midY: midY,
                 alignRight: alignRight, kern: Typeface.labelKern(12))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let s = snap else { return }
        if ThemeController.shared.isNative { drawNative(); return }
        let p = ThemeColors.current
        if showsConflict, let c = s.conflict { drawConflict(c, p) }
        if showsProblem, let problem = s.problem { drawProblem(problem, p) }
        if showsResolution, let resolution { drawResolution(resolution, p) }
        drawCopyCard(s, p)
    }

    private var stateTone: (ThemeColors) -> NSColor {
        switch snap?.state {
        case .cancelled: { $0.miss }
        case .paused, .waitingOnConflict, .waitingOnProblem: { $0.muted }
        case .done: { $0.ok }
        default: { $0.accent }
        }
    }

    private func drawCopyCard(_ s: JobSnapshot, _ p: ThemeColors) {
        let w = bounds.width
        let y0 = bodyTop
        card(NSRect(x: 0, y: y0, width: w, height: Self.bodyH), p)
        // `.cc-h`: the badge, the title and route, the state, Hide.
        let badge = NSRect(x: 18, y: y0 + 16, width: 36, height: 36)
        withGlow(p.accent.withAlpha(0.25), blur: 18) { fillRounded(badge, radius: 8, p.accent.withAlpha(0.16)) }
        strokeRounded(badge, radius: 8, p.accent.withAlpha(0.40))
        let badgeGlyph: Glyph = s.kind == .move ? .arrow : .copy
        badgeGlyph.draw(in: NSRect(x: badge.midX - 9, y: badge.midY - 9, width: 18, height: 18), color: p.accent.ns)
        let (state, stateColor) = stateLabel(s)
        let stateW = textWidth(state, font: Typeface.mono(12, weight: 600), kern: Typeface.labelKern(12))
        let stateRight = hideButton.frame.minX - 12
        label(state, x: stateRight, midY: y0 + 34, color: stateColor, alignRight: true, p)
        let textX = badge.maxX + 12, room = stateRight - stateW - 16 - textX
        drawLine(title(s), font: Typeface.ui(15, weight: 700), color: p.text, x: textX, midY: y0 + 25, maxWidth: room)
        let from = (s.sources.first?.deletingLastPathComponent() ?? s.destination).standardizedFileURL
        let to = s.destination.standardizedFileURL
        func short(_ u: URL) -> String { u.path == "/" ? "/" : u.pathComponents.suffix(2).joined(separator: "/") }
        let small = Typeface.ui(12)
        let fw = drawLine(from.lastPathComponent, font: small, color: p.muted, x: textX, midY: y0 + 43, maxWidth: room / 2)
        Glyph.arrow.draw(in: NSRect(x: textX + fw + 6, y: y0 + 43 - 6.5, width: 13, height: 13), color: p.muted.ns)
        drawLine(short(to), font: small, color: p.muted, x: textX + fw + 25, midY: y0 + 43, maxWidth: room - fw - 25)
        // `.cc-paths`: From and To in a well.
        let well = NSRect(x: 18, y: y0 + 66, width: w - 36, height: 62)
        fillRounded(well, radius: 8, p.well.over(p.tray.over(p.bg)))
        strokeRounded(well, radius: 8, p.line)
        let valueX = well.minX + 12 + 54
        label("From", x: well.minX + 12, midY: well.minY + 18, p)
        drawLine(from.path, font: Typeface.mono(12), color: p.text2, x: valueX, midY: well.minY + 18, maxWidth: well.maxX - 12 - valueX)
        label("To", x: well.minX + 12, midY: well.minY + 42, p)
        drawLine(to.path, font: Typeface.mono(12), color: p.text2, x: valueX, midY: well.minY + 42, maxWidth: well.maxX - 12 - valueX)
        // `.cc-bar`: 8 pt, the fill fading in from the left and glowing, a bright head.
        let tone = stateTone(p)
        let d = CGFloat(shown)
        let bar = NSRect(x: 18, y: y0 + 146, width: w - 36, height: 8)
        fillRounded(bar, radius: 4, p.s3)
        if d > 0 {
            let fill = NSRect(x: bar.minX, y: bar.minY, width: max(8, bar.width * d), height: bar.height)
            withGlow(tone.withAlpha(0.55), blur: 14) {
                if let g = NSGradient(starting: tone.withAlpha(0.45).ns, ending: tone.ns) {
                    g.draw(in: NSBezierPath(roundedRect: fill, xRadius: 4, yRadius: 4), angle: 0)
                }
            }
            if s.state == .running || s.state == .preparing {
                let hx = fill.maxX, hy = bar.midY
                withGlow(tone.withAlpha(0.55), blur: 16) {
                    fillRounded(NSRect(x: hx - 5, y: hy - 5, width: 10, height: 10), radius: 5, tone.withAlpha(0.85))
                }
                fillRounded(NSRect(x: hx - 2, y: hy - 2, width: 4, height: 4), radius: 2, p.text)
            }
        }
        // `.cc-meta`: done of total; the percentage in the accent.
        let shownBytes = s.state == .done ? s.bytesTotal : Int64(Double(s.bytesTotal) * shown)
        drawLine(ProgressText.bytesOf(shownBytes, s.bytesTotal), font: Typeface.mono(12, weight: 500), color: p.text, x: 18, midY: y0 + 170)
        let pct = s.state == .done ? 100 : Int((shown * 100).rounded(.down))
        drawLine("\(pct)%", font: Typeface.mono(13, weight: 500), color: tone, x: w - 18, midY: y0 + 170, alignRight: true)
        drawStats(s, y: y0 + 184, p)
        // `.cc-f`: the waiting conflict, or the file in flight and what is left; Pause and Cancel.
        let noteY = y0 + 262 + 22, noteRoom = pauseButton.frame.minX - 18 - 12
        if showsConflict {
            withGlow(p.part, blur: 8) { fillRounded(NSRect(x: 18, y: noteY - 3.5, width: 7, height: 7), radius: 3.5, p.part) }
            let n = s.conflictsLeft
            drawLine(n == 1 ? "1 conflict is waiting for you" : "\(n) conflicts are waiting for you", font: small, color: p.muted,
                     x: 31, midY: noteY, maxWidth: noteRoom - 13)
        } else {
            var now = ""
            if let name = s.currentName, !s.state.isFinished { now = name + ", " }
            let itemsLeft = max(0, s.itemsTotal - s.itemsDone)
            now += ByteText.grouped(itemsLeft) + (itemsLeft == 1 ? " item" : " items") + " left"
            if s.skipped > 0 { now += ", \(s.skipped) skipped" }
            drawLine(now, font: small, color: p.muted, x: 18, midY: noteY, maxWidth: noteRoom)
        }
    }

    /// `.cc-stats`: Speed (with the sparkline), Time left and Items between two hairlines.
    private func drawStats(_ s: JobSnapshot, y: CGFloat, _ p: ThemeColors) {
        let w = bounds.width
        let x0: CGFloat = 18, total = w - 36, h: CGFloat = 66
        fillRect(NSRect(x: x0, y: y, width: total, height: 1), p.line)
        fillRect(NSRect(x: x0, y: y + h - 1, width: total, height: 1), p.line)
        let speed: String, left: String
        switch s.state {
        case .preparing: speed = "Counting"; left = "Counting"
        case .running:
            speed = ProgressText.speed(s.speed)
            left = s.secondsLeft.map(ProgressText.timeLeft) ?? "Working out"
        case .paused: speed = "Paused"; left = "Paused"
        case .waitingOnConflict, .waitingOnProblem: speed = "Idle"; left = "Waiting on you"
        case .done: speed = "Done"; left = "Done"
        case .cancelled: speed = "Stopped"; left = "Stopped"
        }
        let items = ByteText.grouped(s.itemsDone) + " of " + ByteText.grouped(s.itemsTotal)
        let unit = total / 3.4
        let widths = [unit * 1.7, unit, unit * 0.7]
        var x = x0
        for (i, (key, value)) in [("Speed", speed), ("Time left", left), ("Items", items)].enumerated() {
            let pad: CGFloat = i == 0 ? 0 : 14
            if i > 0 { fillRect(NSRect(x: x, y: y + 1, width: 1, height: h - 2), p.line) }
            label(key, x: x + pad, midY: y + 22, p)
            let valueFont = i == 1 ? Typeface.ui(14, weight: 600) : Typeface.mono(14, weight: 600)
            let valueW = drawLine(value, font: valueFont, color: p.text, x: x + pad, midY: y + 44, maxWidth: widths[i] - pad - 8)
            if i == 0 {
                let sx = x + max(96, valueW + 16)
                drawSparkline(NSRect(x: sx, y: y + 13, width: max(0, widths[0] - (sx - x) - 14), height: 40), s, p)
            }
            x += widths[i]
        }
    }

    /// `.spark`: the speed so far as a line with a fading area under it and a glowing dot at its end.
    private func drawSparkline(_ r: NSRect, _ s: JobSnapshot, _ p: ThemeColors) {
        let pts = Array(samples.suffix(56))
        guard pts.count > 1, r.width > 20 else { return }
        let tone = s.state == .running ? p.accent : p.muted
        let mx = max(1, pts.map(\.v).max() ?? 1) * 1.22
        func point(_ i: Int) -> NSPoint {
            NSPoint(x: r.minX + 3 + CGFloat(i) / CGFloat(pts.count - 1) * (r.width - 8),
                    y: r.maxY - 4 - CGFloat(min(1, pts[i].v / mx)) * (r.height - 10))
        }
        let line = NSBezierPath()
        line.move(to: point(0))
        for i in 1..<pts.count { line.line(to: point(i)) }
        let area = line.copy() as! NSBezierPath
        area.line(to: NSPoint(x: point(pts.count - 1).x, y: r.maxY))
        area.line(to: NSPoint(x: point(0).x, y: r.maxY))
        area.close()
        NSGradient(starting: tone.withAlpha(0.32).ns, ending: tone.withAlpha(0).ns)?.draw(in: area, angle: 90)
        line.lineWidth = 1.6
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        tone.ns.setStroke()
        line.stroke()
        let end = point(pts.count - 1)
        withGlow(tone, blur: 4) { fillRounded(NSRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6), radius: 3, tone) }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private func facts(_ f: ItemFacts) -> String {
        let date = f.modified.map(Self.dateFormatter.string(from:)) ?? ""
        if f.isFolder { return date + ", folder" }
        return date + ", " + ByteText.kilobytes(f.size ?? 0)
    }

    /// The card above the copy card, with a glowing 3 pt edge in `edge` along its left side.
    private func topCard(_ edge: NSColor, _ p: ThemeColors) -> NSRect {
        let r = NSRect(x: 0, y: 0, width: bounds.width, height: topH)
        card(r, p)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 16, yRadius: 16).addClip()
        drawEdgeBar(NSRect(x: 0, y: 0, width: 3, height: r.height), color: edge)
        NSGraphicsContext.restoreGraphicsState()
        return r
    }

    /// `.cf`: "README.md is already in Backup/Code", the two copies side by side (the newer one tagged),
    /// then Replace, Skip, Keep both and Compare.
    private func drawConflict(_ c: FileConflict, _ p: ThemeColors) {
        let r = topCard(p.part, p)
        let w = r.width
        let folder = c.destination.deletingLastPathComponent().lastPathComponent
        let from = c.source.deletingLastPathComponent().lastPathComponent
        withGlow(p.part.withAlpha(0.6), blur: 6) {
            Glyph.alert.draw(in: NSRect(x: 20, y: 15, width: 20, height: 20), color: p.part.ns)
        }
        let left = snap?.conflictsLeft ?? 1
        let count = left == 1 ? "1 conflict" : "\(left) conflicts"
        label(count, x: w - 18, midY: 22, color: p.part, alignRight: true, p)
        let countW = textWidth(Typeface.caption(count), font: Typeface.mono(12, weight: 600), kern: Typeface.labelKern(12))
        drawLine(c.incoming.name + " is already in " + folder, font: Typeface.ui(14, weight: 700), color: p.text, x: 52, midY: 23,
                 maxWidth: w - 52 - countW - 30)
        drawLine("The copy keeps going while you decide.", font: Typeface.ui(12), color: p.muted, x: 52, midY: 41)
        let newer = c.incomingIsNewer
        let older = c.existing.modified.flatMap { e in c.incoming.modified.map { e.timeIntervalSince($0) > 1 } } ?? false
        let delta = c.sizeDelta
        let sides: [(key: String, f: ItemFacts, tags: [String], incoming: Bool, wins: Bool)] = [
            ("In \(folder)", c.existing,
             [older ? "Newer" : newer ? "Older" : "Same date", delta < 0 ? "Larger" : delta > 0 ? "Smaller" : "Same size"],
             false, older || delta < 0),
            ("From \(from)", c.incoming,
             [newer ? "Newer" : older ? "Older" : "Same date",
              delta > 0 ? "Larger by " + ByteText.kilobytes(delta) : delta < 0 ? "Smaller" : "Same size"],
             true, newer || delta > 0),
        ]
        let cw = (w - 38 - 8) / 2
        for (i, side) in sides.enumerated() {
            let box = NSRect(x: 20 + CGFloat(i) * (cw + 8), y: 66, width: cw, height: cardH)
            fillRounded(box, radius: 8, p.well.over(p.tray.over(p.bg)))
            let border = side.incoming && newer ? p.ok.mixed(0.40, with: p.line) : (compare && side.wins ? p.accent : p.line)
            strokeRounded(box, radius: 8, border)
            label(side.key, x: box.minX + 12, midY: box.minY + 17, p)
            let icon = NSRect(x: box.minX + 12, y: box.minY + 30, width: 16, height: 16)
            ItemIcon.draw(name: c.incoming.name, isFolder: side.f.isFolder, in: icon, palette: p)
            drawLine(c.incoming.name, font: Typeface.ui(13, weight: 600), color: p.text, x: icon.maxX + 8, midY: icon.midY,
                     maxWidth: box.maxX - 12 - icon.maxX - 8)
            let fw = drawLine(facts(side.f), font: Typeface.mono(12), color: p.text2, x: box.minX + 12, midY: box.minY + 58,
                              maxWidth: box.width - 24 - (side.incoming && newer ? 70 : 0))
            if side.incoming && newer {
                // `.tag`: a green pill with its own light.
                let tw = textWidth("Newer", font: Typeface.ui(12, weight: 600)) + 16 + 12
                let tag = NSRect(x: box.minX + 12 + fw + 8, y: box.minY + 48, width: tw, height: 20)
                fillRounded(tag, radius: 10, p.ok.withAlpha(0.13))
                withGlow(p.ok, blur: 8) { fillRounded(NSRect(x: tag.minX + 8, y: tag.midY - 3, width: 6, height: 6), radius: 3, p.ok) }
                drawLine("Newer", font: Typeface.ui(12, weight: 600), color: p.ok, x: tag.minX + 20, midY: tag.midY)
            }
            guard compare else { continue }
            var x = box.minX + 12
            for tag in side.tags {
                let tw = textWidth(tag, font: Typeface.mono(12, weight: 500)) + 16
                let tr = NSRect(x: x, y: box.minY + 70, width: tw, height: 20)
                fillRounded(tr, radius: 10, side.wins ? p.accentSoft : p.line)
                drawLine(tag, font: Typeface.mono(12, weight: 500), color: side.wins ? p.text : p.text2, x: tr.minX + 8, midY: tr.midY)
                x += tw + 6
            }
        }
    }

    /// A problem: a coral edge, the item and the message, Try again, Skip, Cancel.
    private func drawProblem(_ problem: JobProblem, _ p: ThemeColors) {
        let r = topCard(p.miss, p)
        withGlow(p.miss.withAlpha(0.6), blur: 6) {
            Glyph.alert.draw(in: NSRect(x: 20, y: 15, width: 20, height: 20), color: p.miss.ns)
        }
        drawLine(problem.url.lastPathComponent, font: Typeface.ui(14, weight: 700), color: p.text, x: 52, midY: 23, maxWidth: r.width / 2)
        drawLine(problem.message, font: Typeface.ui(12), color: p.muted, x: 52, midY: 41, maxWidth: r.width - 70)
    }

    /// `.cf-done`: a green tick and what was decided.
    private func drawResolution(_ text: String, _ p: ThemeColors) {
        let r = topCard(p.ok, p)
        Glyph.check.draw(in: NSRect(x: 20, y: r.midY - 9, width: 18, height: 18), color: p.ok.ns)
        drawLine(text, font: Typeface.ui(13), color: p.text2, x: 48, midY: r.midY, maxWidth: r.width - 66)
    }
}

/// A system-font label for the Native cards.
@MainActor
private func nativeLabel(_ size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false,
                         mode: NSLineBreakMode = .byTruncatingTail, alignment: NSTextAlignment = .left) -> NSTextField {
    let l = NSTextField(labelWithString: "")
    l.font = NSFont.systemFont(ofSize: size, weight: weight)
    l.textColor = secondary ? .secondaryLabelColor : .labelColor
    l.lineBreakMode = mode
    l.alignment = alignment
    l.cell?.usesSingleLineMode = true
    return l
}

// MARK: Native

extension JobPanelView {
    /// Native card geometry, in points.
    private var nativeSideH: CGFloat { compare ? 92 : 70 }
    private var nativeRow: CGFloat { 28 }

    fileprivate var nativeTopH: CGFloat {
        if showsConflict { return 60 + nativeSideH + 12 + nativeRow + 8 + 18 + 16 }
        if showsProblem { return 60 + nativeRow + 16 }
        if showsResolution { return 48 }
        return 0
    }

    fileprivate func setUpNative() {
        let icons: [NSImageView] = [kindIcon, topIcon] + sideIcons
        for v in icons { v.imageScaling = .scaleProportionallyUpOrDown; addSubview(v) }
        kindIcon.contentTintColor = .controlAccentColor
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.style = .bar
        addSubview(bar)
        let labels: [NSTextField] = [titleLabel, routeLabel, fromKey, toKey, fromPath, toPath, doneLabel, percentLabel, noteLabel,
                                     topTitle, topSub, topCount] + statKeys + statValues + sideKeys + sideNames + sideFacts + sideTags
        for l in labels { addSubview(l) }
        fromKey.stringValue = "From"
        toKey.stringValue = "To"
        for (i, key) in ["Speed", "Time left", "Items"].enumerated() { statKeys[i].stringValue = key }
        // The links sit over the paths, above the labels.
        for v in [fromLink, toLink] as [NSView] { v.removeFromSuperview(); addSubview(v) }
        topIcon.isHidden = true
    }

    private func put(_ l: NSTextField, _ text: String) { if l.stringValue != text { l.stringValue = text } }

    fileprivate func refreshNative(_ s: JobSnapshot) {
        let conflict = showsConflict, problem = showsProblem, resolved = showsResolution
        // A new button title can change its width, so the row needs a new layout.
        let titles = cancelButton.title + "|" + pauseButton.title
        if titles != nativeButtonTitles { nativeButtonTitles = titles; needsLayout = true }
        // The LEDs are D4's. A lit one would show its dot at the corner.
        headLight.isHidden = true
        cardLight.isHidden = true
        let symbol = s.kind == .move ? "arrow.right.circle" : s.kind == .compress ? "doc.zipper" : s.kind == .extract ? "archivebox" : "doc.on.doc"
        if kindIcon.toolTip != symbol {
            kindIcon.toolTip = symbol
            kindIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 26, weight: .regular))
        }
        put(titleLabel, title(s))
        let from = (s.sources.first?.deletingLastPathComponent() ?? s.destination).standardizedFileURL
        let to = s.destination.standardizedFileURL
        let short = to.path == "/" ? "/" : to.pathComponents.suffix(2).joined(separator: "/")
        put(routeLabel, from.lastPathComponent + " \u{2192} " + short)
        put(fromPath, from.path)
        put(toPath, to.path)
        bar.doubleValue = shown
        let shownBytes = s.state == .done ? s.bytesTotal : Int64(Double(s.bytesTotal) * shown)
        put(doneLabel, ProgressText.bytesOf(shownBytes, s.bytesTotal))
        put(percentLabel, "\(s.state == .done ? 100 : Int((shown * 100).rounded(.down)))%")
        let speed: String, left: String
        switch s.state {
        case .preparing: speed = "Counting"; left = "Counting"
        case .running:
            speed = ProgressText.speed(s.speed)
            left = s.secondsLeft.map(ProgressText.timeLeft) ?? "Working out"
        case .paused: speed = "Paused"; left = "Paused"
        case .waitingOnConflict, .waitingOnProblem: speed = "Idle"; left = "Waiting on you"
        case .done: speed = "Done"; left = "Done"
        case .cancelled: speed = "Stopped"; left = "Stopped"
        }
        put(statValues[0], speed)
        put(statValues[1], left)
        put(statValues[2], ByteText.grouped(s.itemsDone) + " of " + ByteText.grouped(s.itemsTotal))
        if conflict {
            let n = s.conflictsLeft
            put(noteLabel, n == 1 ? "1 conflict is waiting for you" : "\(n) conflicts are waiting for you")
        } else {
            var now = ""
            if let name = s.currentName, !s.state.isFinished { now = name + ", " }
            let itemsLeft = max(0, s.itemsTotal - s.itemsDone)
            now += ByteText.grouped(itemsLeft) + (itemsLeft == 1 ? " item" : " items") + " left"
            if s.skipped > 0 { now += ", \(s.skipped) skipped" }
            put(noteLabel, now)
        }
        // The card above.
        let showTop = conflict || problem || resolved
        topIcon.isHidden = !showTop
        topTitle.isHidden = !showTop
        topSub.isHidden = !(conflict || problem)
        topCount.isHidden = !conflict
        let sideViews: [NSView] = sideKeys + sideIcons + sideNames + sideFacts
        for v in sideViews { v.isHidden = !conflict }
        for t in sideTags { t.isHidden = !(conflict && compare) }
        if conflict, let c = s.conflict {
            setTop(symbol: nil)
            let folder = c.destination.deletingLastPathComponent().lastPathComponent
            let from = c.source.deletingLastPathComponent().lastPathComponent
            put(topTitle, c.incoming.name + " is already in " + folder)
            put(topSub, "The copy keeps going while you decide.")
            put(topCount, s.conflictsLeft == 1 ? "1 conflict" : "\(s.conflictsLeft) conflicts")
            let newer = c.incomingIsNewer
            let older = c.existing.modified.flatMap { e in c.incoming.modified.map { e.timeIntervalSince($0) > 1 } } ?? false
            let delta = c.sizeDelta
            let keys = ["In \(folder)", "From \(from)"]
            let sides = [c.existing, c.incoming]
            let tags = [[older ? "Newer" : newer ? "Older" : "Same date", delta < 0 ? "Larger" : delta > 0 ? "Smaller" : "Same size"],
                        [newer ? "Newer" : older ? "Older" : "Same date",
                         delta > 0 ? "Larger by " + ByteText.kilobytes(delta) : delta < 0 ? "Smaller" : "Same size"]]
            let wins = [older || delta < 0, newer || delta > 0]
            for i in 0..<2 {
                put(sideKeys[i], keys[i])
                put(sideNames[i], c.incoming.name)
                var line = facts(sides[i])
                if i == 1 && newer { line += ", newer" }
                put(sideFacts[i], line)
                put(sideTags[i], tags[i].joined(separator: ", "))
                sideIcons[i].image = FinderIconCache.shared.icon(name: c.incoming.name, isDir: sides[i].isFolder)
                sideBorders[i] = i == 1 && newer ? NSColor.systemGreen.withAlphaComponent(0.6)
                    : (compare && wins[i] ? .controlAccentColor : .separatorColor)
            }
        } else if problem, let pr = s.problem {
            setTop(symbol: nil)
            put(topTitle, pr.url.lastPathComponent)
            put(topSub, pr.message)
        } else if resolved, let resolution {
            setTop(symbol: "checkmark.circle.fill")
            topIcon.contentTintColor = .systemGreen
            put(topTitle, resolution)
        }
    }

    /// The icon of the card above: the caution icon, or a symbol.
    private func setTop(symbol: String?) {
        let key = symbol ?? "caution"
        guard topIcon.toolTip != key else { return }
        topIcon.toolTip = key
        if let symbol {
            topIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .regular))
        } else {
            topIcon.image = NSImage(named: NSImage.cautionName)
            topIcon.contentTintColor = nil
        }
    }

    fileprivate func layoutNative() {
        let w = bounds.width, pad: CGFloat = 20
        let btnH = OSButton.height, rowPad = (nativeRow - btnH) / 2
        // The card above.
        if showsResolution {
            topIcon.frame = NSRect(x: pad, y: 12, width: 24, height: 24)
            topTitle.frame = NSRect(x: pad + 34, y: 15, width: w - pad * 2 - 34, height: 18)
        } else {
            topIcon.frame = NSRect(x: pad, y: 14, width: 32, height: 32)
            let countW: CGFloat = showsConflict ? 90 : 0
            topCount.frame = NSRect(x: w - pad - countW, y: 17, width: countW, height: 15)
            topTitle.frame = NSRect(x: 64, y: 14, width: w - 64 - pad - countW - 8, height: 18)
            topSub.frame = NSRect(x: 64, y: 33, width: w - 64 - pad, height: 15)
        }
        let cw = (w - pad * 2 - 8) / 2
        for i in 0..<2 {
            let x = pad + CGFloat(i) * (cw + 8)
            sideKeys[i].frame = NSRect(x: x + 12, y: 60 + 8, width: cw - 24, height: 14)
            sideIcons[i].frame = NSRect(x: x + 12, y: 60 + 26, width: 32, height: 32)
            sideNames[i].frame = NSRect(x: x + 52, y: 60 + 27, width: cw - 64, height: 17)
            sideFacts[i].frame = NSRect(x: x + 52, y: 60 + 44, width: cw - 64, height: 15)
            sideTags[i].frame = NSRect(x: x + 12, y: 60 + 66, width: cw - 24, height: 15)
        }
        var x = pad
        let by = 60 + nativeSideH + 12 + rowPad
        for b in [replaceButton, skipButton, keepButton] {
            let bw = b.fit()
            b.frame = NSRect(x: x, y: by, width: bw, height: btnH)
            x += bw + 8
        }
        let cmpW = compareButton.fit()
        compareButton.frame = NSRect(x: w - pad - cmpW, y: by, width: cmpW, height: btnH)
        let cy = 60 + nativeSideH + 12 + nativeRow + 8
        applyAllCheck.frame = NSRect(x: pad, y: cy, width: applyAllCheck.fit(), height: 18)
        let ix = applyAllCheck.isHidden ? pad : applyAllCheck.frame.maxX + 20
        identicalCheck.frame = NSRect(x: ix, y: cy, width: identicalCheck.fit(), height: 18)
        x = pad
        for b in [retryButton, skipProblemButton, stopButton] {
            let bw = b.fit(minimum: 80)
            b.frame = NSRect(x: x, y: 60 + rowPad, width: bw, height: btnH)
            x += bw + 8
        }
        // The copy card.
        let y0 = bodyTop
        let hideW = hideButton.fit()
        hideButton.frame = NSRect(x: w - pad - hideW, y: y0 + 16 + rowPad, width: hideW, height: btnH)
        kindIcon.frame = NSRect(x: pad, y: y0 + 16, width: 32, height: 32)
        titleLabel.frame = NSRect(x: 64, y: y0 + 16, width: hideButton.frame.minX - 64 - 8, height: 17)
        routeLabel.frame = NSRect(x: 64, y: y0 + 34, width: hideButton.frame.minX - 64 - 8, height: 15)
        let valueX: CGFloat = 52
        fromKey.frame = NSRect(x: pad, y: y0 + 64, width: 32, height: 15)
        toKey.frame = NSRect(x: pad, y: y0 + 83, width: 32, height: 15)
        fromPath.frame = NSRect(x: valueX, y: y0 + 64, width: w - valueX - pad, height: 15)
        toPath.frame = NSRect(x: valueX, y: y0 + 83, width: w - valueX - pad, height: 15)
        fromLink.frame = fromPath.frame
        toLink.frame = toPath.frame
        bar.frame = NSRect(x: pad, y: y0 + 108, width: w - pad * 2, height: 10)
        doneLabel.frame = NSRect(x: pad, y: y0 + 124, width: (w - pad * 2) * 0.7, height: 15)
        percentLabel.frame = NSRect(x: w - pad - 60, y: y0 + 124, width: 60, height: 15)
        let col = (w - pad * 2) / 3
        for i in 0..<3 {
            statKeys[i].frame = NSRect(x: pad + CGFloat(i) * col, y: y0 + 150, width: col - 8, height: 14)
            statValues[i].frame = NSRect(x: pad + CGFloat(i) * col, y: y0 + 165, width: col - 8, height: 17)
        }
        let fy = y0 + 192
        let cancelW = cancelButton.fit(minimum: 80), pauseW = pauseButton.fit(minimum: 80)
        cancelButton.frame = NSRect(x: w - pad - cancelW, y: fy + rowPad, width: cancelW, height: btnH)
        pauseButton.frame = NSRect(x: cancelButton.frame.minX - 8 - pauseW, y: fy + rowPad, width: pauseW, height: btnH)
        noteLabel.frame = NSRect(x: pad, y: fy + 6, width: pauseButton.frame.minX - pad - 12, height: 15)
    }

    /// Native draws only the hairline between the cards and the two sides' boxes. The rest is subviews.
    fileprivate func drawNative() {
        let w = bounds.width
        if topH > 0 {
            NSColor.separatorColor.setFill()
            NSRect(x: 0, y: topH + 4.5, width: w, height: 1).fill()
        }
        guard showsConflict else { return }
        let cw = (w - 40 - 8) / 2
        for i in 0..<2 {
            let box = NSRect(x: 20 + CGFloat(i) * (cw + 8), y: 60, width: cw, height: nativeSideH)
            let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            sideBorders[i].setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

/// An invisible button over the From and To names: opens that folder in a window.
final class LinkArea: NSButton {
    var onPress: (() -> Void)?

    init() {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        target = self
        action = #selector(pressed(_:))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func pressed(_ sender: Any?) { onPress?() }
    override func draw(_ dirtyRect: NSRect) {}
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
