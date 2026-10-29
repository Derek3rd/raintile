# Raintile: importa i giochi installati dagli store in un file di categoria.
#
# Store letti: Steam, Epic Games, GOG Galaxy, Ubisoft Connect.
# I giochi trovati vengono scritti in fondo al file di categoria, dopo la riga
# segnaposto IMPORT_MARKER: tutto cio' che sta sopra (le tile scritte a mano)
# non viene mai toccato, il blocco sotto viene riscritto a ogni import.
# Un gioco gia' presente tra le tile a mano (stesso nome o stesso comando) non
# viene importato di nuovo.
#
# Immagini: Steam le tiene gia' in locale (appcache\librarycache). Per gli
# altri store, e per i giochi Steam senza immagini locali, se c'e' una chiave
# API di SteamGridDB vengono scaricate in Images\<categoria>\imported\.
# Un'immagine messa a mano in background\<Nome>.* o logo\<Nome>.* ha sempre la
# precedenza.

param(
    [Parameter(Mandatory = $true)][string]$Resources,
    [string]$Category = 'Games',
    [string]$Stores = 'Steam|Epic|GOG|Ubisoft',
    [string]$SteamGridDBKey = '',
    # solo per i test: percorsi alternativi al posto di registro e ProgramData
    [string]$SteamPath = '',
    [string]$EpicManifests = ''
)

$ErrorActionPreference = 'Stop'
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { }
$IMPORT_MARKER = '; ===== IMPORTATI AUTOMATICAMENTE ====='
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

# Nome utilizzabile come sezione INI e come nome di file
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
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { return 'non installato' }
    $root = $root -replace '/', '\'

    $libraries = @($root)
    $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
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
            $text = Get-Content -LiteralPath $acf.FullName -Raw
            $appid = [regex]::Match($text, '"appid"\s+"(\d+)"').Groups[1].Value
            $name = [regex]::Match($text, '"name"\s+"([^"]+)"').Groups[1].Value
            if (-not $appid -or -not $name -or $seen[$appid] -or $name -match $skip) { continue }
            $seen[$appid] = $true

            # Cache della libreria: vecchio formato <appid>_library_hero.jpg,
            # nuovo formato <appid>\...\library_hero.jpg
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
    return "$count trovati"
}

function Read-Epic {
    $dir = $EpicManifests
    if (-not $dir) { $dir = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests' }
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return 'non installato' }
    $count = 0
    foreach ($item in Get-ChildItem -LiteralPath $dir -Filter '*.item' -File) {
        try { $m = Get-Content -LiteralPath $item.FullName -Raw | ConvertFrom-Json } catch { continue }
        if (-not $m.DisplayName -or -not $m.AppName) { continue }
        # solo giochi principali (niente DLC, niente applicazioni)
        if ($m.AppCategories -and ($m.AppCategories -notcontains 'games')) { continue }
        if ($m.MainGameAppName -and $m.MainGameAppName -ne $m.AppName) { continue }
        $cmd = 'com.epicgames.launcher://apps/{0}%3A{1}%3A{2}?action=launch&silent=true' -f `
            $m.CatalogNamespace, $m.CatalogItemId, $m.AppName
        Add-Game 'Epic' $m.AppName $m.DisplayName $cmd $null $null $null
        $count++
    }
    return "$count trovati"
}

function Read-GOG {
    $key = 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games'
    if (-not (Test-Path $key)) { return 'non installato' }
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
    return "$count trovati"
}

function Read-Ubisoft {
    $key = 'HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs'
    if (-not (Test-Path $key)) { return 'non installato' }
    $count = 0
    foreach ($g in Get-ChildItem $key) {
        $dir = Get-RegValue $g.PSPath 'InstallDir'
        if (-not $dir) { continue }
        $name = Split-Path ($dir.TrimEnd('\', '/')) -Leaf
        Add-Game 'Ubisoft' $g.PSChildName $name "uplay://launch/$($g.PSChildName)/0" $null $null $null
        $count++
    }
    return "$count trovati"
}

# --- SteamGridDB -------------------------------------------------------------

function Invoke-SGDB([string]$path) {
    $headers = @{ Authorization = "Bearer $SteamGridDBKey" }
    $r = Invoke-RestMethod -Uri ("https://www.steamgriddb.com/api/v2/" + $path) -Headers $headers -TimeoutSec 15
    if ($r.success) { return $r.data }
    return $null
}

# Scarica (una volta sola) eroe e logo del gioco in Images\<categoria>\imported\
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
        Write-Output "SteamGridDB: immagini non scaricate per $($game.Name): $($_.Exception.Message)"
    }
    return @{ Hero = (Find-Image $importedDir "$tileName.hero"); Logo = (Find-Image $importedDir "$tileName.logo") }
}

# --- Scrittura del file di categoria ------------------------------------------

$summary = @()
foreach ($store in 'Steam', 'Epic', 'GOG', 'Ubisoft') {
    if (-not $enabled[$store.ToLowerInvariant()]) { continue }
    try { $summary += "${store}: " + (& "Read-$store") }
    catch { $summary += "${store}: errore ($($_.Exception.Message))" }
}

# Parte scritta a mano (tutto prima del segnaposto) e sue tile
$manual = ''
if (Test-Path -LiteralPath $categoryFile) {
    $text = [IO.File]::ReadAllText($categoryFile)
    $i = $text.IndexOf($IMPORT_MARKER)
    $manual = if ($i -ge 0) { $text.Substring(0, $i) } else { $text }
} else {
    $manual = "[Category]`r`nName=$Category`r`n"
}
$manual = $manual.TrimEnd() + "`r`n"

$manualNames = @{}; $manualCommands = @{}
$section = $null
foreach ($line in $manual -split "`r?`n") {
    $t = $line.Trim()
    if ($t -match '^\[(.+)\]$') { $section = $Matches[1].Trim(); $manualNames[$section.ToLowerInvariant()] = $true }
    elseif ($section -and $t -match '^(?i)command\s*=\s*(.+)$') { $manualCommands[$Matches[1].Trim().ToLowerInvariant()] = $true }
}

$out = New-Object System.Text.StringBuilder
[void]$out.Append($manual)
[void]$out.Append("`r`n$IMPORT_MARKER`r`n")
[void]$out.Append("; Scritti da Importa giochi: questo blocco viene riscritto a ogni import.`r`n")
[void]$out.Append("; Per personalizzare un gioco spostane la sezione sopra questa riga.`r`n")

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
    # un'immagine messa a mano nella cartella di default ha la precedenza
    if ($hero -and -not (Find-Image (Join-Path $imagesDir 'background') $name)) {
        [void]$out.Append("Background=$hero`r`n")
    }
    if ($logo -and -not (Find-Image (Join-Path $imagesDir 'logo') $name)) {
        [void]$out.Append("Logo=$logo`r`n")
    }
    [void]$out.Append("Source=$($g.Store):$($g.Id)`r`n")
    $imported++
}

# Riscrive il file solo se e' cambiato: la skin si ricarica solo in quel caso
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
Write-Output "Importati $imported giochi in $Category.ini ($skipped gia' presenti tra le tile a mano)"
# ultima riga letta dalla skin
if ($changed) { Write-Output 'RESULT:CHANGED' } else { Write-Output 'RESULT:UNCHANGED' }
