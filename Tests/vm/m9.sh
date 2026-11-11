#!/bin/bash
# Milestone 9 GUI check: ff launches Folio on a folder, --reveal selects a file, -t opens a second tab,
# --search runs a search; two windows with tabs, a sort by Size, a selection, a folded sidebar section, an
# opened tree folder and the orange accent (hue 55, picked in the title bar's accent popover) all come back
# after quit and relaunch; a garbage session file is
# moved aside and the app starts on Home; Open folders in Folio instead of Finder reports what macOS kept,
# then `open <folder>` from the shell shows which app macOS used; Open "Show in Finder" from other apps in
# Folio (NSFileViewer) on and off, with another process's reveal going to Folio, then to Finder; the Dock
# icon; Keep running when the last window closes, and Cmd+, with no window; Launch at login;
# `Folio --version`; ff's mistakes.
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Needs ~/folio/Folio.app and ~/folio/ff (copied in from .build/release/ff). Makes
# /private/tmp/folio-tests/m9-<stamp>/{work,other}; drives the app with real events (System Events keys,
# folio-mouse6 clicks). PNGs go to ~/folio/shots/:
#   m9-1-ff-launch.png        ff <work> with Folio not running: Folio starts on work
#   m9-2-reveal.png           ff --reveal work/bert-notes.txt: the same tab, the file selected
#   m9-3-new-tab.png          ff -t other: a second tab, shown
#   m9-4-search.png           ff --search "bert" (run in work): Search Results in work: bert-notes.txt, Bertie.md
#   m9-5-before-quit.png      two windows: [search, other sorted by Size, mid.bin selected] and
#                             [docs, work with the tree open at docs], Network folded, accent orange (55)
#   m9-6-restored.png         quit, open -b com.anshul.folio: the front window as it was
#   m9-6b-restored-other.png  the other window raised: its tabs, sort and selection
#   m9-7-corrupt-home.png     `echo garbage > session.json`, relaunch: Home, no crash, the file moved aside
#   m9-8a-options-general.png View > Options > General: Folio and macOS, before the click
#   m9-8-default-handler.png  Options > General > Open folders in Folio instead of Finder: what macOS kept
#   m9-9-open-folder.png      `open <work>` from the shell: the app macOS chose
#   m9-9b-reveal-box.png      Options > General: Open "Show in Finder" from other apps in Folio, ticked
#   m9-9c-reveal-in-folio.png another process's NSWorkspace reveal of revealed/shown.txt: Folio, the file selected
#   m9-9d-textedit-path.png   TextEdit's title path menu, its parent folder picked: which app showed it
#   m9-9e-reveal-in-finder.png the box off again: the same reveal goes to Finder
#   m9-10-dock.png            the Dock, Folio's icon in it
#   m9-10b-dock-icon.png      Folio's Dock tile close up (light on a light Mac, dark on a dark one)
#   m9-11b-settings-no-window.png  every window closed, Cmd+,: Folder Options
# Prints one line per step and exits non-zero if any step fails.
set -u

APP="$HOME/folio/Folio.app"
FF="$HOME/folio/ff"
SHOTS="$HOME/folio/shots"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT="/private/tmp/folio-tests/m9-$STAMP"
WORK="$ROOT/work"
OTHER="$ROOT/other"
MOUSE="$HOME/folio/folio-mouse6"
LSH="$HOME/folio/folio-lshandler"
REVEAL="$HOME/folio/folio-reveal"
REVEALED="$ROOT/revealed"
REVEAL_BOX="Open “Show in Finder” from other apps in Folio"
SESSION="$HOME/Library/Application Support/Folio/session.json"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
SW="Search Results in work"
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "m9: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if [ ! -d "$APP" ] || [ ! -f "$FF" ]; then
    echo "m9: missing $APP or $FF (stage the build and ff first, docs/plan/VM.md)"
    exit 2
fi
chmod +x "$FF"

pass() { echo "step $1 $2: ok - $3"; }
fail() { echo "step $1 $2: FAILED - $3"; fails=$((fails + 1)); }

# --- folio-mouse6 (as m6.sh to m8.sh build it) and folio-lshandler --------------------------------------------
mkdir -p "$HOME/folio" "$ROOT"
cat > "$ROOT/folio-mouse6.swift" <<'SWIFT'
// folio-mouse6: real mouse events through the HID event tap, for the VM scripts (docs/plan/VM.md).
// Compiled inside the test VM with swiftc; never run on a host Mac (RULES.md, rule 0).
//   folio-mouse6 move <x> <y>
//   folio-mouse6 click <x> <y> [--right | --middle] [--shift] [--option] [--double]
//   folio-mouse6 scroll <x> <y> <lines> [--command]
//   folio-mouse6 release
import CoreGraphics
import Foundation

let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ p: CGPoint, _ button: CGMouseButton, _ flags: CGEventFlags = [], clicks: Int64 = 1) {
    guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
    e.flags = flags
    e.setIntegerValueField(.mouseEventClickState, value: clicks)
    if button == .center { e.setIntegerValueField(.mouseEventButtonNumber, value: 2) }
    e.post(tap: .cghidEventTap)
}
var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}
let right = flag("--right"), middle = flag("--middle"), shift = flag("--shift"), option = flag("--option")
let command = flag("--command"), double = flag("--double")
var flags: CGEventFlags = []
if shift { flags.insert(.maskShift) }
if option { flags.insert(.maskAlternate) }
if command { flags.insert(.maskCommand) }
let nums = args.dropFirst().compactMap(Double.init)
switch args.first {
case "release":
    let here = CGEvent(source: nil)?.location ?? .zero
    post(.leftMouseUp, here, .left)
    usleep(300_000)
    print("released at \(Int(here.x)),\(Int(here.y))")
case "move" where nums.count == 2:
    let p = CGPoint(x: nums[0], y: nums[1])
    // Two steps, so the window sees the pointer arrive (tracking areas want a move inside them).
    post(.mouseMoved, CGPoint(x: p.x - 6, y: p.y), .left)
    usleep(80_000)
    post(.mouseMoved, p, .left)
    usleep(150_000)
    print("moved to \(Int(p.x)),\(Int(p.y))")
case "scroll" where nums.count == 3:
    let p = CGPoint(x: nums[0], y: nums[1])
    post(.mouseMoved, p, .left)
    usleep(120_000)
    if let e = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: Int32(nums[2]), wheel2: 0, wheel3: 0) {
        e.location = p
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }
    usleep(250_000)
    print("scrolled \(Int(nums[2])) at \(Int(p.x)),\(Int(p.y))" + (command ? " with Command" : ""))
