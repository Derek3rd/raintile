# The Options window: UI rules

How the Options window looks and behaves, so that every page works the same way.
These rules apply to the Options program (`src/Options/`, `RaintileOptions.exe`) and
to its PowerShell fallback (`@Resources/Scripts/Options.ps1`), which share the
styles of `@Resources/Scripts/Options.xaml`.

Most rules are already code: the constants and helpers in `src/Options/Ui.cs`
(`Glyph`, `Fs`, `Gap`, `FieldWidth`, `NewHelp`, `NewSectionTitle`, `NewLabelBlock`,
`NewClearButton`, `NewDeleteButton`, `NewResetIcon`, `SetActionVisible`,
`MarkInvalid`, `SetTrimmed`, `NewNumberField`, `NewSizeField`, `NewEqualButtons`,
`ShowDialog`), and in `Categories.cs` the stacked row `NewFormRow` with
`SetFormHelp`. Build new UI with them: no glyph codes,
font sizes or margins written by hand. When a page needs something the helpers do
not have, add it to `Ui.cs` and to this page, not to the page's own file.
`Options.ps1` has the same rules as `$GLYPH`, `$FS`, `$GAP`, `$FIELD`, `New-Help`,
`New-SectionTitle`, `New-ActionIcon`, `Set-ActionVisible`, `Set-Invalid`, `Set-Trimmed`
and `Show-Dialog -Danger`.

## 1. Nothing only in a tooltip

The window is used with the mouse, the keyboard and the gamepad: hovering is not
always possible.

- Every field has its help as text under its label (`NewLabelBlock`): what it does,
  its default, what an empty value means. Current values (a default taken from
  All tiles, the file an image comes from) are shown the same way.
- A tooltip is only for:
  - the name of an icon button (always: it has no text of its own);
  - the full text of something cut with an ellipsis (always: `SetTrimmed` shows it
    only when the text is actually cut);
  - a keyboard shortcut (Ctrl+S on Save).

## 2. One glyph, one action

Icon buttons use the `IconButton` style and the glyphs of `Glyph` (Segoe MDL2 Assets):

| Glyph | Constant | Action | Tooltip wording |
|---|---|---|---|
| `0xE7A7` | `Glyph.Reset` | Back to the default, or to the value inherited from All tiles | "Restore default", "Back to the value of All tiles" |
| `0xE711` | `Glyph.Clear` | Empty a field (colour, hot key), take an entry out of a list (a folder): no file is deleted | "Clear ...", "Remove ... from the list" |
| `0xE74D` | `Glyph.Delete` | Something that goes away or to the Recycle Bin (tile, category, image, widget): always confirmed | "Delete ..." |
| `0xE710` | `Glyph.Add` | A new entry | "New ..." |
| `0xE74A` `0xE74B` `0xE72B` `0xE72A` | `Glyph.Up` `Down` `Left` `Right` | Move an entry in a list | "Move up", ... |

- Chevrons (`0xE70D`, `0xE76C`) only open and close groups of the menu.
- An icon button that would do nothing (the value is already the default, the field
  is already empty) is hidden with `SetActionVisible`: `Visibility.Hidden`, so its
  room stays and nothing moves. Never dim it by hand.
- A list toolbar button that cannot act on the selection (Delete on All tiles) is
  disabled: the style dims it.

## 3. The control for each kind of value

| Value | Control |
|---|---|
| On / off | Switch (`CheckBox`) |
| One of up to ~5 choices | Segments (`Segment`) |
| One of more choices, or a list read from disk | Combo |
| Several of a fixed set | Switches with their labels |
| A number in a range worth dragging (counts, ms, pt, zoom, opacity) | Slider + text box + unit |
| A length that can be pixels or a share of the screen | `size`: text box + px / % |
| An identifier or a huge range (a port) | Text box + unit (`NoSlider` in the schema) |
| A colour | Swatch + text box |
| A key | Key button + clear |
| Text, path | Text box (paths: + "Browse...") |

- The unit is always shown (px, pt, ms, s, %, ×, steps, columns, rows): numbers without
  one reserve its room, so sliders line up.
- The same kind of value gets the same control on every page (a grid size, an
  opacity, a zoom look the same in Settings and in the category editor).
- A value that is not valid gets the red border (`MarkInvalid`) and is not saved
  until it is fixed; a valid one clears the border.

## 4. Rows and layout

Two row templates, with the same fonts and spacing:

