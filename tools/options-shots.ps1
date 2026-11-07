# Screenshots of every page of the Options window (RaintileOptions.exe) and, with
# -Base, of the same pages at another git ref, compared pixel by
# pixel: a check by eye of what a change does to the layout. It opens the windows
# and takes a few minutes, so it is run by hand when the window changed, never by
# tools/check.py; with -Base it stops at once when nothing of the window changed.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\options-shots.ps1 -Base origin/nightly
#
# Output in build\options-shots\ (git-ignored): current\ and base\ (program\,
# one PNG per page and screen), diff\ (the current shot dimmed, the
# changed pixels red) and report.txt. The windows use a copy of the data folder and
# the skin name RaintileShots, so nothing is saved and no bang reaches the skin.
# Pages are reached with UI Automation: every entry of the menu, every screen of a
# page scrolled, and on a category page also its first tile. Dialogs are not shot.
param(
    [string]$Base = '',     # git ref to compare with; empty: only the shots of this checkout
    [string]$Out = '',
    [int]$Width = 1280,
    [int]$Height = 1000,
    [switch]$Force          # with -Base: compare even when the window did not change
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Out) { $Out = Join-Path $repo 'build\options-shots' }
$windowFiles = @('src/Options', '@Resources/Scripts/Options.xaml')

