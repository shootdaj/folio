#!/bin/bash
# Milestone 3 GUI check: selection, copy and paste with the progress window, a conflict and Keep both,
# F2 rename, Delete to the Trash and Cmd+Z.
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Makes /private/tmp/folio-tests/m3-<stamp>/work with 2 folders (dest, drafts) and 6 files (three
# videos of 70, 70 and 60 MB, three small text files), opens ~/folio/Folio.app on it with FOLIO_SLOW_COPY=1
# (the engine copies at 40 MB/s, so the 200 MB copy shows its progress window for about 5 s), drives it
# with System Events and writes PNGs to ~/folio/shots/:
#   m3-1-range.png       click the first file (row 3), Shift+click the third file (row 5): 3 selected
#   m3-2-progress.png    Cmd+C, type .../work/dest into the address bar, Enter, Cmd+V: the copy mid-way
#   m3-2b-paused.png     Pause: the job reads "Copy paused" in amber; then Resume
#   m3-3-conflict.png    Cmd+V again (the sources touched, so they are newer): the conflict card
#   m3-3b-compare.png    Compare: the Newer badges
#   m3-4-keep-both.png   Do this for the next 2 conflicts, Keep both: a-video (1).mov and the rest
#   m3-5-rename.png      click c-video (1).mov, F2, type "renamed", Enter: renamed.mov
#   m3-6-deleted.png     Delete (forward delete): renamed.mov goes to the Trash
#   m3-7-undo.png        Cmd+Z: renamed.mov is back
# Every check reads the list's row names through accessibility. Prints one line per step and exits
# non-zero if any step fails.
set -u

APP="$HOME/folio/Folio.app"
# These scripts check the D4 Obsidian look (View > Theme); the app's default is Native.
defaults write com.anshul.folio lookTheme obsidian
# The VM has no Full Disk Access to give: the launch alert (DiskAccessPrompt) must not hold the run.
defaults write com.anshul.folio diskAccessDismissed -bool true
SHOTS="$HOME/folio/shots"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT="/private/tmp/folio-tests/m3-$STAMP"
WORK="$ROOT/work"
DEST="$WORK/dest"
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "m3: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if [ ! -d "$APP" ]; then
    echo "m3: missing $APP (stage the build first, docs/plan/VM.md)"
    exit 2
fi

pass() { echo "step $1 $2: ok - $3"; }
fail() { echo "step $1 $2: FAILED - $3"; fails=$((fails + 1)); }

frontmost() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>&1; }

