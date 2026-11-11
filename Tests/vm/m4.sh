#!/bin/bash
# Milestone 4 GUI check: the item menu and Copy as path, Properties (General and Permissions), dragging a
# file onto a folder row, the background menu, a Control-drop's Move/Copy/Alias menu, a spring-loaded
# folder, pinning a folder by dropping it in Quick access, and Create alias. Then two checks of presses
# and drags that lose their end: a marquee whose release never reaches Folio (the press must end with the
# button, so the next click works at once), and no "unrecognized selector" from a drag's end in Folio's
# log, so Mission Control (Ctrl+Up) still opens after the drags.
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Makes /private/tmp/folio-tests/m4-<stamp>/work with a folder "target" and five text files,
# opens ~/folio/Folio.app on it and drives it with real events: System Events for keys and accessibility,
# and folio-mouse (CGEvent through the HID tap, compiled here with swiftc from the source below) for
# right-clicks and drags, so every drop goes through AppKit's real NSDraggingDestination path. A context
# menu is modal and hidden from System Events while open, so items are picked by typing their name
# (NSMenu type-select) and Return. PNGs go to ~/folio/shots/:
#   m4-1-context-menu.png        right-click alpha.txt: the icon row, Open with, Copy as path, Properties...
#                                then "Copy as path": pbpaste reads "<work>/alpha.txt" in quotes
#   m4-2-properties-general.png  Option+Return on alpha.txt: the Properties window, General tab
#   m4-3-properties-permissions.png  the Permissions tab (owner, group, the nine boxes, mode); Esc closes it
#   m4-3b-marquee-held.png       a marquee held from the empty space up over delta.txt to gamma.txt
#   m4-3c-after-lost-release.png the button let go with the release dropped before Folio (an event tap):
#                                the marquee is gone
#   m4-3d-after-press.png        one click on alpha.txt, then Down: beta.txt selected (the press had ended)
#   m4-4-drag-over-target.png    beta.txt dragged over the target row, mid-drag: row lit, "Move to target"
#   m4-5-dropped.png             after the drop: beta.txt moved into target (same volume moves)
#   m4-6-background-menu.png     right-click empty space: View, Sort by, Group by, Refresh, Paste, New...
#   m4-7-control-drop-menu.png   gamma.txt dropped on target with Control held: Move here, Copy here...
#   m4-7b-copied.png             "Copy here": gamma.txt in target and still in work
#   m4-8-spring-loaded.png       delta.txt held over target for 1.4 s: target opened under the drag
#   m4-8b-spring-dropped.png     dropped on target's background: delta.txt moved into target
#   m4-9-pinned.png              back in work, target dropped between Quick access's first two pins
#   m4-10-alias.png              right-click epsilon.txt, "Create alias": "epsilon.txt alias" appears
#   m4-12-mission-control.png    after every drag above, Ctrl+Up: Mission Control opens
# Prints one line per step and exits non-zero if any step fails.
set -u

APP="$HOME/folio/Folio.app"
SHOTS="$HOME/folio/shots"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT="/private/tmp/folio-tests/m4-$STAMP"
WORK="$ROOT/work"
MOUSE="$HOME/folio/folio-mouse"
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "m4: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if [ ! -d "$APP" ]; then
    echo "m4: missing $APP (stage the build first, docs/plan/VM.md)"
    exit 2
fi

pass() { echo "step $1 $2: ok - $3"; }
fail() { echo "step $1 $2: FAILED - $3"; fails=$((fails + 1)); }

