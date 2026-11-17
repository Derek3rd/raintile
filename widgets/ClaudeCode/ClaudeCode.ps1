# Claude Code widget for Raintile: the Claude Code sessions open on this PC,
# the ones that wait for you first, and the use of the plan's limits.
#
# The sessions: Claude Code keeps one file per running session in
# sessions\ of its folder (%USERPROFILE%\.claude, or CLAUDE_CONFIG_DIR):
# its process, folder, name and status (busy: working; waiting: it asks
# something, e.g. a permission; idle: done, your turn). They are read only;
# a file whose process is gone is left out.
#
# The limits (5 hours, week): Claude Code gives them only to its status
# line; StatusLine.ps1, set as that line, keeps them in limits.txt of the
# widget's folder. Without it the tile has a row that opens StatusLine.txt,
# which says how (with this PC's path).
#
# A click on a session brings the window it runs in to the front (its
# terminal, or the Claude app): the row's command writes "focus <pid>" into
# -Cmd. Claude Code has no link that opens a given session.
#
# Started by the widget's OnShow and running only while it is on screen: it
# waits on the sessions folder (and reads again every -Interval ms, for the
# times shown), writes the rows into -List and the limits into the meters
# (WM_COPYDATA, as "Rainmeter.exe !bang" does), only when they changed. It
# exits on "quit" in -Cmd (the widget's OnHide), when another copy started
# for the same tile (Owner= in -Cmd), when Rainmeter is gone or when the
# launcher shows no widget (-Flag).

param(
    [string]$Config = 'Raintile',
    [string]$Section = '',
    [string]$Cmd = '',
    [string]$List = '',
    [string]$Flag = '',
    [string]$Folder = '',
    [int]$ShowUsage = 1,
    [int]$Interval = 5000,
    [string]$Accent = '0,210,180,255',
    [string]$Warn = '255,166,0,255'
)

$ErrorActionPreference = 'Stop'

# --- Helpers (pure: tested in tests/ps/ClaudeCode.Tests.ps1) ---------------------