- **Side by side** (settings pages): label and help on the left (`*`), the control
  (`Auto`), then a 34 px column for the row's reset or clear button.
- **Stacked** (narrow panes: the category and tile editor): label and help on top,
  the control below at the full width of the column, the 34 px action column on
  its right.

Widths:

- Fields use `FieldWidth.S` (80: numbers, sizes), `FieldWidth.M` (220: colours,
  combos, short text) or `FieldWidth.L` (300: text, paths, fonts), or fill the
  column. No other widths.
- Panels of segments or switches wrap within `FieldWidth.Wrap` (470).
- A row of buttons is either all `Auto` and aligned to the start, or all the same
  width filling the row (`UniformGrid`): never mixed.

## 5. Type sizes (`Fs`)

| Use | Size |
|---|---|
| Page title | `Fs.Title` 24, SemiBold |
| Section (card) title | `Fs.Section` 11.5, SemiBold, upper case, dim |
| Label, name of an entry in a list | `Fs.Label` 13.5 |
| Help, hint, status, notes, values | `Fs.Help` 12, dim (accent for a note that asks for an action) |
| Badges and chips | `Fs.Badge` 11 |
| Caption under a thumbnail (tiles strip) | `Fs.Help` 12 |

The window chrome keeps its own: the name in the menu (21) and its version (12), the
title of the saving overlay (17).

## 6. Spacing (`Gap`)

- Page: margin 36, 4, 36, 24 (`Gap.Page`); the footer lines up with it.
- Cards: the `Card` style; 16 between cards (`Gap.Card`).
- Rows: 11 above and below in side-by-side rows (`Gap.Row`), 8 in stacked rows
  (`Gap.StackedRow`).
- 8 between controls and between buttons (`Gap.Control`); an icon button after a
  field: 6 (`Gap.Icon`, the button has its own padding).

## 7. Buttons and dialogs

- `AccentButton`: the one main action of a section or of a dialog. Not more than one
  per card.
- `DangerButton`: an action that deletes or cannot be undone. It is never the
  default button.
- Order: the main action first, Cancel or Close last; the window's footer too
  ("Save and refresh", "Close").
- Dialogs use `ShowDialog`, titled with the action ("Delete tile", "Update Raintile"),
  not "Raintile". A destructive question uses `ShowDialog(..., danger: true)`: its
  first button is red and Cancel is the default (Enter and Escape cancel).
- Ask before anything is deleted or sent to the Recycle Bin, and before removing
  more than one entry at once. Clearing a field is not asked: Close without saving
  undoes it.

## 8. Words

- English, sentence case ("Direct update", "Open the folder"), British spelling
  (colour, centre). Names of the launcher's own things stay as they are
  (Favorites, Recent).
- Delete = goes away or to the Recycle Bin. Remove = taken out of a list, nothing
  is deleted. Clear = a field is emptied.
- "Browse..." picks a file or a folder; a button that opens a dialog ends with "...".
  Always three ASCII dots, in buttons and in statuses ("Checking..."), as in the
  ASCII-only fallback.
- "Cancel" in dialogs. "cannot", not "can not".
- Statuses are sentences with a full stop: "Saved.", "Unsaved changes.",
  "Download failed: ...", "The search could not start: ...".

## 9. Lists

- A list with actions has them as icon buttons in its card header (as the tiles
  strip); actions with a long name ("Open") stay text buttons there.
- An empty list says so in its place, in `Fs.Help`, with what to do ("No tiles yet:
  add one with the + button.").
- Long names are cut with `SetTrimmed`.

## 10. When changes are written

- Changes wait for "Save and refresh" (the status says "Unsaved changes."), and
  closing the window asks.
- Operations on files that happen at once (sending an image or a category to the
  Recycle Bin, adding tiles from Import or the widget gallery) say so in their help,
  and the destructive ones ask first.

## 11. Checklist for a change to the window

- [ ] Glyphs, sizes, widths and margins come from `Ui.cs`.
- [ ] Every field shows its help; tooltips only name icon buttons, show cut text or
      shortcuts.
- [ ] The control matches the kind of value, and has its unit.
- [ ] Icon buttons that cannot act are hidden; list buttons that cannot act are
      disabled.
- [ ] Deleting asks, with `danger: true`; the button says Delete, Remove or Clear as
      in "Words".
- [ ] Works with the keyboard and the gamepad, without hovering.
- [ ] Fits the narrowest window (960 px): nothing cut without its tooltip.
- [ ] The same change in `Options.ps1`, when the page exists there too.