# --- folio-mouse: built once per change of its source -------------------------------------------------
mkdir -p "$HOME/folio" "$ROOT"
cat > "$ROOT/folio-mouse.swift" <<'SWIFT'
// folio-mouse: real mouse and modifier events through the HID event tap, for the VM scripts
// (docs/plan/VM.md). Compiled inside the test VM with swiftc; never run on a host Mac (RULES.md, rule 0).
//
//   folio-mouse click <x> <y> [--right] [--option]
//   folio-mouse drag <x1> <y1> <x2> <y2> [--right] [--control] [--hold S]
//                    [--shot PATH --shot-at S] [--then X Y --then-hold S]
//   folio-mouse press <x1> <y1> <x2> <y2>   left press at 1, dragged to 2, and left held (no release)
//   folio-mouse release <x> <y> [--swallow-for <pid>]  the left button up at (x, y); with --swallow-for an
//                                           event tap on that process drops the release before it gets it,
//                                           while the rest of the system sees the button go up
//
// A drag presses at (x1, y1), moves in small steps to (x2, y2), stays there `--hold` seconds (nudging
// the pointer so the destination keeps getting updates), takes `--shot` with screencapture `--shot-at`
// seconds into the hold, optionally moves on to `--then` (after a spring-loaded folder opened) and
// lets go. `--control` holds the Control key for the last part of the drag and the drop.
import AppKit
import CoreGraphics
import Foundation

let source = CGEventSource(stateID: .hidSystemState)

func post(_ type: CGEventType, _ p: CGPoint, _ button: CGMouseButton, _ flags: CGEventFlags = []) {
    guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
    e.flags = flags
    e.setIntegerValueField(.mouseEventClickState, value: 1)
    e.post(tap: .cghidEventTap)
}

func controlKey(_ down: Bool) {
    guard let e = CGEvent(keyboardEventSource: source, virtualKey: 59, keyDown: down) else { return }
    e.flags = down ? .maskControl : []
    e.post(tap: .cghidEventTap)
}

func pause(_ s: Double) { usleep(useconds_t(s * 1_000_000)) }

/// Starts screencapture and carries on posting events (a capture takes a few tenths of a second).
var captures: [Process] = []
func shoot(_ path: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", path]
    try? p.run()
    captures.append(p)
}

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}
func value(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
func values(_ name: String, _ n: Int) -> [Double]? {
    guard let i = args.firstIndex(of: name), args.count > i + n else { return nil }
    let v = args[(i + 1)...(i + n)].compactMap(Double.init)
    args.removeSubrange(i...(i + n))
    return v.count == n ? v : nil
}

let right = flag("--right")
let option = flag("--option")
let control = flag("--control")
let hold = Double(value("--hold") ?? "0.5") ?? 0.5
let shotPath = value("--shot")
let shotAt = Double(value("--shot-at") ?? "0.3") ?? 0.3
let swallowFor = value("--swallow-for").flatMap { pid_t($0) }
let then = values("--then", 2)
let thenHold = Double(value("--then-hold") ?? "0.6") ?? 0.6
let mode = args.first ?? ""
let nums = args.dropFirst().compactMap(Double.init)
let button: CGMouseButton = right ? .right : .left
let downType: CGEventType = right ? .rightMouseDown : .leftMouseDown
let upType: CGEventType = right ? .rightMouseUp : .leftMouseUp
let dragType: CGEventType = right ? .rightMouseDragged : .leftMouseDragged

switch mode {
case "click" where nums.count == 2:
    let p = CGPoint(x: nums[0], y: nums[1])
    let flags: CGEventFlags = option ? .maskAlternate : []
    post(.mouseMoved, p, .left)
    pause(0.12)
    post(downType, p, button, flags)
    pause(0.06)
    post(upType, p, button, flags)
    print("click at \(Int(p.x)),\(Int(p.y))" + (right ? " with the right button" : ""))

case "drag" where nums.count == 4:
    let a = CGPoint(x: nums[0], y: nums[1]), b = CGPoint(x: nums[2], y: nums[3])
    post(.mouseMoved, a, .left)
    pause(0.15)
    post(downType, a, button)
    pause(0.25)
    // A few small steps first, so the press reads as a drag, then the rest of the way.
    for i in 1...6 {
        post(dragType, CGPoint(x: a.x + CGFloat(i) * 2, y: a.y + CGFloat(i)), button)
        pause(0.03)
    }
    let steps = 30
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        post(dragType, CGPoint(x: a.x + 12 + (b.x - a.x - 12) * t, y: a.y + 6 + (b.y - a.y - 6) * t), button)
        pause(0.02)
    }
    var flags: CGEventFlags = []
    var held = 0.0
    var shot = false
    while held < hold {
        if control && held >= hold - 0.35 && flags.isEmpty {
            controlKey(true)
            flags = .maskControl
        }
        let jitter = CGFloat(Int(held * 20) % 2)
        post(dragType, CGPoint(x: b.x + jitter, y: b.y), button, flags)
        if let shotPath, !shot, held >= shotAt {
            shoot(shotPath)
            shot = true
            print("shot \(shotPath) at \(String(format: "%.2f", held)) s into the hold")
        }
        pause(0.05)
        held += 0.05
    }
    var end = b
    if let then {
        end = CGPoint(x: then[0], y: then[1])
        for i in 1...20 {
            let t = CGFloat(i) / 20
            post(dragType, CGPoint(x: b.x + (end.x - b.x) * t, y: b.y + (end.y - b.y) * t), button, flags)
            pause(0.02)
        }
        var h = 0.0
        while h < thenHold {
            post(dragType, end, button, flags)
            pause(0.05)
            h += 0.05
        }
    }
    if control && flags.isEmpty {
        controlKey(true)
        flags = .maskControl
        post(dragType, end, button, flags)
        pause(0.3)
    }
    post(upType, end, button, flags)
    pause(0.15)
    if control { controlKey(false) }
    print("drag \(Int(a.x)),\(Int(a.y)) -> \(Int(end.x)),\(Int(end.y))" + (control ? " with Control" : "")
          + (right ? " with the right button" : ""))

case "press" where nums.count == 4:
    let a = CGPoint(x: nums[0], y: nums[1]), b = CGPoint(x: nums[2], y: nums[3])
    post(.mouseMoved, a, .left)
    pause(0.15)
    post(.leftMouseDown, a, .left)
    pause(0.25)
    for i in 1...30 {
        let t = CGFloat(i) / 30
        post(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), .left)
        pause(0.02)
    }
    pause(0.2)
    print("press \(Int(a.x)),\(Int(a.y)) -> \(Int(b.x)),\(Int(b.y)), button still down")

