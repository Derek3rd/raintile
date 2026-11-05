# Raintile: Steam games with an update waiting, for the line shown on the
# tiles (GameUpdates). Started by the skin in the background, together with
# Playtime.ps1.
#
# Steam writes the state of every installed game in
#   <library>\steamapps\appmanifest_<appid>.acf
# An update is waiting when "StateFlags" has the UpdateRequired bit (2) or
# "TargetBuildID" differs from "buildid"; "BytesToDownload" and
# "BytesDownloaded" give its size and progress, "ScheduledAutoUpdate" (unix
# time, 0 = none) when Steam will download it. Steam fills them in only
# while it runs: what is read is what Steam knew last.
#
# Output: Generated\GameUpdates.txt, one game per line:
#   <appid>|<bytes to download>|<bytes downloaded>|<scheduled, unix time>
# rewritten only when it changes. Last output line, read by the skin:
# RESULT:UPDATES=<number of games>.

param(
    [Parameter(Mandatory = $true)][string]$Resources,
    # tests only: Steam folder instead of the one in the registry
    [string]$SteamPath = ''
)

$ErrorActionPreference = 'Stop'
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { }
$utf8 = New-Object System.Text.UTF8Encoding $false
$Resources = [IO.Path]::GetFullPath($Resources).TrimEnd('\', '/')
$outFile = Join-Path $Resources 'Generated\GameUpdates.txt'

$root = $SteamPath
if (-not $root) {
    try { $root = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name 'SteamPath' -ErrorAction Stop).SteamPath } catch { $root = '' }
}
if (-not $root -or -not (Test-Path -LiteralPath $root)) {
    Write-Output 'Steam not installed'
    Write-Output 'RESULT:UPDATES=0'
    exit 0
}
$root = $root -replace '/', '\'

# The libraries: Steam's own folder and the ones in libraryfolders.vdf, each
# once (the registry and the file may write the same folder differently)
$libraries = @{}
$candidates = @($root)
$vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
if (Test-Path -LiteralPath $vdf) {
    try {
        $vdfText = [IO.File]::ReadAllText($vdf, $utf8)
        foreach ($m in [regex]::Matches($vdfText, '"path"\s+"([^"]+)"')) { $candidates += $m.Groups[1].Value -replace '\\\\', '\' }
    } catch { }
}
foreach ($lib in $candidates) {
    try { $full = [IO.Path]::GetFullPath($lib).TrimEnd('\') } catch { continue }
    if (-not $libraries.ContainsKey($full.ToLowerInvariant())) { $libraries[$full.ToLowerInvariant()] = $full }
}

function Get-Field([string]$text, [string]$name) {
    $m = [regex]::Match($text, '"' + $name + '"\s+"(\d+)"', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return '0'
}

$games = @{}   # appid -> line
foreach ($lib in $libraries.Values) {
    $apps = Join-Path $lib 'steamapps'
    if (-not (Test-Path -LiteralPath $apps)) { continue }
    foreach ($acf in Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue) {
        try { $text = [IO.File]::ReadAllText($acf.FullName, $utf8) } catch { continue }
        $appid = Get-Field $text 'appid'
        if ($appid -eq '0') { continue }
        $flags = [int64](Get-Field $text 'StateFlags')
        $build = Get-Field $text 'buildid'
        $target = Get-Field $text 'TargetBuildID'
        if (($flags -band 2) -eq 0 -and ($target -eq '0' -or $target -eq $build)) { continue }
        $games[$appid] = '{0}|{1}|{2}|{3}' -f $appid, (Get-Field $text 'BytesToDownload'), (Get-Field $text 'BytesDownloaded'), (Get-Field $text 'ScheduledAutoUpdate')
    }
}

$lines = @($games.Keys | Sort-Object { [int64]$_ } | ForEach-Object { $games[$_] })
$text = if ($lines.Count) { ($lines -join "`r`n") + "`r`n" } else { '' }
$old = if (Test-Path -LiteralPath $outFile) { [IO.File]::ReadAllText($outFile) } else { $null }
if ($old -ne $text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outFile) | Out-Null
    [IO.File]::WriteAllText("$outFile.tmp", $text, $utf8)
    Move-Item -LiteralPath "$outFile.tmp" -Destination $outFile -Force
}
Write-Output "$($libraries.Count) Steam libraries, $($games.Count) updates waiting"
Write-Output "RESULT:UPDATES=$($games.Count)"
