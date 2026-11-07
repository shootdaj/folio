#!/bin/bash
# Milestone 6 GUI check: header filters (hover chevron, Size buckets, tokens, status count), Group by with
# a collapsed group, Shift+click sort keys with their badges, the header menu and Choose details, the
# icon views with thumbnails, Tiles, Content, Gallery, Cmd+scroll, the Preview and Details panes, Quick
# Look with the arrow keys, hidden items, and the one global view after a relaunch.
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Makes /private/tmp/folio-tests/m6-<stamp>/work with text files of 0 B, 5 KB, 300 KB and 2 MB,
# a PNG and a JPEG (a system desktop picture through sips), a short .mov (screencapture -V) when it can, three folders,
# dates spread with touch -t over today, last week, last month and last year, and a dot file; opens
# ~/folio/Folio.app on it and drives it with real events: System Events for keys and menus,
# folio-mouse6 (CGEvent through the HID tap, compiled here with swiftc) for hovering, clicks, Shift+clicks,
# right-clicks and Cmd+scroll.
# PNGs go to ~/folio/shots/:
#   m6-1-size-hover.png        the pointer on the Size header: its filter chevron at the right edge
#   m6-2-size-filter.png       the chevron clicked: Size's buckets (Empty, Tiny, Small, Medium, Unspecified)
#   m6-3-filtered.png          Small and Medium ticked: only those files, the token in the address bar,
#                              "N items (filtered from M)" in the status bar, a tick on the Size header
#   m6-4-grouped.png           filter cleared from its token, View > Group By > Date modified: Today, Last week...
#   m6-5-collapsed.png         Last week's chevron clicked: the group folded to its header
#   m6-6-sort-badges.png       grouping off, Date modified clicked, Shift+click Type then Name: badges 1, 2, 3
#   m6-7-header-menu.png       right-click a header: Size column to fit, Size all columns to fit, ticks, More...
#   m6-8-choose-details.png    More...: Choose Details with Dimensions ticked
#   m6-9-dimensions.png        OK: the Dimensions column, read from the pictures
#   m6-10-large-icons.png      View > Large icons: thumbnails of the pictures (and the movie)
#   m6-11-tiles.png            View > Tiles
#   m6-12-content.png          View > Content
#   m6-13-preview-pane.png     the PNG selected, Option+P: the Preview pane
#   m6-14-quick-look.png       Space: Quick Look on the PNG
#   m6-14b-quick-look-next.png Down in Quick Look: the next item, the list selection moved with it
#   m6-15-details-pane.png     Option+Shift+P: the Details pane for the PNG
#   m6-16-hidden.png           Cmd+Shift+.: the dot file shows, faded
#   m6-17-gallery.png          View > Gallery: the strip and the preview
#   m6-18-cmd-scroll.png       Details, then Cmd+scroll up once: List
#   m6-19-relaunch-default.png Large icons made the default, Details picked again, quit and relaunch: the
#                              window opens in Large icons, the one global default, not the last view
#   m6-20-subfolder.png        into Albums: the same view (no folder keeps its own)
# Prints one line per step and exits non-zero if any step fails.
set -u

APP="$HOME/folio/Folio.app"
# These scripts check the D4 Obsidian look (View > Theme); the app's default is Native.
defaults write com.anshul.folio lookTheme obsidian
SHOTS="$HOME/folio/shots"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT="/private/tmp/folio-tests/m6-$STAMP"
WORK="$ROOT/work"
MOUSE="$HOME/folio/folio-mouse6"
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "m6: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if [ ! -d "$APP" ]; then
    echo "m6: missing $APP (stage the build first, docs/plan/VM.md)"
    exit 2
fi

pass() { echo "step $1 $2: ok - $3"; }
fail() { echo "step $1 $2: FAILED - $3"; fails=$((fails + 1)); }

