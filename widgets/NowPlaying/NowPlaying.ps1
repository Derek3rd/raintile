# Now Playing widget for Raintile: what any player is playing (Spotify, a
# browser with YouTube, the Media Player, VLC...), as Windows shows it over
# the volume: its cover, the controls and the time.
#
# The players give it to Windows' media controls (System Media Transport
# Controls); Windows gives it to other programs through
# Windows.Media.Control (Windows 10 1809 and later), read here from
# PowerShell 5.1 with no plugin. The session shown is the one Windows calls
# current (the player used last).
#
# Started by the widget's OnShow and running only while it is on screen: it
# reads the session every -Interval ms and, only when something changed,
# sends it to the widget's meters with WM_COPYDATA (as "Rainmeter.exe !bang"
# does, without a process each time). The widget's clicks reach it through
# -Cmd, an .ini the meters write with !WriteKeyValue ([Cmd] Do=<command>),
# which it waits on:
#   playpause, next, previous, shuffle (on / off), repeat (off, all, one)
#   seek <p>      to <p> % of the song (0-100; the bar's $MouseX:%$)
#   step <s>      <s> seconds on (negative: back)
#   quit          exits (the widget's OnHide)
# It exits too when another copy started for the same tile (Owner= in
# -Cmd), when Rainmeter is gone or when the launcher shows no widget (-Flag).
#
# The cover (the session's thumbnail) is saved once per song into covers\ of
# the widget's folder, where the last few are kept.

param(
    [string]$Config = 'Raintile',
    [string]$Section = '',
    [string]$Cmd = '',
    [int]$Interval = 500,
    [string]$Flag = '',
    [string]$Text = '240,240,245,255',
    [string]$Accent = '0,210,180,255'
)

$ErrorActionPreference = 'Stop'

# --- Helpers (pure: tested in tests/ps/NowPlaying.Tests.ps1) -------------------

# Text for a meter's option inside a quoted bang argument: no quotes, no
# brackets (section variables) and no # (variables), on one line, not too long
function Get-SafeText([string]$Value) {
    if ($null -eq $Value) { return '' }
    $v = $Value -replace '[\r\n\t]', ' '
    $v = $v.Replace('"', "'").Replace('[', '(').Replace(']', ')').Replace('#', '')
    $v = $v.Trim()
    if ($v.Length -gt 200) { $v = $v.Substring(0, 200) }
    return $v
}

# The name of the player from its app id: "Spotify.exe" -> Spotify,
# "Chrome" -> Chrome, "Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic"
# -> ZuneMusic
function Get-AppName([string]$Id) {
    if (-not $Id) { return '' }
    $n = $Id
    if ($n.Contains('!')) { $n = $n.Substring(0, $n.IndexOf('!')) }
    if ($n.Contains('_')) { $n = $n.Substring(0, $n.IndexOf('_')) }
    $n = $n -replace '\.exe$', ''
    if ($n.Contains('.')) { $n = $n.Substring($n.LastIndexOf('.') + 1) }
    if ($n.Length -gt 0) { $n = $n.Substring(0, 1).ToUpperInvariant() + $n.Substring(1) }
    return $n
}

