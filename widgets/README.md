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
- `kind`: `custom` (files downloaded to the Widgets folder, `Widget=custom`, `Param=<id>`), `skin` (an `.rmskin` package, opened with the Rainmeter installer: give it as `package`, and its `skin` as `<config>\<file>.ini` for `Widget=skin`) or `builtin` (a widget of Raintile itself, nothing to download: `widget`, `param` and optionally `size` are the `Widget=`, `Param=` and `Size=` of the tile **Add as a tile** creates, e.g. `list` / `modrinth` / `1x2`). Versions that do not know a kind leave its entries out.
- `category`: where the widget fits, and where its tile goes by default (the gallery groups widgets by it): `General` (anywhere: the category open last, or the Dashboard) or the name of one of Raintile's categories, e.g. `Games`, `Apps`, `Dashboard` (the user's category of that file or menu name; `General` when there is none). Missing: `General`.
- `base` and `files`: the folder the files are downloaded from and their names (no subfolders). Addresses must be `https` on GitHub (`raw.githubusercontent.com`, or `github.com` for release downloads). A `base` that is not an address (e.g. `MyWidget`) is a folder next to `index.json`, on the same branch: Options reads the list of `main`, or of `nightly` with nightly builds (Options > Advanced > Updates), so a widget can be tried there before a release. Only versions after 1.2.2 understand it: widgets meant for older ones keep a full address.
- `version`: change it when the files change: the gallery offers the update.
- Widgets are Rainmeter code and can run programs: entries are reviewed before they are merged. Prefer a fixed commit or tag in `base` over a branch, so the files cannot change after the review.
- A widget's own `[Variables]` work as usual in its file: Raintile writes their values in place of `#Name#` when it adds the widget to the launcher (so changing one with `!SetVariable` does not change the meters). `#WIDGETW#` and `#WIDGETH#` are the size of the tile.

## Parts of a tile

A widget can split its tile into parts that are pointed at and clicked on their own: give the meter of each part `Part=1` and its own `LeftMouseUpAction`. Raintile's highlight then goes onto the part under the mouse, with the same animation as between tiles (and its colours and rounded corners), and a click runs the part's action instead of the tile's. Parts are rectangles: the meter's X, Y, W and H inside the tile; write X and Y as numbers or formulas from the tile's top left corner (not relative to the meter before, `r`/`R`). The whole tile is never highlighted: between two parts the highlight stays on the last one. Its own `MouseOverAction` / `MouseLeaveAction`, if any, still run.

`QuadTest` (not in the gallery) is an example: four smaller tiles in a 2 x 2 grid, starting Notepad, Calculator, Explorer and Task Manager. Copy `QuadTest\QuadTest.ini` to `Widgets\QuadTest\` in your data folder and add a tile with `Widget=custom`, `Param=QuadTest`, `Size=2x2`. The keyboard and the gamepad still select the whole tile.
