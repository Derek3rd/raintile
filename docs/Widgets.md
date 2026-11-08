# Writing Raintile widgets

A widget is a tile that shows something or offers more than one thing to start, instead of starting one game: a clock, a list of Minecraft instances, the achievements of a game. Every widget that is not one of Raintile's own system widgets (CPU, GPU, memory, disks, network, processes, system, temperatures, fans) is a **custom widget**: a folder with a Rainmeter `.ini` and, if it needs one, a script of its own. It is installed from the widget gallery (Options > Widgets) or by hand, and its tile can go in any category.

Raintile itself holds no logic for a particular widget: what a widget needs that Rainmeter alone cannot give, Raintile offers to every widget through the [Raintile section](#the-raintile-section).

Examples in this repository: [`widgets/BigClock`](../widgets/BigClock) (meters only), [`widgets/Modrinth`](../widgets/Modrinth) (a script reading a program's database into a list) and [`widgets/SteamAchievements`](../widgets/SteamAchievements) (a web API with the user's key in its settings, a setting per tile).

## Contents

- [Files](#files)
- [How the file is read](#how-the-file-is-read)
- [Variables Raintile fills in](#variables-raintile-fills-in)
- [The Raintile section](#the-raintile-section)
  - [OnShow and OnHide](#onshow-and-onhide)
  - [Lists](#lists)
  - [WidgetChanged()](#widgetchanged)
- [Settings of a widget](#settings-of-a-widget)
- [Parts of a tile](#parts-of-a-tile)
- [Getting data: scripts](#getting-data-scripts)
  - [Keys of the user's](#keys-of-the-users)
- [Rules](#rules)
- [Testing](#testing)
- [Publishing in the gallery](#publishing-in-the-gallery)

## Files

```
Widgets\<Id>\<Id>.ini      the widget (required; the name is its Param=)
Widgets\<Id>\...           anything else it needs: scripts, images, its data
Widgets\<Id>\settings.inc  its settings, written by the Options window (see Settings of a widget)
```

`Widgets\` is in the data folder (`%APPDATA%\Rainmeter\Raintile\Widgets\`). A tile uses it with:

```ini
[My tile]
Widget=custom
Param=<Id>
Size=1x2          ; optional: more cells
WidgetOption=     ; optional: a setting of this tile for the widget (#WIDGETOPTION#)
```

## How the file is read

The `.ini` is written like a Rainmeter skin, but it is not a skin of its own: Raintile copies its sections into the launcher (into `@Resources\Generated\Grid.inc`), inside a container as large as the tile. So:

- Coordinates start at the top left corner of the tile.
- `[Rainmeter]`, `[Metadata]` and the `[Option:...]` sections are left out. `Name=` and `Information=` of `[Metadata]` are shown in the Options window.
- **Section names get a prefix** (`[Read]` becomes `[CW11_Read]`): references written as `[Section]`, `[Section:...]` and `MeasureName=` are renamed by themselves; anywhere else (in bangs) write [`#WIDGET:Read#`](#variables-raintile-fills-in), or `#CURRENTSECTION#` in a section's own actions.
- **Its `[Variables]`** are written in place of `#Name#` before the widget is added (so `!SetVariable` on one of them does not change the meters). Prefer names of your own (`MyClockColor`).
- The launcher has no update cycle of its own (`Update=-1`): while the widget is on screen, Raintile updates its measures and meters every `DashInterval` ms (1 s by default), and not at all while it is hidden. Work that should not run that often (reading files, starting a script) goes in [OnShow](#onshow-and-onhide), or in a RunCommand measure started with `!CommandMeasure` (updating it does not run it).
- The file must be UTF-8 (or ANSI), not UTF-16.
- When the file changes, refresh the skin: Raintile writes the launcher's widgets again.

## Variables Raintile fills in

| Variable | Is |
| --- | --- |
| `#WIDGETW#`, `#WIDGETH#` | the size of the tile, in pixels (with `Size=` larger) |
| `#WIDGETPATH#` | the widget's folder, with a backslash at the end: `#WIDGETPATH#icon.png`, `"#WIDGETPATH#read.ps1"` |
| `#WIDGET:<Section>#` | the name a section of the widget has in the launcher: `[!CommandMeasure #WIDGET:Read# "Run"]` |
| `#WIDGETOPTION#` | the tile's `WidgetOption=` (Options: the tile's *Widget setting*), empty without one: e.g. which game. Two tiles of the same widget can have different ones: give files that depend on it its value in their name (`List=list_#WIDGETOPTION#.txt`) |
| `#OPTION:<Name>#` | the value of one of [its settings](#settings-of-a-widget) (not of a `secret` one: empty) |
| `#SETTINGSPATH#` | (Rainmeter's) the folder of Rainmeter's settings: Raintile's own are in `#SETTINGSPATH#Raintile\Settings.inc` |
| `#CURRENTSECTION#` | (Rainmeter's) the section the action belongs to |

## The Raintile section

What the widget asks of Raintile:

```ini
[Raintile]
OnShow=[!CommandMeasure #WIDGET:Read# "Run"]
OnHide=
List=list.txt
ListY=
```

Raintile writes no title on a custom widget's tile (the tile's `Label=` is not used): the whole tile is the widget's, and a widget that wants a title draws it with a meter of its own.

### OnShow and OnHide

Bangs run when the widget's category comes on screen (the launcher opens on it, or the menu goes to it) and when it leaves the screen (another category, the launcher hidden). This is where a widget starts its work: reading its data, loading something. Nothing runs while the launcher is hidden.

### Lists

`List=<file>`: a file in the widget's folder (or a full path) that Raintile draws as rows, one per line:

```
<title>|<subtitle>|<icon>|<command>
```

| Field | |
| --- | --- |
| title | the row's text (a row without one is left out) |
| subtitle | a smaller line under it (e.g. `Played 3 days ago`); may be empty |
| icon | an image file (full path); may be empty |
| command | what a click on the row runs: a bang (starting with `[`), or a program, file or address, opened like a tile's `Command` (`modrinth://...`, `"C:\Games\x.exe"`); empty: nothing |

The rows start at the top of the tile, or at `ListY=` (pixels or a formula from the tile's top, e.g. `ListY=(#WIDGETH#*0.2)`) to leave room for a title of the widget's own; as many as fit (at most 10; more cells for the tile, more rows). Each row is a [part](#parts-of-a-tile): Raintile's highlight goes onto it, and the launcher hides after a click like after a tile (`CloseOnLaunch`). A file with no rows shows *Nothing to show yet*. Write the file UTF-8, `|` and line breaks out of the fields, and replace it whole (write a `.tmp`, then move it): Raintile may read it at any time.

A widget can have a list and meters of its own (e.g. a picture behind the rows), or only a list.

### WidgetChanged()

When its data changed, the widget calls:

```ini
[!CommandMeasure MeasureScript "WidgetChanged()"]
```

and Raintile reads its list again and draws the tile. The usual place is the `FinishAction` of the RunCommand measure that wrote the file. Raintile also reads the list when the category comes on screen, so the last one shows at once while the new one is read.

## Settings of a widget

A widget can have settings of its own, the same for all its tiles: Options > Widgets shows one entry per installed widget, with its settings. Each one is an `[Option:<Name>]` section (`<Name>`: letters, digits, `_`):

```ini
[Option:ApiKey]
Label=Steam Web API key
Kind=secret
Help=Free, from steamcommunity.com/dev/apikey.

[Option:Rows]
Label=Rows
Kind=choice
Choices=3|6|10
Default=6
```

| Key | |
| --- | --- |
| `Label` | the name shown (default: `<Name>`) |
| `Kind` | `text` (default), `secret` (a key or password: hidden, saved encrypted), `bool` (`1`/`0`), `number` (the box takes only a number, decimals and a minus sign included; one not finished, such as `-`, is outlined in red and not saved), `choice` (a drop-down list) |
| `Choices` | for `choice`: the values, separated by `\|` |
| `Default` | the value until the user sets one |
| `Help` | a line under it |

The values are saved in the widget's folder, `settings.inc`, one `<Name>=<value>` per line (an update from the gallery keeps the file). The launcher writes them in place of `#OPTION:<Name>#` in the `.ini` (the file is read again when the settings change), and scripts read the file: pass it as `-Settings "#WIDGETPATH#settings.inc"`. A `secret` is never written into the launcher; see [Keys of the user's](#keys-of-the-users).

Settings of one tile only (which game, which folder) go in its `WidgetOption=` instead ([`#WIDGETOPTION#`](#variables-raintile-fills-in)).

## Parts of a tile

A meter with `Part=1` is a part of the tile: pointed at and clicked on its own, with Raintile's highlight (the same animation, colours and rounded corners as between tiles). Give it a `LeftMouseUpAction`:

```ini
[Play]
Meter=Shape
X=8
Y=(#WIDGETH#/2)
Shape=Rectangle 0,0,(#WIDGETW#-16),40,8 | Fill Color 255,255,255,30 | StrokeWidth 0
Part=1
LeftMouseUpAction=["steam://rungameid/570"]
```

- The part is the meter's rectangle: write `X=` and `Y=` as numbers or formulas from the tile's top left corner (not `r`/`R`, relative to the meter before).
- A tile with parts is never highlighted whole: between two parts the highlight stays on the last one.
- The meter's own `MouseOverAction` / `MouseLeaveAction` still run.
- The keyboard and the gamepad go from part to part too: coming onto the tile the highlight lands on the part nearest the side it comes from, the arrows (D-pad) move to the next part in that direction, and past the last one onto the next tile; `Enter` / `A` does what a click on the part does (its `LeftMouseUpAction`; a row of a list: its command). With the mouse on a part, the keys go on from it.

## Getting data: scripts

A widget that needs data from outside (a program's database, a web service, files) brings its own script and runs it with a RunCommand measure:

```ini
[Read]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
Parameter=-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "#WIDGETPATH#read.ps1" -Out "#WIDGETPATH#list.txt"
State=Hide
OutputType=UTF8
FinishAction=[!CommandMeasure MeasureScript "WidgetChanged()"]
```

- Windows PowerShell 5.1 (included in Windows): no PowerShell 7 syntax. C# through `Add-Type` is C# 5.
- **Do the least work**: check first whether anything changed (the date of the source against the date of your list) and exit at once if not; the script runs every time the category comes on screen.
- **Read other programs' data read only.** SQLite databases: the SQLite of Windows (`winsqlite3.dll`, in Windows 10 and 11) opened with `file:<path>?mode=ro`; see [`Modrinth.ps1`](../widgets/Modrinth/Modrinth.ps1).
- Write into the widget's folder, whole files (`.tmp`, then move).
- Network: `https` only, and only to the service the widget is about.

### Keys of the user's

A widget that needs an account key asks for it as a `secret` [setting](#settings-of-a-widget). The Options window saves it encrypted with Windows DPAPI for the current user, `<Name>=dpapi:<base64>` in `settings.inc`, with the entropy `Raintile SteamGridDB key` (UTF-8). In PowerShell:

```powershell
Add-Type -AssemblyName System.Security
$bytes = [Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($stored.Substring(6)),
    [Text.Encoding]::UTF8.GetBytes('Raintile SteamGridDB key'), [Security.Cryptography.DataProtectionScope]::CurrentUser)
$key = [Text.Encoding]::UTF8.GetString($bytes)
```

Use a key only for the service it is for, never write it to a file or a log, and say on a row how to add it when it is missing (see [`SteamAchievements.ps1`](../widgets/SteamAchievements/SteamAchievements.ps1)).

## Rules

- A widget is self-contained: its files in its folder, nothing installed elsewhere, nothing left running.
- Nothing runs while the launcher is hidden: no timers, no polling; work starts from `OnShow` (and can stop on `OnHide`).
- No plugins beyond Rainmeter's own (and HotKey); no DLLs of your own.
- Text: ASCII in the `.ini` and the scripts (`[\xHHHH]` in a meter's text for other characters), files UTF-8 without BOM.
- Widgets are Rainmeter code and can run programs: the gallery reviews them before they are listed.

## Testing

1. Copy the folder to `Widgets\<Id>\` in the data folder (with the repository linked as the skin, `widgets\<Id>\` of the repository is not read by the launcher).
2. Add a tile with `Widget=custom`, `Param=<Id>`, refresh the skin.
3. A widget that is not shown says why on its tile: the file looked for, a file with no meters and no `List=`, a UTF-16 file.
4. Errors of formulas and bangs go to Rainmeter's log (Manage > Log), under the names with the prefix (`CW11_Read`).

## Publishing in the gallery

Add an entry to [`widgets/index.json`](../widgets/index.json), and the folder to `widgets/<Id>/` if it is hosted here: see [widgets/README.md](../widgets/README.md). With nightly builds the gallery reads the list of the `nightly` branch, so a widget can be tried there before a release.
