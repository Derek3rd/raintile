# Screenshots of every page of the Options window (RaintileOptions.exe), or of the
# ones named with -Page, and, with -Base, of the same pages at another git ref, compared pixel by
# pixel: a check by eye of what a change does to the layout. It opens the windows
# and takes a few minutes, so it is run by hand when the window changed, never by
# tools/check.py; with -Base it stops at once when nothing of the window changed.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\options-shots.ps1 -Base origin/nightly
#   ... -Base HEAD     while working on a change: against its last commit
#   ... -Page General  only the entries of the menu named (General,Tiles: several)
#
# -Page names the entries as the report does (General, Playtimeandupdates): spaces,
# case, the number before and the screen after do not matter, so a file name of the
# report works too. Only those entries are reached and shot, at both refs, and only
# they are compared. Their shots are a content of their own in the cache: a page
# reached on its own may look different from the same page reached after the others
# (Found marks the games found as seen, and the dot of the menu goes), so they never
# mix with the shots of every page, and a later run without -Page shoots every page.
# A name that is no entry of the menu (at both refs) stops the run; an entry greyed
# out (a mode not in use) is said in the report, not shot.
#
# Shots are kept: build\options-shots\cache\<key>\ (git-ignored) holds the shots of
# one content of the window's sources (src\Options, @Resources, Raintile.ini) with
# the inputs below, and the same content is never shot twice. A ref already shot
# (the nightly branch, the last commit, a branch merged as it was) costs nothing; only
# what changed is built and shot. The last 12 contents are kept. Shots taken by an
# older version of this script, which reached the pages otherwise, are not reused
# ($shotsVersion below): the first run after such a change shoots both refs again.
#
# The inputs are frozen in inputs\ at the first run: a copy of the data folder and of
# @Resources\Generated (the games found), so that shots taken days apart differ only
# by the code. -NewInputs takes a new copy (after the data changed): what was
# shot with the old one is shot again.
#
# Output: diff\ (the current shot dimmed, the changed pixels red) and report.txt.
# Shots are named after the entry of the menu and its place there (05-Search.png,
# 20-Games-tile-1.png) but compared by page: an entry added to the menu or removed
# moves the number of every later one, so the two refs are paired without it. A new
# page is then the only one at one ref, the others are still compared, and a page
# shot whole at one ref and scrolled at the other is compared by its first screen.
# The programs are built from their sources, never taken from @Resources\Bin (it may
# be older than the sources, or locked by an open Options window). Each window runs
# from stage\, a copy of the skin always at the same place (the folders shown on Info
# are the same for every ref), with a fresh copy of the data and the skin name
# RaintileShots, so nothing is saved and no bang reaches the skin.
# Pages are reached with UI Automation: every entry of the menu, every screen of a
# page scrolled, and on a category page also its first tile. Dialogs are not shot.
# The menu is walked to its end: an entry out of its view is scrolled into it first,
# as a click would need. Before a page is shot, the title over it must be the name of
# the entry selected (and the first tile of a category selected, before its shots):
# a selection that did not take is tried again, and after 3 tries the run stops, so
# the shots of another page never go into the cache as this one's.
param(
    [string]$Base = '',     # git ref to compare with; empty: only the shots of this checkout
    [string]$Out = '',
    [int]$Width = 1280,
    [int]$Height = 1000,
    [switch]$Force,         # with -Base: compare even when the window did not change
    [switch]$NewInputs,     # a new copy of the data folder and of Generated
    [string[]]$Page = @()   # entries of the menu to shoot; empty: every page
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Out) { $Out = Join-Path $repo 'build\options-shots' }
$cache = Join-Path $Out 'cache'
$inputs = Join-Path $Out 'inputs'
. (Join-Path $PSScriptRoot 'options-ui-common.ps1')
$windowFiles = @('src/Options', '@Resources/Scripts/Options.xaml')
# Part of every key: raised when this script shoots the same content otherwise (other
# entries reached, a page shown another way), so that shots cached before are not
# compared with the new ones. 2: the entries out of the menu's view reached too.
$shotsVersion = 2

