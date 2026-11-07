# Native look

The Native look makes Folio feel like a Mac app: Finder's type, colours, selection and materials. It is
the default; D4 Obsidian (`d4-obsidian-spotlight.html`) stays available in View > Theme. Where this
page says nothing, Finder on the same Mac is the reference.

```
D4 Obsidian                         Native
-----------                         ------
Geist, Geist Mono                   SF Pro (system font), SF Pro tabular digits
UPPERCASE TRACKED LABELS            Sentence case, no tracking
fixed sRGB hex tokens               dynamic system colours (light, dark, Increase Contrast)
accent hue picker (title bar)       System Settings > Appearance > Accent and Highlight colour
neon file icons, Lucide glyphs      Finder file icons, SF Symbols
glow, edge bars, cards              system selection, materials, plain lists
```

## Rules

- Colours are system colours resolved when drawn, never copied into hex. Light, dark, Increase
  Contrast and the accent follow the Mac with no relaunch.
- Selection is the system's: the accent fill with white text when the list has focus in the key
  window, the grey unemphasised fill with label text otherwise.
- Surfaces that macOS draws with a material use `NSVisualEffectView`: the sidebar (`.sidebar`), the
  toolbar band (`.titlebar`), menus and drop-down panels (`.menu`), popovers (`.popover`). Reduce
  Transparency is then honoured by AppKit.
- Real AppKit components where custom drawing cannot match the system: push buttons, check boxes,
  radios, segmented controls, the search field, progress bars, menus in the menu font.
- Never italic. Never emoji icons. No glows.

## Tokens

The palette keeps D4's token names, so every view asks for the same name in both looks.

| Token | Native system colour |
|---|---|
| text | `labelColor` |
| text2, muted | `secondaryLabelColor` |
| faint | `tertiaryLabelColor` |
| line, line2 | `separatorColor` |
| outline | `tertiaryLabelColor` |
| accent | `controlAccentColor` |
| onAccent, selectedText | `alternateSelectedControlTextColor` |
| accentSoft | `keyboardFocusIndicatorColor` |
| markFill | `selectedTextBackgroundColor` (the highlight colour) |
| selectionFill | `selectedContentBackgroundColor` |
| selectionInactive | `unemphasizedSelectedContentBackgroundColor` |
| ok, part, miss | `systemGreen`, `systemOrange`, `systemRed` |
| pane, s1, headBg | `controlBackgroundColor` |
| bg, s2, chrome | `windowBackgroundColor` |
| s3, s4 | `secondarySystemFill`, `systemFill` |
| side, bar, pop, tray | drawn by a material, not a fill |
| field, well, segBg | `quaternarySystemFill` |
| rowLine | none (Finder's list has no row lines; alternating rows instead) |

File type colours (D4's neon hues) are not used: Finder icons carry their own colour. Finder tag dots
use the system tag colours (`systemRed`, `systemOrange`, `systemYellow`, `systemGreen`, `systemBlue`,
`systemPurple`, `systemGray`).

## Type

| Use | Native | D4 |
|---|---|---|
| Interface text | `systemFont` 13 | Geist 13 |
| Dates, sizes, counts | `monospacedDigitSystemFont` | Geist Mono |
| Section and column heads | `systemFont` 11 semibold, sentence case | Geist Mono 600, uppercase, tracked |
| Menus | `menuFont` | Geist Mono 13 |

CSS weights map to system weights: 400 and 500 regular, 600 and 650 semibold, 700 and up bold.

## Metrics

| | Native | D4 |
|---|---|---|
| Window top | sidebar runs the full height under the traffic lights | 44 pt title bar with tabs |
| Toolbar band | 52 pt, `.titlebar` material, one hairline below | 52 pt |
| Tab row | shown with two or more tabs, equal widths | always, in the title bar |
| List rows | `.inset` table style, alternating rows | 26 pt, row lines |
| Status bar | 22 pt, 11 pt secondary text | 28 pt |
| Control radius | 6 pt | 12 pt |

## Finder reference shots

To add: `native-shots/finder-dark-1440.png` and `native-shots/finder-light-1440.png`, a Finder window
in list view on the same Mac, for side-by-side comparison with Folio's Native proof shots.
