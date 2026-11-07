#!/bin/bash
# Milestone 8 GUI check: Compress to ZIP with its progress window, the zip browsed like a folder, Extract all
# with its destination dialog and Show extracted files when complete, Folder Options (General, then View:
# Display the full path in the title bar and Use check boxes to select items, OK), Tags > Red with the tag
# dot and the Tags column, auto-refresh after a file made from the shell, the Option tap's access keys and
# N for New, full screen with Ctrl+Cmd+F, and Rotate right on a JPEG with the Dimensions column swapping.
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Makes /private/tmp/folio-tests/m8-<stamp>/work with alpha.txt, a 150 MB random big.bin (so the
# compress takes long enough to see), notes.md, photo.jpg (64 x 32, with EXIF, embedded below as base64)
# and a docs folder; opens ~/folio/Folio.app on it and drives it with real events: System Events for keys,
# folio-mouse6 (CGEvent through the HID tap, compiled here with swiftc) for clicks and right-clicks.
# PNGs go to ~/folio/shots/:
#   m8-1-compress-progress.png   right-click > Compress to > ZIP file on alpha.txt and big.bin: the progress window
#   m8-2-zip-in-list.png         big.zip in the list when it is done
#   m8-3-zip-browse.png          double-click big.zip: its entries, read like a folder
#   m8-4-extract-dialog.png      Back, right-click big.zip > Extract all...: the destination dialog
#   m8-5-extracted.png           Return: the extracted folder opened in a window of its own
#   m8-6-options-general.png     View > Options (Cmd+Option+,): Folder Options, General
#   m8-7-options-view.png        the View tab with the two boxes ticked
#   m8-8-fullpath-checkboxes.png OK: the full path in the title bar, check boxes on the rows
#   m8-9-tags.png                right-click alpha.txt > Tags > Red: the red dot and the Tags column
#   m8-10-autorefresh.png        touch fresh.txt from the shell: in the list within a second
#   m8-11-access-keys.png        Option tapped: the command bar's letters
#   m8-12-access-new.png         N: the New menu (then Esc)
#   m8-13-fullscreen.png         Ctrl+Cmd+F: full screen
#   m8-14-rotate-before.png      the Dimensions column on photo.jpg: 64 x 32
#   m8-15-rotate-after.png       right-click > Rotate right: 32 x 64
#   m8-16-thousand-archives.png  a folder of 1,000 files compressed to set.zip, set.7z and set.tar (MILESTONES'
#                                check), each extracted back with Extract all and counted
#   m8-17-changed-in-shell.png   notes.md grown from the shell: its Size cell updates within a second
#   m8-18-customize.png          right-click docs > Customize this folder...: Properties at Customize
# Prints one line per step and exits non-zero if any step fails.
set -u

APP="$HOME/folio/Folio.app"
# These scripts check the D4 Obsidian look (View > Theme); the app's default is Native.
defaults write com.anshul.folio lookTheme obsidian
SHOTS="$HOME/folio/shots"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT="/private/tmp/folio-tests/m8-$STAMP"
WORK="$ROOT/work"
MOUSE="$HOME/folio/folio-mouse6"
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "m8: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if [ ! -d "$APP" ]; then
    echo "m8: missing $APP (stage the build first, docs/plan/VM.md)"
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
if [ ! -x "$MOUSE" ]; then echo "m8: could not build folio-mouse6"; exit 2; fi

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

# submenu_pick <item> <sub item>: type the item, Right opens its submenu, type the sub item, Return.
submenu_pick() {
    echo "  menu: type \"$1\", Right, type \"$2\", Return"
    osascript -e "tell application \"System Events\" to keystroke \"$1\"" >/dev/null 2>&1
    sleep 0.5
    osascript -e 'tell application "System Events" to key code 124' >/dev/null 2>&1
    sleep 0.5
    osascript -e "tell application \"System Events\" to keystroke \"$2\"" >/dev/null 2>&1
    sleep 0.4
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

# ax_frame <AXRole> <description> <window>: "x y w h" of the first match.
ax_frame() {
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
        set {px, py} to position of found
        set {sx, sy} to size of found
        return (px as text) & " " & (py as text) & " " & (sx as text) & " " & (sy as text)
    end tell
end run
OSA
}

# inside "<x y>" "<x y w h>": the point lies within the frame (8 pt in from its top and bottom).
inside() {
    [ -n "$1" ] && [ -n "$2" ] || return 1
    set -- ${1} ${2}
    [ "$2" -ge $(( $4 + 8 )) ] && [ "$2" -le $(( $4 + $6 - 8 )) ]
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

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

# The keys milestones 2 to 8 keep in the app's defaults, so each run starts from Explorer's defaults.
clean_defaults() {
    for k in session quickAccessPins navPaneCollapsed homeCollapsed favorites recentFiles addressHistory \
             navPaneExpandToCurrent navPaneShown navPaneWidth showHiddenItems trashOrigins \
             defaultView detailsColumns showFileExtensions showThumbnails compactView sidePane itemCheckBoxes \
             searchFileContents searchSystemFiles searchRecentDropdown recentSearches searchBoxWidth \
             openFolioTo browseFoldersOwnWindow singleClickOpen singleClickUnderline showRecentFiles showFrequentFolders \
             fileIconOnThumbnails folderTipSizes fullPathInTitle hideEmptyDrives hideFolderMergeConflicts hideProtectedFiles \
             showDriveLetters showCompressedInColour showInfoTips showPreviewHandlers showStatusBar typeIntoSearch confirmDelete \
             navPaneShowAllFolders navPaneShowNetwork navPaneShowThisPC searchDontUseIndex searchZippedFolders; do
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

expect() { echo "$@" | tr ' ' '\n' | LC_ALL=C sort | paste -sd ' ' -; }

# wait_rows <window> <name>: until a row of that name shows (up to $3 seconds).
wait_row() {
    local i=0 n=$(( ${3:-10} * 10 ))
    while [ "$i" -lt "$n" ]; do
        list_rows "$1" | grep -Fxq "$2" && return 0
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

# The tags Finder keeps on a file, as text (the binary plist made readable).
tags_of() {
    local hex
    hex=$(xattr -px com.apple.metadata:_kMDItemUserTags "$1" 2>/dev/null) || return 0
    echo "$hex" | xxd -r -p > "$ROOT/tags.plist"
    # Each tag is stored as "Name<newline>Colour": folded here to "Name|Colour" (Red is colour 6).
    plutil -p "$ROOT/tags.plist" 2>/dev/null | tr '\n' '|' | sed 's/[][]//g; s/| *[0-9]* => //g; s/"//g; s/^|//; s/|$//'
}

PHOTO_B64='/9j/4AAQSkZJRgABAQAASABIAAD/4QEIRXhpZgAATU0AKgAAAAgABAEPAAIAAAAGAAAAPgEQAAIAAAALAAAARIdpAAQAAAABAAAAUIglAAQAAAABAAAAmgAAAABGb2xpbwBGb2xpb0NhbSA4AAAABJADAAIAAAAUAAAAhqABAAMAAAABAAEAAKACAAQAAAABAAAAQKADAAQAAAABAAAAIAAAAAAyMDI0OjA1OjAxIDEwOjIwOjMwAAAEAAEAAgAAAAJOAAAAAAIABQAAAAMAAADQAAMAAgAAAAJFAAAAAAQABQAAAAMAAADoAAAAAAAAAA0AAAABAAAALQAAAAEAAAAAAAAAZAAAAGQAAAABAAAAHgAAAAEAAAAAAAAAZP/tADhQaG90b3Nob3AgMy4wADhCSU0EBAAAAAAAADhCSU0EJQAAAAAAENQdjNmPALIE6YAJmOz4Qn7/wAARCAAgAEADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9sAQwACAgICAgIDAgIDBAMDAwQFBAQEBAUHBQUFBQUHCAcHBwcHBwgICAgICAgICgoKCgoKCwsLCwsNDQ0NDQ0NDQ0N/9sAQwECAgIDAwMGAwMGDQkHCQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0N/90ABAAE/9oADAMBAAIRAxEAPwD0yiiiv5HP9HDH1b/ll/wL+lY9bGrf8sv+Bf0rHr/UT6Ov/Jvcv/7i/wDp6of5I/Sc/wCTl5l/3B/9MUgooor9sPwUKKKKAP/Q9Mooor+Rz/Rwx9W/5Zf8C/pWPWxq3/LL/gX9Kx6/1E+jr/yb3L/+4v8A6eqH+SP0nP8Ak5eZf9wf/TFIKKKK/bD8FCiiigD/2Q=='

# --- setup ------------------------------------------------------------------------------------------------
echo "  $("$MOUSE" release)"
mkdir -p "$SHOTS" "$WORK/docs"
printf 'alpha\n' > "$WORK/alpha.txt"
printf '# Notes\n' > "$WORK/notes.md"
printf 'inside docs\n' > "$WORK/docs/readme.txt"
head -c 150000000 /dev/urandom > "$WORK/big.bin"
echo "$PHOTO_B64" | base64 -D > "$WORK/photo.jpg"
echo "setup: $WORK"
(cd "$WORK" && find . -print | sed 's#^\./##' | grep -v '^\.$' | while read -r f; do
    echo "  $(stat -f '%z %Sm' -t '%Y-%m-%d %H:%M' "$f") $f"
done)
echo "  photo.jpg: $(sips -g pixelWidth -g pixelHeight "$WORK/photo.jpg" | tail -2 | tr -s ' ' | paste -sd ' ' -)"

quit_folio
clean_defaults
# Folio follows the Mac's light or dark setting (it has no theme of its own): the shots are in dark.
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1
open -a "$APP" "$WORK"
if wait_window work 15 && [ -n "$(list_point work alpha.txt)" ]; then
    echo "launch: ok - window \"work\": $(sorted_rows work)"
else
    echo "launch: FAILED - no window \"work\" with rows after 15 s (windows: $(names_now))"
    exit 1
fi
front
sleep 1.2

# --- 1, 2: select alpha.txt and big.bin, right-click > Compress to > ZIP file ------------------------------------
click_at "$(list_point work alpha.txt)"
sleep 0.3
click_at "$(list_point work big.bin)" --command
sleep 0.4
st=$(status_text work)
echo "  status: $st"
click_at "$(list_point work big.bin)" --right
sleep 0.8
submenu_pick "Compress to" "ZIP"
if wait_window Progress 8; then
    sleep 0.6
    job=$(osascript -e 'tell application "System Events" to tell process "Folio" to get description of every group of window "Progress"' 2>/dev/null)
    f=$(shot m8-1-compress-progress)
    pass 1 compress-progress "\"$st\"; Compress to > ZIP file: the Progress window [$job]; $f"
else
    f=$(shot m8-1-compress-progress)
    fail 1 compress-progress "no Progress window (windows: $(names_now)); ${f:-none}"
fi
if wait_row work big.zip 40; then
    i=0
    while has_window Progress && [ "$i" -lt 60 ]; do sleep 0.5; i=$((i + 1)); done
    sleep 1
    entries=$(cd "$ROOT" && unzip -Z1 "$WORK/big.zip" 2>/dev/null | LC_ALL=C sort | paste -sd ' ' -)
    size=$(stat -f %z "$WORK/big.zip")
    f=$(shot m8-2-zip-in-list)
    if [ "$entries" = "alpha.txt big.bin" ]; then
        pass 2 zip-in-list "big.zip ($size bytes, named after the right-clicked item) holds [$entries]; rows [$(sorted_rows work)]; $f"
    else
        fail 2 zip-in-list "big.zip holds [$entries]; ${f:-none}"
    fi
else
    f=$(shot m8-2-zip-in-list)
    fail 2 zip-in-list "no big.zip row (rows: $(sorted_rows work)); ${f:-none}"
fi

# --- 3: double-click big.zip: its entries, like a folder ----------------------------------------------------------------
click_at "$(list_point work big.zip)" --double
if wait_window big.zip 6 && wait_row big.zip alpha.txt 6; then
    sleep 0.8
    rows=$(sorted_rows big.zip)
    cells=$(row_cells big.zip big.bin)
    f=$(shot m8-3-zip-browse)
    if [ "$rows" = "alpha.txt big.bin" ]; then
        pass 3 zip-browse "big.zip opened like a folder: [$rows]; big.bin row [$cells]; $f"
    else
        fail 3 zip-browse "rows [$rows]; ${f:-none}"
    fi
else
    f=$(shot m8-3-zip-browse)
    fail 3 zip-browse "no big.zip window (windows: $(names_now)); ${f:-none}"
fi

# --- 4, 5: Back; right-click big.zip > Extract all...; Return -----------------------------------------------------------
keys 'key code 123 using option down'
wait_window work 6
sleep 1
click_at "$(list_point work big.zip)" --right
sleep 0.8
menu_pick "Extract all"
i=0
while [ "$i" -lt 24 ]; do
    [ "$(osascript -e 'tell application "System Events" to tell process "Folio" to exists sheet 1 of window "work"' 2>/dev/null)" = "true" ] && break
    sleep 0.25; i=$((i + 1))
done
sleep 0.6
dest=$(osascript -e 'tell application "System Events" to tell process "Folio" to get value of text field 1 of sheet 1 of window "work"' 2>/dev/null)
show=$(osascript -e 'tell application "System Events" to tell process "Folio" to get value of checkbox 1 of sheet 1 of window "work"' 2>/dev/null)
f=$(shot m8-4-extract-dialog)
if { [ "$dest" = "$WORK/big" ] || [ "$dest" = "${WORK#/private}/big" ]; } && [ "$show" = "1" ]; then
    pass 4 extract-dialog "Extract all: destination [$dest], Show extracted files when complete ticked; $f"
else
    fail 4 extract-dialog "sheet: destination [$dest] show [$show]; ${f:-none}"
fi
osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
if wait_window big 30 && wait_row big alpha.txt 10; then
    sleep 1
    rows=$(sorted_rows big)
    same=$(cmp -s "$WORK/big.bin" "$WORK/big/big.bin" && echo same || echo different)
    f=$(shot m8-5-extracted)
    if [ "$rows" = "alpha.txt big.bin" ] && [ "$same" = "same" ]; then
        pass 5 extracted "a window on work/big: [$rows]; big.bin $same as the original; $f"
    else
        fail 5 extracted "rows [$rows]; big.bin $same; ${f:-none}"
    fi
    keys 'keystroke "w" using {command down, shift down}'
    sleep 0.8
else
    f=$(shot m8-5-extracted)
    fail 5 extracted "no window big (windows: $(names_now)); ${f:-none}"
fi
front
sleep 0.5

# --- 6, 7, 8: View > Options; View tab; tick two boxes; OK ---------------------------------------------------------
keys 'keystroke "," using {command down, option down}'
if wait_window "Folder Options" 6; then
    sleep 0.8
    general=$(ax_find AXRadioButton "Open each folder in the same window" "Folder Options" value)
    f=$(shot m8-6-options-general)
    if [ "$general" = "1" ]; then
        pass 6 options-general "Folder Options, General: Open each folder in the same window chosen; $f"
    else
        fail 6 options-general "same-window radio [$general]; ${f:-none}"
    fi
    click_at "$(ax_find AXButton View "Folder Options")"
    sleep 0.8
    click_at "$(ax_find AXCheckBox "Display the full path in the title bar" "Folder Options")"
    sleep 0.4
    # Use check boxes is further down the Advanced settings list: scroll it into view, then click it.
    list=$(ax_find AXScrollArea "Advanced settings" "Folder Options")
    for lines in -12 -12 24; do
        echo "  $("$MOUSE" scroll ${list% *} ${list#* } $lines)"
        sleep 0.6
        box=$(ax_find AXCheckBox "Use check boxes to select items" "Folder Options")
        if inside "$box" "$(ax_frame AXScrollArea "Advanced settings" "Folder Options")"; then
            click_at "$box"
            break
        fi
    done
    sleep 0.5
    full=$(ax_find AXCheckBox "Display the full path in the title bar" "Folder Options" value)
    boxes=$(ax_find AXCheckBox "Use check boxes to select items" "Folder Options" value)
    f=$(shot m8-7-options-view)
    if [ "$full" = "1" ] && [ "$boxes" = "1" ]; then
        pass 7 options-view "View tab: Display the full path [$full], Use check boxes [$boxes]; $f"
    else
        fail 7 options-view "full path [$full] check boxes [$boxes]; ${f:-none}"
    fi
    click_at "$(ax_find AXButton OK "Folder Options")"
    sleep 1.2
else
    f=$(shot m8-6-options-general)
    fail 6 options "no Folder Options window (windows: $(names_now)); ${f:-none}"
fi
# The title bar spells paths as the address bar does: /tmp, not /private/tmp.
W="${WORK#/private}"
if wait_window "$W" 5; then
    sleep 0.6
    saved="fullPathInTitle=$(defaults read com.anshul.folio fullPathInTitle 2>/dev/null) itemCheckBoxes=$(defaults read com.anshul.folio itemCheckBoxes 2>/dev/null)"
    click_at "$(list_point "$W" notes.md)"
    sleep 0.6
    f=$(shot m8-8-fullpath-checkboxes)
    if ! has_window "Folder Options" && echo "$saved" | grep -q "fullPathInTitle=1 itemCheckBoxes=1"; then
        pass 8 fullpath-checkboxes "OK: the window is now named \"$W\"; [$saved]; $f"
    else
        fail 8 fullpath-checkboxes "windows $(names_now); [$saved]; ${f:-none}"
    fi
else
    f=$(shot m8-8-fullpath-checkboxes)
    fail 8 fullpath-checkboxes "no window named \"$W\" (windows: $(names_now)); ${f:-none}"
    W=work
fi

# --- 9: the Tags and Dimensions columns; right-click alpha.txt > Tags > Red -------------------------------------
click_at "$(ax_find AXButton "Type header" "$W")" --right
sleep 0.8
menu_pick "Tags"
sleep 1
click_at "$(ax_find AXButton "Type header" "$W")" --right
sleep 0.8
menu_pick "Dimensions"
sleep 1.2
click_at "$(list_point "$W" alpha.txt)" --right
sleep 0.8
submenu_pick "Tags" "Red"
sleep 1.2
tags=$(tags_of "$WORK/alpha.txt")
cells=$(row_cells "$W" alpha.txt)
f=$(shot m8-9-tags)
if echo "$tags" | grep -q "Red|6" && echo "$cells" | grep -q "Red" && [ -n "$(ax_find AXButton "Tags header" "$W")" ]; then
    pass 9 tags "Tags > Red: Finder's attribute reads [$tags]; the row [$cells]; $f"
else
    fail 9 tags "attribute [$tags]; row [$cells]; ${f:-none}"
fi

# --- 10: touch a file from the shell: in the list within a second ------------------------------------------------------
t0=$(now)
touch "$WORK/fresh.txt"
seen=""
i=0
while [ "$i" -lt 20 ]; do
    if list_rows "$W" | grep -Fxq fresh.txt; then seen=$(now); break; fi
    sleep 0.05
    i=$((i + 1))
done
f=$(shot m8-10-autorefresh)
if [ -n "$seen" ]; then
    ms=$(perl -e "printf '%d', ($seen - $t0) * 1000")
    pass 10 autorefresh "touch fresh.txt: in the list after $ms ms (polled through accessibility); $f"
    [ "$ms" -le 1000 ] || { fail 10 autorefresh-time "took $ms ms"; }
else
    fail 10 autorefresh "fresh.txt not listed within a second (rows: $(sorted_rows "$W")); ${f:-none}"
fi

# --- 11, 12: tap Option: access keys; N opens New; Esc --------------------------------------------------------------
front
click_at "$(list_point "$W" notes.md)"
sleep 0.5
osascript -e 'tell application "System Events" to key down option' >/dev/null 2>&1
sleep 0.15
osascript -e 'tell application "System Events" to key up option' >/dev/null 2>&1
sleep 0.6
newkey=$(ax_quick AXButton New "$W" value)
morekey=$(ax_quick AXButton "See more" "$W" value)
f=$(shot m8-11-access-keys)
if [ "$newkey" = "N" ] && [ "$morekey" = "M" ]; then
    pass 11 access-keys "Option tapped: New shows [$newkey], See more [$morekey] (Delete, Sort and View fold into See more at this width); $f"
else
    fail 11 access-keys "New [$newkey] See more [$morekey]; ${f:-none}"
fi
osascript -e 'tell application "System Events" to keystroke "n"' >/dev/null 2>&1
sleep 0.9
menu=$(osascript -e 'tell application "System Events" to tell process "Folio" to get name of every menu item of menu 1' 2>/dev/null)
after=$(ax_quick AXButton New "$W" value)
f=$(shot m8-12-access-new)
osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1
sleep 0.5
if [ "$after" = "" ] && [ "$newkey" = "N" ]; then
    pass 12 access-new "N pressed New: its menu [$menu]; the letters went; Esc closed it; $f"
else
    fail 12 access-new "menu [$menu]; letters after [$after]; ${f:-none}"
fi

# --- 13: Ctrl+Cmd+F: full screen, and back ----------------------------------------------------------------------
keys 'keystroke "f" using {control down, command down}'
sleep 2.5
fs=$(osascript -e "tell application \"System Events\" to tell process \"Folio\" to get value of attribute \"AXFullScreen\" of window \"$W\"" 2>/dev/null)
f=$(shot m8-13-fullscreen)
keys 'keystroke "f" using {control down, command down}'
sleep 2.5
back=$(osascript -e "tell application \"System Events\" to tell process \"Folio\" to get value of attribute \"AXFullScreen\" of window \"$W\"" 2>/dev/null)
if [ "$fs" = "true" ] && [ "$back" = "false" ]; then
    pass 13 fullscreen "Ctrl+Cmd+F: full screen [$fs], again: back [$back]; $f"
else
    fail 13 fullscreen "full screen [$fs], after [$back]; ${f:-none}"
fi

# --- 14, 15: Rotate right on photo.jpg: the Dimensions column swaps -----------------------------------------------
front
sleep 0.5
# Room for Dimensions on this narrow screen: Tags and Date modified come off.
for col in Tags "Date modified"; do
    click_at "$(ax_find AXButton "Type header" "$W")" --right
    sleep 0.8
    menu_pick "$col"
    sleep 1
done
before=$(row_cells "$W" photo.jpg)
click_at "$(list_point "$W" photo.jpg)"
sleep 0.4
f1=$(shot m8-14-rotate-before)
click_at "$(list_point "$W" photo.jpg)" --right
sleep 0.8
menu_pick "Rotate right"
sleep 1.5
after=$(row_cells "$W" photo.jpg)
dims=$(sips -g pixelWidth -g pixelHeight "$WORK/photo.jpg" | tail -2 | tr -s ' ' | paste -sd ' ' -)
f2=$(shot m8-15-rotate-after)
if echo "$before" | grep -q "64 x 32" && echo "$after" | grep -q "32 x 64"; then
    pass 14 rotate "Dimensions [$before] -> [$after]; the stored pixels stay [$dims] (lossless: only the orientation tag turned); $f1 $f2"
else
    fail 14 rotate "before [$before] after [$after]; [$dims]; ${f2:-none}"
fi

# --- 16: MILESTONES' check: 1,000 files to zip, 7z and tar, and back --------------------------------------------
mkdir -p "$WORK/set"
(cd "$WORK/set" && seq -f "file-%04g.txt" 1 1000 | while read -r n; do printf '%s\n' "$n" > "$n"; done)
front
sleep 1
wait_row "$W" set 5
counts=""
ok16=1
for fmt in "ZIP:zip" "7z:7z" "TAR:tar"; do
    pick=${fmt%%:*}; ext=${fmt#*:}
    click_at "$(list_point "$W" set)" --right
    sleep 0.8
    submenu_pick "Compress to" "$pick"
    if ! wait_row "$W" "set.$ext" 30; then ok16=0; counts="$counts no set.$ext;"; continue; fi
    i=0
    while has_window Progress && [ "$i" -lt 60 ]; do sleep 0.5; i=$((i + 1)); done
    sleep 0.8
done
mv "$WORK/set" "$ROOT/set-src"
for ext in zip 7z tar; do
    wait_row "$W" "set.$ext" 5
    click_at "$(list_point "$W" "set.$ext")" --right
    sleep 0.8
    menu_pick "Extract all"
    sleep 1.2
    osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1
    # The full path is in the title now (step 8); the archives hold set/, so it lands in set/set as in Explorer.
    if wait_window "$W/set" 30; then
        n=$(find "$WORK/set" -type f | wc -l | tr -d ' ')
        same=$(diff -rq "$ROOT/set-src" "$WORK/set/set" >/dev/null 2>&1 && echo same || echo differ)
        counts="$counts set.$ext: $n files, $same;"
        [ "$n" = "1000" ] && [ "$same" = "same" ] || ok16=0
        keys 'keystroke "w" using {command down, shift down}'
        sleep 0.8
        mv "$WORK/set" "$ROOT/set-from-$ext"
    else
        ok16=0
        counts="$counts set.$ext: no window;"
    fi
    front
    sleep 0.6
done
f=$(shot m8-16-thousand-archives)
sizes=$(cd "$WORK" && stat -f '%N %z' set.zip set.7z set.tar 2>/dev/null | paste -sd ',' -)
if [ "$ok16" = "1" ]; then
    pass 16 thousand "1,000 files: [$sizes]; extracted back:$counts $f"
else
    fail 16 thousand "[$sizes]$counts ${f:-none}"
fi

# --- 17: a file changed from the shell: its row updates within a second ---------------------------------------------
before=$(row_cells "$W" notes.md)
t0=$(now)
head -c 3000 /dev/zero | tr '\0' 'x' >> "$WORK/notes.md"
seen=""
i=0
while [ "$i" -lt 20 ]; do
    if row_cells "$W" notes.md | grep -q "|3 KB"; then seen=$(now); break; fi
    sleep 0.05
    i=$((i + 1))
done
after=$(row_cells "$W" notes.md)
f=$(shot m8-17-changed-in-shell)
if [ -n "$seen" ]; then
    ms=$(perl -e "printf '%d', ($seen - $t0) * 1000")
    pass 17 changed "notes.md grown by 3,000 bytes from the shell: [$before] -> [$after] after $ms ms; $f"
    [ "$ms" -le 1000 ] || fail 17 changed-time "took $ms ms"
else
    fail 17 changed "row [$before] -> [$after]; ${f:-none}"
fi

# --- 18: right-click docs > Customize this folder...: Properties at Customize ----------------------------------------------
click_at "$(list_point "$W" docs)" --right
sleep 0.8
menu_pick "Customize this folder"
if wait_window "docs Properties" 6; then
    sleep 0.8
    tab=$(ax_find AXButton Customize "docs Properties" value)
    f=$(shot m8-18-customize)
    if [ "$tab" = "1" ] && [ -n "$(ax_find AXPopUpButton "Optimize this folder for" "docs Properties")" ]; then
        pass 18 customize "Properties opened at Customize: Optimize for (columns per kind), Change Icon, Restore Default; $f"
    else
        fail 18 customize "Customize tab [$tab]; ${f:-none}"
    fi
    keys 'keystroke "w" using command down'
    sleep 0.6
else
    f=$(shot m8-18-customize)
    fail 18 customize "no docs Properties window (windows: $(names_now)); ${f:-none}"
fi

# --- quit and clean up ------------------------------------------------------------------------------------
if quit_folio; then pass 19 quit "Folio quit"; else fail 19 quit "Folio was still running 10 s after quit"; fi
clean_defaults
mv "$ROOT" "$HOME/.Trash/" 2>/dev/null
# The proof PNGs go into the repo at 1440 wide.
for png in "$SHOTS"/m8-*.png; do sips --resampleWidth 1440 "$png" >/dev/null 2>&1; done

if [ "$fails" -eq 0 ]; then
    echo "result: ok, PNGs in $SHOTS"
    exit 0
fi
echo "result: FAILED ($fails steps), PNGs in $SHOTS"
exit 1
