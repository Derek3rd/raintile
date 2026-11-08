# Raintile: prepares the folder with your data (started by the skin when
# needed).
#
# Your settings, categories, images and positions live in
# #SETTINGSPATH#Raintile\ (usually %APPDATA%\Rainmeter\Raintile\), not in the
# skin folder: installing an update (.rmskin) replaces the skin folder, moving
# the old one to Skins\@Backup\, and never touches this one.
#
#  - First time: the folder is filled from the previous version, i.e. the
#    backup the installer has just made (Skins\@Backup\<skin>\@Resources), or
#    the skin folder itself (new install, or a copy updated by hand).
#  - Settings.inc: rebuilt from the skin's Settings.inc (the defaults: every
#    key, with its comments, in its order) with your values. New settings of
#    an update appear with their default, settings removed by an update go.
#
# Last output line, read by the skin: RESULT:OK or RESULT:ERROR.

param(
    [Parameter(Mandatory = $true)][string]$Resources,
    [Parameter(Mandatory = $true)][string]$Data,
    [string]$Skins = '',
    [string]$Config = 'Raintile'
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$Resources = [IO.Path]::GetFullPath($Resources).TrimEnd('\', '/')
$Data = [IO.Path]::GetFullPath($Data).TrimEnd('\', '/')

# Key -> value of the [Variables] of a settings file (comments left out)
function Read-Values([string]$path) {
    $values = @{}
    if (-not (Test-Path -LiteralPath $path)) { return $values }
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $t = $line.Trim()
        if ($t -match '^([^;=\[][^=]*?)\s*=(.*)$') { $values[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    return $values
}

# Settings of older versions that became part of another one, before they go:
# ImportFoldersKind (one kind for all your folders) is now the kind of each
# folder in ImportFolders ("Folder>App"), given to the folders without one;
# GameUpdates is now UpdateInfo.
# Idempotent: once moved the old key is gone, and a folder with a kind keeps it.
function Convert-OldSettings([hashtable]$values) {
    if ($values.ContainsKey('ImportFoldersKind')) {
        $kind = $values['ImportFoldersKind']
        if ($kind -match '(?i)^app' -and $values.ContainsKey('ImportFolders')) {
            $entries = @()
            foreach ($e in $values['ImportFolders'].Split('|')) {
                $e = $e.Trim()
                if (-not $e) { continue }
                if ($e.Contains('>')) { $entries += $e } else { $entries += "$e>App" }
            }
            $values['ImportFolders'] = $entries -join '|'
        }
        $values.Remove('ImportFoldersKind')
    }
    # GameUpdates=0/1 (the Steam updates on or off) is now UpdateInfo=Never or
    # Hover, its default (the line only on the highlighted tile; also Always)
    if ($values.ContainsKey('GameUpdates')) {
        if (-not $values.ContainsKey('UpdateInfo')) {
            $values['UpdateInfo'] = if ($values['GameUpdates'] -eq '0') { 'Never' } else { 'Hover' }
        }
        $values.Remove('GameUpdates')
    }
}

# The defaults file with the given values in place of the default ones
function Merge-Settings([string]$defaults, [hashtable]$values) {
    $lines = [IO.File]::ReadAllLines($defaults)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(\s*)([^;=\[][^=]*?)(\s*=)(.*)$') {
            $key = $Matches[2].Trim()
            if ($values.ContainsKey($key)) { $lines[$i] = $Matches[1] + $Matches[2] + $Matches[3] + $values[$key] }
        }
    }
    return (($lines -join "`r`n") + "`r`n")
}

try {
    New-Item -ItemType Directory -Force -Path $Data | Out-Null

    # Where the previous data is: the installer's backup if there is one
    $source = $Resources
    if ($Skins) {
        $backup = Join-Path ([IO.Path]::GetFullPath($Skins)) "@Backup\$Config\@Resources"
        if (Test-Path -LiteralPath (Join-Path $backup 'Categories')) { $source = $backup }
    }

    # Categories, images, positions, list of what was already seen: only if
    # the folder does not have them yet
    $firstTime = -not (Test-Path -LiteralPath (Join-Path $Data 'Categories'))
    if ($firstTime) {
        foreach ($dir in 'Categories', 'Images') {
            $from = Join-Path $source $dir
            if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination $Data -Recurse -Force }
            else { New-Item -ItemType Directory -Force -Path (Join-Path $Data $dir) | Out-Null }
        }
        foreach ($file in 'State.inc', 'Generated\Seen.txt') {
            $from = Join-Path $source $file
            if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination (Join-Path $Data (Split-Path -Leaf $file)) -Force }
        }
        Write-Output "Your data was copied from $source to $Data"
    }
    # The Dashboard (1.0.6): added once to an existing folder; deleted, it does
    # not come back (Dashboard.added)
    $marker = Join-Path $Data 'Dashboard.added'
    if (-not (Test-Path -LiteralPath $marker)) {
        $hasDashboard = @(Get-ChildItem -LiteralPath (Join-Path $Data 'Categories') -Filter '*.ini' -File -ErrorAction SilentlyContinue |
            Where-Object { [IO.File]::ReadAllText($_.FullName) -match '(?im)^\s*Type\s*=\s*Dashboard\s*$' }).Count -gt 0
        $file = Join-Path $Data 'Categories\Dashboard.ini'
        if (-not $hasDashboard -and -not (Test-Path -LiteralPath $file) -and (Test-Path -LiteralPath (Join-Path $Resources 'Categories\Dashboard.ini'))) {
            Copy-Item -LiteralPath (Join-Path $Resources 'Categories\Dashboard.ini') -Destination $file
            $icon = Join-Path $Resources 'Images\Dashboard'
            if (Test-Path -LiteralPath $icon) { Copy-Item -LiteralPath $icon -Destination (Join-Path $Data 'Images') -Recurse -Force }
            Write-Output "Dashboard added: $file"
        }
        [IO.File]::WriteAllText($marker, '', $utf8)
    }

    # Settings: defaults of this version + your values
    $defaults = Join-Path $Resources 'Settings.inc'
    $user = Join-Path $Data 'Settings.inc'
    $values = if (Test-Path -LiteralPath $user) { Read-Values $user } else { Read-Values (Join-Path $source 'Settings.inc') }
    Convert-OldSettings $values
    $text = Merge-Settings $defaults $values
    $old = if (Test-Path -LiteralPath $user) { [IO.File]::ReadAllText($user) } else { '' }
    if ($text -ne $old) {
        $tmp = "$user.tmp"
        [IO.File]::WriteAllText($tmp, $text, $utf8)
        Move-Item -LiteralPath $tmp -Destination $user -Force
        Write-Output "Settings updated: $user"
    }
    Write-Output 'RESULT:OK'
} catch {
    Write-Output "Error preparing $Data`: $($_.Exception.Message)"
    Write-Output 'RESULT:ERROR'
}
