# Build rules for Folio

Binding for every agent and every session that touches this repo. Anshul's words, 2026-11-05: "make sure nothing gets fucked up", "my files should not be touched", "use an emulator to test if you can".

## 1. His files are never a test target

- No test, selftest, script or manual check ever reads, writes, moves, renames, copies into, deletes or trashes anything under `/Users/anshul` except the repo worktree itself and `~/.Trash` as a destination for the repo's own build leftovers.
- Listing (read-only) of real folders is allowed only through the app's `--selftest <folder>`, which opens nothing and changes nothing.
- File-operation tests (copy, move, rename, delete, trash, undo, conflict handling, zip) run only on:
  - temp folders created by the test under `$TMPDIR` or `/private/tmp/folio-tests/<run id>/`, removed by moving to the Trash when done;
  - the scratch disk image `/private/tmp/folio-tests/scratch.dmg` (APFS, created with `hdiutil create -size 2g -fs APFS -volname FolioScratch`), mounted at `/Volumes/FolioScratch`, for anything that needs a real volume (eject, capacity bars, cross-volume moves). Never any other volume.
- The app itself, when launched by an agent for a check, is launched only on a temp folder or the scratch volume, never on a real folder, and never while the GUI test rule below is in force on the host.

## 2. GUI tests run in the VM, not on his desktop

- No `osascript` System Events keystrokes, mouse events, window activation or `open` on folders on the host Mac. His Finder was hijacked by exactly that on 2026-11-05.
- GUI checks (clicks, keys, drag and drop, menus, dialogs) run inside the tart VM `folio-test` (macOS, Apple Virtualization). Install the built `Folio.app` into the VM (`tart` shares a folder or `scp` over its IP), drive it there with AppleScript or the app's `--uitest` script runner, and bring screenshots back.
- On the host, the only allowed visual check is a screenshot of an already open Folio window by window id (`screencapture -l <id>`), without activating it.
- Until the VM exists, GUI behaviour is covered by unit tests plus the `--selftest` and `--uitest` headless runners only, and the hand-off says so.

## 3. Tests first, then code, then proof

- Every behaviour gets a failing test first (swift-testing in `Tests/`), written from the user-visible workflow in `docs/plan/MILESTONES.md`.
- `make test` must pass before any commit. `make app` must build. Both run after every milestone.
- Nothing is reported as done without a real run: a command output or a screenshot the agent looked at.

## 4. Scope and style

- One milestone per branch, stacked on the previous one; small commits with messages that name the slice; push, report, stop (no CI watching by agents).
- The look is `docs/design/d1-control-room.html` (the design Anshul picked). Tokens, type, icons, chassis and motion are ported from it, never improvised. Never italic. Never emoji icons.
- Explorer behaviour comes from `docs/research/` and `docs/plan/MILESTONES.md`; when they disagree with memory, the research wins.
- Swift 6 + AppKit, SwiftPM, Command Line Tools only. No Xcode project, no Apple developer account, no third-party runtime dependencies without a reason written in the PR.
- Deleting anything in the repo: `mv` to `~/.Trash`, never `rm -rf`.
