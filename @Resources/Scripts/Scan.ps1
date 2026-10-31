# Raintile: looks for the games and apps installed on this PC. Nothing is
# added to the launcher: the list (Generated\Found.json) is shown in the
# Options window (Import), where you pick what to add.
#
# Games: Steam, Epic Games, GOG Galaxy, Ubisoft Connect, Battle.net, EA app,
# Xbox (Microsoft Store / Game Pass). Apps: what the Start menu lists, desktop
# programs (shortcuts) and Store apps, without uninstallers, help files and
# the like, and without the games already found.
#
# Each item: Id, Kind (game/app), Store, Name, Command, Hero and Logo (local
# images, Steam only), Icon (program icon, extracted to Generated\Found\),
# SteamAppId, New. New = not among the tiles of any category and not seen yet
# in the list (Seen.txt in the data folder, written by the Options window).
# The last output line, read by the skin, is RESULT:NEW=<number of new items>.
#
# With -NoRun only the functions are loaded (Options window, tests).

param(
    [Parameter(Mandatory = $true)][string]$Resources,
    # folder with your data (Categories\, Seen.txt); the skin's own if empty
    [string]$Data = '',
    [string]$Stores = 'Steam|Epic|GOG|Ubisoft|Battlenet|EA|Xbox|Apps',
    [switch]$NoRun,
    # tests only: alternative paths instead of the registry and ProgramData
    [string]$SteamPath = '',
    [string]$EpicManifests = '',
    [string]$StartMenu = ''
)

