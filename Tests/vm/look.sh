#!/bin/bash
# Look check for D4 Obsidian spotlight: browse in dark, the accent popover, a recoloured selection after a
# preset click and a hue-slider drag, Esc and a click outside closing the popover, the accent kept in the
# defaults as a hue number, then the Mac switched to light (the app follows it) and back.
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Makes /private/tmp/folio-tests/look-<stamp>/Code (folders and files of several types), opens
# ~/folio/Folio.app on it, drives it with System Events and folio-mouse-look (real mouse events through the
# HID tap, compiled here with swiftc), and writes PNGs of the Folio window to ~/folio/shots/:
#   look-1-browse-dark.png      dark, ai-harness selected, the pointer resting on another row (cursor glow)
#   look-2-accent-picker.png    the title bar's swatch clicked: ACCENT, the eight presets, the hue slider
#   look-3-preset-violet.png    the Violet preset clicked: the picker and the window recoloured at once
#   look-4-slider-green.png     the slider dragged to green, the popover closed with Esc: the selection green
#   look-5-browse-light.png     the Mac in light mode, accent back to electric blue: the light theme
#   look-6-accent-light.png     the picker in light
# Prints one line per step and exits non-zero if any step fails. The Mac is left in dark mode.
set -u

APP="$HOME/folio/Folio.app"
# The VM has no Full Disk Access to give: the launch alert (DiskAccessPrompt) must not hold the run.
defaults write com.anshul.folio diskAccessDismissed -bool true
SHOTS="$HOME/folio/shots"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT="/private/tmp/folio-tests/look-$STAMP"
CODE="$ROOT/Code"
MOUSE="$HOME/folio/folio-mouse-look"
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "look: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if [ ! -d "$APP" ]; then
    echo "look: missing $APP (stage the build first, docs/plan/VM.md)"
    exit 2
fi

pass() { echo "step $1 $2: ok - $3"; }
fail() { echo "step $1 $2: FAILED - $3"; fails=$((fails + 1)); }

# --- folio-mouse-look: move, click and drag through the HID event tap ----------------------------------
mkdir -p "$HOME/folio" "$ROOT" "$SHOTS"
cat > "$ROOT/folio-mouse-look.swift" <<'SWIFT'
// folio-mouse-look: real mouse events for the look check (docs/plan/VM.md). VM only (RULES.md, rule 0).
//   folio-mouse-look move <x> <y>
//   folio-mouse-look click <x> <y>
//   folio-mouse-look drag <x1> <y1> <x2> <y2>     (press, 12 steps, release)
import CoreGraphics
import Foundation

let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ p: CGPoint) {
    guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
    e.setIntegerValueField(.mouseEventClickState, value: 1)
    e.post(tap: .cghidEventTap)
}
let a = Array(CommandLine.arguments.dropFirst())
let n = a.dropFirst().compactMap(Double.init)
switch a.first {
case "move" where n.count == 2:
    post(.mouseMoved, CGPoint(x: n[0] - 6, y: n[1])); usleep(80_000)
    post(.mouseMoved, CGPoint(x: n[0], y: n[1])); usleep(150_000)
    print("moved to \(Int(n[0])),\(Int(n[1]))")
case "click" where n.count == 2:
    let p = CGPoint(x: n[0], y: n[1])
    post(.mouseMoved, p); usleep(120_000)
    post(.leftMouseDown, p); usleep(60_000)
    post(.leftMouseUp, p); usleep(150_000)
    print("click at \(Int(p.x)),\(Int(p.y))")
case "drag" where n.count == 4:
    let from = CGPoint(x: n[0], y: n[1]), to = CGPoint(x: n[2], y: n[3])
    post(.mouseMoved, from); usleep(120_000)
    post(.leftMouseDown, from); usleep(150_000)
    for i in 1...12 {
        let t = Double(i) / 12
        post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        usleep(40_000)
    }
    usleep(150_000)
    post(.leftMouseUp, to); usleep(200_000)
    print("drag \(Int(from.x)),\(Int(from.y)) -> \(Int(to.x)),\(Int(to.y))")
default:
    print("usage: folio-mouse-look move x y | click x y | drag x1 y1 x2 y2")
    exit(2)
}
SWIFT
if ! cmp -s "$ROOT/folio-mouse-look.swift" "$HOME/folio/folio-mouse-look.swift" || [ ! -x "$MOUSE" ]; then
    cp "$ROOT/folio-mouse-look.swift" "$HOME/folio/folio-mouse-look.swift"
    swiftc -O "$HOME/folio/folio-mouse-look.swift" -o "$MOUSE" 2>&1 | tail -5
fi
if [ ! -x "$MOUSE" ]; then echo "look: could not build folio-mouse-look"; exit 2; fi

