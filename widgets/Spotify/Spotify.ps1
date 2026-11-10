# Spotify widget for Raintile: the song playing in Spotify, its cover, the
# controls and the time.
#
# Spotify itself gives no data to other programs: Spicetify's WebNowPlaying
# extension (Spicetify Marketplace, or `spicetify config extensions
# webnowplaying.js`) connects from Spotify to ws://localhost:<port> (8974)
# and sends the song ("TITLE ...", "POSITION 1:02", ...), taking commands
# back ("TOGGLE_PLAYING", ...): the protocol of WebNowPlaying-Redux,
# revision 1. This script is that server, so no plugin is needed: a
# WebSocket server on 127.0.0.1 only, running from the widget's OnShow to its
# OnHide, one client at a time.
#
# While it runs it sends what changed to the widget's meters with
# WM_COPYDATA (as "Rainmeter.exe !bang" does, without a process each time).
# The widget's clicks reach it through -Cmd, an .ini the meters write with
# !WriteKeyValue ([Cmd] Do=<command>), which it waits on:
#   playpause, next, previous, like
#   seek <p>      to <p> % of the song (0-100; the bar's $MouseX:%$)
#   step <s>      <s> seconds on (negative: back)
#   quit          exits (the widget's OnHide)
# It exits too when another copy started for the same tile (Owner= in
# -Cmd), when Rainmeter is gone or when the launcher shows no widget (-Flag).
#
# The cover is downloaded once per song from Spotify's image server
# (https://i.scdn.co/image/<id> only) into covers\ of the widget's folder,
# where the last few are kept.

param(
    [string]$Config = 'Raintile',
    [string]$Section = '',
    [string]$Cmd = '',
    [int]$Port = 8974,
    [int]$Interval = 300,
    [string]$Flag = '',
    [string]$Text = '240,240,245,255',
    [string]$Accent = '0,210,180,255'
)

$ErrorActionPreference = 'Stop'

# --- Helpers (pure: tested in tests/ps/Spotify.Tests.ps1) ---------------------

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

# "3:13", "1:02:03" -> seconds; 0 when it is not a time
function ConvertTo-Seconds([string]$Time) {
    if ($Time -notmatch '^\d+(:\d{1,2}){1,2}$') { return 0 }
    $s = 0
    foreach ($p in $Time.Split(':')) { $s = $s * 60 + [int]$p }
    return $s
}

# The id of a cover from Spotify's image server, '' for any other address
function Get-CoverId([string]$Url) {
    if ($Url -match '^https://i\.scdn\.co/image/([A-Za-z0-9]{8,64})$') { return $Matches[1] }
    return ''
}

