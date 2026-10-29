# Raintile Guide

Complete reference for Raintile. For a presentation and installation steps see the [README](../README.md).

## Contents

- [Opening and closing](#opening-and-closing)
- [Controls](#controls)
  - [Mouse](#mouse)
  - [Keyboard](#keyboard)
  - [Gamepad](#gamepad)
- [Search](#search)
- [Launching a tile](#launching-a-tile)
- [Categories and tiles](#categories-and-tiles)
  - [Category files](#category-files)
  - [Tile keys](#tile-keys)
  - [Commands](#commands)
  - [Images](#images)
- [Importing games from stores](#importing-games-from-stores)
- [Options window (WIP)](#options-window-wip)
- [Settings reference](#settings-reference)
- [Sizes in pixels or percentages](#sizes-in-pixels-or-percentages)
- [How it works](#how-it-works)
- [File structure](#file-structure)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)

## Opening and closing

The launcher loads **once** (when Rainmeter starts, or on *Refresh skin*) and then stays in memory: opening and closing it only **shows and hides** it, without re-reading files or recomputing anything.

| How | Opens | Closes |
| --- | --- | --- |
| `Ctrl+Alt+G` (`OpenHotKey`) | ✓ | ✓ |
| Gamepad `Back` + `Start` (`GamepadToggle`) | ✓ | ✓ |
| `Esc` (`CloseHotKey`) | | ✓ (closes the search first, if open) |
| The **X** at the top right (`CloseAction`) | | ✓ |
| After launching a tile (`CloseOnLaunch=1`) | | ✓ |
| Losing focus: a click outside the launcher (e.g. on a second monitor) or another program coming to the foreground (`AutoHide=1`) | | ✓ |

Without the HotKey plugin you can toggle it from a Windows shortcut: create a shortcut with this target and assign it a *Shortcut key* in its properties:

```
"C:\Program Files\Rainmeter\Rainmeter.exe" !CommandMeasure MeasureScript "Toggle()" "Raintile"
```

Related settings: `StartHidden=1` keeps the launcher hidden when Rainmeter starts; `ShowZPos=1` brings it above other windows when shown (`-2` = on the desktop); `CloseAction=[!DeactivateConfig]` unloads the skin on close instead of hiding it (slower to reopen).

## Controls

### Mouse

- **Click** a tile to launch it; **wheel** to scroll.
- **Click** a category in the menu to switch to it; clicking the category already open scrolls back to the start.
- The **search bar** at the top left opens the search; the **gear** opens the Options window; the **X** closes the launcher.
- Right click: *Options...*, *Edit Settings.inc*, *Images folder*, *Import games from stores*, *Categories folder*, plus Rainmeter's own menu.

### Keyboard

Keys are only captured **while the launcher is visible**: when it is hidden they work normally in other applications.

| Keys | Action |
| --- | --- |
| `W` `A` `S` `D` / arrows | move the highlight between tiles (the grid scrolls when needed, infinite scroll included) |
| `Space` / `Enter` | launch the highlighted tile (if nothing is highlighted, the first press highlights the first visible tile) |
| `Q` / `E` | previous / next category |
| `F` | open the search |
| `Esc` | close the search, or the launcher |

Mouse and keyboard move the same highlight. Every action has two configurable keys (`NavUp`/`NavUp2`, `NavConfirm`/`NavConfirm2`, ...) using HotKey plugin key names: letters, `UP`, `DOWN`, `LEFT`, `RIGHT`, `SPACE`, `ENTER`, `TAB`, ... `KeyboardNav=0` turns keyboard navigation off. Confirm keys act on **release**, so key repeat and the release itself never reach the game you just launched.

The keys are registered by two invisible mini-skins, `Raintile\Hotkey` (Esc) and `Raintile\Navigation` (everything else), which the launcher activates when shown and deactivates when hidden. Don't load them by hand.

### Gamepad

Xbox and compatible controllers (XInput):

| Button | Action |
| --- | --- |
| `Back` + `Start` (View + Menu) | open / close the launcher (`GamepadToggle`) |
| D-pad / left stick | move the highlight (holding repeats) |
| `A` | launch the highlighted tile |
| `B` | close the search, or the launcher |
| `LB` / `RB` | previous / next category |

Rainmeter cannot read controllers, so a small background helper does it (`Scripts\Helper.ps1`: C# compiled by PowerShell on first start). It polls the controllers every 16 ms at below-normal priority and sends commands to Rainmeter through a Windows message (`WM_COPYDATA`), without starting processes. Only one copy runs: refreshing the skin replaces it, and it exits by itself when Rainmeter is closed. While the launcher is hidden, commands other than open/close are ignored, so it does not interfere with games.

Settings: `Gamepad=0` turns it off; `GamepadToggle` (buttons held together: `A B X Y LB RB BACK START LS RS UP DOWN LEFT RIGHT`), `GamepadDeadZone`, `GamepadRepeatDelay`, `GamepadRepeatRate`. The same helper handles `AutoHide`; with `Gamepad=0` and `AutoHide=0` it does not run at all.

## Search

Click the **Search** bar at the top left, or press `F` (`NavSearch`), and type; press **Enter** to search.

- The grid shows the tiles of **every category** that contain all the typed words, in the tile name, its label or the category name (`games steam` finds Steam tiles in the Games category). Names starting with the first word come first, then the rest alphabetically.
- The first result is already highlighted: `Space`/`Enter` (or gamepad `A`) launches it, WASD/arrows move through the results.
- `Esc`, clicking a category or an empty search go back to the categories, at the position you left them.
- Results use the default grid (`NX`/`NY` in `Settings.inc`).
- The text field is Rainmeter's InputText plugin, which only returns the text on Enter: results do not update while typing.

## Launching a tile

On click the tile expands to full screen (with background and logo at full resolution), stays visible for `LaunchHold` ms, then the launcher hides. The command starts right away, at the beginning of the animation.

| Setting | Default | Effect |
| --- | --- | --- |
| `LaunchAnimation` | `1` | `0` = no animation, hide immediately |
| `LaunchAnimFrames` | `15` | expansion steps of 16 ms (15 ≈ 250 ms) |
| `LaunchHold` | `1500` | ms at full screen before hiding |
| `LaunchLogoSize` | `33%` | final logo size |
| `LaunchFontSize` | `48` | centre text for tiles without a logo |

## Categories and tiles

### Category files

Each `.ini` file in `@Resources\Categories\` is a category; the file name (without `.ini`) identifies it and its image folder `@Resources\Images\<file>\`. To add a category, create a new file (e.g. `Emulators.ini`) and refresh the skin — the folder is re-checked in the background on every load.

```ini
[Category]
Name=Games         ; text in the menu (default: the file name)
Icon=              ; default: Images\Games\icon.png
Order=1            ; position in the menu (default: alphabetical)
NX=4               ; grid of this category (default: NX/NY from Settings.inc)
NY=1
IconSize=12%       ; logo size in this category's tiles (pixels or %)

[Diablo]
Command=steam://rungameid/2344520
```

Every section other than `[Category]` is a tile, in file order. Each category can have its own grid: for example Games `NX=4` `NY=1` (large tiles) and Apps `NX=5` `NY=2`. Tiles resize to fill the screen.

### Tile keys

| Key | Meaning |
| --- | --- |
| *section name* | tile name; also the default name of its images and what search looks at |
| `Command` | what to run on launch (see below) |
| `Label` | text at the bottom left; a tile without images shows its name |
| `Color` | background colour (`R,G,B,A` or `#RRGGBBAA`, see [Colours](#colours)) when there is no background image (empty: taken from the logo with `AutoTileColor=1`, otherwise `TileColor`) |
| `Image` | another name for both images: `Image=diablo4` looks for `background\diablo4.*` and `logo\diablo4.*` |
| `Background` | specific background file (relative to `background\` or absolute; extension optional) |
| `Logo` | specific logo file (relative to `logo\` or absolute) |
| `Source` | written by the importer (`Steam:570`); informational |

### Commands

`Command` accepts:

- a program, with arguments: `"C:\Program Files\App\app.exe" --arg`
- a shortcut: `"C:\Users\Me\Desktop\Game.lnk"` or a `.url` file — the easiest way for any launcher (Steam, Epic, GOG, Battle.net, ...)
- a URL or protocol: `https://github.com`, `steam://rungameid/2344520`, `ms-settings:`
- a folder: `"D:\Downloads"`
- Rainmeter bangs in square brackets: `[!ActivateConfig "Some\Skin"]`

For Steam games the number in the store page address (`store.steampowered.com/app/2344520/...`) is the id for `steam://rungameid/<id>`.

### Images

For the `Games.ini` category:

```
Images\Games\
  icon.png                 menu icon
  background\Diablo.jpg    background of the [Diablo] tile
  logo\Diablo.png          centred logo of the [Diablo] tile
```

Each tile looks for images named after itself, with the extensions `.png`, `.jpg`, `.jpeg`, `.bmp`, `.ico`, `.gif`. Use landscape backgrounds; logos work best as PNG with transparency. You don't need to resize anything: Raintile makes thumbnails at the displayed size (see [How it works](#how-it-works)).

## Importing games from stores

Right click on the launcher > **Import games from stores** (or **Import games** in the Options window). The script (`Scripts\Import.ps1`, in the background) reads the games installed from:

| Store | Source | Images |
| --- | --- | --- |
| Steam | `libraryfolders.vdf` and `appmanifest_*.acf` in every library | local library cache (both the old and the 2024+ layout) |
| Epic Games | launcher manifests (main games only, no DLC or apps) | SteamGridDB |
| GOG Galaxy | registry; launched through Galaxy if installed | SteamGridDB |
| Ubisoft Connect | registry | SteamGridDB |

How the result is written:

- Games go to the end of the `ImportCategory` file (default `Games.ini`), below the line `; ===== IMPORTED AUTOMATICALLY =====`. Everything above it — your hand-written tiles — is never touched.
- The imported block is rebuilt on every import: uninstalled games disappear, new ones appear.
- A game already present among your hand-written tiles (same name or same `Command`) is not imported again. To customise an imported game, move its section above the marker line.
- **Images** for stores other than Steam (and Steam games without local images) are downloaded from [SteamGridDB](https://www.steamgriddb.com/) into `Images\<category>\imported\` if `SteamGridDBKey` holds an API key (free, from the site's preferences). An image you put in `background\<Name>.*` or `logo\<Name>.*` always wins.
- The file is only rewritten if something changed, and the skin only refreshes in that case. The outcome goes to the Rainmeter log (`Raintile: import:` lines).

Settings: `ImportCategory`, `ImportStores` (e.g. `Steam|Epic`), `ImportOnStart=1` to import automatically in the background on every load, `SteamGridDBKey`.

## Options window (WIP)

The **gear** next to the X, or right click > **Options...**, opens the Options window (`Scripts\Options.ps1`, WPF; its look is in `Scripts\Options.xaml`). It is a **work in progress**: it works, but features will still change.

The sections are in the menu on the left; **Keybindings** and **Categories** open into sub-entries (click them again to close them):

| Section | What it holds |
| --- | --- |
| General | area covered (whole screen or work area, monitor), opening and closing behaviour, fade |
| Layout | default grid, scrolling, spacing |
| Menu | category menu, X and gear buttons |
| Appearance | fonts, tile colours, launcher colours |
| Animations | effects, appearing tiles, smoothing, tile launch |
| Backgrounds | background style and its amounts |
| Keybindings > Keyboard | open/close shortcut, close key, navigation keys |
| Keybindings > Gamepad | support, open/close buttons, dead zone, repeat |
| Search | search bar |
| Import | store import settings and **Import games** |
| Advanced | performance, debug log, entries without a page of their own, links to the files |
| Categories | the list of categories: create, open, reorder, delete |
| Categories > *each category* | its name, icon, grid and logo size, and its tiles, with a preview |

- Every setting has a fitting control: switches, sliders (you can also type the value), choices, colour swatches (click to pick; the text field takes `R,G,B,A` or `#RRGGBBAA`), and sizes in **px** or **%** (switching unit converts the number for the main screen).
- **Keybindings**: click a key and press the new one. For the open/close shortcut hold the modifiers (Ctrl, Alt, Shift, Win) and press the key. The **x** next to a key removes it. A key used by two actions is marked in red.
- The arrow next to a setting appears when it differs from the default, and restores it.
- **Categories**: create, delete (to the Recycle Bin) and reorder categories; double-click one (or pick it in the menu) to open it. In a category you edit its name, icon, grid and logo size, and add, delete, reorder and edit tiles (name, command with *Browse...* for `.exe`/`.lnk`/`.url`, label, colour, background, logo). Picked images are copied to `Images\<category>\background|logo\<TileName>.<ext>`; renaming a tile renames its images too. The preview shows the tile as the launcher draws it. Imported games are listed read-only.
- **Save and refresh** (or `Ctrl+S`) writes the files and refreshes the skin. Saving only changes the values: comments and order of `Settings.inc` stay as they were.

The window hides the launcher while open. You can always keep editing the files by hand.

## Settings reference

All settings live in `@Resources\Settings.inc`. Switches are `1` (on) / `0` (off). Sizes marked *(size)* accept pixels or percentages ([see below](#sizes-in-pixels-or-percentages)). After editing the file by hand, refresh the skin.

### Screen

| Setting | Default | Description |
| --- | --- | --- |
| `ScreenX`, `ScreenY`, `ScreenW`, `ScreenH` | `#SCREENAREA...#` | area covered by the launcher. Use `#WORKAREA...#` to keep the taskbar free, or `#SCREENAREAWIDTH@2#` (etc.) for another monitor |

### Grid

| Setting | Default | Description |
| --- | --- | --- |
| `NX`, `NY` | `4`, `2` | default visible tiles: columns × rows (per category: `NX`/`NY` in `[Category]`) |
| `ScrollDir` | `V` | scroll direction: `V` (by rows) or `H` (by columns) |
| `ScrollStep` | `1` | rows/columns per mouse wheel notch |
| `InfiniteScroll` | `1` | after the last row the first comes back (only when the tiles don't all fit) |

### Spacing

| Setting | Default | Description |
| --- | --- | --- |
| `Gap` | `18` | space between tiles *(size)* |
| `PadX`, `PadY` | `40`, `24` | outer margins; they also hold the vertical / horizontal scrollbar *(size)* |
| `IconSize` | `96` | logo box in the tiles (per category: `IconSize` in `[Category]`) *(size)* |
| `LabelPad` | `14` | label margin inside the tile *(size)* |
| `ScrollBarSize` | `4` | scrollbar thickness *(size)* |

### Category menu

| Setting | Default | Description |
| --- | --- | --- |
| `MenuMode` | `IconText` | `IconText`, `Icon` or `Text`; a category without an icon always shows its text |
| `MenuH` | `44` | menu bar height *(size)* |
| `MenuIconSize` | `24` | category icon size *(size)* |
| `MenuIconGap` | `8` | space between icon and text *(size)* |
| `MenuItemPad` | `16` | inner padding of each entry's pill *(size)* |
| `MenuGap` | `6` | space between entries *(size)* |
| `MenuRadius` | `22` | pill corner radius *(size)* |
| `MenuIconDimAlpha` | `150` | opacity of inactive category icons (0-255) |

### Open and close

| Setting | Default | Description |
| --- | --- | --- |
| `OpenHotKey` | `CTRL ALT G` | combination that opens/closes the launcher (HotKey plugin) |
| `CloseAction` | `[!CommandMeasure MeasureScript "Hide()"]` | action of the X; `[!DeactivateConfig]` unloads the skin |
| `CloseSize` | `14` | size of the X and gear buttons |
| `CloseHotKey` | `ESCAPE` | close key, registered only while visible; empty = none |
| `KeyboardNav` | `1` | keyboard navigation |
| `NavUp`, `NavUp2`, `NavDown`, `NavDown2`, `NavLeft`, `NavLeft2`, `NavRight`, `NavRight2` | `W`/`UP`, `S`/`DOWN`, `A`/`LEFT`, `D`/`RIGHT` | movement keys |
| `NavConfirm`, `NavConfirm2` | `SPACE`, `ENTER` | launch the highlighted tile (on release) |
| `NavPrevCategory`, `NavNextCategory` | `Q`, `E` | previous / next category |
| `NavSearch` | `F` | open the search |
| `CloseOnLaunch` | `1` | hide after launching a tile |
| `AutoHide` | `1` | hide on focus loss (click outside, or another program in the foreground) |
| `StartHidden` | `0` | stay hidden when Rainmeter starts |
| `ShowZPos` | `1` | window level when shown: `1` above other windows, `-2` on the desktop, empty = unchanged |

### Tile launch

See [Launching a tile](#launching-a-tile): `LaunchAnimation`, `LaunchAnimFrames`, `LaunchHold`, `LaunchLogoSize` *(size)*, `LaunchFontSize`.

### Animations

All of them only run while something moves.

| Setting | Default | Description |
| --- | --- | --- |
| `AnimOpen` | `1` | tiles appear one after another when the launcher opens |
| `AnimCategory` | `1` | tiles appear again and the menu pill slides on category change |
| `AnimHover` | `1` | the highlight box slides between tiles and fades in/out |
| `AnimScroll` | `1` | smooth mouse wheel scrolling |
| `AnimLogoZoom` | `1` | the logo under the mouse grows by `HoverLogoScale` |
| `HoverLogoScale` | `1.25` | logo zoom factor |
| `LogoGreyscale` | `1` | greyscale logos that turn to colour under the mouse |
| `AnimAppearFrames` | `12` | length of each tile's appearance, in 16 ms steps |
| `AnimStagger` | `2` | delay between one tile and the next, in steps |
| `AnimSlide` | `30` | upward slide while appearing, in pixels |
| `AnimSmooth` | `0.3` | base smoothing (0.05 very smooth/slow, 1 instant), used by the next ones when left empty |
| `AnimScrollSmooth` | `0.15` | smoothing of scrolling |
| `AnimHoverSmooth` | `0.3` | smoothing of the highlight box |
| `AnimPillSmooth` | `0.25` | smoothing of the menu pill |
| `AnimLogoSmooth` | `0.2` | smoothing of logo zoom/colour and background Zoom |

Smooth scrolling uses one extra row (or column) of tiles and Rainmeter's `Container` option to clip them at the edges of the grid, hence Rainmeter 4.5+.

### Tile backgrounds

| Setting | Default | Description |
| --- | --- | --- |
| `BgStyle` | `Pan` | `Crop` fixed centre crop; `Pan` under the mouse the tile slowly slides over the image, then goes back; `Parallax` while scrolling the image moves slower than the tile; `Zoom` under the mouse the background slightly grows |
| `BgOverscan` | `1.15` | how much larger the image is than the tile (room to slide) |
| `BgPanFrames` | `180` | length of the Pan slide in 16 ms steps (≈ 3 s) |
| `BgHoverZoom` | `1.08` | background zoom for `Zoom` |

### Performance

| Setting | Default | Description |
| --- | --- | --- |
| `Thumbnails` | `1` | use thumbnails at the exact displayed size (`0` = original images) |
| `TileHover` | `1` | highlight the tile under the mouse |
| `FadeDuration` | `0` | open/close fade in ms; copied to `Rainmeter.ini`, applies from the next load |

### Gamepad

See [Gamepad](#gamepad): `Gamepad`, `GamepadToggle`, `GamepadDeadZone` (0-32767), `GamepadRepeatDelay`, `GamepadRepeatRate` (ms).

### Search

| Setting | Default | Description |
| --- | --- | --- |
| `SearchW` | `320` | search bar width *(size)* |
| `SearchPlaceholder` | `Search` | text shown in the empty search bar |

### Store import

See [Importing games from stores](#importing-games-from-stores): `ImportCategory`, `ImportStores`, `ImportOnStart`, `SteamGridDBKey`.

### Diagnostics

| Setting | Default | Description |
| --- | --- | --- |
| `DebugLog` | `0` | write to the Rainmeter log what happens on confirm, launch, show/hide and focus loss, and the keys seen by the HotKey plugin |

### Appearance

<a id="colours"></a>Colours can be written as `R,G,B,A` (e.g. `0,210,180,255`; the alpha is optional) or in hex as `#RRGGBBAA` or `#RRGGBB` (e.g. `#00D2B4FF`; the `#` is optional). Alpha is the opacity, 0-255 (`00`-`FF`). The same formats work for `Color=` in the category files.

| Setting | Default | Description |
| --- | --- | --- |
| `ShowLabels` | `1` | show tile labels |
| `FontFace` | `Segoe UI` | font |
| `MenuFontSize`, `LabelFontSize` | `12`, `14` | font sizes (points) |
| `BgColor` | `8,8,12,200` | launcher background |
| `TileColor` | `36,36,44,255` | default tile colour |
| `AutoTileColor` | `1` | tiles with a logo but no background image and no `Color=` get a dark colour taken from the logo's main hue (white/grey logos keep `TileColor`); computed in the background and cached in `Generated\Colors.txt` |
| `HoverColor`, `AccentColor` | `255,255,255,25`, `0,210,180,255` | highlight fill and border/accent |
| `ActiveCategoryColor`, `HoverCategoryColor` | `0,210,180,70`, `255,255,255,20` | menu pills |
| `TextColor`, `TextDimColor` | `240,240,245,255`, `150,150,160,255` | text |
| `ScrollTrackColor`, `ScrollThumbColor` | `255,255,255,25`, `0,210,180,200` | scrollbar |

## Sizes in pixels or percentages

Sizes in `Settings.inc` can be written in pixels (`PadX=40`) or as a percentage of the screen (`PadX=2%`):

- of the **width** for `PadX`, `SearchW`, `MenuItemPad`, `MenuGap`, `MenuIconGap`;
- of the **height** for all the others (`PadY`, `Gap`, `MenuH`, `MenuIconSize`, `MenuRadius`, `IconSize`, `LabelPad`, `ScrollBarSize`, `LaunchLogoSize`), including `IconSize` in category files.

With percentages the same settings work on monitors with different resolutions. Rainmeter does not understand `2%` in its formulas, so the script converts percentages to pixels into `Generated\Sizes.inc` (included after `Settings.inc`) and rewrites it, refreshing the skin, only when a percentage or the resolution changes. Font sizes stay in points.

## How it works

Raintile is designed to be light even on a large full-screen window:

- **No update cycle** (`Update=-1`): the skin does nothing until you click, scroll, hover or press a key. At rest it uses 0% CPU.
- **Loaded once**: opening and closing only show and hide it.
- **Fixed number of meters**: only the visible slots exist (as many as the largest category grid needs), however many tiles you have. Scrolling or switching category only changes the options of existing slots.
- **Only differences**: the script remembers the last value set on each meter and only sends Rainmeter what changed, then updates only those meters.
- **Self-pacing animation clock**: a single ActionTimer clock drives every animation; each step schedules the next only after drawing, so steps never queue up and input stays responsive. It stops as soon as nothing moves.
- **Thumbnails** (`Thumbnails=1`): Rainmeter decodes images at full resolution and rescales them on every draw. Raintile creates copies of backgrounds and logos at the exact displayed size in `Generated\Thumbs\` (`Scripts\Thumbs.ps1`, below-normal priority) and loads those. Right after adding images you see the originals for a few seconds, then the thumbnails take over. They are rebuilt when an image, the resolution, the grid or the background style changes; unused ones are deleted.
- **Generated grid**: the menu and slot meters live in `Generated\Grid.inc`, written by `Raintile.lua`; it is rewritten (with a refresh) when categories or grids change.
- **Category files read once**, on load. The list of files is cached, so the skin draws immediately; the folder is re-checked in the background (RunCommand plugin) and the skin refreshes by itself if it changed.

## File structure

```
Raintile.ini                 main skin (styles, measures, fixed meters)
Hotkey/Hotkey.ini            Esc mini-skin (activated by the launcher)
Navigation/Navigation.ini    navigation keys mini-skin (activated by the launcher)
@Resources/
  Settings.inc               settings
  State.inc                  last category and scroll positions (written by the skin)
  Categories/*.ini           one file per category (menu entry + tiles)
  Images/<category>/         icon.*, background/, logo/, imported/
  Scripts/Raintile.lua       launcher logic
  Scripts/Thumbs.ps1         thumbnail creation
  Scripts/Import.ps1         store import
  Scripts/Helper.ps1         gamepad and focus-loss helper
  Scripts/Options.ps1        Options window
  Scripts/Options.xaml       look of the Options window
  Generated/Grid.inc         generated meters
  Generated/Sizes.inc        percentage sizes and #hex colours converted for Rainmeter
  Generated/Thumbs/          thumbnails (safe to delete: they are rebuilt)
  Generated/Colors.txt       tile colours taken from logos (AutoTileColor)
```

## Troubleshooting

- **First stop: the Rainmeter log** (*Manage* > *Log*). Raintile's messages start with `Raintile:`. Set `DebugLog=1` for more detail.
- **Esc, keyboard navigation or the gamepad don't work after an update**: in Rainmeter use **Refresh all** (not just *Refresh skin*) so it sees new or renamed mini-skins and scripts. Check that the HotKey plugin is installed.
- **A category icon doesn't show**: the icon goes in `Images\<file name>\icon.png` — the folder is named after the category *file* (`Games`), not its menu label. The log shows exactly where it looked (`Raintile: no icon for category ...`).
- **A tile image doesn't show**: check the file name matches the tile name (or its `Image`/`Background`/`Logo` key); explicit names that are not found are logged.
- **The Options window doesn't open, or shows an error**: errors are shown in a message box and written to `Generated\Options.log`. It needs Windows PowerShell 5.1 (included in Windows 10/11).
- **Imported games are missing images**: only Steam has local images; for the other stores set `SteamGridDBKey`. Import messages are in the log (`Raintile: import:`).
- **Thumbnails are not created**: they are made by PowerShell in the background; errors are listed in the log. Deleting `Generated\Thumbs\` forces a rebuild.
- **Slow or choppy animations on very large screens**: every animation step redraws the whole full-screen window. Turn off the heaviest ones (`AnimScroll`, `BgStyle=Crop`), lower `AnimAppearFrames`/`LaunchAnimFrames` or raise the `Anim*Smooth` values.

## Known limitations

- **Text input** goes through Rainmeter's InputText plugin: search results only appear after Enter.
- **Focus loss** (`AutoHide`) is detected only while the launcher is above other windows (`ShowZPos=1`, the default), not when it sits on the desktop (`-2`).
- **Icons from `.exe` files** cannot be extracted by Rainmeter: provide an image.
- **Non-ASCII characters** (accents, etc.) in category names and labels may display incorrectly: category files are read as UTF-8.
- **Store import** does not cover Battle.net, EA app and Xbox/Microsoft Store yet; use `.lnk` shortcuts for those.
- **Fonts** sizes cannot be percentages.
- **Options window** is a work in progress.