# a list given through -File arrives as one string: General,Tiles
$pageNames = @($Page | ForEach-Object { $_ -split ',' } | ForEach-Object { Get-PageName $_ } | Where-Object { $_ } | Select-Object -Unique)
[Array]::Sort($pageNames, [StringComparer]::Ordinal)
if ($Page.Count -gt 0 -and $pageNames.Count -eq 0) { throw ('-Page: no name of an entry in "' + ($Page -join ',') + '"') }

if ($Base) {
    [void](Invoke-Git rev-parse --verify --quiet ($Base + '^{commit}'))
    # the working tree against the ref: committed and uncommitted changes ('--'
    # quoted: PowerShell drops it bare)
    $changed = @(Invoke-Git diff --name-only $Base '--' @windowFiles | Where-Object { $_ })
    if ($changed.Count -eq 0 -and -not $Force) {
        Write-Output "The Options window has not changed since ${Base}: nothing to compare."
        exit 0
    }
}

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class ShotsWin32 {
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
public static class ShotsDiff {
    // Pixels whose colour moved by more than 24 on a channel: count, bounding box
    // (x0, y0, x1, y1) and the number of rows they are on; with any, a picture of
    // them (red on the dimmed new shot). Sizes that differ: count -1.
    public static int[] Compare(string a, string b, string diffPng) {
        using (var x = new Bitmap(a)) using (var y = new Bitmap(b)) {
            if (x.Width != y.Width || x.Height != y.Height) return new[] { -1, 0, 0, 0, 0, 0 };
            int w = x.Width, h = x.Height;
            byte[] pa = Bytes(x), pb = Bytes(y);
            byte[] po = new byte[pb.Length];
            bool[] rows = new bool[h];
            int n = 0, x0 = w, y0 = h, x1 = -1, y1 = -1;
            for (int i = 0; i < pa.Length; i += 4) {
                bool d = Math.Abs(pa[i] - pb[i]) > 24 || Math.Abs(pa[i + 1] - pb[i + 1]) > 24 || Math.Abs(pa[i + 2] - pb[i + 2]) > 24;
                if (d) {
                    n++;
                    int p = i / 4, px = p % w, py = p / w;
                    x0 = Math.Min(x0, px); y0 = Math.Min(y0, py); x1 = Math.Max(x1, px); y1 = Math.Max(y1, py);
                    rows[py] = true;
                    po[i] = 0; po[i + 1] = 0; po[i + 2] = 255;
                } else {
                    po[i] = (byte)(pb[i] * 45 / 100); po[i + 1] = (byte)(pb[i + 1] * 45 / 100); po[i + 2] = (byte)(pb[i + 2] * 45 / 100);
                }
                po[i + 3] = 255;
            }
            if (n > 0) {
                using (var o = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
                    var bd = o.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                    Marshal.Copy(po, 0, bd.Scan0, po.Length);
                    o.UnlockBits(bd);
                    o.Save(diffPng, ImageFormat.Png);
                }
            }
            int r = 0;
            foreach (bool on in rows) if (on) r++;
            return new[] { n, x0, y0, x1, y1, r };
        }
    }
    static byte[] Bytes(Bitmap b) {
        var bd = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var a = new byte[b.Width * b.Height * 4];
        // rows one by one: the stride may be wider than the row
        for (int r = 0; r < b.Height; r++) Marshal.Copy(IntPtr.Add(bd.Scan0, r * bd.Stride), a, r * b.Width * 4, b.Width * 4);
        b.UnlockBits(bd);
        return a;
    }
}
"@

# The key of a content of the window's sources: the blobs of its files, at a ref or
# in the working tree (hash-object normalises line ends as 'git add' would), with
# the inputs and the window size
$keyPaths = @('src/Options', '@Resources', 'Raintile.ini')
function Get-Key([string]$ref, [string]$inputsId) {
    if ($ref) {
        $lines = @(Invoke-Git -c core.quotePath=false ls-tree -r $ref '--' @keyPaths | ForEach-Object {
            $p = $_ -split "`t", 2
            ($p[0] -split ' ')[2] + ' ' + $p[1]
        })
    }
    else {
        $files = @(Invoke-Git -c core.quotePath=false ls-files --cached --others --exclude-standard '--' @keyPaths |
            Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $repo $_)) })
        # as arguments, in blocks (PowerShell 5.1 puts a BOM before what it pipes to git)
        $hashes = @()
        for ($i = 0; $i -lt $files.Count; $i += 100) {
            $hashes += @(Invoke-Git hash-object '--' @($files[$i..([Math]::Min($i + 99, $files.Count - 1))]))
        }
        if ($hashes.Count -ne $files.Count) { throw 'git hash-object: not a hash for every file' }
        $lines = @(for ($i = 0; $i -lt $files.Count; $i++) { $hashes[$i] + ' ' + $files[$i] })
    }
    [Array]::Sort($lines, [StringComparer]::Ordinal)
    $text = 'shots ' + $shotsVersion + "`n" + $inputsId + "`n" + $Width + 'x' + $Height + "`n" + ($lines -join "`n")
    # the shots of some pages: a content of their own (see -Page above)
    if ($pageNames.Count -gt 0) { $text = 'pages ' + ($pageNames -join ',') + "`n" + $text }
    $sha = New-Object System.Security.Cryptography.SHA1Managed
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))
    return ((($bytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 16))
}