# --- folio-mouse6: real pointer events through the HID event tap -------------------------------------
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
if [ ! -x "$MOUSE" ]; then echo "m6: could not build folio-mouse6"; exit 2; fi

# --- helpers ------------------------------------------------------------------------------------------
frontmost() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>&1; }

keys() {
    echo "  key: $1 (frontmost: $(frontmost))"
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to $1" >/dev/null 2>&1
}

front() { osascript -e 'tell application "System Events" to set frontmost of process "Folio" to true' >/dev/null 2>&1; }

# menu_bar <menu> <item> [<submenu item>]: picks from the menu bar, as a person would.
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

# list_rows <window>: the Details table's rows (an item's name, or a group header's "Today (3)").
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
has_table() {
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to exists table 1 of scroll area 2 of window \"$1\"" 2>/dev/null
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

# ax_find <AXRole> <description> <window> [what]: "x y" (middle) of the first match, ten levels deep;
# what = value returns its value instead.
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

# checkboxes <window>: the titles of its check boxes, joined with |.
checkboxes() {
    osascript - "$1" 2>/dev/null <<'OSA'
on run argv
    set out to {}
    tell application "System Events" to tell process "Folio"
        repeat with c in (every checkbox of window (item 1 of argv))
            set end of out to (title of c) as text
        end repeat
    end tell
    set AppleScript's text item delimiters to "|"
    return out as text
end run
OSA
}
checkbox_point() {
    osascript - "$1" "$2" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        set c to (first checkbox of window (item 1 of argv) whose title is (item 2 of argv))
        set {px, py} to position of c
        set {sx, sy} to size of c
        return ((px + 7) as text) & " " & ((py + (sy div 2)) as text)
    end tell
end run
OSA
}

# sheet_check <title>: "value|x y" (top left) of that check box in the window's sheet, empty when not in view.
sheet_check() {
    osascript - "$1" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        repeat with e in (entire contents of sheet 1 of window "work")
            try
                if role of e is "AXCheckBox" and ((title of e) as text) is (item 1 of argv) then
                    set {px, py} to position of e
                    return ((value of e) as text) & "|" & (px as text) & " " & (py as text)
                end if
            end try
        end repeat
    end tell
    return ""
end run
OSA
}
sheet_boxes() {
    osascript 2>/dev/null <<'OSA'
set out to {}
tell application "System Events" to tell process "Folio"
    repeat with e in (entire contents of sheet 1 of window "work")
        try
            if role of e is "AXCheckBox" then set end of out to ((title of e) as text) & "=" & ((value of e) as text)
        end try
    end repeat
end tell
set AppleScript's text item delimiters to "|"
return out as text
OSA
}

status_text() {
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to get value of (first group of window \"$1\" whose description is \"Status bar\")" 2>/dev/null
}

click_at() {
    local pt="$1"
    shift
    [ -n "$pt" ] || { echo "  (no point to click)"; return 1; }
    echo "  $("$MOUSE" click ${pt% *} ${pt#* } "$@")"
}
move_to() {
    [ -n "$1" ] || { echo "  (no point to move to)"; return 1; }
    echo "  $("$MOUSE" move ${1% *} ${1#* })"
}

clean_defaults() {
    for k in session quickAccessPins navPaneCollapsed homeCollapsed favorites recentFiles addressHistory \
             navPaneExpandToCurrent navPaneShown navPaneWidth showHiddenItems trashOrigins \
             defaultView detailsColumns showFileExtensions showThumbnails compactView sidePane itemCheckBoxes; do
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

# --- setup: the mixed folder ----------------------------------------------------------------------------
echo "  $("$MOUSE" release)"
mkdir -p "$SHOTS" "$WORK/Albums" "$WORK/Backups" "$WORK/Code"
: > "$WORK/empty.txt"
head -c 5000 /dev/zero | tr '\0' 'a' > "$WORK/notes-5k.txt"
head -c 300000 /dev/zero | tr '\0' 'b' > "$WORK/report-300k.txt"
head -c 2000000 /dev/zero | tr '\0' 'c' > "$WORK/data-2mb.txt"
echo "inside" > "$WORK/Albums/inside.txt"
echo "inside" > "$WORK/Backups/inside.txt"
echo "inside" > "$WORK/Code/main.swift"
# Pictures from the system's own desktop pictures (any crash dialog from an earlier run closed first,
# since the movie records the screen).
pkill -x "Problem Reporter" >/dev/null 2>&1
source_pic=$(ls "/System/Library/Desktop Pictures/"*.heic 2>/dev/null | head -1)
if [ -n "$source_pic" ]; then
    sips -s format png -Z 900 "$source_pic" --out "$WORK/photo.png" >/dev/null 2>&1
    sips -s format jpeg -s formatOptions 70 -Z 480 "$source_pic" --out "$WORK/picture.jpg" >/dev/null 2>&1
fi
if [ ! -s "$WORK/photo.png" ]; then
    screencapture -x "$ROOT/screen.png" 2>/dev/null
    sips -Z 900 "$ROOT/screen.png" --out "$WORK/photo.png" >/dev/null 2>&1
    sips -Z 480 -s format jpeg -s formatOptions 70 "$ROOT/screen.png" --out "$WORK/picture.jpg" >/dev/null 2>&1
fi
screencapture -x -V 2 "$WORK/movie.mov" >/dev/null 2>&1
[ -s "$WORK/movie.mov" ] || rm -f "$WORK/movie.mov"
echo "secret" > "$WORK/.hidden-notes"
NOW=$(stamp_at -0H); WEEK=$(stamp_at -7d); MONTH=$(stamp_at -1m); YEAR=$(stamp_at -1y)
touch -t "$NOW" "$WORK/empty.txt" "$WORK/photo.png" "$WORK/Albums" "$WORK/.hidden-notes"
touch -t "$WEEK" "$WORK/notes-5k.txt" "$WORK/picture.jpg" "$WORK/Backups"
touch -t "$MONTH" "$WORK/report-300k.txt"
[ -f "$WORK/movie.mov" ] && touch -t "$MONTH" "$WORK/movie.mov"
touch -t "$YEAR" "$WORK/data-2mb.txt" "$WORK/Code"
echo "setup: $WORK: $(ls -A "$WORK" | paste -sd ' ' -)"
for f in "$WORK"/*; do echo "  $(stat -f '%z %Sm' -t '%Y-%m-%d' "$f") $(basename "$f")"; done

# What the Size filter should keep (Small: over 16 KB up to 1 MB; Medium: up to 128 MB), and every visible item.
expect_small_medium=$(for f in "$WORK"/*; do
    [ -f "$f" ] || continue
    s=$(stat -f %z "$f"); if [ "$s" -gt 16384 ] && [ "$s" -le 134217728 ]; then basename "$f"; fi
done | sort | paste -sd ' ' -)
all_visible=$(ls "$WORK" | sort | paste -sd ' ' -)
total=$(ls "$WORK" | wc -l | tr -d ' ')
echo "setup: Small or Medium should be: $expect_small_medium ($total items in all)"

quit_folio
clean_defaults
# Folio follows the Mac's light or dark setting (it has no theme of its own): the shots are in dark.
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1
open -a "$APP" "$WORK"
if wait_window "work" 15 && [ -n "$(list_point work notes-5k.txt)" ]; then
    echo "launch: ok - window \"work\": $(list_rows work | paste -sd ' ' -)"
else
    echo "launch: FAILED - no window \"work\" with rows after 15 s (windows: $(names_now))"
    exit 1
fi
front
sleep 1.2

# --- 1 and 2: hover the Size header, open its filter -----------------------------------------------------
size_head=$(ax_find AXButton "Size header" work)
move_to "$size_head"
sleep 0.4
move_to "$size_head"
sleep 0.6
f=$(shot m6-1-size-hover)
chev=$(ax_find AXButton "Filter Size" work)
if [ -n "$size_head" ] && [ -n "$chev" ] && [ -n "$f" ]; then
    pass 1 hover "Size header at [$size_head], its chevron at [$chev], $f"
else
    fail 1 hover "header [$size_head] chevron [$chev] shot ${f:-none}"
fi
click_at "$chev"
if wait_window "Filter Size" 4; then
    sleep 0.6
    boxes=$(checkboxes "Filter Size")
    f=$(shot m6-2-size-filter)
    if echo "$boxes" | grep -q "Small (16 KB - 1 MB)" && echo "$boxes" | grep -q "Medium (1 - 128 MB)" \
       && echo "$boxes" | grep -q "Empty (0 KB)" && echo "$boxes" | grep -q "Unspecified"; then
        pass 2 size-filter "buckets: $boxes; $f"
    else
        fail 2 size-filter "buckets: $boxes; shot ${f:-none}"
    fi
else
    f=$(shot m6-2-size-filter)
    fail 2 size-filter "no Filter Size panel (windows: $(names_now))"
fi

# --- 3: tick Small and Medium ------------------------------------------------------------------------------
click_at "$(checkbox_point "Filter Size" "Small (16 KB - 1 MB)")"
sleep 0.5
click_at "$(checkbox_point "Filter Size" "Medium (1 - 128 MB)")"
sleep 0.8
keys 'key code 53'
sleep 0.6
move_to "$(ax_find AXGroup "Status bar" work)"
sleep 0.5
rows=$(list_rows work | sort | paste -sd ' ' -)
token=$(ax_find AXButton "Filter Size: Small, Medium" work)
status=$(status_text work)
filtered=$(ax_find AXButton "Filter Size" work value)
f=$(shot m6-3-filtered)
n=$(echo "$expect_small_medium" | wc -w | tr -d ' ')
if [ "$rows" = "$expect_small_medium" ] && [ -n "$token" ] && echo "$status" | grep -q "^$n items* (filtered from $total)" \
   && [ "$filtered" = "filtered" ]; then
    pass 3 filtered "rows: $rows; token \"Size: Small, Medium\" at [$token]; status \"$status\"; header $filtered; $f"
else
    fail 3 filtered "rows [$rows] want [$expect_small_medium]; token [$token]; status [$status]; header [$filtered]; ${f:-none}"
fi

# --- 4: clear from the token's x, then Group by Date modified ---------------------------------------------------
click_at "$(ax_find AXButton "Clear filter Size: Small, Medium" work)"
sleep 1
rows=$(list_rows work | sort | paste -sd ' ' -)
if [ "$rows" = "$all_visible" ] && [ -z "$(ax_find AXButton "Filter Size: Small, Medium" work)" ]; then
    echo "  cleared: every item back ($rows)"
else
    fail 4 clear "after the token's x: [$rows] want [$all_visible]"
fi
front
menu_bar View "Group By" "Date modified"
sleep 1.2
rows=$(list_rows work)
f=$(shot m6-4-grouped)
if echo "$rows" | grep -q "^Today (" && echo "$rows" | grep -q "^Last week (" && echo "$rows" | grep -q "^Last month (" \
   && echo "$rows" | grep -q "^A long time ago ("; then
    pass 4 group-by "groups: $(echo "$rows" | grep ' (' | paste -sd '|' -); $f"
else
    fail 4 group-by "rows: $(echo "$rows" | paste -sd '|' -); ${f:-none}"
fi

# --- 5: fold Last week from its chevron ----------------------------------------------------------------
lw=$(echo "$rows" | grep "^Last week (" | head -1)
before=$(echo "$rows" | wc -l | tr -d ' ')
click_at "$(list_point work "$lw" 22)"
sleep 1
rows2=$(list_rows work)
after=$(echo "$rows2" | wc -l | tr -d ' ')
gone=$(echo "$lw" | sed 's/.*(\([0-9]*\))/\1/')
f=$(shot m6-5-collapsed)
if [ $((before - after)) -eq "$gone" ] && echo "$rows2" | grep -q "^Last week (" && ! echo "$rows2" | grep -qx "notes-5k.txt"; then
    pass 5 collapse "\"$lw\" folded: $before rows -> $after; $f"
else
    fail 5 collapse "$before -> $after rows (want $gone fewer): $(echo "$rows2" | paste -sd '|' -); ${f:-none}"
fi

# --- 6: no grouping; Date modified, then Shift+click Type and Name ------------------------------------------
menu_bar View "Group By" "(None)"
sleep 1
click_at "$(ax_find AXButton "Date modified header" work)"
sleep 0.8
click_at "$(ax_find AXButton "Type header" work)" --shift
sleep 0.8
click_at "$(ax_find AXButton "Name header" work)" --shift
sleep 1
d=$(ax_find AXButton "Date modified header" work value)
t=$(ax_find AXButton "Type header" work value)
nm=$(ax_find AXButton "Name header" work value)
first=$(list_rows work | head -1)
last=$(list_rows work | tail -1)
move_to "$(ax_find AXGroup "Status bar" work)"
f=$(shot m6-6-sort-badges)
if [ "$d" = "sort 1 descending" ] && [ "$t" = "sort 2 ascending" ] && [ "$nm" = "sort 3 ascending" ] && [ "$last" = "Code" ]; then
    pass 6 sort-badges "Date modified [$d], Type [$t], Name [$nm]; first row $first, last row $last (folders last, oldest last); $f"
else
    fail 6 sort-badges "Date [$d] Type [$t] Name [$nm]; rows $(list_rows work | paste -sd ' ' -); ${f:-none}"
fi

# --- 7, 8, 9: the header menu, Choose Details, the Dimensions column -------------------------------------------
click_at "$(ax_find AXButton "Type header" work)" --right
sleep 0.8
f=$(shot m6-7-header-menu)
pass 7 header-menu "right-click on the Type header; $f"
osascript -e 'tell application "System Events" to keystroke "More"' >/dev/null 2>&1
sleep 0.3
osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
sleep 1.5
sheet=$(osascript -e 'tell application "System Events" to tell process "Folio" to get role of sheet 1 of window "work"' 2>&1)
# The list has the keys: type Dimensions to find it, Space ticks it.
osascript -e 'tell application "System Events" to keystroke "Dimensions"' >/dev/null 2>&1
sleep 0.8
osascript -e 'tell application "System Events" to key code 49' >/dev/null 2>&1
sleep 0.8
f=$(shot m6-8-choose-details)
if [ "$sheet" = "AXSheet" ]; then
    pass 8 choose-details "More... opened Choose Details; Dimensions found by typing and ticked with Space; $f"
else
    fail 8 choose-details "no sheet: $sheet; ${f:-none}"
fi
# Return is OK.
osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
sleep 2
dimcell=$(osascript -e 'tell application "System Events" to tell process "Folio" to get description of every UI element of (first row of table 1 of scroll area 2 of window "work" whose description of UI element 1 is "photo.png")' 2>&1)
f=$(shot m6-9-dimensions)
if [ -n "$(ax_find AXButton "Dimensions header" work)" ] && echo "$dimcell" | grep -Eq "[0-9]+ x [0-9]+"; then
    pass 9 dimensions "Dimensions column on; photo.png reads: $dimcell; $f"
else
    fail 9 dimensions "photo.png row: $dimcell; ${f:-none}"
fi

# --- 10, 11, 12: Large icons, Tiles, Content -----------------------------------------------------------------
menu_bar View "Large icons"
sleep 2.5
f=$(shot m6-10-large-icons)
if [ "$(has_table work)" != "true" ] && [ -n "$(ax_find AXStaticText photo.png work)" ]; then
    pass 10 large-icons "the grid shows photo.png at [$(ax_find AXStaticText photo.png work)]; $f"
else
    fail 10 large-icons "table still there: $(has_table work); ${f:-none}"
fi
menu_bar View Tiles
sleep 1.5
f=$(shot m6-11-tiles)
[ -n "$(ax_find AXStaticText photo.png work)" ] && pass 11 tiles "$f" || fail 11 tiles "no photo.png tile; ${f:-none}"
menu_bar View Content
sleep 1.5
f=$(shot m6-12-content)
[ -n "$(ax_find AXStaticText photo.png work)" ] && pass 12 content "$f" || fail 12 content "no photo.png row; ${f:-none}"

# --- 13: select the PNG, Option+P ------------------------------------------------------------------------
click_at "$(ax_find AXStaticText photo.png work)"
sleep 0.5
keys 'keystroke "p" using option down'
sleep 2.5
pane=$(defaults read com.anshul.folio sidePane 2>/dev/null)
f=$(shot m6-13-preview-pane)
if [ "$pane" = "preview" ] && [ -n "$(ax_find AXGroup "Preview pane" work)" ]; then
    pass 13 preview-pane "Option+P: the Preview pane (saved as \"$pane\"); $f"
else
    fail 13 preview-pane "sidePane=[$pane]; ${f:-none}"
fi

# --- 14: Space for Quick Look, Down for the next item ------------------------------------------------------
keys 'key code 49'
sleep 2.5
f=$(shot m6-14-quick-look)
if has_window "photo.png" || window_names | grep -qi "quick look"; then
    pass 14 quick-look "Quick Look open on photo.png: windows $(names_now); $f"
else
    fail 14 quick-look "windows: $(names_now); ${f:-none}"
fi
before_ql=$(status_text work)
osascript -e 'tell application "System Events" to key code 125' >/dev/null 2>&1
sleep 2
after_ql=$(status_text work)
f=$(shot m6-14b-quick-look-next)
if [ -n "$before_ql" ] && [ "$before_ql" != "$after_ql" ] && echo "$after_ql" | grep -q "1 selected" && window_names | grep -q "Quick Look"; then
    pass 14b quick-look-next "Down in Quick Look moved the list on: [$before_ql] -> [$after_ql], Quick Look still open; $f"
else
    fail 14b quick-look-next "status before [$before_ql] after [$after_ql], windows $(names_now); ${f:-none}"
fi
osascript -e 'tell application "System Events" to key code 49' >/dev/null 2>&1
sleep 1
front
osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1
sleep 0.5

# --- 15: the Details pane for the PNG ---------------------------------------------------------------------
click_at "$(ax_find AXStaticText photo.png work)"
sleep 0.4
keys 'keystroke "p" using {option down, shift down}'
sleep 2
pane=$(defaults read com.anshul.folio sidePane 2>/dev/null)
dims=$(echo "$dimcell" | grep -oE "[0-9]+ x [0-9]+" | head -1)
f=$(shot m6-15-details-pane)
info=$(ax_find AXGroup "Details pane" work value)
if [ "$pane" = "details" ] && echo "$info" | grep -q "^photo.png; PNG image" && echo "$info" | grep -q "Dimensions: $dims" \
   && [ -n "$(ax_find AXTextField Tags work)" ] && [ -n "$(ax_find AXTextField Comments work)" ]; then
    pass 15 details-pane "Option+Shift+P: the Details pane reads [$info]; Tags and Comments fields; $f"
else
    fail 15 details-pane "sidePane=[$pane] dims [$dims] pane reads [$info]; ${f:-none}"
fi
keys 'keystroke "p" using {option down, shift down}'
sleep 0.6

# --- 16: Cmd+Shift+. shows the dot file -------------------------------------------------------------------
keys 'keystroke "." using {command down, shift down}'
sleep 1.5
f=$(shot m6-16-hidden)
if [ -n "$(ax_find AXStaticText .hidden-notes work)" ] && [ "$(defaults read com.anshul.folio showHiddenItems 2>/dev/null)" = "1" ]; then
    pass 16 hidden "the dot file shows (saved: showHiddenItems 1); $f"
else
    fail 16 hidden "no .hidden-notes; ${f:-none}"
fi
keys 'keystroke "." using {command down, shift down}'
sleep 1

# --- 17: Gallery ------------------------------------------------------------------------------------------
menu_bar View Gallery
sleep 1.2
click_at "$(ax_find AXStaticText photo.png work)"
sleep 2.5
f=$(shot m6-17-gallery)
[ -n "$(ax_find AXStaticText photo.png work)" ] && pass 17 gallery "$f" || fail 17 gallery "no strip; ${f:-none}"

# --- 18: Details (Ctrl+Shift+6), then Cmd+scroll up once: List --------------------------------------------
keys 'key code 22 using {control down, shift down}'
sleep 1.2
if [ "$(has_table work)" = "true" ]; then echo "  Ctrl+Shift+6: Details"; else fail 18 ctrl-shift-6 "no table after Ctrl+Shift+6"; fi
pt=$(list_point work notes-5k.txt 200)
echo "  $("$MOUSE" scroll ${pt% *} ${pt#* } 1 --command)"
sleep 1.5
f=$(shot m6-18-cmd-scroll)
if [ "$(has_table work)" != "true" ] && [ -n "$(ax_find AXStaticText photo.png work)" ]; then
    pass 18 cmd-scroll "Cmd+scroll up stepped Details to List; $f"
else
    fail 18 cmd-scroll "table still there: $(has_table work); ${f:-none}"
fi

# --- 19 and 20: Large icons as the default, Details picked again, quit, relaunch -------------------------
menu_bar View "Large icons"
sleep 1
menu_bar View "Make This the Default View"
sleep 0.5
keys 'key code 22 using {control down, shift down}'
sleep 1
saved=$(defaults read com.anshul.folio defaultView 2>/dev/null)
was=$(has_table work)
if quit_folio; then echo "  quit in Details (table: $was), default saved: $saved"; else fail 19 quit "still running"; fi
open -a "$APP" "$WORK"
if wait_window work 15; then
    front
    sleep 3
    f=$(shot m6-19-relaunch-default)
    if [ "$saved" = "largeIcons" ] && [ "$was" = "true" ] && [ "$(has_table work)" != "true" ] && [ -n "$(ax_find AXStaticText photo.png work)" ]; then
        pass 19 global-default "relaunched in Large icons (the saved default), not Details (the last view); $f"
    else
        fail 19 global-default "default [$saved], table before quit [$was], table now [$(has_table work)]; ${f:-none}"
    fi
    click_at "$(ax_find AXStaticText Albums work)" --double
    if wait_window Albums 6; then
        sleep 1.5
        f=$(shot m6-20-subfolder)
        if [ "$(has_table Albums)" != "true" ] && [ -n "$(ax_find AXStaticText inside.txt Albums)" ]; then
            pass 20 subfolder "Albums opens in the same Large icons view; $f"
        else
            fail 20 subfolder "table [$(has_table Albums)]; ${f:-none}"
        fi
    else
        f=$(shot m6-20-subfolder)
        fail 20 subfolder "no Albums window: $(names_now)"
    fi
else
    fail 19 global-default "no window after relaunch: $(names_now)"
fi

# --- quit and clean up ------------------------------------------------------------------------------------
if quit_folio; then pass 21 quit "Folio quit"; else fail 21 quit "Folio was still running 10 s after quit"; fi
clean_defaults
mv "$ROOT" "$HOME/.Trash/" 2>/dev/null

if [ "$fails" -eq 0 ]; then
    echo "result: ok, PNGs in $SHOTS"
    exit 0
fi
echo "result: FAILED ($fails steps), PNGs in $SHOTS"
exit 1
