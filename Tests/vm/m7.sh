#!/bin/bash
# Milestone 7 GUI check: the search box (Cmd+F, as macOS sees Explorer's Ctrl+F), live results with word-start
# matching, *bert*, kind: and size:, content: with Advanced options > File contents, NOT, Search options >
# Date modified writing AQS into the box, the Current folder switch, Open file location and Back to the
# results, Save search and the Recent searches list, Esc back to the folder, reopening the saved search, and
# a timing run on 20,000 files.
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Makes /private/tmp/folio-tests/m7-<stamp>/work, three levels deep, with files named for the
# matching rules (Bert.txt, Bertie.md, my_bert.log, Albert.txt, report-2024.txt, notes.txt holding "needle in
# the text"), sizes from 18 B to 2 MB, a dot folder with a file, and dates from today to last year; opens
# ~/folio/Folio.app on it and drives it with real events: System Events for keys, folio-mouse6 (CGEvent
# through the HID tap, compiled here with swiftc) for clicks and right-clicks. The VM's Spotlight index is
# off for / and /private/tmp is never indexed, so the live walk has to find everything.
# PNGs go to ~/folio/shots/:
#   m7-1-bert.png              Cmd+F, "bert": Bert.txt, Bertie.md, my_bert.log (not Albert), Folder column,
#                              Search Results in work with its progress line, Search options row
#   m7-2-substring.png         "*bert*": Albert.txt too
#   m7-3-kind-size.png         "kind:document size:tiny": the tiny documents, not the 40 KB report or the picture
#   m7-4-content.png           "content:needle" with Advanced options > File contents on: notes.txt (found by
#                              reading it; nothing with File contents off; the dot folder's file stays out)
#   m7-5-not-report.png        "NOT report": everything but report-2024.txt
#   m7-6-date-today.png        Search options > Date modified > Today: "datemodified:today" written into the box
#   m7-7-current-folder.png    Current folder: only work's own items
#   m7-8-open-location.png     right-click Bertie.md > Open file location: level2 with Bertie.md selected
#   m7-8b-back-to-results.png  Back: the results again, "bert" in the box
#   m7-9-recent-searches.png   right-click empty space > Save search (the sheet, Return), then Cmd+F, Down:
#                              the Recent searches list
#   m7-10-esc-folder.png       Esc, Esc: the plain folder, the box empty
#   m7-11-reopened.png         open the saved bert.foliosearch: a window with the search running again
#   m7-12-timing-progress.png  "a" in 20,000 files: the bar crawling while results stream in
#   m7-13-timing-done.png      the same search finished
# Prints one line per step and exits non-zero if any step fails.
set -u

APP="$HOME/folio/Folio.app"
# These scripts check the D4 Obsidian look (View > Theme); the app's default is Native.
defaults write com.anshul.folio lookTheme obsidian
SHOTS="$HOME/folio/shots"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT="/private/tmp/folio-tests/m7-$STAMP"
WORK="$ROOT/work"
BIG="$ROOT/big"
MOUSE="$HOME/folio/folio-mouse6"
SEARCHES="$HOME/Library/Application Support/Folio/Searches"
SW="Search Results in work"
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "m7: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if [ ! -d "$APP" ]; then
    echo "m7: missing $APP (stage the build first, docs/plan/VM.md)"
    exit 2
fi

pass() { echo "step $1 $2: ok - $3"; }
fail() { echo "step $1 $2: FAILED - $3"; fails=$((fails + 1)); }

# --- folio-mouse6 (the same tool m6.sh builds): real pointer events through the HID event tap ------------
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
if [ ! -x "$MOUSE" ]; then echo "m7: could not build folio-mouse6"; exit 2; fi

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
    sleep 0.5
    osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
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

# list_rows <window>: the Details table's rows (an item's name).
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
sorted_rows() { list_rows "$1" | LC_ALL=C sort | paste -sd ' ' -; }

