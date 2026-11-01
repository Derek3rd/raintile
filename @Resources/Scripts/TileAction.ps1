# Raintile: actions of the tile context menu that the skin cannot do itself.
#
#  -Action runas   starts the tile's program as administrator (Windows asks
#                  for confirmation, UAC)
#  -Action remove  removes the tile from its category file, after asking, and
#                  refreshes the skin (its images stay in Images\)
#
# The tile is read from Generated\TileAction.txt ("<file>|<tile name>"),
# written by the skin: the file must be one of the category files, and the
# command is read from that file, not taken from the command line.

param(
    [Parameter(Mandatory = $true)][string]$Resources,
    [string]$Data = '',
    [string]$Config = 'Raintile',
    [Parameter(Mandatory = $true)][ValidateSet('runas', 'remove')][string]$Action
)

$ErrorActionPreference = 'Stop'
# Category files, tiles and their keys (Read-Category, Write-Category, ...)
. (Join-Path $PSScriptRoot 'Options.ps1') -Resources $Resources -Data $Data -Config $Config -NoGui
Add-Type -AssemblyName System.Windows.Forms

# Message box on top of the launcher (which covers the screen)
function Show-Message([string]$text, [string]$buttons = 'OK', [string]$icon = 'Information') {
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $owner.ShowInTaskbar = $false
    $owner.StartPosition = 'CenterScreen'
    $owner.Size = New-Object System.Drawing.Size(1, 1)
    $owner.Opacity = 0
    $owner.Show()
    try { return [System.Windows.Forms.MessageBox]::Show($owner, $text, 'Raintile', $buttons, $icon) }
    finally { $owner.Close() }
}

function Invoke-Rainmeter([string]$bang) {
    $exe = (Get-Process Rainmeter -ErrorAction SilentlyContinue | Select-Object -First 1).Path
    if (-not $exe) { $exe = Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe' }
    if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe -ArgumentList $bang }
}

# Program and arguments of a command, as the skin reads it: "C:\x\a.exe" -b,
# a.exe -b. $null for URLs and bangs.
function Split-Command([string]$command) {
    $c = $command.Trim()
    if (-not $c -or $c.StartsWith('[') -or $c.Contains('://')) { return $null }
    if ($c -match '^"([^"]+)"\s*(.*)$') { return @($Matches[1], $Matches[2]) }
    if ($c -match '^(\S+)\s*(.*)$') { return @($Matches[1], $Matches[2]) }
    return $null
}

# --- The tile -----------------------------------------------------------------------

$tileFile = Join-Path $Resources 'Generated\TileAction.txt'
if (-not (Test-Path -LiteralPath $tileFile)) { exit 0 }
$parts = [IO.File]::ReadAllText($tileFile).Split('|', 2)
Remove-Item -LiteralPath $tileFile -Force -ErrorAction SilentlyContinue
if ($parts.Count -ne 2) { exit 0 }
$file = Get-CategoryFiles | Where-Object { $_.Name -ieq $parts[0].Trim() } | Select-Object -First 1
$name = $parts[1].Trim()
if (-not $file) { exit 0 }
$model = Read-Category $file.FullName
$section = @(Get-Tiles $model | Where-Object { $_.Name -eq $name }) | Select-Object -First 1

if (-not $section) {
    if ((Get-ImportedNames $model) -contains $name) {
        [void](Show-Message "'$name' comes from the old automatic import. Open Options > Import once: it becomes a normal tile, which can then be removed.")
    }
    exit 0
}

if ($Action -eq 'runas') {
    $target = Split-Command (Get-Key $section 'Command')
    if (-not $target) { exit 0 }
    try {
        if ($target[1]) { Start-Process -FilePath $target[0] -ArgumentList $target[1] -Verb RunAs }
        else { Start-Process -FilePath $target[0] -Verb RunAs }
    } catch {
        # cancelled in the Windows prompt, or the program could not start
        if ($_.Exception.Message -notmatch 'cancel') { [void](Show-Message "Could not start '$name' as administrator: $($_.Exception.Message)" 'OK' 'Warning') }
    }
    exit 0
}

# remove
$label = Get-Key (Get-CategorySection $model) 'Name'
if (-not $label) { $label = $file.BaseName }
$answer = Show-Message "Remove '$name' from $label?`r`n`r`nIts images stay in the Images folder." 'YesNo' 'Question'
if ("$answer" -ne 'Yes') { exit 0 }
[void]$model.Sections.Remove($section)
Write-Category $file.FullName $model
Invoke-Rainmeter "!Refresh `"$Config`""
