# Raintile: imports the games installed from stores into a category file.
#
# Stores read: Steam, Epic Games, GOG Galaxy, Ubisoft Connect.
# The games found are written at the end of the category file, after the
# IMPORT_MARKER line: everything above it (the hand-written tiles) is never
# touched, the block below is rewritten on every import.
# A game already among the hand-written tiles of any category (same name or
# same command) is not imported again: it may have been moved elsewhere.
#
# Images: Steam keeps them locally (appcache\librarycache). For the other
# stores, and for Steam games without local images, they are downloaded to
# Images\<category>\imported\ if a SteamGridDB API key is set.
# An image placed by hand in background\<Name>.* or logo\<Name>.* always takes
# precedence.

param(
    [Parameter(Mandatory = $true)][string]$Resources,
    [string]$Category = 'Games',
    [string]$Stores = 'Steam|Epic|GOG|Ubisoft',
    [string]$SteamGridDBKey = '',
    # tests only: alternative paths instead of the registry and ProgramData
    [string]$SteamPath = '',
    [string]$EpicManifests = ''
)

$ErrorActionPreference = 'Stop'
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { }
$IMPORT_MARKER = '; ===== IMPORTED AUTOMATICALLY ====='
# Marker written by older Italian versions, still recognised
$OLD_IMPORT_MARKER = '; ===== IMPORTATI AUTOMATICAMENTE ====='

# Position of the import marker in a category file (-1 if missing)
function Find-ImportMarker([string]$text) {
    $i = $text.IndexOf($IMPORT_MARKER)
    if ($i -lt 0) { $i = $text.IndexOf($OLD_IMPORT_MARKER) }
    return $i
}
$imageExts = '.png', '.jpg', '.jpeg', '.bmp', '.ico', '.gif'
$utf8 = New-Object System.Text.UTF8Encoding $false

$categoryFile = Join-Path $Resources "Categories\$Category.ini"
$imagesDir = Join-Path $Resources "Images\$Category"
$importedDir = Join-Path $imagesDir 'imported'
$enabled = @{}
foreach ($s in $Stores.Split('|')) { if ($s.Trim()) { $enabled[$s.Trim().ToLowerInvariant()] = $true } }

function Get-RegValue($path, $name) {
    try { return (Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop).$name } catch { return $null }
}

# Name usable as an INI section and as a file name
function Get-TileName([string]$name) {
    $n = $name -replace '[\[\]]', '' -replace '[\u2122\u00AE\u00A9]', '' -replace '[\\/:*?"<>|]', ' '
    $n = ($n -replace '\s+', ' ').Trim().TrimStart(';')
    return $n.Trim()
}

function Find-Image([string]$dir, [string]$name) {
    foreach ($ext in $imageExts) {
        $p = Join-Path $dir ($name + $ext)
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# --- Store -------------------------------------------------------------------

$games = New-Object System.Collections.ArrayList

function Add-Game($store, $id, $name, $command, $hero, $logo, $steamAppId) {
    [void]$games.Add([pscustomobject]@{
            Store = $store; Id = "$id"; Name = $name; Command = $command
            Hero = $hero; Logo = $logo; SteamAppId = $steamAppId
        })
}

function Read-Steam {
    $root = $SteamPath
    if (-not $root) { $root = Get-RegValue 'HKCU:\Software\Valve\Steam' 'SteamPath' }
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { return 'not installed' }
    $root = $root -replace '/', '\'

    $libraries = @($root)
    $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw -Encoding UTF8), '"path"\s+"([^"]+)"')) {
            $libraries += $m.Groups[1].Value -replace '\\\\', '\'
        }
    }
    $cache = Join-Path $root 'appcache\librarycache'
    $skip = 'Steamworks Common Redistributables|Steam Linux Runtime|^Proton |Steam Controller Configs|SteamVR'
    $seen = @{}
    $count = 0
    foreach ($lib in ($libraries | Select-Object -Unique)) {
        $apps = Join-Path $lib 'steamapps'
        if (-not (Test-Path -LiteralPath $apps)) { continue }
        foreach ($acf in Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File) {
            $text = Get-Content -LiteralPath $acf.FullName -Raw -Encoding UTF8
            $appid = [regex]::Match($text, '"appid"\s+"(\d+)"').Groups[1].Value
            $name = [regex]::Match($text, '"name"\s+"([^"]+)"').Groups[1].Value
            if (-not $appid -or -not $name -or $seen[$appid] -or $name -match $skip) { continue }
            $seen[$appid] = $true

            # Library cache: old layout <appid>_library_hero.jpg,
            # new layout <appid>\...\library_hero.jpg
            $hero = $null; $logo = $null
            foreach ($f in @("${appid}_library_hero.jpg", "${appid}_library_hero.png")) {
                $p = Join-Path $cache $f
                if (-not $hero -and (Test-Path -LiteralPath $p)) { $hero = $p }
            }
            $p = Join-Path $cache "${appid}_logo.png"
            if (Test-Path -LiteralPath $p) { $logo = $p }
            $sub = Join-Path $cache $appid
            if (Test-Path -LiteralPath $sub) {
                $files = Get-ChildItem -LiteralPath $sub -Recurse -File
                if (-not $hero) { $hero = ($files | Where-Object { $_.Name -like 'library_hero.*' } | Select-Object -First 1).FullName }
                if (-not $logo) { $logo = ($files | Where-Object { $_.Name -like 'logo.*' } | Select-Object -First 1).FullName }
            }
            Add-Game 'Steam' $appid $name "steam://rungameid/$appid" $hero $logo $appid
            $count++
        }
    }
    return "$count found"
}

