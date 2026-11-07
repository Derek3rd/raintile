---
paths:
  - "src/Options/**"
  - "@Resources/Scripts/Options.ps1"
  - "@Resources/Scripts/Options.xaml"
---

# Changing the Options window

- Read `docs/OptionsUI.md` before changing a page: it says which glyph, control, size,
  spacing, button and word to use. Build with the helpers of `src/Options/Ui.cs`
  (`$GLYPH`, `$FS`, `$GAP`, `$FIELD` and the `New-...` helpers in `Options.ps1`); what
  they lack goes into `Ui.cs` and into `docs/OptionsUI.md`, not into the page.
- Make the same change in `Options.ps1` when the page exists there too: the fallback
  window must look and behave like the program.
- Layout changes: compare the page you changed with one you did not (General against
  Layout, Keyboard, Categories). The control column has the same edges on every page,
  every row ends with the action column, icon buttons that cannot act are hidden.
  The user found these by screenshot more than once: check them before handing over.
- Before handing over, go through the checklist at the end of `docs/OptionsUI.md`,
  run `python tools/check.py` (it rejects glyph codes, font sizes, margins and
  paddings written by hand) and `powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev-build.ps1`, then
  ask the user to test both the program and the `Options.ps1` fallback, saying which
  pages changed.