$ErrorActionPreference = 'Stop'
$imageExts = '.png', '.jpg', '.jpeg', '.bmp', '.ico', '.gif'
$utf8 = New-Object System.Text.UTF8Encoding $false
$Resources = [IO.Path]::GetFullPath($Resources).TrimEnd('\', '/')
$Data = if ($Data) { [IO.Path]::GetFullPath($Data).TrimEnd('\', '/') } else { $Resources }
$generated = Join-Path $Resources 'Generated'
$foundFile = Join-Path $generated 'Found.json'
$seenFile = Join-Path $Data 'Seen.txt'
$iconDir = Join-Path $generated 'Found'

function Get-RegValue($path, $name) {
    try { return (Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop).$name } catch { return $null }
}

# Name usable as an INI section and as a file name: no brackets, no
# characters Windows refuses in file names, no control characters, no
# leading or trailing dots (so a name can never point to another folder)
function Get-TileName([string]$name) {
    $n = $name -replace '[\x00-\x1F\x7F]', ' ' -replace '[\[\]]', '' -replace '[\u2122\u00AE\u00A9]', '' -replace '[\\/:*?"<>|]', ' '
    $n = ($n -replace '\s+', ' ').Trim().Trim('.', ' ').TrimStart(';').Trim('.', ' ')
    return $n
}

# Key to compare names: lower case, without spaces and light punctuation
# ("Half-Life: Alyx" = "half life alyx"; "Notepad++" stays apart from "Notepad")
function Get-NameKey([string]$name) {
    return ((Get-TileName $name).ToLowerInvariant() -replace "[\s\-_:.,'!\u2019]", '')
}

# Exe path from a registry DisplayIcon value: "C:\x\game.exe",0 -> C:\x\game.exe
function Get-ExeFromIcon([string]$value) {
    if (-not $value) { return $null }
    $p = ($value -replace ',\s*-?\d+\s*$', '').Trim().Trim('"')
    if ($p -match '\.exe$' -and (Test-Path -LiteralPath $p)) { return $p }
    return $null
}

# Programs and Features entries (machine and user, 32 and 64 bit)
function Get-UninstallEntries {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    foreach ($k in $keys) {
        if (-not (Test-Path $k)) { continue }
        foreach ($e in Get-ChildItem $k -ErrorAction SilentlyContinue) {
            try { $p = Get-ItemProperty $e.PSPath } catch { continue }
            if ($p.DisplayName) { $p }
        }
    }
}

# --- Items -----------------------------------------------------------------------

$items = New-Object System.Collections.ArrayList
$gameDirs = New-Object System.Collections.ArrayList   # install folders: their shortcuts are not apps
$gameNames = @{}

function Add-Item([string]$kind, [string]$store, [string]$id, [string]$name, [string]$command,
    [string]$hero = '', [string]$logo = '', [string]$iconSource = '', [string]$steamAppId = '') {
    $name = Get-TileName $name
    if (-not $name -or -not $command) { return }
    if ($kind -eq 'game') { $gameNames[(Get-NameKey $name)] = $true }
    [void]$items.Add([pscustomobject]@{
            Id = "${store}:$id"; Kind = $kind; Store = $store; Name = $name; Command = $command
            Hero = $hero; Logo = $logo; Icon = ''; IconSource = $iconSource; SteamAppId = $steamAppId; New = $false
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
        [void]$gameDirs.Add((Join-Path $apps 'common'))
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
            Add-Item 'game' 'Steam' $appid $name "steam://rungameid/$appid" $hero $logo '' $appid
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
        $exe = ''
        if ($m.InstallLocation) {
            [void]$gameDirs.Add($m.InstallLocation)
            if ($m.LaunchExecutable) { $exe = Join-Path $m.InstallLocation $m.LaunchExecutable }
        }
        Add-Item 'game' 'Epic' $m.AppName $m.DisplayName $cmd '' '' $exe
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
        if ($p.path) { [void]$gameDirs.Add($p.path) }
        Add-Item 'game' 'GOG' $p.gameID $p.gameName $cmd '' '' "$($p.exe)"
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
        [void]$gameDirs.Add($dir)
        $name = Split-Path ($dir.TrimEnd('\', '/')) -Leaf
        Add-Item 'game' 'Ubisoft' $g.PSChildName $name "uplay://launch/$($g.PSChildName)/0"
        $count++
    }
    return "$count found"
}

# Battle.net: the uninstall entries of its games carry the product uid
# (--uid=fenris); the known ones launch through Battle.net, the others with
# their own launcher (DisplayIcon).
$BATTLENET_CODES = @{
    'wow' = 'WoW'; 'wow_classic' = 'WoWC'; 'wow_classic_era' = 'WoWC'; 'd3' = 'D3'; 'diablo3' = 'D3'
    'fenris' = 'Fen'; 'osi' = 'OSI'; 'anbs' = 'ANBS'; 's2' = 'S2'; 's1' = 'S1'; 'w3' = 'W3'
    'hs_beta' = 'WTCG'; 'heroes' = 'Hero'; 'prometheus' = 'Pro'; 'rtro' = 'RTRO'; 'wlby' = 'WLBY'
    'viper' = 'VIPR'; 'odin' = 'ODIN'; 'lazarus' = 'LAZR'; 'zeus' = 'ZEUS'; 'fore' = 'FORE'; 'auks' = 'AUKS'
}
function Read-Battlenet {
    $entries = @(Get-UninstallEntries)
    $client = @($entries | Where-Object { $_.DisplayName -eq 'Battle.net' } | Select-Object -First 1)
    $exe = $null
    foreach ($c in @(
            $(if ($client -and $client[0].InstallLocation) { Join-Path $client[0].InstallLocation 'Battle.net.exe' }),
            $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Battle.net\Battle.net.exe' }))) {
        if ($c -and (Test-Path -LiteralPath $c)) { $exe = $c; break }
    }
    if (-not $exe -and -not $client) { return 'not installed' }
    $count = 0
    foreach ($e in $entries) {
        if ("$($e.UninstallString)" -notmatch 'Battle\.net' -or $e.DisplayName -eq 'Battle.net') { continue }
        $uid = [regex]::Match("$($e.UninstallString)", '--uid=([^\s"]+)').Groups[1].Value
        $code = $BATTLENET_CODES[$uid.ToLowerInvariant()]
        $own = Get-ExeFromIcon $e.DisplayIcon
        if ($code -and $exe) { $cmd = '"{0}" --exec="launch {1}"' -f $exe, $code }
        elseif ($own) { $cmd = '"{0}"' -f $own }
        else { continue }
        if ($e.InstallLocation) { [void]$gameDirs.Add($e.InstallLocation) }
        Add-Item 'game' 'Battle.net' $(if ($uid) { $uid } else { $e.DisplayName }) $e.DisplayName $cmd '' '' "$own"
        $count++
    }
    return "$count found"
}

# EA app: uninstall entries of Electronic Arts games, launched with their own
# exe (DisplayIcon); the EA app and its helpers are left out
function Read-EA {
    $entries = @(Get-UninstallEntries)
    $count = 0
    $any = $false
    foreach ($e in $entries) {
        $isEA = "$($e.Publisher)" -match 'Electronic Arts' -or "$($e.UninstallString)" -match 'EAInstaller|EA Desktop|\\Origin\\'
        if (-not $isEA) { continue }
        $any = $true
        if ($e.DisplayName -match '^(EA app|EA|Origin|EA Desktop)$|Overlay|Touchup|Redistributable|Anti-?Cheat') { continue }
        $own = Get-ExeFromIcon $e.DisplayIcon
        if (-not $own) { continue }
        if ($e.InstallLocation) { [void]$gameDirs.Add($e.InstallLocation) }
        Add-Item 'game' 'EA' $e.PSChildName $e.DisplayName ('"{0}"' -f $own) '' '' $own
        $count++
    }
    if (-not $any) { return 'not installed' }
    return "$count found"
}

# Start menu entries: Name, AppID (Get-StartApps, Windows 10/11)
$script:startApps = $null
function Get-StartEntries {
    if ($null -eq $script:startApps) {
        $script:startApps = @()
        try { $script:startApps = @(Get-StartApps) } catch { }
    }
    return $script:startApps
}

# Xbox / Microsoft Store games: Store packages with a MicrosoftGame.config
function Read-Xbox {
    try { $packages = @(Get-AppxPackage -ErrorAction Stop) } catch { return 'not available' }
    $start = Get-StartEntries
    $count = 0
    foreach ($p in $packages) {
        if ($p.IsFramework -or -not $p.InstallLocation) { continue }
        $isGame = $false
        try { $isGame = Test-Path -LiteralPath (Join-Path $p.InstallLocation 'MicrosoftGame.config') } catch { }
        if (-not $isGame) { continue }
        foreach ($a in @($start | Where-Object { $_.AppID -like "$($p.PackageFamilyName)!*" })) {
            Add-Item 'game' 'Xbox' $a.AppID $a.Name ('explorer.exe "shell:AppsFolder\{0}"' -f $a.AppID) '' '' "shell:AppsFolder\$($a.AppID)"
            $count++
        }
    }
    return "$count found"
}

# Apps: Start menu shortcuts (desktop programs) and Store apps
$APP_SKIP = '(?i)uninstall|deinstall|readme|read me|\bhelp\b|documentation|\bmanual\b|licen[cs]e|release notes|changelog|' +
'website|web site|homepage|\bsupport\b|\bfaq\b|what.s new|\bsetup\b|\brepair\b|\bmodify\b'
function Read-Apps {
    $roots = if ($StartMenu) { @($StartMenu) } else {
        @((Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'), (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))
    }
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { }
    $names = @{}
    $count = 0
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($lnk in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.lnk' -File -ErrorAction SilentlyContinue) {
            if ($lnk.FullName -match '[\\/]Startup[\\/]') { continue }
            $name = $lnk.BaseName
            if ($name -match $APP_SKIP) { continue }
            $target = ''
            if ($shell) { try { $target = $shell.CreateShortcut($lnk.FullName).TargetPath } catch { } }
            if ($target -match '\.(chm|txt|pdf|html?|url|ini|rtf|md)$') { continue }
            # shortcuts of games already found (their folder or their name)
            if ($gameNames[(Get-NameKey $name)]) { continue }
            if ($target -and ($gameDirs | Where-Object { $_ -and $target.StartsWith($_.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) })) { continue }
            $key = Get-NameKey $name
            if (-not $key -or $names[$key]) { continue }
            $names[$key] = $true
            $rel = $lnk.FullName.Substring($root.Length).TrimStart('\', '/')
            Add-Item 'app' 'Apps' $rel $name ('"{0}"' -f $lnk.FullName) '' '' $(if ($target -and (Test-Path -LiteralPath $target)) { $target } else { $lnk.FullName })
            $count++
        }
    }
    # Store apps (Calculator, Photos, ...): AppID Package!App
    foreach ($a in Get-StartEntries) {
        if ("$($a.AppID)" -notmatch '!') { continue }
        if ($a.Name -match $APP_SKIP) { continue }
        $key = Get-NameKey $a.Name
        if (-not $key -or $names[$key] -or $gameNames[$key]) { continue }
        $names[$key] = $true
        Add-Item 'app' 'Apps' $a.AppID $a.Name ('explorer.exe "shell:AppsFolder\{0}"' -f $a.AppID) '' '' "shell:AppsFolder\$($a.AppID)"
        $count++
    }
    return "$count found"
}

# --- Icons -------------------------------------------------------------------------
# The shell's own icon of a program, a shortcut or a Store app, as a 256 px
# PNG with transparency (IShellItemImageFactory).

$script:iconsReady = $false
function Initialize-Icons {
    if ($script:iconsReady) { return $true }
    try {
        Add-Type -AssemblyName System.Drawing
        Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class RaintileShellIcon
{
    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellItemImageFactory { [PreserveSig] int GetImage(SIZE size, int flags, out IntPtr bitmap); }

    [StructLayout(LayoutKind.Sequential)]
    struct SIZE { public int cx; public int cy; }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void SHCreateItemFromParsingName(string path, IntPtr bindContext,
        [MarshalAs(UnmanagedType.LPStruct)] Guid riid, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory item);

    [DllImport("gdi32.dll")]
    static extern bool DeleteObject(IntPtr handle);

    public static bool Save(string parsingName, string png, int size)
    {
        IShellItemImageFactory factory;
        SHCreateItemFromParsingName(parsingName, IntPtr.Zero, typeof(IShellItemImageFactory).GUID, out factory);
        SIZE s; s.cx = size; s.cy = size;
        IntPtr hbm;
        if (factory.GetImage(s, 0x4 /* SIIGBF_ICONONLY */, out hbm) != 0) return false;
        try
        {
            // FromHbitmap drops the alpha channel: the pixels are read again as
            // premultiplied ARGB, which is what the shell returns
            using (Bitmap raw = Image.FromHbitmap(hbm))
            {
                Rectangle r = new Rectangle(0, 0, raw.Width, raw.Height);
                BitmapData data = raw.LockBits(r, ImageLockMode.ReadOnly, raw.PixelFormat);
                try
                {
                    using (Bitmap view = new Bitmap(data.Width, data.Height, data.Stride, PixelFormat.Format32bppPArgb, data.Scan0))
                    using (Bitmap copy = new Bitmap(view))
                    {
                        copy.Save(png, ImageFormat.Png);
                    }
                }
                finally { raw.UnlockBits(data); }
            }
            return true;
        }
        finally { DeleteObject(hbm); }
    }
}
'@
        $script:iconsReady = $true
    } catch { }
    return $script:iconsReady
}

function Get-Hash([string]$text) {
    $md5 = [Security.Cryptography.MD5]::Create()
    return (($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($text.ToLowerInvariant())) | ForEach-Object { $_.ToString('x2') }) -join '')
}

# Icon of every item without images (kept between scans)
function Save-Icons {
    if (-not (Initialize-Icons)) { return }
    New-Item -ItemType Directory -Force -Path $iconDir | Out-Null
    $wanted = @{}
    foreach ($it in $items) {
        if ($it.Logo -or -not $it.IconSource) { continue }
        $png = Join-Path $iconDir ((Get-Hash $it.IconSource) + '.png')
        $wanted[$png.ToLowerInvariant()] = $true
        if (-not (Test-Path -LiteralPath $png)) {
            try { [void][RaintileShellIcon]::Save($it.IconSource, $png, 256) } catch { }
        }
        if (Test-Path -LiteralPath $png) { $it.Icon = $png }
    }
    Get-ChildItem -LiteralPath $iconDir -Filter '*.png' -File | Where-Object { -not $wanted.ContainsKey($_.FullName.ToLowerInvariant()) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# --- Tiles already in the launcher -------------------------------------------------

# Names (keys) and commands (lower case) of the tiles of every category
function Get-ExistingTiles {
    $names = @{}; $commands = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $Data 'Categories') -Filter '*.ini' -File -ErrorAction SilentlyContinue)) {
        $section = $null
        foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
            $t = $line.Trim()
            if ($t -match '^\[(.+)\]$') {
                $section = $Matches[1].Trim()
                if ($section -ine 'Category') { $names[(Get-NameKey $section)] = $true }
            } elseif ($section -and $t -match '^(?i)command\s*=\s*(.+)$') {
                $commands[$Matches[1].Trim().ToLowerInvariant()] = $true
            }
        }
    }
    return @{ Names = $names; Commands = $commands }
}

function Test-Present($item, $existing) {
    return $existing.Commands.ContainsKey($item.Command.ToLowerInvariant()) -or $existing.Names.ContainsKey((Get-NameKey $item.Name))
}

function Read-Seen {
    $seen = @{}
    if (Test-Path -LiteralPath $seenFile) { foreach ($l in [IO.File]::ReadAllLines($seenFile)) { if ($l) { $seen[$l] = $true } } }
    return $seen
}

# --- SteamGridDB (used by the Options window when adding) ---------------------------

function Invoke-SGDB([string]$key, [string]$path) {
    $r = Invoke-RestMethod -Uri ("https://www.steamgriddb.com/api/v2/" + $path) -Headers @{ Authorization = "Bearer $key" } -TimeoutSec 15
    if ($r.success) { return $r.data }
    return $null
}

# Downloads a hero ('heroes') or logo ('logos') to <destBase>.<ext>; returns
# the file, or $null
function Get-SGDBImage([string]$key, [string]$kind, [string]$name, [string]$steamAppId, [string]$destBase) {
    if (-not $key) { return $null }
    if ($steamAppId) { $id = (Invoke-SGDB $key "games/steam/$steamAppId").id }
    else { $id = (Invoke-SGDB $key ("search/autocomplete/" + [uri]::EscapeDataString($name)) | Select-Object -First 1).id }
    if (-not $id) { return $null }
    $img = Invoke-SGDB $key "$kind/game/$id" | Select-Object -First 1
    if (-not $img -or "$($img.url)" -notlike 'https://*') { return $null }
    $ext = [IO.Path]::GetExtension(([uri]$img.url).AbsolutePath).ToLowerInvariant()
    if ($imageExts -notcontains $ext) { $ext = '.png' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destBase) | Out-Null
    Invoke-WebRequest -Uri $img.url -OutFile "$destBase$ext" -UseBasicParsing -TimeoutSec 30
    return "$destBase$ext"
}

if ($NoRun) { return }

# --- Scan ------------------------------------------------------------------------------

try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { }
$enabled = @{}
foreach ($s in $Stores.Split('|')) { if ($s.Trim()) { $enabled[($s.Trim() -replace '\.', '').ToLowerInvariant()] = $true } }

$summary = @()
# games first: the apps leave out their shortcuts
foreach ($store in 'Steam', 'Epic', 'GOG', 'Ubisoft', 'Battlenet', 'EA', 'Xbox', 'Apps') {
    if (-not $enabled[$store.ToLowerInvariant()]) { continue }
    try { $summary += "${store}: " + (& "Read-$store") }
    catch { $summary += "${store}: error ($($_.Exception.Message))" }
}
Save-Icons

$existing = Get-ExistingTiles
$seen = Read-Seen
$new = 0
foreach ($it in $items) {
    $it.New = -not (Test-Present $it $existing) -and -not $seen.ContainsKey($it.Id)
    if ($it.New) { $new++ }
}

New-Item -ItemType Directory -Force -Path $generated | Out-Null
$list = @($items | Sort-Object Kind, Name | Select-Object Id, Kind, Store, Name, Command, Hero, Logo, Icon, SteamAppId, New)
$json = ConvertTo-Json -InputObject @{ Scanned = (Get-Date).ToString('s'); Items = $list } -Depth 4
$tmp = "$foundFile.tmp"
[IO.File]::WriteAllText($tmp, $json, $utf8)
Move-Item -LiteralPath $tmp -Destination $foundFile -Force

foreach ($s in $summary) { Write-Output $s }
Write-Output "$($items.Count) found, $new new"
# last line, read by the skin
Write-Output "RESULT:NEW=$new"
