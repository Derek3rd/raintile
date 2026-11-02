# Raintile Options (native)

The Options window of Raintile as a Windows program: C#, WPF, .NET Framework 4.8
(included in Windows 10/11). It is a port of `@Resources/Scripts/Options.ps1`,
which stays as the fallback when the program is missing (a copy of the
repository) and as the library of `TileAction.ps1`.

- **Look**: the styles are read at run time from `@Resources/Scripts/Options.xaml`,
  the same file the PowerShell window uses; the window layout is in `WindowXaml.cs`.
- **Pages, menu, defaults**: written once, in the `$schema` of `Options.ps1`.
  `SchemaData.cs` is generated from it: after changing the schema run

  ```
  python tools/gen_options_schema.py
  ```

  (needs PowerShell, `pwsh`). The release workflow stops if it is out of date.
- **Build**: `dotnet build src/Options -c Release -o build/options` (works on Linux
  too: no compiled XAML). The release workflow copies `RaintileOptions.exe` to
  `@Resources/Bin/`, where the skin looks for it (`OpenOptions` in `Raintile.lua`).
- **Arguments**: as `Options.ps1`: `-Resources <@Resources> -Data <data folder>
  -Config <skin> [-Page import|tile|info]`.

| File | What it holds |
| --- | --- |
| `Core.cs` | files and data: Settings.inc, category files, images, secret, backup, scan and update helpers |
| `Schema.cs`, `SchemaData.cs` | pages and key names |
| `Ui.cs` | start, element helpers, dialogs |
| `Settings.cs` | a control for each kind of setting, rows, settings pages |
| `Nav.cs` | menu, pages, Info and updates, start of the window |
| `Categories.cs` | Categories page, tiles of a category, framing and logo editor |
| `Import.cs` | games and apps found, tiles of games no longer installed |
| `Save.cs` | saving, Save and refresh, backup and restore |