# A command of the widget: @{ Verb; Value }, or $null
function ConvertFrom-SpotifyCommand([string]$Line) {
    if ($null -eq $Line) { return $null }
    $parts = @($Line.Trim() -split '\s+')
    $verb = $parts[0].ToLowerInvariant()
    if (@('playpause', 'next', 'previous', 'like', 'quit', 'show') -contains $verb) { return @{ Verb = $verb; Value = 0.0 } }
    if (($verb -eq 'seek' -or $verb -eq 'step') -and $parts.Count -ge 2) {
        $v = 0.0
        if (-not [double]::TryParse($parts[1], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $null }
        if ($verb -eq 'seek') { $v = [Math]::Max(0.0, [Math]::Min(100.0, $v)) }
        return @{ Verb = $verb; Value = $v }
    }
    return $null
}

# What to send to Spotify for a command, given the song (its position and
# duration in seconds): the WebNowPlaying-Redux message, or $null
function Get-SpotifyMessage($Command, [int]$Position, [int]$Duration) {
    switch ($Command.Verb) {
        'playpause' { return 'TOGGLE_PLAYING' }
        'next' { return 'NEXT' }
        'previous' { return 'PREVIOUS' }
        'like' { return 'TOGGLE_THUMBS_UP' }
        default {
            if ($Duration -le 0) { return $null }
            if ($Command.Verb -eq 'seek') { $f = $Command.Value / 100 }
            else { $f = ($Position + $Command.Value) / $Duration }
            $f = [Math]::Max(0.0, [Math]::Min(1.0, $f))
            # "SET_POSITION <seconds>:<fraction>" (Spicetify seeks to the fraction)
            return 'SET_POSITION ' + [int][Math]::Round($f * $Duration) + ':' + $f.ToString('0.#####', [Globalization.CultureInfo]::InvariantCulture)
        }
    }
}

# The bangs that show the song ($Song: Title, Artist, State, Position,
# Duration, Liked, Cover, Note) in the widget's meters (<Prefix><Meter>), then
# the group updated and redrawn
function Format-SpotifyBang($Song, [string]$Prefix, [string]$Group, [string]$Config, $Colors) {
    $sb = New-Object System.Text.StringBuilder
    $set = {
        param($meter, $key, $value)
        [void]$sb.Append('[!SetOption "' + $Prefix + $meter + '" "' + $key + '" "' + $value + '" "' + $Config + '"]')
    }
    $has = $Song.Title -ne ''
    $pos = [int]$Song.Position
    $dur = [int]$Song.Duration
    & $set 'Title' 'Text' (Get-SafeText $Song.Title)
    & $set 'Artist' 'Text' (Get-SafeText $Song.Artist)
    & $set 'Cover' 'ImageName' (Get-SafeText $Song.Cover)
    & $set 'NoCover' 'Hidden' $(if ($Song.Cover -ne '') { '1' } else { '0' })
    # (Segoe MDL2 Assets: Play E768, Pause E769, Heart E006, HeartFill E00B)
    & $set 'PlayGlyph' 'Text' $(if ($Song.State -eq 'PLAYING') { [string][char]0xE769 } else { [string][char]0xE768 })
    & $set 'LikeGlyph' 'Text' $(if ($Song.Liked) { [string][char]0xE00B } else { [string][char]0xE006 })
    & $set 'LikeGlyph' 'FontColor' $(if ($Song.Liked) { $Colors.Accent } else { $Colors.Text })
    & $set 'Pos' 'Text' (Format-Time $pos)
    & $set 'Dur' 'Text' (Format-Time $dur)
    & $set 'Progress' 'Formula' $(if ($dur -gt 0) { [string][Math]::Round(100.0 * [Math]::Min($pos, $dur) / $dur, 2).ToString([Globalization.CultureInfo]::InvariantCulture) } else { '0' })
    & $set 'Status' 'Text' (Get-SafeText $Song.Note)
    & $set 'Status' 'Hidden' $(if ($has) { '1' } else { '0' })
    [void]$sb.Append('[!UpdateMeasureGroup "' + $Group + '" "' + $Config + '"][!UpdateMeterGroup "' + $Group + '" "' + $Config + '"][!Redraw "' + $Config + '"]')
    return $sb.ToString()
}

# seconds -> "3:13", "1:02:03"
function Format-Time([int]$Seconds) {
    if ($Seconds -lt 0) { $Seconds = 0 }
    $m = [Math]::Floor($Seconds / 60)
    if ($m -lt 60) { return ('{0}:{1:00}' -f $m, ($Seconds % 60)) }
    return ('{0}:{1:00}:{2:00}' -f [Math]::Floor($m / 60), ($m % 60), ($Seconds % 60))
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

# --- The WebSocket server -------------------------------------------------------

# (in $source: tests/ps/Spotify.Tests.ps1 compiles it without running the script)
$source = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace RaintileSpotify
{
    // A WebSocket server for one client at a time (RFC 6455: the handshake,
    // text frames, ping, close), on 127.0.0.1. What the client sends is kept
    // as "KEY value" pairs (WebNowPlaying-Redux revision 1); Version grows at
    // each change, so the reader knows when to look again.
    public class Link
    {
        readonly TcpListener listener;
        readonly object gate = new object();
        readonly Dictionary<string, string> state = new Dictionary<string, string>();
        TcpClient client;
        Stream stream;
        public int Version;
        public bool Connected;
        public string Error = "";

        public Link(int port)
        {
            listener = new TcpListener(IPAddress.Loopback, port);
            listener.Start();
            var t = new Thread(AcceptLoop) { IsBackground = true };
            t.Start();
        }

        public Dictionary<string, string> Snapshot()
        {
            lock (gate) return new Dictionary<string, string>(state);
        }

        void AcceptLoop()
        {
            while (true)
            {
                TcpClient c;
                try { c = listener.AcceptTcpClient(); }
                catch (Exception) { return; }
                var t = new Thread(() => Serve(c)) { IsBackground = true };
                t.Start();
            }
        }

        // The handshake, then the frames until the client goes; a new client
        // takes the place of the one before
        void Serve(TcpClient c)
        {
            try
            {
                c.NoDelay = true;
                var s = c.GetStream();
                string key = ReadHandshake(s);
                if (key == null) { c.Close(); return; }
                string accept;
                using (var sha = SHA1.Create())
                    accept = Convert.ToBase64String(sha.ComputeHash(Encoding.ASCII.GetBytes(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));
                byte[] reply = Encoding.ASCII.GetBytes("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n");
                s.Write(reply, 0, reply.Length);
                lock (gate)
                {
                    if (client != null) { try { client.Close(); } catch (Exception) { } }
                    client = c;
                    stream = s;
                    state.Clear();
                    Connected = true;
                    Version++;
                }
                // (the extension takes the protocol from the first message)
                Send("ADAPTER_VERSION 1.0.0;WNPRLIB_REVISION 1");
                ReadFrames(c, s);
            }
            catch (Exception) { }
            lock (gate)
            {
                if (client == c) { client = null; stream = null; Connected = false; Version++; }
            }
            try { c.Close(); } catch (Exception) { }
        }

        static string ReadHandshake(Stream s)
        {
            var buf = new List<byte>();
            while (buf.Count < 16384)
            {
                int b = s.ReadByte();
                if (b < 0) return null;
                buf.Add((byte)b);
                int n = buf.Count;
                if (n >= 4 && buf[n - 4] == 13 && buf[n - 3] == 10 && buf[n - 2] == 13 && buf[n - 1] == 10) break;
            }
            foreach (string line in Encoding.ASCII.GetString(buf.ToArray()).Split('\n'))
            {
                int colon = line.IndexOf(':');
                if (colon > 0 && line.Substring(0, colon).Trim().Equals("Sec-WebSocket-Key", StringComparison.OrdinalIgnoreCase))
                    return line.Substring(colon + 1).Trim();
            }
            return null;
        }

        static byte[] ReadExactly(Stream s, long n)
        {
            if (n > 1 << 20) throw new IOException("frame too large");
            var b = new byte[n];
            int at = 0;
            while (at < n)
            {
                int r = s.Read(b, at, (int)(n - at));
                if (r <= 0) throw new IOException("closed");
                at += r;
            }
            return b;
        }

        void ReadFrames(TcpClient c, Stream s)
        {
            var text = new List<byte>();
            while (true)
            {
                byte[] h = ReadExactly(s, 2);
                bool fin = (h[0] & 0x80) != 0;
                int op = h[0] & 0x0F;
                bool masked = (h[1] & 0x80) != 0;
                long len = h[1] & 0x7F;
                if (len == 126) { var e = ReadExactly(s, 2); len = (e[0] << 8) | e[1]; }
                else if (len == 127) { var e = ReadExactly(s, 8); len = 0; for (int i = 0; i < 8; i++) len = (len << 8) | e[i]; }
                byte[] mask = masked ? ReadExactly(s, 4) : null;
                byte[] data = ReadExactly(s, len);
                if (masked) for (int i = 0; i < data.Length; i++) data[i] ^= mask[i % 4];
                if (op == 8) return;
                if (op == 9) { WriteFrame(0xA, data); continue; }
                if (op != 0 && op != 1) continue;
                text.AddRange(data);
                if (!fin) continue;
                Take(Encoding.UTF8.GetString(text.ToArray()));
                text.Clear();
            }
        }

        // "TITLE Maneater": kept by its key
        void Take(string message)
        {
            int sp = message.IndexOf(' ');
            string k = (sp < 0 ? message : message.Substring(0, sp)).ToUpperInvariant();
            string v = sp < 0 ? "" : message.Substring(sp + 1);
            if (k.StartsWith("ERROR")) { Error = v; return; }
            lock (gate)
            {
                string old;
                if (state.TryGetValue(k, out old) && old == v) return;
                state[k] = v;
                Version++;
            }
        }

        void WriteFrame(int op, byte[] data)
        {
            var f = new List<byte>();
            f.Add((byte)(0x80 | op));
            if (data.Length < 126) f.Add((byte)data.Length);
            else if (data.Length < 65536) { f.Add(126); f.Add((byte)(data.Length >> 8)); f.Add((byte)data.Length); }
            else { f.Add(127); for (int i = 7; i >= 0; i--) f.Add((byte)((long)data.Length >> (8 * i))); }
            f.AddRange(data);
            lock (gate)
            {
                if (stream == null) return;
                try { stream.Write(f.ToArray(), 0, f.Count); } catch (Exception) { }
            }
        }

        public void Send(string text) { WriteFrame(1, Encoding.UTF8.GetBytes(text)); }

        public void Stop()
        {
            try { listener.Stop(); } catch (Exception) { }
            lock (gate) { if (client != null) try { client.Close(); } catch (Exception) { } }
        }
    }

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
Add-Type -TypeDefinition $source -Language CSharp

# --- The widget ------------------------------------------------------------------

# Prefix of the widget's sections in the launcher (CW11_Server: CW11_) and
# the group of its measures and meters (CW11)
$prefix = $Section -replace 'Server$', ''
$group = $prefix.TrimEnd('_')
$colors = @{ Text = $Text; Accent = $Accent }
$utf8 = New-Object System.Text.UTF8Encoding $false

# This copy owns the tile: an older one still running exits when it reads it
$cmdDir = Split-Path -Parent $Cmd
$tmp = "$Cmd.tmp"
[IO.File]::WriteAllText($tmp, "[Cmd]`r`nOwner=$PID`r`nDo=`r`n", $utf8)
if (Test-Path -LiteralPath $Cmd) { Remove-Item -LiteralPath $Cmd -Force }
Move-Item -LiteralPath $tmp -Destination $Cmd
$cmdStamp = (Get-Item -LiteralPath $Cmd).LastWriteTimeUtc

$note = ''
$link = $null
try { $link = New-Object RaintileSpotify.Link $Port }
catch { $note = "Port $Port is taken: close the other WebNowPlaying (a skin or its plugin), then show this again." }
if (-not $note) { $note = 'Waiting for Spotify: it needs Spicetify with the WebNowPlaying extension.' }

# The cover of a song, downloaded once (the last few kept): its path, or ''
$coverDir = Join-Path $cmdDir 'covers'
function Get-Cover([string]$Url) {
    $id = Get-CoverId $Url
    if ($id -eq '') { return '' }
    $path = Join-Path $coverDir ($id + '.jpg')
    if (Test-Path -LiteralPath $path) { return $path }
    try {
        if (-not (Test-Path -LiteralPath $coverDir)) { New-Item -ItemType Directory -Path $coverDir | Out-Null }
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $part = "$path.tmp"
        (New-Object Net.WebClient).DownloadFile('https://i.scdn.co/image/' + $id, $part)
        Move-Item -LiteralPath $part -Destination $path -Force
        Get-ChildItem -LiteralPath $coverDir -Filter '*.jpg' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -Skip 5 | Remove-Item -Force
        return $path
    } catch { return '' }   # (offline: no cover, the next song tries again)
}

$watcher = New-Object IO.FileSystemWatcher $cmdDir, (Split-Path -Leaf $Cmd)
$watcher.NotifyFilter = [IO.NotifyFilters]'LastWrite, Size, FileName'
$seen = -1
$last = $null
$coverUrl = $null
$coverPath = ''
$song = @{ Title = ''; Artist = ''; State = ''; Position = 0; Duration = 0; Liked = $false; Cover = ''; Note = $note }
$wait = 0
try {
    while ($true) {
        if ($wait -gt 0) { [void]$watcher.WaitForChanged([IO.WatcherChangeTypes]::All, $wait) }
        $wait = [Math]::Max(100, $Interval)
        if (-not [RaintileSpotify.Rainmeter]::Running()) { break }
        if ($Flag -and -not (Test-Path -LiteralPath $Flag)) { break }
        # a command: the file is newer (also checked without an event)
        if (Test-Path -LiteralPath $Cmd) {
            $stamp = (Get-Item -LiteralPath $Cmd).LastWriteTimeUtc
            if ($stamp -ne $cmdStamp) {
                $cmdStamp = $stamp
                $file = Read-CommandFile $Cmd
                if ($file.Owner -and $file.Owner -ne [string]$PID) { break }
                $c = ConvertFrom-SpotifyCommand $file.Do
                if ($c -and $c.Verb -eq 'quit') { break }
                if ($c -and $c.Verb -ne 'show' -and $link) {
                    $m = Get-SpotifyMessage $c $song.Position $song.Duration
                    if ($m) { $link.Send($m) }
                }
            }
        }
        # the song, when something came from Spotify
        if ($link -and $link.Version -ne $seen) {
            $seen = $link.Version
            $d = $link.Snapshot()
            $get = { param($k) if ($d.ContainsKey($k)) { [string]$d[$k] } else { '' } }
            $state = & $get 'STATE'
            $playing = $link.Connected -and $state -ne '' -and $state -ne 'STOPPED'
            if ((& $get 'COVER') -ne $coverUrl) { $coverUrl = & $get 'COVER'; $coverPath = Get-Cover $coverUrl }
            $song = @{
                Title = $(if ($playing) { & $get 'TITLE' } else { '' })
                Artist = & $get 'ARTIST'
                State = $state
                Position = ConvertTo-Seconds (& $get 'POSITION')
                Duration = ConvertTo-Seconds (& $get 'DURATION')
                Liked = [int](0 + ((& $get 'RATING') -replace '[^0-9]', '')) -ge 4
                Cover = $(if ($playing) { $coverPath } else { '' })
                Note = $(if ($link.Connected) { 'Nothing playing in Spotify.' } else { $note })
            }
        }
        $bang = Format-SpotifyBang $song $prefix $group $Config $colors
        if ($bang -ne $last) {
            $last = $bang
            if (-not [RaintileSpotify.Rainmeter]::Send($bang)) { break }
        }
    }
} finally {
    if ($link) { $link.Stop() }
}
