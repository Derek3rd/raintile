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
  "description": "The time in big letters, with the day and the date.",
  "base": "https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<folder>",
  "files": ["BigClock.ini", "background.png"],
  "page": "https://github.com/<owner>/<repo>/tree/<branch>/<folder>"
}
```

- `id`: letters, digits, `.`, `_` and `-`; also the name of the folder it is installed to (`Widgets\<id>\`) and of its main file, `<id>.ini`.
- `kind`: `custom` (files downloaded to the Widgets folder, `Widget=custom`, `Param=<id>`) or `skin` (an `.rmskin` package, opened with the Rainmeter installer: give it as `package`, and its `skin` as `<config>\<file>.ini` for `Widget=skin`).
- `base` and `files`: the folder the files are downloaded from and their names (no subfolders). Addresses must be `https` on GitHub (`raw.githubusercontent.com`, or `github.com` for release downloads).
- `version`: change it when the files change: the gallery offers the update.
- Widgets are Rainmeter code and can run programs: entries are reviewed before they are merged. Prefer a fixed commit or tag in `base` over a branch, so the files cannot change after the review.
- A widget's own `[Variables]` work as usual in its file: Raintile writes their values in place of `#Name#` when it adds the widget to the launcher (so changing one with `!SetVariable` does not change the meters). `#WIDGETW#` and `#WIDGETH#` are the size of the tile.

## Parts of a tile

A widget can split its tile into parts that are pointed at and clicked on their own: give the meter of each part `Part=1` and its own `LeftMouseUpAction`. Raintile's highlight then goes onto the part under the mouse, with the same animation as between tiles (and its colours and rounded corners), and a click runs the part's action instead of the tile's. Parts are rectangles: the meter's X, Y, W and H inside the tile. Its own `MouseOverAction` / `MouseLeaveAction`, if any, still run.

`QuadTest` (not in the gallery) is an example: four smaller tiles in a 2 x 2 grid, starting Notepad, Calculator, Explorer and Task Manager. Copy `QuadTest\QuadTest.ini` to `Widgets\QuadTest\` in your data folder and add a tile with `Widget=custom`, `Param=QuadTest`, `Size=2x2`. The keyboard and the gamepad still select the whole tile.
