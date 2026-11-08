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