# row_cells <window> <name>: every cell of that row, joined with |.
row_cells() {
    osascript - "$1" "$2" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        set t to table 1 of scroll area 2 of window (item 1 of argv)
        repeat with r in rows of t
            try
                if ((description of UI element 1 of r) as text) is (item 2 of argv) then
                    set out to {}
                    repeat with c in UI elements of r
                        set end of out to (description of c) as text
                    end repeat
                    set AppleScript's text item delimiters to "|"
                    return out as text
                end if
            end try
        end repeat
    end tell
    return ""
end run
OSA
}

# list_point <window> <name> [dx]: "x y" on a Details row (dx from the row's left edge, default 70).
list_point() {
    osascript - "$1" "$2" "${3:-70}" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        set t to table 1 of scroll area 2 of window (item 1 of argv)
        repeat with r in rows of t
            try
                set c to UI element 1 of r
                if ((description of c) as text) is (item 2 of argv) then
                    set {px, py} to position of c
                    set {sx, sy} to size of c
                    return ((px + ((item 3 of argv) as integer)) as text) & " " & ((py + (sy div 2)) as text)
                end if
            end try
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
        return ((px + (sx div 2)) as text) & " " & ((py + sy - 60) as text)
    end tell
end run
OSA
}

# ax_find <AXRole> <description> <window> [value]: "x y" (middle) of the first match, ten levels deep;
# value returns its value instead.
ax_find() {
    osascript - "$@" 2>/dev/null <<'OSA'
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

# ax_quick <AXRole> <description> <window> [value]: as ax_find, but it never goes into a scroll area, so a
# list of 5,000 results does not slow it down (the address bar, the search box and the options row are outside).
ax_quick() {
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
        if depth is 0 or r is "AXScrollArea" or r is "AXTable" or r is "AXOutline" then return missing value
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

status_text() {
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to get value of (first group of window \"$1\" whose description is \"Status bar\")" 2>/dev/null
}

box_text() { ax_quick AXTextField "Search work" "$1" value; }
progress_state() { ax_quick AXStaticText "$SW" "$SW" value; }

# wait_done [seconds]: until the address bar's search label reads done (after the 300 ms wait has passed).
wait_done() {
    sleep 0.8
    local i=0 n=$(( ${1:-15} * 4 ))
    while [ "$i" -lt "$n" ]; do
        [ "$(progress_state)" = "done" ] && return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}

# search <text>: Cmd+F (selects the box's text), then the query typed as a person would.
search() {
    front
    keys 'keystroke "f" using command down'
    sleep 0.4
    echo "  type: $1"
    osascript -e "tell application \"System Events\" to keystroke \"$1\"" >/dev/null 2>&1
}

click_at() {
    local pt="$1"
    shift
    [ -n "$pt" ] || { echo "  (no point to click)"; return 1; }
    echo "  $("$MOUSE" click ${pt% *} ${pt#* } "$@")"
}

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

clean_defaults() {
    for k in session quickAccessPins navPaneCollapsed homeCollapsed favorites recentFiles addressHistory \
             navPaneExpandToCurrent navPaneShown navPaneWidth showHiddenItems trashOrigins \
             defaultView detailsColumns showFileExtensions showThumbnails compactView sidePane itemCheckBoxes \
             searchFileContents searchSystemFiles searchRecentDropdown recentSearches searchBoxWidth; do
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

stamp_at() { date -v"$1" +%Y%m%d%H%M; }

expect() { echo "$@" | tr ' ' '\n' | LC_ALL=C sort | paste -sd ' ' -; }

# --- setup ------------------------------------------------------------------------------------------------
echo "  $("$MOUSE" release)"
mkdir -p "$SHOTS" "$WORK/level2/level3" "$WORK/.stash"
fill() { head -c "$2" /dev/zero | tr '\0' 'a' > "$1"; }
fill "$WORK/Bert.txt" 120
fill "$WORK/Albert.txt" 300
fill "$WORK/photo.png" 5000
fill "$WORK/big-data.bin" 2000000
fill "$WORK/level2/Bertie.md" 2000
fill "$WORK/level2/my_bert.log" 900
fill "$WORK/level2/level3/report-2024.txt" 40000
printf 'needle in the text\n' > "$WORK/level2/level3/notes.txt"
printf 'a needle in the dot folder\n' > "$WORK/.stash/stashed.txt"
NOW=$(stamp_at -0H); DAY=$(stamp_at -1d); WEEK=$(stamp_at -7d); MONTH=$(stamp_at -1m); YEAR=$(stamp_at -1y)
touch -t "$WEEK" "$WORK/Albert.txt"
touch -t "$DAY" "$WORK/photo.png"
touch -t "$MONTH" "$WORK/big-data.bin" "$WORK/level2/Bertie.md"
touch -t "$YEAR" "$WORK/level2/my_bert.log" "$WORK/level2/level3/report-2024.txt"
touch -t "$NOW" "$WORK/Bert.txt" "$WORK/level2/level3/notes.txt" "$WORK/level2/level3" "$WORK/level2"
mv "$SEARCHES" "$HOME/.Trash/Searches-$STAMP" 2>/dev/null
echo "setup: $WORK"
(cd "$WORK" && find . -print | sed 's#^\./##' | grep -v '^\.$' | while read -r f; do
    echo "  $(stat -f '%z %Sm' -t '%Y-%m-%d' "$f") $f"
done)
echo "  Spotlight on /: $(mdutil -s / 2>&1 | tail -1 | tr -d '\t')"

quit_folio
clean_defaults
# Folio follows the Mac's light or dark setting (it has no theme of its own): the shots are in dark.
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1
open -a "$APP" "$WORK"
if wait_window work 15 && [ -n "$(list_point work Bert.txt)" ]; then
    echo "launch: ok - window \"work\": $(sorted_rows work)"
else
    echo "launch: FAILED - no window \"work\" with rows after 15 s (windows: $(names_now))"
    exit 1
fi
front
sleep 1.2

# --- 1: Cmd+F, "bert" ---------------------------------------------------------------------------------------
want=$(expect Bert.txt Bertie.md my_bert.log)
search bert
if wait_window "$SW" 6 && wait_done 15; then
    sleep 0.6
    rows=$(sorted_rows "$SW")
    cells=$(row_cells "$SW" Bertie.md)
    folder_head=$(ax_find AXButton "Folder header" "$SW")
    opts=$(ax_quick AXButton "Date modified" "$SW")
    box=$(box_text "$SW")
    f=$(shot m7-1-bert)
    # The window shows the folder as /tmp/... (the standard spelling of /private/tmp).
    if [ "$rows" = "$want" ] && echo "$cells" | grep -Fq "level2 (${WORK#/private})" && [ -n "$folder_head" ] && [ -n "$opts" ] && [ "$box" = "bert" ]; then
        pass 1 bert "word-start: [$rows], not Albert; Bertie.md row [$cells]; Folder column, Search options, progress done; $f"
    else
        fail 1 bert "rows [$rows] want [$want]; cells [$cells]; folder header [$folder_head]; options [$opts]; box [$box]; ${f:-none}"
    fi
else
    f=$(shot m7-1-bert)
    fail 1 bert "no \"$SW\" finishing (windows: $(names_now), progress [$(progress_state)]); ${f:-none}"
fi

# --- 2: "*bert*" --------------------------------------------------------------------------------------------
want=$(expect Albert.txt Bert.txt Bertie.md my_bert.log)
search '*bert*'
wait_done 15
sleep 0.5
rows=$(sorted_rows "$SW")
f=$(shot m7-2-substring)
if [ "$rows" = "$want" ]; then pass 2 substring "*bert* adds Albert: [$rows]; $f"; else fail 2 substring "rows [$rows] want [$want]; ${f:-none}"; fi

# --- 3: "kind:document size:tiny" ---------------------------------------------------------------------------
want=$(expect Albert.txt Bert.txt Bertie.md my_bert.log notes.txt)
search 'kind:document size:tiny'
wait_done 15
sleep 0.5
rows=$(sorted_rows "$SW")
f=$(shot m7-3-kind-size)
if [ "$rows" = "$want" ]; then
    pass 3 kind-size "tiny documents: [$rows] (not report-2024.txt at 40 KB, not photo.png); $f"
else
    fail 3 kind-size "rows [$rows] want [$want]; ${f:-none}"
fi

# --- 4: "content:needle", File contents off then on ------------------------------------------------------------
search 'content:needle'
wait_done 15
sleep 0.5
off_rows=$(sorted_rows "$SW")
empty_text=$(ax_quick AXStaticText "Search status" "$SW" value)
echo "  File contents off: rows [$off_rows], empty state [$empty_text]"
click_at "$(ax_quick AXButton "Advanced options" "$SW")"
sleep 0.8
menu_pick "File contents"
sleep 0.4
wait_done 15
sleep 0.6
rows=$(sorted_rows "$SW")
setting=$(defaults read com.anshul.folio searchFileContents 2>/dev/null)
f=$(shot m7-4-content)
if [ -z "$off_rows" ] && [ "$empty_text" = "No items match your search." ] && [ "$rows" = "notes.txt" ] && [ "$setting" = "1" ]; then
    pass 4 content "off: nothing (\"$empty_text\"); File contents on ($setting): [$rows] read by the walk, the dot folder's file left out; $f"
else
    fail 4 content "off [$off_rows] [$empty_text]; on [$rows] want [notes.txt]; setting [$setting]; ${f:-none}"
fi

# --- 5: "NOT report" -------------------------------------------------------------------------------------------
want=$(expect Albert.txt Bert.txt Bertie.md big-data.bin level2 level3 my_bert.log notes.txt photo.png)
search 'NOT report'
wait_done 20
sleep 0.5
rows=$(sorted_rows "$SW")
f=$(shot m7-5-not-report)
if [ "$rows" = "$want" ]; then pass 5 not "everything but report-2024.txt: [$rows]; $f"; else fail 5 not "rows [$rows] want [$want]; ${f:-none}"; fi

# --- 6: Search options > Date modified > Today ---------------------------------------------------------------
want=$(expect Bert.txt level2 level3 notes.txt)
click_at "$(ax_quick AXButton "Date modified" "$SW")"
sleep 0.8
menu_pick "Today"
wait_done 15
sleep 0.6
box=$(box_text "$SW")
chip=$(ax_quick AXButton "Date modified" "$SW" value)
rows=$(sorted_rows "$SW")
f=$(shot m7-6-date-today)
if [ "$box" = "NOT report datemodified:today" ] && [ "$chip" = "today" ] && [ "$rows" = "$want" ]; then
    pass 6 date-today "the box reads [$box], the chip [$chip], rows [$rows]; $f"
else
    fail 6 date-today "box [$box] chip [$chip] rows [$rows] want [$want]; ${f:-none}"
fi

# --- 7: Current folder --------------------------------------------------------------------------------------
want=$(expect Bert.txt level2)
click_at "$(ax_quick AXRadioButton "Current folder" "$SW")"
wait_done 15
sleep 0.6
rows=$(sorted_rows "$SW")
cur=$(ax_quick AXRadioButton "Current folder" "$SW" value)
f=$(shot m7-7-current-folder)
if [ "$rows" = "$want" ] && [ "$cur" = "1" ]; then pass 7 current-folder "only work's own: [$rows]; $f"; else fail 7 current-folder "rows [$rows] want [$want]; switch [$cur]; ${f:-none}"; fi
click_at "$(ax_quick AXRadioButton "All subfolders" "$SW")"
sleep 0.6
# File contents back off for the rest (and the timing run).
click_at "$(ax_quick AXButton "Advanced options" "$SW")"
sleep 0.8
menu_pick "File contents"
sleep 0.5

# --- 8: right-click Bertie.md > Open file location, then Back ------------------------------------------------
search bert
wait_done 15
sleep 0.6
click_at "$(list_point "$SW" Bertie.md)" --right
sleep 0.8
menu_pick "Open file location"
if wait_window level2 6; then
    sleep 1
    st=$(status_text level2)
    box=$(ax_quick AXTextField "Search level2" level2 value)
    f=$(shot m7-8-open-location)
    if echo "$st" | grep -q "1 selected" && [ -n "$(list_point level2 Bertie.md)" ] && [ -z "$box" ]; then
        pass 8 open-location "level2 opened with Bertie.md selected: \"$st\"; the box reads \"Search level2\", empty; $f"
    else
        fail 8 open-location "status [$st]; box [$box]; rows [$(sorted_rows level2)]; ${f:-none}"
    fi
else
    f=$(shot m7-8-open-location)
    fail 8 open-location "no level2 window (windows: $(names_now)); ${f:-none}"
fi
keys 'key code 123 using option down'
if wait_window "$SW" 6 && wait_done 15; then
    sleep 0.6
    rows=$(sorted_rows "$SW")
    box=$(box_text "$SW")
    f=$(shot m7-8b-back-to-results)
    if [ "$rows" = "$(expect Bert.txt Bertie.md my_bert.log)" ] && [ "$box" = "bert" ]; then
        pass 8b back "Back returns to the results with the query: [$box] [$rows]; $f"
    else
        fail 8b back "box [$box] rows [$rows]; ${f:-none}"
    fi
else
    f=$(shot m7-8b-back-to-results)
    fail 8b back "windows: $(names_now); ${f:-none}"
fi

# --- 9: right-click empty space > Save search; Cmd+F, Down: Recent searches ------------------------------------
click_at "$(list_blank "$SW")" --right
sleep 0.8
menu_pick "Save search"
i=0
while [ "$i" -lt 24 ]; do
    [ "$(osascript -e "tell application \"System Events\" to tell process \"Folio\" to exists sheet 1 of window \"$SW\"" 2>/dev/null)" = "true" ] && break
    sleep 0.25; i=$((i + 1))
done
sleep 0.6
osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
SAVED="$SEARCHES/bert.foliosearch"
i=0
while [ ! -s "$SAVED" ] && [ "$i" -lt 24 ]; do sleep 0.25; i=$((i + 1)); done
sleep 0.8
front
keys 'keystroke "f" using command down'
sleep 0.4
keys 'key code 125'
sleep 1
recent=$(defaults read com.anshul.folio recentSearches 2>/dev/null | tr -d '\n ' )
f=$(shot m7-9-recent-searches)
if [ -s "$SAVED" ] && grep -q "<text>bert</text>" "$SAVED" && has_window "Recent searches" && echo "$recent" | grep -q '"bert"\|(bert'; then
    pass 9 save-recent "saved $SAVED ($(wc -c < "$SAVED" | tr -d ' ') bytes, query bert); Recent searches open [$recent]; $f"
else
    fail 9 save-recent "file [$(ls "$SEARCHES" 2>&1 | paste -sd ' ' -)]; recent window $(has_window "Recent searches" && echo yes || echo no) [$recent]; ${f:-none}"
fi
[ -s "$SAVED" ] && sed 's/^/    /' "$SAVED"

# --- 10: Esc, Esc: back to the folder ---------------------------------------------------------------------------
keys 'key code 53'
sleep 0.4
keys 'key code 53'
if wait_window work 6; then
    sleep 1
    rows=$(sorted_rows work)
    box=$(box_text work)
    f=$(shot m7-10-esc-folder)
    want=$(expect Albert.txt Bert.txt big-data.bin level2 photo.png)
    if [ "$rows" = "$want" ] && [ -z "$box" ] && ! has_window "$SW"; then
        pass 10 esc "the folder again: [$rows], the box empty; $f"
    else
        fail 10 esc "rows [$rows] want [$want]; box [$box]; windows $(names_now); ${f:-none}"
    fi
else
    f=$(shot m7-10-esc-folder)
    fail 10 esc "windows: $(names_now); ${f:-none}"
fi

# --- 11: open the saved search: it runs again --------------------------------------------------------------------
open -a "$APP" "$SAVED"
if wait_window "$SW" 8 && wait_done 15; then
    sleep 0.8
    rows=$(sorted_rows "$SW")
    f=$(shot m7-11-reopened)
    if [ "$rows" = "$(expect Bert.txt Bertie.md my_bert.log)" ]; then
        pass 11 reopen "bert.foliosearch reopened as a live search: [$rows]; windows $(names_now); $f"
    else
        fail 11 reopen "rows [$rows]; ${f:-none}"
    fi
    keys 'keystroke "w" using {command down, shift down}'
    sleep 0.8
else
    f=$(shot m7-11-reopened)
    fail 11 reopen "windows: $(names_now); ${f:-none}"
fi

# --- 12: timing: "a" in 20,000 files --------------------------------------------------------------------------------
for d in $(seq -w 1 20); do
    mkdir -p "$BIG/set-$d"
    (cd "$BIG/set-$d" && seq -f "alpha-%04g.txt" 1 250 | xargs touch && seq -f "note-%04g.txt" 251 1000 | xargs touch)
done
files=$(find "$BIG" -type f | wc -l | tr -d ' ')
expected_hits=$(find "$BIG" -name 'alpha-*' | wc -l | tr -d ' ')
echo "  timing tree: $files files, $expected_hits named alpha-*"
front
keys 'keystroke "l" using command down'
sleep 0.4
keys 'keystroke "a" using command down'
osascript -e "tell application \"System Events\" to keystroke \"$BIG\"" >/dev/null 2>&1
keys 'key code 36'
if wait_window big 8; then
    sleep 1.5
    keys 'keystroke "f" using command down'
    sleep 0.4
    t0=$(now)
    osascript -e 'tell application "System Events" to keystroke "a"' >/dev/null 2>&1
    sleep 0.45
    f1=$(shot m7-12-timing-progress)
    mid=$(ax_quick AXStaticText "Search Results in big" "Search Results in big" value)
    i=0
    while [ "$i" -lt 240 ]; do
        [ "$(ax_quick AXStaticText "Search Results in big" "Search Results in big" value)" = "done" ] && break
        sleep 0.25; i=$((i + 1))
    done
    t1=$(now)
    sleep 0.6
    st=$(status_text "Search Results in big")
    f2=$(shot m7-13-timing-done)
    perf=$(log show --last 5m --style compact --predicate 'subsystem == "com.anshul.folio" AND category == "perf"' 2>/dev/null \
        | grep 'search ' | grep '"a"' | tail -2 | sed 's/^.*\] //')
    echo "$perf" | sed 's/^/    /'
    first_ms=$(echo "$perf" | grep 'search done' | sed -n 's/.*first after \([0-9]*\) ms.*/\1/p')
    done_ms=$(echo "$perf" | grep 'search done' | sed -n 's/.* hits in \([0-9]*\) ms.*/\1/p')
    hits=$(echo "$perf" | grep 'search done' | sed -n 's/.*" \([0-9]*\) hits in.*/\1/p')
    wall=$(perl -e "printf '%.2f', $t1 - $t0")
    if [ "$expected_hits" = "5000" ] && echo "$st" | grep -q "^5,000 items" && [ "$hits" = "5000" ] && [ -n "$done_ms" ]; then
        pass 12 timing "\"a\" in $files files: $hits hits; first results ${first_ms} ms, done ${done_ms} ms after the query started (app log); ${wall} s wall from the key press incl. the 300 ms wait; mid-run [$mid]; status [$st]; $f1 $f2"
    else
        fail 12 timing "status [$st] want $expected_hits items; perf [$perf]; mid [$mid]; ${f2:-none}"
    fi
else
    fail 12 timing "no window big (windows: $(names_now))"
fi

# --- quit and clean up ------------------------------------------------------------------------------------
if quit_folio; then pass 13 quit "Folio quit"; else fail 13 quit "Folio was still running 10 s after quit"; fi
clean_defaults
mv "$SEARCHES" "$HOME/.Trash/Searches-$STAMP-run" 2>/dev/null
mv "$ROOT" "$HOME/.Trash/" 2>/dev/null

if [ "$fails" -eq 0 ]; then
    echo "result: ok, PNGs in $SHOTS"
    exit 0
fi
echo "result: FAILED ($fails steps), PNGs in $SHOTS"
exit 1
