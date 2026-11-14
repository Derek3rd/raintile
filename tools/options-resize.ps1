# How long the Options window (RaintileOptions.exe) stays busy while it is resized:
# on every page (or the ones named with -Page), the window is narrowed and widened
# again a few pixels at a time, and each step is timed until the window answers
# again. A size taken from the layout that changes what decides the layout (a
# scrollbar that shows, narrows the page, hides, widens it...) makes the window
# loop for a second or more at some widths: this finds it. Run by hand after a
# change that sizes things from the layout (docs/OptionsUI.md, "Sizes taken from the
# layout"); it takes a few minutes, so tools/check.py does not. The windows are not
# on screen and never take the focus (as in tools\options-shots.ps1).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\options-resize.ps1 -Base origin/nightly
#   ... -Page Found      only the entries named (Found,General: several)
#
# The programs are built from their sources (this checkout, and with -Base that
# ref), and run on the same frozen data as tools\options-shots.ps1 (its inputs\
# folder, copied at its first run). Output: the slowest steps of each page, and the
# pages whose slowest step is over -Limit ms, for which the tool exits with 1.
param(
    [string]$Base = '',     # git ref to time as well, for comparison
    [string]$Out = '',
    [int]$Wide = 1460,      # the window narrows from this width ...
    [int]$Narrow = 1000,    # ... to this one, and widens again
    [int]$Step = 8,         # pixels per step
    [int]$Height = 960,
    [int]$Limit = 200,      # ms: a step slower than this fails the run
    [string[]]$Page = @()   # entries of the menu; empty: every page
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Out) { $Out = Join-Path $repo 'build\options-resize' }
$inputs = Join-Path $repo 'build\options-shots\inputs'
$NewInputs = $false
. (Join-Path $PSScriptRoot 'options-ui-common.ps1')

$pageNames = @($Page | ForEach-Object { $_ -split ',' } | ForEach-Object { Get-PageName $_ } | Where-Object { $_ } | Select-Object -Unique)
if ($Page.Count -gt 0 -and $pageNames.Count -eq 0) { throw ('-Page: no name of an entry in "' + ($Page -join ',') + '"') }
if ($Narrow -ge $Wide -or $Step -lt 1) { throw '-Narrow must be less than -Wide, and -Step at least 1' }
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'the .NET SDK (dotnet) is needed: the programs are built from their sources'
}
New-Item -ItemType Directory -Force $Out | Out-Null
[void](Initialize-Inputs)

# The window narrowed and widened once; values: the slowest step (ms) and its width.
# A step: the window moved (WM_SIZE is handled before MoveWindow returns), a short
# wait for the layout the dispatcher runs after it, and a message sent that the
# window can only answer when that layout is done.
function Measure-Resize([IntPtr]$hwnd) {
    $widths = @()
    for ($w = $Wide; $w -ge $Narrow; $w -= $Step) { $widths += $w }
    for ($w = $Narrow + $Step; $w -le $Wide; $w += $Step) { $widths += $w }
    $r = [IntPtr]::Zero
    $sw = New-Object System.Diagnostics.Stopwatch
    $worst = 0; $at = 0
    foreach ($w in $widths) {
        $sw.Restart()
        [void][OptionsWin32]::MoveWindow($hwnd, 0, 0, $w, $Height, $true)
        Start-Sleep -Milliseconds 15
        # WM_NULL, SMTO_NORMAL, 30 s
        if ([OptionsWin32]::SendMessageTimeout($hwnd, 0, [IntPtr]::Zero, [IntPtr]::Zero, 0, 30000, [ref]$r) -eq [IntPtr]::Zero) {
            throw "the window did not answer within 30 s at width $w"
        }
        $ms = $sw.ElapsedMilliseconds - 15
        if ($ms -gt $worst) { $worst = $ms; $at = $w }
    }
    [void][OptionsWin32]::MoveWindow($hwnd, 0, 0, $Wide, $Height, $true)
    return @($worst, $at)
}

# Every page of one program: name -> @(slowest ms, width)
function Measure-Program([string]$exe, [string]$resources) {
    $res = [ordered]@{}
    $o = Start-OptionsWindow $exe $resources $Wide $Height
    try {
        for ($i = 0; ; $i++) {
            if ($i -ge 200) { throw 'more than 200 entries in the menu: the walk does not end' }
            $item = Get-MenuEntry $o.Win $i
            if (-not $item) { break }
            if (-not $item.Current.IsEnabled) { continue }   # a mode not in use
            $label = Get-MenuLabel $item
            if ($pageNames.Count -gt 0 -and $pageNames -notcontains (Get-PageName $label)) { continue }
            Show-MenuEntry $o.Win $i $label
            $name = '{0:00}-{1}' -f $i, ($label -replace '[^A-Za-z0-9]', '')
            $res[$name] = Measure-Resize $o.Hwnd
        }
    }
    finally { Stop-Process -Id $o.Process.Id -Force -ErrorAction SilentlyContinue }
    if ($res.Count -eq 0) { throw ('no page measured' + $(if ($pageNames.Count -gt 0) { ': no entry ' + ($pageNames -join ', ') + ' in the menu' } else { '' })) }
    return $res
}

Write-Output 'This checkout...'
$cur = Measure-Program (Build-Program $repo (Join-Path $Out 'current-bin')) (New-Stage $repo)
$baseRes = $null
if ($Base) {
    Write-Output "$Base..."
    [void](Invoke-Git rev-parse --verify --quiet ($Base + '^{commit}'))
    $tree = New-BaseTree $Base
    try { $baseRes = Measure-Program (Build-Program $tree (Join-Path $Out 'base-bin')) (New-Stage $tree) }
    finally { Remove-BaseTree $tree }
}

$report = New-Object System.Collections.Generic.List[string]
$report.Add(('Slowest resize step per page, ms (width {0} to {1} and back, {2} px a step; limit {3} ms)' -f $Wide, $Narrow, $Step, $Limit))
if ($Base) { $report.Add(('  {0,-30} {1,16} {2,16}' -f 'page', 'this checkout', $Base)) }
$slow = 0
foreach ($k in $cur.Keys) {
    $c = $cur[$k]
    $line = '  {0,-30} {1,7} at {2,5}' -f $k, $c[0], $c[1]
    if ($baseRes -and $baseRes.Contains($k)) { $line += ('   {0,7} at {1,5}' -f $baseRes[$k][0], $baseRes[$k][1]) }
    if ($c[0] -gt $Limit) { $line += '   SLOW'; $slow++ }
    $report.Add($line)
}
[System.IO.File]::WriteAllLines((Join-Path $Out 'report.txt'), $report)
$report
if ($slow -gt 0) {
    Write-Output ('{0} page(s) over {1} ms: see docs/OptionsUI.md, "Sizes taken from the layout".' -f $slow, $Limit)
    exit 1
}