keys() {
    echo "  key: $1 (frontmost: $(frontmost))"
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to $1" >/dev/null 2>&1
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

wait_no_window() {
    local i=0 n=$(( ${2:-10} * 4 ))
    while [ "$i" -lt "$n" ]; do
        has_window "$1" || return 0
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

# rows <window>: the list's row names, one per line, read from each row's Name cell.
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
has_row() { rows "$1" | grep -Fxq "$2"; }

# wait_rows <window> <seconds> <name>...: waits until every name is a row.
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

# mouse_click <x> <y> [shift]: a real left click (CoreGraphics events through JXA; System Events'
# "click at" only presses accessibility elements, which a table row is not).
mouse_click() {
    osascript -l JavaScript - "$1" "$2" "${3:-}" 2>&1 <<'JXA'
ObjC.import('CoreGraphics');
function run(argv) {
    var p = $.CGPointMake(parseFloat(argv[0]), parseFloat(argv[1]));
    var shift = argv[2] === 'shift';
    var move = $.CGEventCreateMouseEvent($(), $.kCGEventMouseMoved, p, $.kCGMouseButtonLeft);
    $.CGEventPost($.kCGHIDEventTap, move);
    delay(0.1);
    var down = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseDown, p, $.kCGMouseButtonLeft);
    var up = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseUp, p, $.kCGMouseButtonLeft);
    if (shift) {
        $.CGEventSetFlags(down, $.kCGEventFlagMaskShift);
        $.CGEventSetFlags(up, $.kCGEventFlagMaskShift);
    }
    $.CGEventPost($.kCGHIDEventTap, down);
    delay(0.06);
    $.CGEventPost($.kCGHIDEventTap, up);
    return 'click at ' + argv[0] + ',' + argv[1] + (shift ? ' with Shift' : '');
}
JXA
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

# click_row <window> <name> [shift]: a real click on the row's name, with Shift held for a range.
click_row() {
    local pt
    pt=$(row_point "$1" "$2")
    if [ -z "$pt" ]; then echo "no row $2"; return 1; fi
    mouse_click ${pt% *} ${pt#* } "${3:-}"
}

# ax value|press|exists <AXRole> <description> <window>: the first match, searched four levels deep.
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
        set found to my find(window winName, wantRole, wantDesc, 4)
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

status_text() { ax value AXGroup "Status bar" "$1"; }

# --- setup -----------------------------------------------------------------------------------------
mkdir -p "$SHOTS" "$DEST" "$WORK/drafts"
echo "plan" > "$WORK/drafts/plan.txt"
dd if=/dev/zero of="$WORK/a-video.mov" bs=1m count=70 2>/dev/null
dd if=/dev/zero of="$WORK/b-video.mov" bs=1m count=70 2>/dev/null
dd if=/dev/zero of="$WORK/c-video.mov" bs=1m count=60 2>/dev/null
echo "notes" > "$WORK/notes.txt"
echo "# Report" > "$WORK/report.md"
echo "todo" > "$WORK/todo.txt"
# Older dates on the sources, so the second paste's incoming copies read as newer once touched.
touch -t 202610301412 "$WORK"/*.mov "$WORK"/*.txt "$WORK"/*.md
echo "setup: $WORK with dest, drafts and 6 files (200 MB of video)"

osascript -e 'quit app "Folio"' >/dev/null 2>&1
sleep 1
pkill -x Folio 2>/dev/null
defaults delete com.anshul.folio addressHistory >/dev/null 2>&1
defaults delete com.anshul.folio itemCheckBoxes >/dev/null 2>&1
# Folio follows the Mac's light or dark setting (it has no theme of its own): the shots are in dark.
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1
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

open --env FOLIO_SLOW_COPY=1 -a "$APP" "$WORK"
if wait_window "work" 15 && wait_rows "work" 10 "todo.txt"; then
    echo "launch: ok - window \"work\", rows: $(row_names work)"
else
    echo "launch: FAILED - no window \"work\" with rows after 15 s (windows: $(names_now))"
    exit 1
fi
osascript -e 'tell application "System Events" to set frontmost of process "Folio" to true' >/dev/null 2>&1
sleep 1

# --- 1: click row 3, Shift+click row 5 ---------------------------------------------------------------
echo "  $(click_row work a-video.mov)"
sleep 0.4
echo "  $(click_row work c-video.mov shift)"
sleep 0.8
f=$(shot m3-1-range)
st=$(status_text work)
if [ -n "$f" ] && echo "$st" | grep -q "8 items, 3 selected, 204,800 KB"; then
    pass 1 range "status reads \"$st\", $f"
else
    fail 1 range "status reads \"$st\", expected 3 selected and 204,800 KB, shot: ${f:-none}"
fi

# --- 2: copy, go to dest by typing its path, paste: the progress window mid-copy ----------------------
keys 'keystroke "c" using command down'
sleep 0.3
keys 'keystroke "l" using command down'
sleep 0.6
keys 'keystroke "a" using command down'
sleep 0.2
keys "keystroke \"$DEST\""
sleep 0.6
keys 'key code 36'
if wait_window "dest" 5; then
    sleep 0.8
    keys 'keystroke "v" using command down'
    if wait_window "Progress" 5; then
        sleep 1.3
        f=$(shot m3-2-progress)
        r=$(ax exists AXButton "Pause" Progress)
        if [ -n "$f" ] && [ "$r" = "yes" ]; then
            pass 2 progress "window \"Progress\" up mid-copy with Pause, $f"
        else
            fail 2 progress "Pause button: $r, shot: ${f:-none}"
        fi
        # Pause, look, resume (MILESTONES: the copy paused and resumed in the progress window).
        r=$(ax press AXButton "Pause" Progress)
        sleep 1
        f=$(shot m3-2b-paused)
        p=$(ax exists AXGroup "Copy paused" Progress)
        r2=$(ax press AXButton "Resume" Progress)
        if [ -n "$f" ] && [ "$p" = "yes" ] && [ "$r2" = "pressed" ]; then
            pass 2b pause "Pause $r, the job reads \"Copy paused\", Resume $r2, $f"
        else
            fail 2b pause "Pause: $r, paused title: $p, Resume: $r2, shot: ${f:-none}"
        fi
    else
        shot m3-2-progress >/dev/null
        fail 2 progress "no Progress window after Cmd+V (windows: $(names_now))"
    fi
else
    shot m3-2-progress >/dev/null
    fail 2 progress "typing the path did not open dest (windows: $(names_now))"
fi
if wait_no_window "Progress" 25 && wait_rows dest 10 a-video.mov b-video.mov c-video.mov; then
    echo "  copy done: dest rows $(row_names dest)"
else
    fail 2 copy-done "dest rows: $(row_names dest), windows: $(names_now)"
fi

# --- 3: paste again: three conflicts, the incoming copies newer --------------------------------------
touch "$WORK/a-video.mov" "$WORK/b-video.mov" "$WORK/c-video.mov"
keys 'keystroke "v" using command down'
if wait_window "Progress" 5 && [ "$(ax exists AXButton "Keep both" Progress)" = "yes" ]; then
    sleep 0.8
    f=$(shot m3-3-conflict)
    pass 3 conflict "conflict card with Replace, Skip, Keep both, Compare, $f"
    r=$(ax press AXButton "Compare" Progress)
    sleep 0.6
    f=$(shot m3-3b-compare)
    if [ -n "$f" ]; then pass 3b compare "Compare $r, $f"; else fail 3b compare "no shot"; fi
else
    shot m3-3-conflict >/dev/null
    fail 3 conflict "no conflict card (windows: $(names_now))"
fi

# --- 4: Do this for the next 2 conflicts, Keep both ---------------------------------------------------
r1=$(ax press AXCheckBox "Do this for the next 2 conflicts" Progress)
sleep 0.3
r2=$(ax press AXButton "Keep both" Progress)
echo "  check box: $r1, Keep both: $r2"
if wait_no_window "Progress" 25 && wait_rows dest 10 "a-video (1).mov" "b-video (1).mov" "c-video (1).mov"; then
    sleep 0.8
    f=$(shot m3-4-keep-both)
    pass 4 keep-both "rows $(row_names dest), $f"
else
    shot m3-4-keep-both >/dev/null
    fail 4 keep-both "rows $(row_names dest), windows: $(names_now)"
fi

# --- 5: F2 on one file, type a name, Enter ----------------------------------------------------------
echo "  $(click_row dest "c-video (1).mov")"
sleep 0.4
keys 'key code 120'
sleep 0.6
keys 'keystroke "renamed"'
sleep 0.3
keys 'key code 36'
if wait_rows dest 5 "renamed.mov" && ! has_row dest "c-video (1).mov"; then
    sleep 0.6
    f=$(shot m3-5-rename)
    pass 5 rename "c-video (1).mov is now renamed.mov, $f"
else
    shot m3-5-rename >/dev/null
    fail 5 rename "rows $(row_names dest)"
fi

# --- 6: Delete (forward delete) sends it to the Trash -------------------------------------------------
keys 'key code 117'
i=0
while has_row dest "renamed.mov" && [ "$i" -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
sleep 0.5
f=$(shot m3-6-deleted)
if ! has_row dest "renamed.mov" && [ ! -e "$DEST/renamed.mov" ]; then
    pass 6 delete "renamed.mov left the list and the folder, $f"
else
    fail 6 delete "rows $(row_names dest)"
fi

# --- 7: Cmd+Z brings it back --------------------------------------------------------------------------
keys 'keystroke "z" using command down'
if wait_rows dest 5 "renamed.mov" && [ -e "$DEST/renamed.mov" ]; then
    sleep 0.6
    f=$(shot m3-7-undo)
    pass 7 undo "renamed.mov is back from the Trash, $f"
else
    shot m3-7-undo >/dev/null
    fail 7 undo "rows $(row_names dest)"
fi

# --- quit and clean up ------------------------------------------------------------------------------
osascript -e 'quit app "Folio"' >/dev/null 2>&1
i=0
while pgrep -x Folio >/dev/null && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
if pgrep -x Folio >/dev/null; then
    pkill -x Folio
    fail 8 quit "Folio was still running 10 s after quit"
else
    pass 8 quit "Folio quit"
fi
mv "$ROOT" "$HOME/.Trash/" 2>/dev/null

if [ "$fails" -eq 0 ]; then
    echo "result: ok, PNGs in $SHOTS"
    exit 0
fi
echo "result: FAILED ($fails steps), PNGs in $SHOTS"
exit 1