function Read-Epic {
    $dir = $EpicManifests
    if (-not $dir) { $dir = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests' }
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return 'not installed' }
    $count = 0
    foreach ($item in Get-ChildItem -LiteralPath $dir -Filter '*.item' -File) {
        try { $m = Get-Content -LiteralPath $item.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        if (-not $m.DisplayName -or -not $m.AppName) { continue }
        # main games only (no DLC, no applications)
        if ($m.AppCategories -and ($m.AppCategories -notcontains 'games')) { continue }
        if ($m.MainGameAppName -and $m.MainGameAppName -ne $m.AppName) { continue }
        $cmd = 'com.epicgames.launcher://apps/{0}%3A{1}%3A{2}?action=launch&silent=true' -f `
            $m.CatalogNamespace, $m.CatalogItemId, $m.AppName
        Add-Game 'Epic' $m.AppName $m.DisplayName $cmd $null $null $null
        $count++
    }
    return "$count found"
}

function Read-GOG {
    $key = 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games'
    if (-not (Test-Path $key)) { return 'not installed' }
    $client = Get-RegValue 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\GalaxyClient\paths' 'client'
    $count = 0
    foreach ($g in Get-ChildItem $key) {
        $p = Get-ItemProperty $g.PSPath
        if (-not $p.gameName -or ($p.dependsOn -and "$($p.dependsOn)".Trim())) { continue }
        if ($client) {
            $exe = Join-Path $client 'GalaxyClient.exe'
            $cmd = '"{0}" /command=runGame /gameId={1} /path="{2}"' -f $exe, $p.gameID, $p.path
        } elseif ($p.exe) {
            $cmd = '"{0}"' -f $p.exe
        } else { continue }
        Add-Game 'GOG' $p.gameID $p.gameName $cmd $null $null $null
        $count++
    }
    return "$count found"
}

function Read-Ubisoft {
    $key = 'HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs'
    if (-not (Test-Path $key)) { return 'not installed' }
    $count = 0
    foreach ($g in Get-ChildItem $key) {
        $dir = Get-RegValue $g.PSPath 'InstallDir'
        if (-not $dir) { continue }
        $name = Split-Path ($dir.TrimEnd('\', '/')) -Leaf
        Add-Game 'Ubisoft' $g.PSChildName $name "uplay://launch/$($g.PSChildName)/0" $null $null $null
        $count++
    }
    return "$count found"
}

# --- SteamGridDB -------------------------------------------------------------

function Invoke-SGDB([string]$path) {
    $headers = @{ Authorization = "Bearer $SteamGridDBKey" }
    $r = Invoke-RestMethod -Uri ("https://www.steamgriddb.com/api/v2/" + $path) -Headers $headers -TimeoutSec 15
    if ($r.success) { return $r.data }
    return $null
}

# Downloads (only once) the game's hero and logo to Images\<category>\imported\
function Get-SGDBImages($game, [string]$tileName) {
    $result = @{}
    if (-not $SteamGridDBKey) { return $result }
    $base = Join-Path $importedDir $tileName
    $hero = Find-Image $importedDir "$tileName.hero"
    $logo = Find-Image $importedDir "$tileName.logo"
    if ($hero -and $logo) { return @{ Hero = $hero; Logo = $logo } }
    try {
        if ($game.SteamAppId) {
            $id = (Invoke-SGDB "games/steam/$($game.SteamAppId)").id
        } else {
            $id = (Invoke-SGDB ("search/autocomplete/" + [uri]::EscapeDataString($game.Name)) | Select-Object -First 1).id
        }
        if (-not $id) { return @{ Hero = $hero; Logo = $logo } }
        New-Item -ItemType Directory -Force -Path $importedDir | Out-Null
        foreach ($kind in 'heroes', 'logos') {
            $suffix = if ($kind -eq 'heroes') { 'hero' } else { 'logo' }
            if (Find-Image $importedDir "$tileName.$suffix") { continue }
            $img = Invoke-SGDB "$kind/game/$id" | Select-Object -First 1
            if (-not $img) { continue }
            $ext = [IO.Path]::GetExtension(([uri]$img.url).AbsolutePath)
            if ($imageExts -notcontains $ext.ToLowerInvariant()) { $ext = '.png' }
            Invoke-WebRequest -Uri $img.url -OutFile "$base.$suffix$ext" -UseBasicParsing -TimeoutSec 30
        }
    } catch {
        Write-Output "SteamGridDB: images not downloaded for $($game.Name): $($_.Exception.Message)"
    }
    return @{ Hero = (Find-Image $importedDir "$tileName.hero"); Logo = (Find-Image $importedDir "$tileName.logo") }
}

# --- Writing the category file -----------------------------------------------

$summary = @()
foreach ($store in 'Steam', 'Epic', 'GOG', 'Ubisoft') {
    if (-not $enabled[$store.ToLowerInvariant()]) { continue }
    try { $summary += "${store}: " + (& "Read-$store") }
    catch { $summary += "${store}: error ($($_.Exception.Message))" }
}

# Hand-written part (everything before the marker) and its tiles
$manual = ''
if (Test-Path -LiteralPath $categoryFile) {
    $text = [IO.File]::ReadAllText($categoryFile)
    $i = Find-ImportMarker $text
    $manual = if ($i -ge 0) { $text.Substring(0, $i) } else { $text }
} else {
    $manual = "[Category]`r`nName=$Category`r`n"
}
$manual = $manual.TrimEnd() + "`r`n"

# Hand-written tiles: those of this category and of all the others
$manualNames = @{}; $manualCommands = @{}
$texts = @($manual)
foreach ($f in @(Get-ChildItem -LiteralPath (Split-Path -Parent $categoryFile) -Filter '*.ini' -File -ErrorAction SilentlyContinue)) {
    if ($f.FullName -ieq [IO.Path]::GetFullPath($categoryFile)) { continue }
    $other = [IO.File]::ReadAllText($f.FullName)
    $j = Find-ImportMarker $other
    $texts += $(if ($j -ge 0) { $other.Substring(0, $j) } else { $other })
}
foreach ($text in $texts) {
    $section = $null
    foreach ($line in $text -split "`r?`n") {
        $t = $line.Trim()
        if ($t -match '^\[(.+)\]$') {
            $section = $Matches[1].Trim()
            if ($section -ine 'Category') { $manualNames[$section.ToLowerInvariant()] = $true }
        }
        elseif ($section -and $t -match '^(?i)command\s*=\s*(.+)$') { $manualCommands[$Matches[1].Trim().ToLowerInvariant()] = $true }
    }
}

$out = New-Object System.Text.StringBuilder
[void]$out.Append($manual)
[void]$out.Append("`r`n$IMPORT_MARKER`r`n")
[void]$out.Append("; Written by Import games: this block is rewritten on every import.`r`n")
[void]$out.Append("; To customise a game, move its section above this line.`r`n")

$used = @{}
$imported = 0; $skipped = 0
foreach ($g in ($games | Sort-Object Name)) {
    $name = Get-TileName $g.Name
    if (-not $name) { continue }
    $key = $name.ToLowerInvariant()
    if ($manualNames[$key] -or $manualCommands[$g.Command.ToLowerInvariant()]) { $skipped++; continue }
    if ($used[$key]) { $name = "$name ($($g.Store))"; $key = $name.ToLowerInvariant() }
    if ($used[$key]) { continue }
    $used[$key] = $true

    $hero = $g.Hero; $logo = $g.Logo
    if (-not $hero -or -not $logo) {
        $sgdb = Get-SGDBImages $g $name
        if (-not $hero) { $hero = $sgdb.Hero }
        if (-not $logo) { $logo = $sgdb.Logo }
    }

    [void]$out.Append("`r`n[$name]`r`n")
    [void]$out.Append("Command=$($g.Command)`r`n")
    # an image placed by hand in the default folder takes precedence
    if ($hero -and -not (Find-Image (Join-Path $imagesDir 'background') $name)) {
        [void]$out.Append("Background=$hero`r`n")
    }
    if ($logo -and -not (Find-Image (Join-Path $imagesDir 'logo') $name)) {
        [void]$out.Append("Logo=$logo`r`n")
    }
    [void]$out.Append("Source=$($g.Store):$($g.Id)`r`n")
    $imported++
}

# Rewrite the file only if it changed: the skin only refreshes in that case
$new = $out.ToString()
$old = if (Test-Path -LiteralPath $categoryFile) { [IO.File]::ReadAllText($categoryFile) } else { '' }
$changed = $new -ne $old
if ($changed) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $categoryFile) | Out-Null
    $tmp = "$categoryFile.tmp"
    [IO.File]::WriteAllText($tmp, $new, $utf8)
    Move-Item -LiteralPath $tmp -Destination $categoryFile -Force
}

foreach ($s in $summary) { Write-Output $s }
Write-Output "Imported $imported games into $Category.ini ($skipped already among the hand-written tiles)"
# last line, read by the skin
if ($changed) { Write-Output 'RESULT:CHANGED' } else { Write-Output 'RESULT:UNCHANGED' }
