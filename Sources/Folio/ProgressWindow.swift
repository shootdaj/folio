import AppKit
import FolioCore

/// The one progress window for every copy and move (Explorer's consolidated dialog), drawn as D1's
/// copy window (`.cw`, step 4): s2 panel, line-2 border, 14 pt accent corner brackets. Jobs stack in
/// it, each a `JobPanelView`. Title "Progress", so scripts and VoiceOver can find it.
@MainActor
final class ProgressWindowController {
    private var window: ProgressPanel?
    private let content = ProgressContentView()
    private var panels: [JobPanelView] = []
    private var lastTick = ProcessInfo.processInfo.systemUptime
    /// Hide was pressed: the window stays away until a job needs an answer or the chip is clicked.
    private var hiddenByUser = false

    static let width: CGFloat = 680

    func add(_ job: FileJob) {
        let panel = JobPanelView(job: job)
        panel.onHide = { [weak self] in self?.hide() }
        panel.onClose = { OperationCenter.shared.dismiss(job) }
        panel.onHeightChange = { [weak self] in self?.relayout() }
        panels.append(panel)
        content.addSubview(panel)
        hiddenByUser = false
        relayout()
    }

    func remove(_ job: FileJob) {
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

    private func relayout() {
        var y: CGFloat = 0
        for panel in panels {
            let h = panel.preferredHeight
            panel.frame = NSRect(x: 0, y: y, width: Self.width, height: h)
            y += h
        }
        let height = max(1, y)
        content.panelCount = panels.count
        guard let window else { return }
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
    override var canBecomeKey: Bool { true }
}

/// The window's frame: s2 with a line-2 border, radius 4, and D1's corner brackets on top.
final class ProgressContentView: NSView {
    var panelCount = 0
    private let overlay = Overlay()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        addSubview(overlay)
        setAccessibilityRole(.group)
        setAccessibilityLabel("File operations")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        overlay.frame = bounds
        addSubview(overlay, positioned: .above, relativeTo: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        fillRect(bounds, Palette.current.s2)
    }

    private final class Overlay: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            let p = Palette.current
            strokeRounded(bounds, radius: 4, p.line2)
            drawBrackets(bounds, color: p.accent.ns, length: 14, width: 2)
        }
    }
}

/// One job, D1 step 4: header (light, "Copying N items", Hide), the ring, From and To, Speed, Time left
/// and Items, the speed graph and bar, Pause and Cancel; under it the conflict card (existing and
/// incoming with dates and sizes, Replace, Skip, Keep both, Compare) or a problem card.
final class JobPanelView: NSView {
    let job: FileJob
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
    private let hideButton = D1Button("Hide", glyph: .minus, style: .ghost)
    private let pauseButton = D1Button("Pause", glyph: .pause)
    private let cancelButton = D1Button("Cancel", glyph: .close)
    private let replaceButton = D1Button("Replace", glyph: .replace, style: .primary)
    private let skipButton = D1Button("Skip", glyph: .skip)
    private let keepButton = D1Button("Keep both", glyph: .both)
    private let compareButton = D1Button("Compare", glyph: .compare)
    private let applyAllCheck = D1Check("Do this for the next conflicts")
    private let identicalCheck = D1Check("Skip files with the same date and size")
    private let retryButton = D1Button("Try again", glyph: .refresh, style: .primary)
    private let skipProblemButton = D1Button("Skip", glyph: .skip)
    private let stopButton = D1Button("Cancel", glyph: .close)
    private let fromLink = LinkArea()
    private let toLink = LinkArea()

    static let bodyH: CGFloat = 440

