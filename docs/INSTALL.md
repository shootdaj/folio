# Installing Folio on your Mac

Folio is built from source with the free Command Line Tools (no Xcode, no developer account). Every
step below runs on your Mac once you decide to use Folio there; until then, development runs the app only
in the test VM (docs/plan/RULES.md, rule 0).

```
clone ──► make app ──► make install ──► make install-cli ──► BTT preset ──► Open folders in Folio
           (build)     (/Applications)   (ff in your PATH)    (Win+E key)    (Folder Options)
```

## 1. Build

```sh
git clone https://github.com/shootdaj/folio.git && cd folio
xcode-select --install      # only if the Command Line Tools are missing (iconutil and swift come with them)
make test                   # the unit tests, on temp folders only
make app                    # build/Folio.app, with the Dock icon and the version stamped in
```

`make app` draws the Dock icon (`folio-icon` writes build/Folio.iconset, `iconutil` turns it into
Folio.icns) and writes the version and the git commit into the bundle. `build/Folio.app/Contents/MacOS/Folio
--version` prints them, for example `Folio 0.9.0 (f12cd6f)`.

## 2. Install the app

```sh
make install
```

Copies build/Folio.app to /Applications (an older copy goes to the Trash first) and registers it with
Launch Services, so `ff`, `open -b com.anshul.folio` and folio: links find it. Quit Folio before
installing a new build. Open it once from /Applications; macOS asks nothing (it is signed ad hoc on this
Mac), and its Dock icon is the folder with the green light (a light version on a light Mac).

## 3. Install `ff`

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

Measured in the test VM (macOS 15.7): macOS accepted both, and `open <folder>` from Terminal then opened
the folder in Folio, as a new tab.

The known limit: **"Reveal in Finder" and "Show in Finder" in other apps stay on Finder.** They call
Finder by name, not the default app for folders. Folders opened through Launch Services follow the
setting: `open <folder>` in Terminal (measured), and other apps that open a folder rather than reveal it.
Double-clicking a folder inside Finder stays in Finder. For a reveal in Folio, use `ff --reveal <path>`.
Turning the box off hands folders back to Finder.

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

1. In Folio, turn off **Open folders in Folio instead of Finder** (folders go back to Finder) and
   **Launch Folio at login**.
2. Quit Folio (Cmd+Q), then:
   ```sh
   make uninstall
   ```
   It moves /Applications/Folio.app and ff (/usr/local/bin or ~/bin) to the Trash.
3. In BetterTouchTool, turn off or delete the Folio preset.
4. Optional: move `~/Library/Application Support/Folio` and `~/Library/Preferences/com.anshul.folio.plist`
   to the Trash to forget the session, saved searches and settings.
