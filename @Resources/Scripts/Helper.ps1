# Raintile: background helper (started by the skin with RunCommand). Sends
# commands to Rainmeter with WM_COPYDATA (like "Rainmeter.exe !bang", but
# without starting a process every time).
#
# Gamepad (XInput: Xbox and compatible controllers), read every 16 ms:
#   Back + Start (GamepadToggle)  opens/closes the launcher
#   D-pad / left stick            moves the highlight (with repeat)
#   A                             launches the highlighted tile
#   B                             closes the search or the launcher
#   LB / RB                       previous / next category
#   GamepadSearch (Y)             search with the on-screen keyboard
#   X / Start                     on-screen keyboard: delete / done
#   LT / RT                       filter chips of the search results
# While the launcher is hidden, commands other than open/close are ignored by
# the skin.
#
# Hide on focus loss (AutoHide): while the launcher is visible, a click
# outside its window (e.g. on the second monitor) or another program coming
# to the foreground hides it.
#
# Play time (TrackPlaytime): after the skin launches a tile that is not a
# Steam game it writes Generated\Launch.txt ("<tile id>|<unix time>|<exe>");
# the helper looks for the game's process (that exe, the one learned last
# time, or the first program coming to the foreground that started after the
# launch, launchers and Windows parts left out), measures how long it runs and
# adds it to TimePlayed.txt in the data folder ("<tile id>|<minutes>|<last>").
# The exe found is kept in GameExe.txt for the next time.
#
# Only one copy runs: a new one (e.g. after "Refresh skin") closes the
# previous one; it exits by itself when Rainmeter is no longer running.

param(
    # 0 and 0 = only close the copy already running
    [int]$Gamepad = 1,
    [int]$AutoHide = 1,
    [string]$Config = 'Raintile',
    [string]$Toggle = 'BACK START',
    [int]$DeadZone = 12000,
    [int]$RepeatDelay = 350,
    [int]$RepeatRate = 110,
    [string]$SearchButton = 'Y',
    [int]$Track = 1,
    [string]$Generated = '',
    [string]$Data = ''
)

$ErrorActionPreference = 'Stop'
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { }

if (-not $Gamepad -and -not $AutoHide -and -not $Track) {
    $quit = $null
    if ([System.Threading.EventWaitHandle]::TryOpenExisting('Local\Raintile.Gamepad.Quit', [ref]$quit)) {
        [void]$quit.Set()
    }
    exit
}

