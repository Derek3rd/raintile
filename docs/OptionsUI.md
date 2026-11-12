# The Options window: UI rules

How the Options window looks and behaves, so that every page works the same way.
These rules apply to the Options program (`src/Options/`, `RaintileOptions.exe`),
whose styles are in `@Resources/Scripts/Options.xaml`.

Most rules are already code: the constants and helpers in `src/Options/Ui.cs`
(`Glyph`, `Fs`, `Gap`, `FieldWidth`, `NewHelp`, `NewSectionTitle`, `NewLabelBlock`,
`NewClearButton`, `NewDeleteButton`, `NewResetIcon`, `SetActionVisible`,
`MarkInvalid`, `SetTrimmed`, `NewNumberField`, `NewSizeField`, `NewChoiceBox` with
`SelectChoice` / `ChoiceValue` / `SetChoices`, `NumericOnly`, `NewEqualButtons`, `AddRowNote`, `ShowDialog`), and in `Categories.cs` the stacked row `NewFormRow` with
`SetFormHelp`. Build new UI with them: no glyph codes,
font sizes or margins written by hand. When a page needs something the helpers do
not have, add it to `Ui.cs` and to this page, not to the page's own file.

`python tools/check.py` fails on a glyph code, a font size, or a margin or padding
with a number other than 0 written by hand in `src/Options/` (outside `Ui.cs`). Where a value really has to be its
own (a drawing on a thumbnail, the menu chrome, the on-screen keyboard, the launcher
preview), the line says why with a comment `ui-exempt: <why>`. The XAML of the window
(`Options.xaml` and the window's frame: menu, header, footer) is the chrome and is not
checked.

## 0. Where a setting goes

Settings are placed **by the part of the launcher they change**, not by the kind of
value: a part's sizes, font size, colours and timing live on its page. Only what
several parts share has a page of its own: **Theme** (the font, the text colours,
background, accent, highlight) and **Animations** (effects of the whole launcher).

| Part of the launcher | Page |
| --- | --- |
| Saved sets of the settings (profiles): pick, load, save, delete | General (its first card) |
| Where it shows, its mode (full screen, window, docked), margins, opening and closing | General |
| Grid or wheel, scrolling and spacing of both, the tile itself in both (colour, corners, inner margin, highlight, label) | Tiles |
| Rows and columns, the grid tiles' logo size, scroll direction, edge fade, how the background images move, scrollbar | Tiles > Grid |
| The wheel's shape, its thumbnails, its backdrop, its turning, its inner wheel of categories | Tiles > Wheel |
| The play time line, Steam updates on the tiles | Tiles > Play time and updates |
| The category menu and its colours, Favorites, the buttons of the top row | Top row |
| Recent, Not played yet | Top row > Recent and Not played yet |
| Time and date | Top row > Clock |
| Search bar, filter bar | Top row > Search |
| Shared font and colours | Theme |
| Effects, appearing tiles, smoothing, tile launch | Animations |
| Opening keys, tile hot keys; navigation keys; the gamepad | Keybindings; > Keyboard; > Gamepad |
| Where to look for games and apps, your folders, where they go | Import |
| The games and apps found, the tiles no longer installed | Import > Found |
| Widgets, Categories | their pages |
| Performance, diagnostics | Advanced |
| The updates (check, channel) with the installed and latest version | Info > Updates |

- A new setting: find its part in the table. A new part gets a row here (and its
  page, or a group on the page of the part it belongs to) in the same PR.
- **Settings of one layout.** What only the grid uses (rows and columns, `Size=`, the
  logo size, the backgrounds' styles, the scrollbar) is on Tiles > Grid; what only the
  wheel uses is on Tiles > Wheel; Tiles holds what both use, with a help that says
  what it does in each when that differs (the mouse wheel notch: rows, or tiles). A
  setting of one layout elsewhere has `When = "ScrollMode=..."`. In the tile editor
  (Categories) a row of the other layout is disabled with its reason
  (`AddGridOnlyReason`), and the preview shows the tile of the layout in use: the
  grid's tile, or the wheel's thumbnail. In the wheel the thumbnail is the tile; when
  the selected tile's logo or lines go on the backdrop, **Place on** switches the
  preview to the backdrop, whose keys are its own (`BackLogoPos`, `BackLogoScale`,
  `BackInfoPos`): a place is edited where it is seen, at its real size, and what does
  not exist there (the framing of the backdrop, a logo kept on the thumbnail) is
  disabled with its reason (docs/Guide.md, "Grid or wheel").
- **The switch before what it switches.** A setting that decides which others apply
  (a mode, a choice of layout, a feature on or off) is the first of its page or group;
  the pages of its modes are sub-pages of the page holding it (Grid / Wheel under
  Tiles, with the choice on Tiles).
- **What does not apply is disabled, not hidden.** A setting that only applies with
  another one has `When = "Key=value"` in `SchemaData.cs` (values separated by `|`,
  conditions by `;`): while it does not apply its control is disabled (the gamepad
  passes over it), its label dimmed, and the reason shown under it in the accent
  colour, from the labels of the settings it needs ("Only with Layout: Wheel (Tiles
  page)."). Built by `AddRowReason` / `SetRowApplies` in `Ui.cs`. The three cases,
  and nothing else:

  | The setting does not apply because | It is | The reason |
  | --- | --- | --- |
  | another setting (`Item.When`, `Group.When`, `Page.When`), also on another page or in the tile editor | disabled | in the accent colour under its label (the card's title, for a whole card; the menu entry is greyed out, for a page) |
  | the switch of its card or of its page is off | disabled | none: the switch is right above |
  | the thing being edited cannot have it (the framing or the logo of a widget tile) | hidden | none: it never applies there |

  So a setting is never hidden because of another setting, and a disabled one
  always shows why unless its own switch is in view.
- **The settings of one mode together.** Settings that all apply with the same
  other one, set outside their group (the window's size, the docked side and size
  with Mode), make a group of their own with the `When` on the group
  (`Group.When`): the whole card is disabled, the reason once under its title
  (`AddCardReason` / `SetCardApplies`), and its settings carry no `When` of that
  mode; a setting of the card that also needs another one keeps its own `When`.
  Their labels do not repeat the group's name (Window > Width, not Window width).
- **Where a switch goes.** A bool that turns a part of the launcher on or off sits
  as high as the part it turns off:
  - the whole page is one part (the clock, keyboard navigation, the gamepad): beside
    the page title;
  - the page holds several parts, each with its own switch (Recent and Not played
    yet; the filter bar on Search; the labels on Tiles): in the header of each card;
  - the part cannot be turned off (the search bar): no switch, the page starts with
    its settings.
- **A switch for a whole page goes beside its title.** It is `Switch = "Key"` on the
  page (`Page.Switch`, the first setting of its first group): the switch and its
  reset are at the right of the page title (`PageSwitch` in the window's header), the
  page title is its label (the setting's own label is only its accessible name), and
  every card of the page is disabled while it is off. With the gamepad, right from
  the menu lands on it first.
- **A switch for a whole group goes in its header.** It is `Switch = "Key"` on the
  group (`Group.Switch`, the first of its items): the card's header is its label,
  upper case like any card title, with the switch and its reset in the control and
  action columns (`NewSwitchCard`); its help (or the group's) is under the header;
  the other settings of the group are disabled while it is off, with no reason under
  them (the switch is right above). Its label names the part ("Filter bar",
  "Labels"), not "Show ...": it is the title of the card.
- **A card** is, from the top: a header (its title, or its switch), then its help,
  then its rows; each of the three can be missing. A row draws the line above it,
  which parts it from what comes before: the first row of a card with no header and
  no help has none (the card's border is there). `NewCard`, `NewSwitchCard` and
  `NewRow` do it (`CardStack`, `CardRow` in `Ui.cs`): a card built by hand uses them,
  never its own lines.
- **Which cards have a title.** Only the first card of a page may have none: it holds
  the settings of the page itself (its mode, what the whole page is about), which
  the page title already names. Every other card has a title or a switch, so the
  page reads as its parts.
- **No title twice.** A card title never repeats its page's title, and a page's only
  card has no title (the page has it), unless its header is a switch.
- **A page for one mode** (Grid, Wheel) has the `When` on the page instead
  (`Page.When`): while the mode is not in use its menu entry is greyed out and
  passed over (keyboard, gamepad), and its settings carry no `When` of that mode.
  The help of the switch says the other page is greyed out, so it is never only in
  a tooltip.
- Order on a page: the switch, then layout and sizes, the look, the behaviour, the
  timing.
- **What concerns one thing stays together**, in the order it is used: the time
  format and its font size, then the date and its format; the height of an entry
  and its font, then its icon and the icon's spacing, then the spacing between
  entries, then the colours. A setting that depends on another comes right after it.
- A page holds settings: a line of text that sets nothing is the help of the setting or
  card it is about, or the page's description, never a row of its own.
- A group (card) is one part of the launcher. A page with fewer than about four
  settings joins the page of its part as a group.
- Two menu levels at most. A menu entry with sub-pages is a page of its own (the
  switch and what the sub-pages share), never only a folder.
- `tools/check.py` checks that every `When` (of a setting, a group or a page) names a setting and values it can take,
  that a switch on the same page comes before what it switches, that a group's or a
  page's `Switch` is its first setting and a bool, that no card is titled as its page, that
  a page's only card has no title, that every card after the first has a title or a
  switch, and that every page is in the menu (`NavTree`) once.

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
- A state to notice that is not a setting's value (General > Profiles: the settings in
  the window differ from the profile shown) is a note in the accent colour under the
  label of its row (`AddRowNote`, as the reason of a row that does not apply; `AddFormNote`
  under the help of a stacked row: the tile's background too small for the screen), shown
  only while it holds.

## 2. One glyph, one action

Icon buttons use the `IconButton` style and the glyphs of `Glyph` (Segoe MDL2 Assets):

| Glyph | Constant | Action | Tooltip wording |
|---|---|---|---|
| `0xE7A7` | `Glyph.Reset` | **A field** goes back to its default, or to the value of All tiles | "Restore default", "Back to the value of All tiles" |
| `0xE70F` | `Glyph.Edit` | **A row of a list** shown read-only (Import > Your folders) is edited in place; the same button ends the editing. Shown with the mouse over the row or the focus in it (faded out otherwise, so the pad still reaches it). **The entry picked in a combo** of entries saved on disk (General > Profiles) is renamed: in the action column of the combo's row, the new name asked in a dialog, hidden when the entry cannot be renamed | "Edit ...", "Done", "Rename ..." |
| `0xE711` | `Glyph.Clear` | **A field** is emptied: no key, no colour, no image, no icon. When the value is a file of the data folder (an image, an icon) the file goes to the Recycle Bin, asked first | "Clear the ..." |
| `0xE74D` | `Glyph.Delete` | **An entry of a list** goes away (a tile, a category): in the list's header, always asked | "Delete ..." |
| `0xE710` | `Glyph.Add` | A new entry of a list | "New ..." |
| `0xE74A` `0xE74B` `0xE72B` `0xE72A` | `Glyph.Up` `Down` `Left` `Right` | Move an entry in a list | "Move up", ... |
| `0xE72C` | `Glyph.Refresh` | **A list** is read again from where it comes from (Import > Found: the search runs again): at the right end of the list's filter row, disabled while it runs | "Search again" |

In short: the arrow and the x act on a field, in the action column of its row (or,
for a field with two values such as a pair of keys, right after each value); the bin
acts on a whole entry of a list, in the list's header; the pencil edits a row of a
list, or renames the entry picked in a combo. A field never has a bin.

- A new glyph is checked by drawing it (Segoe MDL2 Assets in a TextBlock, saved to a
  picture) before its constant goes into `Glyph`: codes are not written from memory.
- Chevrons (`0xE70D`, `0xE76C`) only open and close groups of the menu.
- Pad glyphs (`Glyph.PadA` `PadB` `PadX` `PadY` `PadLB` `PadRB` `PadLT` `PadRT` `PadStart`)
  only go before the text of what a gamepad button presses: a button of the window
  (`AddPadHint`, shown while the pad is in use) or a key of the on-screen keyboard
  (Delete, Space, Shift, symbols, Done). The keyboard's hint line names the other pad
  buttons by their glyphs too, never by their letters. Never an icon button of their own.
- The value of a gamepad setting is shown by its glyphs too (`NewPadFace`, with
  `Glyph.PadBack` `PadLS` `PadRS` and `PadDpad` plus the arrow for the D-pad): in its
  fields and on the dial that picks it. Their names are in the tooltips
  (`Schema.PAD_LABELS`).
- An icon button that would do nothing (the value is already the default, the field
  is already empty) is hidden with `SetActionVisible`: `Visibility.Hidden`, so its
  room stays and nothing moves. Never dim it by hand.
- A list toolbar button that cannot act on the selection (Delete on All tiles) is
  disabled: the style dims it.

## 3. The control for each kind of value

| Value | Control |
|---|---|
| On / off | Switch (`CheckBox`) |
| One of a fixed set, however few | Combo (`NewChoiceBox`) |
| One of a list read from disk | Combo |
| Several of a fixed set | Switches with their labels |
| A number in a range worth dragging (counts, ms, pt, zoom, opacity) | Slider + text box with its unit (`NewNumberField`) |
| A length that can be pixels or a share of the screen | `size`: text box + px / % combo (`NewSizeField`) |
| An identifier or a huge range (a port) | Text box with its unit (`NoSlider` in the schema) |
| A colour | Swatch + text box |
| A key | Key button + clear |
| Gamepad buttons (one, or two held together) | Two key buttons + clear, with the button's glyph (`NewPadControl`): clicked, the dial of the buttons around it; with the pad, A and then the button |
| Text, path | Text box (paths: + "Browse...") |

- No row of chips for a single choice: it wraps and clutters the page. Chips stay for
  several of a set. The filters of a list are combos too (Import > Found: the kind, the store or folder, the order), so a new kind or store adds an entry, not a chip.
- A unit of measure is always shown (px, pt, ms, s, %, ×, / 255, steps), inside the
  number's box on its right (the `UnitBox` style of `Options.xaml`: the unit is the
  box's `Tag`). A count has no unit when its label already says what it counts
  (Columns, Rows, Tiles in Recent); it keeps it when the label does not (a tile's
  Width in columns). Every number box is `FieldWidth.S` wide, so the boxes line up and
  the sliders before them take the rest of the row.
- Number boxes take only numbers (`NumericOnly`, already in `NewNumberField` and
  `NewSizeField`): typing and pasting change the text only into what can still be a
  number (`IsPartialNumber`): no letters or spaces, the minus sign once and at the
  start (only where the value can be negative: a slider whose minimum is below 0, a
  widget's number; never a size), one decimal point (a comma becomes it). The on-screen keyboard shows a number pad on them with the same rule
  (`NumericChars`): the keys that cannot type there are dimmed and skipped.
- With the gamepad every control is a stop the ring passes over, a slider too: `A`
  starts changing it (the ring goes, its thumb turns accent), left and right change
  it, `A` keeps the value and `B` puts it back. Left and right never change a value
  by themselves, or the control after it could not be reached.
- The same kind of value gets the same control on every page (a grid size, an
  opacity, a zoom look the same in Settings and in the category editor).
- A value that is not valid gets the red border (`MarkInvalid`) and is not saved
  until it is fixed; a valid one clears the border.

## 4. Rows and layout

Two row templates, with the same fonts and spacing:

- **Side by side** (settings pages): label and help on the left (`*`), the control
  column, then the action column.
- **Stacked** (narrow panes: the category and tile editor): label and help on top,
  the control below filling the column, the action column on its right.

Every row, of both kinds, ends with the **action column** (34 px, `Gap.ActionColumn`):
the row's reset or clear button, or nothing. It is there even when empty, so every
control of a card ends at the same right edge.

In side-by-side rows the **control column has one width for every page** (the
`ControlColumn` resource, set by `UpdateControlColumn` / `Update-ControlColumn` with
the window size): half the room inside a card, between `FieldWidth.ControlMin` (300)
and `ControlMax` (440). The room of the page scrollbar is kept also on pages that do
not scroll, so cards and columns are in the same place on every page. In it:

- text fields, combos, colours, folder lists and sliders **fill** the column (no
  width of their own), so their left and right edges line up;
- switches, chips, sizes, keys and buttons keep their size and **end at the right
  edge** of the column; two combos of one value (the screen's area and monitor) share
  it in equal parts (`NewEqualButtons`).

Widths: number and size boxes `FieldWidth.S` (120), the px / % combo after a size box
`FieldWidth.Unit` (72); panels of chips or switches wrap within `FieldWidth.Wrap` (470); `FieldWidth.M` / `L` only for fields outside rows
(the Import filter and target). No other widths.
- A row of buttons is either all `Auto` and aligned to the start, or all the same
  width filling the row (`UniformGrid`): never mixed.

### Sizes taken from the layout

A size computed from the window's own layout (in `ScrollChanged` or `SizeChanged`,
or a binding to `ActualWidth` / `ActualHeight`) must not change what decides that
layout. Otherwise, at some window sizes, WPF lays the page out again and again and
the window stalls for a second or more. This has happened several times. The category
preview followed its column: the scrollbar showed, the preview shrank, the bar hid,
the preview grew. Every settings page whose height was close to the window's stalled
when its help text wrapped across that point. The Found list filling the page stalled
when a filter row wrapped. Each time, a scrollbar that took width from the content
made it wrap differently, which showed or hid the bar again.

- Scrollers of pages and panes use the `PageScroller` style (`NewPageScroller`,
  `KeepScrollBarRoom`). The bar is drawn over the room kept for it on the right
  (`Gap.ScrollBar`), so the content's width is the same with or without it. A new
  scroller of a page or pane uses it too.
- Take widths from the scroller, never from the content inside it (`UpdateFraming`).
- Check with `tools\options-resize.ps1 -Base origin/nightly -Page <entry>`. It narrows
  and widens the window step by step on the page and fails when a step takes more
  than 200 ms (on nightly, every page stays under about 20 ms).

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
menu's icons (15) and group chevrons (9), the title of the saving overlay (17).

## 6. Spacing (`Gap`)

Every margin and padding of a page is one of these, or 0:

| Constant | px | Where |
|---|---|---|
| `Gap.Help` | 3 | a label to its help below |
| `Gap.Line` | 4 | a hint or status under its control, between the lines of a list |
| `Gap.Icon` | 6 | before an icon button after a field (the button has its own padding); small insets: a thumbnail's frame, the control under its label in a stacked row |
| `Gap.Control` | 8 | between controls and between buttons |
| `Gap.Text` | 10 | a thumbnail or icon to its text; a header or a note to what follows |
| `Gap.Group` | 12 | between groups inside a card (a heading, a block of fields); a status after its buttons; a slider to its number box |
| `Gap.Card` | 16 | between cards |
| `Gap.Indent` | 18 | a switch that belongs to the one above it |
| `Gap.Column` | 24 | the label column to the control column |
| `Gap.DialogBar` | 20 | above the buttons of a dialog |
| `Gap.Row` | 11 | above and below a side-by-side row |
| `Gap.StackedRow` | 8 | above and below a stacked row |
| `Gap.Page` | 36, 4, 36, 24 | around a page; the footer lines up with it |
| `Gap.Dialog` | 24, 20, 24, 18 | inside a dialog (`ShowDialog`, the image picker) |
| `Gap.Chip` | 8, 1, 8, 2 | padding of badges and chips |
| `Gap.ListItem` | 12, 9 | padding of the entries of the menu and of the category list |

Cards use the `Card` style. A spacing that none of these fits is a new constant in
`Ui.cs` and in this table, not a number in the page.

## 7. Buttons and dialogs

- `AccentButton`: the one main action of a section or of a dialog. Not more than one
  per card.
- `DangerButton`: an action that deletes or cannot be undone. It is never the
  default button.
- Order: the main action first, Cancel or Close last; the window's footer too
  ("Save and refresh", "Close"), with "Preview" / "Hide preview" before them, as it
  saves nothing.
- Every button of the footer has a pad button, its glyph before the text
  (`AddPadHint`): Preview `Y`, Save and refresh `Start`, Close `B`. A button whose
  text changes keeps its glyph (`SetPadHintText`).
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
- Delete = an entry goes away (a tile, a category, a widget). Remove = taken out of a
  list, nothing is deleted. Clear = a field is emptied (its file, if any, goes to the
  Recycle Bin).
- "Browse..." picks a file or a folder; a button that opens a dialog ends with "...".
  Always three ASCII dots, in buttons and in statuses ("Checking...").
- "Cancel" in dialogs. "cannot", not "can not".
- Statuses are sentences with a full stop: "Saved.", "Unsaved changes.",
  "Download failed: ...", "The search could not start: ...".

## 9. Lists

- A list with actions has them as icon buttons in its card header (as the tiles
  strip); actions with a long name ("Open") stay text buttons there.
- An empty list says so in its place, in `Fs.Help`, with what to do ("No tiles yet:
  add one with the + button.").
- Long names are cut with `SetTrimmed`.
- A list that is the main content of its page (Import > Found) fills the height left
  on the page (`FillPageHeight`), with a minimum under which the page scrolls.
- A list filtered as you type keeps its entries once built and only shows them again
  (Import > Found: `foundEntries`). Building every entry and reading every image from
  disk at each letter froze the window for half a second.

## 10. When changes are written

- Changes wait for "Save and refresh" (the status says "Unsaved changes."), and
  closing the window asks.
- Operations on files that happen at once (sending an image or a category to the
  Recycle Bin, adding tiles from Import or the widget gallery, saving or deleting a
  profile) say so in their help, and the destructive ones ask first.
- The settings of a widget wait too (`widgetValues`, written by `SaveAll`), and so
  does a profile picked or loaded: it only puts its values in the window, as if they
  had been set by hand.

## 11. Checklist for a change to the window

- [ ] Glyphs, sizes, widths and margins come from `Ui.cs` (`tools/check.py` passes).
- [ ] A new setting is on the page of the part it changes ("Where a setting goes"),
      after the switch it depends on, with its `When` (or in the group of its switch).
- [ ] No title is repeated: page, card and first row do not say the same word.
- [ ] Every field shows its help; tooltips only name icon buttons, show cut text or
      shortcuts.
- [ ] The control matches the kind of value: a single choice is a combo, a unit only
      where the label does not say it already.
- [ ] The control refuses what the value cannot be: letters in a number, a minus sign
      in a size or a count, a second decimal point (`NumericOnly`, with the range of
      the value: can it be negative, can it have decimals?).
- [ ] Every row ends with the action column; fields fill the control column, the
      other controls end at its right edge.
- [ ] Icon buttons that cannot act are hidden; list buttons that cannot act are
      disabled.
- [ ] Deleting asks, with `danger: true`; the button says Delete, Remove or Clear as
      in "Words".
- [ ] Works with the keyboard and the gamepad, without hovering. With the pad, on
      the page changed: right from the menu lands on the first control (top, then
      left); every control can be reached and left in every direction (a slider: `A`
      to change it); `A` acts, `B` goes back or puts the value back; a text or number
      field opens the right keyboard. These were found only by trying with the pad:
      say in the hand-over which of them were not tried.
- [ ] Fits the narrowest window (960 px): nothing cut without its tooltip.
- [ ] A size taken from the layout ("Sizes taken from the layout"):
      `tools\options-resize.ps1 -Base origin/nightly -Page <entry>` passes.
- [ ] `tools\options-shots.ps1 -Base origin/nightly` (with `-Page <entry>` when only
      that page's own code changed): only the pages you meant to change are
      different.
