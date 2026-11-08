# Raintile Options

The Options window of Raintile as a Windows program: C#, WPF, .NET Framework 4.8
(included in Windows 10/11). The packages of the releases have it in
`@Resources/Bin/`; a copy of the repository builds it with `tools/dev-build.ps1`.

- **Look**: the styles are read at run time from `@Resources/Scripts/Options.xaml`;
  the window layout is in `WindowXaml.cs`. The rules of the pages are in
  `docs/OptionsUI.md`, their constants and helpers in `Ui.cs`.
- **Pages, menu, defaults**: `SchemaData.cs`. A new setting goes there and into
  `@Resources/Settings.inc`: `tools/check.py` checks that the two have the same keys.
- **Build**: `dotnet build src/Options -c Release -o build/options` (works on Linux
  too: no compiled XAML). The workflows copy `RaintileOptions.exe` to
  `@Resources/Bin/`, where the skin looks for it (`OpenOptions` in `Raintile.lua`).
- **Arguments**: `-Resources <@Resources> -Data <data folder> -Config <skin>
  [-Page import|tile|info]`, or `-Action runas|remove` for the tile menu (no window).

| File | What it holds |
| --- | --- |
| `Core.cs` | files and data: Settings.inc, category files, images, secret, backup, scan and update helpers |
| `Schema.cs`, `SchemaData.cs` | the settings schema: pages, menu, defaults, key names |
| `Ui.cs` | start, element helpers, dialogs |
| `Settings.cs` | a control for each kind of setting, rows, settings pages |
| `Nav.cs` | menu, pages, Info and updates, start of the window |
| `Categories.cs` | Categories page, tiles of a category, framing and logo editor |
| `Import.cs` | games and apps found, tiles of games no longer installed |
| `Save.cs` | saving, Save and refresh, backup and restore |
| `Gamepad.cs` | the window with a controller (XInput): moving between controls, pressing, pages |
| `Osk.cs` | on-screen keyboard for text fields, for the controller |
| `PadPlace.cs` | framing, logo and play time line of the tile preview with the controller |
| `TileAction.cs` | the tile menu's Run as administrator and Remove (`-Action`) |
| `WidgetOptions.cs` | the settings of each installed widget (Widgets > the widget) |
| `PreviewWindow.cs` | the preview window beside the Options window (Preview button): the launcher with the settings and tiles not saved yet, the grid |
| `WheelPreview.cs` | the preview's drawing: the screen, the launcher, the wheel and the inner ring with the launcher's formulas |
