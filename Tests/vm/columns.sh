#!/bin/bash
# Columns view GUI check (Finder's column view in Folio's look): Ctrl+Shift+9 on a tree 4 levels deep,
# Right, Right, Right, Left, a file selected (the preview column), F2 rename, a file dragged onto a folder
# in the column before, Cmd+Left back, Details and back (same folder), search results in their list, the
# greyed Group by, a divider dragged and double-clicked, and a 50,000-file folder in a column.
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Makes /private/tmp/folio-tests/columns-<stamp>/tree:
#   tree/ alpha/ beta/ gamma/ delta/ d1.txt         (4 levels under tree)
#   tree/alpha/ sibling/, a1.txt;  tree/alpha/beta/ b-notes.txt, move-me.txt, photo.png;  tree/alpha/beta/gamma/ g1.txt
#   tree/big/ 50,000 empty files;  tree/readme.txt
# pins tree to Quick access (so the columns start there, as Finder's do from a sidebar place), opens
# ~/folio/Folio.app on it and drives it with real events: System Events for keys and menus, folio-mouse-col
# (CGEvent through the HID tap, compiled here with swiftc) for clicks, drags and the scroll wheel.
# PNGs go to ~/folio/shots/:
#   columns-1-open.png       Ctrl+Shift+9 in tree: the Columns view, tree's column
#   columns-2-right3.png     Down, Right, Right, Right: tree, alpha, beta, gamma, then delta's contents
#   columns-3-left.png       Left: beta is the current column, gamma lit, gamma's contents after it
#   columns-4-preview.png    "ph" typed: photo.png selected, the preview column (thumbnail, Kind, Size...)
#   columns-5a-renaming.png  b-notes.txt, F2: the rename box over its name in the column
#   columns-5-renamed.png    "renamed" and Return: renamed.txt on disk and selected
#   columns-6a-drag-over.png move-me.txt dragged over sibling in alpha's column, mid-drag: sibling lit
#   columns-6-dragged.png    dropped: moved into alpha/sibling, gone from beta's column
#   columns-7-back.png       Cmd+Left: back to gamma
#   columns-8-details.png    Ctrl+Shift+6: Details of gamma (same folder)
#   columns-9-columns.png    View > Columns: gamma's column again
#   columns-10-search.png    Cmd+F "g1": results in the Details list, not columns
#   columns-11-groupby.png   View > Group By open: greyed in Columns
#   columns-12-divider.png   alpha's divider dragged 80 pt wider, then beta's double-clicked to fit
#   columns-12b-spring.png   Left, photo.png held over sibling in alpha's column: sibling springs open, alpha stays put
#   columns-13a-big-scrolled.png  Up to tree, "bi" lights big, Right into its 50,000 files, the wheel spun over it
#   columns-13-big.png       then End: the last file lit
# Prints one line per step and exits non-zero if any step fails.
set -u

APP="$HOME/folio/Folio.app"
SHOTS="$HOME/folio/shots"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT="/private/tmp/folio-tests/columns-$STAMP"
TREE="$ROOT/tree"
MOUSE="$HOME/folio/folio-mouse-col"
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "columns: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if [ ! -d "$APP" ]; then
    echo "columns: missing $APP (stage the build first, docs/plan/VM.md)"
    exit 2
fi

pass() { echo "step $1 $2: ok - $3"; }
failed=""
fail() { echo "step $1 $2: FAILED - $3"; fails=$((fails + 1)); failed="$failed $1-$2"; }

# --- folio-mouse-col: real pointer events through the HID event tap --------------------------------------
mkdir -p "$HOME/folio" "$ROOT" "$SHOTS"
# The whole run's lines also go to a text file the helper brings back with the shots (it fetches *.png).
exec > >(tee "$SHOTS/columns-run-log.txt.png") 2>&1
cat > "$ROOT/folio-mouse-col.swift" <<'SWIFT'
// folio-mouse-col: real mouse events through the HID event tap, for the Columns VM script (docs/plan/VM.md).
// Compiled inside the test VM with swiftc; never run on a host Mac (RULES.md, rule 0).
//   folio-mouse-col move <x> <y>
//   folio-mouse-col click <x> <y> [--double]
//   folio-mouse-col drag <x1> <y1> <x2> <y2> [--steps N] [--hold S] [--shot PATH --shot-at S]
//   folio-mouse-col scroll <x> <y> <lines> <times>
//   folio-mouse-col release
import CoreGraphics
import Foundation