# --- helpers --------------------------------------------------------------------------------------------
frontmost() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>&1; }

keys() {
    echo "  key: $1 (frontmost: $(frontmost))"
    osascript -e "tell application \"System Events\" to tell process \"Folio\" to $1" >/dev/null 2>&1
}

front() { osascript -e 'tell application "System Events" to set frontmost of process "Folio" to true' >/dev/null 2>&1; }

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

# set_dark true|false: the Mac's appearance (the app follows it; it has no theme of its own).
set_dark() {
    osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $1" >/dev/null 2>&1
}
is_dark() { osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode' 2>/dev/null; }

# The Folio window's frame on screen: "x y w h".
window_frame() {
    osascript -e 'tell application "System Events" to tell process "Folio"' \
              -e 'set {px, py} to position of window "Code"' -e 'set {sx, sy} to size of window "Code"' \
              -e 'return (px as text) & " " & (py as text) & " " & (sx as text) & " " & (sy as text)' -e 'end tell' 2>/dev/null
}

# shot <name>: the Folio window only (the popover hangs inside it), whatever the step's outcome.
shot() {
    local f="$SHOTS/$1.png" fr
    rm -f "$f"
    fr=$(window_frame)
    if [ -n "$fr" ]; then
        set -- $fr
        screencapture -x -R"$1,$2,$3,$4" "$f" 2>/dev/null
    else
        screencapture -x "$f" 2>/dev/null
    fi
    if [ -s "$f" ]; then echo "$f"; fi
}

# ax_find <AXRole> <description> [value]: "x y" (middle) of the first match in any Folio window (popovers
# hang off the window they belong to), ten levels deep; with "value", the element's value instead.
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
        set found to missing value
        repeat with w in windows
            set found to my find(contents of w, item 1 of argv, item 2 of argv, 10)
            if found is not missing value then exit repeat
        end repeat
        if found is missing value then return ""
        if (count of argv) > 2 and item 3 of argv is "value" then
            try
                return (value of found) as text
            on error
                return ""
            end try
        end if
        if (count of argv) > 2 and item 3 of argv is "frame" then
            set {px, py} to position of found
            set {sx, sy} to size of found
            return (px as text) & " " & (py as text) & " " & (sx as text) & " " & (sy as text)
        end if
        set {px, py} to position of found
        set {sx, sy} to size of found
        return ((px + (sx div 2)) as text) & " " & ((py + (sy div 2)) as text)
    end tell
end run
OSA
}

click_at() {
    local pt="$1"
    [ -n "$pt" ] || { echo "  (no point to click)"; return 1; }
    echo "  $("$MOUSE" click ${pt% *} ${pt#* })"
}

