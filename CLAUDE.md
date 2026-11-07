# Raintile - working rules

Tile launcher skin for Rainmeter 4.5+ (Windows 10/11), full screen, in a window or docked on a side: Lua for the launcher, Windows PowerShell 5.1 for the background jobs, C# (WPF, .NET Framework 4.8) for the Options window.
User-facing docs: `README.md` and `docs/Guide.md`.

This file is shared by everyone who works on Raintile (people and Claude sessions). Personal notes, facts about one machine and dated analyses do not go here: keep them in `CLAUDE.local.md`, in `.claude/` or in `docs/analysis/`, excluded through `.git/info/exclude` (never through `.gitignore`, which is published).

## Git and ownership
- The repository is `Derek3rd/raintile`. `nightly` is the default and working branch; `main` only gets releases, through a PR `nightly` -> `main`.
- One branch per change, cut from an up-to-date `nightly` and named after it: `feature/<name>` or `fix/<name>`, with the author's prefix where useful (e.g. `claude/feature-tile-pin`). Never commit straight to `main` or `nightly`.
- Every change reaches `nightly` as a PR with base `nightly`: every push to `nightly` publishes a nightly build, so only finished, tested work goes there. The `package` check must pass before merging.
- Merged branches are deleted (GitHub does it automatically after the merge); the next change gets a new branch.
- Commits on your own branch are always pushed, unless the user says otherwise (so the branch can be tested from any machine). Open PRs only when asked. Changes the user has not verified live stay on their branch: the user tests the branch, then the PR is merged.
- A tag is also called `nightly` (the pre-release): in git commands that take a revision write the branch as `refs/heads/nightly` or `origin/nightly`.
- No history rewrites of shared branches (force push, rebase, reset of `main` or `nightly`), no deleting releases or other people's branches.
- Keep the author's style: do not restructure or reformat code that is not part of the change.

