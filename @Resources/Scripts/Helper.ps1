# Raintile: background helper (started by the skin with RunCommand). Sends
# commands to Rainmeter with WM_COPYDATA (like "Rainmeter.exe !bang", but
# without starting a process every time).
#
# Gamepad (XInput: Xbox and compatible controllers), read every 16 ms. Every
# action has its buttons in the settings (-Bindings; the defaults here):
#   Toggle: Back + Start          opens/closes the launcher
#   Up/Down/Left/Right: D-pad     moves the highlight (with repeat); the left
#                                 stick always moves too
#   Confirm: A                    launches the highlighted tile
#   Back: B                       closes the search or the launcher
#   PrevCategory / NextCategory   LB / RB
#   Search: Y                     search with the on-screen keyboard
#   Delete / Done: X / Start      on-screen keyboard: delete / done
#   PrevChip / NextChip: LT / RT  filter chips of the search results
#   Options: RS                   the Options window
#   Rainside: (none)              the Rainside's Toggle(), also while hidden
#   PadTile <n>: the pad shortcuts of the tiles (PadKey=), one per line of
#                Generated\PadKeys.txt, read at start; after the actions
# One button or several held together (see Step). Every action but Toggle goes
# through the skin's Pad(), which ignores it while the launcher is hidden or
# does not have the focus.
#
# Keyboard (RaintileKeys): the keys the skin lists in Generated\HotKeys.txt
# (open/close, the tiles' hot keys, and while the launcher has the focus Esc,
# the navigation or the letters of the search), with a keyboard hook.
#
# Focus: while the launcher is visible, a click outside its window (e.g. on
# the second monitor, or on a program over it) or another program coming to
# the foreground sends FocusLost(), a click on it FocusGained(). The skin
# turns its keys off and on with them, and hides on FocusLost() if AutoHide=1.
#
# Play time (TrackPlaytime): after the skin launches a tile that is not a
# Steam game it writes Generated\Launch.txt ("<tile id>|<unix time>|<exe>");
# the helper looks for the game's process (that exe, the one learned last
# time, or the first program coming to the foreground that started after the
# launch, launchers and Windows parts left out), measures how long it runs and
# adds it to TimePlayed.txt in the data folder ("<tile id>|<minutes>|<last>").
# The exe found is kept in GameExe.txt for the next time.
#
# Steam downloads: while the launcher is open, the progress, speed and time
# left of the Steam games downloading an update (see DownloadStep).
#
# Only one copy runs: a new one (e.g. after "Refresh skin") closes the
# previous one; it exits by itself when Rainmeter is no longer running.

param(
    # Gamepad, Track and Dash all 0 = only close the copy already running
    [int]$Gamepad = 1,
    [string]$Config = 'Raintile',
    # the buttons of the actions: "Toggle=BACK START;Search=Y;..." (RaintilePad.Actions)
    [string]$Bindings = '',
    [int]$DeadZone = 12000,
    [int]$RepeatDelay = 350,
    [int]$RepeatRate = 110,
    [int]$Track = 1,
    [int]$Dash = 1,
    [string]$Generated = '',
    [string]$Data = ''
)

$ErrorActionPreference = 'Stop'
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { }

