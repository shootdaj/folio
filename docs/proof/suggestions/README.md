# Suggestions: VM proof

The VM proof for Milestone 10 is not run yet. No shot is in this folder.
The branch was built without a VM, so nobody has seen the page yet.

## How to run it

Run these commands in the test VM, never on a host Mac (docs/plan/RULES.md, rule 0).

1. Build the app on the host and stage `Folio.app` in the VM at `~/folio/Folio.app` (docs/plan/VM.md).
2. In the VM, run `bash ~/folio/m10.sh` (copy `Tests/vm/m10.sh` there first).
3. Fetch the PNGs from `~/folio/shots/m10-*.png` and put them in this folder.

The script runs `Folio --uitest` three times. Each run uses all three suggestions extras.

```
Folio --uitest new --shot ~/folio/shots/m10-native-dark.png  --look native   --theme dark  --extra suggestions --extra suggestions-empty --extra suggestions-access
Folio --uitest new --shot ~/folio/shots/m10-native-light.png --look native   --theme light --extra suggestions --extra suggestions-empty --extra suggestions-access
Folio --uitest new --shot ~/folio/shots/m10-d4-dark.png      --look obsidian --theme dark  --extra suggestions --extra suggestions-empty --extra suggestions-access
```

## What each run checks

- The scan of the fake home finds exactly the set in `UITestFixture.cleanupExpected`. Each miss fails the run.
- Move to Trash takes one large unused row. The row leaves the page.
- Undo brings the row back to the page.
- The run shoots the empty page and the Full Disk Access page.

If "Display delete confirmation" is on in the VM, the run skips the Trash and Undo steps and says so.

## What to look at in the shots and by hand

Nobody saw these parts while the branch was built. Check each one in the VM.

- Home did not change. The Home row stays lit on Home, the crumb shows one "Home" with no arrows, and the side pane returns on a folder. Run `m4.sh` and `m5.sh`.
- The sidebar row: the sparkles icon in both looks, the row sits above the Trash row, the row lights when the page shows, and drag-to-pin still lands between the pins.
- Go > Suggestions and Cmd+Shift+S open the page. The tab shows the sparkles icon. A search from the page reads "Home" in the box and the tab, and Esc goes back to the page.
- Native: the header buttons and progress bar fit, the rows do not clip under the action strip, and the selection colors are the system colors.
- D4: the card and row spacing, the glow on hover and focus, and the accent progress line. The Native shots must not change because of D4 work, and the reverse.
- A narrow pane of about 300 pt: the header button and the card button stay inside the pane, and the two access buttons stack.
- Quit with a Suggestions tab open. On the next launch, no scan starts until you show the page again or press Rescan.
- With "Display delete confirmation" on, change the file while the sheet is open. The file must not move.
- The row menu, Cmd+Backspace, Return (reveals and never opens), Cmd+R, and Esc.
- VoiceOver: the Down arrow reads the focused row, and the rows have Move to Trash, Reveal and Ignore actions.