# A command of the widget: @{ Verb; Value }, or $null
function ConvertFrom-PlayingCommand([string]$Line) {
    if ($null -eq $Line) { return $null }
    $parts = @($Line.Trim() -split '\s+')
    $verb = $parts[0].ToLowerInvariant()
    if (@('playpause', 'next', 'previous', 'shuffle', 'repeat', 'quit', 'show') -contains $verb) { return @{ Verb = $verb; Value = 0.0 } }
    if (($verb -eq 'seek' -or $verb -eq 'step') -and $parts.Count -ge 2) {
        $v = 0.0
        if (-not [double]::TryParse($parts[1], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $null }
        if ($verb -eq 'seek') { $v = [Math]::Max(0.0, [Math]::Min(100.0, $v)) }
        return @{ Verb = $verb; Value = $v }
    }
    return $null
}

# The position (seconds) a seek or a step goes to, in the song; -1: none
function Get-SeekTarget($Command, [double]$Position, [double]$Duration) {
    if ($Duration -le 0) { return -1 }
    if ($Command.Verb -eq 'seek') { $t = $Duration * $Command.Value / 100 }
    elseif ($Command.Verb -eq 'step') { $t = $Position + $Command.Value }
    else { return -1 }
    return [Math]::Max(0.0, [Math]::Min($Duration, $t))
}

# The position now: the one Windows has, plus the time since it was written
# while playing (players write it now and then)
function Get-LivePosition([double]$Position, [double]$Duration, [double]$SinceUpdate, [bool]$Playing) {
    $p = $Position
    if ($Playing -and $SinceUpdate -gt 0) { $p += $SinceUpdate }
    if ($Duration -gt 0) { $p = [Math]::Min($p, $Duration) }
    return [Math]::Max(0.0, $p)
}

# seconds -> "3:13", "1:02:03"
function Format-Time([int]$Seconds) {
    if ($Seconds -lt 0) { $Seconds = 0 }
    $m = [Math]::Floor($Seconds / 60)
    if ($m -lt 60) { return ('{0}:{1:00}' -f $m, ($Seconds % 60)) }
    return ('{0}:{1:00}:{2:00}' -f [Math]::Floor($m / 60), ($m % 60), ($Seconds % 60))
}

# The bangs that show the song ($Song: Title, Artist, App, Playing,
# Position, Duration, Shuffle, Repeat: NONE ALL ONE, Cover, Note) in the
# widget's meters (<Prefix><Meter>), then the group updated and redrawn
function Format-PlayingBang($Song, [string]$Prefix, [string]$Group, [string]$Config, $Colors) {
    $sb = New-Object System.Text.StringBuilder
    $set = {
        param($meter, $key, $value)
        [void]$sb.Append('[!SetOption "' + $Prefix + $meter + '" "' + $key + '" "' + $value + '" "' + $Config + '"]')
    }
    $has = $Song.Title -ne ''
    $pos = [int]$Song.Position
    $dur = [int]$Song.Duration
    # (the title, the artist and the player: the cover's tooltip)
    $tip = $Song.Title
    if ($Song.Artist) { $tip += ' - ' + $Song.Artist }
    if ($Song.App) { $tip += ' (' + $Song.App + ')' }
    & $set 'Cover' 'ImageName' (Get-SafeText $Song.Cover)
    & $set 'Cover' 'ToolTipText' (Get-SafeText $tip)
    # (over the cover, with the ShowTrack setting)
    & $set 'Title' 'Text' (Get-SafeText $Song.Title)
    & $set 'Artist' 'Text' (Get-SafeText $Song.Artist)
    & $set 'NoCover' 'Hidden' $(if ($Song.Cover -ne '') { '1' } else { '0' })
    # (Segoe MDL2 Assets: Play E768, Pause E769, RepeatAll E8EE, RepeatOne
    # E8ED; shuffle and repeat lit when on)
    & $set 'PlayGlyph' 'Text' $(if ($Song.Playing) { [string][char]0xE769 } else { [string][char]0xE768 })
    & $set 'ShuffleGlyph' 'FontColor' $(if ($Song.Shuffle) { $Colors.Accent } else { $Colors.Text })
    & $set 'RepeatGlyph' 'Text' $(if ($Song.Repeat -eq 'ONE') { [string][char]0xE8ED } else { [string][char]0xE8EE })
    & $set 'RepeatGlyph' 'FontColor' $(if ($Song.Repeat -eq 'ALL' -or $Song.Repeat -eq 'ONE') { $Colors.Accent } else { $Colors.Text })
    & $set 'Pos' 'Text' $(if ($dur -gt 0) { Format-Time $pos } else { '' })
    & $set 'Dur' 'Text' $(if ($dur -gt 0) { Format-Time $dur } else { '' })
    & $set 'Progress' 'Formula' $(if ($dur -gt 0) { [Math]::Round(100.0 * [Math]::Min($pos, $dur) / $dur, 2).ToString([Globalization.CultureInfo]::InvariantCulture) } else { '0' })
    & $set 'Status' 'Text' (Get-SafeText $Song.Note)
    & $set 'Status' 'Hidden' $(if ($has) { '1' } else { '0' })
    [void]$sb.Append('[!UpdateMeasureGroup "' + $Group + '" "' + $Config + '"][!UpdateMeterGroup "' + $Group + '" "' + $Config + '"][!Redraw "' + $Config + '"]')
    return $sb.ToString()
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

namespace RaintileNowPlaying
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
}
'@

# --- Windows' media controls (WinRT, from PowerShell 5.1) --------------------------

# An asynchronous WinRT call waited for: IAsyncOperation<T> through .NET's
# AsTask (System.Runtime.WindowsRuntime); an IAsyncAction through its own
$script:asTask = $null
function Wait-WinRT($Operation, [Type]$Result) {
    if (-not $script:asTask) {
        $script:asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        } | Select-Object -First 1
    }
    $task = $script:asTask.MakeGenericMethod($Result).Invoke($null, @($Operation))
    if (-not $task.Wait(3000)) { throw 'Windows did not answer' }
    return $task.Result
}