if (-not $Gamepad -and -not $Track -and -not $Dash) {
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

// Data of the Dashboard (Helper: while Generated\DashOn.txt exists, every
// DashInterval ms): CPU, RAM, GPU, disks, network, processes, system, and the
// sensors of HWiNFO (shared memory) when it runs. Written to
// Generated\DashData.txt, one "key=value" per line (lists repeat the key).
public class RaintileDash
{
    [StructLayout(LayoutKind.Sequential)]
    struct MemoryStatus
    {
        public uint Length, MemoryLoad;
        public ulong TotalPhys, AvailPhys, TotalPageFile, AvailPageFile, TotalVirtual, AvailVirtual, AvailExtendedVirtual;
    }
    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
    [DllImport("kernel32.dll")] static extern ulong GetTickCount64();

    [StructLayout(LayoutKind.Sequential)]
    struct PowerStatus { public byte ACLineStatus, BatteryFlag, BatteryLifePercent, Reserved; public int LifeTime, FullLifeTime; }
    [DllImport("kernel32.dll")] static extern bool GetSystemPowerStatus(out PowerStatus status);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr OpenFileMapping(uint access, bool inherit, string name);
    [DllImport("kernel32.dll")] static extern IntPtr MapViewOfFile(IntPtr map, uint access, uint high, uint low, UIntPtr bytes);
    [DllImport("kernel32.dll")] static extern bool UnmapViewOfFile(IntPtr view);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

    PerformanceCounter cpuTotal, cpuPerf;
    List<PerformanceCounter> cores;
    double baseMhz;
    string cpuName = "", gpuName = "", osName = "";
    long vramTotal;
    Dictionary<string, PerformanceCounter> gpuEngines, gpuMemory;
    DateTime gpuRefresh = DateTime.MinValue;
    long netRx = -1, netTx = -1;
    DateTime netTime;
    Dictionary<int, TimeSpan> procTimes = new Dictionary<int, TimeSpan>();
    DateTime procTime;
    bool started;

    static string Clean(string s)
    {
        if (s == null) return "";
        return s.Replace("|", "/").Replace("\r", " ").Replace("\n", " ").Trim();
    }

    static string N(double v) { return v.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture); }

    static PerformanceCounter Counter(string category, string counter, string instance)
    {
        try { var c = new PerformanceCounter(category, counter, instance, true); c.NextValue(); return c; }
        catch { return null; }
    }

    void Start()
    {
        started = true;
        cpuTotal = Counter("Processor Information", "% Processor Utility", "_Total")
            ?? Counter("Processor", "% Processor Time", "_Total");
        cpuPerf = Counter("Processor Information", "% Processor Performance", "_Total");
        cores = new List<PerformanceCounter>();
        try
        {
            var names = new List<string>(new PerformanceCounterCategory("Processor Information").GetInstanceNames());
            names.RemoveAll(n => n.EndsWith("_Total"));
            names.Sort((a, b) =>
            {
                string[] x = a.Split(','), y = b.Split(',');
                int c = int.Parse(x[0]).CompareTo(int.Parse(y[0]));
                return c != 0 ? c : int.Parse(x[1]).CompareTo(int.Parse(y[1]));
            });
            bool utility = cpuTotal != null && cpuTotal.CounterName == "% Processor Utility";
            foreach (var n in names)
            {
                var c = Counter("Processor Information", utility ? "% Processor Utility" : "% Processor Time", n);
                if (c != null) cores.Add(c);
            }
        }
        catch { }
        try
        {
            using (var k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0"))
            {
                if (k != null)
                {
                    cpuName = Clean(Convert.ToString(k.GetValue("ProcessorNameString")));
                    baseMhz = Convert.ToDouble(k.GetValue("~MHz", 0));
                }
            }
        }
        catch { }
        // the graphics card with the most memory (the dedicated one on laptops)
        try
        {
            using (var cls = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"))
            {
                if (cls != null)
                    foreach (var sub in cls.GetSubKeyNames())
                    {
                        try
                        {
                            using (var k = cls.OpenSubKey(sub))
                            {
                                if (k == null) continue;
                                object mem = k.GetValue("HardwareInformation.qwMemorySize") ?? k.GetValue("HardwareInformation.MemorySize");
                                long bytes = 0;
                                if (mem is long) bytes = (long)mem;
                                else if (mem is int) bytes = (uint)(int)mem;
                                else if (mem is byte[] && ((byte[])mem).Length >= 4) bytes = ((byte[])mem).Length >= 8 ? BitConverter.ToInt64((byte[])mem, 0) : BitConverter.ToUInt32((byte[])mem, 0);
                                string desc = Convert.ToString(k.GetValue("DriverDesc"));
                                if (!string.IsNullOrEmpty(desc) && bytes >= vramTotal) { vramTotal = bytes; gpuName = Clean(desc); }
                            }
                        }
                        catch { }
                    }
            }
        }
        catch { }
        try
        {
            using (var k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
            {
                if (k != null)
                {
                    string product = Convert.ToString(k.GetValue("ProductName"));
                    int build;
                    int.TryParse(Convert.ToString(k.GetValue("CurrentBuildNumber")), out build);
                    if (build >= 22000) product = product.Replace("Windows 10", "Windows 11");
                    string ver = Convert.ToString(k.GetValue("DisplayVersion"));
                    osName = Clean(product + (string.IsNullOrEmpty(ver) ? "" : " " + ver));
                }
            }
        }
        catch { }
    }

    // GPU load: the "3D" engines of every process, summed (as Task Manager);
    // the instances change with the processes: looked up again every 5 s
    void RefreshGpu()
    {
        gpuRefresh = DateTime.Now;
        try
        {
            var engines = new Dictionary<string, PerformanceCounter>();
            foreach (var n in new PerformanceCounterCategory("GPU Engine").GetInstanceNames())
            {
                if (!n.EndsWith("engtype_3D")) continue;
                PerformanceCounter c;
                if (gpuEngines != null && gpuEngines.TryGetValue(n, out c)) { engines[n] = c; gpuEngines.Remove(n); }
                else { c = Counter("GPU Engine", "Utilization Percentage", n); if (c != null) engines[n] = c; }
            }
            if (gpuEngines != null) foreach (var c in gpuEngines.Values) c.Dispose();
            gpuEngines = engines;
            var memory = new Dictionary<string, PerformanceCounter>();
            foreach (var n in new PerformanceCounterCategory("GPU Adapter Memory").GetInstanceNames())
            {
                PerformanceCounter c;
                if (gpuMemory != null && gpuMemory.TryGetValue(n, out c)) { memory[n] = c; gpuMemory.Remove(n); }
                else { c = Counter("GPU Adapter Memory", "Dedicated Usage", n); if (c != null) memory[n] = c; }
            }
            if (gpuMemory != null) foreach (var c in gpuMemory.Values) c.Dispose();
            gpuMemory = memory;
        }
        catch { }
    }

    static float Next(PerformanceCounter c)
    {
        try { return c != null ? c.NextValue() : 0f; } catch { return 0f; }
    }

    // Counters made ahead (the helper calls it in the background when it
    // starts): making them, the GPU ones above all, takes seconds
    public void Prepare()
    {
        lock (this)
        {
            if (!started) Start();
            if (gpuEngines == null) RefreshGpu();
        }
    }

    // The GPU engines come and go with the programs: their list is read again
    // every 5 s, after the data is sent
    public void RefreshGpuIfDue()
    {
        lock (this)
        {
            if ((DateTime.Now - gpuRefresh).TotalSeconds >= 5) RefreshGpu();
        }
    }

    public string Collect(bool processes, bool sensors)
    {
        lock (this) { return CollectNow(processes, sensors); }
    }

    string CollectNow(bool processes, bool sensors)
    {
        if (!started) Start();
        if (gpuEngines == null) RefreshGpu();
        var sb = new System.Text.StringBuilder();
        var now = DateTime.Now;

        // CPU
        sb.Append("cpu=").Append(N(Math.Min(100, Next(cpuTotal)))).Append('\n');
        sb.Append("cpu.name=").Append(cpuName).Append('\n');
        if (cpuPerf != null && baseMhz > 0) sb.Append("cpu.mhz=").Append(N(Math.Round(baseMhz * Next(cpuPerf) / 100))).Append('\n');
        foreach (var c in cores) sb.Append("core=").Append(N(Math.Min(100, Next(c)))).Append('\n');

        // RAM
        var ms = new MemoryStatus { Length = (uint)Marshal.SizeOf(typeof(MemoryStatus)) };
        if (GlobalMemoryStatusEx(ref ms))
        {
            sb.Append("ram.total=").Append(ms.TotalPhys).Append('\n');
            sb.Append("ram.used=").Append(ms.TotalPhys - ms.AvailPhys).Append('\n');
        }

        // GPU
        if (gpuEngines != null)
        {
            double g = 0;
            foreach (var c in gpuEngines.Values) g += Next(c);
            sb.Append("gpu=").Append(N(Math.Min(100, g))).Append('\n');
        }
        if (gpuMemory != null)
        {
            double used = 0;
            foreach (var c in gpuMemory.Values) used += Next(c);
            sb.Append("gpu.vram=").Append(N(used)).Append('\n');
        }
        if (vramTotal > 0) sb.Append("gpu.vramtotal=").Append(vramTotal).Append('\n');
        sb.Append("gpu.name=").Append(gpuName).Append('\n');

        // Disks: letter|label|total|free
        try
        {
            foreach (var d in System.IO.DriveInfo.GetDrives())
            {
                if (d.DriveType != System.IO.DriveType.Fixed || !d.IsReady) continue;
                sb.Append("disk=").Append(d.Name.TrimEnd('\\')).Append('|').Append(Clean(d.VolumeLabel)).Append('|')
                  .Append(d.TotalSize).Append('|').Append(d.TotalFreeSpace).Append('\n');
            }
        }
        catch { }

        // Network: bytes per second, all the interfaces that are up
        try
        {
            long rx = 0, tx = 0;
            foreach (var ni in System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != System.Net.NetworkInformation.OperationalStatus.Up) continue;
                var t = ni.NetworkInterfaceType;
                if (t == System.Net.NetworkInformation.NetworkInterfaceType.Loopback || t == System.Net.NetworkInformation.NetworkInterfaceType.Tunnel) continue;
                var st = ni.GetIPv4Statistics();
                rx += st.BytesReceived; tx += st.BytesSent;
            }
            if (netRx >= 0)
            {
                double secs = Math.Max(0.1, (now - netTime).TotalSeconds);
                sb.Append("net.down=").Append(N(Math.Max(0, rx - netRx) / secs)).Append('\n');
                sb.Append("net.up=").Append(N(Math.Max(0, tx - netTx) / secs)).Append('\n');
            }
            netRx = rx; netTx = tx; netTime = now;
        }
        catch { }

        // Processes, by name: CPU % since the last time, memory
        if (processes)
        {
            var cpu = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
            var ram = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
            var times = new Dictionary<int, TimeSpan>();
            double elapsed = Math.Max(0.1, (now - procTime).TotalSeconds);
            int logical = Math.Max(1, Environment.ProcessorCount);
            foreach (var p in Process.GetProcesses())
            {
                try
                {
                    if (p.Id == 0) continue;
                    string name = p.ProcessName;
                    long ws = p.WorkingSet64;
                    long r; ram.TryGetValue(name, out r); ram[name] = r + ws;
                    TimeSpan t = p.TotalProcessorTime, before;
                    times[p.Id] = t;
                    if (procTimes.TryGetValue(p.Id, out before))
                    {
                        double pct = (t - before).TotalSeconds / elapsed / logical * 100;
                        double c; cpu.TryGetValue(name, out c); cpu[name] = c + pct;
                    }
                }
                catch { }
                finally { p.Dispose(); }
            }
            procTimes = times; procTime = now;
            var byCpu = new List<KeyValuePair<string, double>>(cpu);
            byCpu.Sort((a, b) => b.Value.CompareTo(a.Value));
            for (int i = 0; i < Math.Min(8, byCpu.Count); i++)
                if (byCpu[i].Key != "Idle") sb.Append("proc.cpu=").Append(Clean(byCpu[i].Key)).Append('|').Append(N(Math.Min(100, byCpu[i].Value))).Append('\n');
            var byRam = new List<KeyValuePair<string, long>>(ram);
            byRam.Sort((a, b) => b.Value.CompareTo(a.Value));
            for (int i = 0; i < Math.Min(8, byRam.Count); i++)
                sb.Append("proc.ram=").Append(Clean(byRam[i].Key)).Append('|').Append(byRam[i].Value).Append('\n');
        }

        // System
        sb.Append("sys.uptime=").Append(GetTickCount64() / 1000).Append('\n');
        sb.Append("sys.os=").Append(osName).Append('\n');
        sb.Append("sys.name=").Append(Clean(Environment.MachineName)).Append('\n');
        PowerStatus ps;
        if (GetSystemPowerStatus(out ps) && ps.BatteryFlag != 128 && ps.BatteryLifePercent <= 100)
            sb.Append("sys.battery=").Append(ps.BatteryLifePercent).Append('|').Append(ps.ACLineStatus == 1 ? 1 : 0).Append('\n');

        // HWiNFO sensors (shared memory, when HWiNFO runs with it on)
        if (sensors && !ReadLhm(sb) && !ReadLhmWeb(sb))
        {
            ReadHwinfo(sb);
            if (sensorError != "") sb.Append("hw.err=").Append(sensorError).Append('\n');
        }
        return sb.ToString();
    }

    // HWiNFO_SENSORS_SHARED_MEM2: a header, then the sensors and the readings
    // (type|sensor|label|value|unit). Types: 1 temperature, 2 voltage, 3 fan,
    // 4 current, 5 power, 6 clock, 7 usage, 8 other.
    // Sensors: LibreHardwareMonitor first (open source, no time limit), which
    // publishes them through WMI (root\LibreHardwareMonitor) while it runs;
    // HWiNFO's shared memory otherwise (its free version turns it off after
    // 12 hours). Both give "hw=on", then "hw=<type>|<hardware>|<label>|
    // <value>|<unit>" with HWiNFO's types: 1 temperature, 2 voltage, 3 fan,
    // 4 current, 5 power, 6 clock, 7 usage, 8 other.
    System.Management.ManagementScope lhmScope;
    Dictionary<string, string> lhmHardware;
    DateTime lhmHardwareTime, lhmRetry = DateTime.MinValue;

    static void LhmType(string kind, out int type, out string unit)
    {
        switch (kind)
        {
            case "Temperature": type = 1; unit = "\u00B0C"; break;
            case "Voltage": type = 2; unit = "V"; break;
            case "Fan": type = 3; unit = "RPM"; break;
            case "Current": type = 4; unit = "A"; break;
            case "Power": type = 5; unit = "W"; break;
            case "Clock": type = 6; unit = "MHz"; break;
            case "Load": type = 7; unit = "%"; break;
            case "Control": case "Level": type = 8; unit = "%"; break;
            case "Data": type = 8; unit = "GB"; break;
            case "SmallData": type = 8; unit = "MB"; break;
            case "Throughput": type = 8; unit = "B/s"; break;
            case "Frequency": type = 8; unit = "Hz"; break;
            default: type = 8; unit = ""; break;
        }
    }

    bool ReadLhm(System.Text.StringBuilder sb)
    {
        // not running: asked again every 10 s, not on every reading
        if (DateTime.Now < lhmRetry) return false;
        try
        {
            if (lhmScope == null || !lhmScope.IsConnected)
            {
                lhmScope = new System.Management.ManagementScope(@"\\.\root\LibreHardwareMonitor");
                lhmScope.Connect();
            }
            if (lhmHardware == null || (DateTime.Now - lhmHardwareTime).TotalSeconds >= 30)
            {
                var hw = new Dictionary<string, string>();
                using (var q = new System.Management.ManagementObjectSearcher(lhmScope, new System.Management.ObjectQuery("SELECT Identifier, Name FROM Hardware")))
                    foreach (System.Management.ManagementObject o in q.Get())
                        using (o) hw[Convert.ToString(o["Identifier"])] = Clean(Convert.ToString(o["Name"]));
                lhmHardware = hw;
                lhmHardwareTime = DateTime.Now;
            }
            var lines = new System.Text.StringBuilder();
            int count = 0;
            using (var q = new System.Management.ManagementObjectSearcher(lhmScope, new System.Management.ObjectQuery("SELECT Name, SensorType, Value, Parent FROM Sensor")))
                foreach (System.Management.ManagementObject o in q.Get())
                    using (o)
                    {
                        object v = o["Value"];
                        if (v == null) continue;
                        int type; string unit;
                        LhmType(Convert.ToString(o["SensorType"]), out type, out unit);
                        string hwName;
                        if (!lhmHardware.TryGetValue(Convert.ToString(o["Parent"]), out hwName)) hwName = "";
                        lines.Append("hw=").Append(type).Append('|').Append(hwName).Append('|').Append(Clean(Convert.ToString(o["Name"]))).Append('|')
                             .Append(N(Convert.ToDouble(v))).Append('|').Append(unit).Append('\n');
                        count++;
                    }
            if (count == 0) { lhmRetry = DateTime.Now.AddSeconds(10); return false; }
            sb.Append("hw=on\n").Append(lines.ToString());
            sensorError = "";
            return true;
        }
        catch
        {
            lhmScope = null;
            lhmHardware = null;
            lhmRetry = DateTime.Now.AddSeconds(10);
            return false;
        }
    }

    // LibreHardwareMonitor's own web server (its Options > Remote Web Server >
    // Run; newer versions publish nothing through WMI): http://localhost:
    // <port>/data.json, the tree of its window. Values come as text in its
    // language ("39,0 \u00B0C"); the kind of a reading from its "Type", or
    // from the group it is in (Temperatures, Load, Clocks...).
    public int LhmPort = 8085;
    DateTime lhmWebRetry = DateTime.MinValue;
    // why the sensors could not be read, shown on the widget (hw.err)
    string sensorError = "";

    static readonly Dictionary<string, string> LHM_GROUPS = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        { "Temperatures", "Temperature" }, { "Voltages", "Voltage" }, { "Fans", "Fan" }, { "Currents", "Current" },
        { "Powers", "Power" }, { "Clocks", "Clock" }, { "Load", "Load" }, { "Loads", "Load" }, { "Controls", "Control" },
        { "Levels", "Level" }, { "Data", "Data" }, { "Throughput", "Throughput" }, { "Factors", "Factor" },
    };

    // "3953,0 MHz", "1.234,5 W", "-" -> number (NaN without one)
    static double ParseLhmValue(string text)
    {
        var m = System.Text.RegularExpressions.Regex.Match(text ?? "", @"-?[\d.,]+");
        if (!m.Success) return double.NaN;
        string v = m.Value;
        int dot = v.LastIndexOf('.'), comma = v.LastIndexOf(',');
        if (dot >= 0 && comma >= 0)
        {
            // the last one separates the decimals
            if (comma > dot) v = v.Replace(".", "").Replace(',', '.'); else v = v.Replace(",", "");
        }
        else if (comma >= 0) v = v.Replace(',', '.');
        double d;
        return double.TryParse(v, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out d) ? d : double.NaN;
    }

    void LhmWebNode(Dictionary<string, object> node, string hardware, string group, System.Text.StringBuilder lines, ref int count)
    {
        string text = Clean(Convert.ToString(node.ContainsKey("Text") ? node["Text"] : ""));
        object kids;
        var children = node.TryGetValue("Children", out kids) ? kids as object[] : null;
        if (children != null && children.Length > 0)
        {
            // a group (Temperatures...) or a piece of hardware
            if (LHM_GROUPS.ContainsKey(text)) { foreach (var c in children) { var d = c as Dictionary<string, object>; if (d != null) LhmWebNode(d, hardware, text, lines, ref count); } }
            else { foreach (var c in children) { var d = c as Dictionary<string, object>; if (d != null) LhmWebNode(d, text, group, lines, ref count); } }
            return;
        }
        if (group == null) return;
        object typeValue;
        string kind = node.TryGetValue("Type", out typeValue) && Convert.ToString(typeValue) != "" ? Convert.ToString(typeValue) : LHM_GROUPS[group];
        double value = ParseLhmValue(Convert.ToString(node.ContainsKey("Value") ? node["Value"] : ""));
        if (double.IsNaN(value)) return;
        int type; string unit;
        LhmType(kind, out type, out unit);
        lines.Append("hw=").Append(type).Append('|').Append(hardware).Append('|').Append(text).Append('|')
             .Append(N(value)).Append('|').Append(unit).Append('\n');
        count++;
    }

    bool ReadLhmWeb(System.Text.StringBuilder sb)
    {
        if (DateTime.Now < lhmWebRetry) return false;
        try
        {
            var req = (System.Net.HttpWebRequest)System.Net.WebRequest.Create("http://localhost:" + LhmPort + "/data.json");
            req.Proxy = null;
            req.Timeout = 1500;
            req.ReadWriteTimeout = 1500;
            req.UserAgent = "Raintile";
            string json;
            using (var r = req.GetResponse())
            using (var reader = new System.IO.StreamReader(r.GetResponseStream(), System.Text.Encoding.UTF8))
                json = reader.ReadToEnd();
            var root = new System.Web.Script.Serialization.JavaScriptSerializer { MaxJsonLength = 32 * 1024 * 1024 }.DeserializeObject(json) as Dictionary<string, object>;
            if (root == null) throw new Exception("no data");
            var lines = new System.Text.StringBuilder();
            int count = 0;
            LhmWebNode(root, "", null, lines, ref count);
            if (count == 0) throw new Exception("no sensors");
            sb.Append("hw=on\n").Append(lines.ToString());
            sensorError = "";
            return true;
        }
        catch (Exception ex)
        {
            sensorError = "LibreHardwareMonitor web server (localhost:" + LhmPort + "): " + Clean(ex.Message);
            lhmWebRetry = DateTime.Now.AddSeconds(10);
            return false;
        }
    }

    static void ReadHwinfo(System.Text.StringBuilder sb)
    {
        IntPtr map = OpenFileMapping(4 /* FILE_MAP_READ */, false, @"Global\HWiNFO_SENS_SM2");
        if (map == IntPtr.Zero) { sb.Append("hw=off\n"); return; }
        IntPtr view = MapViewOfFile(map, 4, 0, 0, UIntPtr.Zero);
        try
        {
            if (view == IntPtr.Zero) { sb.Append("hw=off\n"); return; }
            int signature = Marshal.ReadInt32(view, 0);
            if (signature == 0x44414544 /* "DEAD" */) { sb.Append("hw=off\n"); return; }
            int sensorOffset = Marshal.ReadInt32(view, 20), sensorSize = Marshal.ReadInt32(view, 24), sensorCount = Marshal.ReadInt32(view, 28);
            int readingOffset = Marshal.ReadInt32(view, 32), readingSize = Marshal.ReadInt32(view, 36), readingCount = Marshal.ReadInt32(view, 40);
            if (readingCount <= 0 || readingCount > 5000 || readingSize < 316) { sb.Append("hw=off\n"); return; }
            var sensorNames = new string[Math.Max(0, Math.Min(sensorCount, 1000))];
            for (int i = 0; i < sensorNames.Length; i++)
            {
                IntPtr s = new IntPtr(view.ToInt64() + sensorOffset + (long)i * sensorSize);
                string user = Marshal.PtrToStringAnsi(new IntPtr(s.ToInt64() + 8 + 128));
                sensorNames[i] = Clean(string.IsNullOrEmpty(user) ? Marshal.PtrToStringAnsi(new IntPtr(s.ToInt64() + 8)) : user);
            }
            sb.Append("hw=on\n");
            for (int i = 0; i < readingCount; i++)
            {
                IntPtr r = new IntPtr(view.ToInt64() + readingOffset + (long)i * readingSize);
                int type = Marshal.ReadInt32(r, 0);
                int sensor = Marshal.ReadInt32(r, 4);
                string label = Marshal.PtrToStringAnsi(new IntPtr(r.ToInt64() + 140));
                if (string.IsNullOrEmpty(label)) label = Marshal.PtrToStringAnsi(new IntPtr(r.ToInt64() + 12));
                string unit = Marshal.PtrToStringAnsi(new IntPtr(r.ToInt64() + 268));
                double value = BitConverter.Int64BitsToDouble(Marshal.ReadInt64(r, 284));
                string sname = sensor >= 0 && sensor < sensorNames.Length ? sensorNames[sensor] : "";
                sb.Append("hw=").Append(type).Append('|').Append(sname).Append('|').Append(Clean(label)).Append('|')
                  .Append(N(value)).Append('|').Append(Clean(unit)).Append('\n');
            }
        }
        catch { sb.Append("hw=off\n"); }
        finally
        {
            if (view != IntPtr.Zero) UnmapViewOfFile(view);
            CloseHandle(map);
        }
    }
}

// Keyboard: the keys the skin lists in Generated\HotKeys.txt, one per line
// "<keys>|<down/up>|<config>|<function>" (the keys as in Settings.inc:
// "CTRL ALT G", "ESCAPE"), last line "end"; "log" writes every key to the
// Rainmeter log (DebugLog). The skin rewrites the list when it changes (shown,
// hidden, focus, typing). A low-level keyboard hook with the rules of the
// HotKey plugin it replaces: the function runs when a key of the combination
// goes down (or, "up", is released) while the others are held, again on every
// repeat; the key still reaches the program in front. No hook while the list
// is empty. The hook only queues the call: another thread sends it, so a busy
// Rainmeter never slows the keys of the PC down.
public class RaintileKeys
{
    public class Binding { public int[] Keys; public bool Up; public string Config, Function; }

    // The plugin's key names
    static readonly Dictionary<string, int> Names = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
    {
        { "LBUTTON", 0x01 }, { "RBUTTON", 0x02 }, { "MBUTTON", 0x04 }, { "XBUTTON1", 0x05 }, { "XBUTTON2", 0x06 },
        { "BACKSPACE", 0x08 }, { "TAB", 0x09 }, { "ENTER", 0x0D }, { "SHIFT", 0x10 }, { "CTRL", 0x11 }, { "ALT", 0x12 },
        { "PAUSE", 0x13 }, { "CAPSLOCK", 0x14 }, { "ESCAPE", 0x1B }, { "SPACE", 0x20 }, { "PAGEUP", 0x21 }, { "PAGEDOWN", 0x22 },
        { "END", 0x23 }, { "HOME", 0x24 }, { "LEFT", 0x25 }, { "UP", 0x26 }, { "RIGHT", 0x27 }, { "DOWN", 0x28 },
        { "PRINTSCREEN", 0x2C }, { "INSERT", 0x2D }, { "DELETE", 0x2E }, { "LWIN", 0x5B }, { "RWIN", 0x5C }, { "MENU", 0x5D },
        { "MULT", 0x6A }, { "ADD", 0x6B }, { "SUBTRACT", 0x6D }, { "DECIMAL", 0x6E }, { "DIVIDE", 0x6F },
        { "NUMLOCK", 0x90 }, { "SCROLLLOCK", 0x91 },
        { "LSHIFT", 0xA0 }, { "RSHIFT", 0xA1 }, { "LCTRL", 0xA2 }, { "RCTRL", 0xA3 }, { "LALT", 0xA4 }, { "RALT", 0xA5 },
        { "COLON", 0xBA }, { "PLUS", 0xBB }, { "COMMA", 0xBC }, { "MINUS", 0xBD }, { "PERIOD", 0xBE }, { "FORWARDSLASH", 0xBF },
        { "BACKTICK", 0xC0 }, { "LBRACKET", 0xDB }, { "BACKSLASH", 0xDC }, { "RBRACKET", 0xDD }, { "QUOTE", 0xDE },
    };

    static RaintileKeys()
    {
        for (int n = 0; n <= 9; n++) Names["NUM" + n] = 0x60 + n;
        for (int n = 1; n <= 24; n++) Names["F" + n] = 0x6F + n;
    }

    [DllImport("user32.dll")] static extern short VkKeyScanEx(char c, IntPtr layout);
    [DllImport("user32.dll")] static extern IntPtr GetKeyboardLayout(uint thread);

    // The keys of a combination, as the plugin reads them: one character (the
    // key that types it), a name, or a number (0x.., 0o.., 0b.., decimal). A
    // generic modifier (CTRL) covers its left and right keys. Sorted; null if
    // a key is not valid (the plugin dropped the whole combination).
    public static int[] ParseCombo(string text)
    {
        var keys = new List<int>();
        foreach (string token in (text ?? "").Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries))
        {
            int vk = 0;
            char c = token[0];
            if (token.Length == 1)
            {
                // letters and digits are their own key on every layout
                if (c >= 'a' && c <= 'z') vk = c - 'a' + 'A';
                else if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) vk = c;
                else vk = VkKeyScanEx(c, GetKeyboardLayout(0)) & 0xFF;
            }
            else if (c == '0' && (token[1] == 'x' || token[1] == 'o' || token[1] == 'b'))
            {
                try { vk = Convert.ToInt32(token.Substring(2), token[1] == 'x' ? 16 : token[1] == 'o' ? 8 : 2); }
                catch (FormatException) { vk = 0; }
                catch (ArgumentException) { vk = 0; }
                catch (OverflowException) { vk = 0; }
            }
            else if (!Names.TryGetValue(token, out vk))
            {
                // a decimal number: its leading digits, as wcstol
                int i = 0;
                while (i < token.Length && i < 4 && token[i] >= '0' && token[i] <= '9') vk = vk * 10 + (token[i++] - '0');
            }
            if (vk < 0x01 || vk > 0xFE) return null;
            if (!keys.Contains(vk)) keys.Add(vk);
        }
        if (keys.Count == 0) return null;
        // SHIFT covers LSHIFT and RSHIFT, CTRL and ALT theirs
        if (keys.Contains(0x10)) keys.RemoveAll(k => k == 0xA0 || k == 0xA1);
        if (keys.Contains(0x11)) keys.RemoveAll(k => k == 0xA2 || k == 0xA3);
        if (keys.Contains(0x12)) keys.RemoveAll(k => k == 0xA4 || k == 0xA5);
        keys.Sort();
        return keys.ToArray();
    }

    // The plugin's rule: the key that went down (up) is one of the
    // combination, and the others are held (more keys held do not matter)
    public static bool Fires(int[] keys, int vk, Func<int, bool> held)
    {
        if (Array.IndexOf(keys, vk) < 0) return false;
        foreach (int k in keys)
            if (k != vk && !held(k)) return false;
        return true;
    }

    // Generated\HotKeys.txt; null while it is incomplete (no "end": being
    // written). Lines that are not valid are left out.
    public static List<Binding> ParseList(string[] lines, out bool log)
    {
        log = false;
        var list = new List<Binding>();
        foreach (string raw in lines)
        {
            string line = raw.Trim();
            if (line == "end") return list;
            if (line == "log") { log = true; continue; }
            string[] p = line.Split('|');
            if (p.Length != 4) continue;
            int[] keys = ParseCombo(p[0]);
            string when = p[1].Trim().ToLowerInvariant(), config = p[2].Trim(), function = p[3].Trim();
            // only a call of the skin's script, with nothing that would end the bang
            if (keys == null || (when != "down" && when != "up") || config == "" || function.IndexOf('(') < 1
                || !function.EndsWith(")") || (config + function).IndexOfAny(new[] { '"', '[', ']' }) >= 0) continue;
            list.Add(new Binding { Keys = keys, Up = when == "up", Config = config, Function = function });
        }
        return null;
    }

    // --- Windows: the hook ------------------------------------------------------

    [StructLayout(LayoutKind.Sequential)]
    struct Msg { public IntPtr Window; public uint Message; public IntPtr WParam, LParam; public uint Time; public int X, Y; }

    delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int id, HookProc proc, IntPtr module, uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern int GetMessage(out Msg msg, IntPtr window, uint min, uint max);
    [DllImport("user32.dll")] static extern bool PeekMessage(out Msg msg, IntPtr window, uint min, uint max, uint remove);
    [DllImport("user32.dll")] static extern bool PostThreadMessage(uint thread, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);

    const int WH_KEYBOARD_LL = 13;
    const uint WM_QUIT = 0x12, WM_APP = 0x8000;
    static readonly Func<int, bool> Held = k => (GetAsyncKeyState(k) & 0x8000) != 0;

    readonly string file;
    readonly object loading = new object();
    readonly System.Collections.Concurrent.BlockingCollection<string> queue = new System.Collections.Concurrent.BlockingCollection<string>();
    readonly ManualResetEvent started = new ManualResetEvent(false);
    readonly HookProc proc; // kept here: Windows calls it, the collector must not take it
    volatile Binding[] bindings = new Binding[0];
    volatile bool log;
    uint hookThread;
    IntPtr hook;
    System.IO.FileSystemWatcher watcher;

    public RaintileKeys(string file)
    {
        this.file = file;
        proc = Proc;
    }

    public void Start()
    {
        // the hook's thread above the helper's (below normal): Windows waits
        // for it on every key of the PC, and drops a hook that is too slow
        new Thread(HookLoop) { IsBackground = true, Priority = ThreadPriority.Highest }.Start();
        new Thread(SendLoop) { IsBackground = true }.Start();
        started.WaitOne();
        watcher = new System.IO.FileSystemWatcher(System.IO.Path.GetDirectoryName(file), System.IO.Path.GetFileName(file));
        watcher.NotifyFilter = System.IO.NotifyFilters.LastWrite | System.IO.NotifyFilters.FileName | System.IO.NotifyFilters.Size;
        System.IO.FileSystemEventHandler changed = (s, e) => Load();
        watcher.Changed += changed;
        watcher.Created += changed;
        watcher.Deleted += changed;
        watcher.Renamed += (s, e) => Load();
        watcher.Error += (s, e) => Load();
        watcher.EnableRaisingEvents = true;
        Load();
    }

    public void Stop()
    {
        if (watcher != null) watcher.Dispose();
        PostThreadMessage(hookThread, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        queue.CompleteAdding();
    }

    // The list read again; while the skin is writing it (locked, or no "end"
    // yet) a few more tries
    void Load()
    {
        lock (loading)
        {
            for (int i = 0; i < 20; i++)
            {
                try
                {
                    string[] lines = System.IO.File.Exists(file) ? System.IO.File.ReadAllLines(file) : new[] { "end" };
                    bool l;
                    List<Binding> list = ParseList(lines, out l);
                    if (list != null)
                    {
                        bindings = list.ToArray();
                        log = l;
                        PostThreadMessage(hookThread, WM_APP, IntPtr.Zero, IntPtr.Zero);
                        return;
                    }
                }
                catch (System.IO.IOException) { }
                catch (UnauthorizedAccessException) { }
                Thread.Sleep(25);
            }
        }
    }

    void HookLoop()
    {
        Msg msg;
        hookThread = GetCurrentThreadId();
        PeekMessage(out msg, IntPtr.Zero, 0, 0, 0); // the thread's queue, before anything is posted to it
        started.Set();
        while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0)
            if (msg.Message == WM_APP) SetHook(bindings.Length > 0);
        SetHook(false);
    }

    void SetHook(bool on)
    {
        if (on && hook == IntPtr.Zero)
        {
            hook = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(null), 0);
            if (hook == IntPtr.Zero)
                Post("[!Log \"Raintile: the keyboard hook could not start (error " + Marshal.GetLastWin32Error() + "): no keys\" Error]");
        }
        else if (!on && hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(hook);
            hook = IntPtr.Zero;
        }
    }

    IntPtr Proc(int code, IntPtr wParam, IntPtr lParam)
    {
        // (nothing may escape from here: Windows called it)
        try
        {
            int m = (int)wParam;
            bool down = m == 0x100 || m == 0x104, up = m == 0x101 || m == 0x105; // WM_(SYS)KEYDOWN, WM_(SYS)KEYUP
            if (code >= 0 && (down || up))
            {
                int vk = Marshal.ReadInt32(lParam);
                if (log) Post("[!Log \"Raintile: key 0x" + vk.ToString("X2") + " (" + vk + ") " + (up ? "up" : "down") + "\"]");
                foreach (Binding b in bindings)
                    if (b.Up == up && Fires(b.Keys, vk, Held)) Post(RaintilePad.CallTo(b.Config, b.Function));
            }
        }
        catch { }
        return CallNextHookEx(hook, code, wParam, lParam);
    }

    // (after Stop the queue takes nothing more)
    void Post(string bang)
    {
        try { queue.Add(bang); }
        catch (InvalidOperationException) { }
    }

    void SendLoop()
    {
        foreach (string bang in queue.GetConsumingEnumerable())
        {
            IntPtr window = RaintilePad.RainmeterWindow();
            if (window != IntPtr.Zero) RaintilePad.Send(window, bang);
        }
    }
}

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

    // The actions, in the order of the settings (Gamepad<Action>), with the
    // buttons they have by default. Each one is one button or several held
    // together; a combination used by two actions acts for the first only.
    public static readonly string[] Actions = { "Toggle", "Up", "Down", "Left", "Right", "Confirm", "Back",
        "PrevCategory", "NextCategory", "Search", "Delete", "Done", "PrevChip", "NextChip", "Options", "Rainside" };
    static readonly string[] DefaultButtons = { "BACK START", "UP", "DOWN", "LEFT", "RIGHT", "A", "B",
        "LB", "RB", "Y", "X", "START", "LT", "RT", "RS", "" };
    const int MOVES = 1;   // Up, Down, Left, Right: they repeat, the left stick does them too

    readonly string config;
    readonly int deadZone, repeatDelay, repeatRate;
    // the actions, then the pad shortcuts of the tiles (SetTiles): each one
    // after Actions.Length starts a tile
    int[] masks = new int[Actions.Length];
    bool[] active = new bool[Actions.Length];   // has buttons, not taken by an action before it
    bool[] late = new bool[Actions.Length];     // part of a larger combination: acts on release
    bool[] held = new bool[Actions.Length];
    bool[] armed = new bool[Actions.Length];    // a late one held, no combination done meanwhile
    readonly long[] nextRepeat = new long[4];
    readonly bool[] stickHeld = new bool[4];
    int[] order = new int[0];                            // larger combinations first
    int used;                                            // buttons of a combination that acted, until released

    public RaintilePad(string config, int deadZone, int repeatDelay, int repeatRate)
    {
        this.config = config;
        this.deadZone = deadZone;
        this.repeatDelay = repeatDelay;
        this.repeatRate = repeatRate;
        for (int i = 0; i < Actions.Length; i++) masks[i] = ParseButtons(DefaultButtons[i]);
        Prepare();
    }

    // "Toggle=BACK START;Search=Y;Options=" (the actions given; empty = none)
    public void SetBindings(string text)
    {
        foreach (string part in (text ?? "").Split(';'))
        {
            int eq = part.IndexOf('=');
            if (eq < 0) continue;
            int i = Array.FindIndex(Actions, a => string.Equals(a, part.Substring(0, eq).Trim(), StringComparison.OrdinalIgnoreCase));
            if (i >= 0) masks[i] = ParseButtons(part.Substring(eq + 1));
        }
        Prepare();
    }

    // The pad shortcuts of the tiles, in the order of Generated\PadKeys.txt
    // (Pad('PadTile', <line>)): after the actions, so an action's buttons stay
    // the action's
    public void SetTiles(string[] combos)
    {
        int n = Actions.Length + (combos == null ? 0 : combos.Length);
        var m = new int[n];
        Array.Copy(masks, m, Actions.Length);
        for (int i = Actions.Length; i < n; i++) m[i] = ParseButtons(combos[i - Actions.Length]);
        masks = m;
        active = new bool[n];
        late = new bool[n];
        held = new bool[n];
        armed = new bool[n];
        Prepare();
    }

    static int Count(int mask)
    {
        int n = 0;
        for (; mask != 0; mask &= mask - 1) n++;
        return n;
    }

    void Prepare()
    {
        var list = new List<int>();
        for (int i = 0; i < masks.Length; i++)
        {
            active[i] = masks[i] != 0 && Array.IndexOf(masks, masks[i]) == i;
            late[i] = false;
            held[i] = armed[i] = false;
            if (active[i]) list.Add(i);
        }
        foreach (int i in list)
            foreach (int j in list)
                if (masks[j] != masks[i] && (masks[j] & masks[i]) == masks[i]) late[i] = true;
        list.Sort((a, b) => Count(masks[b]) != Count(masks[a]) ? Count(masks[b]) - Count(masks[a]) : a - b);
        order = list.ToArray();
    }

    string Call(string function)
    {
        return CallTo(config, function);
    }

    internal static string CallTo(string skin, string function)
    {
        return "[!CommandMeasure MeasureScript \"" + function + "\" \"" + skin + "\"]";
    }

    // The Rainside's config (Rainside\Rainside.ini, run by the same script)
    string SideConfig { get { return config + "\\Rainside"; } }

    // A button for the launcher: through Pad(), which drops it while the
    // launcher is hidden or does not have the focus
    string PadCall(string function, string args)
    {
        return Call("Pad('" + function + "'" + (args.Length > 0 ? "," + args : "") + ")");
    }

    string Command(int action)
    {
        if (action >= Actions.Length) return PadCall("PadTile", (action - Actions.Length + 1).ToString());
        switch (Actions[action])
        {
            case "Toggle": return Call("Toggle()");
            case "Up": return PadCall("Nav", "0,-1");
            case "Down": return PadCall("Nav", "0,1");
            case "Left": return PadCall("Nav", "-1,0");
            case "Right": return PadCall("Nav", "1,0");
            case "Confirm": return PadCall("Confirm", "");
            case "Back": return PadCall("Escape", "");
            case "PrevCategory": return PadCall("NextCategory", "-1");
            case "NextCategory": return PadCall("NextCategory", "1");
            case "Search": return PadCall("PadSearch", "");
            case "Delete": return PadCall("PadX", "");
            case "Done": return PadCall("PadStart", "");
            case "PrevChip": return PadCall("PadChip", "-1");
            case "NextChip": return PadCall("PadChip", "1");
            // (through the launcher, which knows whether there is a Rainside)
            case "Rainside": return Call("RainsideToggle()");
            default: return PadCall("PadOptions", "");
        }
    }

    // Button state (all controllers together) and left stick at time 'now'
    // (ms) -> commands to send to Rainmeter.
    //
    // An action acts when its buttons are all held, the last one just pressed;
    // the buttons of a combination that acted do nothing else until released.
    // An action whose buttons are part of a larger combination (Start of
    // Back + Start) acts on release instead, and only if no combination was
    // done while it was held.
    public List<string> Step(int buttons, int lx, int ly, long now)
    {
        var bangs = new List<string>();
        used &= buttons;
        // the left stick always moves, whatever the buttons of the moves
        int[] stick = { ly > deadZone ? 1 : 0, ly < -deadZone ? 1 : 0, lx < -deadZone ? 1 : 0, lx > deadZone ? 1 : 0 };
        foreach (int i in order)
        {
            int m = masks[i];
            bool all = (buttons & m) == m && (used & m) == 0;
            if (late[i])
            {
                if (all && !held[i]) armed[i] = true;
                else if ((buttons & m) != m && armed[i]) { armed[i] = false; bangs.Add(Command(i)); }
                held[i] = (buttons & m) == m;
                continue;
            }
            bool move = i >= MOVES && i < MOVES + 4;
            bool on = all || (move && stick[i - MOVES] != 0);
            if (on && !held[i])
            {
                bangs.Add(Command(i));
                if (move) nextRepeat[i - MOVES] = now + repeatDelay;
                if (all && Count(m) > 1)
                {
                    used |= m;
                    foreach (int j in order) if (late[j] && (masks[j] & m) != 0) armed[j] = false;
                }
            }
            else if (on && move && now >= nextRepeat[i - MOVES])
            {
                bangs.Add(Command(i));
                nextRepeat[i - MOVES] = now + repeatRate;
            }
            held[i] = on;
        }
        // directions whose move has no buttons of its own or acts on release:
        // the stick still does them
        for (int d = 0; d < 4; d++)
        {
            int i = MOVES + d;
            if (active[i] && !late[i]) continue;
            bool on = stick[d] != 0;
            if (on && !stickHeld[d]) { bangs.Add(Command(i)); nextRepeat[d] = now + repeatDelay; }
            else if (on && now >= nextRepeat[d]) { bangs.Add(Command(i)); nextRepeat[d] = now + repeatRate; }
            stickHeld[d] = on;
        }
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

    internal static IntPtr RainmeterWindow()
    {
        return FindWindow("DummyRainWClass", null);
    }

    // --- Focus --------------------------------------------------------------

    [StructLayout(LayoutKind.Sequential)]
    struct Rect { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    struct Point { public int X, Y; }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string windowName);

    [DllImport("user32.dll")]
    static extern IntPtr WindowFromPoint(Point point);

    [DllImport("user32.dll")]
    static extern IntPtr GetAncestor(IntPtr window, uint flags);

    const uint GA_ROOT = 2;

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

    // The launcher's window: the Rainmeter window of the size the skin wrote
    // to Generated\LauncherSize.txt ("<w>|<h>"), shown or hidden (it keeps
    // its size while hidden and while it slides in and out of its side);
    // without it, the largest visible one (right when it covers the screen,
    // not when it is a window or docked on a side next to bigger skins)
    public string SizeFile;
    int launcherW, launcherH;
    DateTime sizeStamp = DateTime.MinValue;

    void ReadLauncherSize()
    {
        try
        {
            if (SizeFile == null || !System.IO.File.Exists(SizeFile)) { launcherW = launcherH = 0; return; }
            DateTime stamp = System.IO.File.GetLastWriteTimeUtc(SizeFile);
            if (stamp == sizeStamp) return;
            sizeStamp = stamp;
            string[] p = System.IO.File.ReadAllText(SizeFile).Trim().Split('|');
            if (p.Length < 2 || !int.TryParse(p[0], out launcherW) || !int.TryParse(p[1], out launcherH)) launcherW = launcherH = 0;
        }
        catch { launcherW = launcherH = 0; }
    }

    // The launcher among Rainmeter's skin windows (each one "w, h, visible
    // 1/0"), -1 for none: the visible one of its size; with none, the hidden
    // one of its size (the launcher is hidden: never another skin, whose
    // focus would be followed in its place); with no window of its size at
    // all, or without the size, the largest visible one.
    public static int PickLauncher(int[][] skins, int launcherW, int launcherH)
    {
        int best = -1, hidden = -1;
        long bestArea = 0;
        for (int i = 0; i < skins.Length; i++)
        {
            int w = skins[i][0], h = skins[i][1];
            bool sized = launcherW > 0 && Math.Abs(w - launcherW) <= 1 && Math.Abs(h - launcherH) <= 1;
            if (skins[i][2] == 0)
            {
                if (sized && hidden < 0) hidden = i;
                continue;
            }
            if (sized) return i;
            long area = (long)w * h;
            if (area > bestArea) { bestArea = area; best = i; }
        }
        return hidden >= 0 ? hidden : best;
    }

    IntPtr LauncherWindow(uint rainmeter)
    {
        ReadLauncherSize();
        var windows = new List<IntPtr>();
        var skins = new List<int[]>();
        IntPtr window = IntPtr.Zero;
        while ((window = FindWindowEx(IntPtr.Zero, window, "RainmeterMeterWindow", null)) != IntPtr.Zero)
        {
            Rect r;
            if (ProcessOf(window) != rainmeter || !GetWindowRect(window, out r)) continue;
            windows.Add(window);
            skins.Add(new[] { r.Right - r.Left, r.Bottom - r.Top, IsWindowVisible(window) ? 1 : 0 });
        }
        int i = PickLauncher(skins.ToArray(), launcherW, launcherH);
        return i < 0 ? IntPtr.Zero : windows[i];
    }

    static bool MouseDown()
    {
        // left, right, middle button
        return (GetAsyncKeyState(0x01) & 0x8000) != 0 || (GetAsyncKeyState(0x02) & 0x8000) != 0
            || (GetAsyncKeyState(0x04) & 0x8000) != 0;
    }

    public bool PadEnabled = true;
    IntPtr launcher, foreground;
    bool launcherShown, mouseWasDown;
    long nextLauncherScan;

    // The window a click lands on: +1 the launcher, 0 a window of Rainmeter
    // that is not a skin (its menus and dialogs), -1 anything else (another
    // program, also when it is over the launcher, another skin, the desktop)
    int ClickedOn(uint rainmeter, IntPtr skin)
    {
        Point p;
        if (!GetCursorPos(out p)) return 0;
        IntPtr root = GetAncestor(WindowFromPoint(p), GA_ROOT);
        if (root == IntPtr.Zero) return 0;
        if (root == skin) return 1;
        if (ProcessOf(root) != rainmeter) return -1;
        var name = new System.Text.StringBuilder(64);
        GetClassName(root, name, name.Capacity);
        return name.ToString() == "RainmeterMeterWindow" ? -1 : 0;
    }

    // While the launcher is visible: -1 if a click elsewhere or another
    // program in the foreground took its focus away, +1 if a click on it
    // gave it back (the skin turns its keys off and on), 0 otherwise.
    int FocusStep(IntPtr rainmeterWindow, long now, bool down)
    {
        uint rainmeter = ProcessOf(rainmeterWindow);
        // the launcher window is looked up every half second, not on every
        // loop, and when it has just been hidden; while hidden, its window
        // (LauncherWindow) tells on the next loop that it is shown again
        if (now >= nextLauncherScan || (launcherShown && !IsWindowVisible(launcher)))
        {
            launcher = LauncherWindow(rainmeter);
            nextLauncherScan = now + 500;
        }
        bool shown = launcher != IntPtr.Zero && IsWindowVisible(launcher);
        int change = 0;
        if (shown && !launcherShown)
        {
            // just shown: only what changes from now on counts
            foreground = GetForegroundWindow();
        }
        else if (shown)
        {
            IntPtr fg = GetForegroundWindow();
            if (fg != foreground && fg != IntPtr.Zero && ProcessOf(fg) != rainmeter) change = -1;
            foreground = fg;
            if (down && !mouseWasDown)
            {
                int click = ClickedOn(rainmeter, launcher);
                if (click != 0) change = click;
            }
        }
        launcherShown = shown;
        mouseWasDown = down;
        return change;
    }

    // --- The Rainside's keys ---------------------------------------------------
    // While the Rainside has the keys (its own opened it or gave it them: it
    // keeps Generated\RainsideKeys.txt), a click outside it or another
    // program in front sends it FocusLost(), as the launcher's FocusStep.
    // Its window: the one of the size in RainsideLauncherSize.txt.
    public string SideKeysFile, SideSizeFile;
    long nextSideCheck;
    bool sideKeys, sideSent, sideMouse;
    IntPtr sideForeground, sideWindow;

    IntPtr SizedWindow(uint rainmeter, string file, bool hidden = false)
    {
        int w, h;
        try
        {
            string[] p = System.IO.File.ReadAllText(file).Trim().Split('|');
            if (p.Length < 2 || !int.TryParse(p[0], out w) || !int.TryParse(p[1], out h)) return IntPtr.Zero;
        }
        catch { return IntPtr.Zero; }
        IntPtr window = IntPtr.Zero;
        while ((window = FindWindowEx(IntPtr.Zero, window, "RainmeterMeterWindow", null)) != IntPtr.Zero)
        {
            Rect r;
            if (ProcessOf(window) != rainmeter || (!hidden && !IsWindowVisible(window)) || !GetWindowRect(window, out r)) continue;
            if (Math.Abs(r.Right - r.Left - w) <= 1 && Math.Abs(r.Bottom - r.Top - h) <= 1) return window;
        }
        return IntPtr.Zero;
    }

    void SideKeysStep(IntPtr rainmeterWindow, long now, bool down)
    {
        uint rainmeter = ProcessOf(rainmeterWindow);
        if (now >= nextSideCheck)
        {
            nextSideCheck = now + 250;
            bool on = System.IO.File.Exists(SideKeysFile);
            if (on && !sideKeys)
            {
                // just given them: only what changes from now on counts
                sideForeground = GetForegroundWindow();
                sideWindow = SizedWindow(rainmeter, SideSizeFile);
                sideSent = false;
            }
            sideKeys = on;
        }
        if (sideKeys && !sideSent)
        {
            bool lost = false;
            IntPtr fg = GetForegroundWindow();
            if (fg != sideForeground && fg != IntPtr.Zero && ProcessOf(fg) != rainmeter) lost = true;
            sideForeground = fg;
            if (down && !sideMouse && ClickedOn(rainmeter, sideWindow) < 0) lost = true;
            if (lost)
            {
                sideSent = true;
                Send(rainmeterWindow, CallTo(SideConfig, "FocusLost()"));
            }
        }
        sideMouse = down;
    }

    // --- The Rainside under a full-screen program (RainsideFullscreen) ---------
    // While it keeps Generated\RainsideScreen.txt ("<x>|<y>|<w>|<h>": its
    // monitor), a program covering that monitor in front (a game, a video)
    // sends it RainsideCovered(1), and (0) when it goes; the file written
    // again (the Rainside loaded again) tells it again.
    public string SideScreenFile;
    long nextScreenCheck, nextCovered;
    bool screenOn, covered;
    int screenX, screenY, screenW, screenH;
    DateTime screenStamp = DateTime.MinValue;

    void CoveredStep(IntPtr window, long now)
    {
        if (now >= nextScreenCheck)
        {
            nextScreenCheck = now + 2000;
            bool on = false;
            try
            {
                if (System.IO.File.Exists(SideScreenFile))
                {
                    DateTime stamp = System.IO.File.GetLastWriteTimeUtc(SideScreenFile);
                    if (stamp != screenStamp || !screenOn)
                    {
                        string[] p = System.IO.File.ReadAllText(SideScreenFile).Trim().Split('|');
                        on = p.Length >= 4 && int.TryParse(p[0], out screenX) && int.TryParse(p[1], out screenY)
                            && int.TryParse(p[2], out screenW) && int.TryParse(p[3], out screenH) && screenW > 0 && screenH > 0;
                        // (a new Rainside starts uncovered: told again)
                        if (stamp != screenStamp) covered = false;
                        screenStamp = stamp;
                    }
                    else on = true;
                }
            }
            catch { on = false; }
            screenOn = on;
        }
        if (!screenOn || now < nextCovered) return;
        nextCovered = now + 500;
        bool c = FullScreenInFront(window, screenX, screenY, screenW, screenH);
        if (c == covered) return;
        covered = c;
        Send(window, CallTo(SideConfig, "RainsideCovered(" + (c ? "1" : "0") + ")"));
    }

    // --- The Rainside's room kept free (RainsideReserve) ----------------------
    // While it keeps Generated\RainsideReserve.txt ("<side>|<x>|<y>|<w>|<h>":
    // always there, or while it is out of its edge), its window is an app
    // bar, as the taskbar: Windows keeps that room free of maximised windows. Let go when the file goes, the window
    // changes or the helper quits. A copy of the helper stopped without
    // quitting (Rainmeter ends it on a refresh of the launcher) cannot let
    // go: the next one does, without the file (also with the Rainside
    // hidden), and before taking the window again.
    [StructLayout(LayoutKind.Sequential)]
    struct AppBarData { public int Size; public IntPtr Window; public uint Callback; public uint Edge; public Rect Area; public IntPtr Param; }

    [DllImport("shell32.dll")]
    static extern UIntPtr SHAppBarMessage(uint message, ref AppBarData data);

    const uint ABM_NEW = 0, ABM_REMOVE = 1, ABM_QUERYPOS = 2, ABM_SETPOS = 3;
    public string SideReserveFile;
    IntPtr barWindow = IntPtr.Zero, freedWindow = IntPtr.Zero;
    string barLine;
    long nextBarCheck, nextFree;

    void ReserveStep(IntPtr rainmeterWindow, long now)
    {
        // (often: out of its edge, the Rainside writes the file as it comes
        // out and removes it as it goes in, and the windows make room then)
        if (now < nextBarCheck) return;
        nextBarCheck = now + 250;
        string line = null;
        try { if (System.IO.File.Exists(SideReserveFile)) line = System.IO.File.ReadAllText(SideReserveFile).Trim(); }
        catch { line = null; }
        // nothing changed: an app bar still shown, or none to free
        if (line != null && line == barLine && barWindow != IntPtr.Zero && IsWindowVisible(barWindow)) return;
        if (line == null && barWindow == IntPtr.Zero && now < nextFree) return;
        nextFree = now + 5000;
        IntPtr w = SizedWindow(ProcessOf(rainmeterWindow), SideSizeFile, line == null);
        if (barWindow != IntPtr.Zero && (line == null || w != barWindow || line != barLine)) ReleaseBar();
        if (line == null)
        {
            // (once per window: a window that is not an app bar is left as it is)
            if (w != IntPtr.Zero && w != freedWindow) FreeBar(w);
            freedWindow = w;
            return;
        }
        freedWindow = IntPtr.Zero;
        if (w == IntPtr.Zero || barWindow != IntPtr.Zero) return;
        string[] p = line.Split('|');
        int x, y, bw, bh;
        if (p.Length < 5 || !int.TryParse(p[1], out x) || !int.TryParse(p[2], out y) || !int.TryParse(p[3], out bw)
            || !int.TryParse(p[4], out bh)) return;
        uint edge = p[0] == "left" ? 0u : p[0] == "top" ? 1u : p[0] == "bottom" ? 3u : 2u;
        // (an app bar left by a stopped copy: anew, with this room)
        FreeBar(w);
        var d = new AppBarData { Size = Marshal.SizeOf(typeof(AppBarData)), Window = w };
        if (SHAppBarMessage(ABM_NEW, ref d) == UIntPtr.Zero) return;
        d.Edge = edge;
        d.Area = new Rect { Left = x, Top = y, Right = x + bw, Bottom = y + bh };
        SHAppBarMessage(ABM_QUERYPOS, ref d);
        // (moved off the taskbar, if it is on that side too: as thick as it is)
        if (edge == 0) d.Area.Right = d.Area.Left + bw;
        else if (edge == 2) d.Area.Left = d.Area.Right - bw;
        else if (edge == 1) d.Area.Bottom = d.Area.Top + bh;
        else d.Area.Top = d.Area.Bottom - bh;
        SHAppBarMessage(ABM_SETPOS, ref d);
        barWindow = w;
        barLine = line;
        if (d.Area.Left != x || d.Area.Top != y)
            Send(rainmeterWindow, CallTo(SideConfig, "RainsideAt(" + d.Area.Left + "," + d.Area.Top + ")"));
    }

    public void ReleaseBar()
    {
        if (barWindow == IntPtr.Zero) return;
        FreeBar(barWindow);
        barWindow = IntPtr.Zero;
    }

    static void FreeBar(IntPtr window)
    {
        var d = new AppBarData { Size = Marshal.SizeOf(typeof(AppBarData)), Window = window };
        SHAppBarMessage(ABM_REMOVE, ref d);
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

    // --- Docked launcher: open from the edge of the screen --------------------
    // While the skin is docked with DockEdge=1 it keeps Generated\DockEdge.txt
    // ("<side>|<x>|<y>|<w>|<h>|<delay ms>": the side and the area it is
    // docked in), the Rainside with RainsideMode=Edge its own
    // (RainsideDockEdge.txt). When the mouse rests on that edge for the delay,
    // with no button down and no full-screen program in front, Show() opens
    // it; the mouse must leave the edge before it can open it again.
    public string EdgeFile, SideEdgeFile;
    class Edge
    {
        public string File, Skin;
        public long NextCheck, Since = -1;
        public bool On, Armed = true;
        public string Side = "left";
        public int X, Y, W, H, Delay = 300;
        public DateTime Stamp = DateTime.MinValue;
    }
    Edge edge, sideEdge;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetClassName(IntPtr window, System.Text.StringBuilder name, int size);

    static void ReadEdge(Edge e)
    {
        e.On = false;
        if (!System.IO.File.Exists(e.File)) return;
        DateTime stamp = System.IO.File.GetLastWriteTimeUtc(e.File);
        string[] p = System.IO.File.ReadAllText(e.File).Trim().Split('|');
        if (p.Length < 6) return;
        e.Side = p[0].ToLowerInvariant();
        if (!int.TryParse(p[1], out e.X) || !int.TryParse(p[2], out e.Y) || !int.TryParse(p[3], out e.W)
            || !int.TryParse(p[4], out e.H) || !int.TryParse(p[5], out e.Delay)) return;
        e.Stamp = stamp;
        e.On = e.W > 0 && e.H > 0;
    }

    // A program covering the whole area in front (a game, a video): not the
    // desktop, not Rainmeter
    bool FullScreenInFront(IntPtr rainmeterWindow, int x, int y, int w, int h)
    {
        IntPtr fg = GetForegroundWindow();
        if (fg == IntPtr.Zero || ProcessOf(fg) == ProcessOf(rainmeterWindow)) return false;
        var name = new System.Text.StringBuilder(64);
        GetClassName(fg, name, name.Capacity);
        string cls = name.ToString();
        if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd") return false;
        Rect r;
        if (!GetWindowRect(fg, out r)) return false;
        return r.Left <= x && r.Top <= y && r.Right >= x + w && r.Bottom >= y + h;
    }

    void EdgeStep(Edge e, IntPtr window, long now, bool down)
    {
        if (now >= e.NextCheck)
        {
            e.NextCheck = now + 1000;
            try
            {
                if (!System.IO.File.Exists(e.File)) e.On = false;
                else if (System.IO.File.GetLastWriteTimeUtc(e.File) != e.Stamp || !e.On) ReadEdge(e);
            }
            catch { e.On = false; }
        }
        if (!e.On) return;
        Point p;
        if (!GetCursorPos(out p)) return;
        bool along = e.Side == "top" || e.Side == "bottom"
            ? p.X >= e.X && p.X < e.X + e.W
            : p.Y >= e.Y && p.Y < e.Y + e.H;
        bool at;
        if (e.Side == "right") at = p.X >= e.X + e.W - 1;
        else if (e.Side == "top") at = p.Y <= e.Y;
        else if (e.Side == "bottom") at = p.Y >= e.Y + e.H - 1;
        else at = p.X <= e.X;
        // (a cursor past the edge, on the next monitor, is not on it)
        if (e.Side == "right") at = at && p.X < e.X + e.W;
        else if (e.Side == "top") at = at && p.Y >= e.Y;
        else if (e.Side == "bottom") at = at && p.Y < e.Y + e.H;
        else at = at && p.X >= e.X;
        if (!at || !along || down)
        {
            e.Since = -1;
            if (!at || !along) e.Armed = true;
            return;
        }
        if (!e.Armed) return;
        if (e.Since < 0) { e.Since = now; return; }
        if (now - e.Since < e.Delay) return;
        e.Armed = false;
        e.Since = -1;
        if (FullScreenInFront(window, e.X, e.Y, e.W, e.H)) return;
        // opened by the mouse: the keys stay with the program in front until
        // a click on the launcher
        Send(window, CallTo(e.Skin, "Show('edge')"));
    }

    void EdgesStep(IntPtr window, long now, bool down)
    {
        if (edge == null && EdgeFile != null) edge = new Edge { File = EdgeFile, Skin = config };
        if (sideEdge == null && SideEdgeFile != null) sideEdge = new Edge { File = SideEdgeFile, Skin = SideConfig };
        if (edge != null) EdgeStep(edge, window, now, down);
        if (sideEdge != null) EdgeStep(sideEdge, window, now, down);
    }

    // --- Dashboard ---------------------------------------------------------------
    // While the skin shows the Dashboard it keeps Generated\DashOn.txt
    // ("<interval ms>|<processes 0/1>|<sensors 0/1>"): the data is collected,
    // written to DashData.txt and DashTick() tells the skin.
    public string DashFlag, DashFile;
    RaintileDash dash;
    long nextDash, nextDashCheck;
    int dashInterval = 1000;
    bool dashOn, dashProcs = true, dashSensors = true;

    // The data is collected on a thread of its own: it takes some time (the
    // processes, the GPU) and the gamepad must not wait for it. The counters
    // are made when the helper starts (PrepareDash).
    volatile bool collecting;

    public void PrepareDash()
    {
        // only for who uses a Dashboard (its data was written before)
        if (DashFlag == null || DashFile == null || !System.IO.File.Exists(DashFile)) return;
        dash = new RaintileDash();
        var d = dash;
        ThreadPool.QueueUserWorkItem(delegate { try { d.Prepare(); } catch { } });
    }

    void DashStep(IntPtr window, long now)
    {
        if (now >= nextDashCheck)
        {
            nextDashCheck = now + 100;
            // the launcher's and the Rainside's widgets (RainsideDashOn.txt):
            // the data for both, DashTick() to those that show some
            dashMain = System.IO.File.Exists(DashFlag);
            dashSide = SideDashFlag != null && System.IO.File.Exists(SideDashFlag);
            bool on = dashMain || dashSide;
            if (on && !dashOn)
            {
                try
                {
                    string[] p = System.IO.File.ReadAllText(dashMain ? DashFlag : SideDashFlag).Trim().Split('|');
                    int ms;
                    if (p.Length > 0 && int.TryParse(p[0], out ms)) dashInterval = Math.Max(250, ms);
                    dashProcs = p.Length < 2 || p[1] != "0";
                    dashSensors = p.Length < 3 || p[2] != "0";
                    int port;
                    if (p.Length > 3 && int.TryParse(p[3], out port) && port > 0 && port < 65536 && dash != null) dash.LhmPort = port;
                    dashPort = p.Length > 3 && int.TryParse(p[3], out port) && port > 0 && port < 65536 ? port : 8085;
                }
                catch { }
                nextDash = now; // right away
                dashFirst = true;
            }
            dashOn = on;
        }
        if (!dashOn || now < nextDash || collecting) return;
        // the second time soon after the first: CPU use of the processes and
        // network speed need two readings
        nextDash = now + (dashFirst ? Math.Min(300, dashInterval) : dashInterval);
        dashFirst = false;
        if (dash == null) dash = new RaintileDash();
        var d = dash;
        d.LhmPort = dashPort;
        bool procs = dashProcs, sensors = dashSensors;
        string bang = (dashMain ? Call("DashTick()") : "") + (dashSide ? CallTo(SideConfig, "DashTick()") : "");
        collecting = true;
        ThreadPool.QueueUserWorkItem(delegate
        {
            try
            {
                string data = d.Collect(procs, sensors);
                string tmp = DashFile + ".tmp";
                System.IO.File.WriteAllText(tmp, data, new System.Text.UTF8Encoding(false));
                if (System.IO.File.Exists(DashFile)) System.IO.File.Delete(DashFile);
                System.IO.File.Move(tmp, DashFile);
                Send(window, bang);
                d.RefreshGpuIfDue();
            }
            catch { }
            finally { collecting = false; }
        });
    }
    bool dashFirst, dashMain, dashSide;
    public string SideDashFlag;
    int dashPort = 8085;

    internal static void Send(IntPtr window, string bang)
    {
        IntPtr text = Marshal.StringToHGlobalUni(bang);
        try
        {
            var data = new CopyData { Data = (IntPtr)1, Size = (bang.Length + 1) * 2, Pointer = text };
            SendMessage(window, 0x004A /* WM_COPYDATA */, IntPtr.Zero, ref data);
        }
        finally { Marshal.FreeHGlobal(text); }
    }

    // --- Steam downloads -----------------------------------------------------------
    // While the launcher is open the skin keeps Generated\DownloadOn.txt (the
    // games with an update it knows of: "<appid>|<appmanifest path>" per line,
    // maybe none). Every second the helper reads what Steam wrote since the
    // last time: the new lines of logs\content_log.txt (state changes right
    // away, "update started : download <done>/<total>", "Current download
    // rate: <n> Mbps" every few seconds), which also tell about downloads
    // started meanwhile (their appmanifest is looked up in the libraries), and
    // the appmanifest of each game when it changes (BytesDownloaded, written
    // only now and then). Between two of them the bytes downloaded are
    // estimated from the rate. Written to Generated\Downloads.txt, one
    // "<appid>|<phase>|<done>|<total>|<bytes per second>|<seconds left>|<new>"
    // per line (phase: download, install, paused, idle; new: 1 for a first
    // install); OnDownloads() tells the skin, only when it changes. Nothing
    // happens while the launcher is hidden.
    public string DownloadFlag, DownloadFile;
    long nextDownload;
    bool downloadOn;
    string steamRoot, downloadsText;
    List<string> steamLibraries;
    long logPos = -1;
    string downloadingApp;
    class Dl
    {
        public string Manifest, Phase = "idle";
        public bool Found, New; // Found: seen in the log, not listed by the skin
        public DateTime ManifestTime;
        public double Done, Total, At; // At: ms of the clock when Done was right
        public double Rate; // bytes per second
    }
    Dictionary<string, Dl> downloads = new Dictionary<string, Dl>();

    static string AcfField(string text, string name)
    {
        var m = System.Text.RegularExpressions.Regex.Match(text, "\"" + name + "\"\\s+\"(\\d+)\"", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        return m.Success ? m.Groups[1].Value : null;
    }

    static string PhaseOf(string state)
    {
        if (state.IndexOf("Downloading", StringComparison.OrdinalIgnoreCase) >= 0) return "download";
        if (state.IndexOf("Suspended", StringComparison.OrdinalIgnoreCase) >= 0 || state.IndexOf("Paused", StringComparison.OrdinalIgnoreCase) >= 0) return "paused";
        if (state.Trim().Trim(',').Length == 0 || state.Trim().StartsWith("None", StringComparison.OrdinalIgnoreCase)) return "idle";
        return "install";
    }

    // What the game has done at 'when' (ms of the clock): the last value
    // read, plus the rate since then. Steam writes the rate every 10-15 s
    // while it downloads: with none for 30 s it is not going on, and the
    // estimate stops.
    static double DoneNow(Dl d, double when)
    {
        if (d.Phase != "download" || d.Rate <= 0 || d.Total <= 0) return d.Done;
        double ms = Math.Max(0, Math.Min(30000, when - d.At));
        return Math.Min(d.Total, d.Done + d.Rate * ms / 1000.0);
    }

    // Steam's folder (registry) and its libraries (libraryfolders.vdf), once
    // each time the launcher opens
    void FindSteam()
    {
        if (steamRoot != null) return;
        steamRoot = "";
        steamLibraries = new List<string>();
        try
        {
            using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam"))
            {
                string root = k != null ? k.GetValue("SteamPath") as string : null;
                if (root != null) steamRoot = root.Replace('/', '\\');
            }
        }
        catch { }
        if (steamRoot == "") return;
        steamLibraries.Add(System.IO.Path.Combine(steamRoot, "steamapps"));
        try
        {
            string vdf = System.IO.File.ReadAllText(System.IO.Path.Combine(steamRoot, @"steamapps\libraryfolders.vdf"));
            foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(vdf, "\"path\"\\s+\"([^\"]+)\""))
            {
                string lib = System.IO.Path.Combine(m.Groups[1].Value.Replace(@"\\", @"\"), "steamapps");
                if (!steamLibraries.Exists(x => string.Equals(x, lib, StringComparison.OrdinalIgnoreCase))) steamLibraries.Add(lib);
            }
        }
        catch { }
    }

    // A game the log talks about: the one the skin listed, or one found now
    // (with its appmanifest), or null
    Dl Follow(string id, bool add)
    {
        Dl d;
        if (downloads.TryGetValue(id, out d)) return d;
        if (!add || steamLibraries == null) return null;
        foreach (string lib in steamLibraries)
        {
            string acf = System.IO.Path.Combine(lib, "appmanifest_" + id + ".acf");
            if (!System.IO.File.Exists(acf)) continue;
            d = new Dl { Manifest = acf, Found = true };
            downloads[id] = d;
            return d;
        }
        return null;
    }

    void ReadSteamLog(long now)
    {
        if (steamRoot == "") return;
        string log = System.IO.Path.Combine(steamRoot, @"logs\content_log.txt");
        if (!System.IO.File.Exists(log)) return;
        string text;
        using (var f = new System.IO.FileStream(log, System.IO.FileMode.Open, System.IO.FileAccess.Read, System.IO.FileShare.ReadWrite | System.IO.FileShare.Delete))
        {
            // the first time only the end of it (what is going on now); a
            // shorter file is a new one
            if (logPos < 0 || logPos > f.Length) logPos = Math.Max(0, f.Length - 262144);
            if (f.Length == logPos) return;
            f.Position = logPos;
            var buffer = new byte[f.Length - logPos];
            int read = 0;
            while (read < buffer.Length)
            {
                int n = f.Read(buffer, read, buffer.Length - read);
                if (n <= 0) break;
                read += n;
            }
            // up to the last complete line: the rest is read next time
            int end = Array.LastIndexOf(buffer, (byte)'\n', read - 1);
            if (end < 0) return;
            logPos += end + 1;
            text = System.Text.Encoding.UTF8.GetString(buffer, 0, end + 1);
        }
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        DateTime clockNow = DateTime.Now;
        foreach (string raw in text.Split('\n'))
        {
            string line = raw.TrimEnd('\r');
            // when the line was written ("[2026-11-06 21:47:11] ..."), as ms of
            // the clock: the end of the log read when the launcher opens tells
            // what happened before, at its own time
            double at = now;
            DateTime written;
            if (line.Length > 21 && line[0] == '[' && DateTime.TryParseExact(line.Substring(1, 19), "yyyy-MM-dd HH:mm:ss", inv, System.Globalization.DateTimeStyles.None, out written))
                at = Math.Min(now, now - (clockNow - written).TotalMilliseconds);
            var m = System.Text.RegularExpressions.Regex.Match(line, @"AppID (\d+) update started : download (\d+)/(\d+)");
            Dl d;
            if (m.Success)
            {
                d = Follow(m.Groups[1].Value, true);
                if (d != null)
                {
                    d.Done = double.Parse(m.Groups[2].Value, inv);
                    d.Total = double.Parse(m.Groups[3].Value, inv);
                    d.At = at;
                }
                continue;
            }
            m = System.Text.RegularExpressions.Regex.Match(line, @"AppID (\d+) App update changed : (.*)$");
            if (m.Success)
            {
                string phase = PhaseOf(m.Groups[2].Value);
                if (phase == "download") downloadingApp = m.Groups[1].Value;
                else if (downloadingApp == m.Groups[1].Value) downloadingApp = null;
                d = Follow(m.Groups[1].Value, phase != "idle");
                if (d != null)
                {
                    d.Done = DoneNow(d, at);
                    d.At = at;
                    d.Phase = phase;
                    if (phase != "download") d.Rate = 0;
                }
                continue;
            }
            // "Current download rate: 40.025 Mbps", and the first one in
            // "Increasing target number of download connections to 5 (rate was 0.000, now 40.888)"
            m = System.Text.RegularExpressions.Regex.Match(line, @"(?:Current download rate: ([\d.]+) Mbps|\(rate was [\d.]+, now ([\d.]+)\))");
            if (m.Success && downloadingApp != null && downloads.TryGetValue(downloadingApp, out d))
            {
                d.Done = DoneNow(d, at);
                d.At = at;
                string mbps = m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value;
                d.Rate = double.Parse(mbps, inv) * 1000000.0 / 8.0;
            }
        }
    }

    // The appmanifest of a game, right when Steam rewrites it
    static void ReadManifest(Dl d, long now)
    {
        if (d.Manifest == null || !d.Manifest.EndsWith(".acf", StringComparison.OrdinalIgnoreCase) || !System.IO.File.Exists(d.Manifest)) return;
        DateTime time = System.IO.File.GetLastWriteTimeUtc(d.Manifest);
        if (time == d.ManifestTime) return;
        d.ManifestTime = time;
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        string acf = System.IO.File.ReadAllText(d.Manifest);
        string done = AcfField(acf, "BytesDownloaded"), total = AcfField(acf, "BytesToDownload");
        string flags = AcfField(acf, "StateFlags"), build = AcfField(acf, "buildid");
        d.New = build == "0";
        if (done != null && total != null)
        {
            double dn = double.Parse(done, inv);
            // never back: the estimate may already be past it
            if (d.Phase != "download" || dn > DoneNow(d, now)) { d.Done = dn; d.At = now; }
            d.Total = double.Parse(total, inv);
        }
        long f;
        if (flags == null || !long.TryParse(flags, out f)) return;
        // no update any more (UpdateRequired 2, UpdateStarted 1024): done
        if ((f & 2) == 0 && (f & 1024) == 0) { d.Phase = "idle"; d.Rate = 0; d.Done = d.Total; return; }
        // before the log says anything: UpdatePaused (512), UpdateStarted (1024)
        if (d.Phase == "idle") d.Phase = (f & 512) != 0 ? "paused" : (f & 1024) != 0 ? "download" : "idle";
    }

    void DownloadStep(IntPtr window, long now)
    {
        if (now < nextDownload) return;
        nextDownload = now + 1000;
        bool on = System.IO.File.Exists(DownloadFlag);
        if (!on)
        {
            // hidden: start again from the files next time
            if (downloadOn) { downloads.Clear(); logPos = -1; downloadingApp = null; downloadsText = null; steamRoot = null; }
            downloadOn = false;
            return;
        }
        var wanted = new Dictionary<string, string>();
        foreach (string line in System.IO.File.ReadAllLines(DownloadFlag))
        {
            string[] p = line.Split(new[] { '|' }, 2);
            if (p.Length == 2 && p[0].Trim().Length > 0) wanted[p[0].Trim()] = p[1].Trim();
        }
        // the ones the skin no longer lists go, unless found in the log
        foreach (var id in new List<string>(downloads.Keys))
            if (!wanted.ContainsKey(id) && !downloads[id].Found) downloads.Remove(id);
        foreach (var kv in wanted)
        {
            Dl d;
            if (!downloads.TryGetValue(kv.Key, out d)) { d = new Dl(); downloads[kv.Key] = d; }
            d.Manifest = kv.Value;
            d.Found = false;
        }
        bool first = !downloadOn;
        downloadOn = true;
        FindSteam();
        try { ReadSteamLog(now); } catch { }
        foreach (var d in downloads.Values) { try { ReadManifest(d, now); } catch { } }
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        var sb = new System.Text.StringBuilder();
        foreach (var kv in downloads)
        {
            Dl d = kv.Value;
            double done = DoneNow(d, now);
            double left = d.Phase == "download" && d.Rate > 0 ? Math.Max(0, d.Total - done) / d.Rate : -1;
            sb.Append(kv.Key).Append('|').Append(d.Phase).Append('|')
              .Append(Math.Floor(done).ToString(inv)).Append('|').Append(Math.Floor(d.Total).ToString(inv)).Append('|')
              .Append(Math.Floor(d.Rate).ToString(inv)).Append('|').Append(Math.Ceiling(left).ToString(inv)).Append('|')
              .Append(d.New ? '1' : '0').Append("\r\n");
        }
        string text = sb.ToString();
        if (text == downloadsText && !first) return;
        downloadsText = text;
        string tmp = DownloadFile + ".tmp";
        System.IO.File.WriteAllText(tmp, text, new System.Text.UTF8Encoding(false));
        if (System.IO.File.Exists(DownloadFile)) System.IO.File.Delete(DownloadFile);
        System.IO.File.Move(tmp, DownloadFile);
        Send(window, Call("OnDownloads()"));
    }

    // How long the loop waits before its next turn (ms). 16 while something
    // is followed closely: a controller connected (its buttons), the
    // launcher shown or the Rainside with the keys (a click elsewhere is
    // seen only while the button is down), the mouse resting on an edge that
    // opens (its delay). At rest there are only files to look at and the
    // edges to watch: 100, so the steps with a time of their own (250 ms to
    // 2 s) and the mouse reaching an edge are seen up to 100 ms later. The
    // Dashboard's data (the Rainside's widgets, always shown) is collected
    // when it is due.
    public const int ACTIVE_WAIT = 16, IDLE_WAIT = 100;

    public int Wait(bool pad, long now)
    {
        if (pad || launcherShown || (sideKeys && !sideSent)) return ACTIVE_WAIT;
        if ((edge != null && edge.Since >= 0) || (sideEdge != null && sideEdge.Since >= 0)) return ACTIVE_WAIT;
        if (dashOn && nextDash - now < IDLE_WAIT) return (int)Math.Max(ACTIVE_WAIT, nextDash - now);
        return IDLE_WAIT;
    }

    // Main loop: ends when 'quit' is signalled (a new copy started) or when
    // Rainmeter is gone.
    public void Run(WaitHandle quit)
    {
        var connected = new bool[4];
        var clock = Stopwatch.StartNew(); // does not wrap after 25 days like TickCount
        long nextScan = 0, lastRainmeter = 0;
        while (!quit.WaitOne(Wait(PadEnabled && Array.IndexOf(connected, true) >= 0, clock.ElapsedMilliseconds)))
        {
            long now = clock.ElapsedMilliseconds;
            IntPtr window = RainmeterWindow();
            if (window != IntPtr.Zero) lastRainmeter = now;
            else if (now - lastRainmeter > 10000) return;
            // (the mouse buttons: read once, for all the steps)
            bool down = window != IntPtr.Zero && MouseDown();

            if (window != IntPtr.Zero)
            {
                int focus = FocusStep(window, now, down);
                if (focus < 0) Send(window, Call("FocusLost()"));
                else if (focus > 0) Send(window, Call("FocusGained()"));
            }
            if (TrackEnabled) { try { TrackStep(now); } catch { } }
            if (DashFlag != null && window != IntPtr.Zero) { try { DashStep(window, now); } catch { } }
            if (window != IntPtr.Zero) { try { EdgesStep(window, now, down); } catch { } }
            if (SideKeysFile != null && window != IntPtr.Zero) { try { SideKeysStep(window, now, down); } catch { } }
            if (SideScreenFile != null && window != IntPtr.Zero) { try { CoveredStep(window, now); } catch { } }
            if (SideReserveFile != null && window != IntPtr.Zero) { try { ReserveStep(window, now); } catch { } }
            if (DownloadFlag != null && window != IntPtr.Zero) { try { DownloadStep(window, now); } catch { } }
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

# the libraries for LibreHardwareMonitor (WMI, the JSON of its web server),
# loaded first and given by their files
Add-Type -AssemblyName System.Management, System.Web.Extensions
$refs = @([System.Management.ManagementScope].Assembly.Location,
    [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies $refs

# Single copy: ask the previous one to quit and take its place
$quit = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\Raintile.Gamepad.Quit')
$mutex = New-Object System.Threading.Mutex($false, 'Local\Raintile.Gamepad')
[void]$quit.Set()
try { $owned = $mutex.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) { exit }
[void]$quit.Reset() # if there was no previous copy, the signal is still set

$pad = New-Object RaintilePad($Config, $DeadZone, $RepeatDelay, $RepeatRate)
$pad.SetBindings($Bindings)
# the tiles' pad shortcuts (PadKey=), written by the skin before it starts the helper
if ($Generated) {
    $padKeys = Join-Path $Generated 'PadKeys.txt'
    if (Test-Path -LiteralPath $padKeys) { $pad.SetTiles([string[]]@([IO.File]::ReadAllLines($padKeys) | Where-Object { $_.Trim() -ne '' })) }
}
$pad.PadEnabled = [bool]$Gamepad
$pad.TrackEnabled = [bool]$Track -and $Generated -and $Data
if ($Generated) {
    $pad.DashFlag = Join-Path $Generated 'DashOn.txt'
    $pad.SideDashFlag = Join-Path $Generated 'RainsideDashOn.txt'
    $pad.DashFile = Join-Path $Generated 'DashData.txt'
    $pad.EdgeFile = Join-Path $Generated 'DockEdge.txt'
    $pad.SideEdgeFile = Join-Path $Generated 'RainsideDockEdge.txt'
    $pad.SideKeysFile = Join-Path $Generated 'RainsideKeys.txt'
    $pad.SideSizeFile = Join-Path $Generated 'RainsideLauncherSize.txt'
    $pad.SideScreenFile = Join-Path $Generated 'RainsideScreen.txt'
    $pad.SideReserveFile = Join-Path $Generated 'RainsideReserve.txt'
    if ($Dash) { $pad.PrepareDash() }
    $pad.SizeFile = Join-Path $Generated 'LauncherSize.txt'
    $pad.DownloadFlag = Join-Path $Generated 'DownloadOn.txt'
    $pad.DownloadFile = Join-Path $Generated 'Downloads.txt'
}
if ($pad.TrackEnabled) {
    $pad.LaunchFile = Join-Path $Generated 'Launch.txt'
    $pad.PlayedFile = Join-Path $Data 'TimePlayed.txt'
    $pad.ExeFile = Join-Path $Data 'GameExe.txt'
}
# the keyboard (Generated\HotKeys.txt, written by the skin)
$keys = $null
if ($Generated) {
    $keys = New-Object RaintileKeys((Join-Path $Generated 'HotKeys.txt'))
    $keys.Start()
}
try { $pad.Run($quit) } finally { if ($keys) { $keys.Stop() }; $pad.ReleaseBar(); $mutex.ReleaseMutex() }
