# What tools\options-shots.ps1 and tools\options-resize.ps1 share: the program built
# from a source tree, the skin staged for it, the frozen data, the window opened and
# the entries of its menu reached with UI Automation. Dot-sourced by them after they
# set $repo, $Out (their output folder), $inputs (the frozen data and Generated) and
# $NewInputs.

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class OptionsWin32 {
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool repaint);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    // The visible top-level windows of a process, cloaked ones included (UI
    // Automation leaves those out of the children of its root)
    public static List<IntPtr> WindowsOf(int pid) {
        var r = new List<IntPtr>();
        EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == (uint)pid && IsWindowVisible(h)) r.Add(h); return true; }, IntPtr.Zero);
        return r;
    }
}
"@
$UA = [System.Windows.Automation.AutomationElement]
$Scope = [System.Windows.Automation.TreeScope]

function New-Condition($property, $value) { return New-Object System.Windows.Automation.PropertyCondition($property, $value) }

function Invoke-Git {
    # git writes progress to stderr: in PowerShell 5.1 with 'Stop' that would be an error
    $ErrorActionPreference = 'Continue'
    $o = @(& git -C $repo @args 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { throw ('git ' + ($args -join ' ') + ': ' + ($o -join ' ')) }
    return $o
}

# An entry's name as the reports write it, lower case: what -Page is matched with
function Get-PageName([string]$s) {
    $s = $s.Trim() -replace '\.png$', '' -replace '^\d+-', '' -replace '(-tile)?(-\d+)?$', ''
    return ($s -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
}

# The frozen inputs (data folder, Generated): copied once; returns their id.
# id.txt is written last: a copy that was stopped is made again.
function Initialize-Inputs {
    $idFile = Join-Path $inputs 'id.txt'
    if (-not $NewInputs -and (Test-Path -LiteralPath $idFile)) { return ([System.IO.File]::ReadAllText($idFile)).Trim() }
    if (Test-Path -LiteralPath $inputs) { Remove-Item -LiteralPath $inputs -Recurse -Force }
    New-Item -ItemType Directory -Force $inputs | Out-Null
    $src = Join-Path $env:APPDATA 'Rainmeter\Raintile'
    # without a data folder the window uses the skin's defaults
    if (Test-Path -LiteralPath (Join-Path $src 'Settings.inc')) { Copy-Item -LiteralPath $src -Destination (Join-Path $inputs 'data') -Recurse }
    $gen = Join-Path $repo '@Resources\Generated'
    if (Test-Path -LiteralPath $gen) { Copy-Item -LiteralPath $gen -Destination (Join-Path $inputs 'Generated') -Recurse }
    $id = [guid]::NewGuid().ToString('N')
    [System.IO.File]::WriteAllText($idFile, $id)
    return $id
}

# The skin as the window sees it: Raintile.ini and @Resources of the tree, with the
# Generated of the inputs; always at the same place
function New-Stage([string]$tree) {
    $stage = Join-Path $Out 'stage'
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    $res = Join-Path $stage '@Resources'
    New-Item -ItemType Directory -Force $res | Out-Null
    Copy-Item -LiteralPath (Join-Path $tree 'Raintile.ini') -Destination $stage
    Get-ChildItem -LiteralPath (Join-Path $tree '@Resources') | Where-Object { $_.Name -ne 'Generated' -and $_.Name -ne 'Bin' } |
        Copy-Item -Destination $res -Recurse
    $gen = Join-Path $inputs 'Generated'
    if (Test-Path -LiteralPath $gen) { Copy-Item -LiteralPath $gen -Destination $res -Recurse }
    return $res
}

# The program of a source tree: built from its src\Options into 'bin'
function Build-Program([string]$tree, [string]$bin) {
    $o = & dotnet build (Join-Path $tree 'src\Options\RaintileOptions.csproj') -c Release -o $bin -nologo -v q 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("build failed in ${tree}:`n" + ($o -join "`n")) }
    return (Join-Path $bin 'RaintileOptions.exe')
}

# A ref checked out in a worktree of its own ($Out\base-src), without hooks: a
# post-checkout hook could build or write into the new tree. Remove-BaseTree after.
function New-BaseTree([string]$ref) {
    $tree = Join-Path $Out 'base-src'
    # left by a run that was stopped
    if (Test-Path -LiteralPath $tree) {
        try { [void](Invoke-Git worktree remove --force $tree) } catch { Remove-Item -LiteralPath $tree -Recurse -Force }
        [void](Invoke-Git worktree prune)
    }
    $noHooks = Join-Path $Out 'no-hooks'
    New-Item -ItemType Directory -Force $noHooks | Out-Null
    [void](Invoke-Git -c "core.hooksPath=$noHooks" worktree add --detach $tree $ref)
    return $tree
}

function Remove-BaseTree([string]$tree) { [void](Invoke-Git worktree remove --force $tree) }

# Opens the program on the staged skin, with a fresh copy of the frozen data (a page
# may mark things as seen) and the skin name RaintileShots (nothing is saved, no bang
# reaches the skin), at the given size; waits for its window. -Offscreen: the window
# is cloaked (not on screen, never under the mouse, still rendered for PrintWindow),
# without the focus or a taskbar button; a program older than the switch ignores it
# and shows its window.
# Values: Process, Win (the UI Automation element), Hwnd. The caller stops the process.
function Start-OptionsWindow([string]$exe, [string]$resources, [int]$width, [int]$height) {
    $a = @('-Resources', ('"' + $resources + '"'), '-Config', 'RaintileShots', '-Offscreen')
    $data = Join-Path $Out 'data'
    if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force }
    $frozen = Join-Path $inputs 'data'
    if (Test-Path -LiteralPath $frozen) {
        Copy-Item -LiteralPath $frozen -Destination $data -Recurse
        $a += @('-Data', ('"' + $data + '"'))
    }
    $p = Start-Process $exe -ArgumentList $a -PassThru
    $win = $null
    for ($i = 0; $i -lt 120 -and -not $win; $i++) {
        Start-Sleep -Milliseconds 500
        if ($p.HasExited) { throw "the window closed at once: see $resources\Generated\Options.log" }
        # the window with the pages (the preview is a window of its own)
        foreach ($h in [OptionsWin32]::WindowsOf($p.Id)) {
            $w = $UA::FromHandle($h)
            if ($w.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window -and
                $w.FindFirst($Scope::Descendants, (New-Condition $UA::AutomationIdProperty 'PageTitle'))) { $win = $w; break }
        }
    }
    if (-not $win) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; throw 'no window after 60 s' }
    $hwnd = [IntPtr]$win.Current.NativeWindowHandle
    $script:OptionsHwnd = $hwnd   # for Select-Item
    [void][OptionsWin32]::MoveWindow($hwnd, 0, 0, $width, $height, $true)
    Start-Sleep -Milliseconds 2500   # the first page is built after the window shows
    return New-Object PSObject -Property @{ Process = $p; Win = $win; Hwnd = $hwnd }
}