    init(job: FileJob) {
        self.job = job
        super.init(frame: NSRect(x: 0, y: 0, width: ProgressWindowController.width, height: Self.bodyH))
        for v in [headLight, cardLight] as [NSView] { addSubview(v) }
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
        toLink.onPress = { [weak self] in self?.open(self?.job.destination) }
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
    private var cardH: CGFloat { compare ? 81 : 55 }

    var preferredHeight: CGFloat {
        if showsConflict { return Self.bodyH + 14 + 18 + 12 + cardH + 12 + 40 + 12 + 20 + 18 }
        if showsProblem { return Self.bodyH + 14 + 18 + 12 + 40 + 18 }
        if showsResolution { return Self.bodyH + 14 + 18 + 18 }
        return Self.bodyH
    }

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
        let w = bounds.width
        let hideW = hideButton.fit()
        hideButton.frame = NSRect(x: w - 8 - hideW, y: 8, width: hideW, height: 36)
        headLight.place(dotAt: NSPoint(x: 18, y: 26 - 4.5))
        cancelButton.frame = NSRect(x: w - 18 - cancelButton.fit(minimum: 112), y: 384, width: cancelButton.fit(minimum: 112), height: 40)
        pauseButton.frame = NSRect(x: cancelButton.frame.minX - 8 - 112, y: 384, width: 112, height: 40)
        let colX: CGFloat = 208, colW = w - 208 - 18
        let routeColW = (colW - 44) / 2
        let top = routeTop
        fromLink.frame = NSRect(x: colX, y: top, width: routeColW, height: 51)
        toLink.frame = NSRect(x: colX + routeColW + 44, y: top, width: routeColW, height: 51)

        let cy = Self.bodyH + 14
        cardLight.place(dotAt: NSPoint(x: 18, y: cy + 9 - 3.5))
        var x: CGFloat = 18
        let by = cy + 18 + 12 + cardH + 12
        for b in [replaceButton, skipButton, keepButton, compareButton] {
            let bw = b.fit()
            b.frame = NSRect(x: x, y: by, width: bw, height: 40)
            x += bw + 8
        }
        applyAllCheck.frame = NSRect(x: 18, y: by + 52, width: applyAllCheck.fit(), height: 20)
        let ix = applyAllCheck.isHidden ? 18 : applyAllCheck.frame.maxX + 24
        identicalCheck.frame = NSRect(x: ix, y: by + 52, width: identicalCheck.fit(), height: 20)
        x = 18
        let py = cy + 18 + 12
        for b in [retryButton, skipProblemButton, stopButton] {
            let bw = b.fit(minimum: 112)
            b.frame = NSRect(x: x, y: py, width: bw, height: 40)
            x += bw + 8
        }
    }

    private var routeTop: CGFloat { 70 + ((168 - 113) / 2).rounded(.down) }

    // MARK: Drawing

    private func title(_ s: JobSnapshot) -> String {
        let copy = s.kind == .copy
        let n = ByteText.grouped(s.itemsTotal) + (s.itemsTotal == 1 ? " item" : " items")
        switch s.state {
        case .preparing, .running: return (copy ? "Copying " : "Moving ") + n
        case .paused: return copy ? "Copy paused" : "Move paused"
        case .waitingOnConflict:
            return s.conflictsLeft == 1 ? "Waiting on 1 conflict" : "Waiting on \(s.conflictsLeft) conflicts"
        case .waitingOnProblem: return "Waiting on you"
        case .done:
            let done = ByteText.grouped(s.itemsDone) + (s.itemsDone == 1 ? " item" : " items")
            return (copy ? "Copied " : "Moved ") + done + (s.skipped > 0 ? ", skipped \(s.skipped)" : "")
        case .cancelled: return copy ? "Copy cancelled" : "Move cancelled"
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let s = snap else { return }
        let p = Palette.current
        let w = bounds.width
        fillRect(NSRect(x: 0, y: 0, width: w, height: Self.bodyH), p.s2)
        // Header.
        fillRect(NSRect(x: 0, y: 0, width: w, height: 52), p.s1)
        fillRect(NSRect(x: 0, y: 51, width: w, height: 1), p.line)
        drawLine(title(s), font: Typeface.ui(16, weight: 750, width: 124), color: p.txt, x: 39, midY: 26,
                 maxWidth: hideButton.frame.minX - 12 - 39)
        drawRing(s, p)
        drawRoute(s, p)
        drawReads(s, p)
        drawGraph(s, p)
        // Left of Pause and Cancel: the file in flight and what is left.
        var now = ""
        if let name = s.currentName, !s.state.isFinished { now = name + ", " }
        let itemsLeft = max(0, s.itemsTotal - s.itemsDone)
        now += ByteText.grouped(itemsLeft) + (itemsLeft == 1 ? " item" : " items") + " left"
        if s.skipped > 0 { now += ", \(s.skipped) skipped" }
        drawLine(now, font: Typeface.mono(12), color: p.txt3, x: 18, midY: 404, maxWidth: pauseButton.frame.minX - 18 - 12)
        if showsConflict, let c = s.conflict { drawConflict(c, p) }
        if showsProblem, let problem = s.problem { drawProblem(problem, p) }
        if showsResolution, let resolution { drawResolution(resolution, p) }
    }

    private var stateTone: (Palette) -> RGBA {
        switch snap?.state {
        case .cancelled: { $0.miss }
        case .paused, .waitingOnConflict, .waitingOnProblem: { $0.part }
        default: { $0.accent }
        }
    }

    /// D1's ring: 60 ticks at r 75, the track at r 62, the progress arc with a head dot, cut into 40
    /// segments by s2 dashes, and the percentage in the middle.
    private func drawRing(_ s: JobSnapshot, _ p: Palette) {
        let k: CGFloat = 168 / 160
        let c = NSPoint(x: 18 + 84, y: 70 + 84)
        let tone = stateTone(p)
        func circle(_ r: CGFloat, from a0: CGFloat = -.pi / 2, sweep: CGFloat = 2 * .pi) -> NSBezierPath {
            let path = NSBezierPath()
            let steps = max(2, Int(abs(sweep) / (2 * .pi) * 180))
            for i in 0...steps {
                let a = a0 + sweep * CGFloat(i) / CGFloat(steps)
                let pt = NSPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
            }
            return path
        }
        let ticks = circle(75 * k)
        ticks.lineWidth = 5 * k
        ticks.setLineDash([1.2 * k, 6.654 * k], count: 2, phase: 0)
        p.line3.ns.setStroke()
        ticks.stroke()
        let track = circle(62 * k)
        track.lineWidth = 10 * k
        p.line2.ns.setStroke()
        track.stroke()
        let d = CGFloat(shown)
        if d > 0 {
            let arc = circle(62 * k, sweep: 2 * .pi * d)
            arc.lineWidth = 10 * k
            tone.ns.setStroke()
            arc.stroke()
        }
        let cut = circle(62 * k)
        cut.lineWidth = 12 * k
        cut.setLineDash([1.6 * k, 8.139 * k], count: 2, phase: 0)
        p.s2.ns.setStroke()
        cut.stroke()
        let a = -CGFloat.pi / 2 + 2 * .pi * d
        let head = NSPoint(x: c.x + 62 * k * cos(a), y: c.y + 62 * k * sin(a))
        let r: CGFloat = 4.5 * k
        tone.ns.setFill()
        NSBezierPath(ovalIn: NSRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r)).fill()
        let pct = s.state == .done ? 100 : Int((shown * 100).rounded(.down))
        let pctFont = Typeface.ui(36, weight: 750, width: 125)
        let pw = textWidth("\(pct)%", font: pctFont)
        drawLine("\(pct)%", font: pctFont, color: p.txt, x: c.x - pw / 2, midY: c.y - 10)
        let sub = s.kind == .copy ? "copied" : "moved"
        let sw = textWidth(sub, font: Typeface.mono(12))
        drawLine(sub, font: Typeface.mono(12), color: p.txt2, x: c.x - sw / 2, midY: c.y + 20)
    }

