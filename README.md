# Raintile

**Raintile** is a full-screen tile launcher for [Rainmeter](https://www.rainmeter.net/), meant to replace the icons on your Windows desktop.

Your games, apps, links and system tools become large tiles with background art and logos, organised in categories you switch between from a menu at the top. Open it with a shortcut, pick a tile with the mouse, the keyboard or a gamepad, and it gets out of the way.

## Features

- **Categories** in a centred menu at the top (icon, text or both), each with its own grid size.
- **Tiles** with background image, logo, label and any command: programs, shortcuts, URLs, folders, `steam://` links, Rainmeter bangs. Backgrounds fit the tile by themselves; you can also frame each one by dragging and zooming it in Options, and move and resize its logo on its own.
- **Add games and apps** found on this PC — Steam, Epic Games, GOG Galaxy, Ubisoft Connect, Battle.net, EA app, Xbox, and the programs of the Start menu — picking them from a list, with background and logo (local Steam cache, [SteamGridDB](https://www.steamgriddb.com/), program icons). New ones are signalled with a dot on the gear.
- **Search** across all categories, with results that follow every key.
- **Favorites and Recent**: your favorite tiles and the ones launched lately (or most often), one click away from the buttons next to the search bar.
- **Tags**: tag your tiles (multiplayer, coop, ...); search finds them, and chips above the results filter by tag or by store with a click.
- **Play time**: hours played (Steam) and last launch, on the highlighted tile or always.
- **Games no longer installed** are found by the same search: greyed out in the launcher, removed or kept with a click.
- **Tile menu**: right click a tile to edit it, add it to Favorites, open its file location, run it as administrator or remove it.
- **Mouse, keyboard and gamepad**: WASD/arrows, Space/Enter, Xbox-compatible controllers (open the launcher with Back + Start).
- **Animations**: tiles appearing, smooth (and optionally infinite) scrolling, sliding highlight, logos turning from greyscale to colour, background pan/parallax/zoom, full-screen expansion when a tile is launched. Every one of them can be turned off.
- **Lightweight**: no update cycle (0% CPU at rest), a fixed number of meters however many tiles you have, thumbnails at the exact displayed size, loaded once and then just shown/hidden.
- **Options window** to edit every setting, the categories and their tiles without touching files.

## Requirements

- Windows 10 or 11
- [Rainmeter](https://www.rainmeter.net/) **4.5** or later
- The **HotKey** plugin, for the open shortcut, Esc and keyboard navigation ([HotKey.dll](https://github.com/brianferguson/HotKey.dll))
- Windows PowerShell 5.1 (included in Windows), used for thumbnails, the search of games and apps, the gamepad helper and the Options window

## Installation

**With the package** (recommended): download the `.rmskin` file of the latest [release](https://github.com/Derek3rd/raintile/releases) and open it: the Rainmeter installer installs and loads the skin. Install the HotKey plugin too if you don't have it.

**By hand**:

1. Download or clone this repository into your Rainmeter skins folder, so that `Raintile.ini` ends up in:

   ```
   Documents\Rainmeter\Skins\Raintile\Raintile.ini
   ```

2. Install the HotKey plugin if you don't have it yet.
3. In Rainmeter: **Manage** > **Refresh all**, then load `Raintile\Raintile.ini`.
4. Press **Ctrl+Alt+G** to show or hide the launcher.

**Updates** (experimental): Raintile checks GitHub once a day and shows a dot on the gear when a new version is out; Options > Info installs it with one click. This is still being tested and could cause problems: keep a copy of your data before updating. Your settings, categories and images live in `%APPDATA%\Rainmeter\Raintile\`, so updating never touches them.

The launcher places itself at the top-left corner and covers the screen. Do not load the `Raintile\Hotkey`, `Raintile\Navigation` and `Raintile\Typing` skins by hand: the launcher turns them on and off by itself.

## Quick start

- **Add tiles**: right click on the launcher > **Options...**, or edit the files of right click > **Categories folder** (one file per category). Right click on a tile > **Edit \<tile\>...** opens it in Options.
- **Add your games and apps**: right click > **Add games and apps...**, tick them and press **Add selected**.
- **Images**: put them in right click > **Images folder** > `<category>\background\<TileName>.jpg` and `...\logo\<TileName>.png`; they are picked up automatically.
- **Settings**: right click > **Options...**, or **Edit Settings.inc**.
- **Back up your launcher**: Options > Info > **Back up...** (and **Restore...** on another PC).

## Documentation

Everything else — every setting, category and tile files, adding games and apps, keyboard and gamepad controls, search, animations, how it works and troubleshooting — is in the **[Guide](docs/Guide.md)**.