function Get-ListItems($win) {
    return @($win.FindAll($Scope::Descendants, (New-Condition $UA::ControlTypeProperty ([System.Windows.Automation.ControlType]::ListItem))))
}

# UI Automation's Select, Scroll and Realize activate the window and take the focus
# from the user: the program started with -Offscreen does them when asked with a
# message instead (WM_APP + 1: select, WM_APP + 2: scroll, WM_APP + 3: an entry of a
# list into view; Nav.cs), at the middle of the element's part inside its parent (an
# entry scrolled into view may stick out of the menu). True when it did; a program
# older than that answers nothing, and the caller uses UI Automation.
function Send-WindowAsk([int]$msg, [int]$wParam, $element) {
    $r = $element.Current.BoundingRectangle
    $parent = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($element)
    if ($parent) { $r = [System.Windows.Rect]::Intersect($r, $parent.Current.BoundingRectangle) }
    if ($r.IsEmpty) { return $false }
    $x = [int]($r.X + $r.Width / 2); $y = [int]($r.Y + $r.Height / 2)
    $answer = [IntPtr]::Zero
    $sent = [OptionsWin32]::SendMessageTimeout($script:OptionsHwnd, $msg, [IntPtr]$wParam, [IntPtr](($y -band 0xFFFF) * 65536 + ($x -band 0xFFFF)), 0, 30000, [ref]$answer)
    return ($sent -ne [IntPtr]::Zero -and $answer -eq [IntPtr]1)
}