case "release" where nums.count == 2:
    let p = CGPoint(x: nums[0], y: nums[1])
    var tap: CFMachPort?
    if let pid = swallowFor {
        // What a press meets when Mission Control or a Space switch takes its release: the button is up
        // for the system, but no mouse-up event reaches the app. A tap on that one process drops it.
        tap = CGEvent.tapCreateForPid(pid: pid, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: CGEventMask(1 << CGEventType.leftMouseUp.rawValue),
                                      callback: { _, type, event, _ in type == .leftMouseUp ? nil : Unmanaged.passUnretained(event) },
                                      userInfo: nil)
        guard let tap else { print("release: no event tap on \(pid) (Accessibility?)"); exit(1) }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    post(.leftMouseUp, p, .left)
    // Stay a moment: a release posted just before exiting can be lost, leaving the button held.
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    print("released at \(Int(p.x)),\(Int(p.y))" + (swallowFor.map { ", the event dropped before process \($0)" } ?? "")
          + "; left button down now: \(NSEvent.pressedMouseButtons & 1 == 1)")

default:
    print("usage: folio-mouse click <x> <y> [--right] [--option] | drag <x1> <y1> <x2> <y2> [--right] [--control] "
          + "[--hold S] [--shot PATH --shot-at S] [--then X Y --then-hold S] | press <x1> <y1> <x2> <y2> | release <x> <y>")
    exit(2)
}
for p in captures { p.waitUntilExit() }
SWIFT
if ! cmp -s "$ROOT/folio-mouse.swift" "$HOME/folio/folio-mouse.swift" || [ ! -x "$MOUSE" ]; then
    cp "$ROOT/folio-mouse.swift" "$HOME/folio/folio-mouse.swift"
    swiftc -O "$HOME/folio/folio-mouse.swift" -o "$MOUSE" 2>&1 | tail -5