case "click" where nums.count == 2:
    let p = CGPoint(x: nums[0], y: nums[1])
    let button: CGMouseButton = right ? .right : middle ? .center : .left
    let (down, up): (CGEventType, CGEventType) = right ? (.rightMouseDown, .rightMouseUp)
        : middle ? (.otherMouseDown, .otherMouseUp) : (.leftMouseDown, .leftMouseUp)
    post(.mouseMoved, p, .left)
    usleep(120_000)
    post(down, p, button, flags)
    usleep(60_000)
    post(up, p, button, flags)
    if double {
        usleep(90_000)
        post(down, p, button, flags, clicks: 2)
        usleep(60_000)
        post(up, p, button, flags, clicks: 2)
    }
    usleep(150_000)
    print("click at \(Int(p.x)),\(Int(p.y))" + (right ? " (right)" : "") + (shift ? " with Shift" : "") + (double ? " twice" : ""))
default:
    print("usage: folio-mouse6 move x y | click x y [--right|--middle] [--shift] [--option] [--double] | scroll x y lines [--command] | release")
    exit(2)
}
SWIFT
if ! cmp -s "$ROOT/folio-mouse6.swift" "$HOME/folio/folio-mouse6.swift" || [ ! -x "$MOUSE" ]; then
    cp "$ROOT/folio-mouse6.swift" "$HOME/folio/folio-mouse6.swift"
    swiftc -O "$HOME/folio/folio-mouse6.swift" -o "$MOUSE" 2>&1 | tail -5
fi
if [ ! -x "$MOUSE" ]; then echo "m9: could not build folio-mouse6"; exit 2; fi

# folio-lshandler: reads (and resets) Launch Services' default app for a content type, independently of Folio.
cat > "$ROOT/folio-lshandler.swift" <<'SWIFT'
// folio-lshandler get <uti> | set <uti> <bundle id>   (VM only, docs/plan/VM.md)
import CoreServices
import Foundation
let a = CommandLine.arguments
if a.count == 3, a[1] == "get" {
    print(LSCopyDefaultRoleHandlerForContentType(a[2] as CFString, .all)?.takeRetainedValue() as String? ?? "none")
} else if a.count == 4, a[1] == "set" {
    print("status \(LSSetDefaultRoleHandlerForContentType(a[2] as CFString, .all, a[3] as CFString))")
} else {
    print("usage: folio-lshandler get <uti> | set <uti> <bundle id>")
    exit(2)
}
SWIFT
if ! cmp -s "$ROOT/folio-lshandler.swift" "$HOME/folio/folio-lshandler.swift" || [ ! -x "$LSH" ]; then
    cp "$ROOT/folio-lshandler.swift" "$HOME/folio/folio-lshandler.swift"
    swiftc -O "$HOME/folio/folio-lshandler.swift" -o "$LSH" 2>&1 | grep -v deprecated | tail -5
fi
if [ ! -x "$LSH" ]; then echo "m9: could not build folio-lshandler"; exit 2; fi

# folio-reveal: another app's "Show in Finder" (NSWorkspace, which follows NSFileViewer), from its own
# process; and a Command-click, for a window title's path menu.
cat > "$ROOT/folio-reveal.swift" <<'SWIFT'
// folio-reveal <path> | cmdclick <x> <y>   (VM only, docs/plan/VM.md)
import AppKit
let a = CommandLine.arguments
if a.count == 2 {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: a[1])])
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
    print("asked NSWorkspace to reveal \(a[1]) (NSFileViewer: \(UserDefaults.standard.string(forKey: "NSFileViewer") ?? "none"))")
} else if a.count == 4, a[1] == "cmdclick", let x = Double(a[2]), let y = Double(a[3]) {
    let source = CGEventSource(stateID: .hidSystemState)
    let p = CGPoint(x: x, y: y)
    for (type, flags) in [(CGEventType.mouseMoved, CGEventFlags()), (.leftMouseDown, .maskCommand), (.leftMouseUp, .maskCommand)] {
        let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
        usleep(120_000)
    }
    print("command-click at \(Int(x)),\(Int(y))")
} else {
    print("usage: folio-reveal <path> | cmdclick <x> <y>")
    exit(2)
}
SWIFT
if ! cmp -s "$ROOT/folio-reveal.swift" "$HOME/folio/folio-reveal.swift" || [ ! -x "$REVEAL" ]; then
    cp "$ROOT/folio-reveal.swift" "$HOME/folio/folio-reveal.swift"
    swiftc -O "$HOME/folio/folio-reveal.swift" -o "$REVEAL" 2>&1 | tail -5
fi
if [ ! -x "$REVEAL" ]; then echo "m9: could not build folio-reveal"; exit 2; fi

# --- helpers ------------------------------------------------------------------------------------------
frontmost() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>&1; }

keys() {
    echo "  key: $1 (frontmost: $(frontmost))"
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to $1" >/dev/null 2>&1
}

front() { osascript -e 'tell application "System Events" to set frontmost of process "Folio" to true' >/dev/null 2>&1; }

raise() { osascript -e "tell application \"System Events\" to tell process \"Folio\" to perform action \"AXRaise\" of window \"$1\"" >/dev/null 2>&1; }

