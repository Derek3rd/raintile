# Raintile: checks GitHub for a newer release (started by the skin, at most
# once a day, and by "Check now" in the Options window).
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

function Format-Version([version]$v) {
    $s = "$($v.Major).$($v.Minor).$($v.Build)"
    if ($v.Revision -gt 0) { $s += ".$($v.Revision)" }
    return $s
}

function Read-UpdateInfo {
    if (-not (Test-Path -LiteralPath $updateFile)) { return $null }
    try { return ([IO.File]::ReadAllText($updateFile) | ConvertFrom-Json) } catch { return $null }
}

# Asks GitHub and writes Update.json; returns the result
function Invoke-UpdateCheck {
    $current = Get-InstalledVersion
    $info = [ordered]@{
        Checked = (Get-Date).ToString('s'); Current = $current; Latest = ''; Newer = $false
        Title = ''; Notes = ''; Page = "https://github.com/$Repository/releases"; Asset = ''; Error = ''
    }
    try {
        if ($ResponseFile) {
            $release = [IO.File]::ReadAllText($ResponseFile) | ConvertFrom-Json
        } else {
            # GitHub wants TLS 1.2 and a User-Agent
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -TimeoutSec 20 `
                -Headers @{ 'User-Agent' = 'Raintile'; Accept = 'application/vnd.github+json' }
        }
        $latest = ConvertTo-Version $release.tag_name
        if (-not $latest) { $latest = ConvertTo-Version $release.name }
        $installed = ConvertTo-Version $current
        if ($latest) {
            $info.Latest = Format-Version $latest
            $info.Newer = [bool]($installed -and $latest -gt $installed)
        }
        $info.Title = "$($release.name)"
        $info.Notes = "$($release.body)"
        if ($release.html_url) { $info.Page = "$($release.html_url)" }
        $asset = @($release.assets | Where-Object { $_.name -like '*.rmskin' }) | Select-Object -First 1
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
