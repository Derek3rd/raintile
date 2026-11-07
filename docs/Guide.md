# Raintile Guide

Complete reference for Raintile. For a presentation and installation steps see the [README](../README.md).

## Contents

- [Opening and closing](#opening-and-closing)
  - [Full screen, window or docked](#full-screen-window-or-docked)
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
- [Widgets and the Dashboard](#widgets-and-the-dashboard)
  - [Widgets](#widgets)
  - [Temperatures and fans](#temperatures-and-fans)
  - [Skins in a tile](#skins-in-a-tile)
  - [Custom widgets](#custom-widgets)
  - [Widget gallery](#widget-gallery)
- [Categories and tiles](#categories-and-tiles)
  - [Category files](#category-files)
  - [Tile keys](#tile-keys)
  - [Tiles of more cells](#tiles-of-more-cells)
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
| Losing focus: a click outside the launcher (e.g. on a second monitor) or another program coming to the foreground (`AutoHide=1`; not as a window) | | ✓ |
| Docked: the mouse resting on that edge of the screen (`DockEdge=1`) | ✓ | |

Without the HotKey plugin you can toggle it from a Windows shortcut: create a shortcut with this target and assign it a *Shortcut key* in its properties:

```
"C:\Program Files\Rainmeter\Rainmeter.exe" !CommandMeasure MeasureScript "Toggle()" "Raintile"
```

### Full screen, window or docked

`LauncherMode` (Options > General > Screen) sets how the launcher shows on its area (`ScreenX/Y/W/H`, a monitor or its work area):

- **Fullscreen** (default): all of the area.
- **Window**: a window of `WindowW` x `WindowH` (pixels or % of the area), centred the first time. Drag an empty part of it (the background, the space around the menu) to move it: it stays where you put it. It does not hide when another program gets the focus; close it with the X, `Esc` or the shortcut.
- **Dock**: on a side of the screen (`DockSide`: `Left`, `Right`, `Top`, `Bottom`), `DockSize` wide (left and right) or tall (top and bottom). It comes in from that side, sliding and fading, and goes back the same way; it hides when you click outside it (`AutoHide`). With `DockEdge=1` it also opens when the mouse rests on that edge of the screen for `DockEdgeDelay` ms, but not while a full-screen program (a game, a video) is in front; move the mouse away from the edge to open it again from there.

Sizes in percent (margins, menu, fonts) are of the area, not of the window, so they stay the same in every mode.

**Compact menu**: when the categories do not all fit in the menu (a narrow window, a launcher docked left or right, or just many categories) the clock, Favorites/Recent/Not played yet, the search, the power button and the gear move into a list opened by the **☰** button at the top left (with the time and date at its top). The categories stay in a strip between it and the X: scroll it with the wheel; its edges fade where more categories are hidden, and it follows the active one. *Search* in that list opens the search bar in the place of the categories.

Related settings: `StartHidden=1` keeps the launcher hidden when Rainmeter starts; `ShowZPos=1` brings it above other windows when shown (`-2` = on the desktop); `CloseAction=[!DeactivateConfig]` unloads the skin on close instead of hiding it (slower to reopen).

## Controls

### Mouse

- **Click** a tile to launch it; **wheel** to scroll.
- **Click** a category in the menu to switch to it; clicking the category already open scrolls back to the start.
- The **search bar** at the top left opens the search; the **gear** opens the Options window; the **X** closes the launcher.
- The **power button**, left of the gear (`ShowPower`), opens **Lock**, **Sleep**, **Restart** and **Shut down**; Restart and Shut down want a second click on the same entry, which says so. The launcher hides first. `Esc` closes the menu.
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
| `Y` (`GamepadSearch`) | search with the on-screen keyboard |
| `LT` / `RT` | with search results: the previous / next filter chip, alone |
| `RS`, the right stick click (`GamepadOptions`) | open the [Options window](#options-window), as the gear |

**On-screen keyboard**: `GamepadSearch` opens the search with a keyboard at the bottom of the screen (letters, digits, `-` and `.`, Delete, Space, Done). The D-pad or stick moves on it, `A` types the key, `X` deletes, `Start` (or *Done*) closes it and keeps the results (the first one highlighted, `A` launches it), `B` closes the search. The keys can be clicked with the mouse too. `Start` is also part of `GamepadToggle`: alone it counts when released, so `Back` + `Start` still opens and closes the launcher.

Rainmeter cannot read controllers, so a small background helper does it (`Scripts\Helper.ps1`: C# compiled by PowerShell on first start). It polls the controllers every 16 ms at below-normal priority and sends commands to Rainmeter through a Windows message (`WM_COPYDATA`), without starting processes. Only one copy runs: refreshing the skin replaces it, and it exits by itself when Rainmeter is closed. While the launcher is hidden, commands other than open/close are ignored, so it does not interfere with games.

The [Options window](#options-window) can be used with the controller too.

Settings: `Gamepad=0` turns it off (in the Options window too); `GamepadSearch` and `GamepadOptions` (one or more buttons, or none; on `X`, `LT` or `RT` they take their place, and `GamepadOptions` does nothing on a button of `GamepadSearch` or `GamepadToggle`), `GamepadToggle` (buttons held together: `A B X Y LB RB BACK START LS RS UP DOWN LEFT RIGHT`), `GamepadDeadZone`, `GamepadRepeatDelay`, `GamepadRepeatRate`. The same helper handles `AutoHide`; with `Gamepad=0` and `AutoHide=0` it does not run at all.

## Search

At the top left, after the [clock](#clock) and the Favorites / Recent buttons, the search bar is just a magnifier: it opens when the mouse is over it (`SearchHover=0` keeps it always open). Click it, or press `F` (`NavSearch`), and type: the results follow every key. It stays open while you type and while the results are shown.

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
| **Pin to the start / Unpin** | keeps the tile at the start of its category, before the others, also when the category is sorted (`Pinned=1`) |
| **Open file location** | opens the folder of the program, with the file selected (only for commands that are a file on this PC) |
| **Run as administrator** | starts the program as administrator; Windows asks for confirmation (only for `.exe`, `.lnk`, `.bat`, `.cmd`) |
| **Remove from \<category\>...** | removes the tile from its category file, after asking; its images stay in `Images\` |

*Run as administrator* and *Remove* go through `Scripts\TileAction.ps1`, which reads the tile's command from its category file.

## Favorites and Recent

Three categories made of the tiles of the others. They are not in the category menu: they are the icon buttons right of the [clock](#clock) (the star, the clock and the play sign); hover one to see its name, click it to open it. The open one is lit like a menu entry. `Q`/`E` and the gamepad `LB`/`RB` reach them too, before the first category.

- **Favorites**: the tiles you add with right click > **Add to Favorites**, in the order you added them.
- **Not played yet**: the tiles never launched (from Raintile, or with play time on Steam or [measured](#play-time)), the ones added last first: tiles added in the Options window remember the day (`Added=`). Up to `UnplayedCount`; `ShowUnplayed=0` turns it off.
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

A small line on the tile (at the top left unless you move it) tells how long you played and when you last did: `123 h played - 3 days ago`.

- **Steam games**: the hours played and the last launch come from Steam itself (`userdata\<account>\config\localconfig.vdf`, every account that logged in on this PC), read in the background (`Scripts\Playtime.ps1`) when the skin loads and, at most once a minute, when the launcher opens. The game is recognised by its `steam://rungameid/<id>` command or by `Source=Steam:<id>`.
- **Other tiles** (`TrackPlaytime=1`): when a tile starts a game, the background helper (the one of the [gamepad](#gamepad)) looks for its process and measures how long it runs: the program of the command (`.exe`), the one it learned the last time, or the first program coming to the foreground that started after the launch (launchers like Epic, GOG, Ubisoft, EA and Battle.net, and parts of Windows, are left out). The minutes go to `TimePlayed.txt` in the data folder, the program found to `GameExe.txt`. Web links and bangs are not measured.
- Before any time is measured: the last launch counted by Raintile (`Usage.txt`), as `Last played yesterday`.
- `TileInfo=Hover` (default) shows it only on the highlighted tile (mouse, keyboard or gamepad), `Always` on every tile, `Never` hides it. Size: `InfoFontSize`. Options > Appearance > Text.
- Tiles of [games no longer installed](#games-no-longer-installed) always show **Not installed**.
- **Steam updates** (`GameUpdates=1`): a Steam game with an update to download says so on a line of its own above the play time, always shown (whatever `TileInfo` says), and its tile gets a border in `DownloadColor1` and `DownloadColor2` that turns for `UpdateGlowTime` seconds when the launcher opens (`0`: it stays still), under the highlight of the mouse.
  - Waiting: `Update 5.4 GB - Sat 06:27` (its size and when Steam scheduled it; `today` / `tomorrow` when close).
  - Downloading: `Downloading 40% - 540 MB / 1.3 GB - 25.3 MB/s - 2:35 left`, then `Installing update`; `Paused 40%` when paused in Steam.
  - A game installed for the first time says `Install 1.3 GB` while it waits and `Installing 40% - ...` while it downloads. A tile of a game no longer installed that Steam is installing again is not greyed out any more: its background is coloured again from the left as the download goes, and the line shows the download instead of *Not installed* (back to *Not installed* only if it is still missing at the next scan). `DownloadInfo` chooses the parts, in any order: `percent`, `size`, `speed`, `eta` (time left), `schedule`.
  - The logo of a game downloading (or no longer installed) stays in greyscale, also under the mouse.
  - The progress shows on the tile as `DownloadStyle` says: `Bar` (a bar along the bottom in `DownloadColor1`), `Greyscale` (the background in greyscale, coloured again from the left as far as it got; tiles without a background image show nothing) or `Both`. It fills up when the launcher opens.
  - Where it comes from: Steam's `steamapps\appmanifest_<id>.acf` of every library (`Scripts\GameUpdates.ps1`), read at the same moments as the play time, so it is what Steam knew last (Steam finds new updates only while it runs). While the launcher is open the background helper follows the downloads every second: Steam's log (`logs\content_log.txt`: its state at once, the speed every few seconds) and the appmanifest when Steam rewrites it; between the two the bytes downloaded are worked out from the speed and the time of each line of the log (also for the part of the download before the launcher opened), so the line moves every second while Steam gives the speed every 10-15 seconds. A download started while the launcher is open shows up within a second, from the log. Nothing is followed while the launcher is hidden.
  - `GameUpdates=0` turns it all off (Options > Appearance > Text; the rest under Appearance > Steam updates).
- **Where**: the top left by default. To move it, drag the sample line in the tile's preview (Options > *the category* > *the tile*), or under **All tiles** for the whole category; the **x** on the **Play time** row gives it back the place of All tiles. It is saved as `InfoPos=X,Y`: where the line goes in the room it leaves inside the margins (`LabelPad`), in %: `0,0` top left, `100,0` top right, `50,50` centre, `100,100` bottom right. The line changes width with what it says, so it stays inside the tile whatever the text.

## Launching a tile

**Hot keys**: a tile with `HotKey=` (e.g. `CTRL ALT 1`) starts with that combination wherever you are, also while the launcher is hidden (`TileKeysWhen=Always`, the default; with `Open` only while it is open, and the keys stay free for other programs the rest of the time): right away, without the animation (an open launcher hides with `CloseOnLaunch=1`). One tile per combination: if two tiles have the same one, the first wins, and the open/close key (`OpenHotKey`) cannot be used. The Options window warns about a combination already used.

On click the tile expands to full screen (with background and logo at full resolution), stays visible for `LaunchHold` ms, then the launcher hides. The command starts right away, at the beginning of the animation.

| Setting | Default | Effect |
| --- | --- | --- |
| `LaunchAnimation` | `1` | `0` = no animation, hide immediately |
| `LaunchAnimFrames` | `15` | expansion steps of 16 ms (15 ≈ 250 ms) |
| `LaunchHold` | `1500` | ms at full screen before hiding |
| `LaunchLogoSize` | `33%` | final logo size |
| `LaunchFontSize` | `48` | centre text for tiles without a logo |

## Widgets and the Dashboard

A **widget** is a tile that shows something instead of starting a game: processor, graphics card, memory, disks, network, processes, temperatures, a skin of yours. Any tile of any category can be a widget, next to the games: e.g. a clock among your apps.

The **Dashboard** (`Categories\Dashboard.ini`, added once to existing data too) is a normal category kept as an example: a 5 x 4 grid of system widgets, CPU, GPU and temperatures of 2 x 2 cells, memory and processes of 1 x 2, network and disks.

- In the Options window it is among the categories like the others: name, icon, grid, **Show in the menu** (`Hidden=1` in its `[Category]` keeps any category out of the menu). Options > **Widgets** > *Add the example Dashboard* brings it back if you deleted it.
- The data is collected by the background helper (the one of the [gamepad](#gamepad)) only while a category with widgets is on screen, every `DashInterval` ms (default 1000): with it closed nothing is measured.
- **Modrinth instances** (widget gallery, under Games): the instances of [Modrinth App](https://modrinth.com/app), the last played first, with their icons; a click starts one. Its script reads Modrinth App's database (read only) when the category comes on screen. More cells for the tile (`Size=1x2`), more rows. Widgets can do the same for anything: see *What Raintile does for a widget* in `widgets/README.md`.
- A custom widget can have parts (`Part=1` on its meters): the highlight goes onto the part under the mouse and a click runs the part's own action (see `widgets/README.md`).
- Widgets are left out of search, Favorites, Recent and the filters. In a sorted category they are sorted like the other tiles (by name, by when they were added...); pin them to keep them first.
- Clicking a widget runs its `Command=`, or by default opens what fits: Task Manager (CPU, GPU, RAM, processes), the disk in Explorer, network or system settings.

### Widgets

A tile becomes a widget with `Widget=` (and, for some kinds, `Param=`). In Options > Categories > *the category* > *the tile* pick **Widget** and **Widget option**. `Label=` is the title shown on the widget (by default the name of the kind), `Size=2x1` makes it larger (see [Tiles of more cells](#tiles-of-more-cells)).

| `Widget=` | Shows | `Param=` |
| --- | --- | --- |
| `cpu` | use, speed, cores and a graph of the last minute | |
| `gpu` | use (3D engine), video memory and a graph | |
| `ram` | memory used and free, and a graph | |
| `disk` | used and free space | a drive (`C:`); empty = every drive, one bar each |
| `network` | download and upload speed, and a graph | |
| `processes` | the programs using the most CPU | `ram` = sorted by memory |
| `system` | Windows version, PC name, uptime, battery | |
| `temps` | temperatures (from LibreHardwareMonitor or HWiNFO) | sensors to show, see below |
| `fans` | fan speeds (from LibreHardwareMonitor or HWiNFO) | sensors to show |
| `skin` | a Rainmeter skin placed over the tile | its config and file: `illustro\Clock\Clock.ini` |
| `custom` | a custom widget drawn in the tile | its name in the `Widgets` folder |

### Temperatures and fans

Windows does not give temperatures to programs without a driver, so Raintile reads them from a sensor program that runs beside it:

- **[LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor)** (free, open source; looked at first): download it, start it (it asks to run as administrator, to read the sensors) and keep it running: in its menu *Options* turn on *Start Minimized*, *Minimize To Tray*, *Run On Windows Startup* and **Remote Web Server > Run**. Raintile reads its sensors from that web server, on this PC only (`http://localhost:8085/data.json`; another port: `SensorPort`, Options > Widgets); Windows may ask about the firewall: it is not needed for this. Older versions also publish them through WMI, which Raintile reads too.
- **[HWiNFO](https://www.hwinfo.com/)** (free), when LibreHardwareMonitor is not running: start it (sensors only is enough), open **Settings** and turn on **Shared Memory Support**. Its free version turns the shared memory off after 12 hours: start it again then.

- Without `Param=`, `temps` shows the CPU and GPU temperatures it finds (package, die, hot spot, ...), `fans` the first fans.
- `Param=` picks the readings, separated by `;`, each one a part of the label as the sensor program writes it (any case; LibreHardwareMonitor and HWiNFO name some of them differently, e.g. `GPU Core` and `GPU Temperature`): `Param=CPU Package;GPU Core;SSD`. Add `=Name` to rename one: `Param=CPU Package=CPU;GPU Hot Spot=GPU hot`. A label that is not a temperature (or a fan) is looked for among the other readings too, so the widget can show anything the sensor program measures: `Param=CPU Package;CPU Total=CPU use;GPU Package` (LibreHardwareMonitor's names; `Total CPU Usage`, `GPU Power` in HWiNFO). Give it a title of your own with `Label=` (e.g. `Label=HWiNFO`).
- The same label can be more readings (in LibreHardwareMonitor `GPU Core` is a temperature, a load and a clock): put its kind before it, `temp:`, `load:`, `clock:`, `power:`, `fan:`, `volt:` or `current:`. For example `Param=temp:GPU Core=GPU;load:GPU Core=GPU use;clock:GPU Core=GPU clock;load:CPU Total=CPU use;power:Package=CPU power`. The names are those of the LibreHardwareMonitor window, in the tree under each piece of hardware.

### Skins in a tile

`Widget=skin` with `Param=<config>\<file>.ini` loads a skin you already have in Rainmeter, places it over the tile while its category is open and unloads it when the launcher hides. The skin keeps its own size: pick one that fits the tile, or change the grid of the category (`NX`, `NY`).

### Custom widgets

A custom widget is a Rainmeter `.ini` drawn inside the tile, as part of the launcher (no separate skin), with scripts of its own if it needs data: put it in the data folder, `Widgets\<name>\<name>.ini`, and use `Widget=custom`, `Param=<name>`; the gallery does it for you. How to write one, and what Raintile offers to widgets (lists of things to start, parts of a tile, `OnShow` / `OnHide`): [Writing Raintile widgets](Widgets.md).

### Widget gallery

Options > Widgets > **Widget gallery** lists widgets made for Raintile, grouped by where they fit (General, Games...): **Install** downloads one to the `Widgets` folder (and offers to add it as a tile to its category: e.g. Games for a games widget; General ones to the category open last, or the Dashboard), **Add as a tile** adds it to any category, picked from a menu (the suggested one first). With nightly builds (`UpdateChannel=Nightly`) the gallery is the list of the `nightly` branch, with the widgets not released yet; **Update** appears when a newer version is out, **Remove** sends it to the Recycle Bin. A widget can run programs like any Rainmeter skin: install only the ones you trust.

The list is [`widgets/index.json`](../widgets/index.json) in this repository; the widgets themselves can be here (`widgets/<id>/`) or in their authors' repositories. To publish one, see [widgets/README.md](../widgets/README.md).

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
Hidden=            ; 1 = not in the menu (the file and its tiles stay)
Sort=              ; keep the tiles in an order (see Sorting the tiles): name, name-desc, added, recent, played, playtime
TileColor=         ; colour of its tiles without a Color= of their own
TileOpacity=       ; opacity of their background, 0-100 (tiles without Opacity=)
LogoPos=           ; logo placement of its tiles without their own (e.g. 85,50: on the right)
LogoScale=
InfoPos=           ; place of the play time line of its tiles without their own (e.g. 100,0: top right)
BgFocus=           ; background framing of its tiles without their own
BgZoom=

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
| `Color` | background colour (`R,G,B,A` or `#RRGGBBAA`, see [Colours](#colours)) when there is no background image (empty: the category's `TileColor`, or taken from the logo with `AutoTileColor=1`, otherwise `TileColor`); with an alpha below 255 it is see-through |
| `Size` | cells the tile takes in the grid, `<columns>x<rows>` (`Size=2x2`, default `1x1`, at most `NX` x `NY`): see [Tiles of more cells](#tiles-of-more-cells) |
| `Opacity` | opacity of the tile's background, colour and image together, `0` to `100` (default: the category's `TileOpacity`, or `100`). `0` leaves only the logo, the label or the widget: e.g. a skin over the tile without a box behind it. The tile still answers the mouse |
| `Image` | another name for both images: `Image=diablo4` looks for `background\diablo4.*` and `logo\diablo4.*` |
| `Background` | specific background file (relative to `background\` or absolute; extension optional) |
| `Logo` | specific logo file (relative to `logo\` or absolute) |
| `BgFocus` | framing of the background: the point of the image kept at the centre of the tile, `X,Y` in % of its width and height (default: the category's `BgFocus`, or `50,50`); see [Framing a background](#framing-a-background) |
| `BgZoom` | framing of the background: enlargement beyond filling the tile, `1` to `4` (default: the category's `BgZoom`, or `1`) |
| `LogoPos` | where the centre of the logo goes, `X,Y` in % of the tile's width and height (default: the category's `LogoPos`, or `50,50`); see [Placing the logo](#placing-the-logo) |
| `LogoScale` | size of the logo, times the category's `IconSize`, `0.25` to `3` (default: the category's `LogoScale`, or `1`) |
| `InfoPos` | where the [play time](#play-time) line goes, `X,Y` in % of the room it leaves in the tile: `0,0` top left, `100,100` bottom right (default: the category's `InfoPos`, or `0,0`) |
| `Source` | where an added game or app comes from (`Steam:570`): gives its store to the [filter bar](#tags-and-filter-bar) and the Steam id to the [play time](#play-time) |
| `Tags` | tags of the tile, separated by commas (`multiplayer, co-op`): found by search, chips of the [filter bar](#tags-and-filter-bar) |
| `HotKey` | key combination that starts the tile, also while the launcher is hidden: HotKey plugin names separated by spaces (`CTRL ALT 1`); in the Options window click the field and press the keys. See [Launching a tile](#launching-a-tile) |
| `Pinned` | `1` = at the start of the category, in the order of the file, whatever the category's `Sort=`: see [Sorting the tiles](#options-window) |
| `Store` | store shown in the filter bar (`Steam`, `Epic Games`, `GOG`, ...), when it cannot be told from `Source` or the command |

### Tiles of more cells

A tile with `Size=` takes more cells: `Size=2x1` is two columns wide, `Size=2x2` twice as wide and tall (Options > *the category* > *the tile* > **Size**). It works for every tile, games and widgets alike: a featured game, a bigger CPU graph.

- The tiles are placed in order, each one in the first free spot where it fits (row by row; column by column with `Horizontal=1`), so the smaller ones after it fill the space around it.
- A size larger than the grid is reduced to it (`NX` columns, `NY` rows).
- The background thumbnail is made at the tile's size; framing and logo placement work on the whole tile.
- In search results, Favorites, Recent and Not played yet every tile takes one cell.
- Keyboard and gamepad move to the tile next to the highlighted one; up and down keep the column you came from.

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

Each tile looks for images named after itself, with the extensions `.png`, `.jpg`, `.jpeg`, `.bmp`, `.ico`, `.gif`. Use landscape backgrounds; logos work best as PNG with transparency.

**Find online...** next to *Background* and *Logo* in the tile editor (Options > the category > the tile) searches the images of that game or app: Steam's own (Steam games), [SteamGridDB](https://www.steamgriddb.com/) (with the key: games of every store and many apps, several of each), [Dashboard Icons](https://github.com/homarr-labs/dashboard-icons) (logos of apps and services) and, for a link, the icon of its website. Click one and *Use it*: it is downloaded to the tile's folder, like a picked file.

**Auto find images** under *All tiles* (Options > the category) does the same for every tile of the category without a background (**Background**), without a logo (**Logo**) or both (**All**: what each tile is missing), taking the first image found, one tile after the other, with a progress bar and a **Stop** button. To avoid wrong pictures, from SteamGridDB it only takes a game or app of the same name as the tile (or the Steam id of a Steam game). Widgets are left out. You don't need to resize anything: Raintile makes thumbnails at the displayed size (see [How it works](#how-it-works)).

### Framing a background

A background fills its tile and, by default, is cropped at the centre. When the subject is off-centre, or the image is much wider or taller than the tile, choose the part to show in Options > *the category* > *the tile* (or right click on the tile > **Edit \<tile\>...**): in the large preview on the left drag the background to move the image, zoom with the mouse wheel (it zooms on the point under the mouse) or the **Framing** slider, and the **x** next to the slider to give the tile back the framing of **All tiles** (the centre unless the category has one, see [Placement for a whole category](#placement-for-a-whole-category)). The preview has the proportions of this category's tiles on this screen.

The framing is saved in the tile as `BgFocus` (the point kept at the centre, in % of the image) and `BgZoom`. Both are relative, so it holds when the resolution, the margins or the grid change: only the edges of the image limit it. With the sliding styles (`BgStyle` `Pan`, `Parallax`, `Zoom`) the tile starts from the framed part and moves within `BgOverscan` of it, instead of across the whole image. Choosing or removing the background resets the framing. The launch animation still shows the whole image.

### Placing the logo

The logo is centred in its tile and as large as the category's `IconSize`. To move it, drag the logo itself in the same preview (Options > *the category* > *the tile*); to resize it, use the mouse wheel over it or the **Logo** slider, and the **x** next to it to give it back the placement of **All tiles** (centred at its normal size unless the category has one of its own). It is independent of the framing: the background and the logo move separately.

The placement is saved in the tile as `LogoPos` (where the centre of the logo goes, in % of the tile) and `LogoScale` (times the category's logo size). Both are relative, so the logo keeps its place when the resolution or the grid change. What is visible of the logo always stays inside the tile, also while it grows under the mouse: pushed into a corner, it stays in the corner at any size. The launch animation starts from where the logo is and brings it to the centre of the screen.

### Placement for a whole category

Logo placement, framing and the place of the [play time](#play-time) line can also be set once for all the tiles of a category, e.g. every logo on the right, every background framed on its top part or the play time at the top right. The page of a category in Options shows its tiles side by side at the top, with **All tiles** first: it holds the settings of the whole category.

- **All tiles**: the large preview shows the category's framing, logo placement and play time line (a sample text) on placeholder images, or on the images of a tile chosen in **Preview on**; drag and zoom them as on a tile. They are saved in `[Category]` with the same keys (`BgFocus`, `BgZoom`, `LogoPos`, `LogoScale`, `InfoPos`), and every tile without its own follows them, the tiles added later too. The framing is relative to each image, so on other backgrounds it frames the same relative part. On the right: the grid, the logo size, the tile colour and background of the category.
- On a tile, a chip next to **Framing**, **Logo** and **Play time** says **From All tiles** or **Own**; a dot on the small tile in the strip marks the tiles with something of their own instead of the one of All tiles (colour, background opacity, framing, logo or play time line). Moving a tile's logo, background or play time line gives it its own; the **x** on the row gives it back the one of All tiles. To change every tile at once, use All tiles.
- **Logo** / **Framing** / **Play time** (All tiles > **Reset**): every tile of the category back to the centre at the normal size (the play time line to the top left), the category's placement included. The row also says how many tiles have a placement of their own.

## Adding games and apps

Right click on the launcher > **Add games and apps...**, or **Import** in the Options window, shows what is installed on this PC. Nothing is added by itself: tick the games and apps you want and press **Add selected**. They become normal tiles, which you can edit, move and keep even after uninstalling.

The search (`Scripts\Scan.ps1`, in the background) looks in:

| Source | How | Launched with | Images |
| --- | --- | --- | --- |
| Steam | `libraryfolders.vdf` and `appmanifest_*.acf` in every library | `steam://rungameid/<id>` | local library cache (old and 2024+ layout), else Steam's servers, then SteamGridDB |
| Epic Games | launcher manifests (main games only, no DLC or apps) | Epic launcher link | SteamGridDB |
| GOG Galaxy | registry | Galaxy, or the game exe | SteamGridDB |
| Ubisoft Connect | registry | `uplay://launch/<id>` | SteamGridDB |
| Battle.net | uninstall entries of its games | Battle.net (`--exec="launch <code>"`), or the game's launcher | SteamGridDB |
| EA app | uninstall entries of Electronic Arts games | the game exe | SteamGridDB |
| Xbox / Microsoft Store | Store packages with a `MicrosoftGame.config` | `shell:AppsFolder` | SteamGridDB |
| Your folders | every `.exe` in the folders of `ImportFolders` (separated by `\|`, e.g. `D:\Games\|E:\Emulators`) and in their subfolders, named after its file; installers, uninstallers, updaters, redistributables, crash reporters and helpers left out. As games or apps: `ImportFoldersKind` | the program | SteamGridDB (games of that name), the program's own icon |
| Apps | Start menu: program shortcuts and Store apps, without uninstallers, help files and the games already found | the shortcut / `shell:AppsFolder` | a logo from Dashboard Icons, or SteamGridDB for an app of that very name, else the program's own icon |

- **The list** shows the cover (Steam) or the icon of each item, with its source, and marks the new ones. Filter by type (All, Games, Apps) or by name; *Show added* also lists what is already in the launcher (dimmed, with its category); *Covers* off gives a compact text list.
- **Where they go**: by type (games to `ImportCategory`, apps to `AppsCategory`; the category is created if missing) or all to one category.
- **Images** are copied to the category folders, named after the tile: the Steam cover and logo, the program icon for apps. Steam games without local images get theirs from Steam's servers (no key needed). Other games, and Steam games without images there, get background and logo from [SteamGridDB](https://www.steamgriddb.com/) if `SteamGridDBKey` holds an API key (free, from the site's preferences). Apps get a logo from [Dashboard Icons](https://github.com/homarr-labs/dashboard-icons) (some 3500 apps and services) or, with the key, from SteamGridDB when it has an app of that very name; otherwise the program's icon. Set the key in Options > Import: it is saved encrypted with Windows DPAPI (`SteamGridDBKey=dpapi:...`), so only your Windows user on this PC can read it; a key written in clear in `Settings.inc` is encrypted the next time the Options window opens.
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

The **gear** next to the X, or right click > **Options...**, opens the Options window: the program `Bin\RaintileOptions.exe` (C#, WPF, .NET Framework 4.8, included in Windows 10/11), in the packages of the releases; a copy of the repository without it opens the same window from `Scripts\Options.ps1` with PowerShell, a little slower. Both look the same: their look is in `Scripts\Options.xaml`. Right click on a tile > **Edit \<tile\>...** (the last of Raintile's entries, shown only on a tile) opens it on that tile, ready to edit or frame.

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
| Categories | the list of categories (create, open, reorder, delete), name and icon of the selected one |
| Categories > *each category* | its tiles side by side, **All tiles** first (grid, logo size, tile colour and background, framing and logo of every tile); a large preview to frame the background and place the logo; edit, drag a tile onto another category in the menu to move it there, turn imported games into normal tiles |
| Info (at the bottom) | version and updates, your data folder, skin folder, number of categories and tiles; buttons to open `Settings.inc`, the folders, Rainmeter's Manage window and this Guide |

- Every setting has a fitting control: switches, sliders (you can also type the value), choices, colour swatches (click to pick; the text field takes `R,G,B,A` or `#RRGGBBAA`), and sizes in **px** or **%** (switching unit converts the number for the main screen).
- **Keybindings**: click a key and press the new one. For the open/close shortcut hold the modifiers (Ctrl, Alt, Shift, Win) and press the key. The **x** next to a key removes it. A key used by two actions is marked in red.
- The arrow next to a setting appears when it differs from the default, and restores it.
- **Categories**: create, delete (to the Recycle Bin) and reorder categories, and edit the name, icon, grid and logo size of the selected one. Categories and tiles can also be reordered by dragging them in their list. Double-click a category (or pick it in the menu) to see its tiles: add, delete, reorder and edit them (name, command with *Browse...* for `.exe`/`.lnk`/`.url`, label, colour, background, logo). Picked images are copied to `Images\<category>\background|logo\<TileName>.<ext>`; renaming a tile renames its images too. The preview shows the tile as the launcher draws it.
  - **Sorting the tiles**: under **All tiles**, **Order** picks an order: *Name A–Z*, *Name Z–A*, *Recently added* (the date the tile was added, `Added=`; tiles without one go last), *Recently played* (the last launch: counted by Raintile, Steam's, or measured), *Most launched* (launches counted by Raintile) or *Most play time* (Steam's play time plus the one measured for the other games). Ties keep the order they had.
    - **Sort now** puts the tiles in that order once; you can still drag them afterwards.
    - **Keep sorted** keeps them in it (`Sort=` in `[Category]`): new and renamed tiles go to their place, and the launcher works the order out again each time it loads and opens, so the orders by play follow what you play. The remembered scroll position follows the tiles: the tile you launched (or had selected) stays in view where it moved. Dragging and the move buttons are off while it is on, except for pinned tiles.
    - **Pinned tiles** (the tile's **Pinned** box, or right click on the tile in the launcher > **Pin to the start**) come first, in the order you drag them to, with a pin on their small tile; sorting moves only the others.
  - **Moving a tile to another category**: drag it from the strip onto that category in the menu on the left (the entry is outlined when it can take it). The tile and its images move, and both category files are saved at once. Imported games move only once they are normal tiles.
  - **Imported games** are shown read-only. **Make it a normal tile** turns one into a hand-written tile: its images are copied to the category folders, and the import will not add it again.
- **Gamepad** (the program only, not `Options.ps1`; off with `Gamepad=0`): while the window is in the foreground the controller moves a ring between the controls. D-pad / left stick move (on a slider left and right change the value, the field next to it is skipped), `A` presses a button, flips a switch, picks a choice or a list entry, opens a drop-down list (up/down choose, `LB`/`RB` jump by 10, `A` keeps, `B` puts back) or types into a text field, `B` goes back to the menu (in the menu it closes the window, in a dialog it cancels), `LB` / `RB` go to the previous / next page, `Start` alone saves and refreshes, the right stick scrolls. The ring goes away when you move the mouse or press a key; the next pad input brings it back without acting.
  - **On-screen keyboard** (`A` on a text field): the launcher's layout with lower case, **Shift** for capitals and a page of symbols (`#+=`) for paths and commands; the text shows above the keys. `A` types the key, `X` deletes, `Y` adds a space, `LB` / `RB` move the cursor, `LT` is Shift, `RT` the symbols, `Start` (or *Done*) keeps the text, `B` puts back what was there. The keys can be clicked too.
  - Still mouse or keyboard: key bindings (they wait for a key), colour and file pickers (Windows dialogs), framing the background and placing the logo by dragging (the zoom and logo size sliders work with the pad).
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
Widgets\          custom widgets, installed from the gallery or by hand
Favorites.txt     your favorite tiles
Usage.txt         how many times and when each tile was launched (Recent)
Seen.txt          games and apps already shown in the Import list
Update.json       result of the last update check
```

Installing an update replaces the skin folder, so nothing of yours may live there. The files in the skin's `@Resources\` (`Settings.inc`, `Categories\`, `Images\`) are the defaults: the first time, `Scripts\Data.ps1` copies them to the data folder — or, when updating from a version that kept them in the skin folder, copies your own from the backup the installer has just made (`Skins\@Backup\Raintile\`). Right click > *Categories folder*, *Images folder* and *Edit Settings.inc*, and Options > Info, open the data folder.

**Back up and restore**: Options > Info > *Backup* saves the whole data folder as a zip (*Back up...*) and puts a backup back (*Restore...*). Restoring never deletes your current data: it is moved to a folder next to it (`Raintile.before-restore-<date>`), and put back if something goes wrong. A backup also moves your launcher to another PC; the SteamGridDB key in it only works for the same Windows user.

When an update adds settings, they are added to your `Settings.inc` with their default value (and settings it removes go), keeping your values; this happens by itself on the first load after the update. To start over from the defaults, delete the data folder and refresh the skin.

### Updates

If something goes wrong with an update, install the package from the [releases page](https://github.com/Derek3rd/raintile/releases) by hand: your data is in its own folder and stays as it is.

With `CheckUpdates=1` (Options > Advanced) the skin asks GitHub for the latest release at most once a day, in the background. When there is a newer version a dot lights up on the gear (the same dot used for new games and apps) and on **Info** in the menu of the Options window; a click opens Options > **Info**, which shows the installed and the latest version and the release notes:

**Nightly builds** (`UpdateChannel=Nightly`, Options > Advanced > *Updates*): the check also looks at the pre-release `nightly`, built on every change, and offers the newer of the two. Their versions have four numbers, `1.2.1.5`: the 5th build after the release `1.2.1`; the next release (`1.2.2` or `1.3.0`) gathers them and is newer than all of them. Newer features, not tested as much: a copy of the skin is kept in `Skins\@Backup` before each update. Back to `Release`, the next release brings you back on it.

- **Direct update** downloads the release's `.rmskin` and installs it by itself: a copy of the current skin folder goes to `Skins\@Backup\Raintile-<version>-<date>` (Rainmeter does not load folders starting with @), the package's files replace the ones of the skin folder, then Rainmeter reloads every skin and the launcher opens. `@Resources\Generated` (thumbnails, lists) stays, the plugins are not touched, and a file in use (the Options program itself) is renamed and replaced; the old copy goes at the next start. If something fails, the files of the backup are put back. The package is refused if it does not hold `Skins/Raintile/Raintile.ini` or a path leaves its folder.
- **Rainmeter Update** downloads the same package and opens it with the Rainmeter installer instead; the Options window closes. Keep the installer's default options.
- Either way your data is not touched, and only files of this repository's releases on GitHub (https) are downloaded, into a new temporary folder, and checked to be a Rainmeter package before they are used. Without the Options program (a copy of the repository) the PowerShell window only has the installer.
- **Check now** asks GitHub again; **Release page** opens the release on GitHub.

### Checks and tests

`python tools/check.py` checks a copy of the repository before a commit; the **checks** job of the **Release package** workflow runs it on every pull request, on Windows. It needs Python 3, Windows PowerShell and `lupa` (`pip install lupa`, which brings Lua 5.1, the version of Rainmeter). It takes a few seconds.

- **Checks on the files**: scripts and `.ini`/`.inc` files ASCII only and without BOM; every `.ps1` parses with Windows PowerShell 5.1 (so no PowerShell 7 syntax); `Options.xaml` and the JSON files load; `Raintile.lua` compiles with Lua 5.1 (also the limit of 200 locals); the widget gallery points to files that exist; every setting of `Settings.inc` is in the Options schema; `GRID_VERSION` is bumped when `writeGrid()` changes; every page of `docs\` goes to the wiki.
- **PowerShell tests** (`tests\ps\`): `Data.ps1` run on temporary folders (first run, a second run that changes nothing, your values kept through an update, the backup of the installer), and the cleaning of tile names (`Get-TileName` of `Scan.ps1`), which must never lead out of their folder.
- **Lua tests** (`tests\lua\`): `Raintile.lua` runs against a small fake Rainmeter (`tests\lua\rainmeter.lua`), which reads `Raintile.ini` with its include files, keeps meters, measures and variables, runs the bangs and the ActionTimer lists and reloads the skin on `!Refresh`. The launcher is loaded full screen, in a window and docked, and used as a person would (categories, scrolling, hover, keyboard, search, the menus, launching a tile, hiding it). A test fails on anything Rainmeter would log as an error (a bang on a meter that does not exist, a script error) and on what the project does not allow: text that is not ASCII, a value on more than one line, a skin that keeps refreshing itself, an animation that never stops or a timer still running once the launcher is hidden. Sizes are estimated, not drawn: layouts can be checked (entries one under the other), pixels cannot. `python tools/check.py --tests` runs only the tests.

What the fake Rainmeter cannot show (drawing, the order of the layers, real mouse moves, the Options window) is still tested live.

**Before every push**: `python tools/check.py --install-hook` installs a local `pre-push` hook (in `.git\hooks`, next to any you have). From then on every commit you push is checked first, in a temporary copy of that commit (a git worktree), so uncommitted changes do not count; if a check fails the push stops: fix, commit, push again. Branches without `tools\check.py` are pushed unchecked.

### Publishing a release

The work goes to the branch **`nightly`** (pull requests included); **`main`** only gets what is released:

1. Set the new version in `Version=` in the `[Metadata]` of `Raintile.ini` on `nightly`, then open a pull request **`nightly` → `main`** and merge it.
2. On GitHub, **Releases > Draft a new release**: tag with the same number, like **`v1.0.3`**, on `main`; write the notes and publish.
3. The **Release package** workflow (`.github/workflows/release.yml`) builds the `.rmskin` with `tools/build_rmskin.py` and attaches it to the release by itself, within a minute or two. If the tag and `Version=` differ, it stops and attaches nothing.

For the update check the tag must hold the version (if it has no number, the number in the release title is used, e.g. "1.0.1 - ..."), and the `.rmskin` must be attached (otherwise the update buttons open the release page). The package can also be built by hand: `python tools/build_rmskin.py` writes it to `dist\`; *Actions > Release package > Run workflow* builds it as a downloadable artifact.

**After a release** the **Sync nightly** workflow (`.github/workflows/sync-nightly.yml`) merges `main` into `nightly` by itself, so `nightly` has the release tag (the nightly builds count from it) and any fix made on `main` for the release. If the merge has conflicts it stops without pushing: merge `main` into `nightly` by hand. (A tag is also called `nightly`, the pre-release below: in git commands write the branch as `refs/heads/nightly` when it matters.)

**Nightly builds.** On every push to the branch `nightly` the **Nightly** workflow (`.github/workflows/nightly.yml`) builds the Options program and the `.rmskin` and publishes them as the pre-release **`nightly`** (replacing the previous one). Its version is the last release plus the number of commits since it: after `v1.2.1`, `1.2.1.1`, `1.2.1.2`, ... until the next release; it is written into the package's `Raintile.ini` (`tools/build_rmskin.py --nightly-version`). So the work merged into `nightly` reaches the skins on the nightly channel at once, the others with the next release.

The package holds the skin only (with the HotKey plugin from `tools/plugins/`): `README.md`, `docs\`, `tests\` and `tools\` stay on GitHub (Options > Info opens the Guide there).

In the package no *VariableFiles* are needed (settings are in the data folder) and the installer's default backup should be kept: the first update to this version recovers the user's categories and images from that backup.

## Settings reference

All settings live in `Settings.inc` in [your data folder](#your-data-and-updates) (right click > *Edit Settings.inc*); `@Resources\Settings.inc` holds the defaults. Switches are `1` (on) / `0` (off). Sizes marked *(size)* accept pixels or percentages ([see below](#sizes-in-pixels-or-percentages)). After editing the file by hand, refresh the skin.

### Screen

| Setting | Default | Description |
| --- | --- | --- |
| `ScreenX`, `ScreenY`, `ScreenW`, `ScreenH` | `#SCREENAREA...#` | area of the launcher. Use `#WORKAREA...#` to keep the taskbar free, or `#SCREENAREAWIDTH@2#` (etc.) for another monitor |
| `LauncherMode` | `Fullscreen` | `Fullscreen`, `Window` or `Dock`: see [Full screen, window or docked](#full-screen-window-or-docked) |
| `WindowW`, `WindowH` | `60%`, `70%` | size of the window (pixels or % of the area) |
| `DockSide` | `Left` | side it is docked on: `Left`, `Right`, `Top`, `Bottom` |
| `DockSize` | `30%` | width when docked left or right, height when docked at the top or bottom (pixels or % of the area) |
| `DockEdge` | `1` | docked: it also opens when the mouse rests on that edge of the screen |
| `DockEdgeDelay` | `300` | ms the mouse rests on the edge before it opens |

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
| `ShowFavorites`, `ShowRecent` | `1`, `1` | the [Favorites and Recent](#favorites-and-recent) buttons, right of the search bar |
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
| `TileKeysWhen` | `Always` | hot keys of the tiles: `Always` (also with the launcher closed) or `Open` (only while it is open) |
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
| `FrameRate` | `Auto` | steps per second of the animations: `Auto` = 30 from about 3 million pixels (e.g. 3440x1440), 60 below; `60` or `30` to choose. Animations last the same either way |

**Large screens.** Rainmeter draws the whole window again on every step of an animation, so the work grows with the pixels: a launcher covering a 3440x1440 screen has 2.4 times those of 1920x1080. What helps, most first:

- Rainmeter's **hardware acceleration** (Rainmeter > Manage > Settings > *Use hardware acceleration*, then restart Rainmeter): the drawing moves to the graphics card. When it is off and the launcher is that large, the dot on the gear suggests it once; a click opens those settings.
- `FrameRate=Auto` (or `30`): half the steps, each moving twice as much. While the only thing moving is a background slowly panning (`BgStyle=Pan`), steps drop to 20 per second by themselves.
- `BgStyle=Crop`: no background moving under the mouse at all; `TileRadius=0` and `EdgeFade=0` take away the shapes drawn over the grid on every step.
- The window mode (`LauncherMode=Window`) or a smaller area: fewer pixels to draw.

### Gamepad

See [Gamepad](#gamepad): `Gamepad`, `GamepadToggle`, `GamepadSearch`, `GamepadOptions`, `GamepadDeadZone` (0-32767), `GamepadRepeatDelay`, `GamepadRepeatRate` (ms).

### Search

| Setting | Default | Description |
| --- | --- | --- |
| `SearchW` | `320` | search bar width when open *(size)* |
| `SearchPlaceholder` | `Search` | text shown in the empty search bar |
| `SearchHover` | `1` | `1` = only the magnifier until the mouse is over it, `0` = always open |

### Widgets

| Setting | Default | Description |
| --- | --- | --- |
| `DashInterval` | `1000` | ms between two updates of the [widgets](#widgets-and-the-dashboard) (250-5000), only while a category with widgets is on screen |
| `SensorPort` | `8085` | port of LibreHardwareMonitor's web server (its Options > Remote Web Server), read for the [sensors](#temperatures-and-fans) |

### Clock

<a id="clock"></a>Time and date at the top left (Options > Menu > Clock). They are updated once a minute, only while the launcher is visible: at rest it still uses no CPU.

| Setting | Default | Description |
| --- | --- | --- |
| `ShowClock`, `ShowDate` | `1`, `1` | show the time, and the date next to it |
| `ClockFormat` | `%H:%M` | time format: `%H:%M` = 14:05, `%#I:%M %p` = 2:05 PM |
| `DateFormat` | `%A %#d %B` | date format, in the language of Windows: `%A %#d %B` = Monday 2 November, `%#d/%m/%Y` = 2/11/2026 |
| `ClockFontSize` | `18` | time font size (points); the date uses `MenuFontSize` |

### Games and apps

See [Adding games and apps](#adding-games-and-apps): `ImportStores`, `ImportFolders`, `ImportFoldersKind`, `ScanOnStart`, `ImportCategory`, `AppsCategory`, `SteamGridDBKey`.

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
| `GameUpdates` | `1` | Steam games with an [update waiting](#play-time) say so on a line above the play time, with a border on their tile; `0` turns it off |
| `DownloadInfo` | `percent speed eta size schedule` | parts of the update line: `percent`, `size`, `speed`, `eta`, `schedule` |
| `DownloadStyle` | `Bar` | progress of a download on its tile: `Bar`, `Greyscale` or `Both` |
| `DownloadColor1` / `DownloadColor2` | `0,210,180,255` / `120,90,255,255` | the border of a tile with an update (gradient from 1 to 2) and the bar (1) |
| `UpdateGlowTime` | `3` | seconds the border turns when the launcher opens; `0` = still |
| `FontFace` | `Segoe UI` | font |
| `MenuFontSize`, `LabelFontSize` | `12`, `14` | font sizes (points) |
| `BgColor` | `8,8,12,200` | launcher background |
| `TileColor` | `36,36,44,255` | default tile colour |
| `TileRadius` | `0` | rounded corners of the tiles and of the highlight, in pixels (`0` = square) |
| `EdgeFade` | `1` | tiles cut by the edge of the grid (a tile of more cells only partly on screen, a row while scrolling) fade into the background there, to show they go on |
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
TileKeys/TileKeys.ini        tile hot keys with TileKeysWhen=Open (activated while the launcher is open)
@Resources/
  Settings.inc               default settings (yours are in the data folder)
  State.inc                  default positions
  Categories/*.ini           default categories (Dashboard.ini: the default Dashboard), copied to the data folder the first time
  Images/<category>/         their icons, backgrounds and logos
  Icons/                     icons of Favorites and Recent
  Scripts/Data.ps1           prepares the data folder
  Scripts/TileAction.ps1     tile menu: run as administrator, remove
  Scripts/Update.ps1         update check
  Scripts/Raintile.lua       launcher logic
  Scripts/Thumbs.ps1         thumbnail creation
  Scripts/Scan.ps1           search of the installed games and apps, and of the tiles no longer installed
  Scripts/Playtime.ps1       play time of the Steam games
  Scripts/GameUpdates.ps1    Steam games with an update waiting
  Scripts/Helper.ps1         gamepad and focus-loss helper
  Bin/RaintileOptions.exe    Options window (built from src/Options by the release workflow)
  Scripts/Options.ps1        Options window with PowerShell, when the program is missing
  Scripts/Options.xaml       look of the Options window
  Generated/Grid.inc         generated meters
  Generated/Sizes.inc        the launcher's rectangle (LauncherMode), percentage sizes and #hex colours converted for Rainmeter
  Generated/Thumbs/          thumbnails (safe to delete: they are rebuilt)
  Generated/Colors.txt       tile colours taken from logos (AutoTileColor)
  Generated/Area.txt         grid area in pixels, for the framing preview of Options
  Generated/EditTile.txt     tile to open Options on (Edit this tile), removed once read
  Generated/Found.json       games and apps found by the last search
  Generated/Found/           their icons
  Generated/Missing.txt      tiles of games no longer installed (last search)
  Generated/Playtime.txt     play time of the Steam games
  Generated/GameUpdates.txt  Steam games with an update waiting
  Generated/DownloadOn.txt   while the launcher is open: the downloads for the helper to follow
  Generated/Downloads.txt    their progress, speed and time left (Helper.ps1)
  Generated/DashOn.txt       present while a category with widgets is on screen: the helper collects their data
  Generated/DashData.txt     the data of the widgets (written by the helper)
  Generated/DockEdge.txt     docked with DockEdge=1: the edge the helper watches to open it
  Generated/LauncherSize.txt size of the launcher, for the helper to find its window
  Generated/TileKeys.inc     the measures of the TileKeys mini-skin
```

The data folder (`%APPDATA%\Rainmeter\Raintile\`) is described in [Where your data is](#where-your-data-is).

## Troubleshooting

- **First stop: the Rainmeter log** (*Manage* > *Log*). Raintile's messages start with `Raintile:`. Set `DebugLog=1` for more detail.
- **Esc, keyboard navigation or the gamepad don't work after an update**: in Rainmeter use **Refresh all** (not just *Refresh skin*) so it sees new or renamed mini-skins and scripts. Check that the HotKey plugin is installed.
- **A category icon doesn't show**: the icon goes in `Images\<file name>\icon.png` — the folder is named after the category *file* (`Games`), not its menu label. The log shows exactly where it looked (`Raintile: no icon for category ...`).
- **A tile image doesn't show**: check the file name matches the tile name (or its `Image`/`Background`/`Logo` key); explicit names that are not found are logged.
- **The Options window doesn't open, or shows an error**: errors are shown in a message box and written to `Generated\Options.log`. The program needs .NET Framework 4.8 (included in Windows 10/11); if it does not start, delete `@Resources\Bin\` in the skin folder and the window opens with PowerShell instead.
- **The Options window is slow to open**: `Generated\Options-startup.log` lists how long each step of the last opening took. The PowerShell version (without `Bin\RaintileOptions.exe`) is slower, and the first time it prepares a small helper, `Generated\RaintileOptions-*.dll`.
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