fi
if [ ! -x "$MOUSE" ]; then echo "m4: could not build folio-mouse"; exit 2; fi

frontmost() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>&1; }

keys() {
    echo "  key: $1 (frontmost: $(frontmost))"
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to $1" >/dev/null 2>&1
}

# menu_pick <word> [downs]: types a word into the open menu (type-select highlights the first item
# starting with it), presses Down `downs` times, then Return. No spaces: a space would act on the menu.
menu_pick() {
    echo "  menu: type \"$1\", Down x${2:-0}, Return"
    osascript -e "tell application \"System Events\" to keystroke \"$1\"" >/dev/null 2>&1
    sleep 0.4
    local i=0
    while [ "$i" -lt "${2:-0}" ]; do
        osascript -e 'tell application "System Events" to key code 125' >/dev/null 2>&1
        sleep 0.15
        i=$((i + 1))
    done
    osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
}

menu_close() { osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1; }

window_names() {
    osascript -e 'tell application "System Events" to tell process "Folio" to get name of every window' 2>/dev/null \
        | tr ',' '\n' | sed 's/^ *//;s/ *$//'
}
has_window() { window_names | grep -Fxq "$1"; }
names_now() { window_names | paste -sd '|' -; }

wait_window() {
    local i=0 n=$(( ${2:-10} * 4 ))
    while [ "$i" -lt "$n" ]; do
        has_window "$1" && return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}

wait_no_window() {
    local i=0 n=$(( ${2:-10} * 4 ))
    while [ "$i" -lt "$n" ]; do
        has_window "$1" || return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}

wait_file() {
    local i=0 n=$(( ${2:-10} * 4 ))
    while [ "$i" -lt "$n" ]; do
        [ -e "$1" ] && return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}

shot() {
    local f="$SHOTS/$1.png"
    rm -f "$f"
    screencapture -x "$f" 2>/dev/null
    if [ -s "$f" ]; then echo "$f"; fi
}

rows() {
    osascript - "$1" 2>/dev/null <<'OSA'
on run argv
    set out to {}
    tell application "System Events" to tell process "Folio"
        set t to table 1 of scroll area 2 of window (item 1 of argv)
        repeat with r in rows of t
            set end of out to (description of UI element 1 of r) as text
        end repeat
    end tell
    set AppleScript's text item delimiters to linefeed
    return out as text
end run
OSA
}
row_names() { rows "$1" | paste -sd '|' -; }

# selected_rows <window>: the names on the file list's selected rows, joined with |.
selected_rows() {
    osascript - "$1" 2>/dev/null <<'OSA'
on run argv
    set out to {}
    tell application "System Events" to tell process "Folio"
        set t to table 1 of scroll area 2 of window (item 1 of argv)
        repeat with r in rows of t
            if selected of r then set end of out to (description of UI element 1 of r) as text
        end repeat
    end tell
    set AppleScript's text item delimiters to "|"
    return out as text
end run
OSA
}

# Mission Control is open while the Dock shows its "Mission Control" group.
mission_control_open() { osascript -e 'tell application "System Events" to tell process "Dock" to exists group "Mission Control"' 2>/dev/null; }
wait_mission_control() {
    local i=0 n=$(( ${2:-3} * 4 ))
    while [ "$i" -lt "$n" ]; do
        [ "$(mission_control_open)" = "$1" ] && return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}
has_row() { rows "$1" | grep -Fxq "$2"; }

wait_rows() {
    local w="$1" secs="$2"
    shift 2
    local i=0 n=$((secs * 4)) missing
    while [ "$i" -lt "$n" ]; do
        missing=0
        for name in "$@"; do has_row "$w" "$name" || missing=1; done
        [ "$missing" -eq 0 ] && return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}

