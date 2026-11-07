# Steam achievements widget for Raintile: the rows of the widget's list (one
# per line: "<title>|<subtitle>|<icon>|<command>") for a Steam game, from the
# Steam Web API with the user's key:
#   - the game: how many achievements are unlocked;
#   - the last ones unlocked;
#   - the locked ones most players have.
# The game is -Game (a Steam app id), or the one played last. The key is
# SteamApiKey in Raintile's Settings.inc, encrypted with DPAPI by the Options
# window. The Steam account is the one that signed in to Steam last on this
# PC. The API is asked at most every 5 minutes for the same game; icons are
# kept in the widget's folder (icons\).

param(
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Game = '',
    [Parameter(Mandatory = $true)][string]$Settings
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$utf8 = New-Object System.Text.UTF8Encoding $false
$dir = Split-Path -Parent $Out
$stamp = "$Out.stamp"

function Clean([string]$s) { return ($s -replace '[|\r\n]', ' ').Trim() }
function Row([string]$title, [string]$sub, [string]$icon, [string]$command) {
    return '{0}|{1}|{2}|{3}' -f (Clean $title), (Clean $sub), (Clean $icon), (Clean $command)
}
function Write-List([string[]]$rows) {
    [IO.File]::WriteAllText("$Out.tmp", (($rows -join "`r`n") + "`r`n"), $utf8)
    Move-Item -LiteralPath "$Out.tmp" -Destination $Out -Force
}

# --- The key ---------------------------------------------------------------------
$key = ''
if (Test-Path -LiteralPath $Settings) {
    foreach ($line in [IO.File]::ReadAllLines($Settings)) {
        if ($line -match '^\s*SteamApiKey\s*=\s*(.*?)\s*$') { $key = $Matches[1] }
    }
}
if ($key.StartsWith('dpapi:')) {
    try {
        Add-Type -AssemblyName System.Security
        $bytes = [Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($key.Substring(6)),
            [Text.Encoding]::UTF8.GetBytes('Raintile SteamGridDB key'), [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $key = [Text.Encoding]::UTF8.GetString($bytes)
    }
    catch { $key = '' }
}
if ($key -notmatch '^[0-9A-Fa-f]{32}$') {
    Write-List @(Row 'Add your Steam Web API key' 'Options > Widgets > Steam' '' 'https://steamcommunity.com/dev/apikey')
    exit 0
}

# --- The account: the one that signed in last (config\loginusers.vdf) -----------
$steamId = ''
try {
    $root = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name SteamPath).SteamPath -replace '/', '\'
    $vdf = [IO.File]::ReadAllText((Join-Path $root 'config\loginusers.vdf'))
    foreach ($m in [regex]::Matches($vdf, '"(\d{17})"\s*\{([^}]*)\}')) {
        if ($m.Groups[2].Value -match '"MostRecent"\s*"1"') { $steamId = $m.Groups[1].Value }
    }
}
catch { }
if ($steamId -eq '') {
    Write-List @(Row 'No Steam account found' 'Sign in to Steam on this PC' '' '')
    exit 0
}

$api = 'https://api.steampowered.com'
function Get-Api([string]$path) {
    return Invoke-RestMethod -Uri "$api/$path" -UseBasicParsing -TimeoutSec 15
}

# --- The game ----------------------------------------------------------------------
$appId = ($Game -replace '\D', '')
if ($appId -eq '') {
    try {
        $recent = Get-Api "IPlayerService/GetRecentlyPlayedGames/v1/?key=$key&steamid=$steamId&count=1"
        $appId = "$($recent.response.games[0].appid)"
    }
    catch { }
    if ($appId -eq '') {
        Write-List @(Row 'No game played lately' 'Or choose one: the tile''s widget setting (app id)' '' '')
        exit 0
    }
}

# Nothing to do: the same game asked less than 5 minutes ago
if ((Test-Path -LiteralPath $stamp) -and (Test-Path -LiteralPath $Out)) {
    $last = [IO.File]::ReadAllText($stamp).Trim() -split '\|'
    if ($last.Count -eq 2 -and $last[0] -eq $appId -and ((Get-Date).ToUniversalTime() - [DateTime]::FromFileTimeUtc([long]$last[1])).TotalMinutes -lt 5) { exit 0 }
}

# --- Achievements --------------------------------------------------------------------
try {
    $player = (Get-Api "ISteamUserStats/GetPlayerAchievements/v1/?appid=$appId&key=$key&steamid=$steamId&l=english").playerstats
}
catch {
    # 403: the profile's game details are private; 400: a game without achievements
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    if ($code -eq 403) { Write-List @(Row 'Steam says your game details are private' 'Steam > Profile > Privacy: Game details public' '' 'steam://url/SteamIDEditPage') }
    elseif ($code -eq 400) { Write-List @(Row 'No achievements for this game' "App $appId" '' '') }
    else { exit 1 } # no connection: the last list stays
    exit 0
}
$schema = $null
try { $schema = (Get-Api "ISteamUserStats/GetSchemaForGame/v2/?key=$key&appid=$appId&l=english").game.availableGameStats.achievements } catch { }
$percent = @{}
try {
    foreach ($a in (Get-Api "ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/?gameid=$appId").achievementpercentages.achievements) {
        $percent[$a.name] = [double]$a.percent
    }
}
catch { }

$name = "$($player.gameName)"
if ($name -eq '') { $name = "App $appId" }
$all = @($player.achievements)
if ($all.Count -eq 0) {
    Write-List @(Row $name 'No achievements' '' '')
    exit 0
}
$info = @{}
foreach ($s in @($schema)) { if ($s) { $info[$s.name] = $s } }

# An image of Steam's, kept in icons\ (only https from Steam's servers)
function Get-Icon([string]$url) {
    if ($url -notmatch '^https://(cdn\.[a-z.]*steamstatic\.com|steamcdn-a\.akamaihd\.net|shared\.[a-z.]*steamstatic\.com)/') { return '' }
    # named after the last two parts of the address: the game's capsule has the
    # same file name for every game (apps/<appid>/capsule_184x69.jpg)
    $parts = ([Uri]$url).AbsolutePath.Trim('/') -split '/'
    $name = ($parts[-2..-1] -join '_') -replace '[^A-Za-z0-9._-]', '_'
    $file = Join-Path (Join-Path $dir 'icons') $name
    if (-not (Test-Path -LiteralPath $file)) {
        try {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
            Invoke-WebRequest -Uri $url -OutFile "$file.tmp" -UseBasicParsing -TimeoutSec 15
            Move-Item -LiteralPath "$file.tmp" -Destination $file -Force
        }
        catch { return '' }
    }
    return $file
}

function Ago([long]$unix) {
    $when = [DateTimeOffset]::FromUnixTimeSeconds($unix).LocalDateTime
    $days = ((Get-Date).Date - $when.Date).Days
    if ($days -le 0) { return 'today' }
    if ($days -eq 1) { return 'yesterday' }
    if ($days -lt 7) { return "$days days ago" }
    return $when.ToString('d MMM yyyy', [Globalization.CultureInfo]::InvariantCulture)
}

$page = "steam://openurl/https://steamcommunity.com/profiles/$steamId/stats/$appId/achievements"
$done = @($all | Where-Object { $_.achieved -eq 1 })
$rows = @(Row $name ("{0} of {1} achievements" -f $done.Count, $all.Count) (Get-Icon "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/$appId/capsule_184x69.jpg") $page)
# the last ones unlocked (3), then the locked ones most players have
foreach ($a in @($done | Sort-Object { [long]$_.unlocktime } -Descending | Select-Object -First 3)) {
    $s = $info[$a.apiname]
    $title = if ($s) { $s.displayName } else { $a.apiname }
    $rows += Row $title ('Unlocked ' + (Ago ([long]$a.unlocktime))) (Get-Icon "$($s.icon)") $page
}
$locked = @($all | Where-Object { $_.achieved -ne 1 } | Sort-Object { if ($percent.ContainsKey($_.apiname)) { -$percent[$_.apiname] } else { 0 } })
foreach ($a in @($locked | Select-Object -First 6)) {
    $s = $info[$a.apiname]
    $title = if ($s) { $s.displayName } else { $a.apiname }
    $sub = if ($percent.ContainsKey($a.apiname)) { '{0:0.#}% of players' -f $percent[$a.apiname] } else { 'Locked' }
    if ($s -and "$($s.description)" -ne '') { $sub += ' - ' + $s.description }
    $rows += Row $title $sub (Get-Icon "$($s.icongray)") $page
}
Write-List $rows
[IO.File]::WriteAllText($stamp, "$appId|$((Get-Date).ToUniversalTime().ToFileTimeUtc())", $utf8)
