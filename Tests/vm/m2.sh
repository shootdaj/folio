#!/bin/bash
# Milestone 2 GUI check: address bar, typeahead, Tab fill, Enter, Option+Up, crumb dropdown, F4 history.
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Makes a test tree under /private/tmp/folio-tests/m2-<stamp>/, opens ~/folio/Folio.app on it as a
# normal foreground app, drives it with System Events and writes PNGs to ~/folio/shots/:
#   m2-1-typeahead.png   Cmd+L (caret at the end), Cmd+A, then typing /private/tmp/folio-tests/m2-<stamp>/Code/a
#   m2-1b-highlight.png  Down: the first match highlighted (extra shot of the highlighted row)
#   m2-2-tab.png         Tab: the field holds .../Code/agent-expert/ and lists its folders
#   m2-3-enter.png       Enter: the window is in agent-expert
#   m2-4-up.png          Option+Up: back in Code
#   m2-5-crumb-menu.png  the arrow after the Code crumb: Code's folders
#   m2-6-history.png     F4: recent locations
# Prints one line per step and exits non-zero if any step fails.
set -u

APP="$HOME/folio/Folio.app"
# The VM has no Full Disk Access to give: the launch alert (DiskAccessPrompt) must not hold the run.
defaults write com.anshul.folio diskAccessDismissed -bool true
SHOTS="$HOME/folio/shots"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT="/private/tmp/folio-tests/m2-$STAMP"
CODE="$ROOT/Code"
TYPED="$CODE/a"
FILLED="$CODE/agent-expert/"
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "m2: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if [ ! -d "$APP" ]; then
    echo "m2: missing $APP (stage the build first, docs/plan/VM.md)"
    exit 2
fi

pass() { echo "step $1 $2: ok - $3"; }
fail() { echo "step $1 $2: FAILED - $3"; fails=$((fails + 1)); }

frontmost() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>&1; }

# Keys go to the frontmost app, so each one says which app that is.
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
yesno() { if "$@"; then echo yes; else echo no; fi; }

# Waits up to $2 seconds for a window named $1.
wait_window() {
    local i=0 n=$(( ${2:-10} * 4 ))
    while [ "$i" -lt "$n" ]; do
        has_window "$1" && return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}

# Full-screen capture, taken whatever the step's outcome; prints the path when the PNG was written.
# (The old one is removed first: bash 3.2's -nt compares whole seconds, so it cannot tell them apart.)
shot() {
    local f="$SHOTS/$1.png"
    rm -f "$f"
    screencapture -x "$f" 2>/dev/null
    if [ -s "$f" ]; then echo "$f"; fi
}

