#!/bin/bash
# Milestone 5 GUI check: the navigation pane's tree, tabs (tear out and merge too), a second window side
# by side, Home, This PC with a scratch disk image (Properties, Rename, Eject, opening the image), the
# session coming back after a relaunch, and the Recycle Bin with Restore. Then, in a second launch, how
# the navigation pane follows the folder: a Quick access click keeps the pane still, while Ctrl+Shift+E,
# New folder from a pin's menu and a typed path scroll to the folder's tree row.
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Mounts the scratch image /private/tmp/folio-tests/scratch.dmg (FolioScratch) so This PC shows
# two volumes, makes /private/tmp/folio-tests/m5-<stamp>/work with a three-level tree
# (alpha/beta/gamma) plus delta (holding report-<time>.txt, "report.txt" below) and notes.txt, opens
# ~/folio/Folio.app on it and drives it with real events: System Events for keys, menus and
# accessibility, folio-mouse5 (CGEvent through the HID tap, compiled here with swiftc) for clicks,
# middle-clicks, right-clicks and drags.
# PNGs go to ~/folio/shots/:
#   m5-1-tree-expanded.png   Ctrl+Shift+E: the tree open down to work (hidden /private revealed), work
#                            selected; Right opens work itself
#   m5-2-tree-click.png      a click on alpha in the tree: the window goes to alpha, its row lit
#   m5-3-two-tabs.png        Cmd+T: a second tab on alpha
#   m5-4-ctrl-tab.png        tab 2 sent to delta through Cmd+L, then Ctrl+Tab back to tab 1 (alpha)
#   m5-5-middle-click.png    middle-click the beta row: a third tab, in the background
#   m5-6-one-tab.png         Cmd+W twice: one tab left (delta)
#   m5-7-two-windows.png     Cmd+N: a second window on delta
#   m5-8-tiled.png           Window > Tile Left and Right: the two windows side by side
#   m5-9-home.png            Go > Home (Cmd+Shift+H) in the left half: the Home panels
#   m5-9b-home-wide.png      Window > Zoom: pins as tiles, report.txt in Favorites and Recent files, Recent locations
#   m5-10-this-pc.png        Quick access folded, the startup disk's tree folded: This PC shows two volumes
#   m5-10b-drive-properties.png  FolioScratch's Properties: used and free ring, bar and legend
#   m5-10c-renamed.png       Rename... from the drive's menu (diskutil rename): FolioScratch is ScratchRenamed
#   m5-11-ejected.png        Eject on ScratchRenamed: unmounted, one volume left
#   m5-11b-image-opened.png  in a new tab, scratch.dmg opened from the list: attached and shown as a drive
#   m5-11c-image-ejected.png File > Eject: detached, the tab back at Home
#   m5-12-restored.png       quit and relaunch with no folder: both windows and their tabs come back
#   m5-13-recycle-bin.png    report.txt deleted (Cmd+Delete), the Recycle Bin row: Original location, Date deleted
#   m5-14-restored-file.png  Restore from its menu: report.txt back in delta
#   m5-15-torn-out.png       a tab dragged off the strip: its own window
#   m5-16-merged.png         that tab dropped on the first window's strip: merged back, the window gone
#   m5-18-pin-click.png      a short window, pane at the top, a click on the delta pin: the tree opens to
#                            delta under work, and the pane stays where it was
#   m5-19-expand-current.png Ctrl+Shift+E: the pane scrolls to delta's tree row and selects it
#   m5-20-new-folder.png     pane at the top again, New folder here from the delta pin's menu: the pane
#                            scrolls to the new folder's tree row
#   m5-21-typed-path.png     pane at the top, work/alpha/beta/gamma typed in the address bar: the pane
#                            scrolls to gamma's tree row
# Prints one line per step and exits non-zero if any step fails.
set -u

APP="$HOME/folio/Folio.app"
SHOTS="$HOME/folio/shots"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT="/private/tmp/folio-tests/m5-$STAMP"
WORK="$ROOT/work"
SCRATCH_DMG="/private/tmp/folio-tests/scratch.dmg"
SCRATCH="/Volumes/FolioScratch"
MOUSE="$HOME/folio/folio-mouse5"
# A name of its own each run, so an older copy in the Trash is never mistaken for it.
REPORT="report-${STAMP#*-}.txt"
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "m5: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if [ ! -d "$APP" ]; then
    echo "m5: missing $APP (stage the build first, docs/plan/VM.md)"
    exit 2
fi

pass() { echo "step $1 $2: ok - $3"; }
fail() { echo "step $1 $2: FAILED - $3"; fails=$((fails + 1)); }

# --- folio-mouse5: real clicks (left, right, middle) through the HID event tap ------------------------
mkdir -p "$HOME/folio" "$ROOT"
cat > "$ROOT/folio-mouse5.swift" <<'SWIFT'
// folio-mouse5: real mouse events through the HID event tap, for the VM scripts (docs/plan/VM.md).
// Compiled inside the test VM with swiftc; never run on a host Mac (RULES.md, rule 0).
//   folio-mouse5 click <x> <y> [--right | --middle] [--option]
//   folio-mouse5 drag <x1> <y1> <x2> <y2> [--hold S]
import CoreGraphics
import Foundation