function Invoke-Git {
    # git writes progress to stderr: in PowerShell 5.1 with 'Stop' that would be an error
    $ErrorActionPreference = 'Continue'
    $o = @(& git -C $repo @args 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { throw ('git ' + ($args -join ' ') + ': ' + ($o -join ' ')) }
    return $o
}

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

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class ShotsWin32 {
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool repaint);
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
$UA = [System.Windows.Automation.AutomationElement]
$Scope = [System.Windows.Automation.TreeScope]

function New-Condition($property, $value) { return New-Object System.Windows.Automation.PropertyCondition($property, $value) }

function Copy-Data([string]$dest) {
    $src = Join-Path $env:APPDATA 'Rainmeter\Raintile'
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    if (-not (Test-Path -LiteralPath (Join-Path $src 'Settings.inc'))) { return '' }   # the skin's defaults
    Copy-Item -LiteralPath $src -Destination $dest -Recurse
    return $dest
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

function Get-ListItems($win) {
    return @($win.FindAll($Scope::Descendants, (New-Condition $UA::ControlTypeProperty ([System.Windows.Automation.ControlType]::ListItem))))
}

function Select-Item($item) {
    $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 1500
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

# Opens one window (the program 'exe') and shoots every page into 'dir'
function Save-Window([string]$exe, [string]$resources, [string]$dir) {
    New-Item -ItemType Directory -Force $dir | Out-Null
    $data = Copy-Data (Join-Path $Out 'data')   # a fresh copy: a page may mark things as seen
    $a = @('-Resources', ('"' + $resources + '"'), '-Config', 'RaintileShots')
    if ($data) { $a += @('-Data', ('"' + $data + '"')) }
    $p = Start-Process $exe -ArgumentList $a -PassThru
    try {
        $win = $null
        for ($i = 0; $i -lt 120 -and -not $win; $i++) {
            Start-Sleep -Milliseconds 500
            if ($p.HasExited) { throw "the window closed at once: see $resources\Generated\Options.log" }
            $w = $UA::RootElement.FindFirst($Scope::Children, (New-Condition $UA::ProcessIdProperty $p.Id))
            if ($w -and $w.Current.Name -and $w.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window) { $win = $w }
        }
        if (-not $win) { throw 'no window after 60 s' }
        $hwnd = [IntPtr]$win.Current.NativeWindowHandle
        [void][ShotsWin32]::MoveWindow($hwnd, 0, 0, $Width, $Height, $true)
        Start-Sleep -Milliseconds 2500   # the first page is built after the window shows
        $menu = @(Get-ListItems $win | Where-Object { $_.Current.BoundingRectangle.X -lt 200 })
        for ($i = 0; $i -lt $menu.Count; $i++) {
            # the entries are found again: building a page may rebuild the menu
            $item = @(Get-ListItems $win | Where-Object { $_.Current.BoundingRectangle.X -lt 200 })[$i]
            $label = @($item.FindAll($Scope::Descendants, (New-Condition $UA::ControlTypeProperty ([System.Windows.Automation.ControlType]::Text))) |
                ForEach-Object { $_.Current.Name } | Where-Object { $_ -match '[A-Za-z]' }) | Select-Object -Last 1
            $name = '{0:00}-{1}' -f $i, ($label -replace '[^A-Za-z0-9]', '')
            Select-Item $item
            Save-Page $win $hwnd $dir $name
            # a category page: also its first tile (after All tiles)
            $strip = @(Get-ListItems $win | Where-Object { $_.Current.BoundingRectangle.X -gt 300 -and $_.Current.BoundingRectangle.Width -lt 200 })
            if ($strip.Count -gt 1) {
                Select-Item $strip[1]
                Save-Page $win $hwnd $dir "$name-tile"
            }
        }
        Write-Output ('  {0}: {1} shots' -f $dir.Substring($Out.Length + 1), @(Get-ChildItem $dir -Filter *.png).Count)
    }
    finally { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
}

# The program of a source tree: built from its src\Options into 'bin'
function Build-Program([string]$tree, [string]$bin) {
    $o = & dotnet build (Join-Path $tree 'src\Options\RaintileOptions.csproj') -c Release -o $bin -nologo -v q 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("build failed in ${tree}:`n" + ($o -join "`n")) }
    return (Join-Path $bin 'RaintileOptions.exe')
}

# Shoots the window of a source tree whose @Resources (Options.xaml) and program
# are given
function Save-Tree([string]$label, [string]$exe, [string]$tree) {
    $res = Join-Path $tree '@Resources'
    if ($exe -and (Test-Path -LiteralPath $exe)) { Save-Window $exe $res (Join-Path $Out "$label\program") }
    else { Write-Output "  $label\program: no RaintileOptions.exe (no .NET SDK?), not shot" }
}

foreach ($d in @('current', 'base', 'diff', 'base-bin')) {
    $p = Join-Path $Out $d
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
}
New-Item -ItemType Directory -Force $Out | Out-Null
$hasDotnet = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)

Write-Output 'Shooting this checkout...'
$exe = Join-Path $repo '@Resources\Bin\RaintileOptions.exe'
if ($hasDotnet) {
    # rebuilds only when a source is newer than the program
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'dev-build.ps1') | Out-Null
}
Save-Tree 'current' $exe $repo

if ($Base) {
    Write-Output "Shooting $Base..."
    $tree = Join-Path $Out 'base-src'
    # left by a run that was stopped
    if (Test-Path -LiteralPath $tree) {
        try { [void](Invoke-Git worktree remove --force $tree) } catch { Remove-Item -LiteralPath $tree -Recurse -Force }
        [void](Invoke-Git worktree prune)
    }
    # no hooks: a post-checkout hook could build or write into the new tree
    $noHooks = Join-Path $Out 'no-hooks'
    New-Item -ItemType Directory -Force $noHooks | Out-Null
    [void](Invoke-Git -c "core.hooksPath=$noHooks" worktree add --detach $tree $Base)
    try {
        # what the skin found (games, icons) for the Import page, as in this checkout
        $gen = Join-Path $repo '@Resources\Generated'
        if (Test-Path -LiteralPath $gen) { Copy-Item -Path (Join-Path $gen '*') -Destination (Join-Path $tree '@Resources\Generated') -Recurse -Force }
        $baseExe = ''
        if ($hasDotnet) { $baseExe = Build-Program $tree (Join-Path $Out 'base-bin') }
        Save-Tree 'base' $baseExe $tree
    }
    finally { [void](Invoke-Git worktree remove --force $tree) }

    $report = New-Object System.Collections.Generic.List[string]
    $report.Add("Options window: this checkout against $Base (changed pixels, area x0,y0-x1,y1;")
    $report.Add('changes on 2 rows or fewer, the edges of a scrolled view, count as the same)')
    foreach ($kind in @('program')) {
        $a = Join-Path $Out "base\$kind"
        $b = Join-Path $Out "current\$kind"
        if (-not ((Test-Path -LiteralPath $a) -and (Test-Path -LiteralPath $b))) { continue }
        $diffDir = Join-Path $Out "diff\$kind"
        New-Item -ItemType Directory -Force $diffDir | Out-Null
        $report.Add('')
        $report.Add("== $kind")
        $names = @(@(Get-ChildItem $a -Filter *.png) + @(Get-ChildItem $b -Filter *.png) | ForEach-Object { $_.Name } | Sort-Object -Unique)
        $same = 0
        foreach ($f in $names) {
            $fa = Join-Path $a $f
            $fb = Join-Path $b $f
            if (-not (Test-Path -LiteralPath $fa)) { $report.Add(('  {0,-34} only in this checkout' -f $f)); continue }
            if (-not (Test-Path -LiteralPath $fb)) { $report.Add(('  {0,-34} only in {1}' -f $f, $Base)); continue }
            $r = [ShotsDiff]::Compare($fa, $fb, (Join-Path $diffDir $f))
            if ($r[0] -lt 0) { $report.Add(('  {0,-34} another size' -f $f)) }
            # on 2 rows at most: a border cut at the edge of a scrolled view, drawn a
            # pixel apart from one run to the next
            elseif ($r[0] -eq 0 -or $r[5] -le 2) { $same++ }
            else { $report.Add(('  {0,-34} {1,7} px  {2},{3}-{4},{5}' -f $f, $r[0], $r[1], $r[2], $r[3], $r[4])) }
        }
        $report.Add(('  {0} of {1} the same' -f $same, $names.Count))
    }
    [System.IO.File]::WriteAllLines((Join-Path $Out 'report.txt'), $report)
    $report
    Write-Output ''
    Write-Output ('Shots and pictures of the changes: ' + $Out)
}
else { Write-Output ('Shots: ' + (Join-Path $Out 'current')) }
