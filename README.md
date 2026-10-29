# Raintile

**Raintile** is a full-screen tile launcher for [Rainmeter](https://www.rainmeter.net/), meant to replace the icons on your Windows desktop.

Your games, apps, links and system tools become large tiles with background art and logos, organised in categories you switch between from a menu at the top. Open it with a shortcut, pick a tile with the mouse, the keyboard or a gamepad, and it gets out of the way.

## Features

- **Categories** in a centred menu at the top (icon, text or both), each with its own grid size.
- **Tiles** with background image, logo, label and any command: programs, shortcuts, URLs, folders, `steam://` links, Rainmeter bangs.
- **Import games** from Steam, Epic Games, GOG Galaxy and Ubisoft Connect, with background and logo (from the local Steam cache or [SteamGridDB](https://www.steamgriddb.com/)).
- **Search** across all categories.
- **Mouse, keyboard and gamepad**: WASD/arrows, Space/Enter, Xbox-compatible controllers (open the launcher with Back + Start).
- **Animations**: tiles appearing, smooth (and optionally infinite) scrolling, sliding highlight, logos turning from greyscale to colour, background pan/parallax/zoom, full-screen expansion when a tile is launched. Every one of them can be turned off.
- **Lightweight**: no update cycle (0% CPU at rest), a fixed number of meters however many tiles you have, thumbnails at the exact displayed size, loaded once and then just shown/hidden.
- **Options window** to edit every setting, the categories and their tiles without touching files.

## Requirements

- Windows 10 or 11
- [Rainmeter](https://www.rainmeter.net/) **4.5** or later
- The **HotKey** plugin, for the open shortcut, Esc and keyboard navigation ([HotKey.dll](https://github.com/brianferguson/HotKey.dll))
- Windows PowerShell 5.1 (included in Windows), used for thumbnails, game import, the gamepad helper and the Options window

## Installation

> A ready-to-install `.rmskin` package is coming soon. Until then, install it manually:

1. Download or clone this repository into your Rainmeter skins folder, so that `Raintile.ini` ends up in:

   ```
   Documents\Rainmeter\Skins\Raintile\Raintile.ini
   ```

2. Install the HotKey plugin if you don't have it yet.
3. In Rainmeter: **Manage** > **Refresh all**, then load `Raintile\Raintile.ini`.
4. Press **Ctrl+Alt+G** to show or hide the launcher.

The launcher places itself at the top-left corner and covers the screen. Do not load the `Raintile\Hotkey` and `Raintile\Navigation` skins by hand: the launcher turns them on and off by itself.

## Quick start

- **Add tiles**: right click on the launcher > **Options...**, or edit the files in `@Resources\Categories\` (one file per category).
- **Import your games**: right click > **Import games from stores**.
- **Images**: put them in `@Resources\Images\<category>\background\<TileName>.jpg` and `...\logo\<TileName>.png`; they are picked up automatically.
- **Settings**: right click > **Options...**, or edit `@Resources\Settings.inc`.

## Documentation

Everything else — every setting, category and tile files, import, keyboard and gamepad controls, search, animations, how it works and troubleshooting — is in the **[Guide](docs/Guide.md)**.
