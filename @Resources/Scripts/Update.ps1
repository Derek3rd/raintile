# Raintile: checks GitHub for a newer release (started by the skin, at most
# once a day, and by "Check now" in the Options window).
#
# UpdateChannel=Nightly (Settings.inc) also looks at the pre-release
# "nightly", built on every change (1.2.2.5: the release after 1.2.1, 5th
# build): the newer of the two is offered. A release counts as newer than the
# nightly builds of the same number (1.2.2 > 1.2.2.5).
#
# The latest release of the repository (api.github.com, no account needed):
# its version is read from the tag (v1.0.2) or, failing that, from the title
# ("1.0.1 - ..."), and compared with Version= in Raintile.ini. The result is
# kept in Update.json in the data folder: Checked, Current, Latest, Newer,
# Title, Notes, Page (release page), Asset (.rmskin download), Error.
#
# Last output line, read by the skin: RESULT:UPDATE=<version>, RESULT:NONE or
# RESULT:ERROR.
#
# With -NoRun only the functions are loaded (Options window, tests).

param(
    [Parameter(Mandatory = $true)][string]$Resources,
    [Parameter(Mandatory = $true)][string]$Data,
    [string]$Repository = 'Derek3rd/raintile',
    # Release or Nightly; if empty, UpdateChannel of Settings.inc
    [string]$Channel = '',
    # check even if the last check is less than a day old
    [switch]$Force,
    [switch]$NoRun,
    # tests only: a saved API response instead of GitHub
    [string]$ResponseFile = ''
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$Resources = [IO.Path]::GetFullPath($Resources).TrimEnd('\', '/')
$Data = [IO.Path]::GetFullPath($Data).TrimEnd('\', '/')
$updateFile = Join-Path $Data 'Update.json'

# Version= in the [Metadata] of Raintile.ini
function Get-InstalledVersion {
    $ini = Join-Path (Split-Path -Parent $Resources) 'Raintile.ini'
    $m = [regex]::Match([IO.File]::ReadAllText($ini), '(?m)^\s*Version\s*=\s*(.+?)\s*$')
    if ($m.Success) { return $m.Groups[1].Value }
    return '0'
}

# "v1.0.2" / "1.0.1 - WPF Options Window" -> [version] 1.0.2 / 1.0.1 ($null
# if there is no number)
function ConvertTo-Version([string]$text) {
    $m = [regex]::Match("$text", '(\d+)\.(\d+)(?:\.(\d+))?(?:\.(\d+))?')
    if (-not $m.Success) { return $null }
    $parts = @(1..4 | ForEach-Object { if ($m.Groups[$_].Success) { [int]$m.Groups[$_].Value } else { 0 } })
    return New-Object Version($parts[0], $parts[1], $parts[2], $parts[3])
}

# For comparing: a release (three numbers) is newer than the nightly builds
# of its number (four numbers: 1.2.2.5 < 1.2.2)
function Get-VersionKey([version]$v) {
    if (-not $v) { return [int64]-1 }
    $rev = if ($v.Revision -gt 0) { $v.Revision } else { 999999 }
    return ([int64]$v.Major * 1000 + $v.Minor) * 1000000000000 + [int64]$v.Build * 1000000 + $rev
}

function Get-Channel {
    if ($Channel) { return $Channel }
    foreach ($file in (Join-Path $Data 'Settings.inc'), (Join-Path $Resources 'Settings.inc')) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $m = [regex]::Match([IO.File]::ReadAllText($file), '(?m)^\s*UpdateChannel\s*=\s*(\S+)')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return 'Release'
}

function Format-Version([version]$v) {
    $s = "$($v.Major).$($v.Minor).$($v.Build)"
    if ($v.Revision -gt 0) { $s += ".$($v.Revision)" }
    return $s
}

# Only addresses of this repository on GitHub, over https, are opened or
# downloaded: Update.json is a plain file and could have been changed.
function Test-ReleaseUrl([string]$url) {
    $u = $null
    if (-not [Uri]::TryCreate("$url", [UriKind]::Absolute, [ref]$u)) { return $false }
    return $u.Scheme -eq 'https' -and $u.Host -eq 'github.com' -and
        $u.AbsolutePath.StartsWith("/$Repository/", [StringComparison]::OrdinalIgnoreCase)
}

# A version made of numbers only (to use in a file name), or ''
function Get-SafeVersion([string]$text) {
    if ("$text" -match '^\d+(\.\d+){1,3}$') { return $text }
    return ''
}

# True if the file is a Rainmeter package: its last 16 bytes are the size of
# the zip before them, a flags byte and "RMSKIN" (the installer checks the same)
function Test-RmskinPackage([string]$path) {
    try {
        $bytes = [IO.File]::ReadAllBytes($path)
        if ($bytes.Length -lt 32) { return $false }
        $size = [BitConverter]::ToInt64($bytes, $bytes.Length - 16)
        $key = [Text.Encoding]::ASCII.GetString($bytes, $bytes.Length - 7, 7)
        # the zip itself starts with "PK"
        return $key -eq "RMSKIN`0" -and $size -eq ($bytes.Length - 16) -and $bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B
    } catch { return $false }
}

function Read-UpdateInfo {
    if (-not (Test-Path -LiteralPath $updateFile)) { return $null }
    try { return ([IO.File]::ReadAllText($updateFile) | ConvertFrom-Json) } catch { return $null }
}

# Asks GitHub and writes Update.json; returns the result
function Invoke-UpdateCheck {
    $current = Get-InstalledVersion
    $info = [ordered]@{
        Checked = (Get-Date).ToString('s'); Current = $current; Channel = (Get-Channel); Latest = ''; Newer = $false
        Title = ''; Notes = ''; Page = "https://github.com/$Repository/releases"; Asset = ''; Error = ''
    }
    try {
        $releases = @()
        if ($ResponseFile) {
            $releases += [IO.File]::ReadAllText($ResponseFile) | ConvertFrom-Json
        } else {
            # GitHub wants TLS 1.2 and a User-Agent
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $headers = @{ 'User-Agent' = 'Raintile'; Accept = 'application/vnd.github+json' }
            try { $releases += Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -TimeoutSec 20 -Headers $headers }
            catch { if ((Get-Channel) -notmatch '(?i)^nightly') { throw } }
            if ((Get-Channel) -match '(?i)^nightly') {
                try { $releases += Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/tags/nightly" -TimeoutSec 20 -Headers $headers }
                catch { if (-not $releases.Count) { throw } }
            }
        }
        # the newest of them (a release beats the nightly builds of its number)
        $release = $null; $latest = $null
        foreach ($r in $releases) {
            $v = ConvertTo-Version $r.tag_name
            if (-not $v) { $v = ConvertTo-Version $r.name }
            if (-not $release -or (Get-VersionKey $v) -gt (Get-VersionKey $latest)) { $release = $r; $latest = $v }
        }
        if (-not $release) { throw 'no release found' }
        $installed = ConvertTo-Version $current
        if ($latest) {
            $info.Latest = Format-Version $latest
            $info.Newer = [bool]($installed -and (Get-VersionKey $latest) -gt (Get-VersionKey $installed))
        }
        $info.Title = "$($release.name)"
        $info.Notes = "$($release.body)"
        if (Test-ReleaseUrl $release.html_url) { $info.Page = "$($release.html_url)" }
        $asset = @($release.assets | Where-Object { $_.name -like '*.rmskin' -and (Test-ReleaseUrl $_.browser_download_url) }) | Select-Object -First 1
        if ($asset) { $info.Asset = "$($asset.browser_download_url)" }
    } catch {
        $info.Error = $_.Exception.Message
    }
    New-Item -ItemType Directory -Force -Path $Data | Out-Null
    [IO.File]::WriteAllText($updateFile, (ConvertTo-Json -InputObject $info), $utf8)
    return [pscustomobject]$info
}

if ($NoRun) { return }

$info = Read-UpdateInfo
$fresh = $false
if ($info -and -not $Force) {
    try { $fresh = ((Get-Date) - [DateTime]::Parse($info.Checked)).TotalHours -lt 24 } catch { }
    # an update installed since the last check: check again
    if ($info.Current -ne (Get-InstalledVersion)) { $fresh = $false }
    # another channel chosen since
    if ("$($info.Channel)" -ne (Get-Channel)) { $fresh = $false }
}
if (-not $fresh) { $info = Invoke-UpdateCheck }

if ($info.Error) {
    Write-Output "Update check failed: $($info.Error)"
    Write-Output 'RESULT:ERROR'
} elseif ($info.Newer) {
    Write-Output "Raintile $($info.Latest) is available (installed: $($info.Current))"
    Write-Output "RESULT:UPDATE=$($info.Latest)"
} else {
    Write-Output "Raintile $($info.Current) is up to date"
    Write-Output 'RESULT:NONE'
}