# ax value|press <AXRole> <description> <window>: reads or presses the first matching element among the
# window's UI elements and theirs (`entire contents` comes back empty for this window in the VM).
ax() {
    osascript - "$@" 2>&1 <<'OSA'
on matches(e, wantRole, wantDesc)
    tell application "System Events"
        try
            return (role of e is wantRole) and (description of e is wantDesc)
        end try
    end tell
    return false
end matches

on run argv
    set act to item 1 of argv
    set wantRole to item 2 of argv
    set wantDesc to item 3 of argv
    set winName to item 4 of argv
    tell application "System Events" to tell process "Folio"
        if not (exists window winName) then return "no window " & winName
        set found to missing value
        set top to UI elements of window winName
        repeat with e in top
            if my matches(e, wantRole, wantDesc) then
                set found to contents of e
                exit repeat
            end if
        end repeat
        if found is missing value then
            repeat with c in top
                try
                    repeat with e in (UI elements of c)
                        if my matches(e, wantRole, wantDesc) then
                            set found to contents of e
                            exit repeat
                        end if
                    end repeat
                end try
                if found is not missing value then exit repeat
            end repeat
        end if
        if found is missing value then return "missing"
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

# --- setup -----------------------------------------------------------------------------------------
mkdir -p "$SHOTS"
for d in agent-expert agent-expert-tests ai-harness alpha beta; do mkdir -p "$CODE/$d/sub"; done
echo "setup: $CODE with agent-expert, agent-expert-tests, ai-harness, alpha, beta (each with sub)"

# A clean start: no Folio running, an empty address history (the F4 list is this run's only), the Mac in
# dark mode, and no macOS notification banner over the toolbar.
osascript -e 'quit app "Folio"' >/dev/null 2>&1
sleep 1
pkill -x Folio 2>/dev/null
defaults delete com.anshul.folio addressHistory >/dev/null 2>&1
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

open -a "$APP" "$CODE"
if wait_window "Code" 15; then
    echo "launch: ok - open -a $APP $CODE, window \"Code\" (windows: $(names_now))"
else
    echo "launch: FAILED - no window \"Code\" after 15 s (windows: $(names_now))"
    exit 1
fi
osascript -e 'tell application "System Events" to set frontmost of process "Folio" to true' >/dev/null 2>&1
sleep 1

# --- 1: Cmd+L, select the path, type ----------------------------------------------------------------
keys 'keystroke "l" using command down'
sleep 0.6
keys 'keystroke "a" using command down'
sleep 0.2
keys "keystroke \"$TYPED\""
sleep 1.5
f=$(shot m2-1-typeahead)
if [ -n "$f" ] && has_window "Address typeahead"; then
    pass 1 typeahead "typed $TYPED, matches listed, $f"
else
    fail 1 typeahead "dropdown open: $(yesno has_window 'Address typeahead'), shot: ${f:-none}, windows: $(names_now)"
fi

keys 'key code 125'
sleep 0.5
f=$(shot m2-1b-highlight)
if [ -n "$f" ] && has_window "Address typeahead"; then
    pass 1b highlight "Down highlights the first match, $f"
else
    fail 1b highlight "dropdown open: $(yesno has_window 'Address typeahead'), shot: ${f:-none}"
fi

# --- 2: Tab fills the highlighted match and adds a slash --------------------------------------------
keys 'key code 48'
sleep 1
f=$(shot m2-2-tab)
v=$(ax value AXTextField Address Code)
if [ -n "$f" ] && [ "$v" = "$FILLED" ]; then
    pass 2 tab "field reads $v, folders of agent-expert listed: $(yesno has_window 'Address typeahead'), $f"
else
    fail 2 tab "field reads '$v', expected '$FILLED', shot: ${f:-none}"
fi

# --- 3: Enter opens it ------------------------------------------------------------------------------
keys 'key code 36'
if wait_window "agent-expert" 5; then
    sleep 0.6
    f=$(shot m2-3-enter)
    if [ -n "$f" ]; then pass 3 enter "window title agent-expert, $f"; else fail 3 enter "no shot"; fi
else
    shot m2-3-enter >/dev/null
    fail 3 enter "window title is not agent-expert (windows: $(names_now))"
fi

# --- 4: Option+Up -----------------------------------------------------------------------------------
keys 'key code 126 using option down'
if wait_window "Code" 5 && ! has_window "agent-expert"; then
    sleep 0.6
    f=$(shot m2-4-up)
    if [ -n "$f" ]; then pass 4 up "window title Code, $f"; else fail 4 up "no shot"; fi
else
    shot m2-4-up >/dev/null
    fail 4 up "window title is not Code (windows: $(names_now))"
fi

# --- 5: the arrow after the Code crumb --------------------------------------------------------------
r=$(ax press AXButton "Folders in Code" Code)
sleep 0.8
f=$(shot m2-5-crumb-menu)
if [ -n "$f" ] && has_window "Folders in Code"; then
    pass 5 crumb-menu "arrow after Code $r, dropdown \"Folders in Code\" open, $f"
else
    fail 5 crumb-menu "arrow: $r, dropdown open: $(yesno has_window 'Folders in Code'), shot: ${f:-none}, windows: $(names_now)"
fi

# --- 6: F4 lists recent locations -------------------------------------------------------------------
keys 'key code 118'
sleep 0.8
f=$(shot m2-6-history)
if [ -n "$f" ] && has_window "Address history"; then
    pass 6 history "F4 opens \"Address history\", $f"
else
    fail 6 history "dropdown open: $(yesno has_window 'Address history'), shot: ${f:-none}, windows: $(names_now)"
fi

# --- quit and clean up ------------------------------------------------------------------------------
osascript -e 'quit app "Folio"' >/dev/null 2>&1
i=0
while pgrep -x Folio >/dev/null && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
if pgrep -x Folio >/dev/null; then
    pkill -x Folio
    fail 7 quit "Folio was still running 10 s after quit"
else
    pass 7 quit "Folio quit"
fi
mv "$ROOT" "$HOME/.Trash/" 2>/dev/null

if [ "$fails" -eq 0 ]; then
    echo "result: ok, PNGs in $SHOTS"
    exit 0
fi
echo "result: FAILED ($fails steps), PNGs in $SHOTS"
exit 1
