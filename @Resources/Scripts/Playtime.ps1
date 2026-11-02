# Raintile: play time of the Steam games, for the line shown on the tiles
# (TileInfo). Started by the skin in the background on load.
#
# Steam keeps, for each account that logged in on this PC, the minutes
# played and the last launch of every game in
#   <Steam>\userdata\<account>\config\localconfig.vdf
# (UserLocalConfigStore > Software > Valve > Steam > apps > <appid>:
# "Playtime", "LastPlayed"). Every account is read; for a game in more than
# one, the highest values are kept.
#
# Output: Generated\Playtime.txt, one game per line:
#   <appid>|<minutes played>|<last played, unix time>
# rewritten only when it changes. Last output line, read by the skin:
# RESULT:GAMES=<number of games>.

param(
    [Parameter(Mandatory = $true)][string]$Resources,
    # tests only: Steam folder instead of the one in the registry
    [string]$SteamPath = ''
)

$ErrorActionPreference = 'Stop'
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { }
$utf8 = New-Object System.Text.UTF8Encoding $false
$Resources = [IO.Path]::GetFullPath($Resources).TrimEnd('\', '/')
$outFile = Join-Path $Resources 'Generated\Playtime.txt'

$root = $SteamPath
if (-not $root) {
    try { $root = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name 'SteamPath' -ErrorAction Stop).SteamPath } catch { $root = '' }
}
if (-not $root -or -not (Test-Path -LiteralPath $root)) {
    Write-Output 'Steam not installed'
    Write-Output 'RESULT:GAMES=0'
    exit 0
}

# A { ... } block with everything nested in it (.NET balancing groups)
$BLOCK = '\{(?>[^{}]+|\{(?<d>)|\}(?<-d>))*(?(d)(?!))\}'
$appsRegex = New-Object regex ('"apps"\s*(' + $BLOCK + ')'), 'IgnoreCase'
$appRegex = New-Object regex ('"(\d+)"\s*(' + $BLOCK + ')')
$playRegex = New-Object regex '"Playtime"\s+"(\d+)"', 'IgnoreCase'
$lastRegex = New-Object regex '"LastPlayed"\s+"(\d+)"', 'IgnoreCase'

$games = @{}   # appid -> @(minutes, last)
$userdata = Join-Path $root 'userdata'
$configs = @(Get-ChildItem -LiteralPath $userdata -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'config\localconfig.vdf' } |
    Where-Object { Test-Path -LiteralPath $_ })
foreach ($file in $configs) {
    try { $text = [IO.File]::ReadAllText($file, $utf8) } catch { continue }
    foreach ($apps in $appsRegex.Matches($text)) {
        $body = $apps.Groups[1].Value
        # the apps themselves, inside the outer braces
        foreach ($app in $appRegex.Matches($body.Substring(1, $body.Length - 2))) {
            $block = $app.Groups[2].Value
            $p = $playRegex.Match($block)
            $l = $lastRegex.Match($block)
            if (-not $p.Success -and -not $l.Success) { continue }
            $minutes = if ($p.Success) { [int64]$p.Groups[1].Value } else { 0 }
            $last = if ($l.Success) { [int64]$l.Groups[1].Value } else { 0 }
            $id = $app.Groups[1].Value
            if ($games.ContainsKey($id)) {
                $minutes = [math]::Max($minutes, $games[$id][0])
                $last = [math]::Max($last, $games[$id][1])
            }
            $games[$id] = @($minutes, $last)
        }
    }
}

$lines = @($games.Keys | Sort-Object { [int64]$_ } | ForEach-Object { '{0}|{1}|{2}' -f $_, $games[$_][0], $games[$_][1] })
$text = if ($lines.Count) { ($lines -join "`r`n") + "`r`n" } else { '' }
$old = if (Test-Path -LiteralPath $outFile) { [IO.File]::ReadAllText($outFile) } else { $null }
if ($old -ne $text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outFile) | Out-Null
    [IO.File]::WriteAllText("$outFile.tmp", $text, $utf8)
    Move-Item -LiteralPath "$outFile.tmp" -Destination $outFile -Force
}
Write-Output "$($configs.Count) Steam accounts, $($games.Count) games"
Write-Output "RESULT:GAMES=$($games.Count)"
