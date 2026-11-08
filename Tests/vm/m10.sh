#!/bin/bash
# Milestone 10 GUI check: the Suggestions page. Three runs of Folio --uitest, each with all three suggestions
# extras: Native dark, Native light and D4 Obsidian dark. Each run makes a fake home of clean-up samples
# (about 100 MB of real bytes, unit 256 KiB) under /private/tmp/folio-tests/, scans it, checks the report
# against UITestFixture.cleanupExpected (every miss is a failed run), moves one large unused file to the
# Trash, waits for the row to leave, undoes it and waits for the row to return. It then shoots the page for
# an empty home and for the Full Disk Access gate.
#
# Runs INSIDE the tart VM folio-test as admin (docs/plan/VM.md), never on a host Mac (docs/plan/RULES.md,
# rule 0). Needs ~/folio/Folio.app. The app drives itself; no System Events keys or mouse events are used.
# PNGs go to ~/folio/shots/, with <run> one of native-dark, native-light, d4-dark:
#   m10-<run>-1-open.png                      the Code folder, before the page
#   m10-<run>-4-suggestions.png               the finished scan: the cards, the sizes, the accent line
#   m10-<run>-4-suggestions-trashed.png       one large unused row moved to the Trash and gone
#   m10-<run>-4-suggestions-undone.png        Undo: the row is back
#   m10-<run>-4-suggestions-empty.png         a home with nothing to offer
#   m10-<run>-4-suggestions-access.png        the Full Disk Access page
# (The 2-name-sorted and 3-row-selected shots of every --uitest run are written too.)
# Prints one line per step and exits non-zero if any step fails.
set -u

APP="$HOME/folio/Folio.app"
BIN="$APP/Contents/MacOS/Folio"
SHOTS="$HOME/folio/shots"
fails=0

if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" != "1" ]; then
    echo "m10: refusing to run: this is not the test VM (docs/plan/RULES.md, rule 0)"
    exit 2
fi
if [ ! -x "$BIN" ]; then
    echo "m10: missing $BIN (stage the build first, docs/plan/VM.md)"
    exit 2
fi

pass() { echo "step $1 $2: ok - $3"; }
fail() { echo "step $1 $2: FAILED - $3"; fails=$((fails + 1)); }

mkdir -p "$SHOTS"
# The VM has no Full Disk Access to give: the launch alert (DiskAccessPrompt) must not hold the run.
defaults write com.anshul.folio diskAccessDismissed -bool true

# run_one <step> <name> <look> <theme>
run_one() {
    local step="$1" name="$2" look="$3" theme="$4"
    local base="$SHOTS/m10-$name" log
    rm -f "$base"-*.png
    log=$("$BIN" --uitest new --shot "$base.png" --look "$look" --theme "$theme" \
        --extra suggestions --extra suggestions-empty --extra suggestions-access 2>&1)
    local rc=$?
    echo "$log" | sed 's/^/    /'
    if [ "$rc" -eq 0 ] && echo "$log" | grep -q "^uitest: result: ok"; then
        pass "$step" "$name-run" "exit 0, every check of the report passed"
    else
        fail "$step" "$name-run" "exit $rc: $(echo "$log" | grep -E 'FAILED|missing|did not|timed out' | head -3 | tr '\n' ' ')"
    fi
    local shot missing=""
    for shot in 4-suggestions 4-suggestions-trashed 4-suggestions-undone 4-suggestions-empty 4-suggestions-access; do
        [ -s "$base-$shot.png" ] || missing="$missing $shot"
    done
    if [ -z "$missing" ]; then
        pass "$step" "$name-shots" "five shots written to $SHOTS"
    else
        fail "$step" "$name-shots" "no PNG for:$missing"
    fi
    if echo "$log" | grep -q "Move to Trash on .*: the row left" && echo "$log" | grep -q "Undo: the row returned"; then
        pass "$step" "$name-undo" "the row left with Move to Trash and returned with Undo"
    elif echo "$log" | grep -q "Display delete confirmation is on"; then
        pass "$step" "$name-undo" "skipped: Display delete confirmation is on in this VM"
    else
        fail "$step" "$name-undo" "the log shows no trash and undo"
    fi
}

run_one 1 native-dark native dark
run_one 2 native-light native light
run_one 3 d4-dark obsidian dark

# The proof PNGs go into the repo at 1440 wide.
for png in "$SHOTS"/m10-*.png; do
    [ -f "$png" ] || continue
    w=$(sips -g pixelWidth "$png" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    [ "${w:-0}" -gt 1440 ] && sips --resampleWidth 1440 "$png" >/dev/null 2>&1
done

if [ "$fails" -eq 0 ]; then
    echo "result: ok, PNGs in $SHOTS"
    exit 0
fi
echo "result: FAILED ($fails steps), PNGs in $SHOTS"
exit 1