function Save-Shot([IntPtr]$hwnd, [string]$file) {
    $r = New-Object ShotsWin32+RECT
    [void][ShotsWin32]::GetClientRect($hwnd, [ref]$r)
    $bmp = New-Object System.Drawing.Bitmap(($r.R - $r.L), ($r.B - $r.T))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $dc = $g.GetHdc()
    # PW_RENDERFULLCONTENT (also when covered) + PW_CLIENTONLY: without the title bar,
    # drawn differently when the window is not active
    [void][ShotsWin32]::PrintWindow($hwnd, $dc, 3)
    $g.ReleaseHdc($dc)
    $g.Dispose()
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

# The tiles of the category page on screen (the strip right of the menu)
function Get-TileStrip($win) {
    return @(Get-ListItems $win | Where-Object { $_.Current.BoundingRectangle.X -gt 300 -and $_.Current.BoundingRectangle.Width -lt 200 })
}

# Selects the first tile of the category on screen (after All tiles), checked as the
# entries of the menu are
function Show-FirstTile($win, [string]$label) {
    for ($try = 0; $try -lt 3; $try++) {
        Select-Item (Get-TileStrip $win)[1]
        $strip = Get-TileStrip $win
        if ($strip.Count -gt 1 -and $strip[1].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected) { return }
    }
    throw "the first tile of ${label}: not selected after 3 tries"
}

# The page on screen and the rest of it scrolled, one shot per screen
function Save-Page($win, [IntPtr]$hwnd, [string]$dir, [string]$name) {
    $scroll = @($win.FindAll($Scope::Descendants, (New-Condition $UA::IsScrollPatternAvailableProperty $true)) |
        Where-Object { $_.Current.BoundingRectangle.X -gt 200 -and $_.Current.BoundingRectangle.Height -gt 400 } |
        ForEach-Object { $_.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern) } |
        Where-Object { $_.Current.VerticallyScrollable } | Select-Object -First 1)
    if ($scroll.Count -eq 0) { Save-Shot $hwnd (Join-Path $dir "$name.png"); return }
    $sp = $scroll[0]
    $sp.SetScrollPercent(-1, 0)
    Start-Sleep -Milliseconds 400
    for ($n = 0; $n -lt 10; $n++) {
        Save-Shot $hwnd (Join-Path $dir ('{0}-{1}.png' -f $name, $n))
        $before = $sp.Current.VerticalScrollPercent
        if ($before -ge 99.9) { break }
        $sp.ScrollVertical([System.Windows.Automation.ScrollAmount]::LargeIncrement)
        Start-Sleep -Milliseconds 400
        if ($sp.Current.VerticalScrollPercent -le $before) { break }
    }
    $sp.SetScrollPercent(-1, 0)
}