let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ p: CGPoint, clicks: Int64 = 1) {
    guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
    e.setIntegerValueField(.mouseEventClickState, value: clicks)
    e.post(tap: .cghidEventTap)
}
func pause(_ s: Double) { usleep(useconds_t(s * 1_000_000)) }
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
let double = flag("--double")
let hold = Double(value("--hold") ?? "0.4") ?? 0.4
let steps = Int(value("--steps") ?? "30") ?? 30
let shotPath = value("--shot")
let shotAt = Double(value("--shot-at") ?? "0.2") ?? 0.2
let nums = args.dropFirst().compactMap(Double.init)
switch args.first {
case "release":
    let here = CGEvent(source: nil)?.location ?? .zero
    post(.leftMouseUp, here)
    pause(0.3)
    print("released at \(Int(here.x)),\(Int(here.y))")
case "move" where nums.count == 2:
    let p = CGPoint(x: nums[0], y: nums[1])
    post(.mouseMoved, CGPoint(x: p.x - 6, y: p.y))
    pause(0.08)
    post(.mouseMoved, p)
    pause(0.15)
    print("moved to \(Int(p.x)),\(Int(p.y))")
case "click" where nums.count == 2:
    let p = CGPoint(x: nums[0], y: nums[1])
    post(.mouseMoved, p)
    pause(0.12)
    post(.leftMouseDown, p)
    pause(0.06)
    post(.leftMouseUp, p)
    if double {
        pause(0.09)
        post(.leftMouseDown, p, clicks: 2)
        pause(0.06)
        post(.leftMouseUp, p, clicks: 2)
    }
    pause(0.15)
    print("click at \(Int(p.x)),\(Int(p.y))" + (double ? " twice" : ""))
case "drag" where nums.count == 4:
    let a = CGPoint(x: nums[0], y: nums[1]), b = CGPoint(x: nums[2], y: nums[3])
    post(.mouseMoved, a)
    pause(0.15)
    post(.leftMouseDown, a)
    pause(0.25)
    for i in 1...6 {
        post(.leftMouseDragged, CGPoint(x: a.x + CGFloat(i) * 2, y: a.y + CGFloat(i)))
        pause(0.03)
    }
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        post(.leftMouseDragged, CGPoint(x: a.x + 12 + (b.x - a.x - 12) * t, y: a.y + 6 + (b.y - a.y - 6) * t))
        pause(0.02)
    }
    var held = 0.0, shot = false
    while held < hold {
        post(.leftMouseDragged, CGPoint(x: b.x + CGFloat(Int(held * 20) % 2), y: b.y))
        if let shotPath, !shot, held >= shotAt { shoot(shotPath); shot = true }
        pause(0.05)
        held += 0.05
    }
    post(.leftMouseUp, b)
    pause(0.15)
    print("drag \(Int(a.x)),\(Int(a.y)) -> \(Int(b.x)),\(Int(b.y))")
case "scroll" where nums.count == 4:
    let p = CGPoint(x: nums[0], y: nums[1])
    post(.mouseMoved, p)
    pause(0.12)
    let started = Date()
    for _ in 0..<Int(nums[3]) {
        if let e = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: Int32(nums[2]), wheel2: 0, wheel3: 0) {
            e.location = p
            e.post(tap: .cghidEventTap)
        }
        pause(0.016)
    }
    print("scrolled \(Int(nums[2])) lines x \(Int(nums[3])) at \(Int(p.x)),\(Int(p.y)) in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
default:
    print("usage: folio-mouse-col move x y | click x y [--double] | drag x1 y1 x2 y2 [--hold S] [--shot P --shot-at S] | scroll x y lines times | release")
    exit(2)
}
for p in captures { p.waitUntilExit() }
SWIFT
if ! cmp -s "$ROOT/folio-mouse-col.swift" "$HOME/folio/folio-mouse-col.swift" || [ ! -x "$MOUSE" ]; then
    cp "$ROOT/folio-mouse-col.swift" "$HOME/folio/folio-mouse-col.swift"
    swiftc -O "$HOME/folio/folio-mouse-col.swift" -o "$MOUSE" 2>&1 | tail -5