let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ p: CGPoint, _ button: CGMouseButton, _ flags: CGEventFlags = []) {
    guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
    e.flags = flags
    e.setIntegerValueField(.mouseEventClickState, value: 1)
    if button == .center { e.setIntegerValueField(.mouseEventButtonNumber, value: 2) }
    e.post(tap: .cghidEventTap)
}
var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}
let right = flag("--right"), middle = flag("--middle"), option = flag("--option")
var hold = 0.5
if let i = args.firstIndex(of: "--hold"), args.indices.contains(i + 1) {
    hold = Double(args[i + 1]) ?? 0.5
    args.removeSubrange(i...(i + 1))
}
let nums = args.dropFirst().compactMap(Double.init)
if args.first == "drag", nums.count == 4 {
    let a = CGPoint(x: nums[0], y: nums[1]), b = CGPoint(x: nums[2], y: nums[3])
    post(.mouseMoved, a, .left)
    usleep(150_000)
    post(.leftMouseDown, a, .left)
    usleep(250_000)
    for i in 1...40 {
        let t = CGFloat(i) / 40
        post(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), .left)
        usleep(25_000)
    }
    var held = 0.0
    while held < hold {
        post(.leftMouseDragged, CGPoint(x: b.x + CGFloat(Int(held * 20) % 2), y: b.y), .left)
        usleep(50_000)
        held += 0.05
    }
    post(.leftMouseUp, b, .left)
    // Stay a moment: a release posted just before exiting can be lost, leaving the button held.
    usleep(300_000)
    print("drag \(Int(a.x)),\(Int(a.y)) -> \(Int(b.x)),\(Int(b.y))")
    exit(0)
}
if args.first == "release" {
    // A clean start: the left button up wherever the pointer is.
    let here = CGEvent(source: nil)?.location ?? .zero
    post(.leftMouseUp, here, .left)
    usleep(300_000)
    print("released at \(Int(here.x)),\(Int(here.y))")
    exit(0)
}
guard args.first == "click", nums.count == 2 else {
    print("usage: folio-mouse5 click <x> <y> [--right | --middle] [--option] | drag <x1> <y1> <x2> <y2> [--hold S]")
    exit(2)
}
let p = CGPoint(x: nums[0], y: nums[1])
let button: CGMouseButton = right ? .right : middle ? .center : .left
let (down, up): (CGEventType, CGEventType) = right ? (.rightMouseDown, .rightMouseUp)
    : middle ? (.otherMouseDown, .otherMouseUp) : (.leftMouseDown, .leftMouseUp)
post(.mouseMoved, p, .left)
usleep(120_000)
post(down, p, button, option ? .maskAlternate : [])
usleep(60_000)
post(up, p, button, option ? .maskAlternate : [])
usleep(150_000)
print("click at \(Int(p.x)),\(Int(p.y))" + (right ? " with the right button" : middle ? " with the middle button" : ""))
SWIFT
if ! cmp -s "$ROOT/folio-mouse5.swift" "$HOME/folio/folio-mouse5.swift" || [ ! -x "$MOUSE" ]; then
    cp "$ROOT/folio-mouse5.swift" "$HOME/folio/folio-mouse5.swift"
    swiftc -O "$HOME/folio/folio-mouse5.swift" -o "$MOUSE" 2>&1 | tail -5
fi
if [ ! -x "$MOUSE" ]; then echo "m5: could not build folio-mouse5"; exit 2; fi

# --- helpers ------------------------------------------------------------------------------------------
frontmost() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>&1; }

keys() {
    echo "  key: $1 (frontmost: $(frontmost))"
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to $1" >/dev/null 2>&1
}

front() { osascript -e 'tell application "System Events" to set frontmost of process "Folio" to true' >/dev/null 2>&1; }

menu_pick() {
    echo "  menu: type \"$1\", Return"
    osascript -e "tell application \"System Events\" to keystroke \"$1\"" >/dev/null 2>&1
    sleep 0.4
    osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
}

# menu_bar <menu> <item>: picks an item from the menu bar, as a person would.
menu_bar() {
    echo "  menu bar: $1 > $2"
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to click menu item \"$2\" of menu \"$1\" of menu bar 1" 2>&1 | grep -v "^menu item" | head -2
}

window_names() {
    osascript -e 'tell application "System Events" to tell process "Folio" to get name of every window' 2>/dev/null \
        | tr ',' '\n' | sed 's/^ *//;s/ *$//'
}
has_window() { window_names | grep -Fxq "$1"; }
names_now() { window_names | paste -sd '|' -; }
window_count() { window_names | grep -c . ; }

wait_window() {
    local i=0 n=$(( ${2:-10} * 4 ))
    while [ "$i" -lt "$n" ]; do
        has_window "$1" && return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}