# Claude Code's folder: the setting, CLAUDE_CONFIG_DIR, or .claude of the
# user's folder
function Get-ClaudeFolder([string]$Setting, [string]$ConfigDir, [string]$UserProfile) {
    if ($Setting.Trim()) { return $Setting.Trim().TrimEnd('\') }
    if ($ConfigDir.Trim()) { return $ConfigDir.Trim().TrimEnd('\') }
    return $UserProfile.TrimEnd('\') + '\.claude'
}

# Text of a row's field: one line, no '|' (the list's separator), not too long
function Get-FieldText([string]$Value) {
    if ($null -eq $Value) { return '' }
    $v = ($Value -replace '[\r\n\t|]', ' ').Trim()
    if ($v.Length -gt 120) { $v = $v.Substring(0, 120) }
    return $v
}

# How long ago, from milliseconds: "now", "4 min", "2 h", "3 d"
function Get-AgeText([double]$Ms) {
    $s = [Math]::Max(0, [Math]::Floor($Ms / 1000))
    if ($s -lt 60) { return 'now' }
    if ($s -lt 3600) { return ('{0} min' -f [Math]::Floor($s / 60)) }
    if ($s -lt 86400) { return ('{0} h' -f [Math]::Floor($s / 3600)) }
    return ('{0} d' -f [Math]::Floor($s / 86400))
}

# A session file (its JSON, read) as a row: @{ Rank; When; Title; Sub; Icon;
# Command } (Rank: 0 waiting, 1 idle, 2 busy, 3 other; Command: the bang
# that asks this script, through the command file $Cmd, to bring its
# window to the front), or $null for one not shown (a spare process Claude
# Code keeps ready, not a session yet)
function Get-SessionView($Session, [double]$NowMs, [string]$IconDir, [string]$Cmd) {
    if ($null -eq $Session -or $Session.spare) { return $null }
    $title = [string]$Session.name
    if (-not $title.Trim() -and $Session.cwd) { $title = Split-Path -Leaf ([string]$Session.cwd) }
    if (-not $title.Trim()) { $title = 'Claude Code' }
    $when = 0.0
    foreach ($k in 'statusUpdatedAt', 'updatedAt', 'startedAt') {
        if ($when -le 0 -and $Session.$k) { [void][double]::TryParse([string]$Session.$k, [ref]$when) }
    }
    $age = $(if ($when -gt 0) { ', ' + (Get-AgeText ($NowMs - $when)) } else { '' })
    switch ([string]$Session.status) {
        'waiting' {
            $what = Get-FieldText ([string]$Session.waitingFor)
            $state = $(if ($what) { 'Needs you: ' + $what } else { 'Needs you' })
            $rank = 0; $icon = 'needs.png'
        }
        'idle' { $state = 'Your turn'; $rank = 1; $icon = 'turn.png' }
        'busy' { $state = 'Working'; $rank = 2; $icon = 'working.png' }
        default { $state = 'Open'; $rank = 3; $icon = '' }
    }
    $id = 0
    $command = ''
    if ($Cmd -and [int]::TryParse([string]$Session.pid, [ref]$id) -and $id -gt 0) {
        $command = '[!WriteKeyValue Cmd Do "focus ' + $id + '" "' + $Cmd + '"]'
    }
    return @{
        Rank = $rank; When = $when; Title = Get-FieldText $title; Sub = $state + $age
        Icon = $(if ($icon) { $IconDir.TrimEnd('\') + '\' + $icon } else { '' }); Command = $command
    }
}

# The rows of the list: the ones that wait for you first, then the newest
function Format-SessionList($Views) {
    $lines = @()
    foreach ($v in @($Views | Where-Object { $_ } | Sort-Object @{ Expression = { $_.Rank } }, @{ Expression = { $_.When }; Descending = $true })) {
        $lines += ($v.Title + '|' + $v.Sub + '|' + $v.Icon + '|' + $v.Command)
    }
    return $lines
}

# Key=value lines (limits.txt) -> hashtable; '' -> empty
function Read-KeyValues([string]$Text) {
    $r = @{}
    if (-not $Text) { return $r }
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*([A-Za-z]+)\s*=\s*(.*?)\s*$') { $r[$Matches[1]] = $Matches[2] }
    }
    return $r
}

# A limit to show: @{ Pct (0-100, 0 once it has reset); Text: "42%, resets 14:30"
# (another day: "Mon 14:30") }, or $null without one. Times in this PC's zone.
function Get-LimitView($Values, [string]$Key, [long]$NowSec, [TimeZoneInfo]$Zone) {
    $pct = 0.0
    if (-not $Values.ContainsKey($Key) -or -not [double]::TryParse([string]$Values[$Key], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$pct)) { return $null }
    $pct = [Math]::Max(0.0, [Math]::Min(100.0, $pct))
    $resets = [long]0
    [void][long]::TryParse([string]$Values[$Key + 'Resets'], [ref]$resets)
    if ($resets -gt 0 -and $resets -le $NowSec) { return @{ Pct = 0.0; Text = '0%' } }
    $text = ('{0:0}%' -f $pct)
    if ($resets -gt 0) {
        $at = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::FromUnixTimeSeconds($resets), $Zone)
        $now = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::FromUnixTimeSeconds($NowSec), $Zone)
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $time = $(if ($at.Date -eq $now.Date) { $at.ToString('HH:mm', $inv) } else { $at.ToString('ddd HH:mm', $inv) })
        $text += ', resets ' + $time
    }
    return @{ Pct = $pct; Text = $text }
}

# The bangs that show the limits in the widget's meters (<Prefix><Meter>),
# then the group updated and redrawn. Without them: a note (why) instead.
# $Age: how old they are, after the first line's name ("5 hours, 40 min
# ago"): Claude Code gives them only while it runs in a terminal (the
# Claude app runs no status line), and the use elsewhere is not in them.
function Format-UsageBang($Five, $Week, [string]$Note, [string]$Age, [string]$Prefix, [string]$Group, [string]$Config, $Colors) {
    $sb = New-Object System.Text.StringBuilder
    $set = {
        param($name, $key, $value)
        [void]$sb.Append('[!SetOption "' + $Prefix + $name + '" "' + $key + '" "' + $value + '" "' + $Config + '"]')
    }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    & $set 'FiveLabel' 'Text' $(if ($Age -and ($Five -or $Week)) { '5 hours, ' + $Age + ' ago' } else { '5 hours' })
    foreach ($row in @(@('Five', $Five), @('Week', $Week))) {
        $v = $row[1]
        # (without them, the note on the first line: why)
        $none = $(if ($row[0] -eq 'Five' -and $Note) { $Note } else { '-' })
        & $set ($row[0] + 'Value') 'Text' $(if ($v) { $v.Text } else { $none })
        & $set ($row[0] + 'Pct') 'Formula' $(if ($v) { $v.Pct.ToString('0.##', $inv) } else { '0' })
        & $set ($row[0] + 'Bar') 'BarColor' $(if ($v -and $v.Pct -ge 90) { $Colors.Warn } else { $Colors.Accent })
    }
    [void]$sb.Append('[!UpdateMeasureGroup "' + $Group + '" "' + $Config + '"][!UpdateMeterGroup "' + $Group + '" "' + $Config + '"][!Redraw "' + $Config + '"]')
    return $sb.ToString()
}

# StatusLine.txt: how to set StatusLine.ps1 as Claude Code's status line,
# with its path on this PC (written into JSON: backslashes doubled)
function Get-StatusLineHelp([string]$Script, [string]$ClaudeFolder) {
    $json = $Script.Replace('\', '\\')
    return @(
        "Raintile's Claude Code widget: the usage limits",
        '',
        'Claude Code tells how much of your plan''s limits you used (5 hours, week)',
        'only to its status line. To show them on the tile, make the widget''s',
        'StatusLine.ps1 Claude Code''s status line: open',
        '',
        "    $ClaudeFolder\settings.json",
        '',
        'and add this inside its outer { } (a comma after the entry before it):',
        '',
        '    "statusLine": {',
        '      "type": "command",',
        "      `"command`": `"powershell -NoProfile -ExecutionPolicy Bypass -File \`"$json\`"`"",
        '    }',
        '',
        'It takes the place of a status line you already have. The line then shows',
        'the model and the two limits, and the tile shows them after Claude Code''s',
        'next answer. Claude Code reports the limits with a Claude plan (Pro, Max),',
        'not with an API key.'
    ) -join "`r`n"
}

# A command of the widget: @{ Verb; Pid }, or $null (show, quit, focus <pid>)
function ConvertFrom-ClaudeCommand([string]$Line) {
    if ($null -eq $Line) { return $null }
    $t = $Line.Trim()
    if ($t -eq 'show' -or $t -eq 'quit') { return @{ Verb = $t; Pid = 0 } }
    if ($t -match '^focus\s+(\d{1,9})$') { return @{ Verb = 'focus'; Pid = [int]$Matches[1] } }
    return $null
}

# [Cmd] of the command file: @{ Owner; Do } (missing keys: '')
function Read-CommandFile([string]$Path) {
    $r = @{ Owner = ''; Do = '' }
    $text = $null
    for ($try = 0; $try -lt 5 -and $null -eq $text; $try++) {
        try { $text = [IO.File]::ReadAllText($Path) }
        catch [IO.FileNotFoundException] { return $r }
        catch { Start-Sleep -Milliseconds 20 }   # (Rainmeter writing it)
    }
    if ($null -eq $text) { return $r }
    $in = $false
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^\s*\[([^\]]+)\]') { $in = $Matches[1].Trim() -eq 'Cmd'; continue }
        if ($in -and $line -match '^\s*(Owner|Do)\s*=(.*)$') { $r[$Matches[1]] = $Matches[2].Trim() }
    }
    return $r
}

# --- Rainmeter --------------------------------------------------------------------

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace RaintileClaudeCode
{
    public static class Rainmeter
    {
        [StructLayout(LayoutKind.Sequential)]
        struct CopyData { public IntPtr Data; public int Size; public IntPtr Pointer; }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string className, string windowName);
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wParam, ref CopyData data);

        // Bangs to Rainmeter; false when it is not running
        public static bool Send(string bang)
        {
            IntPtr window = FindWindow("DummyRainWClass", null);
            if (window == IntPtr.Zero) return false;
            IntPtr text = Marshal.StringToHGlobalUni(bang);
            try
            {
                var data = new CopyData { Data = (IntPtr)1, Size = (bang.Length + 1) * 2, Pointer = text };
                SendMessage(window, 0x004A /* WM_COPYDATA */, IntPtr.Zero, ref data);
            }
            finally { Marshal.FreeHGlobal(text); }
            return true;
        }

        public static bool Running() { return FindWindow("DummyRainWClass", null) != IntPtr.Zero; }
    }

    public static class Window
    {
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
        [DllImport("user32.dll")] static extern void keybd_event(byte key, byte scan, int flags, IntPtr extra);

        // To the front, restored if minimised. Windows lets only the program
        // in front give the focus away: an Alt press and release first (no
        // menu opens) lifts that, as tools that switch windows do.
        public static void Front(IntPtr window)
        {
            if (window == IntPtr.Zero) return;
            if (IsIconic(window)) ShowWindow(window, 9 /* SW_RESTORE */);
            keybd_event(0x12 /* VK_MENU */, 0, 0, IntPtr.Zero);
            keybd_event(0x12, 0, 2 /* KEYEVENTF_KEYUP */, IntPtr.Zero);
            SetForegroundWindow(window);
        }
    }
}
'@

# --- The widget ------------------------------------------------------------------

$prefix = $Section -replace 'Server$', ''
$group = $prefix.TrimEnd('_')
$utf8 = New-Object System.Text.UTF8Encoding $false
$dir = Split-Path -Parent $Cmd
$claude = Get-ClaudeFolder $Folder ([string]$env:CLAUDE_CONFIG_DIR) ([string]$env:USERPROFILE)
$sessions = Join-Path $claude 'sessions'
$limitsFile = Join-Path $dir 'limits.txt'
$helpFile = Join-Path $dir 'StatusLine.txt'
$colors = @{ Accent = $Accent; Warn = $Warn }

function Write-Whole([string]$Path, [string]$Text) {
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, $Text, $utf8)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# This copy owns the tile: an older one still running exits when it reads it
Write-Whole $Cmd "[Cmd]`r`nOwner=$PID`r`nDo=`r`n"
$cmdStamp = (Get-Item -LiteralPath $Cmd).LastWriteTimeUtc

# (the help, with this PC's paths, written when it differs)
$help = Get-StatusLineHelp (Join-Path $dir 'StatusLine.ps1') $claude
$oldHelp = $null
if (Test-Path -LiteralPath $helpFile) { $oldHelp = [IO.File]::ReadAllText($helpFile) }
if ($help -ne $oldHelp) { Write-Whole $helpFile $help }

# A session's process still running: the same process, not a later one with
# its id (started before the session)
function Test-SessionAlive($Session) {
    $id = 0
    if (-not [int]::TryParse([string]$Session.pid, [ref]$id) -or $id -le 0) { return $false }
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    $started = 0.0
    if (-not [double]::TryParse([string]$Session.startedAt, [ref]$started)) { return $true }
    try { $procMs = ([DateTimeOffset]$p.StartTime).ToUnixTimeMilliseconds() } catch { return $true }   # (another user's: no time)
    return $procMs -le ($started + 5000)
}

function Get-Rows {
    $now = [double][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $views = @()
    if (Test-Path -LiteralPath $sessions) {
        foreach ($f in Get-ChildItem -LiteralPath $sessions -Filter '*.json' -File) {
            try { $s = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { continue }   # (being written)
            if (-not (Test-SessionAlive $s)) { continue }
            $views += Get-SessionView $s $now $dir $Cmd
        }
    }
    $rows = @()
    if ($ShowUsage -eq 1 -and -not (Test-Path -LiteralPath $limitsFile)) {
        $rows += ('Usage limits: set up|Click: how, in Notepad||"' + $helpFile + '"')
    }
    $sessionRows = @(Format-SessionList $views)
    if ($sessionRows.Count -eq 0) {
        $rows += $(if (Test-Path -LiteralPath $claude) { 'No session open|Claude Code is not running||' } else { 'Claude Code not found|No ' + (Get-FieldText $claude) + '||' })
    }
    return ($rows + $sessionRows) -join "`r`n"
}

# The window a session runs in: the first of its process and the ones that
# started it with a window of their own (the terminal, the Claude app); a
# process of the Claude app without one (its windows are its main
# process's): a window of a process of the same name
function Invoke-Focus([int]$Id) {
    for ($k = 0; $k -lt 8 -and $Id -gt 0; $k++) {
        $p = Get-Process -Id $Id -ErrorAction SilentlyContinue
        if (-not $p -or $p.ProcessName -eq 'explorer') { return }   # (the desktop's: not the session's)
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [RaintileClaudeCode.Window]::Front($p.MainWindowHandle); return }
        if ($k -gt 0 -and $p.ProcessName -eq 'claude') {
            $main = Get-Process -Name $p.ProcessName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
            if ($main) { [RaintileClaudeCode.Window]::Front($main.MainWindowHandle); return }
        }
        $w = Get-CimInstance Win32_Process -Filter "ProcessId=$Id" -ErrorAction SilentlyContinue
        if (-not $w) { return }
        $Id = [int]$w.ParentProcessId
    }
}

function Get-UsageBang {
    $values = @{}
    $age = ''
    $nowSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (Test-Path -LiteralPath $limitsFile) {
        $values = Read-KeyValues ([IO.File]::ReadAllText($limitsFile))
        $updated = [long]0
        if (-not [long]::TryParse([string]$values['Updated'], [ref]$updated) -or $updated -le 0) {
            $updated = ([DateTimeOffset](Get-Item -LiteralPath $limitsFile).LastWriteTimeUtc).ToUnixTimeSeconds()
        }
        # (just given: no age)
        if ($nowSec - $updated -ge 120) { $age = Get-AgeText (1000.0 * ($nowSec - $updated)) }
    }
    $five = Get-LimitView $values 'FiveHour' $nowSec ([TimeZoneInfo]::Local)
    $week = Get-LimitView $values 'Week' $nowSec ([TimeZoneInfo]::Local)
    $note = $(if ($five -or $week) { '' } elseif (Test-Path -LiteralPath $limitsFile) { 'none reported' } else { 'not set up' })
    return Format-UsageBang $five $week $note $age $prefix $group $Config $colors
}

$watcher = $null
$lastRows = $null
$lastUsage = $null
if (Test-Path -LiteralPath $List) { $lastRows = [IO.File]::ReadAllText($List) }
while ($true) {
    if (-not [RaintileClaudeCode.Rainmeter]::Running()) { exit 0 }
    if ($Flag -and -not (Test-Path -LiteralPath $Flag)) { exit 0 }
    if (Test-Path -LiteralPath $Cmd) {
        $stamp = (Get-Item -LiteralPath $Cmd).LastWriteTimeUtc
        if ($stamp -ne $cmdStamp) {
            $cmdStamp = $stamp
            $file = Read-CommandFile $Cmd
            if ($file.Owner -and $file.Owner -ne [string]$PID) { exit 0 }
            $c = ConvertFrom-ClaudeCommand $file.Do
            if ($c -and $c.Verb -eq 'quit') { exit 0 }
            if ($c -and $c.Verb -eq 'focus') { try { Invoke-Focus $c.Pid } catch { } }   # (the session ended meanwhile)
        }
    }
    $rows = Get-Rows
    if ($rows -ne $lastRows) {
        $lastRows = $rows
        Write-Whole $List $rows
        if (-not [RaintileClaudeCode.Rainmeter]::Send('[!CommandMeasure "MeasureScript" "WidgetChanged()" "' + $Config + '"]')) { exit 0 }
    }
    if ($ShowUsage -eq 1) {
        $usage = Get-UsageBang
        if ($usage -ne $lastUsage) {
            $lastUsage = $usage
            if (-not [RaintileClaudeCode.Rainmeter]::Send($usage)) { exit 0 }
        }
    }
    # (wakes on a session's change, a command, or after -Interval for the times)
    if (-not $watcher -and (Test-Path -LiteralPath $sessions)) {
        $watcher = New-Object IO.FileSystemWatcher $sessions, '*.json'
        $watcher.NotifyFilter = [IO.NotifyFilters]'LastWrite, Size, FileName'
    }
    $until = [DateTime]::UtcNow.AddMilliseconds([Math]::Max(1000, $Interval))
    while ([DateTime]::UtcNow -lt $until) {
        # (short waits: the command file and the flag are checked between)
        if ($watcher) { if (-not $watcher.WaitForChanged([IO.WatcherChangeTypes]::All, 500).TimedOut) { Start-Sleep -Milliseconds 150; break } }
        else { Start-Sleep -Milliseconds 500 }
        if ($Flag -and -not (Test-Path -LiteralPath $Flag)) { exit 0 }
        if ((Test-Path -LiteralPath $Cmd) -and (Get-Item -LiteralPath $Cmd).LastWriteTimeUtc -ne $cmdStamp) { break }
        if ((Test-Path -LiteralPath $limitsFile) -and $ShowUsage -eq 1 -and (Get-Item -LiteralPath $limitsFile).LastWriteTimeUtc -gt [DateTime]::UtcNow.AddSeconds(-1)) { break }
    }
}