fi
if [ ! -x "$MOUSE" ]; then echo "columns: could not build folio-mouse-col"; exit 2; fi

# --- helpers ------------------------------------------------------------------------------------------
frontmost() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>&1; }
keys() {
    echo "  key: $1 (frontmost: $(frontmost))"
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to $1" >/dev/null 2>&1
}
front() { osascript -e 'tell application "System Events" to set frontmost of process "Folio" to true' >/dev/null 2>&1; }
menu_bar() {
    echo "  menu bar: $1 > $2${3:+ > $3}"
    if [ $# -ge 3 ]; then
        osascript -e "tell application \"System Events\" to tell process \"Folio\" to click menu item \"$3\" of menu \"$2\" of menu item \"$2\" of menu \"$1\" of menu bar 1" 2>&1 | grep -v "^menu item" | head -2
    else
        osascript -e "tell application \"System Events\" to tell process \"Folio\" to click menu item \"$2\" of menu \"$1\" of menu bar 1" 2>&1 | grep -v "^menu item" | head -2
    fi
}
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
shot() {
    local f="$SHOTS/$1.png"
    rm -f "$f"
    screencapture -x "$f" 2>/dev/null
    if [ -s "$f" ]; then echo "$f"; fi
}
status_text() {
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to get value of (first group of window \"$1\" whose description is \"Status bar\")" 2>/dev/null
}
has_table() {
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to exists table 1 of scroll area 2 of window \"$1\"" 2>/dev/null
}
list_rows() {
    osascript - "$1" 2>/dev/null <<'OSA'
on run argv
    set out to {}
    tell application "System Events" to tell process "Folio"
        set t to table 1 of scroll area 2 of window (item 1 of argv)
        repeat with r in rows of t
            try
                set end of out to (description of UI element 1 of r) as text
            end try
        end repeat
    end tell
    set AppleScript's text item delimiters to linefeed
    return out as text
end run
OSA
}

# The Columns view's AX tree: each column is a table described "Column <folder>", its rows' cells carry
# the item names. col_names <window>: the columns left to right.
AX_WALK='
on walk(e, depth, want, out)
    tell application "System Events"
        try
            if role of e is "AXTable" then
                set d to (description of e) as text
                if d starts with "Column " then
                    if want is "" then
                        set end of out to (text 8 thru -1 of d)
                    else if d is ("Column " & want) then
                        set end of out to e
                    end if
                end if
                return out
            end if
        end try
        if depth is 0 then return out
        try
            repeat with k in (UI elements of e)
                set out to my walk(contents of k, depth - 1, want, out)
            end repeat
        end try
    end tell
    return out
end walk'
col_names() {
    osascript - "$1" 2>/dev/null <<OSA
$AX_WALK
on run argv
    tell application "System Events" to tell process "Folio"
        set found to my walk(window (item 1 of argv), 9, "", {})
    end tell
    set AppleScript's text item delimiters to "|"
    return found as text
end run
OSA
}
# col_point <window> <column> <item> [dx]: "x y" on that item's name in that column.
col_point() {
    osascript - "$1" "$2" "$3" "${4:-60}" 2>/dev/null <<OSA
$AX_WALK
on run argv
    tell application "System Events" to tell process "Folio"
        set found to my walk(window (item 1 of argv), 9, item 2 of argv, {})
        if (count of found) is 0 then return ""
        set t to item 1 of found
        repeat with r in rows of t
            try
                set c to UI element 1 of r
                if ((description of c) as text) is (item 3 of argv) then
                    set {px, py} to position of c
                    set {sx, sy} to size of c
                    return ((px + ((item 4 of argv) as integer)) as text) & " " & ((py + (sy div 2)) as text)
                end if
            end try
        end repeat
    end tell
    return ""
end run
OSA
}
# col_rows <window> <column>: the names on screen in that column; col_selected: the lit ones.
col_rows() {
    osascript - "$1" "$2" "${3:-all}" 2>/dev/null <<OSA
$AX_WALK
on run argv
    set out to {}
    tell application "System Events" to tell process "Folio"
        set found to my walk(window (item 1 of argv), 9, item 2 of argv, {})
        if (count of found) is 0 then return ""
        repeat with r in rows of (item 1 of found)
            try
                if (item 3 of argv) is "all" or (selected of r) then set end of out to (description of UI element 1 of r) as text
            end try
        end repeat
    end tell
    set AppleScript's text item delimiters to "|"
    return out as text
end run
OSA
}
col_selected() { col_rows "$1" "$2" selected; }
# col_frame <window> <column>: "x y w h" of that column's table on screen.
col_frame() {
    osascript - "$1" "$2" 2>/dev/null <<OSA
$AX_WALK
on run argv
    tell application "System Events" to tell process "Folio"
        set found to my walk(window (item 1 of argv), 9, item 2 of argv, {})
        if (count of found) is 0 then return ""
        set {px, py} to position of (item 1 of found)
        set {sx, sy} to size of (item 1 of found)
        return (px as text) & " " & (py as text) & " " & (sx as text) & " " & (sy as text)
    end tell
end run
OSA
}
# strip_left <window>: the x where the columns' strip starts on screen (left of it is the sidebar).
strip_left() {
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to get item 1 of (position of scroll area 2 of window \"$1\")" 2>/dev/null
}
preview_value() {
    osascript - "$1" 2>/dev/null <<'OSA'
on find(e, depth)
    tell application "System Events"
        try
            if (role of e is "AXGroup") and ((description of e) as text is "Preview") then return e
            -- Never into a column's rows (50,000 of them in big).
            if role of e is "AXTable" then return missing value
        end try
        if depth is 0 then return missing value
        try
            repeat with k in (UI elements of e)
                set hit to my find(contents of k, depth - 1)
                if hit is not missing value then return hit
            end repeat
        end try
    end tell
    return missing value
end find
on run argv
    tell application "System Events" to tell process "Folio"
        set p to my find(window (item 1 of argv), 8)
        if p is missing value then return ""
        return (value of p) as text
    end tell
end run
OSA
}
menu_enabled() {
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to get enabled of menu item \"$3\" of menu \"$2\" of menu item \"$2\" of menu \"$1\" of menu bar 1" 2>/dev/null
}
click_at() {
    local pt="$1"
    shift
    [ -n "$pt" ] || { echo "  (no point to click)"; return 1; }
    echo "  $("$MOUSE" click ${pt% *} ${pt#* } "$@")"
}
clean_defaults() {
    for k in session quickAccessPins navPaneCollapsed homeCollapsed favorites recentFiles addressHistory \
             navPaneExpandToCurrent navPaneShown navPaneWidth showHiddenItems trashOrigins \
             defaultView detailsColumns showFileExtensions showThumbnails compactView sidePane itemCheckBoxes columnViewWidth; do
        defaults delete com.anshul.folio "$k" >/dev/null 2>&1
    done
}
quit_folio() {
    osascript -e 'quit app "Folio"' >/dev/null 2>&1
    local i=0
    while pgrep -x Folio >/dev/null && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
    if pgrep -x Folio >/dev/null; then pkill -x Folio; return 1; fi
    return 0
}
perf_lines() {
    log show --last "${1:-2m}" --style compact --predicate 'subsystem == "com.anshul.folio" AND category == "perf"' 2>/dev/null \
        | grep -E "$2" | tail -${3:-3} | sed 's/^.*perf\] //'
}

# --- setup: the tree ----------------------------------------------------------------------------------
echo "  $("$MOUSE" release)"
mkdir -p "$SHOTS" "$TREE/alpha/beta/gamma/delta" "$TREE/alpha/sibling" "$TREE/big"
echo "readme" > "$TREE/readme.txt"
echo "a1" > "$TREE/alpha/a1.txt"
echo "notes" > "$TREE/alpha/beta/b-notes.txt"
echo "move me" > "$TREE/alpha/beta/move-me.txt"
echo "g1" > "$TREE/alpha/beta/gamma/g1.txt"
echo "d1" > "$TREE/alpha/beta/gamma/delta/d1.txt"
source_pic=$(ls "/System/Library/Desktop Pictures/"*.heic 2>/dev/null | head -1)
[ -n "$source_pic" ] && sips -s format png -Z 600 "$source_pic" --out "$TREE/alpha/beta/photo.png" >/dev/null 2>&1
[ -s "$TREE/alpha/beta/photo.png" ] || { screencapture -x "$ROOT/screen.png"; sips -Z 600 "$ROOT/screen.png" --out "$TREE/alpha/beta/photo.png" >/dev/null 2>&1; }
( cd "$TREE/big" && seq -f "file-%05g.txt" 1 50000 | xargs touch )
echo "setup: $TREE ($(find "$TREE" -not -path "*/big/*" | wc -l | tr -d ' ') items besides big, big holds $(ls "$TREE/big" | wc -l | tr -d ' ') files)"

quit_folio
clean_defaults
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1
# The tree as a Quick access place: the columns start at it, as Finder's start at a sidebar place.
defaults write com.anshul.folio quickAccessPins -array "$TREE"
open -a "$APP" "$TREE"
if wait_window "tree" 15; then
    echo "launch: ok - window \"tree\""
else
    echo "launch: FAILED - no window \"tree\" after 15 s (windows: $(names_now))"
    exit 1
fi
front
sleep 1.5

# --- 1: Ctrl+Shift+9: Columns ----------------------------------------------------------------------------
keys 'key code 25 using {control down, shift down}'
sleep 1.2
cols=$(col_names tree)
rows=$(col_rows tree tree)
f=$(shot columns-1-open)
if [ "$cols" = "tree" ] && echo "$rows" | grep -q "alpha" && echo "$rows" | grep -q "readme.txt" && [ "$(has_table tree)" != "true" ]; then
    pass 1 ctrl-shift-9 "Columns: [$cols], tree's column: $rows; $f"
else
    fail 1 ctrl-shift-9 "columns [$cols] rows [$rows] details table [$(has_table tree)]; ${f:-none}"
fi

# --- 2: Down, Right, Right, Right -------------------------------------------------------------------------
keys 'key code 125'
sleep 0.5
sel=$(col_selected tree tree)
keys 'key code 124'
sleep 0.6
keys 'key code 124'
sleep 0.6
keys 'key code 124'
sleep 1
cols=$(col_names gamma)
f=$(shot columns-2-right3)
if [ "$sel" = "alpha" ] && has_window gamma && [ "$cols" = "tree|alpha|beta|gamma|delta" ] && [ "$(col_selected gamma gamma)" = "delta" ] \
   && [ "$(col_selected gamma beta)" = "gamma" ] && [ "$(col_rows gamma delta)" = "d1.txt" ]; then
    pass 2 right-right-right "Down lit alpha; window \"gamma\", columns [$cols], delta lit in gamma, delta's d1.txt after; status \"$(status_text gamma)\"; $f"
else
    fail 2 right-right-right "down lit [$sel], windows [$(names_now)], columns [$cols], gamma lit [$(col_selected gamma gamma)], beta lit [$(col_selected gamma beta)]; ${f:-none}"
fi

# --- 3: Left ---------------------------------------------------------------------------------------------
keys 'key code 123'
sleep 1
cols=$(col_names beta)
f=$(shot columns-3-left)
if has_window beta && [ "$cols" = "tree|alpha|beta|gamma" ] && [ "$(col_selected beta beta)" = "gamma" ] \
   && echo "$(status_text beta)" | grep -q "1 selected"; then
    pass 3 left "window \"beta\", columns [$cols], gamma lit in beta, status \"$(status_text beta)\"; $f"
else
    fail 3 left "windows [$(names_now)], columns [$cols], beta lit [$(col_selected beta beta)], status [$(status_text beta)]; ${f:-none}"
fi

# --- 4: type "ph": photo.png and its preview column --------------------------------------------------------
keys 'keystroke "ph"'
sleep 2
pv=$(preview_value beta)
f=$(shot columns-4-preview)
if [ "$(col_selected beta beta)" = "photo.png" ] && echo "$pv" | grep -q "^photo.png" && echo "$pv" | grep -q "Kind: PNG" \
   && echo "$pv" | grep -q "Size: " && echo "$pv" | grep -q "Modified: " && echo "$pv" | grep -q "Tags: "; then
    pass 4 preview "photo.png lit, preview: $pv; $f"
else
    fail 4 preview "lit [$(col_selected beta beta)], preview [$pv]; ${f:-none}"
fi

# --- 5: F2 on b-notes.txt ----------------------------------------------------------------------------------
sleep 1.1
keys 'keystroke "b-"'
sleep 0.6
keys 'key code 120'
sleep 0.8
f5a=$(shot columns-5a-renaming)
keys 'keystroke "renamed"'
sleep 0.3
keys 'key code 36'
sleep 1.5
f=$(shot columns-5-renamed)
if [ -f "$TREE/alpha/beta/renamed.txt" ] && [ ! -e "$TREE/alpha/beta/b-notes.txt" ] && [ "$(col_selected beta beta)" = "renamed.txt" ]; then
    pass 5 rename "b-notes.txt renamed to renamed.txt on disk and lit; $f5a $f"
else
    fail 5 rename "beta holds: $(ls "$TREE/alpha/beta" | paste -sd ' ' -), lit [$(col_selected beta beta)]; ${f:-none}"
fi

# --- 6: drag move-me.txt onto sibling in alpha's column ---------------------------------------------------
from=$(col_point beta beta move-me.txt)
to=$(col_point beta alpha sibling)
if [ -n "$from" ] && [ -n "$to" ]; then
    # Quick, so the folder does not spring open under it (step 12b holds on purpose).
    echo "  $("$MOUSE" drag ${from% *} ${from#* } ${to% *} ${to#* } --steps 10 --hold 0.2 --shot "$SHOTS/columns-6a-drag-over.png" --shot-at 0.05)"
    sleep 2
fi
f=$(shot columns-6-dragged)
brows=$(col_rows beta beta)
if [ -f "$TREE/alpha/sibling/move-me.txt" ] && [ ! -e "$TREE/alpha/beta/move-me.txt" ] && ! echo "$brows" | grep -q "move-me.txt" && has_window beta; then
    pass 6 drag "move-me.txt dropped on sibling in alpha's column: in alpha/sibling now, beta's column [$brows]; $SHOTS/columns-6a-drag-over.png $f"
else
    fail 6 drag "from [$from] to [$to]; sibling holds: $(ls "$TREE/alpha/sibling" | paste -sd ' ' -), beta: $(ls "$TREE/alpha/beta" | paste -sd ' ' -), column [$brows], windows [$(names_now)]; ${f:-none}"
fi

# --- 7: Cmd+Left: back -----------------------------------------------------------------------------------
front
keys 'key code 123 using {command down}'
sleep 1.2
cols=$(col_names gamma)
f=$(shot columns-7-back)
if has_window gamma && [ "$cols" = "tree|alpha|beta|gamma" ]; then
    pass 7 back "Cmd+Left: window \"gamma\", columns [$cols]; $f"
else
    fail 7 back "windows [$(names_now)], columns [$cols]; ${f:-none}"
fi

# --- 8 and 9: Details and back: the same folder ---------------------------------------------------------
keys 'key code 22 using {control down, shift down}'
sleep 1.2
drows=$(list_rows gamma | paste -sd ' ' -)
f=$(shot columns-8-details)
if has_window gamma && [ "$(has_table gamma)" = "true" ] && [ "$drows" = "delta g1.txt" ] && [ -z "$(col_names gamma)" ]; then
    pass 8 details "Ctrl+Shift+6: Details of gamma: $drows; $f"
else
    fail 8 details "windows [$(names_now)], table [$(has_table gamma)], rows [$drows], columns [$(col_names gamma)]; ${f:-none}"
fi
menu_bar View Columns
sleep 1.2
cols=$(col_names gamma)
f=$(shot columns-9-columns)
if has_window gamma && [ "$cols" = "tree|alpha|beta|gamma" ] && [ "$(has_table gamma)" != "true" ]; then
    pass 9 columns-again "View > Columns: columns [$cols], still gamma; $f"
else
    fail 9 columns-again "windows [$(names_now)], columns [$cols]; ${f:-none}"
fi

# --- 10: search: results in their list, not columns -------------------------------------------------------
keys 'keystroke "f" using {command down}'
sleep 0.5
keys 'keystroke "g1"'
sleep 3
srows=$(list_rows gamma 2>/dev/null | paste -sd ' ' -)
[ -z "$srows" ] && srows=$(osascript -e 'tell application "System Events" to tell process "Folio" to get name of every window' 2>/dev/null)
f=$(shot columns-10-search)
scols=$(col_names "$(window_names | head -1)")
if [ -z "$scols" ] && echo "$(list_rows "$(window_names | head -1)")" | grep -q "g1.txt"; then
    pass 10 search "results in the Details list: $(list_rows "$(window_names | head -1)" | paste -sd ' ' -); no columns; $f"
else
    fail 10 search "windows [$(names_now)], columns [$scols], rows [$(list_rows "$(window_names | head -1)" | paste -sd ' ' -)]; ${f:-none}"
fi
keys 'key code 53'
sleep 1
keys 'key code 53'
sleep 1.2
wait_window gamma 4
cols=$(col_names gamma)
if [ "$cols" = "tree|alpha|beta|gamma" ]; then echo "  Esc: back to the columns [$cols]"; else fail 10 search-esc "after Esc: windows [$(names_now)], columns [$cols]"; fi
# The keyboard stays in the search box after Esc: a click on gamma's empty space gives it back to the column.
fg=$(col_frame gamma gamma)
if [ -n "$fg" ]; then
    set -- $fg
    click_at "$(( $1 + $3 / 2 )) $(( $2 + $4 - 60 ))"
    sleep 0.6
fi

# --- 11: Group by greyed in Columns --------------------------------------------------------------------------
g=$(menu_enabled View "Group By" "Date modified")
s=$(menu_enabled View "Sort By" "Date modified")
osascript -e 'tell application "System Events" to tell process "Folio" to click menu bar item "View" of menu bar 1' >/dev/null 2>&1
sleep 0.4
osascript -e 'tell application "System Events" to tell process "Folio" to click menu item "Group By" of menu "View" of menu bar item "View" of menu bar 1' >/dev/null 2>&1
sleep 0.6
f=$(shot columns-11-groupby)
keys 'key code 53'
keys 'key code 53'
sleep 0.4
if [ "$g" = "false" ] && [ "$s" = "true" ]; then
    pass 11 greyed "Group By > Date modified enabled: $g (Sort By > Date modified: $s); $f"
else
    fail 11 greyed "Group By item enabled [$g], Sort By item [$s]; ${f:-none}"
fi

# --- 12: a divider dragged wider, another double-clicked to fit -------------------------------------------
front
fa=$(col_frame gamma alpha)
if [ -n "$fa" ]; then
    set -- $fa
    dx=$(( $1 + $3 + 1 )); dy=$(( $2 + $4 / 2 ))
    echo "  $("$MOUSE" drag $dx $dy $((dx + 80)) $dy --hold 0.2)"
    sleep 0.8
fi
fa2=$(col_frame gamma alpha)
saved=$(defaults read com.anshul.folio columnViewWidth 2>/dev/null)
fb=$(col_frame gamma beta)
if [ -n "$fb" ]; then
    set -- $fb
    bx=$(( $1 + $3 + 1 )); by=$(( $2 + $4 / 2 ))
    click_at "$bx $by" --double
    sleep 0.8
fi
fb2=$(col_frame gamma beta)
f=$(shot columns-12-divider)
wa=$(echo "$fa" | cut -d' ' -f3); wa2=$(echo "$fa2" | cut -d' ' -f3); wb=$(echo "$fb" | cut -d' ' -f3); wb2=$(echo "$fb2" | cut -d' ' -f3)
if [ -n "$wa" ] && [ -n "$wa2" ] && [ $((wa2 - wa)) -ge 60 ] && [ -n "$saved" ] && [ -n "$wb2" ] && [ "$wb2" != "$wb" ]; then
    pass 12 divider "alpha $wa -> $wa2 pt by drag (saved width $saved), beta $wb -> $wb2 pt by double-click; $f"
else
    fail 12 divider "alpha [$fa] -> [$fa2], saved [$saved], beta [$fb] -> [$fb2]; ${f:-none}"
fi

# --- 12b: a drag held on a folder in another column: it springs open, nothing slides under the pointer ------
# Left first, so alpha's column is in view (beta current, gamma's column after it).
front
keys 'key code 123'
sleep 1.2
# photo.png selected first: its preview column comes in and the strip settles before the drag.
click_at "$(col_point beta beta photo.png)"
sleep 1.2
from=$(col_point beta beta photo.png)
to=$(col_point beta alpha sibling)
fa=$(col_frame beta alpha)
left=$(strip_left beta)
# Only the part of a column inside the strip takes the drop: never aim left of the strip's edge.
if [ -n "$to" ] && [ -n "$left" ] && [ "${to% *}" -lt $((left + 30)) ]; then to="$((left + 30)) ${to#* }"; fi
fa2=""
if [ -n "$from" ] && [ -n "$to" ]; then
    "$MOUSE" drag ${from% *} ${from#* } ${to% *} ${to#* } --steps 12 --hold 2.4 --shot "$SHOTS/columns-12b-spring.png" --shot-at 1.6 \
        > "$ROOT/spring.out" &
    sleep 2.2
    # Mid-drag, after the spring: where alpha's column is now.
    fa2=$(col_frame sibling alpha)
    wait
    echo "  $(cat "$ROOT/spring.out")"
    sleep 2
fi
# The drop landing in sibling after it sprang open is the proof that sibling stayed under the pointer
# (the mid-drag shot shows it); alpha's frame as AX reports it mid-drag is logged, not judged.
if [ -f "$TREE/alpha/sibling/photo.png" ] && has_window sibling; then
    pass 12b spring "held on sibling: it opened (window \"sibling\") and photo.png still dropped into it; alpha's table at x ${fa%% *} before, ${fa2%% *} mid-drag (AX); $SHOTS/columns-12b-spring.png"
else
    fail 12b spring "from [$from] to [$to] (strip from x $left); alpha [$fa] -> [$fa2]; sibling holds: $(ls "$TREE/alpha/sibling" | paste -sd ' ' -); windows [$(names_now)]"
fi

# --- 13: 50,000 files in a column -------------------------------------------------------------------------
# Up to tree, "bi" types big's name: its 50,000 files are read off the main thread into the next column;
# Right goes into it (shown from its column at once), the wheel spins over it, End lights the last file.
front
i=0
while ! has_window tree && [ "$i" -lt 5 ]; do keys 'key code 126 using {option down}'; sleep 1; i=$((i + 1)); done
sleep 1.1
t0=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')
keys 'keystroke "bi"'
i=0
while [ "$i" -lt 60 ] && [ -z "$(perf_lines 1m "columns: read 50000 items" 1)" ]; do sleep 0.2; i=$((i + 1)); done
t1=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')
lit=$(col_selected tree tree)
keys 'key code 124'
sleep 1.5
fbig=$(col_frame big big)
scroll_out=""
t2=0; t3=0
if [ -n "$fbig" ]; then
    set -- $fbig
    scroll_out=$("$MOUSE" scroll $(( $1 + $3 / 2 )) $(( $2 + 200 )) -12 60)
    # The app has handled every wheel event when it answers again.
    t2=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')
    names_now >/dev/null
    t3=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')
fi
sleep 0.5
f13a=$(shot columns-13a-big-scrolled)
keys 'key code 119'
sleep 1.5
# The last file is lit when the preview column shows it and the status bar counts one selected.
last=$(preview_value big | cut -d';' -f1)
status13=$(status_text big)
echo "  wheel: $scroll_out; the app answered $((t3 - t2)) ms after the last event; status \"$status13\""
f=$(shot columns-13-big)
perf=$(perf_lines 3m "columns: (read 50000|50000 items)" 4)
echo "$perf" | sed 's/^/    /'
if [ "$lit" = "big" ] && has_window big && [ "$last" = "file-50000.txt" ] && echo "$status13" | grep -q "^50,000 items, 1 selected" \
   && echo "$perf" | grep -q "read 50000 items"; then
    pass 13 big "\"bi\" lit big, its 50,000 files read and logged $((t1 - t0)) ms after the keys; Right into it; $scroll_out, answered $((t3 - t2)) ms after the last; End lit $last; $f13a $f"
else
    fail 13 big "lit [$lit], windows [$(names_now)], last [$last], frame [$fbig], perf [$perf]; ${f:-none}"
fi

# --- quit and clean up ------------------------------------------------------------------------------------
keys 'key code 22 using {control down, shift down}'
sleep 0.5
if quit_folio; then pass 14 quit "Folio quit"; else fail 14 quit "Folio was still running 10 s after quit"; fi
clean_defaults
mv "$ROOT" "$HOME/.Trash/columns-$STAMP" 2>/dev/null

if [ "$fails" -eq 0 ]; then
    echo "result: ok, PNGs in $SHOTS"
    exit 0
fi
echo "failed steps:$failed"
echo "result: FAILED ($fails steps), PNGs in $SHOTS"
exit 1