wait_windows() {
    local i=0 n=$(( ${2:-10} * 4 ))
    while [ "$i" -lt "$n" ]; do
        [ "$(window_count)" -eq "$1" ] && return 0
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

# tabs <window>: each tab as "title=1" (shown) or "title=0", left to right, joined with |.
tabs() {
    osascript - "$1" 2>/dev/null <<'OSA'
on run argv
    set out to {}
    tell application "System Events" to tell process "Folio"
        set g to first group of window (item 1 of argv) whose description is "Tabs"
        repeat with r in radio buttons of g
            set end of out to ((description of r) as text) & "=" & ((value of r) as text)
        end repeat
    end tell
    set AppleScript's text item delimiters to "|"
    return out as text
end run
OSA
}

# tab_point <window> <index>: "x y" in the middle of tab <index> (1-based).
tab_point() {
    osascript - "$1" "$2" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        set g to first group of window (item 1 of argv) whose description is "Tabs"
        set r to radio button ((item 2 of argv) as integer) of g
        set {px, py} to position of r
        set {sx, sy} to size of r
        return ((px + (sx div 2) - 20) as text) & " " & ((py + (sy div 2)) as text)
    end tell
end run
OSA
}

wait_tabs() {
    local i=0 n=$(( ${3:-8} * 4 ))
    while [ "$i" -lt "$n" ]; do
        [ "$(tabs "$1")" = "$2" ] && return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}

# list_rows <window>: the file list's names.
list_rows() {
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
wait_list_row() {
    local i=0 n=$(( ${3:-8} * 4 ))
    while [ "$i" -lt "$n" ]; do
        list_rows "$1" | grep -Fxq "$2" && return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}

# list_point <window> <name>: "x y" on a file list row's name.
list_point() {
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

# tree_rows <window>: the navigation pane's rows, top to bottom, joined with |.
tree_rows() {
    osascript - "$1" 2>/dev/null <<'OSA'
on run argv
    set out to {}
    tell application "System Events" to tell process "Folio"
        set o to outline 1 of scroll area 1 of window (item 1 of argv)
        repeat with r in rows of o
            set end of out to (description of UI element 1 of r) as text
        end repeat
    end tell
    set AppleScript's text item delimiters to "|"
    return out as text
end run
OSA
}

# tree_selected <window>: the name on the navigation pane's selected row.
tree_selected() {
    osascript - "$1" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        set o to outline 1 of scroll area 1 of window (item 1 of argv)
        repeat with r in rows of o
            if selected of r then return (description of UI element 1 of r) as text
        end repeat
    end tell
    return ""
end run
OSA
}

# tree_point <window> <name> <dx> <dy>: "x y" at an offset into the first tree row with that name
# (dy -1 means the row's middle). Rows above the visible part are scrolled to first.
tree_point() {
    osascript - "$1" "$2" "$3" "$4" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        set s to scroll area 1 of window (item 1 of argv)
        set o to outline 1 of s
        set {sx, sy} to position of s
        set {sw, sh} to size of s
        repeat with r in rows of o
            if ((description of UI element 1 of r) as text) is (item 2 of argv) then
                set {px, py} to position of r
                set {rw, rh} to size of r
                if py < sy or py + rh > sy + sh then
                    try
                        set v to value of scroll bar 1 of s
                        set total to 0
                        repeat with q in rows of o
                            set total to total + (item 2 of (size of q as list))
                        end repeat
                        set offsetY to (py - sy) - (sh div 3)
                        set newV to v + offsetY / (total - sh)
                        if newV < 0 then set newV to 0
                        if newV > 1 then set newV to 1
                        set value of scroll bar 1 of s to newV
                        delay 0.4
                        set {px, py} to position of r
                    end try
                end if
                set dy to (item 4 of argv) as integer
                if dy < 0 then set dy to rh div 2
                return ((px + ((item 3 of argv) as integer)) as text) & " " & ((py + dy) as text)
            end if
        end repeat
    end tell
    return ""
end run
OSA
}

# ax_point <AXRole> <description> <window>: "x y" at the middle of the first match, eight levels deep.
ax_point() {
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
    tell application "System Events" to tell process "Folio"
        set found to my find(window (item 3 of argv), item 1 of argv, item 2 of argv, 8)
        if found is missing value then return ""
        set {px, py} to position of found
        set {sx, sy} to size of found
        return ((px + (sx div 2)) as text) & " " & ((py + (sy div 2)) as text)
    end tell
end run
OSA
}

# pane_scroll <window>: the navigation pane's vertical scroll position, 0 (top) to 1.
pane_scroll() {
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to get value of scroll bar 1 of scroll area 1 of window \"$1\"" 2>/dev/null
}
pane_top() {
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to set value of scroll bar 1 of scroll area 1 of window \"$1\" to 0" >/dev/null 2>&1
    sleep 0.5
}

# tree_in_view <window> <name>: "yes" when the last tree row with that name (a tree row comes after a pin
# of the same name) lies inside the pane's scroll area, "no" when it is out of view, "" with no such row.
tree_in_view() {
    osascript - "$1" "$2" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        set s to scroll area 1 of window (item 1 of argv)
        set {sx, sy} to position of s
        set {sw, sh} to size of s
        set found to ""
        repeat with r in rows of outline 1 of s
            if ((description of UI element 1 of r) as text) is (item 2 of argv) then
                set {px, py} to position of r
                set {rw, rh} to size of r
                if py >= sy and py + rh <= sy + sh then
                    set found to "yes"
                else
                    set found to "no"
                end if
            end if
        end repeat
        return found
    end tell
end run
OSA
}

click_at() {
    local pt="$1"
    shift
    [ -n "$pt" ] || { echo "  (no point to click)"; return 1; }
    echo "  $("$MOUSE" click ${pt% *} ${pt#* } "$@")"
}

window_x() {
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to get item 1 of (position of window \"$1\" as list)" 2>/dev/null
}

clean_defaults() {
    for k in session quickAccessPins navPaneCollapsed homeCollapsed favorites recentFiles addressHistory \
             navPaneExpandToCurrent navPaneShown navPaneWidth showHiddenItems trashOrigins; do
        defaults delete com.anshul.folio "$k" >/dev/null 2>&1
    done
}

# scratch_disks: the device of every attachment of the scratch image, mounted or not.
scratch_disks() {
    hdiutil info | awk -v img="$SCRATCH_DMG" '
        /^image-path/ { want = ($3 == img); next }
        want && /^\/dev\/disk[0-9]+[ \t]/ { print $1; want = 0 }'
}
detach_scratch() {
    for d in $(scratch_disks); do hdiutil detach "$d" -force >/dev/null 2>&1; done
}

quit_folio() {
    osascript -e 'quit app "Folio"' >/dev/null 2>&1
    local i=0
    while pgrep -x Folio >/dev/null && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
    if pgrep -x Folio >/dev/null; then pkill -x Folio; return 1; fi
    return 0
}

# --- setup: the scratch volume, the tree, a clean start ------------------------------------------------
echo "  $("$MOUSE" release)"
mkdir -p "$SHOTS" "$WORK/alpha/beta/gamma" "$WORK/delta" "$WORK/epsilon"
echo "notes" > "$WORK/notes.txt"
echo "report" > "$WORK/delta/$REPORT"
echo "setup: $WORK with alpha/beta/gamma, delta ($REPORT), epsilon, notes.txt"

quit_folio
clean_defaults
# Folio follows the Mac's light or dark setting (it has no theme of its own): the shots are in dark.
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1
for v in "$SCRATCH" /Volumes/ScratchRenamed; do [ -d "$v" ] && hdiutil detach "$v" -force >/dev/null 2>&1; done
detach_scratch
mkdir -p /private/tmp/folio-tests
if hdiutil create -ov -size 200m -fs APFS -volname FolioScratch "$SCRATCH_DMG" >/dev/null 2>&1 \
   && hdiutil attach "$SCRATCH_DMG" >/dev/null 2>&1 && [ -d "$SCRATCH" ]; then
    # Spotlight would keep the new volume busy and refuse the eject.
    sudo -n mdutil -i off "$SCRATCH" >/dev/null 2>&1
    echo "setup: $SCRATCH_DMG attached at $SCRATCH"
else
    echo "setup: FAILED - could not create or attach $SCRATCH_DMG"
    exit 1
fi
osascript >/dev/null 2>&1 <<'OSA'
tell application "System Events" to tell process "NotificationCenter"
    repeat 5 times
        if not (exists window 1) then exit repeat
        try
            set banner to group 1 of scroll area 1 of group 1 of group 1 of window 1
            repeat with a in (actions of banner)
                if name of a starts with "Name:Close" then perform a
            end repeat
        on error
            exit repeat
        end try
        delay 0.3
    end repeat
end tell
OSA

open -a "$APP" "$WORK"
if wait_window "work" 15 && wait_list_row work notes.txt 10; then
    echo "launch: ok - window \"work\", tabs: $(tabs work)"
else
    echo "launch: FAILED - no window \"work\" with rows after 15 s (windows: $(names_now))"
    exit 1
fi
front
sleep 1.5

# --- 1: Ctrl+Shift+E expands the tree to the current folder; Right opens work -------------------------------
keys 'key code 14 using {control down, shift down}'
sleep 1
sel=$(tree_selected work)
rows=$(tree_rows work)
keys 'key code 124'
sleep 0.8
rows2=$(tree_rows work)
f=$(shot m5-1-tree-expanded)
if [ "$sel" = "work" ] && echo "$rows" | grep -q "|private|" && echo "$rows" | grep -q "|m5-$STAMP|work" \
   && echo "$rows2" | grep -q "|work|alpha|delta|epsilon"; then
    pass 1 expand-to-current "selected row \"$sel\"; the tree runs / > private > tmp > folio-tests > m5-$STAMP > work; Right opened work: alpha, delta, epsilon; $f"
else
    fail 1 expand-to-current "selected \"$sel\"; rows: $rows2; shot: ${f:-none}"
fi

# --- 2: click alpha in the tree -------------------------------------------------------------------------
click_at "$(tree_point work alpha 120 -1)"
if wait_window alpha 6 && wait_list_row alpha beta 6; then
    sleep 1
    f=$(shot m5-2-tree-click)
    pass 2 tree-click "the window went to alpha (list: $(list_rows alpha | paste -sd ' ' -)), tree selection \"$(tree_selected alpha)\", $f"
else
    shot m5-2-tree-click >/dev/null
    fail 2 tree-click "windows: $(names_now)"
fi

# --- 3: Cmd+T: two tabs ---------------------------------------------------------------------------------
keys 'keystroke "t" using command down'
if wait_tabs alpha "alpha=0|alpha=1" 6; then
    sleep 0.6
    f=$(shot m5-3-two-tabs)
    pass 3 new-tab "tabs: $(tabs alpha), $f"
else
    shot m5-3-two-tabs >/dev/null
    fail 3 new-tab "tabs: $(tabs alpha)"
fi

# --- 4: tab 2 goes to delta through the address bar; Ctrl+Tab back to tab 1 ----------------------------------
keys 'keystroke "l" using command down'
sleep 0.5
keys 'keystroke "a" using command down'
keys "keystroke \"$WORK/delta\""
sleep 0.5
keys 'key code 36'
if wait_window delta 6 && wait_tabs delta "alpha=0|delta=1" 6; then
    echo "  tab 2 is on delta: $(tabs delta)"
    keys 'key code 48 using control down'
    if wait_window alpha 6 && wait_tabs alpha "alpha=1|delta=0" 6 && wait_list_row alpha beta 6; then
        sleep 0.8
        f=$(shot m5-4-ctrl-tab)
        pass 4 ctrl-tab "Ctrl+Tab went back to tab 1: $(tabs alpha), list $(list_rows alpha | paste -sd ' ' -), $f"
    else
        shot m5-4-ctrl-tab >/dev/null
        fail 4 ctrl-tab "windows: $(names_now), tabs: $(tabs alpha; tabs delta)"
    fi
else
    shot m5-4-ctrl-tab >/dev/null
    fail 4 address "Cmd+L, $WORK/delta, Return: windows $(names_now), tabs $(tabs delta)"
fi

# --- 5: middle-click the beta row: a third tab in the background -------------------------------------------
click_at "$(list_point alpha beta)" --middle
if wait_tabs alpha "alpha=1|beta=0|delta=0" 6; then
    sleep 0.6
    f=$(shot m5-5-middle-click)
    pass 5 middle-click "beta opened behind: $(tabs alpha), window still \"alpha\", $f"
else
    shot m5-5-middle-click >/dev/null
    fail 5 middle-click "tabs: $(tabs alpha), windows: $(names_now)"
fi

# --- 6: Cmd+W twice: one tab -----------------------------------------------------------------------------
keys 'keystroke "w" using command down'
sleep 1
echo "  after one Cmd+W: windows $(names_now), tabs $(tabs beta 2>/dev/null)"
keys 'keystroke "w" using command down'
if wait_window delta 6 && wait_tabs delta "delta=1" 6 && [ "$(window_count)" -eq 1 ]; then
    wait_list_row delta $REPORT 6
    sleep 0.6
    f=$(shot m5-6-one-tab)
    pass 6 close-tabs "one window, one tab: $(tabs delta), $f"
else
    shot m5-6-one-tab >/dev/null
    fail 6 close-tabs "windows: $(names_now), tabs: $(tabs delta)"
fi

# $REPORT goes to Favorites from its menu (Home shows it in step 9).
click_at "$(list_point delta $REPORT)" --right
sleep 0.8
menu_pick "add"
sleep 0.6
favs=$(defaults read com.anshul.folio favorites 2>/dev/null | tr -d '\n' | tr -s ' ')
echo "  favorites now: $favs"
# Open it (Return on the row) so it lands in Recent files, then close TextEdit again.
click_at "$(list_point delta $REPORT)"
sleep 0.4
keys 'key code 36'
sleep 3
osascript -e 'quit app "TextEdit" saving no' >/dev/null 2>&1
sleep 1
front
sleep 0.6
echo "  recent files now: $(defaults read com.anshul.folio recentFiles 2>/dev/null | tr -d '\n' | tr -s ' ')"

# --- 7 and 8: Cmd+N, then Window > Tile Left and Right -----------------------------------------------------
keys 'keystroke "n" using command down'
if wait_windows 2 6; then
    sleep 1.2
    f=$(shot m5-7-two-windows)
    pass 7 new-window "two windows: $(names_now), $f"
else
    shot m5-7-two-windows >/dev/null
    fail 7 new-window "windows: $(names_now)"
fi
front
menu_bar Window "Tile Left and Right"
sleep 1.5
xs=$(osascript -e 'tell application "System Events" to tell process "Folio" to get position of every window' 2>/dev/null)
ws=$(osascript -e 'tell application "System Events" to tell process "Folio" to get size of every window' 2>/dev/null)
f=$(shot m5-8-tiled)
if echo "$xs" | grep -Eq "(^|, )0, " && echo "$xs" | grep -Eq "(^|, )512, " && [ -n "$f" ]; then
    pass 8 tile "positions $xs, sizes $ws, $f"
else
    fail 8 tile "positions $xs, sizes $ws, shot: ${f:-none}"
fi

# --- 9: Go > Home ----------------------------------------------------------------------------------------
keys 'keystroke "h" using {command down, shift down}'
if wait_window Home 6; then
    sleep 1.2
    f=$(shot m5-9-home)
    fav=$(ax_point AXButton $REPORT Home)
    qa=$(ax_point AXButton "Quick access section" Home)
    rl=$(ax_point AXButton "Recent locations section" Home)
    if [ -n "$fav" ] && [ -n "$qa" ] && [ -n "$rl" ]; then
        pass 9 home "Home shows Quick access, $REPORT in Favorites and Recent locations; tabs $(tabs Home), $f"
    else
        fail 9 home "favorite at [$fav], Quick access at [$qa], Recent locations at [$rl], shot: ${f:-none}"
    fi
else
    shot m5-9-home >/dev/null
    fail 9 home "windows: $(names_now)"
fi
menu_bar Window Zoom
sleep 1.5
f=$(shot m5-9b-home-wide)
recent=$(defaults read com.anshul.folio recentFiles 2>/dev/null | grep -c $REPORT)
if [ -n "$f" ] && [ "$recent" -ge 1 ] && [ -n "$(ax_point AXButton "Recent files section" Home)" ]; then
    pass 9b home-wide "zoomed Home: $REPORT in Favorites and Recent files, $f"
else
    fail 9b home-wide "recent log has $REPORT: $recent, shot: ${f:-none}"
fi

# --- 10: This PC with both volumes: fold Quick access and the startup disk's tree --------------------------
click_at "$(tree_point Home "Quick access" 120 31)"
sleep 0.8
click_at "$(tree_point Home "Macintosh HD" 23 17)"
sleep 1
osascript -e 'tell application "System Events" to tell process "Folio" to set value of scroll bar 1 of scroll area 1 of window "Home" to 0' >/dev/null 2>&1
sleep 0.5
rows=$(tree_rows Home)
collapsed=$(defaults read com.anshul.folio navPaneCollapsed 2>/dev/null | tr -d '\n' | tr -s ' ')
f=$(shot m5-10-this-pc)
if echo "$rows" | grep -q "This PC|Macintosh HD|FolioScratch|" && echo "$collapsed" | grep -q quickAccess; then
    pass 10 this-pc "rows: $rows; folded sections kept: $collapsed; $f"
else
    fail 10 this-pc "rows: $rows; folded: $collapsed; shot: ${f:-none}"
fi

# --- 10b: the drive's Properties: used and free --------------------------------------------------------------
click_at "$(tree_point Home FolioScratch 120 17)" --right
sleep 0.8
menu_pick "prop"
if wait_window "FolioScratch Properties" 5; then
    sleep 1
    f=$(shot m5-10b-drive-properties)
    used=$(osascript -e 'tell application "System Events" to tell process "Folio" to get value of (first static text of window "FolioScratch Properties" whose description is "Used space")' 2>&1)
    pass 10b drive-properties "Used space \"$used\", $f"
    keys 'key code 53'
    sleep 0.6
else
    shot m5-10b-drive-properties >/dev/null
    fail 10b drive-properties "windows: $(names_now)"
fi
front

# --- 10c: Rename... from the drive's menu (diskutil rename) ----------------------------------------------------
RENAMED="/Volumes/ScratchRenamed"
click_at "$(tree_point Home FolioScratch 120 17)" --right
sleep 0.8
menu_pick "ren"
sleep 1
keys 'keystroke "a" using command down'
keys 'keystroke "ScratchRenamed"'
keys 'key code 36'
i=0
while [ ! -d "$RENAMED" ] && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
sleep 1.5
rows=$(tree_rows Home)
f=$(shot m5-10c-renamed)
if [ -d "$RENAMED" ] && echo "$rows" | grep -q "|ScratchRenamed|"; then
    pass 10c rename-drive "diskutil renamed it: $RENAMED, rows: $rows, $f"
else
    fail 10c rename-drive "mounted: $(ls /Volumes | paste -sd ' ' -), rows: $rows, shot: ${f:-none}"
fi

# --- 11: Eject from the drive's row ------------------------------------------------------------------------
name=ScratchRenamed
[ -d "$RENAMED" ] || name=FolioScratch
pt=$(ax_point AXButton "Eject $name" Home)
click_at "$pt"
i=0
while { [ -d "$SCRATCH" ] || [ -d "$RENAMED" ]; } && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
sleep 1.5
rows=$(tree_rows Home)
f=$(shot m5-11-ejected)
if [ ! -d "$SCRATCH" ] && [ ! -d "$RENAMED" ] && ! echo "$rows" | grep -q "Scratch" && [ -z "$(scratch_disks)" ]; then
    pass 11 eject "$name unmounted and detached; rows: $rows; $f"
else
    fail 11 eject "button at [$pt], mounted: $(ls /Volumes | paste -sd ' ' -), rows: $rows, shot: ${f:-none}"
fi

# --- 11b and 11c: open scratch.dmg from the list (hdiutil attach), then File > Eject ------------------------------
keys 'keystroke "t" using command down'
sleep 0.8
keys 'keystroke "l" using command down'
sleep 0.4
keys 'keystroke "a" using command down'
keys 'keystroke "/private/tmp/folio-tests"'
keys 'key code 36'
if wait_window folio-tests 6 && wait_list_row folio-tests scratch.dmg 6; then
    click_at "$(list_point folio-tests scratch.dmg)"
    sleep 0.4
    keys 'key code 36'
    if wait_window ScratchRenamed 15; then
        sleep 1.5
        f=$(shot m5-11b-image-opened)
        pass 11b open-image "Return on scratch.dmg attached it and the tab shows the drive: $(names_now), $f"
        # File > Eject is Cmd+Shift+E since milestone 7 (Cmd+E is Explorer's Ctrl+E, the search box).
        keys 'keystroke "e" using {command down, shift down}'
        i=0
        while [ -d "$RENAMED" ] && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
        if [ ! -d "$RENAMED" ] && wait_tabs Home "Home=0|Home=1" 8 && [ -z "$(scratch_disks)" ]; then
            sleep 1
            f=$(shot m5-11c-image-ejected)
            pass 11c file-eject "File > Eject detached it, the tab went Home: $(tabs Home), $f"
        else
            shot m5-11c-image-ejected >/dev/null
            fail 11c file-eject "mounted: $(ls /Volumes | paste -sd ' ' -), windows: $(names_now)"
        fi
    else
        shot m5-11b-image-opened >/dev/null
        fail 11b open-image "windows: $(names_now), mounted: $(ls /Volumes | paste -sd ' ' -)"
    fi
else
    fail 11b open-image "no folio-tests listing (windows: $(names_now))"
fi
keys 'keystroke "w" using command down'
wait_tabs Home "Home=1" 5

# --- 12: quit, relaunch with no folder: the session comes back --------------------------------------------
before=$(names_now)
if quit_folio; then echo "  quit with windows: $before"; else fail 12 quit "Folio was still running 10 s after quit"; fi
open -a "$APP"
if wait_windows 2 15 && wait_window Home 5 && wait_window delta 5; then
    front
    sleep 1.5
    f=$(shot m5-12-restored)
    pass 12 restore "windows back: $(names_now) (tabs $(tabs delta)), $f"
else
    shot m5-12-restored >/dev/null
    fail 12 restore "after relaunch: $(names_now)"
fi

# --- 13 and 14: delete $REPORT, find it in the Recycle Bin, Restore it ---------------------------------------
# The restored Home window is zoomed over delta: delta comes to the front first.
osascript -e 'tell application "System Events" to tell process "Folio" to perform action "AXRaise" of window "delta"' >/dev/null 2>&1
sleep 0.8
click_at "$(list_point delta $REPORT)"
sleep 0.4
keys 'key code 51 using command down'
i=0
while [ -e "$WORK/delta/$REPORT" ] && [ "$i" -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
click_at "$(tree_point delta "Quick access" 120 31)"
sleep 0.8
click_at "$(tree_point delta "Recycle Bin" 120 -1)"
if wait_window "Recycle Bin" 6 && wait_list_row "Recycle Bin" $REPORT 6; then
    # Newest deleted first (View > Sort By > Date modified, which is Date deleted here): $REPORT on top.
    osascript -e 'tell application "System Events" to tell process "Folio" to click menu item "Date modified" of menu "Sort By" of menu item "Sort By" of menu "View" of menu bar 1' >/dev/null 2>&1
    sleep 1.2
    origin=$(osascript -e 'tell application "System Events" to tell process "Folio" to get description of UI element 3 of (first row of table 1 of scroll area 2 of window "Recycle Bin" whose description of UI element 1 is "'"$REPORT"'")' 2>&1)
    f=$(shot m5-13-recycle-bin)
    if [ "$(echo "$origin" | sed 's#^/private##')" = "$(echo "$WORK/delta" | sed 's#^/private##')" ]; then
        pass 13 recycle-bin "$REPORT listed with Original location $origin, $f"
    else
        fail 13 recycle-bin "Original location reads [$origin], shot: ${f:-none}"
    fi
    click_at "$(list_point "Recycle Bin" $REPORT)" --right
    sleep 0.8
    menu_pick "restore"
    i=0
    while [ ! -e "$WORK/delta/$REPORT" ] && [ "$i" -lt 24 ]; do sleep 0.25; i=$((i + 1)); done
    sleep 1
    f=$(shot m5-14-restored-file)
    if [ -e "$WORK/delta/$REPORT" ]; then
        pass 14 restore-file "$REPORT is back in delta, $f"
    else
        fail 14 restore-file "not back in delta; shot: ${f:-none}"
    fi
else
    f=$(shot m5-13-recycle-bin)
    fail 13 recycle-bin "windows: $(names_now), rows: $(list_rows "Recycle Bin" | paste -sd ' ' -), trash has it: $(ls ~/.Trash | grep -c report), shot: ${f:-none}"
fi

# --- 15 and 16: tear a tab out, then merge it back -----------------------------------------------------------
osascript -e 'tell application "System Events" to tell process "Folio" to perform action "AXRaise" of window "Recycle Bin"' >/dev/null 2>&1
win="Recycle Bin"
has_window "$win" || win=delta
keys 'keystroke "t" using command down'
sleep 0.6
keys 'keystroke "t" using command down'
if wait_tabs "$win" "$win=0|$win=0|$win=1" 6; then
    from=$(tab_point "$win" 2)
    orig=$(osascript -e "tell application \"System Events\" to tell process \"Folio\" to get position of window \"$win\"" 2>/dev/null | tr -d ' ')
    ox=${orig%,*}; oy=${orig#*,}
    echo "  $("$MOUSE" drag ${from% *} ${from#* } 300 560 --hold 0.4)"
    if wait_windows 3 6; then
        sleep 1.2
        f=$(shot m5-15-torn-out)
        pass 15 tear-out "tab 2 has its own window: $(names_now); first window tabs $(tabs "$win" | tr '\n' ' '), $f"
        # The new window is in front: its one tab goes back onto the first window's strip.
        newfrom=$(osascript -e 'tell application "System Events" to tell process "Folio" to get position of window 1' 2>/dev/null | tr -d ' ')
        nx=${newfrom%,*}; ny=${newfrom#*,}
        # Dropped past the first window's last tab: it goes on the end and is shown. The tabs sit in the
        # 44 pt title bar (centre 26 pt down), starting 88 pt in, after the traffic lights.
        echo "  $("$MOUSE" drag $((nx + 128)) $((ny + 26)) $((ox + 360)) $((oy + 26)) --hold 0.6)"
        if wait_windows 2 6 && wait_tabs "$win" "$win=0|$win=0|$win=1" 6; then
            sleep 1
            f=$(shot m5-16-merged)
            pass 16 merge "dropped on the first window's strip: tabs $(tabs "$win"), windows $(names_now), $f"
        else
            shot m5-16-merged >/dev/null
            fail 16 merge "windows: $(names_now), tabs: $(tabs "$win")"
        fi
    else
        shot m5-15-torn-out >/dev/null
        fail 15 tear-out "windows: $(names_now), tabs: $(tabs "$win")"
    fi
else
    fail 15 tear-out "Cmd+T twice: tabs $(tabs "$win")"
fi

if quit_folio; then pass 17 quit "Folio quit"; else fail 17 quit "Folio was still running 10 s after quit"; fi

# --- 18 to 21: how the navigation pane follows the folder (a second launch, a short window) -----------------
# Explorer's "Expand to open folder" opens the tree down to the folder after every move; the pane scrolls
# only when no row for that folder is in view. A short window keeps the tree rows under the pins out of
# view; delta is pinned after the six default pins.
clean_defaults
defaults write com.anshul.folio quickAccessPins -array "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents" \
    "$HOME/Pictures" "$HOME/Movies" "$HOME/Music" "$WORK/delta"
open -a "$APP" "$WORK"
if wait_window work 15 && wait_list_row work notes.txt 10; then
    front
    osascript -e 'tell application "System Events" to tell process "Folio" to set size of window "work" to {1000, 520}' >/dev/null 2>&1
    sleep 1
    pane_top work
    v0=$(pane_scroll work)
    click_at "$(tree_point work delta 120 -1)"
    if wait_window delta 6; then
        sleep 1.2
        v1=$(pane_scroll delta)
        rows=$(tree_rows delta)
        f=$(shot m5-18-pin-click)
        if [ "$v1" = "$v0" ] && echo "$rows" | grep -q "|work|alpha|delta|epsilon"; then
            pass 18 pin-click "the delta pin: the tree opened to work > delta, the pane stayed at $v1 ($v0 before); $f"
        else
            fail 18 pin-click "pane at [$v1], [$v0] before; rows: $rows; ${f:-no shot}"
        fi

        pane_top delta
        keys 'key code 14 using {control down, shift down}'
        sleep 1
        v2=$(pane_scroll delta)
        sel=$(tree_selected delta)
        seen=$(tree_in_view delta delta)
        f=$(shot m5-19-expand-current)
        if [ "$sel" = "delta" ] && [ "$seen" = "yes" ] && [ "$v2" != "$v0" ]; then
            pass 19 expand-current "Ctrl+Shift+E: delta's tree row selected and in view, the pane moved to $v2; $f"
        else
            fail 19 expand-current "selected [$sel], tree row in view [$seen], pane [$v2]; ${f:-no shot}"
        fi

        pane_top delta
        click_at "$(tree_point delta delta 120 -1)" --right
        sleep 0.8
        menu_pick "new"
        i=0
        while [ ! -d "$WORK/delta/New folder" ] && [ "$i" -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
        sleep 1
        v3=$(pane_scroll delta)
        seen=$(tree_in_view delta "New folder")
        f=$(shot m5-20-new-folder)
        if [ -d "$WORK/delta/New folder" ] && [ "$seen" = "yes" ]; then
            pass 20 new-folder "New folder here from the delta pin's menu: the pane scrolled to the new folder's tree row ($v3); $f"
        else
            fail 20 new-folder "made: $([ -d "$WORK/delta/New folder" ] && echo yes || echo no), its tree row in view [$seen], pane [$v3]; ${f:-no shot}"
        fi

        pane_top delta
        keys 'keystroke "l" using command down'
        sleep 0.5
        keys 'keystroke "a" using command down'
        keys "keystroke \"$WORK/alpha/beta/gamma\""
        sleep 0.5
        keys 'key code 36'
        if wait_window gamma 6; then
            sleep 1.2
            v4=$(pane_scroll gamma)
            seen=$(tree_in_view gamma gamma)
            f=$(shot m5-21-typed-path)
            if [ "$seen" = "yes" ] && [ "$v4" != "$v0" ]; then
                pass 21 typed-path "a typed path: the pane scrolled to gamma's tree row ($v4); $f"
            else
                fail 21 typed-path "gamma's tree row in view [$seen], pane [$v4]; ${f:-no shot}"
            fi
        else
            f=$(shot m5-21-typed-path)
            fail 21 typed-path "no window gamma (windows: $(names_now)); ${f:-no shot}"
        fi
    else
        f=$(shot m5-18-pin-click)
        fail 18 pin-click "no window delta after the pin click (windows: $(names_now)); ${f:-no shot}"
    fi
else
    fail 18 relaunch "no window work after the second launch (windows: $(names_now))"
fi

# --- quit and clean up ------------------------------------------------------------------------------------
if quit_folio; then pass 22 quit "Folio quit"; else fail 22 quit "Folio was still running 10 s after quit"; fi
clean_defaults
for v in "$SCRATCH" /Volumes/ScratchRenamed; do [ -d "$v" ] && hdiutil detach "$v" -force >/dev/null 2>&1; done
detach_scratch
mv "$SCRATCH_DMG" "$HOME/.Trash/scratch-$STAMP.dmg" 2>/dev/null
mv "$ROOT" "$HOME/.Trash/" 2>/dev/null

if [ "$fails" -eq 0 ]; then
    echo "result: ok, PNGs in $SHOTS"
    exit 0
fi
echo "result: FAILED ($fails steps), PNGs in $SHOTS"
exit 1