# menu_bar <menu> <item> [<sub item>]: picks an item from the menu bar, as a person would.
menu_bar() {
    echo "  menu bar: $1 > $2${3:+ > $3}"
    if [ $# -ge 3 ]; then
        osascript -e "tell application \"System Events\" to tell process \"Folio\" to click menu item \"$3\" of menu \"$2\" of menu item \"$2\" of menu \"$1\" of menu bar 1" 2>&1 | grep -v "^menu item" | head -2
    else
        osascript -e "tell application \"System Events\" to tell process \"Folio\" to click menu item \"$2\" of menu \"$1\" of menu bar 1" 2>&1 | grep -v "^menu item" | head -2
    fi
}

# menu_mark <menu> <item>: the tick on a menu item ("on" or "off"), read with the menu open (AppKit
# validates the items, which sets the tick, when the menu opens), then Esc.
menu_mark() {
    local m
    m=$(osascript -e "tell application \"System Events\" to tell process \"Folio\"" \
                  -e "click menu bar item \"$1\" of menu bar 1" -e "delay 0.5" \
                  -e "get value of attribute \"AXMenuItemMarkChar\" of menu item \"$2\" of menu \"$1\" of menu bar item \"$1\" of menu bar 1" \
                  -e "end tell" 2>/dev/null)
    osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1
    sleep 0.3
    if [ -n "$m" ] && [ "$m" != "missing value" ]; then echo on; else echo off; fi
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

# The pointer out of the way (no tooltips in the shots): the empty middle of the menu bar.
park() { "$MOUSE" move 700 11 >/dev/null; }

# macOS banners (a Login Item Added left from step 12 of an earlier run) off the screen.
clear_banners() { killall NotificationCenter >/dev/null 2>&1; sleep 1; }

shot() {
    local f="$SHOTS/$1.png"
    rm -f "$f"
    park
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

# list_rows <window>: the Details table's rows (an item's name), in order.
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
rows_line() { list_rows "$1" | paste -sd ' ' -; }
sorted_rows() { list_rows "$1" | LC_ALL=C sort | paste -sd ' ' -; }

# selected_rows <window>: the names on the selected rows.
selected_rows() {
    osascript - "$1" 2>/dev/null <<'OSA'
on run argv
    set out to {}
    tell application "System Events" to tell process "Folio"
        set t to table 1 of scroll area 2 of window (item 1 of argv)
        repeat with r in rows of t
            try
                if selected of r then set end of out to (description of UI element 1 of r) as text
            end try
        end repeat
    end tell
    set AppleScript's text item delimiters to " "
    return out as text
end run
OSA
}

wait_row() {
    local i=0 n=$(( ${3:-10} * 4 ))
    while [ "$i" -lt "$n" ]; do
        list_rows "$1" | grep -Fxq "$2" && return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}

# list_point <window> <name>: "x y" on a Details row's name.
list_point() {
    osascript - "$1" "$2" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        set t to table 1 of scroll area 2 of window (item 1 of argv)
        repeat with r in rows of t
            try
                set c to UI element 1 of r
                if ((description of c) as text) is (item 2 of argv) then
                    set {px, py} to position of c
                    set {sx, sy} to size of c
                    return ((px + 70) as text) & " " & ((py + (sy div 2)) as text)
                end if
            end try
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
            try
                set end of out to (description of UI element 1 of r) as text
            end try
        end repeat
    end tell
    set AppleScript's text item delimiters to "|"
    return out as text
end run
OSA
}

# tree_point <window> <name>: "x y" in the middle of the first tree row with that name (scrolled to).
tree_point() {
    osascript - "$1" "$2" 2>/dev/null <<'OSA'
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
                        set newV to v + ((py - sy) - (sh div 3)) / (total - sh)
                        if newV < 0 then set newV to 0
                        if newV > 1 then set newV to 1
                        set value of scroll bar 1 of s to newV
                        delay 0.4
                        set {px, py} to position of r
                    end try
                end if
                return ((px + 60) as text) & " " & ((py + (rh div 2)) as text)
            end if
        end repeat
    end tell
    return ""
end run
OSA
}

# ax_find <AXRole> <description> <window> [value]: "x y" (middle) of the first match, ten levels deep.
ax_find() {
    osascript - "$@" 2>/dev/null <<'OSA'
on find(e, wantRole, wantDesc, depth)
    tell application "System Events"
        set r to ""
        try
            set r to role of e
        end try
        try
            if (r is wantRole) and ((description of e) as text is wantDesc) then return e
        end try
        if depth is 0 or r is "AXTable" or r is "AXOutline" then return missing value
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
        set found to my find(window (item 3 of argv), item 1 of argv, item 2 of argv, 10)
        if found is missing value then return ""
        if (count of argv) > 3 and item 4 of argv is "value" then
            try
                return (value of found) as text
            on error
                return ""
            end try
        end if
        set {px, py} to position of found
        set {sx, sy} to size of found
        return ((px + (sx div 2)) as text) & " " & ((py + (sy div 2)) as text)
    end tell
end run
OSA
}

# ax_find_any <AXRole> <description>: "x y" of the first match in any Folio window (the accent popover
# hangs off the window it belongs to).
ax_find_any() {
    local w pt
    while read -r w; do
        [ -n "$w" ] || continue
        pt=$(ax_find "$1" "$2" "$w")
        [ -n "$pt" ] && { echo "$pt"; return 0; }
    done < <(window_names)
    osascript - "$1" "$2" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        repeat with w in windows
            try
                set e to (first UI element of (entire contents of w) whose role is (item 1 of argv) and description is (item 2 of argv))
                set {px, py} to position of e
                set {sx, sy} to size of e
                return ((px + (sx div 2)) as text) & " " & ((py + (sy div 2)) as text)
            end try
        end repeat
    end tell
    return ""
end run
OSA
}

click_at() {
    local pt="$1"
    shift
    [ -n "$pt" ] || { echo "  (no point to click)"; return 1; }
    echo "  $("$MOUSE" click ${pt% *} ${pt#* } "$@")"
}

# The keys milestones 2 to 9 keep in the app's defaults, so each run starts from Explorer's defaults.
clean_defaults() {
    for k in session quickAccessPins navPaneCollapsed homeCollapsed favorites recentFiles addressHistory \
             navPaneExpandToCurrent navPaneShown navPaneWidth showHiddenItems trashOrigins accent accentHue \
             defaultView detailsColumns showFileExtensions showThumbnails compactView sidePane itemCheckBoxes \
             searchFileContents searchSystemFiles searchRecentDropdown recentSearches searchBoxWidth \
             openFolioTo browseFoldersOwnWindow singleClickOpen singleClickUnderline showRecentFiles showFrequentFolders \
             fileIconOnThumbnails folderTipSizes fullPathInTitle hideEmptyDrives hideFolderMergeConflicts hideProtectedFiles \
             showDriveLetters showCompressedInColour showInfoTips showPreviewHandlers showStatusBar typeIntoSearch confirmDelete \
             navPaneShowAllFolders navPaneShowNetwork navPaneShowThisPC searchDontUseIndex searchZippedFolders \
             externalFoldersInNewTab reopenWindows keepRunningWithoutWindows; do
        defaults delete com.anshul.folio "$k" >/dev/null 2>&1
    done
}

# The session file out of the way (into the run's folder, which goes to the Trash at the end).
clear_session() {
    local d
    d="$(dirname "$SESSION")"
    mkdir -p "$ROOT/old-sessions"
    for f in "$d"/session*.json; do [ -e "$f" ] && mv "$f" "$ROOT/old-sessions/" 2>/dev/null; done
}

quit_folio() {
    osascript -e 'quit app "Folio"' >/dev/null 2>&1
    local i=0
    while pgrep -x Folio >/dev/null && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
    if pgrep -x Folio >/dev/null; then pkill -x Folio; return 1; fi
    return 0
}

# session_summary: the session file read back (python3 parses the JSON).
session_summary() {
    /usr/bin/python3 - "$SESSION" <<'PY' 2>&1
import json, sys
s = json.load(open(sys.argv[1]))
out = []
for w in s["windows"]:
    tabs = []
    for t in w["tabs"]:
        name = t["path"].rstrip("/").split("/")[-1] or "/"
        extra = []
        if t.get("search"): extra.append("search=" + t["search"]["text"])
        if t["sortKey"] != "name": extra.append("sort=" + t["sortKey"] + ("+" if t["ascending"] else "-"))
        if t.get("selection"): extra.append("sel=" + ",".join(p.split("/")[-1] for p in t["selection"]))
        tabs.append(name + ("[" + " ".join(extra) + "]" if extra else ""))
    tree = [p.split("/")[-1] or "/" for p in (w.get("expandedFolders") or [])]
    out.append("window(%s active=%d display=%s tree=%s)" % (" | ".join(tabs), w["active"], (w.get("display") or {}).get("name"), ",".join(tree)))
print("; ".join(out) + "; view=" + str(s.get("viewMode")))
PY
}

ffrun() {
    local out rc
    out=$( (cd "${FFDIR:-$WORK}" && "$FF" "$@") 2>&1 ); rc=$?
    echo "  ff $* (in ${FFDIR:-$WORK}): exit $rc${out:+, said: $out}"
    return $rc
}

# --- setup ------------------------------------------------------------------------------------------------
echo "  $("$MOUSE" release)"
mkdir -p "$SHOTS" "$WORK/docs/deep" "$OTHER/zz-folder" "$REVEALED"
printf 'shown\n' > "$REVEALED/shown.txt"
printf 'a note\n' > "$REVEALED/note.txt"
printf 'alpha\n' > "$WORK/alpha.txt"
printf 'notes about bert\n' > "$WORK/bert-notes.txt"
printf '# Bertie\n' > "$WORK/Bertie.md"
printf 'albert\n' > "$WORK/albert.txt"
printf 'deep\n' > "$WORK/docs/deep/inner.txt"
printf 'x' > "$OTHER/tiny.txt"
head -c 51200 /dev/urandom > "$OTHER/mid.bin"
head -c 1048576 /dev/urandom > "$OTHER/huge.bin"
echo "setup: $ROOT"
(cd "$ROOT" && find . -path ./old-sessions -prune -o -print | sed 's#^\./##' | grep -v '^\.$' | grep -v '\.swift$' | while read -r f; do
    echo "  $(stat -f '%z' "$f") $f"
done)

quit_folio
clean_defaults
clear_session
clear_banners
# A new install's state: other apps' reveals go to Finder.
[ "$(defaults read -g NSFileViewer 2>/dev/null)" = "com.anshul.folio" ] && defaults delete -g NSFileViewer
# Folio follows the Mac's light or dark setting (it has no theme of its own): the shots are in dark.
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1
"$LSREGISTER" -f "$APP"
echo "  Launch Services: $("$LSREGISTER" -dump 2>/dev/null | grep -c 'path: *.*Folio.app') Folio.app path(s) known; folders open with $("$LSH" get public.folder)"
echo "  ff: $(ls -l "$FF" | awk '{print $1, $5}') $FF"

# --- 1: ff <work> with Folio not running ---------------------------------------------------------------------
running=$(pgrep -x Folio >/dev/null && echo yes || echo no)
ffrun "$WORK"
if wait_window work 20 && wait_row work alpha.txt 10; then
    sleep 1.5
    front
    f=$(shot m9-1-ff-launch)
    t=$(tabs work)
    if [ "$running" = "no" ] && [ "$(window_count)" -eq 1 ] && [ "$t" = "work=1" ]; then
        pass 1 ff-launch "Folio was not running; ff started it on work: windows [$(names_now)], tabs [$t], rows [$(sorted_rows work)]; $f"
    else
        fail 1 ff-launch "running before [$running], windows [$(names_now)], tabs [$t]; ${f:-none}"
    fi
else
    f=$(shot m9-1-ff-launch)
    fail 1 ff-launch "no window work after 20 s (windows: $(names_now)); ${f:-none}"
    exit 1
fi

# --- 2: ff --reveal work/bert-notes.txt: the same tab, the file selected ---------------------------------------
ffrun --reveal "$WORK/bert-notes.txt"
sleep 1.5
sel=$(selected_rows work)
t=$(tabs work)
f=$(shot m9-2-reveal)
if [ "$sel" = "bert-notes.txt" ] && [ "$t" = "work=1" ]; then
    pass 2 reveal "the tab on work came forward with [$sel] selected (no second tab: [$t]); $f"
else
    fail 2 reveal "selected [$sel], tabs [$t]; ${f:-none}"
fi

# --- 3: ff -t other: a second tab -------------------------------------------------------------------------------
ffrun -t "$OTHER"
if wait_window other 8 && wait_tabs other "work=0|other=1" 6 && wait_row other huge.bin 6; then
    sleep 1
    f=$(shot m9-3-new-tab)
    pass 3 new-tab "tabs [$(tabs other)], rows [$(rows_line other)]; $f"
else
    f=$(shot m9-3-new-tab)
    fail 3 new-tab "windows [$(names_now)], tabs [$(tabs other 2>/dev/null)]; ${f:-none}"
fi

# --- 4: ff --search "bert" in work: the work tab shows the results -----------------------------------------------
ffrun --search "bert"
if wait_window "$SW" 8 && wait_row "$SW" Bertie.md 15; then
    sleep 2
    rows=$(sorted_rows "$SW")
    f=$(shot m9-4-search)
    if [ "$rows" = "Bertie.md bert-notes.txt" ] && [ "$(tabs "$SW")" = "$SW=1|other=0" ]; then
        pass 4 search "word-start matches only (albert.txt left out): [$rows]; tabs [$(tabs "$SW")]; $f"
    else
        fail 4 search "rows [$rows], tabs [$(tabs "$SW")]; ${f:-none}"
    fi
else
    f=$(shot m9-4-search)
    fail 4 search "no results window (windows: $(names_now), rows: $(sorted_rows "$SW" 2>/dev/null)); ${f:-none}"
fi

# --- 5: two windows, a sort, a selection, a tree folder, a folded section, amber ---------------------------------
front
click_at "$(tab_point "$SW" 2)"
wait_window other 5
sleep 1
menu_bar View "Sort By" "Size"
sleep 1.2
order_a=$(rows_line other)
click_at "$(list_point other mid.bin)"
sleep 0.6
sel_a=$(selected_rows other)
echo "  window A (other): rows [$order_a], selected [$sel_a], tabs [$(tabs other)]"

ffrun -n "$WORK/docs"
wait_window docs 8
sleep 1
keys 'keystroke "t" using command down'
sleep 1
keys 'keystroke "l" using command down'
sleep 0.4
keys 'keystroke "a" using command down'
keys "keystroke \"$WORK\""
keys 'key code 36'
wait_window work 6
wait_row work alpha.txt 6
sleep 1
# The tree: Ctrl+Shift+E puts the keys on work; Right opens it (when it is not open yet), Right goes to
# docs (the tree's selection opens the folder, as in Explorer), Right opens docs; Back returns to work and
# docs stays open in the tree.
keys 'keystroke "e" using {control down, shift down}'
sleep 0.8
n=3
tree_rows work | tr '|' '\n' | grep -Fxq docs && n=2
for k in $(seq 1 $n); do keys 'key code 124'; sleep 0.6; done
wait_window docs 5
keys 'key code 123 using option down'
wait_window work 5
sleep 0.8
tree_b=$(tree_rows work)
# Network folds.
click_at "$(tree_point work Network)"
sleep 0.8
# The accent: the title bar's swatch opens its popover; the Orange preset; Esc closes it.
click_at "$(ax_find AXButton "Accent colour" work)"
sleep 1
click_at "$(ax_find_any AXRadioButton Orange)"
sleep 0.6
keys 'key code 53'
sleep 0.6
click_at "$(list_point work alpha.txt)"
sleep 0.8
tabs_b=$(tabs work)
collapsed=$(defaults read com.anshul.folio navPaneCollapsed 2>/dev/null | tr -d ' \n()"')
accent=$(defaults read com.anshul.folio accentHue 2>/dev/null)
echo "  window B (work): tabs [$tabs_b], tree [$tree_b], folded [$collapsed], accent [$accent]"
f=$(shot m9-5-before-quit)
if [ "$(window_count)" -eq 2 ] && [ "$tabs_b" = "docs=0|work=1" ] && [ "$sel_a" = "mid.bin" ] \
   && [ "$order_a" != "zz-folder huge.bin mid.bin tiny.txt" ] && echo "$tree_b" | grep -q "|deep" \
   && echo "$collapsed" | grep -q network && [ "$accent" = "55" ]; then
    pass 5 before-quit "A: other by Size [$order_a] with [$sel_a] selected; B: [$tabs_b], tree open at docs (deep shows), Network folded, amber; $f"
else
    fail 5 before-quit "windows [$(names_now)], A [$order_a] sel [$sel_a], B [$tabs_b] tree [$tree_b] folded [$collapsed] accent [$accent]; ${f:-none}"
fi

# --- 6: quit, relaunch with open -b: every state back ----------------------------------------------------------
if quit_folio; then echo "  quit"; else fail 6 quit "Folio was still running 10 s after quit"; fi
echo "  session file: $(session_summary)"
open -b com.anshul.folio
if wait_windows 2 20 && wait_window work 5 && wait_window other 5; then
    wait_row work alpha.txt 8
    wait_row other mid.bin 8
    sleep 2
    front
    tabs_b2=$(tabs work); tabs_a2=$(tabs other)
    order_a2=$(rows_line other); sel_a2=$(selected_rows other)
    tree_b2=$(tree_rows work)
    collapsed2=$(defaults read com.anshul.folio navPaneCollapsed 2>/dev/null | tr -d ' \n()"')
    accent2=$(defaults read com.anshul.folio accentHue 2>/dev/null)
    tree_point work deep >/dev/null   # scrolls the tree so docs and deep are in the shot
    sleep 0.6
    f=$(shot m9-6-restored)
    raise other
    sleep 1
    f2=$(shot m9-6b-restored-other)
    raise work
    problems=""
    [ "$tabs_b2" = "$tabs_b" ] || problems="$problems B tabs [$tabs_b2];"
    [ "$tabs_a2" = "$SW=0|other=1" ] || problems="$problems A tabs [$tabs_a2];"
    [ "$order_a2" = "$order_a" ] || problems="$problems A order [$order_a2];"
    [ "$sel_a2" = "mid.bin" ] || problems="$problems A selection [$sel_a2];"
    echo "$tree_b2" | grep -q "|deep" || problems="$problems tree [$tree_b2];"
    echo "$tree_b2" | grep -q "Connect to server" && problems="$problems Network open;"
    [ "$accent2" = "55" ] || problems="$problems accent [$accent2];"
    if [ -z "$problems" ]; then
        pass 6 restored "2 windows: A [$tabs_a2] sorted [$order_a2] selected [$sel_a2]; B [$tabs_b2], tree open at docs, Network folded [$collapsed2], accent $accent2; $f $f2"
    else
        fail 6 restored "$problems; ${f:-none} ${f2:-none}"
    fi
else
    f=$(shot m9-6-restored)
    fail 6 restored "after relaunch: windows [$(names_now)]; ${f:-none}"
fi

# --- 7: garbage in the session file: moved aside, Home, no crash -------------------------------------------------
quit_folio
echo garbage > "$SESSION"
open -b com.anshul.folio
if wait_window Home 15; then
    sleep 3
    alive=$(pgrep -x Folio >/dev/null && echo running || echo gone)
    aside=$(ls "$(dirname "$SESSION")"/session.corrupt-*.json 2>/dev/null | tail -1)
    kept=$( [ -n "$aside" ] && cat "$aside")
    f=$(shot m9-7-corrupt-home)
    if [ "$alive" = "running" ] && [ "$(window_count)" -eq 1 ] && [ "$kept" = "garbage" ]; then
        pass 7 corrupt "Folio $alive on [$(names_now)]; the bad file is now $(basename "$aside") [$kept]; $f"
    else
        fail 7 corrupt "Folio $alive, windows [$(names_now)], aside [$aside] holds [$kept]; ${f:-none}"
    fi
else
    f=$(shot m9-7-corrupt-home)
    fail 7 corrupt "no Home window (windows: $(names_now), Folio $(pgrep -x Folio >/dev/null && echo running || echo gone)); ${f:-none}"
fi

# --- 8, 9: Open folders in Folio instead of Finder; then `open <work>` from the shell ------------------------------
front
before_ls="folder=$("$LSH" get public.folder) volume=$("$LSH" get public.volume)"
keys 'keystroke "," using {command down, option down}'
if wait_window "Folder Options" 6; then
    sleep 0.8
    general=$(shot m9-8a-options-general)
    echo "  Folder Options, General (Folio and macOS): $general"
    click_at "$(ax_find AXCheckBox "Open folders in Folio instead of Finder" "Folder Options")"
    i=0
    while [ "$i" -lt 24 ]; do
        [ "$(osascript -e 'tell application "System Events" to tell process "Folio" to exists sheet 1 of window "Folder Options"' 2>/dev/null)" = "true" ] && break
        sleep 0.25; i=$((i + 1))
    done
    sleep 0.6
    said=$(osascript -e 'tell application "System Events" to tell process "Folio" to get value of every static text of sheet 1 of window "Folder Options"' 2>/dev/null | tr '\n' ' ')
    after_ls="folder=$("$LSH" get public.folder) volume=$("$LSH" get public.volume)"
    f=$(shot m9-8-default-handler)
    osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
    sleep 0.8
    box=$(ax_find AXCheckBox "Open folders in Folio instead of Finder" "Folder Options" value)
    if [ -n "$said" ]; then
        pass 8 default-handler "before [$before_ls]; the dialog said [$said]; Launch Services now [$after_ls] (read by folio-lshandler); the box reads [$box]; $f"
    else
        fail 8 default-handler "no report sheet; Launch Services [$after_ls]; ${f:-none}"
    fi
    click_at "$(ax_find AXButton OK "Folder Options")"
    sleep 0.8
else
    after_ls="(not asked)"
    fail 8 default-handler "no Folder Options window (windows: $(names_now))"
fi
finder_before=$(osascript -e 'tell application "System Events" to get name of every window of process "Finder"' 2>/dev/null)
open "$WORK"
sleep 3
fm=$(frontmost)
finder_after=$(osascript -e 'tell application "System Events" to get name of every window of process "Finder"' 2>/dev/null)
folio_tabs=$(tabs work 2>/dev/null)
f=$(shot m9-9-open-folder)
if [ "$fm" = "Folio" ] && has_window work; then
    went="Folio (a tab on work: [$folio_tabs])"
elif echo "$finder_after" | grep -q "work"; then
    went="Finder (window \"work\"; macOS kept Finder for \`open\` of a folder)"
else
    went="unclear: frontmost [$fm], Folio windows [$(names_now)], Finder windows [$finder_after]"
fi
if echo "$went" | grep -q "^unclear"; then
    fail 9 open-folder "$went; ${f:-none}"
else
    pass 9 open-folder "Launch Services [$after_ls]; \`open $WORK\` went to $went; frontmost [$fm]; Finder windows before [$finder_before] after [$finder_after]; $f"
fi
# Leave the VM as it was: Finder for folders, Finder's window closed.
echo "  reset: public.folder $("$LSH" set public.folder com.apple.finder), public.volume $("$LSH" set public.volume com.apple.finder) -> folder=$("$LSH" get public.folder)"
if echo "$finder_after" | grep -q "work"; then
    osascript -e 'tell application "System Events" to tell process "Finder" to set frontmost to true' -e 'delay 0.4' \
              -e 'tell application "System Events" to keystroke "w" using command down' >/dev/null 2>&1
fi
front

# --- 9b to 9e: Open "Show in Finder" from other apps in Folio (NSFileViewer) ------------------------------------
# AppKit sends an app's NSWorkspace reveal to the app NSFileViewer names (Finder when there is none). The box
# writes it at once, as the folders box does; off removes it.
viewer() { defaults read -g NSFileViewer 2>/dev/null || echo none; }
finder_windows() { osascript -e 'tell application "System Events" to get name of every window of process "Finder"' 2>/dev/null; }
reveal_box() {
    keys 'keystroke "," using {command down, option down}'
    wait_window "Folder Options" 6 || return 1
    sleep 0.6
    box_was=$(ax_find AXCheckBox "$REVEAL_BOX" "Folder Options" value)
    viewer_was=$(viewer)
    click_at "$(ax_find AXCheckBox "$REVEAL_BOX" "Folder Options")"
    sleep 0.8
    box_now=$(ax_find AXCheckBox "$REVEAL_BOX" "Folder Options" value)
    viewer_now=$(viewer)
    box_shot=$(shot "$1")
    click_at "$(ax_find AXButton OK "Folder Options")"
    sleep 0.8
}
front
if reveal_box m9-9b-reveal-box && [ "$box_was" = "0" ] && [ "$viewer_was" = "none" ] && [ "$box_now" = "1" ] \
   && [ "$viewer_now" = "com.anshul.folio" ]; then
    pass 9b reveal-box "off on a new install (box [$box_was], NSFileViewer [$viewer_was]); one click: box [$box_now], NSFileViewer [$viewer_now]; $box_shot"
else
    fail 9b reveal-box "before: box [${box_was:-}] NSFileViewer [${viewer_was:-}]; after the click: box [${box_now:-}] NSFileViewer [${viewer_now:-}] (windows: $(names_now))"
fi

said=$("$REVEAL" "$REVEALED/shown.txt")
sleep 2
fm=$(frontmost)
sel=""
wait_window revealed 4 && sleep 0.6 && sel=$(selected_rows revealed)
fw=$(finder_windows)
f=$(shot m9-9c-reveal-in-folio)
if [ "$fm" = "Folio" ] && [ "$sel" = "shown.txt" ] && ! echo "$fw" | grep -q revealed; then
    pass 9c reveal-in-folio "$said; Folio came forward on revealed with [$sel] selected (tabs [$(tabs revealed)]); Finder windows [$fw]; $f"
else
    fail 9c reveal-in-folio "$said; frontmost [$fm], selected [$sel], Folio windows [$(names_now)], Finder windows [$fw]; ${f:-none}"
fi

# Real apps, recorded (not passed or failed): `open -R`, and TextEdit's title path menu (Command-click
# the title, pick the folder above the document).
"$REVEAL" "$OTHER/tiny.txt" >/dev/null 2>&1 && sleep 1.5
front
open -R "$REVEALED/note.txt"
sleep 2
openr="frontmost [$(frontmost)], Folio's revealed tab selects [$(selected_rows revealed)], Finder windows [$(finder_windows)]"
open -a TextEdit "$REVEALED/shown.txt"
te=""
i=0
while [ "$i" -lt 40 ]; do
    te=$(osascript -e 'tell application "System Events" to tell process "TextEdit" to get {position, size} of window "shown.txt"' 2>/dev/null | tr -d ' ')
    [ -n "$te" ] && break
    sleep 0.25; i=$((i + 1))
done
textedit="no TextEdit window"
if [ -n "$te" ]; then
    IFS=, read -r tx ty tw th <<< "$te"
    "$REVEAL" "$OTHER/tiny.txt" >/dev/null 2>&1 && sleep 1.5   # Folio's selection moves away from shown.txt first
    osascript -e 'tell application "System Events" to set frontmost of process "TextEdit" to true' >/dev/null 2>&1
    sleep 0.5
    echo "  $("$REVEAL" cmdclick $((tx + tw / 2)) $((ty + 14)))"
    sleep 1
    osascript -e 'tell application "System Events" to key code 125' -e 'delay 0.2' \
              -e 'tell application "System Events" to key code 125' -e 'delay 0.2' \
              -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
    sleep 2.5
    textedit="frontmost [$(frontmost)], Folio's revealed tab selects [$(selected_rows revealed)], Finder windows [$(finder_windows)]"
    shot m9-9d-textedit-path >/dev/null
    osascript -e 'quit app "TextEdit"' >/dev/null 2>&1
fi
echo "info 9d real-apps: with NSFileViewer [$(viewer)]: open -R revealed/note.txt -> $openr; TextEdit's title path menu, revealed picked -> $textedit"
front

if reveal_box m9-9e-reveal-box-off && [ "$box_now" = "0" ] && [ "$viewer_now" = "none" ]; then
    fw_before=$(finder_windows)
    said=$("$REVEAL" "$REVEALED/shown.txt")
    sleep 2.5
    fm=$(frontmost)
    fw=$(finder_windows)
    f=$(shot m9-9e-reveal-in-finder)
    if [ "$fm" = "Finder" ] && echo "$fw" | grep -q revealed; then
        pass 9e reveal-off "box off: NSFileViewer [$viewer_now]; $said; Finder came forward (windows [$fw], before [$fw_before]); $f"
    else
        fail 9e reveal-off "box off: NSFileViewer [$viewer_now]; frontmost [$fm], Finder windows [$fw]; ${f:-none}"
    fi
    if echo "$fw" | grep -q revealed; then
        osascript -e 'tell application "System Events" to tell process "Finder" to set frontmost to true' -e 'delay 0.4' \
                  -e 'tell application "System Events" to keystroke "w" using command down' >/dev/null 2>&1
    fi
else
    fail 9e reveal-off "box [${box_now:-}], NSFileViewer [${viewer_now:-}] after the second click"
fi
front

# --- 10: the Dock ---------------------------------------------------------------------------------------------
dock=$(osascript -e 'tell application "System Events" to tell process "Dock" to get name of every UI element of list 1' 2>/dev/null)
geom=$(osascript -e 'tell application "System Events" to tell process "Dock" to get {position, size} of list 1' 2>/dev/null | tr -d ' ')
IFS=, read -r dx dy dw dh <<< "$geom"
rm -f "$SHOTS/m9-10-dock.png"
if [ -n "${dh:-}" ]; then
    screencapture -x -R"$dx,$((dy - 10)),$dw,$((dh + 10))" "$SHOTS/m9-10-dock.png" 2>/dev/null
else
    screencapture -x "$SHOTS/m9-10-dock.png" 2>/dev/null
fi
# Folio's own tile, close up.
tile=$(osascript -e 'tell application "System Events" to tell process "Dock" to get {position, size} of UI element "Folio" of list 1' 2>/dev/null | tr -d ' ')
IFS=, read -r tx ty tw th <<< "$tile"
rm -f "$SHOTS/m9-10b-dock-icon.png"
[ -n "${th:-}" ] && screencapture -x -R"$((tx - 8)),$((ty - 8)),$((tw + 16)),$((th + 16))" "$SHOTS/m9-10b-dock-icon.png" 2>/dev/null
icon=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP/Contents/Info.plist" 2>/dev/null)
icns=$(stat -f %z "$APP/Contents/Resources/Folio.icns" 2>/dev/null)
if echo "$dock" | tr ',' '\n' | sed 's/^ *//' | grep -Fxq Folio && [ -s "$SHOTS/m9-10-dock.png" ]; then
    pass 10 dock "Dock items [$dock]; region [$geom]; Folio's tile [$tile]; CFBundleIconFile [$icon], Folio.icns $icns bytes; system appearance [$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)]; $SHOTS/m9-10-dock.png $SHOTS/m9-10b-dock-icon.png"
else
    fail 10 dock "Dock items [$dock], region [$geom]"
fi

# --- 11: Keep running when the last window closes (on by default) ----------------------------------------------------
front
for w in $(window_names | tr ' ' '_'); do
    keys 'keystroke "w" using {command down, shift down}'
    sleep 0.6
done
sleep 2
left=$(window_count)
alive=$(pgrep -x Folio >/dev/null && echo running || echo gone)
# 11b: Cmd+, (Folio > Settings...) with no window open: Folder Options all the same; Esc closes it.
settings="not tried (windows left [$left], Folio $alive)"
if [ "$alive" = "running" ] && [ "$left" -eq 0 ]; then
    front
    keys 'keystroke "," using command down'
    if wait_window "Folder Options" 5; then
        sleep 0.6
        settings="opened Folder Options [$(names_now)], $(shot m9-11b-settings-no-window)"
        keys 'key code 53'
        sleep 1
    else
        settings="no Folder Options window [$(names_now)]"
    fi
fi
open -b com.anshul.folio
if [ "$alive" = "running" ] && [ "$left" -eq 0 ] && wait_window Home 8; then
    pass 11 keep-running "every window closed: Folio still $alive with $left windows; open -b brought a Home window back"
else
    fail 11 keep-running "windows left [$left], Folio $alive, after reopen [$(names_now)]"
fi
if echo "$settings" | grep -q "^opened"; then
    pass 11b settings-no-window "Cmd+, with no window: $settings"
else
    fail 11b settings-no-window "Cmd+, with no window: $settings"
fi

# --- 12: Launch at login, from the Folio menu, and back off ----------------------------------------------------------
front
was=$(menu_mark Folio "Launch at Login")
menu_bar Folio "Launch at Login"
sleep 1.5
alert=$(osascript -e 'tell application "System Events" to tell process "Folio" to get value of every static text of window 1' 2>/dev/null | head -c 300)
now=$(menu_mark Folio "Launch at Login")
if [ "$now" = "on" ]; then
    menu_bar Folio "Launch at Login"
    sleep 1.5
    back=$(menu_mark Folio "Launch at Login")
    if [ "$was" = "off" ] && [ "$back" = "off" ]; then
        pass 12 login-item "Launch at Login: [$was] -> [$now] (SMAppService.mainApp enabled) -> [$back]"
    else
        fail 12 login-item "[$was] -> [$now] -> [$back]"
    fi
    clear_banners
else
    osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
    fail 12 login-item "the tick stayed [$now]; macOS said [$alert]"
fi

# --- 13: Folio --version, and ff's mistakes ----------------------------------------------------------------------
version=$("$APP/Contents/MacOS/Folio" --version 2>&1)
# What make app stamped from the git tags (tools/ci/version.sh): 1.2.3, 1.2.3-4-gabc1234 or 0.0.0-abc1234.
stamped="Folio $(defaults read "$APP/Contents/Info" FolioVersion 2>/dev/null) ($(defaults read "$APP/Contents/Info" FolioGitCommit 2>/dev/null))"
if [ "$version" = "$stamped" ] \
    && echo "$version" | grep -Eq '^Folio [0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)? \([0-9a-f]{7,}\)$'; then
    pass 13 version "Folio --version: $version"
else
    fail 13 version "Folio --version said [$version], Info.plist says [$stamped]"
fi
missing=$( (cd "$WORK" && "$FF" "$ROOT/not-there") 2>&1 ); rc1=$?
both=$( (cd "$WORK" && "$FF" -n -t docs) 2>&1 ); rc2=$?
helpline=$("$FF" -h 2>&1 | head -1); rc3=$?
if [ "$rc1" -eq 1 ] && [ "$rc2" -eq 2 ] && [ "$rc3" -eq 0 ]; then
    pass 14 ff-mistakes "ff <missing>: exit $rc1 [$missing]; ff -n -t: exit $rc2 [$both]; ff -h: [$helpline]"
else
    fail 14 ff-mistakes "exits $rc1 $rc2 $rc3: [$missing] [$both] [$helpline]"
fi

# --- quit and clean up ------------------------------------------------------------------------------------
if quit_folio; then pass 15 quit "Folio quit"; else fail 15 quit "Folio was still running 10 s after quit"; fi
clean_defaults
[ "$(defaults read -g NSFileViewer 2>/dev/null)" = "com.anshul.folio" ] && defaults delete -g NSFileViewer
clear_session
mv "$ROOT" "$HOME/.Trash/" 2>/dev/null
# The proof PNGs go into the repo at 1440 wide (the Dock strip is narrower and stays as it is).
for png in "$SHOTS"/m9-*.png; do
    w=$(sips -g pixelWidth "$png" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    [ "${w:-0}" -gt 1440 ] && sips --resampleWidth 1440 "$png" >/dev/null 2>&1
done

if [ "$fails" -eq 0 ]; then
    echo "result: ok, PNGs in $SHOTS"
    exit 0
fi
echo "result: FAILED ($fails steps), PNGs in $SHOTS"
exit 1