# row_point <window> <name>: "x y" on the row's name, in screen points.
row_point() {
    osascript - "$1" "$2" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        set t to table 1 of scroll area 2 of window (item 1 of argv)
        repeat with r in rows of t
            set c to UI element 1 of r
            if ((description of c) as text) is (item 2 of argv) then
                set {px, py} to position of c
                set {sx, sy} to size of c
                return ((px + 70) as text) & " " & ((py + (sy div 2)) as text)
            end if
        end repeat
    end tell
    return ""
end run
OSA
}

# list_blank <window>: "x y" in the list's empty space, well below the rows.
list_blank() {
    osascript - "$1" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        set s to scroll area 2 of window (item 1 of argv)
        set {px, py} to position of s
        set {sx, sy} to size of s
        return ((px + (sx div 2)) as text) & " " & ((py + sy - 90) as text)
    end tell
end run
OSA
}

# quick_access_gap <window> <k>: "x y" on the line between Quick access pins k-1 and k. The navigation
# pane is scrolled to the top first (milestone 5's tree scrolls it to the current folder), and Home is
# the row above the first pin.
quick_access_gap() {
    osascript - "$1" "$2" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        set s to scroll area 1 of window (item 1 of argv)
        try
            set value of scroll bar 1 of s to 0
        end try
        delay 0.4
        set {px, py} to position of s
        set k to (item 2 of argv) as integer
        return ((px + 130) as text) & " " & ((py + 12 + 1 + 36 + 30 + 30 * k) as text)
    end tell
end run
OSA
}

# ax value|press|exists <AXRole> <description> <window>: the first match, searched five levels deep.
ax() {
    osascript - "$@" 2>&1 <<'OSA'
on find(e, wantRole, wantDesc, depth)
    tell application "System Events"
        try
            if (role of e is wantRole) and ((description of e) as text is wantDesc) then return e
        end try
        if depth is 0 then return missing value
        try
            repeat with k in (UI elements of e)
                set hit to my find(contents of k, wantRole, wantDesc, depth - 1)
                if hit is not missing value then return hit
            end repeat
        end try
    end tell
    return missing value
end find

on run argv
    set act to item 1 of argv
    set wantRole to item 2 of argv
    set wantDesc to item 3 of argv
    set winName to item 4 of argv
    tell application "System Events" to tell process "Folio"
        if not (exists window winName) then return "no window " & winName
        set found to my find(window winName, wantRole, wantDesc, 5)
        if found is missing value then return "missing"
        if act is "exists" then return "yes"
        if act is "value" then return (value of found) as text
        try
            perform action "AXPress" of found
            return "pressed"
        on error
            set {px, py} to position of found
            set {sx, sy} to size of found
            click at {px + (sx div 2), py + (sy div 2)}
            return "clicked"
        end try
    end tell
end run
OSA
}

# Paths read the same with or without /private in front.
plain_path() { echo "$1" | sed 's#^"/private/#"/#; s#^/private/#/#'; }

# --- setup -----------------------------------------------------------------------------------------
mkdir -p "$SHOTS" "$WORK/target"
for f in alpha beta gamma delta epsilon; do echo "$f" > "$WORK/$f.txt"; done
echo "setup: $WORK with target and alpha, beta, gamma, delta, epsilon .txt"

osascript -e 'quit app "Folio"' >/dev/null 2>&1
sleep 1
pkill -x Folio 2>/dev/null
defaults delete com.anshul.folio addressHistory >/dev/null 2>&1
defaults delete com.anshul.folio itemCheckBoxes >/dev/null 2>&1
defaults delete com.anshul.folio quickAccessPins >/dev/null 2>&1
# Folio follows the Mac's light or dark setting (it has no theme of its own): the shots are in dark.
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1
echo -n "" | pbcopy

# Folio's log from here on is read in step 11.
LOG_START="$(date '+%Y-%m-%d %H:%M:%S')"
open -a "$APP" "$WORK"
if wait_window "work" 15 && wait_rows "work" 10 "epsilon.txt"; then
    echo "launch: ok - window \"work\", rows: $(row_names work)"