# Opens one window (the program 'exe') and shoots every page (with -Page, the
# entries named) into 'dir'; menu.txt there lists every entry, ' greyed' after those
# that cannot be selected
function Save-Window([string]$exe, [string]$resources, [string]$dir) {
    New-Item -ItemType Directory -Force $dir | Out-Null
    $o = Start-OptionsWindow $exe $resources $Width $Height
    try {
        $win = $o.Win
        $hwnd = $o.Hwnd
        $entries = New-Object System.Collections.Generic.List[string]
        for ($i = 0; ; $i++) {
            if ($i -ge 200) { throw 'more than 200 entries in the menu: the walk does not end' }
            # the entries are found again: building a page may rebuild the menu
            $item = Get-MenuEntry $win $i
            if (-not $item) { break }
            $label = Get-MenuLabel $item
            $name = '{0:00}-{1}' -f $i, ($label -replace '[^A-Za-z0-9]', '')
            # a page of a mode not in use (Page.When) is greyed out: it cannot be selected
            $enabled = $item.Current.IsEnabled
            if ($enabled) { $entries.Add($name) } else { $entries.Add("$name greyed") }
            if (-not $enabled) { continue }
            if ($pageNames.Count -gt 0 -and $pageNames -notcontains (Get-PageName $label)) { continue }
            Show-MenuEntry $win $i $label
            Save-Page $win $hwnd $dir $name
            # a category page: also its first tile (after All tiles)
            if ((Get-TileStrip $win).Count -gt 1) {
                Show-FirstTile $win $label
                Save-Page $win $hwnd $dir "$name-tile"
            }
        }
        [System.IO.File]::WriteAllLines((Join-Path $dir 'menu.txt'), $entries)
        Write-Output ('  {0}: {1} shots' -f $dir.Substring($Out.Length + 1), @(Get-ChildItem $dir -Filter *.png).Count)
    }
    finally { Stop-Process -Id $o.Process.Id -Force -ErrorAction SilentlyContinue }
}

# The shots of one content by the page they show, as the comparison pairs them: the
# file name without the number of the menu entry (an entry added or removed moves
# the number of every later one; one greyed out keeps its number), with screen 0 for
# a page shot whole (it may scroll at the other ref). Two entries with the same name (two categories
# called alike) are told apart by their order in the menu. Values: the file and the
# number of its entry.
function Get-ShotsByPage([string]$dir) {
    $shots = @(Get-ChildItem -LiteralPath $dir -Filter *.png | ForEach-Object {
            $m = [regex]::Match($_.Name, '^(\d+)-([A-Za-z0-9]*)(-tile)?(?:-(\d+))?\.png$')
            if (-not $m.Success) { throw ('a shot not named as Save-Window names them: ' + $_.FullName) }
            $screen = $m.Groups[4].Value
            if (-not $screen) { $screen = '0' }
            New-Object PSObject -Property @{ File = $_.Name; Index = [int]$m.Groups[1].Value; Label = $m.Groups[2].Value; Rest = $m.Groups[3].Value + '-' + $screen }
        })
    $byPage = @{}
    foreach ($s in $shots) {
        $pageKey = $s.Label
        $before = @($shots | Where-Object { $_.Label -eq $s.Label -and $_.Index -lt $s.Index } | ForEach-Object { $_.Index } | Sort-Object -Unique).Count
        if ($before -gt 0) { $pageKey += '~' + ($before + 1) }
        $pageKey += $s.Rest + '.png'
        if ($byPage.ContainsKey($pageKey)) { throw ('two shots of the same page in ' + $dir + ': ' + $byPage[$pageKey].File + ', ' + $s.File) }
        $byPage[$pageKey] = $s
    }
    return $byPage
}