# Selects an entry (of the menu, of the tiles), with UI Automation when the program
# could not (see Send-WindowAsk). Not checked here: selecting a category rebuilds the
# menu, and $item no longer says; the callers check the page or the tile shown.
function Select-Item($item) {
    if (-not (Send-WindowAsk 0x8001 0 $item)) { $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }
    Start-Sleep -Milliseconds 1500
}

# The menu: the lists left of the pages, in their order (Info, at the bottom, is a
# list of its own and comes first). They are virtualized: an entry scrolled out of
# the menu may not be in the tree at all, so the entries are walked with
# ItemContainerPattern, not looked for among the descendants.
# Values: Item, List (its list) and Index (its place there); $null after the last one
function Find-MenuPlace($win, [int]$n) {
    $lists = @($win.FindAll($Scope::Descendants, (New-Condition $UA::ControlTypeProperty ([System.Windows.Automation.ControlType]::List))) |
        Where-Object { $_.Current.BoundingRectangle.X -lt 200 })
    foreach ($list in $lists) {
        $ic = $list.GetCurrentPattern([System.Windows.Automation.ItemContainerPattern]::Pattern)
        $item = $ic.FindItemByProperty($null, $null, $null)
        $i = 0
        while ($item -and $n -gt 0) { $n--; $i++; $item = $ic.FindItemByProperty($item, $null, $null) }
        if ($item) { return New-Object PSObject -Property @{ Item = $item; List = $list; Index = $i } }
    }
    return $null
}

function Find-MenuEntry($win, [int]$n) {
    $place = Find-MenuPlace $win $n
    if ($place) { return $place.Item }
    return $null
}

function Test-Offscreen($item) {
    # a virtualized entry has no state to read until it is realized
    try { return $item.Current.IsOffscreen } catch { return $true }
}

# Entry n of the menu (from 0), scrolled into view first when it is out of it, as a
# click on it would need; $null after the last one
function Get-MenuEntry($win, [int]$n) {
    $place = Find-MenuPlace $win $n
    if (-not $place) { return $null }
    $item = $place.Item
    if (-not (Test-Offscreen $item)) { return $item }
    # asked to the program (Send-WindowAsk: Realize would activate the window), else
    # with UI Automation
    if (-not (Send-WindowAsk 0x8003 $place.Index $place.List)) {
        $p = $null
        if ($item.TryGetCurrentPattern([System.Windows.Automation.VirtualizedItemPattern]::Pattern, [ref]$p)) { $p.Realize() }
        elseif ($item.TryGetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern, [ref]$p)) { $p.ScrollIntoView() }
        else { throw "menu entry ${n}: out of view, and it cannot be scrolled into it" }
    }
    Start-Sleep -Milliseconds 400
    $item = Find-MenuEntry $win $n
    if (-not $item -or (Test-Offscreen $item)) { throw "menu entry ${n}: still out of view after scrolling to it" }
    return $item
}

# The text of a menu entry (its last text with a letter: the glyph comes first)
function Get-MenuLabel($item) {
    return @($item.FindAll($Scope::Descendants, (New-Condition $UA::ControlTypeProperty ([System.Windows.Automation.ControlType]::Text))) |
        ForEach-Object { $_.Current.Name } | Where-Object { $_ -match '[A-Za-z]' }) | Select-Object -Last 1
}

function Get-PageTitle($win) {
    $t = $win.FindFirst($Scope::Descendants, (New-Condition $UA::AutomationIdProperty 'PageTitle'))
    if ($t) { return $t.Current.Name }
    return '(no title found)'
}

# Selects entry n of the menu and waits for its page: the title over the page is the
# name of the entry (pages, categories and widgets alike). A selection may not take
# while the window is busy, and the page left on screen would be taken for this
# entry's: it is selected again, and a page that never shows stops the run.
function Show-MenuEntry($win, [int]$n, [string]$label) {
    $want = $label -replace '[^A-Za-z0-9]', ''
    $title = ''
    for ($try = 0; $try -lt 3; $try++) {
        # found again: building a page may rebuild the menu
        Select-Item (Get-MenuEntry $win $n)
        for ($w = 0; $w -lt 10; $w++) {
            $title = Get-PageTitle $win
            if (($title -replace '[^A-Za-z0-9]', '') -ceq $want) { return }
            Start-Sleep -Milliseconds 500
        }
    }
    throw ('menu entry {0} ({1}): the page on screen is still "{2}" after 3 tries' -f $n, $label, $title)
}