## Layout
- `Raintile.ini`: main skin. `Hotkey/`, `Navigation/`, `Typing/`, `TileKeys/`: helper skins the launcher loads and unloads itself.
- `@Resources/Scripts/Raintile.lua`: launcher logic.
- `@Resources/Scripts/*.ps1`: background jobs (`Scan`, `Thumbs`, `Update`, `Data`, `Helper`, `Playtime`, `GameUpdates`, `TileAction`).
- `src/Options/`: the Options window (`RaintileOptions.exe`, C# 7.3, WPF), one file per page or feature. The workflows build it into `@Resources/Bin/`. `@Resources/Scripts/Options.ps1` + `Options.xaml` stay as the fallback when the program is missing, as the library of `TileAction.ps1`, and as the source of the settings schema (`$schema`): after changing it run `python tools/gen_options_schema.py` (needs `pwsh`), which writes `src/Options/SchemaData.cs`; the workflows stop if it is out of date.
- `@Resources/Settings.inc`, `State.inc`, `Categories/`, `Images/`: the defaults, copied to the user data folder on first run.
- `@Resources/Generated/`: written by the skin (git-ignored). Never edit or commit it.
- `widgets/`: the widget gallery (`index.json`) and the widgets hosted here (`widgets/<Id>/`). `docs/Widgets.md`: how to write widgets and the widget API.
- `tests/`: `ps/` (PowerShell tests, `run.ps1`) and `lua/` (`Raintile.lua` against a fake Rainmeter, `rainmeter.lua`), run by `tools/check.py`. No `.ini` files there: Rainmeter would list the folder as a skin.
- `tools/build_rmskin.py`: builds the `.rmskin`. `tools/dev-build.ps1`: builds the Options program into the repository's `@Resources\Bin\` (git-ignored), for testing. `.github/workflows/`: `release.yml` (tag `vX.Y.Z`), `nightly.yml` (every push to `nightly`), `sync-nightly.yml` (merges `main` back into `nightly` after a release), `wiki.yml` (writes the GitHub wiki from `docs/` with `tools/build_wiki.py` when the docs reach `main`).

## Conventions
- English for code, comments, docs, commit messages, PRs and release notes.
- Scripts and `.ini`/`.inc` files are ASCII only, without BOM: PowerShell 5.1 and Rainmeter read BOM-less files as ANSI. Use `[char]0x...` for glyphs in PowerShell, `\uXXXX` in C#.
- Text that Lua sends to Rainmeter reaches it as ANSI: write non-ASCII characters as character references `[\xHHHH]` (`D.text()`).
- PowerShell 5.1 syntax only: no `&&`/`||`, `??`, `?.`, ternary or other PowerShell 7 features. C# compiled by `Add-Type` (in `Helper.ps1`) is C# 5; the Options program is C# 7.3.
- Lua 5.1 allows at most 200 locals per function, the main chunk included: put new functions in the existing tables (`D` for the Dashboard, `M` for the rest) instead of new top-level locals.
- No update cycle (`Update=-1`): the skin redraws only on events, and animations run on ActionTimer only while something moves. Never add polling or a timer that runs at rest. Animations are time-based (`M.animScale`), so they last the same at every frame rate.
- The helper (`Helper.ps1`) may push live data to the skin (Dashboard, Steam downloads) only while it is shown, and only when the data changes: the skin asks for it with a flag file in `Generated/` written on show and removed on hide.
- Fixed number of meters: the grid is generated into `Generated/Grid.inc` and tiles are shown or hidden. Never one meter per tile. When the meters written by `writeGrid()` change, bump `GRID_VERSION` in `Raintile.lua`, or skins with the old `Grid.inc` keep it and the new meters do not exist.
- LinearGradient angles in Rainmeter run the other way round (0 = right to left).
- Image names: with or without extension; a dot in a tile name is not an extension (`Battle.net` -> `Battle.net.png`).
- Dependencies: Rainmeter built-in plugins (ActionTimer, InputText, RunCommand) plus HotKey; .NET Framework 4.8 for the Options program. No new plugins, DLLs or PowerShell modules.
- User data lives in `#SETTINGSPATH#Raintile\` (`%APPDATA%\Rainmeter\Raintile`), never in the skin folder, so `.rmskin` updates do not touch it.
- A new setting goes into `@Resources/Settings.inc` with its comment and default, and into the schema of `Options.ps1` (then regenerate `SchemaData.cs`); `Data.ps1` merges it into the user's file. Keep `Data.ps1` idempotent and never let it lose user values.
- Pass the resources path as `"#@#."`: a trailing backslash would escape the closing quote.
- Background scripts run through RunCommand with `-NoProfile -NonInteractive -ExecutionPolicy Bypass`. Their last output line is `RESULT:...`, read by the skin in FinishAction.
- The Options window: `RaintileOptions.exe` when present, otherwise `conhost.exe --headless powershell.exe -STA` with `Options.ps1`, so it has no console window and survives skin refreshes.
- The Options window follows `docs/OptionsUI.md` (one glyph per action, help shown under every field, the same control for the same kind of value, one type scale): build it with the constants and helpers of `src/Options/Ui.cs`, never with glyph codes, font sizes or margins written by hand, and make the same change in `Options.ps1`.
- File writes: UTF-8 without BOM, atomic (write `.tmp`, then `Move-Item`).
- Comments explain why, at the density of the surrounding code.

## Widgets
- Every tile that is not a normal tile or one of the system widgets (cpu, gpu, ram, disk, network, processes, system, temps, fans) is an installable custom widget in `widgets/<Id>/`, listed in `widgets/index.json` with its `category`: no widget-specific logic in `Raintile.lua` or `Helper.ps1`.
- What a widget needs that Rainmeter does not give goes into the generic widget API (the `[Raintile]` section, `#WIDGET:Name#`, `Part=1`, `List=`, `OnShow`/`OnHide`, `WidgetChanged()`), documented in `docs/Widgets.md` in the same PR.
- Widget scripts follow the project's rules: PowerShell 5.1, ASCII, work only from `OnShow` (never at rest), exit early when nothing changed, other programs' data read only (SQLite: `winsqlite3.dll`, `mode=ro`), whole-file writes in the widget's folder.
- A new widget is tried from the gallery of the `nightly` branch first (relative `base` in `index.json`); a widget meant for versions before the API keeps an absolute `base`.

## Security
- Data from outside (GitHub API, SteamGridDB, Steam, Dashboard Icons, store manifests, files in the data folder) is untrusted: `https` only, check hosts before use, never pass it unchecked to `Start-Process`, `Invoke-WebRequest` or a path.
- Tile names become file names: clean them, and keep every destination inside its folder.
- Values written to `.inc`/`.ini` files stay on one line.
- Tile commands run as given (`SKIN:Bang`): that is the feature itself.
- No telemetry. Network calls only for the update check, the widget gallery and the images found online (Steam, SteamGridDB, Dashboard Icons, the website of a link), plus LibreHardwareMonitor's web server on `localhost`.

## Docs stay in sync
- New or changed setting: its comment in `Settings.inc` and the "Settings reference" in `docs/Guide.md`.
- Changed behaviour: the matching section of `docs/Guide.md`, and `README.md` if it is a feature.
- The GitHub wiki is a copy of `docs/`, rewritten at each release: edit `docs/`, never the wiki. A new page of `docs/` goes into `PAGES` of `tools/build_wiki.py`.
- Versions: releases are `X.Y.Z` (`Version=` in `[Metadata]` of `Raintile.ini`); nightly builds are the last release plus the build number (`1.2.2.3`), written by the workflow.
- Release: bump `Version=` on `nightly`, PR `nightly` -> `main`, tag `vX.Y.Z` on `main`; the workflows attach the `.rmskin` and merge `main` back into `nightly` (see "Publishing a release" in the Guide). Release notes in English.

## Verifying changes
- `python tools/check.py` passes before every commit (needs `pip install lupa`): it runs the checks below that can be automated and the tests in `tests/`; the `checks` job runs it on every PR, and `python tools/check.py --install-hook` makes it run before every push (a failure stops the push: fix, commit, push again; never `--no-verify`). A fixed bug gets a test that fails without the fix, where the fake Rainmeter or a PowerShell test can show it; when the fake lacks a Rainmeter behaviour the change relies on, add it to `tests/lua/rainmeter.lua`.
- Every changed `.ps1` parses without errors (`[System.Management.Automation.Language.Parser]::ParseFile`), and `Options.xaml` loads as `[xml]`.
- Changed scripts are still ASCII only and without BOM.
- Lua: `tools/check.py` compiles it with Lua 5.1 and runs it in the fake Rainmeter; that does not replace a live test.
- Options program: it builds (`dotnet build src/Options/RaintileOptions.csproj -c Release`, also on Linux; the `package` check does it on every PR), and `python tools/gen_options_schema.py --check` passes after schema changes.
- Suggested local setup: make the repository the skin itself, linking it into Rainmeter's skins folder (`mklink /J "%USERPROFILE%\Documents\Rainmeter\Skins\Raintile" <repo>`): the branch checked out is then what Rainmeter runs, with nothing to copy.
- `RaintileOptions.exe` is not in the repository (the workflows build it): without it the skin opens the older `Options.ps1` window. Before every live test of a branch, after changing anything under `src/Options` and after pulling or switching branch, run `powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev-build.ps1` (needs the .NET SDK, `dotnet`): it rebuilds only when a source is newer than the program, into `@Resources\Bin\` of the repository (git-ignored; close the Options window first), or of another skin folder with `-Target <folder>`. Without the SDK, take `RaintileOptions.exe` from the `rmskin` artifact of the PR's `package` check.
- Live test: refresh the skin in Rainmeter and use the changed feature; for Options, open it from the gear.
- Anything touching `Data.ps1`, `Update.ps1` or the install path: back up the user data folder first.
- Say what was not verified.

## Notes and analyses
- Dated analyses and decision records go in `docs/analysis/` (local, never pushed). A decision that becomes a rule gets one line here; the reasoning stays there.
- Facts about one machine or one person live in Claude's memory or in `CLAUDE.local.md`, not here.
