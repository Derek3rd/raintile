---
paths:
  - "src/Options/**"
  - "@Resources/Scripts/Options.xaml"
---

# Changing the Options window

- Read `docs/OptionsUI.md` before changing a page: it says which glyph, control, size,
  spacing, button and word to use. Build with the helpers of `src/Options/Ui.cs`; what
  they lack goes into `Ui.cs` and into `docs/OptionsUI.md`, not into the page.
- Layout changes: compare the page you changed with one you did not (General against
  Layout, Keyboard, Categories). The control column has the same edges on every page,
  every row ends with the action column, icon buttons that cannot act are hidden.
  The user found these by screenshot more than once: check them before handing over.
- Before handing over, go through the checklist at the end of `docs/OptionsUI.md`,
  run `python tools/check.py` (it rejects glyph codes, font sizes, margins and
  paddings written by hand) and `powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev-build.ps1`, then
  ask the user to test the program, saying which pages changed.
- A layout change: run `tools\options-shots.ps1 -Base origin/nightly` and look at
  `build\options-shots\report.txt` and the pictures in `diff\` (CLAUDE.md,
  "Verifying changes"); say in the hand-over which pages changed and how. While
  iterating, commit each step you are happy with and compare the next one with
  `-Base HEAD`: that step is already in the cache, only the new state is shot.
- Shoot what the change can reach. Shared code (`Ui.cs`, `Settings.cs`, `Nav.cs`,
  `Schema*.cs`, `Options.xaml`): every page. Code of one page only (`Profiles.cs` on
  General, `Dashboard.cs` and `Market.cs` on Widgets): `-Page <that entry>`, as the
  report names it (several: `-Page General,Tiles`). A step that cannot show in the
  shots (a control hidden with the frozen data): no shots, and say so in the
  hand-over.