function Test-Cached([string]$key) { return (Test-Path -LiteralPath (Join-Path (Join-Path $cache $key) 'done.txt')) }

# The shots of a source tree into the cache, unless that content was shot already
function Save-Tree([string]$label, [string]$tree, [string]$key) {
    $dir = Join-Path $cache $key
    if (Test-Cached $key) {
        (Get-Item -LiteralPath $dir).LastWriteTime = Get-Date   # recently used: kept by the pruning
        Write-Output "  ${label}: from the cache ($key)"
        return
    }
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }   # left by a run that was stopped
    Save-Window (Build-Program $tree (Join-Path $Out "$label-bin")) (New-Stage $tree) $dir
    $what = $label
    if ($pageNames.Count -gt 0) { $what += ', pages ' + ($pageNames -join ',') }
    [System.IO.File]::WriteAllText((Join-Path $dir 'done.txt'), $what)
}

# With -Page: what became of a name in the shots of 'key', as a phrase of the report;
# empty when it was shot. Shots of every page made before menu.txt never get here.
function Get-PageState([string]$key, [string]$page) {
    $menuFile = Join-Path (Join-Path $cache $key) 'menu.txt'
    $entries = @([System.IO.File]::ReadAllLines($menuFile) | Where-Object { (Get-PageName ($_ -replace ' greyed$', '')) -eq $page })
    if ($entries.Count -eq 0) { return 'not in the menu' }
    if (@($entries | Where-Object { $_ -notmatch ' greyed$' }).Count -eq 0) { return 'greyed out (a mode not in use), not shot' }
    return ''
}

# With -Page: a name that is no entry of the menu at any ref shot stops the run, with
# the entries there are (of this checkout)
function Assert-Pages([string[]]$keys) {
    $unknown = @($pageNames | Where-Object {
            $n = $_
            @($keys | Where-Object { (Get-PageState $_ $n) -ne 'not in the menu' }).Count -eq 0
        })
    if ($unknown.Count -eq 0) { return }
    $known = @([System.IO.File]::ReadAllLines((Join-Path (Join-Path $cache $keys[0]) 'menu.txt')) |
        ForEach-Object { ($_ -replace ' greyed$', '') -replace '^\d+-', '' })
    throw ('-Page: no entry ' + ($unknown -join ', ') + ' in the menu. The entries: ' + ($known -join ', '))
}

# current\ and base\ were the shots before the cache
foreach ($d in @('diff', 'stage', 'current-bin', 'base-bin', 'current', 'base')) {
    $p = Join-Path $Out $d
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
}
New-Item -ItemType Directory -Force $cache | Out-Null
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'the .NET SDK (dotnet) is needed: the programs are built from their sources'
}
$inputsId = Initialize-Inputs

if ($pageNames.Count -gt 0) { Write-Output ('Pages: ' + ($pageNames -join ', ')) }
Write-Output 'This checkout...'
$curKey = Get-Key '' $inputsId
Save-Tree 'current' $repo $curKey
if ($pageNames.Count -gt 0 -and -not $Base) { Assert-Pages @($curKey) }

