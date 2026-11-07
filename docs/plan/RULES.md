# Build rules for Folio

Binding for every agent and every session that touches this repo. Anshul's words, 2026-11-05: "make sure nothing gets fucked up", "my files should not be touched", "use an emulator to test if you can", and the golden rule: "no files on the actual physical machine should be touched by the folio app, everything it runs should be on the VM".

## 0. The golden rule: Folio never runs on the physical Mac

- The Folio binary is never executed on Anshul's MacBook or on the Ultra host, in any mode: no `open`, no direct launch, no `--selftest`, no `--uitest`. Not on real folders, not on temp folders. Read-only is not an exception.
- On the host, allowed: `swift build`, `make app` (produces the bundle, runs nothing), `make test` (unit tests on FolioCore, which touch only temp folders the tests create), `codesign`, `xattr`.
- Every run of the app happens inside the tart VM `folio-test` on the Ultra: copy the built `Folio.app` in, run and screenshot it there, bring PNGs back. Until the VM is up, nothing is run and the hand-off says so.

## 1. His files are never a test target

- No test, selftest, script or manual check ever reads, writes, moves, renames, copies into, deletes or trashes anything under `/Users/anshul` except the repo worktree itself and `~/.Trash` as a destination for the repo's own build leftovers.
- Listing of real folders by the app is not allowed on the host either (rule 0). `--selftest` and `--uitest` exist for the VM.
- File-operation tests (copy, move, rename, delete, trash, undo, conflict handling, zip) run only on:
  - temp folders created by the test under `$TMPDIR` or `/private/tmp/folio-tests/<run id>/`, removed by moving to the Trash when done;
  - the scratch disk image `/private/tmp/folio-tests/scratch.dmg` (APFS, created with `hdiutil create -size 2g -fs APFS -volname FolioScratch`), mounted at `/Volumes/FolioScratch`, for anything that needs a real volume (eject, capacity bars, cross-volume moves). Never any other volume.
- The app itself is launched only inside the VM (rule 0), on the VM's own folders.

## 2. GUI tests run in the VM, not on his desktop

- No `osascript` System Events keystrokes, mouse events, window activation or `open` on folders on the host Mac. His Finder was hijacked by exactly that on 2026-11-05.
- GUI checks (clicks, keys, drag and drop, menus, dialogs) run inside the tart VM `folio-test` (macOS, Apple Virtualization). Install the built `Folio.app` into the VM (`tart` shares a folder or `scp` over its IP), drive it there with AppleScript or the app's `--uitest` script runner, and bring screenshots back.
- No visual check on the host at all: the app does not run there (rule 0).
- Until the VM exists, behaviour is covered by unit tests only, and the hand-off says so.

## 3. Tests first, then code, then proof

- Every behaviour gets a failing test first (swift-testing in `Tests/`), written from the user-visible workflow in `docs/plan/MILESTONES.md`.
- `make test` must pass before any commit. `make app` must build. Both run after every milestone.
- Nothing is reported as done without a real run: a command output or a screenshot the agent looked at.

## 4. Scope and style

- One milestone per branch, stacked on the previous one; small commits with messages that name the slice; push, report, stop (no CI watching by agents).
- There are two looks, picked in View > Theme (added 2026-11-06):
  - **Native** (the default) follows macOS's own styles: SF Pro, system colours, the system accent, materials, SF Symbols, Finder icons. Its reference is `docs/design/native.md`, and the Mac itself (Finder) where that page is silent.
  - **D4 Obsidian** is `docs/design/d4-obsidian-spotlight.html` (the design Anshul picked, replacing D1 Control room on 2026-11-07). Tokens, type, icons, chassis and motion are ported from it, never improvised. A Native change never changes a D4 pixel.
  - In both: never italic, never emoji icons.
- Explorer behaviour comes from `docs/research/` and `docs/plan/MILESTONES.md`; when they disagree with memory, the research wins.
- Swift 6 + AppKit, SwiftPM, Command Line Tools only. No Xcode project, no Apple developer account, no third-party runtime dependencies without a reason written in the PR.
- Deleting anything in the repo: `mv` to `~/.Trash`, never `rm -rf`.
