# Raintile widgets

The widgets of the gallery in Options > Dashboard. [`index.json`](index.json) is the list the Options window reads; the widgets can live in this folder (`widgets/<id>/`) or in their authors' own repositories.

How to write a custom widget: [Guide > Custom widgets](../docs/Guide.md#custom-widgets).

## Adding a widget

Open a pull request that adds an entry to `index.json` (and, if you want it hosted here, its folder):

```json
{
  "id": "BigClock",
  "name": "Big clock",
  "author": "Raintile",
  "version": "1.0",
  "kind": "custom",
  "category": "General",
  "description": "The time in big letters, with the day and the date.",
  "base": "https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<folder>",
  "files": ["BigClock.ini", "background.png"],
  "page": "https://github.com/<owner>/<repo>/tree/<branch>/<folder>"
}
```

- `id`: letters, digits, `.`, `_` and `-`; also the name of the folder it is installed to (`Widgets\<id>\`) and of its main file, `<id>.ini`.
- `kind`: `custom` (files downloaded to the Widgets folder, `Widget=custom`, `Param=<id>`) or `skin` (an `.rmskin` package, opened with the Rainmeter installer: give it as `package`, and its `skin` as `<config>\<file>.ini` for `Widget=skin`).
- `category`: where the widget fits, and where its tile goes by default (the gallery groups widgets by it): `General` (anywhere: the category open last, or the Dashboard) or the name of one of Raintile's categories, e.g. `Games`, `Apps`, `Dashboard` (the user's category of that file or menu name; `General` when there is none). Missing: `General`.
- `base` and `files`: the folder the files are downloaded from and their names (no subfolders). Addresses must be `https` on GitHub (`raw.githubusercontent.com`, or `github.com` for release downloads). A `base` that is not an address (e.g. `MyWidget`) is a folder next to `index.json`, on the same branch: Options reads the list of `main`, or of `nightly` with nightly builds (Options > Advanced > Updates), so a widget can be tried there before a release. Only versions after 1.2.2 understand it: widgets meant for older ones keep a full address.
- `version`: change it when the files change: the gallery offers the update.
- Widgets are Rainmeter code and can run programs: entries are reviewed before they are merged. Prefer a fixed commit or tag in `base` over a branch, so the files cannot change after the review.
- A widget's own `[Variables]` work as usual in its file: Raintile writes their values in place of `#Name#` when it adds the widget to the launcher (so changing one with `!SetVariable` does not change the meters). `#WIDGETW#` and `#WIDGETH#` are the size of the tile.

## Parts of a tile

A widget can split its tile into parts that are pointed at and clicked on their own: give the meter of each part `Part=1` and its own `LeftMouseUpAction`. Raintile's highlight then goes onto the part under the mouse, with the same animation as between tiles (and its colours and rounded corners), and a click runs the part's action instead of the tile's. Parts are rectangles: the meter's X, Y, W and H inside the tile; write X and Y as numbers or formulas from the tile's top left corner (not relative to the meter before, `r`/`R`). The whole tile is never highlighted: between two parts the highlight stays on the last one. Its own `MouseOverAction` / `MouseLeaveAction`, if any, still run.

`QuadTest` (not in the gallery) is an example: four smaller tiles in a 2 x 2 grid, starting Notepad, Calculator, Explorer and Task Manager. Copy `QuadTest\QuadTest.ini` to `Widgets\QuadTest\` in your data folder and add a tile with `Widget=custom`, `Param=QuadTest`, `Size=2x2`. The keyboard and the gamepad still select the whole tile.

## What Raintile does for a widget

A `[Raintile]` section in the widget's file asks Raintile for more:

```ini
[Raintile]
OnShow=[!CommandMeasure #WIDGET:Read# "Run"]
OnHide=
List=list.txt
```

- `OnShow` / `OnHide`: bangs run when the widget's category comes on screen and when it leaves it (another category, or the launcher hidden). Nothing runs while the launcher is hidden: start work here, not with timers.
- `List`: a file in the widget's folder (or a full path), one row per line: `<title>|<subtitle>|<icon>|<command>`. Raintile draws the rows in the tile under its title, as many as fit (icon, title, subtitle in small letters), each one a part with Raintile's highlight; a click runs its command: a bang (starting with `[`), or a program, file or address opened like a tile's `Command`.
- `#WIDGET:<Section>#`, in any value of the widget: the name that section has in the launcher (Raintile renames the sections of a widget), e.g. for `!CommandMeasure`.
- When its data changed, the widget calls `[!CommandMeasure MeasureScript "WidgetChanged()"]` (e.g. in the `FinishAction` of a RunCommand measure): Raintile reads its `List` file again and draws it.

`Modrinth` is an example: on `OnShow` its RunCommand measure starts `Modrinth.ps1`, which reads Modrinth App's database (read only, with the SQLite of Windows) into `list.txt` only when it changed, then calls `WidgetChanged()`.