    private func drawRoute(_ s: JobSnapshot, _ p: Palette) {
        let colX: CGFloat = 208, colW = bounds.width - 208 - 18
        let top = routeTop
        let cw = (colW - 44) / 2
        // Both spelled as the title bar spells paths (/tmp, not /private/tmp).
        let from = (s.sources.first?.deletingLastPathComponent() ?? s.destination).standardizedFileURL
        for (i, (key, url)) in [("From", from), ("To", s.destination.standardizedFileURL)].enumerated() {
            let x = colX + CGFloat(i) * (cw + 44)
            drawLine(key, font: Typeface.ui(12, weight: 650, width: 116), color: p.txt2, x: x, midY: top + 6)
            let name = url.path == "/" ? "/" : url.lastPathComponent
            drawLine(name, font: Typeface.ui(14, weight: 700), color: p.txt, x: x, midY: top + 24, maxWidth: cw)
            drawLine(url.path, font: Typeface.mono(12), color: p.txt3, x: x, midY: top + 43, maxWidth: cw)
        }
        Glyph.arrow.draw(in: NSRect(x: colX + cw + 12, y: top + 15, width: 20, height: 20), color: p.accent.ns)
        fillRect(NSRect(x: colX, y: top + 65, width: colW, height: 1), p.line)
    }

    private func drawReads(_ s: JobSnapshot, _ p: Palette) {
        let colX: CGFloat = 208, colW = bounds.width - 208 - 18
        let y = routeTop + 80
        let rw = (colW - 24) / 3
        let speed: String, left: String
        switch s.state {
        case .preparing: speed = "Counting"; left = "Counting"
        case .running:
            speed = ProgressText.speed(s.speed)
            left = s.secondsLeft.map(ProgressText.timeLeft) ?? "Working out"
        case .paused: speed = "0 MB/s"; left = "Paused"
        case .waitingOnConflict, .waitingOnProblem: speed = "Idle"; left = "Waiting on you"
        case .done: speed = "Done"; left = "Done"
        case .cancelled: speed = "Stopped"; left = "Stopped"
        }
        let items = ByteText.grouped(s.itemsDone) + " of " + ByteText.grouped(s.itemsTotal)
        for (i, (key, value)) in [("Speed", speed), ("Time left", left), ("Items", items)].enumerated() {
            let x = colX + CGFloat(i) * (rw + 12)
            fillRect(NSRect(x: x, y: y, width: 2, height: 33), p.line2)
            drawLine(key, font: Typeface.ui(12, weight: 650, width: 116), color: p.txt2, x: x + 10, midY: y + 6)
            drawLine(value, font: Typeface.mono(15, weight: 600), color: p.txt, x: x + 10, midY: y + 26, maxWidth: rw - 10)
        }
    }

