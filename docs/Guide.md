# Raintile Guide

Complete reference for Raintile. For a presentation and installation steps see the [README](../README.md).

## Contents

- [Opening and closing](#opening-and-closing)
- [Controls](#controls)
  - [Mouse](#mouse)
  - [Keyboard](#keyboard)
  - [Gamepad](#gamepad)
- [Search](#search)
- [Tile menu](#tile-menu)
- [Favorites and Recent](#favorites-and-recent)
- [Tags and filter bar](#tags-and-filter-bar)
- [Play time](#play-time)
- [Launching a tile](#launching-a-tile)
- [Categories and tiles](#categories-and-tiles)
  - [Category files](#category-files)
  - [Tile keys](#tile-keys)
  - [Commands](#commands)
  - [Images](#images)
- [Adding games and apps](#adding-games-and-apps)
  - [Games no longer installed](#games-no-longer-installed)
- [Options window](#options-window)
- [Your data and updates](#your-data-and-updates)
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
- Right click: *Options...*, *Edit Settings.inc*, *Images folder*, *Add games and apps...*, *Categories folder*, plus Rainmeter's own menu. On a tile, also the [tile menu](#tile-menu).

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

Click the **Search** bar at the top left, or press `F` (`NavSearch`), and type: the results follow every key.

- The grid shows the tiles of **every category** that contain all the typed words, in the tile name, its label, the category name, its store or its [tags](#tags-and-filter-bar) (`games steam` finds Steam tiles in the Games category, `coop` the tiles tagged coop). Above the results, the [filter bar](#tags-and-filter-bar) narrows them down with a click. Names starting with the first word come first, then the rest alphabetically. Favorites and Recent are left out (their tiles are in the other categories).
- While typing, letters, digits (keypad too), space, `-` and `.` go into the search and `Backspace` deletes; the other keys of the launcher are off. **Enter** stops typing and keeps the results; the first one is highlighted: `Space`/`Enter` (or gamepad `A`) launches it, WASD/arrows move through the results.
- `Esc`, clicking a category or an empty search go back to the categories, at the position you left them.
- Results use the default grid (`NX`/`NY` in `Settings.inc`).
- The keys are taken by the `Raintile\Typing` mini-skin (HotKey plugin), active only while you type.

## Tile menu

Right click on a tile adds, after Raintile's own entries, the ones that apply to it:

| Entry | What it does |
| --- | --- |
| **Edit \<tile\>...** | opens the tile in the Options window |
| **Add to / Remove from Favorites** | see [Favorites and Recent](#favorites-and-recent) |
| **Open file location** | opens the folder of the program, with the file selected (only for commands that are a file on this PC) |
| **Run as administrator** | starts the program as administrator; Windows asks for confirmation (only for `.exe`, `.lnk`, `.bat`, `.cmd`) |
| **Remove from \<category\>...** | removes the tile from its category file, after asking; its images stay in `Images\` |

*Run as administrator* and *Remove* go through `Scripts\TileAction.ps1`, which reads the tile's command from its category file.

## Favorites and Recent

Two categories at the start of the menu, made of the tiles of the others:

- **Favorites**: the tiles you add with right click > **Add to Favorites**, in the order you added them.
- **Recent**: the tiles you launched lately (`RecentOrder=Recent`) or most often (`MostUsed`), up to `RecentCount`.

They are kept in your data folder (`Favorites.txt`, `Usage.txt`); turn them off with `ShowFavorites=0` / `ShowRecent=0` (Options > Menu).

## Tags and filter bar

- **Tags**: give a tile tags with `Tags=` in its category file, separated by commas (`Tags=multiplayer, coop`), or in Options > *the category* > *the tile* > **Tags**, where the tags already used elsewhere are one click away. [Search](#search) finds them: typing `coop` lists the tiles tagged coop.
- **Filter bar**: while the search results are shown, a row of chips appears above them (the grid moves down to make room) — one per tag (`#coop`) and, with `FilterStores=1`, one per store when your tiles come from at least two (Steam, Epic Games, GOG, Ubisoft, Battle.net, EA, Xbox). Outside the search there is no bar, and the grid keeps all the space.
- A click turns a chip on or off; you can turn on more than one. The results shown are those of **one of** the selected stores (if any) that have **all** the selected tags; **All** turns everything off. To see every tile of a store, or with a tag, search for it (`steam`, `coop`) or type a letter and use the chips. Leaving the search clears the filter.
- The store of a tile is taken from `Store=` if it has it, otherwise from `Source=` (written when a game is added from Import) or from the command (`steam://`, the Epic launcher link, GOG Galaxy, `uplay://`, Battle.net, EA).
- `FilterBar=0` turns the bar off.

Settings (Options > Menu > Filter bar): `FilterBar`, `FilterStores`, `FilterH`, `FilterGap`, `FilterPad`, `FilterFontSize`.

## Play time

A small line at the top left of the tile tells how long you played and when you last did: `123 h played - 3 days ago`.

- **Steam games**: the hours played and the last launch come from Steam itself (`userdata\<account>\config\localconfig.vdf`, every account that logged in on this PC), read in the background (`Scripts\Playtime.ps1`) when the skin loads and, at most once a minute, when the launcher opens. The game is recognised by its `steam://rungameid/<id>` command or by `Source=Steam:<id>`.
- **Other tiles**: the last launch counted by Raintile (`Usage.txt`), as `Last played yesterday`.
- `TileInfo=Hover` (default) shows it only on the highlighted tile (mouse, keyboard or gamepad), `Always` on every tile, `Never` hides it. Size: `InfoFontSize`. Options > Appearance > Text.
- Tiles of [games no longer installed](#games-no-longer-installed) always show **Not installed**.

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

Each `.ini` file in `Categories\` of [your data folder](#your-data-and-updates) is a category; the file name (without `.ini`) identifies it and its image folder `Images\<file>\`. To add a category, create a new file (e.g. `Emulators.ini`) and refresh the skin — the folder is re-checked in the background on every load.

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
| `BgFocus` | framing of the background: the point of the image kept at the centre of the tile, `X,Y` in % of its width and height (default `50,50`); see [Framing a background](#framing-a-background) |
| `BgZoom` | framing of the background: enlargement beyond filling the tile, `1` to `4` (default `1`) |
| `LogoPos` | where the centre of the logo goes, `X,Y` in % of the tile's width and height (default `50,50`); see [Placing the logo](#placing-the-logo) |
| `LogoScale` | size of the logo, times the category's `IconSize`, `0.25` to `3` (default `1`) |
| `Source` | where an added game or app comes from (`Steam:570`): gives its store to the [filter bar](#tags-and-filter-bar) and the Steam id to the [play time](#play-time) |
| `Tags` | tags of the tile, separated by commas (`multiplayer, co-op`): found by search, chips of the [filter bar](#tags-and-filter-bar) |
| `Store` | store shown in the filter bar (`Steam`, `Epic Games`, `GOG`, ...), when it cannot be told from `Source` or the command |

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
  logo\Diablo.png          logo of the [Diablo] tile, centred
```

Each tile looks for images named after itself, with the extensions `.png`, `.jpg`, `.jpeg`, `.bmp`, `.ico`, `.gif`. Use landscape backgrounds; logos work best as PNG with transparency. You don't need to resize anything: Raintile makes thumbnails at the displayed size (see [How it works](#how-it-works)).

### Framing a background

A background fills its tile and, by default, is cropped at the centre. When the subject is off-centre, or the image is much wider or taller than the tile, choose the part to show in Options > *the category* > *the tile* > **Framing** (or right click on the tile > **Edit \<tile\>...**): drag the background in the preview to move the image, zoom with the mouse wheel (it zooms on the point under the mouse) or the slider, and **Reset** to go back to the centre. The preview has the proportions of this category's tiles on this screen.

The framing is saved in the tile as `BgFocus` (the point kept at the centre, in % of the image) and `BgZoom`. Both are relative, so it holds when the resolution, the margins or the grid change: only the edges of the image limit it. With the sliding styles (`BgStyle` `Pan`, `Parallax`, `Zoom`) the tile starts from the framed part and moves within `BgOverscan` of it, instead of across the whole image. Choosing or removing the background resets the framing. The launch animation still shows the whole image.

### Placing the logo

The logo is centred in its tile and as large as the category's `IconSize`. To move it, drag the logo itself in the same preview (Options > *the category* > *the tile*); to resize it, use the mouse wheel over it or the **Logo** slider, and **Reset** to centre it again at its normal size. It is independent of the framing: the background and the logo move separately.

The placement is saved in the tile as `LogoPos` (where the centre of the logo goes, in % of the tile) and `LogoScale` (times the category's logo size). Both are relative, so the logo keeps its place when the resolution or the grid change. What is visible of the logo always stays inside the tile, also while it grows under the mouse: pushed into a corner, it stays in the corner at any size. The launch animation starts from where the logo is and brings it to the centre of the screen.

## Adding games and apps

Right click on the launcher > **Add games and apps...**, or **Import** in the Options window, shows what is installed on this PC. Nothing is added by itself: tick the games and apps you want and press **Add selected**. They become normal tiles, which you can edit, move and keep even after uninstalling.

The search (`Scripts\Scan.ps1`, in the background) looks in:

| Source | How | Launched with | Images |
| --- | --- | --- | --- |
| Steam | `libraryfolders.vdf` and `appmanifest_*.acf` in every library | `steam://rungameid/<id>` | local library cache (old and 2024+ layout) |
| Epic Games | launcher manifests (main games only, no DLC or apps) | Epic launcher link | SteamGridDB |
| GOG Galaxy | registry | Galaxy, or the game exe | SteamGridDB |
| Ubisoft Connect | registry | `uplay://launch/<id>` | SteamGridDB |
| Battle.net | uninstall entries of its games | Battle.net (`--exec="launch <code>"`), or the game's launcher | SteamGridDB |
| EA app | uninstall entries of Electronic Arts games | the game exe | SteamGridDB |
| Xbox / Microsoft Store | Store packages with a `MicrosoftGame.config` | `shell:AppsFolder` | SteamGridDB |
| Apps | Start menu: program shortcuts and Store apps, without uninstallers, help files and the games already found | the shortcut / `shell:AppsFolder` | the program's own icon (as logo) |

- **The list** shows the cover (Steam) or the icon of each item, with its source, and marks the new ones. Filter by type (All, Games, Apps) or by name; *Show added* also lists what is already in the launcher (dimmed, with its category); *Covers* off gives a compact text list.
- **Where they go**: by type (games to `ImportCategory`, apps to `AppsCategory`; the category is created if missing) or all to one category.
- **Images** are copied to the category folders, named after the tile: the Steam cover and logo, the program icon for apps. For games without local images, background and logo are downloaded from [SteamGridDB](https://www.steamgriddb.com/) if `SteamGridDBKey` holds an API key (free, from the site's preferences). Set the key in Options > Import: it is saved encrypted with Windows DPAPI (`SteamGridDBKey=dpapi:...`), so only your Windows user on this PC can read it; a key written in clear in `Settings.inc` is encrypted the next time the Options window opens.
- Something already in the launcher, in any category (same name or same command), is not listed again.
- **New ones**: with `ScanOnStart=1` the search runs in the background on every skin load; if it finds games or apps you have not seen in the list yet, a dot lights up on the gear, and on **Import** in the menu of the Options window. A click on it opens the list.
- **Games no longer installed** are reported by the same search (see below).
- The added tiles are written at once; **Save and refresh** shows them in the launcher.
- **Older versions** imported games automatically, in a block below the line `; ===== IMPORTED AUTOMATICALLY =====`. Opening **Import** turns those games into normal tiles, once.

Settings: `ImportStores` (e.g. `Steam|Epic|Apps`), `ScanOnStart`, `ImportCategory`, `AppsCategory`, `SteamGridDBKey`.

### Games no longer installed

The same search also checks your tiles. A tile is reported when:

- its command points to a game of a store that was searched and is installed, and the game is not there any more: Steam (`steam://rungameid/<id>`), Epic Games (launcher link), GOG Galaxy (`/gameId=`), Ubisoft Connect (`uplay://launch/<id>`), Store apps and Xbox games (`shell:AppsFolder\...`);
- or its command is a program file (`.exe`, `.lnk`, `.bat`, `.cmd`, `.url`) that no longer exists.

Nothing is reported when it cannot be told: a store that is not installed or not searched, a Steam library or a drive that is not connected (USB, network), URLs, folders, bangs, Battle.net games.

Reported tiles are **greyed out** in the launcher, say **Not installed** and do not start: a click opens Options > **Import**. They light the dot on the gear and on **Import** in the menu of the Options window. At the top of Import, **No longer installed** lists them: **Remove** takes the tile out of its category (its images stay in `Images\`), **Keep** leaves it as it is and stops reporting it (`KeepMissing.txt` in the data folder). The list is in `Generated\Missing.txt`.

## Options window

The **gear** next to the X, or right click > **Options...**, opens the Options window (`Scripts\Options.ps1`, WPF; its look is in `Scripts\Options.xaml`). Right click on a tile > **Edit \<tile\>...** (the last of Raintile's entries, shown only on a tile) opens it on that tile, ready to edit or frame.

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
| Import | the games and apps found on this PC, to add; where to look and where they go |
| Advanced | performance, debug log, entries without a page of their own |
| Categories | the list of categories (create, open, reorder, delete) and the settings of the selected one: name, icon, grid, logo size |
| Categories > *each category* | its tiles, with a preview: edit, frame the background, move to another category, turn imported games into normal tiles |
| Info (at the bottom) | version and updates, your data folder, skin folder, number of categories and tiles; buttons to open `Settings.inc`, the folders, Rainmeter's Manage window and this Guide |

- Every setting has a fitting control: switches, sliders (you can also type the value), choices, colour swatches (click to pick; the text field takes `R,G,B,A` or `#RRGGBBAA`), and sizes in **px** or **%** (switching unit converts the number for the main screen).
- **Keybindings**: click a key and press the new one. For the open/close shortcut hold the modifiers (Ctrl, Alt, Shift, Win) and press the key. The **x** next to a key removes it. A key used by two actions is marked in red.
- The arrow next to a setting appears when it differs from the default, and restores it.
- **Categories**: create, delete (to the Recycle Bin) and reorder categories, and edit the name, icon, grid and logo size of the selected one. Double-click a category (or pick it in the menu) to see its tiles: add, delete, reorder and edit them (name, command with *Browse...* for `.exe`/`.lnk`/`.url`, label, colour, background, logo). Picked images are copied to `Images\<category>\background|logo\<TileName>.<ext>`; renaming a tile renames its images too. The preview shows the tile as the launcher draws it.
  - **Move to**: moves a tile, and its images, to another category; both category files are saved at once.
  - **Imported games** are shown read-only. **Make it a normal tile** turns one into a hand-written tile: its images are copied to the category folders, and the import will not add it again.
- **Save and refresh** (or `Ctrl+S`) writes the files and refreshes the skin; a progress bar covers the window for 2.5-3.5 seconds, then the window closes, the skin refreshes and the launcher shows itself once reloaded. Saving only changes the values: comments and order of `Settings.inc` stay as they were.

The window hides the launcher while open. You can always keep editing the files by hand.

## Your data and updates

### Where your data is

Your settings, categories, images and positions are kept in **`%APPDATA%\Rainmeter\Raintile\`** (Rainmeter's `#SETTINGSPATH#Raintile\`), not in the skin folder:

```
Settings.inc      your settings (every key, with its comments)
State.inc         last category and scroll positions
Categories\*.ini  your categories and tiles
Images\           their icons, backgrounds and logos
Favorites.txt     your favorite tiles
Usage.txt         how many times and when each tile was launched (Recent)
Seen.txt          games and apps already shown in the Import list
Update.json       result of the last update check
```

Installing an update replaces the skin folder, so nothing of yours may live there. The files in the skin's `@Resources\` (`Settings.inc`, `Categories\`, `Images\`) are the defaults: the first time, `Scripts\Data.ps1` copies them to the data folder — or, when updating from a version that kept them in the skin folder, copies your own from the backup the installer has just made (`Skins\@Backup\Raintile\`). Right click > *Categories folder*, *Images folder* and *Edit Settings.inc*, and Options > Info, open the data folder.

**Back up and restore**: Options > Info > *Backup* saves the whole data folder as a zip (*Back up...*) and puts a backup back (*Restore...*). Restoring never deletes your current data: it is moved to a folder next to it (`Raintile.before-restore-<date>`), and put back if something goes wrong. A backup also moves your launcher to another PC; the SteamGridDB key in it only works for the same Windows user.

When an update adds settings, they are added to your `Settings.inc` with their default value (and settings it removes go), keeping your values; this happens by itself on the first load after the update. To start over from the defaults, delete the data folder and refresh the skin.

### Updates

> **Experimental**: installing updates from the Options window is still being tested and could cause problems. Before installing, keep a copy of your data folder (Options > Info > *Your data*); if something goes wrong, install the package from the [releases page](https://github.com/Derek3rd/raintile/releases) by hand.

With `CheckUpdates=1` (Options > Advanced) the skin asks GitHub for the latest release at most once a day, in the background. When there is a newer version a dot lights up on the gear (the same dot used for new games and apps) and on **Info** in the menu of the Options window; a click opens Options > **Info**, which shows the installed and the latest version and the release notes:

- **Download and install** downloads the release's `.rmskin` and opens it with the Rainmeter installer; the Options window closes. Keep the installer's default options. Your data is not touched. Only files of this repository's releases on GitHub (https) are downloaded, into a new temporary folder, and the file is checked to be a Rainmeter package before it is opened.
- **Check now** asks GitHub again; **Release page** opens the release on GitHub.

### Publishing a release

1. Set the new version in `Version=` in the `[Metadata]` of `Raintile.ini` and merge it.
2. On GitHub, **Releases > Draft a new release**: tag with the same number, like **`v1.0.3`**, on `main`; write the notes and publish.
3. The **Release package** workflow (`.github/workflows/release.yml`) builds the `.rmskin` with `tools/build_rmskin.py` and attaches it to the release by itself, within a minute or two. If the tag and `Version=` differ, it stops and attaches nothing.

For the update check the tag must hold the version (if it has no number, the number in the release title is used, e.g. "1.0.1 - ..."), and the `.rmskin` must be attached (otherwise *Download and install* opens the release page). The package can also be built by hand: `python tools/build_rmskin.py` writes it to `dist\`; *Actions > Release package > Run workflow* builds it as a downloadable artifact.

The package holds the skin only (with the HotKey plugin from `tools/plugins/`): `README.md`, `docs\` and `tools\` stay on GitHub (Options > Info opens the Guide there).

In the package no *VariableFiles* are needed (settings are in the data folder) and the installer's default backup should be kept: the first update to this version recovers the user's categories and images from that backup.

## Settings reference

All settings live in `Settings.inc` in [your data folder](#your-data-and-updates) (right click > *Edit Settings.inc*); `@Resources\Settings.inc` holds the defaults. Switches are `1` (on) / `0` (off). Sizes marked *(size)* accept pixels or percentages ([see below](#sizes-in-pixels-or-percentages)). After editing the file by hand, refresh the skin.

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
| `ShowFavorites`, `ShowRecent` | `1`, `1` | the [Favorites and Recent](#favorites-and-recent) categories |
| `RecentOrder` | `Recent` | `Recent` (last launched first) or `MostUsed` |
| `RecentCount` | `12` | tiles in Recent |
| `FilterBar` | `1` | the [filter bar](#tags-and-filter-bar) above the search results |
| `FilterStores` | `1` | a chip per store (only with tiles from at least two stores) |
| `FilterH`, `FilterGap`, `FilterPad` | `30`, `6`, `12` | chip height, space between chips, inner padding *(size)* |
| `FilterFontSize` | `10` | chip font size (points) |

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

### Games and apps

See [Adding games and apps](#adding-games-and-apps): `ImportStores`, `ScanOnStart`, `ImportCategory`, `AppsCategory`, `SteamGridDBKey`.

### Updates

| Setting | Default | Description |
| --- | --- | --- |
| `CheckUpdates` | `1` | check GitHub for a newer version, at most once a day ([see above](#updates)) |

### Diagnostics

| Setting | Default | Description |
| --- | --- | --- |
| `DebugLog` | `0` | write to the Rainmeter log what happens on confirm, launch, show/hide and focus loss, and the keys seen by the HotKey plugin |

### Appearance

<a id="colours"></a>Colours can be written as `R,G,B,A` (e.g. `0,210,180,255`; the alpha is optional) or in hex as `#RRGGBBAA` or `#RRGGBB` (e.g. `#00D2B4FF`; the `#` is optional). Alpha is the opacity, 0-255 (`00`-`FF`). The same formats work for `Color=` in the category files.

| Setting | Default | Description |
| --- | --- | --- |
| `ShowLabels` | `1` | show tile labels |
| `TileInfo` | `Hover` | [play time](#play-time) line on the tiles: `Hover` (highlighted tile), `Always` or `Never` |
| `InfoFontSize` | `10` | its font size (points) |
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
- **Thumbnails** (`Thumbnails=1`): Rainmeter decodes images at full resolution and rescales them on every draw. Raintile creates copies of backgrounds and logos at the exact displayed size in `Generated\Thumbs\` (`Scripts\Thumbs.ps1`, below-normal priority) and loads those. Right after adding images you see the originals for a few seconds, then the thumbnails take over. They are rebuilt when an image, its framing, the resolution, the grid or the background style changes; unused ones are deleted.
- **Generated grid**: the menu and slot meters live in `Generated\Grid.inc`, written by `Raintile.lua`; it is rewritten (with a refresh) when categories or grids change.
- **Category files read once**, on load. The list of files is cached, so the skin draws immediately; the folder is re-checked in the background (RunCommand plugin) and the skin refreshes by itself if it changed.

## File structure

```
Raintile.ini                 main skin (styles, measures, fixed meters)
Hotkey/Hotkey.ini            Esc mini-skin (activated by the launcher)
Navigation/Navigation.ini    navigation keys mini-skin (activated by the launcher)
Typing/Typing.ini            keys typed in the search bar (activated while typing)
@Resources/
  Settings.inc               default settings (yours are in the data folder)
  State.inc                  default positions
  Categories/*.ini           default categories, copied to the data folder the first time
  Images/<category>/         their icons, backgrounds and logos
  Icons/                     icons of Favorites and Recent
  Scripts/Data.ps1           prepares the data folder
  Scripts/TileAction.ps1     tile menu: run as administrator, remove
  Scripts/Update.ps1         update check
  Scripts/Raintile.lua       launcher logic
  Scripts/Thumbs.ps1         thumbnail creation
  Scripts/Scan.ps1           search of the installed games and apps, and of the tiles no longer installed
  Scripts/Playtime.ps1       play time of the Steam games
  Scripts/Helper.ps1         gamepad and focus-loss helper
  Scripts/Options.ps1        Options window
  Scripts/Options.xaml       look of the Options window
  Generated/Grid.inc         generated meters
  Generated/Sizes.inc        percentage sizes and #hex colours converted for Rainmeter
  Generated/Thumbs/          thumbnails (safe to delete: they are rebuilt)
  Generated/Colors.txt       tile colours taken from logos (AutoTileColor)
  Generated/Area.txt         grid area in pixels, for the framing preview of Options
  Generated/EditTile.txt     tile to open Options on (Edit this tile), removed once read
  Generated/Found.json       games and apps found by the last search
  Generated/Found/           their icons
  Generated/Missing.txt      tiles of games no longer installed (last search)
  Generated/Playtime.txt     play time of the Steam games
```

The data folder (`%APPDATA%\Rainmeter\Raintile\`) is described in [Where your data is](#where-your-data-is).

## Troubleshooting

- **First stop: the Rainmeter log** (*Manage* > *Log*). Raintile's messages start with `Raintile:`. Set `DebugLog=1` for more detail.
- **Esc, keyboard navigation or the gamepad don't work after an update**: in Rainmeter use **Refresh all** (not just *Refresh skin*) so it sees new or renamed mini-skins and scripts. Check that the HotKey plugin is installed.
- **A category icon doesn't show**: the icon goes in `Images\<file name>\icon.png` — the folder is named after the category *file* (`Games`), not its menu label. The log shows exactly where it looked (`Raintile: no icon for category ...`).
- **A tile image doesn't show**: check the file name matches the tile name (or its `Image`/`Background`/`Logo` key); explicit names that are not found are logged.
- **The Options window doesn't open, or shows an error**: errors are shown in a message box and written to `Generated\Options.log`. It needs Windows PowerShell 5.1 (included in Windows 10/11).
- **The Options window is slow to open**: the first time (and after an update) it prepares a small helper, `Generated\RaintileOptions-*.dll`, so later openings are faster. `Generated\Options-startup.log` lists how long each step of the last opening took.
- **Your categories are gone after an update**: they are copied from `Skins\@Backup\Raintile\@Resources\` the first time the new version loads; if the backup option was turned off in the installer, copy `Categories\` and `Images\` from your old copy into the data folder by hand.
- **The update check fails**: Options > Info shows the error (no connection, GitHub not reachable). It is retried on the next load after a day, or with *Check now*.
- **Added games are missing images**: only Steam has local images; for the other stores set `SteamGridDBKey` before adding them. With `DebugLog=1` the search writes what it found per store to the log (`Raintile: scan:` lines).
- **A tile is greyed out but the game is installed**: it was reported as [no longer installed](#games-no-longer-installed). Check that its store is ticked in Import > *Where to look* and press *Search again*, or press **Keep** in Import.
- **No play time on a Steam tile**: its command must be `steam://rungameid/<id>` (or the tile must have `Source=Steam:<id>`), and Steam must have recorded time for the account you play with; with `TileInfo=Hover` it only shows on the highlighted tile.
- **A game or app is not in the list**: check that its source is ticked in Import > *Where to look*, then *Search again*. Anything else can always be added by hand with its `.lnk` shortcut.
- **Thumbnails are not created**: they are made by PowerShell in the background; errors are listed in the log. Deleting `Generated\Thumbs\` forces a rebuild.
- **Slow or choppy animations on very large screens**: every animation step redraws the whole full-screen window. Turn off the heaviest ones (`AnimScroll`, `BgStyle=Crop`), lower `AnimAppearFrames`/`LaunchAnimFrames` or raise the `Anim*Smooth` values.

## Known limitations

- **Search** takes letters, digits, space, `-` and `.`: accented letters and other characters can not be typed in it.
- **Focus loss** (`AutoHide`) is detected only while the launcher is above other windows (`ShowZPos=1`, the default), not when it sits on the desktop (`-2`).
- **Icons from `.exe` files** cannot be extracted by Rainmeter: provide an image.
- **Non-ASCII characters** (accents, etc.) in category names and labels may display incorrectly: category files are read as UTF-8.
- **Battle.net, EA app and Xbox** games are found through Windows' list of installed programs and Store packages: a game installed in an unusual way may be missing (add its shortcut by hand). Battle.net games without a known product code open through their own launcher.
- **Fonts** sizes cannot be percentages.