else
    echo "launch: FAILED - no window \"work\" with rows after 15 s (windows: $(names_now))"
    exit 1
fi
osascript -e 'tell application "System Events" to set frontmost of process "Folio" to true' >/dev/null 2>&1
sleep 1

# --- 1: right-click a file: the item menu; Copy as path ---------------------------------------------
pt=$(row_point work alpha.txt)
echo "  $("$MOUSE" click ${pt% *} ${pt#* } --right)"
sleep 1
f=$(shot m4-1-context-menu)
menu_pick "copy" 2            # Copy, Copy path, Copy as path
sleep 0.6
got=$(plain_path "$(pbpaste)")
want=$(plain_path "\"$WORK/alpha.txt\"")
if [ -n "$f" ] && [ "$got" = "$want" ]; then
    pass 1 copy-as-path "menu shot $f; pbpaste reads $got"
else
    fail 1 copy-as-path "pbpaste reads [$got], expected [$want]; shot: ${f:-none}"
fi

# --- 2 and 3: Option+Return: Properties, General then Permissions ----------------------------------------
keys 'key code 36 using option down'
if wait_window "alpha.txt Properties" 5; then
    sleep 1
    f=$(shot m4-2-properties-general)
    size=$(ax value AXStaticText "Size" "alpha.txt Properties")
    kind=$(ax value AXStaticText "Type" "alpha.txt Properties")
    if [ -n "$f" ] && echo "$size" | grep -q "6 bytes"; then
        pass 2 properties "General: Type \"$kind\", Size \"$size\", $f"
    else
        fail 2 properties "General: Size \"$size\", shot: ${f:-none}"
    fi
    r=$(ax press AXButton "Permissions" "alpha.txt Properties")
    sleep 0.8
    f=$(shot m4-3-properties-permissions)
    mode=$(ax value AXStaticText "Mode" "alpha.txt Properties")
    owner=$(ax value AXStaticText "Owner" "alpha.txt Properties")
    if [ "$r" = "pressed" ] && echo "$mode" | grep -q "rw-r--r--"; then
        pass 3 permissions "tab $r, Owner \"$owner\", Mode \"$mode\", $f"
    else
        fail 3 permissions "tab: $r, Mode \"$mode\", shot: ${f:-none}"
    fi
    keys 'key code 53'
    if wait_no_window "alpha.txt Properties" 5; then echo "  Esc closed Properties"; else fail 3 close "still open"; fi
else
    shot m4-2-properties-general >/dev/null
    fail 2 properties "no window \"alpha.txt Properties\" (windows: $(names_now))"
fi
osascript -e 'tell application "System Events" to set frontmost of process "Folio" to true' >/dev/null 2>&1
sleep 0.5

