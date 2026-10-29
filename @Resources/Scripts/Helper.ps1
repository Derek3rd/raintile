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
# While the launcher is hidden, commands other than open/close are ignored by
# the skin.
#
# Hide on focus loss (AutoHide): while the launcher is visible, a click
# outside its window (e.g. on the second monitor) or another program coming
# to the foreground hides it.
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
    [int]$RepeatRate = 110
)

$ErrorActionPreference = 'Stop'
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { }

if (-not $Gamepad -and -not $AutoHide) {
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
        LS = 0x40, RS = 0x80, LB = 0x100, RB = 0x200, A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000;

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
            }
        }
        return mask;
    }

    // --- Button logic (no Windows dependencies: testable) ----------------

    readonly string config;
    readonly int toggleMask, deadZone, repeatDelay, repeatRate;
    int previous;
    bool toggleHeld;
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

        // Open/close combination: while it is held nothing else counts
        if (toggleMask != 0 && (buttons & toggleMask) == toggleMask)
        {
            if (!toggleHeld) bangs.Add(Call("Toggle()"));
            toggleHeld = true;
            return bangs;
        }
        if (toggleHeld)
        {
            if ((buttons & toggleMask) != 0) return bangs; // wait for the release
            toggleHeld = false;
        }

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
try { $pad.Run($quit) } finally { $mutex.ReleaseMutex() }
