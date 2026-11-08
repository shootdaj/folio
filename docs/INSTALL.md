# Installing Folio on your Mac

The normal way is the zip on the [Releases page](https://github.com/shootdaj/folio/releases): every
`vX.Y.Z` tag publishes one, built and tested by CI on the Mac Ultra. Building from source with the free
Command Line Tools works too (no Xcode, no developer account). Every step below runs on your Mac once you
decide to use Folio there; until then, development runs the app only in the test VM (docs/plan/RULES.md,
rule 0).

```
Releases zip ──► /Applications ──► make install-cli ──► BTT preset ──► Open folders in Folio
  (or clone ──► make app ──► make install)   (ff in your PATH)   (Win+E key)    (Folder Options)
```

## 1. Download a release

1. On the [Releases page](https://github.com/shootdaj/folio/releases), download `Folio-<version>.zip` from
   the newest release. It is built for Apple Silicon Macs on macOS 14 or later; versions below 1.0.0 are
   marked pre-release. What changed in each version: [CHANGELOG.md](../CHANGELOG.md).
2. Quit Folio if an older copy is running (Cmd+Q) and move that copy to the Trash. Unzip the download and
   move `Folio.app` to /Applications.
3. Folio is signed ad hoc, not with an Apple developer account, so macOS blocks a downloaded copy until
   you clear its download flag once:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Folio.app
   ```
   (Or try to open it, then System Settings > Privacy & Security > **Open Anyway**.)
4. Open it once from /Applications. That registers it with Launch Services, so `ff`, `open -b
   com.anshul.folio` and folio: links find it. Its Dock icon is three glass leaves: a blue front leaf on a
   white tile, or a white one on a graphite tile in macOS 26's dark icon style.

`/Applications/Folio.app/Contents/MacOS/Folio --version` prints the version and the commit it was built
from, for example `Folio 1.0.0 (f12cd6f)`.

## 2. Or build it yourself

```sh
git clone https://github.com/shootdaj/folio.git && cd folio
xcode-select --install      # only if the Command Line Tools are missing (iconutil and swift come with them)
make test                   # the unit tests, on temp folders only
make app                    # build/Folio.app, with the Dock icon and the version stamped in
make install                # copies it to /Applications and registers it
```

`make app` draws the Dock icon (`folio-icon` writes build/Folio.iconset, `iconutil` turns it into
Folio.icns). If Xcode is installed, `actool` also compiles build/AppIcon.icon into Assets.car, which has
the dark icon for macOS 26's dark icon style. Without Xcode the light icon shows in every style. `make
app` also stamps the version from the git tags (`git describe --tags --always --dirty`: 1.0.0 on the
tag v1.0.0, 1.0.0-3-gabc1234 three commits after it) and the commit into the bundle.

`make install` copies build/Folio.app to /Applications (an older copy goes to the Trash first) and
registers it with Launch Services. Quit Folio before installing a new build. Open it once from
/Applications; macOS asks nothing, since a copy built on your own Mac carries no download flag.

## 3. Install `ff`

`ff` is not in the release zip; it builds from a clone of the repo (step 2's first line):

```sh
sudo make install-cli          # /usr/local/bin/ff
make install-cli PREFIX=$HOME  # or ~/bin/ff, no sudo (put ~/bin in your PATH)
```

| Command | Opens |
|---|---|
| `ff` | the current folder |
| `ff <path>` | that folder; a file opens its folder with it selected |
| `ff -n <path>` | in a new window |
| `ff -t <path>` | in a new tab of the front window |
| `ff --reveal <path>` | its folder, with it selected (Explorer's /select) |
| `ff --search "<query>" [path]` | a search of the folder, as typed in the search box |

Folio starts when it is not running. By default a folder goes to a tab already showing it, or a new tab
in the front window (Folder Options > General > Open external folder links in a new tab).

## 4. The Win+E key (BetterTouchTool)

`docs/btt/Folio.bttpreset` holds one global trigger: **Cmd+Shift+E** (what macOS sees for your Win+E-style
key) runs `open -b com.anshul.folio`, which starts Folio, or brings it forward with a window on Home when
none is open. It adds nothing for Finder: your Finder rules stay as they are and never fire inside Folio.

1. BetterTouchTool > Presets (the toolbar's preset menu) > **Import Preset...**, pick `docs/btt/Folio.bttpreset`.
2. Turn the Folio preset on next to your own (BTT runs several presets at once).
3. Press the key: Folio comes forward.

Notes:
- Cmd+Shift+E is also Folio's File > Eject. With the trigger on, BTT takes the key first; eject from the
  sidebar's eject button instead, or pick another key for the trigger.
- The other way round: if your Win+E key arrives as something else (look at what BTT shows when you
  record it), click the trigger in BTT, record the key again, keep the action. A new window on every press,
  as Win+E does, is `open "folio://open?newWindow=1"` as the action's script.
- Without BTT: System Settings > Keyboard > Keyboard Shortcuts > App Shortcuts cannot start an app; a
  Shortcuts.app shortcut with "Open App: Folio" and a key does.

## 5. Open folders in Folio instead of Finder

Folio > **Open Folders in Folio Instead of Finder**, or View > Options... > General > Folio and macOS >
**Open folders in Folio instead of Finder**. Folio asks Launch Services to make it the default app for
folders (`public.folder`) and drives (`public.volume`), reads the answer back, and shows what macOS kept.

**macOS 26 keeps folders on Finder.** Measured on macOS 26.4.1: Launch Services refuses
`public.folder` with error -50 (`paramErr`) for every app, Finder too. The system log says
`scheme or content type is protected`. Only Apple processes with a private entitlement (Finder,
CoreServicesUIAgent) can change this default, and System Settings has no control for it. This is a
macOS limit, not a Folio fault. Drives still change: after the click, a drive's root opens in Folio.
Folio then shows the box as on, so a second click hands drives back to Finder.

Measured in the test VM (macOS 15.7): macOS accepted both types, and `open <folder>` from Terminal then
opened the folder in Folio, as a new tab.

The known limits on every version:
- **"Reveal in Finder" and "Show in Finder" in other apps go to Finder**, unless **Reveal in Folio
  instead of Finder** is on (below).
- Folders that other apps open (`open <folder>` in Terminal, for example) go to the default app for
  folders. On macOS 26 that is always Finder.
- Double-clicking a folder inside Finder stays in Finder.

In Terminal, use `ff --reveal <path>` for a reveal in Folio.

### Reveal in Folio instead of Finder

Folio > **Reveal in Folio Instead of Finder**, or View > Options... > General > Folio and macOS >
**Reveal in Folio instead of Finder**. Folio sets the `NSFileViewer` user default in the global domain
to Folio. It is the same as this command:

```sh
defaults write -g NSFileViewer -string com.anshul.folio
```

AppKit reads this setting when an app calls "Reveal in Finder" or "Show in Finder" through
`NSWorkspace`. Turning the box off removes the key when it names Folio, so reveals go to Finder
again. If the key names another app (ForkLift, for example), turning the box on replaces it and tells
you which app it replaced.

Measured on macOS 26.4.1, with probe apps in place of Folio:
- A reveal of a file opens Folio with the file selected in its folder.
- A reveal of a folder and a plain open of a folder (`open -a Folio <folder>`) send identical events.
  Only the sender is different: a reveal comes from the app that asks for it, and a command-line tool is
  no app. So Folio shows a folder selected in its parent when this box is on and the folder comes from
  another app. A folder from a command-line tool, the Dock (a drop on Folio's icon), Finder (Open With),
  or a drive's root opens the folder itself.
- A plain folder open from another app does not follow this setting. It goes to the default app for
  folders, which macOS 26 keeps on Finder. Where Folio is the default app for folders (macOS 15), such
  an open reaches Folio and looks the same as a reveal. With this box on, Folio then shows the folder
  selected in its parent. Turn the box off to open the folder itself.
- If the app that the key names is missing, AppKit logs
  `Finder replacement <id> not found; "defaults delete -g NSFileViewer" to remove`.

Not measured:
- The Dock and Finder senders. Their bundle IDs are on the list, but no test dropped a folder on the Dock.
- Whether an app that is already open follows the change at once. If a reveal still goes to Finder,
  quit and reopen that app.
- Scripts and Apple events that address Finder by name always go to Finder.

## 6. The rest of Folder Options > General > Folio and macOS

| Setting | Default | What it does |
|---|---|---|
| Open external folder links in a new tab | on | Folders from ff and other apps open as a tab in the front window, not a new window |
| Reopen windows and tabs on relaunch | on | Windows, tabs, each tab's folder, history, sort, selection, scroll place and search, the tree's open folders and the view come back |
| Keep running when the last window closes | on | Folio stays in the Dock with no window, as Explorer does; Cmd+Q still quits |
| Launch Folio at login | off | Adds Folio to System Settings > General > Login Items |

The session lives in `~/Library/Application Support/Folio/session.json`, written half a second after each
change and on quit. A damaged file is moved aside (`session.corrupt-<time>.json`) and Folio starts on Home.
Settings live in `~/Library/Preferences/com.anshul.folio.plist`.

## Uninstall

1. In Folio, turn off **Open folders in Folio instead of Finder** (folders go back to Finder),
   **Reveal in Folio instead of Finder** (reveals go back to Finder) and **Launch Folio at login**.
2. Quit Folio (Cmd+Q), then:
   ```sh
   make uninstall
   ```
   It moves /Applications/Folio.app and ff (/usr/local/bin or ~/bin) to the Trash. If `NSFileViewer`
   still names Folio, it removes that key, so reveals go to Finder again.
3. In BetterTouchTool, turn off or delete the Folio preset.
4. Optional: move `~/Library/Application Support/Folio` and `~/Library/Preferences/com.anshul.folio.plist`
   to the Trash to forget the session, saved searches and settings.