$note = ''
$manager = $null
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager,Windows.Media.Control,ContentType=WindowsRuntime]
    $null = [Windows.Storage.Streams.IRandomAccessStreamWithContentType,Windows.Storage.Streams,ContentType=WindowsRuntime]
    $null = [Windows.Media.MediaPlaybackAutoRepeatMode,Windows.Media,ContentType=WindowsRuntime]
    $manager = Wait-WinRT ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
} catch {
    $note = 'Windows does not give what is playing here (Windows 10 1809 or later).'
}

# The thumbnail of the session, saved once per song (the last few kept): its
# path, or ''
$coverDir = $null
function Save-Cover($Properties, [string]$Key) {
    if (-not $Properties.Thumbnail) { return '' }
    $name = ([BitConverter]::ToString((New-Object Security.Cryptography.SHA1Managed).ComputeHash([Text.Encoding]::UTF8.GetBytes($Key))) -replace '-', '').Substring(0, 16)
    foreach ($ext in '.jpg', '.png') {
        $p = Join-Path $coverDir ($name + $ext)
        if (Test-Path -LiteralPath $p) { return $p }
    }
    try {
        $stream = Wait-WinRT ($Properties.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
        $ext = $(if ($stream.ContentType -match 'png') { '.png' } else { '.jpg' })
        if (-not (Test-Path -LiteralPath $coverDir)) { New-Item -ItemType Directory -Path $coverDir | Out-Null }
        $path = Join-Path $coverDir ($name + $ext)
        $part = "$path.tmp"
        $in = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
        $out = [IO.File]::Create($part)
        try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
        Move-Item -LiteralPath $part -Destination $path -Force
        Get-ChildItem -LiteralPath $coverDir -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -Skip 5 | Remove-Item -Force
        return $path
    } catch { return '' }
}

# --- The widget ------------------------------------------------------------------

# Prefix of the widget's sections in the launcher (CW11_Server: CW11_) and
# the group of its measures and meters (CW11)
$prefix = $Section -replace 'Server$', ''
$group = $prefix.TrimEnd('_')
$utf8 = New-Object System.Text.UTF8Encoding $false

# This copy owns the tile: an older one still running exits when it reads it
$cmdDir = Split-Path -Parent $Cmd
$coverDir = Join-Path $cmdDir 'covers'
$tmp = "$Cmd.tmp"
[IO.File]::WriteAllText($tmp, "[Cmd]`r`nOwner=$PID`r`nDo=`r`n", $utf8)
if (Test-Path -LiteralPath $Cmd) { Remove-Item -LiteralPath $Cmd -Force }
Move-Item -LiteralPath $tmp -Destination $Cmd
$cmdStamp = (Get-Item -LiteralPath $Cmd).LastWriteTimeUtc

# The current session and its song; the properties (title, cover) read again
# every other round, the time at each
$session = $null
$song = @{ Title = ''; Artist = ''; App = ''; Playing = $false; Position = 0; Duration = 0; Shuffle = $false; Repeat = 'NONE'; Cover = ''; Note = $note }
$colors = @{ Text = $Text; Accent = $Accent }
$key = $null
$cover = ''
$round = 0
function Read-Session {
    $script:session = $null
    if (-not $manager) { return }
    $s = $manager.GetCurrentSession()
    if (-not $s) {
        $script:song = @{ Title = ''; Artist = ''; App = ''; Playing = $false; Position = 0; Duration = 0; Shuffle = $false; Repeat = 'NONE'; Cover = ''; Note = 'Nothing is playing.' }
        return
    }
    $script:session = $s
    $info = $s.GetPlaybackInfo()
    $playing = [string]$info.PlaybackStatus -eq 'Playing'
    $tl = $s.GetTimelineProperties()
    $dur = ($tl.EndTime - $tl.StartTime).TotalSeconds
    $since = ([DateTimeOffset]::Now - $tl.LastUpdatedTime).TotalSeconds
    $pos = Get-LivePosition ($tl.Position - $tl.StartTime).TotalSeconds $dur $since $playing
    if ($script:round % 2 -eq 0 -or -not $script:song.Title) {
        $p = Wait-WinRT ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
        $k = $s.SourceAppUserModelId + '|' + $p.Title + '|' + $p.Artist + '|' + $p.AlbumTitle
        # (a browser gives the thumbnail a moment after the title: asked
        # again while the song has none)
        if ($k -ne $script:key -or -not $script:cover) { $script:key = $k; $script:cover = Save-Cover $p $k }
        $script:song.Title = [string]$p.Title
        $script:song.Artist = $(if ($p.Artist) { [string]$p.Artist } else { [string]$p.AlbumArtist })
    }
    $script:round++
    $script:song.App = Get-AppName $s.SourceAppUserModelId
    $script:song.Playing = $playing
    # (players that do not say: off)
    $script:song.Shuffle = $info.IsShuffleActive -eq $true
    $script:song.Repeat = $(switch ([string]$info.AutoRepeatMode) { 'List' { 'ALL' } 'Track' { 'ONE' } default { 'NONE' } })
    $script:song.Position = $pos
    $script:song.Duration = $dur
    $script:song.Cover = $(if ($script:song.Title) { $script:cover } else { '' })
    $script:song.Note = 'Nothing is playing.'
}

function Invoke-PlayingCommand($c) {
    $s = $script:session
    if (-not $s) { return }
    switch ($c.Verb) {
        'playpause' { [void](Wait-WinRT ($s.TryTogglePlayPauseAsync()) ([bool])) }
        'next' { [void](Wait-WinRT ($s.TrySkipNextAsync()) ([bool])) }
        'previous' { [void](Wait-WinRT ($s.TrySkipPreviousAsync()) ([bool])) }
        'shuffle' { [void](Wait-WinRT ($s.TryChangeShuffleActiveAsync(-not $script:song.Shuffle)) ([bool])) }
        'repeat' {
            # off -> all -> one -> off, as the players do
            $next = $(switch ($script:song.Repeat) { 'NONE' { 'List' } 'ALL' { 'Track' } default { 'None' } })
            [void](Wait-WinRT ($s.TryChangeAutoRepeatModeAsync([Windows.Media.MediaPlaybackAutoRepeatMode]$next)) ([bool]))
        }
        default {
            $t = Get-SeekTarget $c $script:song.Position $script:song.Duration
            if ($t -ge 0) {
                $start = $s.GetTimelineProperties().StartTime
                [void](Wait-WinRT ($s.TryChangePlaybackPositionAsync(($start + [TimeSpan]::FromSeconds($t)).Ticks)) ([bool]))
            }
        }
    }
}

$watcher = New-Object IO.FileSystemWatcher $cmdDir, (Split-Path -Leaf $Cmd)
$watcher.NotifyFilter = [IO.NotifyFilters]'LastWrite, Size, FileName'
$last = $null
$wait = 0
while ($true) {
    if ($wait -gt 0) { [void]$watcher.WaitForChanged([IO.WatcherChangeTypes]::All, $wait) }
    $wait = [Math]::Max(200, $Interval)
    if (-not [RaintileNowPlaying.Rainmeter]::Running()) { exit 0 }
    if ($Flag -and -not (Test-Path -LiteralPath $Flag)) { exit 0 }
    # a command: the file is newer (also checked without an event)
    if (Test-Path -LiteralPath $Cmd) {
        $stamp = (Get-Item -LiteralPath $Cmd).LastWriteTimeUtc
        if ($stamp -ne $cmdStamp) {
            $cmdStamp = $stamp
            $file = Read-CommandFile $Cmd
            if ($file.Owner -and $file.Owner -ne [string]$PID) { exit 0 }
            $c = ConvertFrom-PlayingCommand $file.Do
            if ($c -and $c.Verb -eq 'quit') { exit 0 }
            if ($c -and $c.Verb -ne 'show') {
                try { Invoke-PlayingCommand $c } catch { }   # (the player went meanwhile)
                $round = 0   # (the new song read at once)
            }
        }
    }
    try { Read-Session } catch { $session = $null }
    $bang = Format-PlayingBang $song $prefix $group $Config $colors
    if ($bang -ne $last) {
        $last = $bang
        if (-not [RaintileNowPlaying.Rainmeter]::Send($bang)) { exit 0 }
    }
}