    /// "Speed over the copy": the speed so far as an area and line against progress, a dashed line at
    /// the current speed, the head at the current point, and the bar under it.
    private func drawGraph(_ s: JobSnapshot, _ p: Palette) {
        let box = NSRect(x: 18, y: 254, width: bounds.width - 36, height: 116)
        fillRounded(box, radius: 3, p.s1)
        strokeRounded(box, radius: 3, p.line)
        drawLine(s.kind == .copy ? "Speed over the copy" : "Speed over the move", font: Typeface.ui(12, weight: 650, width: 116),
                 color: p.txt2, x: 30, midY: 270)
        let shownBytes = s.state == .done ? s.bytesTotal : Int64(Double(s.bytesTotal) * shown)
        drawLine(ProgressText.bytesOf(shownBytes, s.bytesTotal), font: Typeface.mono(12), color: p.txt,
                 x: bounds.width - 30, midY: 270, alignRight: true)
        let plot = NSRect(x: 30, y: 284, width: bounds.width - 60, height: 64)
        var gy = plot.minY
        while gy < plot.maxY { fillRect(NSRect(x: plot.minX, y: gy, width: plot.width, height: 1), p.line); gy += 16 }
        let tone = stateTone(p)
        let d = CGFloat(shown)
        let cur = s.state == .running ? s.speed : 0
        let mx = max(1, max(samples.map(\.v).max() ?? 0, cur)) * 1.18
        func y(_ v: Double) -> CGFloat { plot.maxY - CGFloat(v / mx) * plot.height }
        let pts = samples.filter { $0.f <= Double(d) + 1e-6 }
        if let last = pts.last {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: plot.minX + CGFloat(pts[0].f) * plot.width, y: y(pts[0].v)))
            for pt in pts.dropFirst() { line.line(to: NSPoint(x: plot.minX + CGFloat(pt.f) * plot.width, y: y(pt.v))) }
            line.line(to: NSPoint(x: plot.minX + d * plot.width, y: y(last.v)))
            let area = line.copy() as! NSBezierPath
            area.line(to: NSPoint(x: plot.minX + d * plot.width, y: plot.maxY))
            area.line(to: NSPoint(x: plot.minX + CGFloat(pts[0].f) * plot.width, y: plot.maxY))
            area.close()
            tone.withAlpha(0.18).ns.setFill()
            area.fill()
            line.lineWidth = 1.5
            tone.ns.setStroke()
            line.stroke()
            let hx = plot.minX + d * plot.width
            fillRect(NSRect(x: hx, y: plot.minY, width: 1, height: plot.height), tone)
            let hy = y(last.v)
            if p.glows, let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 9, color: tone.cg)
                fillRounded(NSRect(x: hx - 3.5, y: hy - 3.5, width: 7, height: 7), radius: 3.5, tone)
                ctx.restoreGState()
            } else {
                fillRounded(NSRect(x: hx - 3.5, y: hy - 3.5, width: 7, height: 7), radius: 3.5, tone)
            }
        }
        let now = NSBezierPath()
        now.move(to: NSPoint(x: plot.minX, y: y(cur)))
        now.line(to: NSPoint(x: plot.maxX, y: y(cur)))
        now.lineWidth = 1
        now.setLineDash([3, 4], count: 2, phase: 0)
        p.txt3.ns.setStroke()
        now.stroke()
        let bar = NSRect(x: 30, y: 356, width: bounds.width - 60, height: 4)
        fillRounded(bar, radius: 2, p.line2)
        fillRounded(NSRect(x: bar.minX, y: bar.minY, width: bar.width * d, height: 4), radius: 2, tone)
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

    /// D1's `.conf`: an amber-tinted strip, "name already exists in folder", two cards, the buttons.
    private func drawConflict(_ c: FileConflict, _ p: Palette) {
        let top = Self.bodyH
        let w = bounds.width
        fillRect(NSRect(x: 0, y: top, width: w, height: preferredHeight - top), p.s2)
        fillRect(NSRect(x: 0, y: top, width: w, height: preferredHeight - top), p.part.withAlpha(0.05))
        fillRect(NSRect(x: 0, y: top, width: w, height: 1), p.line)
        let hy = top + 14 + 9
        let nameFont = Typeface.mono(13, weight: 700)
        let nw = drawLine(c.incoming.name, font: nameFont, color: p.txt, x: 35, midY: hy, maxWidth: w / 2)
        let folder = c.destination.deletingLastPathComponent().lastPathComponent
        drawLine(" already exists in " + folder, font: Typeface.ui(14), color: p.txt, x: 35 + nw, midY: hy,
                 maxWidth: w - 35 - nw - 18)
        let cy = top + 14 + 18 + 12
        let cw = (w - 36 - 10) / 2
        let newer = c.incomingIsNewer
        let older = c.existing.modified.flatMap { e in c.incoming.modified.map { e.timeIntervalSince($0) > 1 } } ?? false
        let delta = c.sizeDelta
        let from = c.source.deletingLastPathComponent().lastPathComponent
        let sides: [(key: String, f: ItemFacts, tags: [String], accent: Bool, wins: Bool)] = [
            ("In \(folder) now", c.existing,
             [older ? "Newer" : newer ? "Older" : "Same date", delta < 0 ? "Larger" : delta > 0 ? "Smaller" : "Same size"],
             false, older || delta < 0),
            ("From \(from)", c.incoming,
             [newer ? "Newer" : older ? "Older" : "Same date",
              delta > 0 ? "Larger by " + ByteText.kilobytes(delta) : delta < 0 ? "Smaller" : "Same size"],
             true, newer || delta > 0),
        ]
        for (i, side) in sides.enumerated() {
            let r = NSRect(x: 18 + CGFloat(i) * (cw + 10), y: cy, width: cw, height: cardH)
            fillRounded(r, radius: 3, p.s1)
            strokeRounded(r, radius: 3, compare && side.wins ? p.accent : p.line2)
            let icon = NSRect(x: r.minX + 12, y: r.minY + 10 + 17 - 12, width: 24, height: 24)
            if side.f.isFolder {
                ItemIcon.drawFolder(in: icon.insetBy(dx: 0, dy: 2), palette: p, lit: false)
            } else {
                ItemIcon.drawFile(named: c.incoming.name, in: icon, palette: p)
            }
            let tx = r.minX + 12 + 24 + 12
            drawLine(side.key, font: Typeface.ui(12, weight: 650, width: 116), color: p.txt2, x: tx, midY: r.minY + 17,
                     maxWidth: r.maxX - 12 - tx)
            drawLine(facts(side.f), font: Typeface.mono(12), color: p.txt, x: tx, midY: r.minY + 36, maxWidth: r.maxX - 12 - tx)
            guard compare else { continue }
            var x = r.minX + 12
            for tag in side.tags {
                let tw = textWidth(tag, font: Typeface.mono(12, weight: 500)) + 16
                let tr = NSRect(x: x, y: r.minY + 48, width: tw, height: 22)
                fillRounded(tr, radius: 3, side.accent ? p.selectionFill : p.line)
                drawLine(tag, font: Typeface.mono(12, weight: 500), color: side.accent ? p.accent : p.txt2,
                         x: tr.minX + 8, midY: tr.midY)
                x += tw + 6
            }
        }
    }

    private func drawProblem(_ problem: JobProblem, _ p: Palette) {
        let top = Self.bodyH
        let w = bounds.width
        fillRect(NSRect(x: 0, y: top, width: w, height: preferredHeight - top), p.miss.withAlpha(0.05))
        fillRect(NSRect(x: 0, y: top, width: w, height: 1), p.line)
        let hy = top + 14 + 9
        let nw = drawLine(problem.url.lastPathComponent, font: Typeface.mono(13, weight: 700), color: p.txt, x: 35, midY: hy,
                          maxWidth: w / 2)
        drawLine(": " + problem.message, font: Typeface.ui(14), color: p.txt, x: 35 + nw, midY: hy, maxWidth: w - 35 - nw - 18)
    }

    /// D1's `.conf.res`: a green light and what was decided.
    private func drawResolution(_ text: String, _ p: Palette) {
        let top = Self.bodyH
        fillRect(NSRect(x: 0, y: top, width: bounds.width, height: 1), p.line)
        let hy = top + 14 + 9
        fillRounded(NSRect(x: 18, y: hy - 3.5, width: 7, height: 7), radius: 3.5, p.ok)
        drawLine(text, font: Typeface.ui(14), color: p.txt, x: 35, midY: hy, maxWidth: bounds.width - 53)
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