$source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public class RaintilePad
{
    // XInput buttons
    public const int UP = 0x1, DOWN = 0x2, LEFT = 0x4, RIGHT = 0x8, START = 0x10, BACK = 0x20,
        LS = 0x40, RS = 0x80, LB = 0x100, RB = 0x200, A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000,
        LT = 0x10000, RT = 0x20000; // the triggers, pressed past half way

    public static int ParseButtons(string text)
    {
        int mask = 0;
        foreach (string part in text.ToUpperInvariant().Split(new[] { ' ', '+', '|', ',' }, StringSplitOptions.RemoveEmptyEntries))
        {
            switch (part)
            {
                case "UP": mask |= UP; break;
                case "DOWN": mask |= DOWN; break;
                case "LEFT": mask |= LEFT; break;
                case "RIGHT": mask |= RIGHT; break;
                case "START": case "MENU": mask |= START; break;
                case "BACK": case "VIEW": mask |= BACK; break;
                case "LS": mask |= LS; break;
                case "RS": mask |= RS; break;
                case "LB": mask |= LB; break;
                case "RB": mask |= RB; break;
                case "A": mask |= A; break;
                case "B": mask |= B; break;
                case "X": mask |= X; break;
                case "Y": mask |= Y; break;
                case "LT": mask |= LT; break;
                case "RT": mask |= RT; break;
            }
        }
        return mask;
    }

    // --- Button logic (no Windows dependencies: testable) ----------------

    readonly string config;
    readonly int toggleMask, deadZone, repeatDelay, repeatRate;
    public int SearchMask = Y;
    int previous, previousForRelease;
    bool toggleHeld, toggleUsed;
    readonly long[] nextRepeat = new long[4];

    public RaintilePad(string config, int toggleMask, int deadZone, int repeatDelay, int repeatRate)
    {
        this.config = config;
        this.toggleMask = toggleMask;
        this.deadZone = deadZone;
        this.repeatDelay = repeatDelay;
        this.repeatRate = repeatRate;
    }

    string Call(string function)
    {
        return "[!CommandMeasure MeasureScript \"" + function + "\" \"" + config + "\"]";
    }

    // Button state (all controllers together) and left stick at time 'now'
    // (ms) -> commands to send to Rainmeter.
    public List<string> Step(int buttons, int lx, int ly, long now)
    {
        var bangs = new List<string>();
        // the left stick counts as the D-pad
        if (lx < -deadZone) buttons |= LEFT;
        if (lx > deadZone) buttons |= RIGHT;
        if (ly > deadZone) buttons |= UP;
        if (ly < -deadZone) buttons |= DOWN;
        int pressed = buttons & ~previous;
        previous = buttons;
        if (toggleHeld || (toggleMask != 0 && (buttons & toggleMask) == toggleMask)) previousForRelease = buttons;

        // Open/close combination: while it is held nothing else counts
        if (toggleMask != 0 && (buttons & toggleMask) == toggleMask)
        {
            if (!toggleHeld) bangs.Add(Call("Toggle()"));
            toggleHeld = true;
            toggleUsed = true;
            return bangs;
        }
        if (toggleHeld)
        {
            if ((buttons & toggleMask) != 0) return bangs; // wait for the release
            toggleHeld = false;
        }
        // Start is part of the combination: it counts on its release, and only
        // if the combination was not used while it was held
        int released = previousForRelease & ~buttons;
        previousForRelease = buttons;
        if ((buttons & START) != 0 && (pressed & START) != 0) toggleUsed = false;
        if ((released & START) != 0 && !toggleUsed) bangs.Add(Call("PadStart()"));

        // Directions, repeating while held
        int[] dirs = { UP, DOWN, LEFT, RIGHT };
        string[] moves = { "Nav(0,-1)", "Nav(0,1)", "Nav(-1,0)", "Nav(1,0)" };
        for (int i = 0; i < 4; i++)
        {
            if ((pressed & dirs[i]) != 0)
            {
                bangs.Add(Call(moves[i]));
                nextRepeat[i] = now + repeatDelay;
            }
            else if ((buttons & dirs[i]) != 0 && now >= nextRepeat[i])
            {
                bangs.Add(Call(moves[i]));
                nextRepeat[i] = now + repeatRate;
            }
        }
        if ((pressed & A) != 0) bangs.Add(Call("Confirm()"));
        if ((pressed & B) != 0) bangs.Add(Call("Escape()"));
        if ((pressed & LB) != 0) bangs.Add(Call("NextCategory(-1)"));
        if ((pressed & RB) != 0) bangs.Add(Call("NextCategory(1)"));
        if (SearchMask != 0 && (pressed & SearchMask) != 0) bangs.Add(Call("PadSearch()"));
        if ((pressed & X) != 0 && (SearchMask & X) == 0) bangs.Add(Call("PadX()"));
        if ((pressed & LT) != 0 && (SearchMask & LT) == 0) bangs.Add(Call("PadChip(-1)"));
        if ((pressed & RT) != 0 && (SearchMask & RT) == 0) bangs.Add(Call("PadChip(1)"));
        return bangs;
    }

    // --- Windows: XInput and sending to Rainmeter -------------------------

    [StructLayout(LayoutKind.Sequential)]
    struct XInputState
    {
        public uint PacketNumber;
        public ushort Buttons;
        public byte LeftTrigger, RightTrigger;
        public short ThumbLX, ThumbLY, ThumbRX, ThumbRY;
    }

    [DllImport("xinput1_4.dll", EntryPoint = "XInputGetState")]
    static extern uint XInputGetState14(uint index, out XInputState state);

    [DllImport("xinput9_1_0.dll", EntryPoint = "XInputGetState")]
    static extern uint XInputGetState910(uint index, out XInputState state);

    static bool useXInput14 = true;

    static bool GetState(uint index, out XInputState state)
    {
        if (useXInput14)
        {
            try { return XInputGetState14(index, out state) == 0; }
            catch (DllNotFoundException) { useXInput14 = false; }
        }
        return XInputGetState910(index, out state) == 0;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct CopyData { public IntPtr Data; public int Size; public IntPtr Pointer; }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr FindWindow(string className, string windowName);

    [DllImport("user32.dll")]
    static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, ref CopyData data);

    static IntPtr RainmeterWindow()
    {
        return FindWindow("DummyRainWClass", null);
    }

    // --- Focus loss --------------------------------------------------------

    [StructLayout(LayoutKind.Sequential)]
    struct Rect { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    struct Point { public int X, Y; }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string windowName);

    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll")]
    static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll")]
    static extern bool GetWindowRect(IntPtr window, out Rect rect);

    [DllImport("user32.dll")]
    static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    static extern short GetAsyncKeyState(int key);

    [DllImport("user32.dll")]
    static extern bool GetCursorPos(out Point point);

    static uint ProcessOf(IntPtr window)
    {
        uint id;
        GetWindowThreadProcessId(window, out id);
        return id;
    }

    // The launcher window: the largest of Rainmeter's visible skins (the
    // launcher covers the screen).
    static IntPtr LauncherWindow(uint rainmeter)
    {
        IntPtr best = IntPtr.Zero, window = IntPtr.Zero;
        long bestArea = 0;
        while ((window = FindWindowEx(IntPtr.Zero, window, "RainmeterMeterWindow", null)) != IntPtr.Zero)
        {
            Rect r;
            if (ProcessOf(window) != rainmeter || !IsWindowVisible(window) || !GetWindowRect(window, out r)) continue;
            long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
            if (area > bestArea) { bestArea = area; best = window; }
        }
        return best;
    }

    static bool MouseDown()
    {
        // left, right, middle button
        return (GetAsyncKeyState(0x01) & 0x8000) != 0 || (GetAsyncKeyState(0x02) & 0x8000) != 0
            || (GetAsyncKeyState(0x04) & 0x8000) != 0;
    }

    public bool PadEnabled = true, AutoHide = true;
    IntPtr launcher, foreground;
    bool launcherShown, mouseWasDown;
    long nextLauncherScan;

    // While the launcher is visible: true if a click outside its window or
    // another program in the foreground took its focus away.
    bool FocusLost(IntPtr rainmeterWindow, long now)
    {
        uint rainmeter = ProcessOf(rainmeterWindow);
        // the launcher window is looked up every half second, not on every loop
        if (now >= nextLauncherScan || (launcher != IntPtr.Zero && !IsWindowVisible(launcher)))
        {
            launcher = LauncherWindow(rainmeter);
            nextLauncherScan = now + 500;
        }
        bool shown = launcher != IntPtr.Zero && IsWindowVisible(launcher);
        bool down = MouseDown();
        bool lost = false;
        if (shown && !launcherShown)
        {
            // just shown: only what changes from now on counts
            foreground = GetForegroundWindow();
        }
        else if (shown)
        {
            IntPtr fg = GetForegroundWindow();
            if (fg != foreground && fg != IntPtr.Zero && ProcessOf(fg) != rainmeter) lost = true;
            foreground = fg;
            if (down && !mouseWasDown)
            {
                Point p; Rect r;
                if (GetCursorPos(out p) && GetWindowRect(launcher, out r)
                    && (p.X < r.Left || p.X >= r.Right || p.Y < r.Top || p.Y >= r.Bottom)) lost = true;
            }
        }
        launcherShown = shown;
        mouseWasDown = down;
        return lost;
    }

    // --- Play time -----------------------------------------------------------

    [DllImport("kernel32.dll")]
    static extern IntPtr OpenProcess(uint access, bool inherit, uint processId);

    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll")]
    static extern bool GetExitCodeProcess(IntPtr process, out uint code);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern bool QueryFullProcessImageName(IntPtr process, int flags, System.Text.StringBuilder name, ref int size);

    [DllImport("kernel32.dll")]
    static extern bool GetProcessTimes(IntPtr process, out long creation, out long exit, out long kernel, out long user);

    const uint QUERY_LIMITED = 0x1000, SYNCHRONIZE = 0x100000;

    // Launchers, browsers' helpers and parts of Windows: never the game
    static readonly string[] NotGames = {
        "explorer", "rainmeter", "powershell", "pwsh", "conhost", "cmd", "openconsole", "windowsterminal",
        "steam", "steamwebhelper", "epicgameslauncher", "epicwebhelper", "galaxyclient", "galaxyclient helper",
        "upc", "ubisoftconnect", "ubisoftgamelauncher", "battle.net", "agent", "eadesktop", "eabackgroundservice",
        "origin", "xboxapp", "xboxpcapp", "gamebar", "gamebarftserver", "applicationframehost",
        "shellexperiencehost", "startmenuexperiencehost", "searchhost", "searchapp", "textinputhost", "lockapp",
        "systemsettings", "taskmgr", "raintileoptions" };

    public bool TrackEnabled;
    public string LaunchFile, PlayedFile, ExeFile;
    string pendingId, pendingExe;
    long pendingUntil;
    DateTime launchTime;
    string watchId, watchExe;
    IntPtr watchHandle = IntPtr.Zero;
    DateTime watchStart;
    long nextTrack;

    static string ImagePath(IntPtr handle)
    {
        var sb = new System.Text.StringBuilder(1024);
        int size = sb.Capacity;
        return QueryFullProcessImageName(handle, 0, sb, ref size) ? sb.ToString() : null;
    }

    static DateTime StartTime(IntPtr handle)
    {
        long c, e, k, u;
        return GetProcessTimes(handle, out c, out e, out k, out u) ? DateTime.FromFileTime(c) : DateTime.MinValue;
    }

    static Dictionary<string, string> ReadTable(string path)
    {
        var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            if (System.IO.File.Exists(path))
                foreach (string line in System.IO.File.ReadAllLines(path, System.Text.Encoding.UTF8))
                {
                    int i = line.LastIndexOf('|');
                    if (i > 0) d[line.Substring(0, i)] = line.Substring(i + 1);
                }
        }
        catch { }
        return d;
    }

    static void WriteLines(string path, IEnumerable<string> lines)
    {
        try
        {
            string tmp = path + ".tmp";
            System.IO.File.WriteAllLines(tmp, new List<string>(lines).ToArray(), new System.Text.UTF8Encoding(false));
            if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
            System.IO.File.Move(tmp, path);
        }
        catch { }
    }

    // A process to measure: open with the rights to read its path and wait for it
    bool StartWatch(uint pid, string id, string exe)
    {
        IntPtr h = OpenProcess(QUERY_LIMITED | SYNCHRONIZE, false, pid);
        if (h == IntPtr.Zero) return false;
        watchHandle = h;
        watchId = id;
        watchExe = exe;
        watchStart = DateTime.Now;
        pendingId = null;
        return true;
    }

    // The game has closed: its minutes go to TimePlayed.txt (tile id ->
    // minutes|last), its exe to GameExe.txt
    void EndWatch()
    {
        CloseHandle(watchHandle);
        watchHandle = IntPtr.Zero;
        int minutes = (int)Math.Round((DateTime.Now - watchStart).TotalMinutes);
        long last = (long)(DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalSeconds;
        int before = 0;
        // "<file>|<name>|<minutes>|<last>": the id is everything before the last two fields
        var byId = new Dictionary<string, long[]>(StringComparer.OrdinalIgnoreCase);
        try
        {
            if (System.IO.File.Exists(PlayedFile))
                foreach (string line in System.IO.File.ReadAllLines(PlayedFile, System.Text.Encoding.UTF8))
                {
                    int b = line.LastIndexOf('|'); if (b <= 0) continue;
                    int a = line.LastIndexOf('|', b - 1); if (a <= 0) continue;
                    long m, l;
                    if (long.TryParse(line.Substring(a + 1, b - a - 1), out m) && long.TryParse(line.Substring(b + 1), out l))
                        byId[line.Substring(0, a)] = new[] { m, l };
                }
        }
        catch { }
        long[] v;
        if (byId.TryGetValue(watchId, out v)) before = (int)v[0];
        byId[watchId] = new[] { (long)(before + minutes), last };
        var lines = new List<string>();
        foreach (var kv in byId) lines.Add(kv.Key + "|" + kv.Value[0] + "|" + kv.Value[1]);
        lines.Sort(StringComparer.OrdinalIgnoreCase);
        WriteLines(PlayedFile, lines);
        if (!string.IsNullOrEmpty(watchExe))
        {
            var exes = ReadTable(ExeFile);
            exes[watchId] = watchExe;
            var el = new List<string>();
            foreach (var kv in exes) el.Add(kv.Key + "|" + kv.Value);
            el.Sort(StringComparer.OrdinalIgnoreCase);
            WriteLines(ExeFile, el);
        }
        watchId = null;
    }

    static bool IsNotGame(string path)
    {
        if (string.IsNullOrEmpty(path)) return true;
        string name = System.IO.Path.GetFileNameWithoutExtension(path).ToLowerInvariant();
        if (Array.IndexOf(NotGames, name) >= 0) return true;
        string win = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        return path.StartsWith(win + "\\", StringComparison.OrdinalIgnoreCase);
    }

    // Twice a second: a new launch, the game to look for, the game that ends
    void TrackStep(long now)
    {
        if (now < nextTrack) return;
        nextTrack = now + 500;
        // a launch written by the skin
        try
        {
            if (System.IO.File.Exists(LaunchFile))
            {
                string text = System.IO.File.ReadAllText(LaunchFile, System.Text.Encoding.UTF8).Trim();
                System.IO.File.Delete(LaunchFile);
                string[] parts = text.Split('|');
                if (parts.Length >= 4)
                {
                    // "<file>|<name>|<unix time>|<exe>"
                    pendingId = parts[0] + "|" + parts[1];
                    pendingExe = parts[3].Trim();
                    // a launcher (GOG Galaxy, Battle.net, ...) is not the game
                    if (pendingExe != "" && IsNotGame(pendingExe)) pendingExe = "";
                    if (pendingExe == "") { string known; if (ReadTable(ExeFile).TryGetValue(pendingId, out known)) pendingExe = known; }
                    pendingUntil = now + 180000;
                    launchTime = DateTime.Now.AddSeconds(-5);
                }
            }
        }
        catch { }

        if (watchHandle != IntPtr.Zero)
        {
            uint code;
            if (!GetExitCodeProcess(watchHandle, out code) || code != 259 /* STILL_ACTIVE */) EndWatch();
            return;
        }
        if (pendingId == null) return;
        if (now > pendingUntil) { pendingId = null; return; }

        // the exe of the command, or the one learned last time
        if (!string.IsNullOrEmpty(pendingExe))
        {
            foreach (var p in Process.GetProcessesByName(System.IO.Path.GetFileNameWithoutExtension(pendingExe)))
            {
                IntPtr h = OpenProcess(QUERY_LIMITED, false, (uint)p.Id);
                if (h == IntPtr.Zero) continue;
                string path = ImagePath(h);
                CloseHandle(h);
                if (path != null && string.Equals(path, pendingExe, StringComparison.OrdinalIgnoreCase)
                    && StartWatch((uint)p.Id, pendingId, path)) return;
            }
        }
        // otherwise the first program in the foreground started after the launch
        IntPtr fg = GetForegroundWindow();
        if (fg == IntPtr.Zero) return;
        uint pid = ProcessOf(fg);
        IntPtr q = OpenProcess(QUERY_LIMITED, false, pid);
        if (q == IntPtr.Zero) return;
        string image = ImagePath(q);
        DateTime started = StartTime(q);
        CloseHandle(q);
        if (IsNotGame(image) || started < launchTime) return;
        StartWatch(pid, pendingId, image);
    }

    static void Send(IntPtr window, string bang)
    {
        IntPtr text = Marshal.StringToHGlobalUni(bang);
        try
        {
            var data = new CopyData { Data = (IntPtr)1, Size = (bang.Length + 1) * 2, Pointer = text };
            SendMessage(window, 0x004A /* WM_COPYDATA */, IntPtr.Zero, ref data);
        }
        finally { Marshal.FreeHGlobal(text); }
    }

    // Main loop: ends when 'quit' is signalled (a new copy started) or when
    // Rainmeter is gone.
    public void Run(WaitHandle quit)
    {
        var connected = new bool[4];
        var clock = Stopwatch.StartNew(); // does not wrap after 25 days like TickCount
        long nextScan = 0, lastRainmeter = 0;
        while (!quit.WaitOne(16))
        {
            long now = clock.ElapsedMilliseconds;
            IntPtr window = RainmeterWindow();
            if (window != IntPtr.Zero) lastRainmeter = now;
            else if (now - lastRainmeter > 10000) return;

            if (AutoHide && window != IntPtr.Zero && FocusLost(window, now)) Send(window, Call("FocusLost()"));
            if (TrackEnabled) { try { TrackStep(now); } catch { } }
            if (!PadEnabled) continue;

            // disconnected controllers are checked again every 2 s (the call
            // on an empty slot is slow)
            bool scan = now >= nextScan;
            if (scan) nextScan = now + 2000;
            int buttons = 0, lx = 0, ly = 0;
            for (uint i = 0; i < 4; i++)
            {
                if (!connected[i] && !scan) continue;
                XInputState state;
                connected[i] = GetState(i, out state);
                if (!connected[i]) continue;
                buttons |= state.Buttons;
                if (state.LeftTrigger > 128) buttons |= LT;
                if (state.RightTrigger > 128) buttons |= RT;
                if (Math.Abs((int)state.ThumbLX) > Math.Abs(lx)) lx = state.ThumbLX;
                if (Math.Abs((int)state.ThumbLY) > Math.Abs(ly)) ly = state.ThumbLY;
            }
            if (window == IntPtr.Zero) continue;
            foreach (string bang in Step(buttons, lx, ly, now)) Send(window, bang);
        }
    }
}
'@

Add-Type -TypeDefinition $source -Language CSharp

# Single copy: ask the previous one to quit and take its place
$quit = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\Raintile.Gamepad.Quit')
$mutex = New-Object System.Threading.Mutex($false, 'Local\Raintile.Gamepad')
[void]$quit.Set()
try { $owned = $mutex.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) { exit }
[void]$quit.Reset() # if there was no previous copy, the signal is still set

$pad = New-Object RaintilePad($Config, [RaintilePad]::ParseButtons($Toggle), $DeadZone, $RepeatDelay, $RepeatRate)
$pad.PadEnabled = [bool]$Gamepad
$pad.AutoHide = [bool]$AutoHide
$pad.SearchMask = [RaintilePad]::ParseButtons($SearchButton)
$pad.TrackEnabled = [bool]$Track -and $Generated -and $Data
if ($pad.TrackEnabled) {
    $pad.LaunchFile = Join-Path $Generated 'Launch.txt'
    $pad.PlayedFile = Join-Path $Data 'TimePlayed.txt'
    $pad.ExeFile = Join-Path $Data 'GameExe.txt'
}
try { $pad.Run($quit) } finally { $mutex.ReleaseMutex() }
