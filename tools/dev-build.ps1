<#
  Raintile: builds the Options program (src/Options) into the repository,
  @Resources\Bin\RaintileOptions.exe (git-ignored), for testing a branch.

  The release and nightly workflows build it for the packages; the repository
  has none, so the skin would open the older Options.ps1 window instead.
  Suggested: make the repository the skin itself, linked into Rainmeter's
  skins folder (mklink /J "%USERPROFILE%\Documents\Rainmeter\Skins\Raintile" <repo>);
  otherwise pass the skin folder with -Target.
  Run this after every change under src/Options (and after pulling or
  switching branch):

    powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev-build.ps1

  It builds only when a source is newer than the installed program (-Force
  builds anyway). Needs the .NET SDK (dotnet, 8 or later); no Visual Studio.

  -Target  another skin folder to put it in (default: the repository)
#>
param(
    [string]$Target = '',
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo 'src\Options'
$project = Join-Path $src 'RaintileOptions.csproj'
if (-not (Test-Path $project)) { Write-Host "Not found: $project"; exit 1 }

if ($Target -eq '') { $Target = $repo }
if (-not (Test-Path (Join-Path $Target 'Raintile.ini'))) {
    Write-Host "No Raintile skin in $Target (use -Target <skin folder>)."
    exit 1
}
$bin = Join-Path $Target '@Resources\Bin'
$exe = Join-Path $bin 'RaintileOptions.exe'

# The settings schema is written in Options.ps1; SchemaData.cs is generated from it
$schemaSource = Join-Path $repo '@Resources\Scripts\Options.ps1'
$schemaData = Join-Path $src 'SchemaData.cs'
if ((Test-Path $schemaSource) -and (Test-Path $schemaData) -and
    (Get-Item $schemaSource).LastWriteTime -gt (Get-Item $schemaData).LastWriteTime) {
    Write-Host 'Options.ps1 is newer than SchemaData.cs: if the schema changed, run python tools\gen_options_schema.py first.'
}

# Up to date: no source newer than the installed program
$sources = Get-ChildItem $src -Recurse -File -Include '*.cs', '*.csproj', '*.manifest' |
    Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' }
# (sorted: Measure-Object -Maximum takes only numbers in PowerShell 5.1)
$newest = $sources | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $Force -and $newest -and (Test-Path $exe) -and (Get-Item $exe).LastWriteTime -ge $newest.LastWriteTime) {
    Write-Host "Up to date: $exe"
    exit 0
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host 'dotnet not found: install the .NET SDK (https://dotnet.microsoft.com/download).'
    exit 1
}
$out = Join-Path $repo 'build\options'
& dotnet build $project -c Release -o $out -nologo -v quiet
if ($LASTEXITCODE -ne 0) { Write-Host 'Build failed.'; exit $LASTEXITCODE }

# The program in use cannot be replaced
if (Get-Process RaintileOptions -ErrorAction SilentlyContinue) {
    Write-Host 'The Options window is open: close it, then run this again.'
    exit 1
}
New-Item -ItemType Directory -Force -Path $bin | Out-Null
$tmp = $exe + '.tmp'
Copy-Item (Join-Path $out 'RaintileOptions.exe') $tmp -Force
Move-Item $tmp $exe -Force
Write-Host "Installed: $exe"