if ($Base) {
    Write-Output "$Base..."
    $baseKey = Get-Key $Base $inputsId
    if (Test-Cached $baseKey) { Save-Tree 'base' '' $baseKey }
    else {
        $tree = New-BaseTree $Base
        try { Save-Tree 'base' $tree $baseKey }
        finally { Remove-BaseTree $tree }
    }
    # a page only in one of them (added or removed) is compared as such
    if ($pageNames.Count -gt 0) { Assert-Pages @($curKey, $baseKey) }

    $report = New-Object System.Collections.Generic.List[string]
    $report.Add("Options window: this checkout ($curKey) against $Base ($baseKey)")
    if ($pageNames.Count -gt 0) { $report.Add('Only the pages ' + ($pageNames -join ', ')) }
    $report.Add('(changed pixels, area x0,y0-x1,y1; changes on 2 rows or fewer, the edges of a scrolled view, count as the same)')
    $report.Add('')
    foreach ($n in $pageNames) {
        foreach ($side in @(@($curKey, 'this checkout'), @($baseKey, $Base))) {
            $state = Get-PageState $side[0] $n
            if ($state) { $report.Add(('  {0,-34} {1} in {2}' -f $n, $state, $side[1])) }
        }
    }
    $a = Join-Path $cache $baseKey
    $b = Join-Path $cache $curKey
    $diffDir = Join-Path $Out 'diff'
    New-Item -ItemType Directory -Force $diffDir | Out-Null
    # paired by page, not by file name (see Get-ShotsByPage); in the order of the menu
    # of this checkout, a page only at the other ref at its place there
    $pa = Get-ShotsByPage $a
    $pb = Get-ShotsByPage $b
    $pages = @(@($pa.Keys) + @($pb.Keys) | Sort-Object -Unique |
        Sort-Object { if ($pb.ContainsKey($_)) { $pb[$_].Index } else { $pa[$_].Index } }, { $_ })
    $same = 0
    $moved = 0
    foreach ($pageKey in $pages) {
        if (-not $pa.ContainsKey($pageKey)) { $report.Add(('  {0,-34} only in this checkout' -f $pb[$pageKey].File)); continue }
        if (-not $pb.ContainsKey($pageKey)) { $report.Add(('  {0,-34} only in {1}' -f $pa[$pageKey].File, $Base)); continue }
        $fa = $pa[$pageKey].File
        $f = $pb[$pageKey].File
        # the name at the other ref, when it is another one
        $was = ''
        if ($fa -cne $f) { $was = "  ($fa in $Base)" }
        if ($pa[$pageKey].Index -ne $pb[$pageKey].Index) { $moved++ }
        $r = [ShotsDiff]::Compare((Join-Path $a $fa), (Join-Path $b $f), (Join-Path $diffDir $f))
        if ($r[0] -lt 0) { $report.Add(('  {0,-34} another size' -f $f) + $was) }
        # on 2 rows at most: a border cut at the edge of a scrolled view, drawn a
        # pixel apart from one run to the next
        elseif ($r[0] -eq 0 -or $r[5] -le 2) { $same++ }
        else { $report.Add(('  {0,-34} {1,7} px  {2},{3}-{4},{5}' -f $f, $r[0], $r[1], $r[2], $r[3], $r[4]) + $was) }
    }
    $report.Add(('  {0} of {1} the same' -f $same, $pages.Count))
    # an entry added or removed before them: the menu drawn on the left of the shots
    # differs too, so even a page that did not change is listed
    if ($moved -gt 0) { $report.Add(('  The menu differs from the one of {0}: {1} shots compared with the same page at another place there, and the menu on the left of the shots differs as well' -f $Base, $moved)) }
    [System.IO.File]::WriteAllLines((Join-Path $Out 'report.txt'), $report)
    $report
    Write-Output ''
    Write-Output ('Pictures of the changes: ' + $diffDir)
    Write-Output ('Shots: ' + $b + ' (this checkout), ' + $a + " ($Base)")
}
else {
    foreach ($n in $pageNames) {
        $state = Get-PageState $curKey $n
        if ($state) { Write-Output "  ${n}: $state" }
    }
    Write-Output ('Shots: ' + (Join-Path $cache $curKey))
}

# the 12 contents used last are kept
Get-ChildItem -LiteralPath $cache -Directory | Sort-Object LastWriteTime -Descending | Select-Object -Skip 12 |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