# --- 3b: a marquee whose release never reaches Folio; then one click and Down work at once ----------------
# The press follows the button, not only its mouse-up event: once the button is up, the marquee ends.
# Without that, the click's mouse-up went to ending the marquee, the list sat in that click's press, and
# Down waited for the next click. Mission Control or a Space switch can take a release on a real Mac; in
# the VM, Ctrl+Up during a press still let the release through, so an event tap drops it instead.
blank=$(list_blank work)
over=$(row_point work delta.txt)
echo "  $("$MOUSE" press ${blank% *} ${blank#* } ${over% *} ${over#* })"
sleep 0.4
f1=$(shot m4-3b-marquee-held)
banded=$(selected_rows work)
rel=$("$MOUSE" release ${over% *} ${over#* } --swallow-for "$(pgrep -x Folio | head -1)")
echo "  $rel"
sleep 0.8
f2=$(shot m4-3c-after-lost-release)
pt=$(row_point work alpha.txt)
echo "  $("$MOUSE" click ${pt% *} ${pt#* })"
sleep 0.5
keys 'key code 125'
sleep 0.8
after=$(selected_rows work)
f3=$(shot m4-3d-after-press)
if echo "$rel" | grep -q "dropped before process [0-9]*; left button down now: false" && [ "$after" = "beta.txt" ]; then
    pass 3b press-without-release "marquee held over [$banded], its release dropped before Folio; one click on alpha.txt and Down select [$after]; $f1 $f2 $f3"
else
    fail 3b press-without-release "marquee [$banded]; release: [$rel]; after a click on alpha.txt and Down: [$after], expected beta.txt; ${f3:-no shot}"
fi
# A list still stuck in a press would hold the next steps' events: one more release frees it.
[ "$after" = "beta.txt" ] || echo "  $("$MOUSE" click ${pt% *} ${pt#* })"

# --- 4 and 5: drag beta.txt onto the target row ------------------------------------------------------
from=$(row_point work beta.txt)
to=$(row_point work target)
rm -f "$SHOTS/m4-4-drag-over-target.png"
echo "  $("$MOUSE" drag ${from% *} ${from#* } ${to% *} ${to#* } --hold 0.3 --shot "$SHOTS/m4-4-drag-over-target.png" --shot-at 0.05)"
if wait_file "$WORK/target/beta.txt" 8 && [ ! -e "$WORK/beta.txt" ] && wait_rows work 5 alpha.txt && ! has_row work beta.txt; then
    sleep 0.8
    f=$(shot m4-5-dropped)
    pass 4 drag-move "beta.txt moved into target (same volume), mid-drag shot $SHOTS/m4-4-drag-over-target.png, $f"
else
    shot m4-5-dropped >/dev/null
    fail 4 drag-move "target holds: $(ls "$WORK/target" | paste -sd ' ' -), work rows: $(row_names work), windows: $(names_now)"
fi
[ -s "$SHOTS/m4-4-drag-over-target.png" ] || fail 4 mid-drag "no mid-drag shot"

# --- 6: right-click empty space: the background menu --------------------------------------------------
pt=$(list_blank work)
echo "  $("$MOUSE" click ${pt% *} ${pt#* } --right)"
sleep 1
f=$(shot m4-6-background-menu)
menu_close
sleep 0.5
if [ -n "$f" ]; then pass 6 background-menu "$f"; else fail 6 background-menu "no shot"; fi

# --- 7: Control-drop gamma.txt on target: the Move here / Copy here / Create alias here menu -------------
from=$(row_point work gamma.txt)
to=$(row_point work target)
echo "  $("$MOUSE" drag ${from% *} ${from#* } ${to% *} ${to#* } --hold 0.5 --control)"
sleep 1
f=$(shot m4-7-control-drop-menu)
menu_pick "copy"              # Copy here
if wait_file "$WORK/target/gamma.txt" 8 && [ -e "$WORK/gamma.txt" ]; then
    sleep 0.8
    f2=$(shot m4-7b-copied)
    pass 7 control-drop "the menu came up ($f); Copy here left gamma.txt in work and put a copy in target, $f2"
else
    shot m4-7b-copied >/dev/null
    fail 7 control-drop "target holds: $(ls "$WORK/target" | paste -sd ' ' -), work has gamma: $([ -e "$WORK/gamma.txt" ] && echo yes || echo no)"
fi

# --- 8: spring-loaded folder: hold over target, it opens, drop inside ------------------------------------
from=$(row_point work delta.txt)
to=$(row_point work target)
blank=$(list_blank work)
echo "  $("$MOUSE" drag ${from% *} ${from#* } ${to% *} ${to#* } --hold 1.6 --shot "$SHOTS/m4-8-spring-loaded.png" --shot-at 1.3 --then ${blank% *} ${blank#* } --then-hold 0.6)"
if wait_file "$WORK/target/delta.txt" 8 && [ ! -e "$WORK/delta.txt" ] && wait_window target 5; then
    sleep 0.8
    f=$(shot m4-8b-spring-dropped)
    pass 8 spring-loaded "target opened under the drag and took delta.txt, window now \"target\", $f"
else
    shot m4-8b-spring-dropped >/dev/null
    fail 8 spring-loaded "target holds: $(ls "$WORK/target" | paste -sd ' ' -), windows: $(names_now)"
fi

# --- 9: back in work, drop target between Quick access's first two pins ----------------------------------
keys 'keystroke "[" using command down'
if wait_window work 5 && wait_rows work 5 target; then
    sleep 0.6
    from=$(row_point work target)
    gap=$(quick_access_gap work 1)
    echo "  $("$MOUSE" drag ${from% *} ${from#* } ${gap% *} ${gap#* } --hold 0.4)"
    sleep 1
    pins=$(defaults read com.anshul.folio quickAccessPins 2>/dev/null | tr -d '\n' | tr -s ' ')
    f=$(shot m4-9-pinned)
    second=$(defaults read com.anshul.folio quickAccessPins 2>/dev/null | sed -n 3p | tr -d ' ",')
    if [ "$(plain_path "$second")" = "$(plain_path "$WORK/target")" ]; then
        pass 9 pin "target pinned second: $pins, $f"
    else
        fail 9 pin "pins: $pins, shot: ${f:-none}"
    fi
else
    fail 9 pin "Cmd+[ did not go back to work (windows: $(names_now))"
fi

# --- 10: Create alias from the item menu ------------------------------------------------------------
pt=$(row_point work epsilon.txt)
echo "  $("$MOUSE" click ${pt% *} ${pt#* } --right)"
sleep 1
menu_pick "create"            # Create alias
if wait_rows work 5 "epsilon.txt alias" && [ -e "$WORK/epsilon.txt alias" ]; then
    sleep 0.6
    f=$(shot m4-10-alias)
    pass 10 alias "epsilon.txt alias made next to it, $f"
else
    shot m4-10-alias >/dev/null
    fail 10 alias "rows: $(row_names work)"
fi

# --- 11: the drags above ended cleanly: no "unrecognized selector" in Folio's log -------------------------
# NSTableView and NSOutlineView have no draggingEnded:, so a super call there threw inside macOS's drag
# completion; the system then still saw a drag (step 12).
thrown=$(log show --start "$LOG_START" --style compact --predicate 'process == "Folio"' 2>/dev/null | grep "unrecognized selector")
if [ -z "$thrown" ]; then
    pass 11 drag-log "no \"unrecognized selector\" in Folio's log since launch ($LOG_START), after the drags of steps 4 to 9"
else
    fail 11 drag-log "$(echo "$thrown" | wc -l | tr -d ' ') lines, first: $(echo "$thrown" | head -1 | cut -c1-220)"
fi

# --- 12: Mission Control still opens (Ctrl+Up) with Folio running ------------------------------------------
osascript -e 'tell application "System Events" to key code 126 using control down' >/dev/null 2>&1
if wait_mission_control true 4; then
    sleep 0.6
    f=$(shot m4-12-mission-control)
    pass 12 mission-control "Ctrl+Up opened Mission Control after the drags; $f"
else
    f=$(shot m4-12-mission-control)
    fail 12 mission-control "Ctrl+Up: no Mission Control within 4 s; ${f:-no shot}"
fi
osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1
wait_mission_control false 3

# --- quit and clean up ------------------------------------------------------------------------------
osascript -e 'quit app "Folio"' >/dev/null 2>&1
i=0
while pgrep -x Folio >/dev/null && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
if pgrep -x Folio >/dev/null; then
    pkill -x Folio
    fail 13 quit "Folio was still running 10 s after quit"
else
    pass 13 quit "Folio quit"
fi
defaults delete com.anshul.folio quickAccessPins >/dev/null 2>&1
mv "$ROOT" "$HOME/.Trash/" 2>/dev/null

if [ "$fails" -eq 0 ]; then
    echo "result: ok, PNGs in $SHOTS"
    exit 0
fi
echo "result: FAILED ($fails steps), PNGs in $SHOTS"
exit 1