# list_point <name>: "x y" on a Details row's name in window Code.
list_point() {
    osascript - "$1" 2>/dev/null <<'OSA'
on run argv
    tell application "System Events" to tell process "Folio"
        set t to table 1 of scroll area 2 of window "Code"
        repeat with r in rows of t
            try
                set c to UI element 1 of r
                if ((description of c) as text) is (item 1 of argv) then
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

# The sidebar scrolled to its top (Explorer's expand-to-open-folder scrolls it down to the folder).
side_top() {
    osascript -e 'tell application "System Events" to tell process "Folio" to set value of scroll bar 1 of scroll area 1 of window "Code" to 0' >/dev/null 2>&1
}

status_text() {
    osascript -e 'tell application "System Events" to tell process "Folio" to get value of (first group of window "Code" whose description is "Status bar")' 2>/dev/null
}

hue_saved() { defaults read com.anshul.folio accentHue 2>/dev/null; }
picker_open() { [ -n "$(ax_find AXRadioButton Violet)" ]; }

quit_folio() {
    osascript -e 'quit app "Folio"' >/dev/null 2>&1
    local i=0
    while pgrep -x Folio >/dev/null && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
    pgrep -x Folio >/dev/null && pkill -x Folio
}

# --- setup: a Code folder like D4's, with files of several types ------------------------------------------
for d in agent-expert agent-expert-tests ai-crypto-alpha ai-harness ai-video-editing alldebrid-streaming-setup \
         anshul-portfolio apple-knowledge-base automator ax ax-test-crm ax-test-dash2 ax-test-flags ax-test-music; do
    mkdir -p "$CODE/$d"
done
printf '# Airbnb Bangkok\n' > "$CODE/airbnb-bangkok-search.md"
printf 'body { color: #fff; }\n' > "$CODE/report.css"
printf 'console.log(1)\n' > "$CODE/report.js"
printf 'export const a = 1\n' > "$CODE/index.ts"
printf '{ "name": "look" }\n' > "$CODE/package.json"
printf 'package main\n' > "$CODE/main.go"
printf '<!doctype html>\n' > "$CODE/index.html"
head -c 4000 /dev/urandom > "$CODE/build.mjs"
i=0
for f in "$CODE"/*; do touch -t "2026$(printf '%02d' $((i % 9 + 1)))$(printf '%02d' $((i % 27 + 1)))0818" "$f"; i=$((i + 1)); done
echo "setup: $CODE ($(ls "$CODE" | wc -l | tr -d ' ') items)"

quit_folio
# Explorer's defaults (the keys milestones 2 to 9 keep), so the shots start from a fresh window.
for k in session accentHue theme accent quickAccessPins navPaneCollapsed homeCollapsed favorites recentFiles addressHistory \
         navPaneExpandToCurrent navPaneShown navPaneWidth showHiddenItems defaultView detailsColumns showFileExtensions \
         showThumbnails compactView sidePane itemCheckBoxes searchBoxWidth fullPathInTitle showStatusBar \
         navPaneShowAllFolders navPaneShowNetwork navPaneShowThisPC; do
    defaults delete com.anshul.folio "$k" >/dev/null 2>&1
done
# View > Navigation pane > Always expand to current folder off, so the sidebar shows D4's three cards
# (Quick access, This PC, Details) rather than the drive's tree opened down to the test folder.
defaults write com.anshul.folio navPaneExpandToCurrent -bool false
defaults write com.anshul.folio theme light      # a retired key: the app must clear it and ignore it
defaults write com.anshul.folio accent amber
killall NotificationCenter >/dev/null 2>&1
set_dark true
sleep 1
echo "  Mac appearance: dark mode $(is_dark)"

open -a "$APP" "$CODE"
if wait_window "Code" 15; then
    echo "launch: ok - window Code (windows: $(names_now))"
else
    echo "launch: FAILED - no window Code after 15 s (windows: $(names_now))"
    exit 1
fi
front
sleep 1
# As large as the VM's 1024 x 768 screen allows, under the menu bar.
osascript -e 'tell application "System Events" to tell process "Folio"' -e 'set position of window "Code" to {0, 25}' \
          -e 'set size of window "Code" to {1024, 743}' -e 'end tell' >/dev/null 2>&1
sleep 1
echo "  window frame: $(window_frame)"

# --- 1: browse in dark ------------------------------------------------------------------------------------
click_at "$(list_point ai-harness)"
sleep 0.5
side_top
"$MOUSE" move $(list_point apple-knowledge-base | awk '{print $1 + 160, $2}') >/dev/null
sleep 0.15   # the hover glow, before Show pop-up description's tip comes up
st=$(status_text)
retired=$(defaults read com.anshul.folio theme 2>/dev/null; defaults read com.anshul.folio accent 2>/dev/null)
f=$(shot look-1-browse-dark)
if [ -n "$f" ] && echo "$st" | grep -q "1 selected" && [ -z "$retired" ] && [ "$(is_dark)" = "true" ]; then
    pass 1 browse-dark "dark Mac, ai-harness selected, status \"$st\", retired theme and accent keys cleared; $f"
else
    fail 1 browse-dark "status \"$st\", retired keys [$retired], dark $(is_dark); ${f:-none}"
fi

# --- 2: the accent swatch opens the popover ----------------------------------------------------------------
sw=$(ax_find AXButton "Accent colour")
click_at "$sw"
sleep 1
presets=""
for n in "Electric blue" Violet Magenta Red Orange Gold Green Teal; do
    [ -n "$(ax_find AXRadioButton "$n")" ] && presets="$presets${presets:+, }$n"
done
slider=$(ax_find AXSlider "Accent hue" value)
f=$(shot look-2-accent-picker)
if [ -n "$sw" ] && [ "$presets" = "Electric blue, Violet, Magenta, Red, Orange, Gold, Green, Teal" ] && [ "$slider" = "262" ]; then
    pass 2 accent-picker "swatch at [$sw]; presets [$presets]; hue slider at $slider; $f"
else
    fail 2 accent-picker "swatch [$sw]; presets [$presets]; slider [$slider]; ${f:-none}"
fi

# --- 3: a preset recolours at once and is saved as a hue number --------------------------------------------
click_at "$(ax_find AXRadioButton Violet)"
sleep 0.8
h=$(hue_saved)
slider=$(ax_find AXSlider "Accent hue" value)
f=$(shot look-3-preset-violet)
if [ "$h" = "295" ] && [ "$slider" = "295" ] && picker_open; then
    pass 3 preset "Violet: accentHue $h, slider $slider, the picker stays open; $f"
else
    fail 3 preset "accentHue [$h], slider [$slider], open $(picker_open && echo yes || echo no); ${f:-none}"
fi

# --- 4: dragging the slider previews live and saves on release; Esc closes ---------------------------------
fr=$(ax_find AXSlider "Accent hue" frame)
if [ -n "$fr" ]; then
    set -- $fr
    sx=$1; sy=$2; swid=$3; shgt=$4
    from_x=$(( sx + 11 + (swid - 22) * 295 / 359 )); to_x=$(( sx + 11 + (swid - 22) * 145 / 359 )); mid_y=$(( sy + shgt / 2 ))
    echo "  $("$MOUSE" drag $from_x $mid_y $to_x $mid_y)"
fi
sleep 0.6
h=$(hue_saved)
keys 'key code 53'
sleep 0.8
closed=$(picker_open && echo no || echo yes)
"$MOUSE" move $(list_point automator | awk '{print $1 + 160, $2}') >/dev/null
sleep 0.4
f=$(shot look-4-slider-green)
if [ -n "${h:-}" ] && [ "$h" -ge 135 ] && [ "$h" -le 155 ] && [ "$closed" = "yes" ]; then
    pass 4 slider "dragged to green: accentHue $h; Esc closed the popover; selection recoloured; $f"
else
    fail 4 slider "accentHue [$h] (want about 145), closed by Esc [$closed]; ${f:-none}"
fi

# --- 4b: a click outside closes it too; the hue survives a relaunch ----------------------------------------
click_at "$sw"
sleep 0.8
opened=$(picker_open && echo yes || echo no)
click_at "$(list_point ax)"
sleep 0.8
closed=$(picker_open && echo no || echo yes)
quit_folio
open -a "$APP" "$CODE"
wait_window "Code" 15
front
sleep 1.5
h2=$(hue_saved)
click_at "$(ax_find AXButton "Accent colour")"
sleep 0.8
slider=$(ax_find AXSlider "Accent hue" value)
if [ "$opened" = "yes" ] && [ "$closed" = "yes" ] && [ "$h2" = "$h" ] && [ "$slider" = "$h" ]; then
    pass 4b outside-relaunch "reopened, a click on the list closed it; after relaunch accentHue $h2 and the slider reads $slider"
else
    fail 4b outside-relaunch "opened [$opened], closed by click [$closed], accentHue [$h2] want [$h], slider [$slider]"
fi

# --- 5: the Mac goes light; the app follows -----------------------------------------------------------------
click_at "$(ax_find AXRadioButton "Electric blue")"
sleep 0.5
keys 'key code 53'
sleep 0.5
osascript -e 'tell application "System Events" to tell process "Folio"' -e 'set position of window "Code" to {0, 25}' \
          -e 'set size of window "Code" to {1024, 743}' -e 'end tell' >/dev/null 2>&1
click_at "$(list_point ai-harness)"
"$MOUSE" move 600 12 >/dev/null   # off the list while the Mac switches, so no info tip is armed
set_dark false
sleep 2
side_top
"$MOUSE" move $(list_point apple-knowledge-base | awk '{print $1 + 160, $2}') >/dev/null
sleep 0.15   # the hover glow, before Show pop-up description's tip comes up
st=$(status_text)
f=$(shot look-5-browse-light)
if [ "$(is_dark)" = "false" ] && [ "$(hue_saved)" = "262" ] && has_window Code && echo "$st" | grep -q "1 selected"; then
    pass 5 browse-light "light Mac, accent back to 262, status \"$st\"; $f"
else
    fail 5 browse-light "dark mode [$(is_dark)], accentHue [$(hue_saved)], windows [$(names_now)], status [$st]; ${f:-none}"
fi

click_at "$(ax_find AXButton "Accent colour")"
sleep 1
f=$(shot look-6-accent-light)
if picker_open && [ -n "$f" ]; then pass 6 accent-light "the picker in light; $f"; else fail 6 accent-light "open $(picker_open && echo yes || echo no); ${f:-none}"; fi
keys 'key code 53'
sleep 0.5

# --- back to dark, quit and clean up -------------------------------------------------------------------------
set_dark true
sleep 1
quit_folio
if pgrep -x Folio >/dev/null; then fail 7 quit "Folio still running"; else pass 7 quit "Folio quit; Mac back in dark mode: $(is_dark)"; fi
for png in "$SHOTS"/look-*.png; do sips --resampleWidth 1440 "$png" >/dev/null 2>&1; done
mv "$ROOT" "$HOME/.Trash/" 2>/dev/null

if [ "$fails" -eq 0 ]; then
    echo "result: ok, PNGs in $SHOTS"
    exit 0
fi
echo "result: FAILED ($fails steps), PNGs in $SHOTS"
exit 1
