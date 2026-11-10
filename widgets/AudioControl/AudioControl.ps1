# Audio control widget for Raintile: the sound devices of the PC (Devices)
# or the volume of each program (Mixer), as in Windows' volume mixer.
#
# Started by the widget's OnShow and running only while it is on screen: it
# reads the devices and the programs' sessions (Windows' Core Audio) every
# -Interval ms and, only when something changed, sends the rows to the
# widget's meters with WM_COPYDATA (as "Rainmeter.exe !bang" does, without a
# process each time). The widget's clicks reach it through -Cmd, an .ini the
# meters write with !WriteKeyValue ([Cmd] Do=<command>): it waits for that
# file to change, so a click is applied at once.
#
# Commands (k: the row, from 1):
#   pick k      Devices: makes the device the default one; Mixer: mute on/off
#   mute k      mute on/off
#   set k <p>   volume <p> % (0-100; the bar's $MouseX:%$)
#   up k, down k  volume +/- -Step % (also the arrows / D-pad on a row)
#   quit        exits (the widget's OnHide)
# The mode is the tile's widget setting (-Mode: Devices or Mixer), so two
# tiles can show one each. Core Audio is used from a thread of the
# multithreaded apartment (see Mta): from PowerShell's own thread the
# programs' sessions do not answer.
#
# -Probe prints what it reads (the devices, the mixer's rows, the sessions
# left out and why) and exits: to look at a PC where a row is missing.
#
# It exits too when another copy started for the same tile (Owner= in -Cmd),
# when Rainmeter is gone or when the launcher shows no widget (-Flag missing).
# The default device is set with IPolicyConfig, the interface Windows' own
# sound settings use (not documented, the same since Windows 7).

param(
    [string]$Config = 'Raintile',
    [string]$Section = '',
    [string]$Cmd = '',
    [string]$Mode = 'Devices',
    [string]$Title = '',
    [string]$Step = '5',
    [int]$Interval = 1000,
    [int]$Rows = 8,
    [string]$Flag = '',
    [string]$Text = '240,240,245,255',
    [string]$Dim = '150,150,160,255',
    [string]$Accent = '0,210,180,255',
    [switch]$Probe
)

$ErrorActionPreference = 'Stop'

# --- Helpers (pure: tested in tests/ps/AudioControl.Tests.ps1) ---------------

# Text for a meter's option inside a quoted bang argument: no quotes, no
# brackets (section variables) and no # (variables), on one line
function Get-SafeText([string]$Value) {
    if ($null -eq $Value) { return '' }
    $v = $Value -replace '[\r\n\t]', ' '
    $v = $v.Replace('"', "'").Replace('[', '(').Replace(']', ')').Replace('#', '')
    return $v.Trim()
}

# "Devices" or "Mixer" from a value of the settings (any case), or $null
function Get-AudioMode([string]$Value) {
    if ($null -eq $Value) { return $null }
    $v = $Value.Trim().ToLowerInvariant()
    if ($v -eq 'devices' -or $v -eq 'device') { return 'Devices' }
    if ($v -eq 'mixer') { return 'Mixer' }
    return $null
}

# A command of the widget: @{ Verb; Row; Value }, or $null
function ConvertFrom-AudioCommand([string]$Line) {
    if ($null -eq $Line) { return $null }
    $parts = @($Line.Trim() -split '\s+')
    if ($parts.Count -eq 0 -or $parts[0] -eq '') { return $null }
    $verb = $parts[0].ToLowerInvariant()
    if ($verb -eq 'quit' -or $verb -eq 'show') { return @{ Verb = $verb; Row = 0; Value = $null } }
    if (@('pick', 'mute', 'set', 'up', 'down') -notcontains $verb) { return $null }
    $row = 0
    if ($parts.Count -lt 2 -or -not [int]::TryParse($parts[1], [ref]$row) -or $row -lt 1) { return $null }
    $value = $null
    if ($verb -eq 'set') {
        $p = 0.0
        if ($parts.Count -lt 3 -or -not [double]::TryParse($parts[2], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$p)) { return $null }
        $value = [Math]::Max(0.0, [Math]::Min(100.0, $p))
    }
    return @{ Verb = $verb; Row = $row; Value = $value }
}

# The volume after "up"/"down" by $Step %, on the step (52 up by 5 is 55)
function Get-SteppedVolume([int]$Volume, [int]$Step, [int]$Direction) {
    if ($Step -lt 1) { $Step = 1 }
    if ($Direction -gt 0) { $v = ([Math]::Floor($Volume / $Step) + 1) * $Step }
    else { $v = ([Math]::Ceiling($Volume / $Step) - 1) * $Step }
    return [int][Math]::Max(0, [Math]::Min(100, $v))
}

# The bangs that show $Items (rows: Name, Volume, Mute, Active, Icon) in the
# widget's meters (<Prefix><Meter><k>), the title ($Title, or the mode's
# name) and what shows without rows ($Note, or the mode's), then the group
# updated and redrawn
function Format-AudioBang($Items, [string]$Mode, [string]$Prefix, [string]$Group, [string]$Config, [int]$Rows, $Colors, [string]$Title = '', [string]$Note = '') {
    $sb = New-Object System.Text.StringBuilder
    $set = {
        param($meter, $key, $value)
        [void]$sb.Append('[!SetOption "' + $Prefix + $meter + '" "' + $key + '" "' + $value + '" "' + $Config + '"]')
    }
    $count = [Math]::Min(@($Items).Count, $Rows)
    for ($k = 1; $k -le $count; $k++) {
        $it = @($Items)[$k - 1]
        & $set "Name$k" 'Text' (Get-SafeText $it.Name)
        & $set "Name$k" 'FontColor' $(if ($it.Active) { $Colors.Accent } else { $Colors.Text })
        & $set "Pct$k" 'Text' $(if ($it.Mute) { 'Muted' } else { [string]$it.Volume + '%' })
        & $set "Vol$k" 'Formula' ([string]$it.Volume)
        & $set "Bar$k" 'BarColor' $(if ($it.Mute) { $Colors.Dim } else { $Colors.Accent })
        & $set "Icon$k" 'ImageName' (Get-SafeText $it.Icon)
    }
    $mixer = $Mode -eq 'Mixer'
    & $set 'Count' 'Formula' ([string]$count)
    & $set 'IconOn' 'Formula' $(if ($mixer) { '1' } else { '0' })
    if (-not $Title) { $Title = $(if ($mixer) { 'Volume mixer' } else { 'Sound devices' }) }
    & $set 'Title' 'Text' (Get-SafeText $Title)
    if (-not $Note) { $Note = 'No sound device' }
    & $set 'Empty' 'Text' (Get-SafeText $Note)
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

# --- Core Audio ------------------------------------------------------------------

# (in $source: tests/ps/AudioControl.Tests.ps1 compiles it without running the script)
$source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace RaintileAudio
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCo { }
    [ComImport, Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9")] class PolicyConfigCo { }

    [StructLayout(LayoutKind.Sequential)]
    struct PropertyKey { public Guid Format; public int Id; }

    // (VT_LPWSTR: the pointer at 8; 24 bytes on x64)
    [StructLayout(LayoutKind.Explicit)]
    struct PropVariant
    {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(8)] public IntPtr Pointer;
        [FieldOffset(16)] public IntPtr Rest;
    }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        void EnumAudioEndpoints(int flow, int stateMask, out IMMDeviceCollection devices);
        void GetDefaultAudioEndpoint(int flow, int role, out IMMDevice device);
        void GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection
    {
        void GetCount(out int count);
        void Item(int index, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        void Activate(ref Guid iid, int context, IntPtr parameters, [MarshalAs(UnmanagedType.IUnknown)] out object result);
        void OpenPropertyStore(int access, out IPropertyStore store);
        void GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        void GetState(out int state);
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        void GetCount(out int count);
        void GetAt(int index, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropVariant value);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume
    {
        void RegisterControlChangeNotify(IntPtr notify);
        void UnregisterControlChangeNotify(IntPtr notify);
        void GetChannelCount(out int count);
        void SetMasterVolumeLevel(float db, ref Guid context);
        void SetMasterVolumeLevelScalar(float level, ref Guid context);
        void GetMasterVolumeLevel(out float db);
        void GetMasterVolumeLevelScalar(out float level);
        void SetChannelVolumeLevel(int channel, float db, ref Guid context);
        void SetChannelVolumeLevelScalar(int channel, float level, ref Guid context);
        void GetChannelVolumeLevel(int channel, out float db);
        void GetChannelVolumeLevelScalar(int channel, out float level);
        void SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);
        void GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2
    {
        void GetAudioSessionControl(IntPtr group, int flags, out IntPtr control);
        void GetSimpleAudioVolume(IntPtr group, int flags, out IntPtr volume);
        void GetSessionEnumerator(out IAudioSessionEnumerator sessions);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator
    {
        void GetCount(out int count);
        void GetSession(int index, out IntPtr session);
    }

    // A program's session (IAudioSessionControl2 and ISimpleAudioVolume),
    // called through its table of methods: the runtime's own casting of the
    // session to those interfaces fails ("no such interface") on some PCs,
    // while the session answers them (QueryInterface)
    class RawSession
    {
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetInt(IntPtr self, out int value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetPtr(IntPtr self, out IntPtr value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int NoArg(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetFloat(IntPtr self, out float value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int SetFloat(IntPtr self, float value, ref Guid context);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int SetInt(IntPtr self, int value, ref Guid context);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetChannel(IntPtr self, int channel, out float value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int SetChannel(IntPtr self, int channel, float value, ref Guid context);

        static readonly Guid Control2Id = new Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D");
        static readonly Guid SimpleVolumeId = new Guid("87CE5498-68D6-44E5-9215-6F071AE88845");
        static readonly Guid ChannelVolumeId = new Guid("1C158861-B533-4B30-B1CF-E853E51C59B8");
        static readonly Guid UnknownId = new Guid("00000000-0000-0000-C000-000000000046");
        IntPtr control, volume;
        bool channels;   // (volume is an IChannelAudioVolume: no mute)

        // (the methods' places: IUnknown 0-2; IAudioSessionControl 3 GetState,
        // 4 GetDisplayName ... 11; IAudioSessionControl2 14 GetProcessId,
        // 15 IsSystemSoundsSession; ISimpleAudioVolume 3 SetMasterVolume,
        // 4 GetMasterVolume, 5 SetMute, 6 GetMute; IChannelAudioVolume
        // 3 GetChannelCount, 4 SetChannelVolume, 5 GetChannelVolume)
        static T Method<T>(IntPtr obj, int slot) where T : class
        {
            IntPtr table = Marshal.ReadIntPtr(obj);
            return (T)(object)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(table, slot * IntPtr.Size), typeof(T));
        }

        static void Check(int hr) { if (hr < 0) Marshal.ThrowExceptionForHR(hr); }

        static int Ask(IntPtr obj, Guid id, out IntPtr result) { return Marshal.QueryInterface(obj, ref id, out result); }

        // From the session the enumerator gave (its reference is taken over);
        // null with why in 'error' when it does not answer. Its volume: from
        // the session, else from its IAudioSessionControl2 or its IUnknown
        // (one PC answered none of them from the session itself), else its
        // volume per channel. 'how' says which one answered.
        public static RawSession From(IntPtr session, out string error, out string how)
        {
            error = null;
            how = null;
            var tried = new List<string>();
            try
            {
                IntPtr c, v, u;
                int hr = Ask(session, Control2Id, out c);
                if (hr != 0) { error = "IAudioSessionControl2: 0x" + hr.ToString("X8"); return null; }
                var r = new RawSession { control = c };
                IntPtr[] from = { session, c };
                string[] names = { "session", "IAudioSessionControl2" };
                for (int k = 0; k < from.Length; k++)
                {
                    hr = Ask(from[k], SimpleVolumeId, out v);
                    if (hr == 0) { r.volume = v; how = "ISimpleAudioVolume from the " + names[k]; return r; }
                    tried.Add("ISimpleAudioVolume from the " + names[k] + ": 0x" + hr.ToString("X8"));
                }
                if (Ask(c, UnknownId, out u) == 0)
                {
                    hr = Ask(u, SimpleVolumeId, out v);
                    Marshal.Release(u);
                    if (hr == 0) { r.volume = v; how = "ISimpleAudioVolume from IUnknown"; return r; }
                    tried.Add("ISimpleAudioVolume from IUnknown: 0x" + hr.ToString("X8"));
                }
                hr = Ask(session, ChannelVolumeId, out v);
                if (hr == 0) { r.volume = v; r.channels = true; how = "IChannelAudioVolume"; return r; }
                tried.Add("IChannelAudioVolume: 0x" + hr.ToString("X8"));
                Marshal.Release(c);
                error = string.Join(", ", tried.ToArray());
                return null;
            }
            finally { Marshal.Release(session); }
        }

        public void Release()
        {
            if (control != IntPtr.Zero) Marshal.Release(control);
            if (volume != IntPtr.Zero) Marshal.Release(volume);
            control = volume = IntPtr.Zero;
        }

        public int State { get { int v; Check(Method<GetInt>(control, 3)(control, out v)); return v; } }
        public int ProcessId { get { int v; Check(Method<GetInt>(control, 14)(control, out v)); return v; } }
        public bool IsSystem { get { return Method<NoArg>(control, 15)(control) == 0; } }
        public string DisplayName
        {
            get
            {
                IntPtr p;
                if (Method<GetPtr>(control, 4)(control, out p) < 0 || p == IntPtr.Zero) return "";
                try { return Marshal.PtrToStringUni(p); }
                finally { Marshal.FreeCoTaskMem(p); }
            }
        }
        public float Level
        {
            get
            {
                float v;
                if (channels) Check(Method<GetChannel>(volume, 5)(volume, 0, out v));
                else Check(Method<GetFloat>(volume, 4)(volume, out v));
                return v;
            }
            set
            {
                Guid none = Guid.Empty;
                if (!channels) { Check(Method<SetFloat>(volume, 3)(volume, value, ref none)); return; }
                int n;
                Check(Method<GetInt>(volume, 3)(volume, out n));
                for (int k = 0; k < n; k++) Check(Method<SetChannel>(volume, 4)(volume, k, value, ref none));
            }
        }
        public bool CanMute { get { return !channels; } }
        public bool Mute
        {
            get { if (channels) return false; int v; Check(Method<GetInt>(volume, 6)(volume, out v)); return v != 0; }
            set { if (channels) return; Guid none = Guid.Empty; Check(Method<SetInt>(volume, 5)(volume, value ? 1 : 0, ref none)); }
        }
    }

    [ComImport, Guid("F8679F50-850A-41CF-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPolicyConfig
    {
        [PreserveSig] int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr format);
        [PreserveSig] int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, int defaultFormat, IntPtr format);
        [PreserveSig] int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id);
        [PreserveSig] int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr format, IntPtr mix);
        [PreserveSig] int GetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string id, int defaultPeriod, IntPtr period, IntPtr min);
        [PreserveSig] int SetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr period);
        [PreserveSig] int GetShareMode([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr mode);
        [PreserveSig] int SetShareMode([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr mode);
        [PreserveSig] int GetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr key, IntPtr value);
        [PreserveSig] int SetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr key, IntPtr value);
        [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role);
    }

    public class Item
    {
        public string Key = "", Name = "", Exe = "", Icon = "";
        public int Volume;
        public bool Mute, Active;
    }

    public static class Audio
    {
        const int Render = 0, Console = 0, Multimedia = 1, Active = 1, All = 23;
        static readonly Guid EndpointVolumeId = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
        static readonly Guid SessionManagerId = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
        static readonly Guid FriendlyNameFormat = new Guid("A45C254E-DF1C-4EFD-8020-67D146A850E0");
        static Guid NoContext = Guid.Empty;

        [DllImport("ole32.dll")] static extern int PropVariantClear(ref PropVariant value);
        [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(int access, bool inherit, int pid);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder name, ref int size);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string className, string windowName);
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wParam, ref CopyData data);

        [StructLayout(LayoutKind.Sequential)]
        struct CopyData { public IntPtr Data; public int Size; public IntPtr Pointer; }

        static IMMDeviceEnumerator Enumerator() { return (IMMDeviceEnumerator)new MMDeviceEnumeratorCo(); }

        static object Activate(IMMDevice device, Guid id, int context = All)
        {
            object result;
            device.Activate(ref id, context, IntPtr.Zero, out result);
            return result;
        }

        static string DeviceName(IMMDevice device)
        {
            IPropertyStore store;
            device.OpenPropertyStore(0, out store);
            var key = new PropertyKey { Format = FriendlyNameFormat, Id = 14 };
            PropVariant value;
            store.GetValue(ref key, out value);
            try { return value.Type == 31 && value.Pointer != IntPtr.Zero ? Marshal.PtrToStringUni(value.Pointer) : ""; }
            finally { PropVariantClear(ref value); }
        }

        static IMMDevice Default(IMMDeviceEnumerator en, int role)
        {
            IMMDevice device;
            try { en.GetDefaultAudioEndpoint(Render, role, out device); return device; }
            catch (COMException) { return null; }   // (no device)
        }

        static Item DeviceItem(IMMDevice device, string defaultId)
        {
            string id;
            device.GetId(out id);
            var volume = (IAudioEndpointVolume)Activate(device, EndpointVolumeId);
            float level;
            bool mute;
            volume.GetMasterVolumeLevelScalar(out level);
            volume.GetMute(out mute);
            return new Item { Key = id, Name = DeviceName(device), Volume = (int)Math.Round(level * 100), Mute = mute, Active = id == defaultId };
        }

        // The playback devices that are on, the default one Active
        static List<Item> DevicesNow()
        {
            var list = new List<Item>();
            var en = Enumerator();
            string defaultId = null;
            IMMDevice def = Default(en, Console);
            if (def != null) def.GetId(out defaultId);
            IMMDeviceCollection devices;
            en.EnumAudioEndpoints(Render, Active, out devices);
            int count;
            devices.GetCount(out count);
            for (int i = 0; i < count; i++)
            {
                IMMDevice device;
                devices.Item(i, out device);
                try { list.Add(DeviceItem(device, defaultId)); }
                catch (COMException) { }   // (gone meanwhile)
            }
            return list;
        }

        static IAudioEndpointVolume DeviceVolume(string id)
        {
            IMMDevice device;
            Enumerator().GetDevice(id, out device);
            return (IAudioEndpointVolume)Activate(device, EndpointVolumeId);
        }

        static void SetDefaultNow(string id)
        {
            var policy = (IPolicyConfig)new PolicyConfigCo();
            Marshal.ThrowExceptionForHR(policy.SetDefaultEndpoint(id, Console));
            Marshal.ThrowExceptionForHR(policy.SetDefaultEndpoint(id, Multimedia));
        }

        static void SetDeviceVolumeNow(string id, int percent)
        {
            var v = DeviceVolume(id);
            v.SetMasterVolumeLevelScalar(Math.Max(0, Math.Min(100, percent)) / 100f, ref NoContext);
            v.SetMute(false, ref NoContext);
        }

        static void SetDeviceMuteNow(string id, bool mute)
        {
            DeviceVolume(id).SetMute(mute, ref NoContext);
        }

        static string ProcessPath(int pid)
        {
            IntPtr h = OpenProcess(0x1000 /* PROCESS_QUERY_LIMITED_INFORMATION */, false, pid);
            if (h == IntPtr.Zero) return null;
            try
            {
                var sb = new StringBuilder(1024);
                int size = sb.Capacity;
                return QueryFullProcessImageName(h, 0, sb, ref size) ? sb.ToString(0, size) : null;
            }
            finally { CloseHandle(h); }
        }

        class Session { public string Key, Name, Exe; public bool System; public RawSession Volume; }

        static void Free(List<Session> list) { foreach (Session s in list) s.Volume.Release(); }

        // The sessions of the default device's programs (not those ended),
        // keyed by program: a program's sessions (a browser has several) are one
        static List<Session> Sessions()
        {
            var list = new List<Session>();
            IMMDevice device = Default(Enumerator(), Multimedia);
            if (device == null) return list;
            // (in this process first: through another one, a session may not
            // give every interface)
            IAudioSessionManager2 manager;
            try { manager = (IAudioSessionManager2)Activate(device, SessionManagerId, 1 /* CLSCTX_INPROC_SERVER */); }
            catch (Exception) { manager = (IAudioSessionManager2)Activate(device, SessionManagerId); }
            IAudioSessionEnumerator sessions;
            manager.GetSessionEnumerator(out sessions);
            int count;
            sessions.GetCount(out count);
            Skipped.Clear();
            for (int i = 0; i < count; i++)
            {
                RawSession raw = null;
                try
                {
                    IntPtr session;
                    sessions.GetSession(i, out session);
                    string why, how;
                    raw = RawSession.From(session, out why, out how);
                    if (raw == null) { Skipped.Add(i + ": left out: " + why); continue; }
                    Skipped.Add(i + ": volume through " + how);
                    if (raw.State == 2) { raw.Release(); continue; }   // (expired)
                    var s = new Session { Volume = raw, System = raw.IsSystem };
                    if (s.System) { s.Key = "system"; s.Name = "System sounds"; s.Exe = ""; }
                    else
                    {
                        int pid = raw.ProcessId;
                        s.Exe = ProcessPath(pid);
                        if (s.Exe == null) { Skipped.Add(i + ": left out: process " + pid + " not readable"); raw.Release(); continue; }   // (the program is gone)
                        s.Key = s.Exe.ToLowerInvariant();
                        string name = raw.DisplayName;
                        // (a name of the program's resources, "@%SystemRoot%\...": its description instead)
                        if (string.IsNullOrEmpty(name) || name.StartsWith("@"))
                        {
                            try { name = FileVersionInfo.GetVersionInfo(s.Exe).FileDescription; }
                            catch (Exception) { name = null; }
                        }
                        if (string.IsNullOrEmpty(name)) name = System.IO.Path.GetFileNameWithoutExtension(s.Exe);
                        s.Name = name.Trim();
                    }
                    list.Add(s);
                    raw = null;
                }
                catch (Exception e)
                {
                    Skipped.Add(i + ": left out: " + e.Message);
                    if (raw != null) raw.Release();
                }
            }
            return list;
        }

        // Mixer: the default device first (its volume), then System sounds,
        // then the programs by name
        static List<Item> MixerNow()
        {
            var list = new List<Item>();
            var en = Enumerator();
            IMMDevice def = Default(en, Multimedia);
            if (def == null) return list;
            string id;
            def.GetId(out id);
            Item master = DeviceItem(def, id);
            master.Key = "device:" + id;
            master.Active = false;
            list.Add(master);
            var programs = new Dictionary<string, Item>();
            var sessions = Sessions();
            try
            {
                foreach (Session s in sessions)
                {
                    if (programs.ContainsKey(s.Key)) continue;
                    programs[s.Key] = new Item { Key = s.Key, Name = s.Name, Exe = s.Exe, Volume = (int)Math.Round(s.Volume.Level * 100), Mute = s.Volume.Mute };
                }
            }
            finally { Free(sessions); }
            var apps = new List<Item>(programs.Values);
            apps.Sort(delegate (Item a, Item b)
            {
                if ((a.Key == "system") != (b.Key == "system")) return a.Key == "system" ? -1 : 1;
                return string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase);
            });
            list.AddRange(apps);
            return list;
        }

        // Volume (percent >= 0) or mute (percent < 0: mute) of a row of Mixer
        static void SetProgramNow(string key, int percent, bool mute)
        {
            if (key.StartsWith("device:"))
            {
                if (percent >= 0) SetDeviceVolumeNow(key.Substring(7), percent);
                else SetDeviceMuteNow(key.Substring(7), mute);
                return;
            }
            var sessions = Sessions();
            try
            {
                foreach (Session s in sessions)
                {
                    if (s.Key != key) continue;
                    if (percent >= 0)
                    {
                        s.Volume.Level = Math.Max(0, Math.Min(100, percent)) / 100f;
                        s.Volume.Mute = false;
                    }
                    else s.Volume.Mute = mute;
                }
            }
            finally { Free(sessions); }
        }

        // Core Audio from a thread of the multithreaded apartment, as it asks
        // (PowerShell's own thread is single-threaded)
        static T Mta<T>(Func<T> work)
        {
            if (Thread.CurrentThread.GetApartmentState() == ApartmentState.MTA) return work();
            T result = default(T);
            Exception error = null;
            var thread = new Thread(() => { try { result = work(); } catch (Exception e) { error = e; } });
            thread.SetApartmentState(ApartmentState.MTA);
            thread.Start();
            thread.Join();
            if (error != null) throw error;
            return result;
        }

        public static List<Item> Devices() { return Mta(() => DevicesNow()); }
        public static List<Item> Mixer() { return Mta(() => MixerNow()); }
        public static void SetDefault(string id) { Mta(() => { SetDefaultNow(id); return 0; }); }
        public static void SetDeviceVolume(string id, int percent) { Mta(() => { SetDeviceVolumeNow(id, percent); return 0; }); }
        public static void SetDeviceMute(string id, bool mute) { Mta(() => { SetDeviceMuteNow(id, mute); return 0; }); }
        public static void SetProgram(string key, int percent, bool mute) { Mta(() => { SetProgramNow(key, percent, mute); return 0; }); }

        // What the last Mixer() did with each session: left out and why, or
        // how its volume is reached (AudioControl.ps1 -Probe)
        public static List<string> Skipped = new List<string>();

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

        public static bool RainmeterRunning() { return FindWindow("DummyRainWClass", null) != IntPtr.Zero; }
    }
}
'@
Add-Type -TypeDefinition $source -Language CSharp
Add-Type -AssemblyName System.Drawing

# --- The widget ------------------------------------------------------------------

# Prefix of the widget's sections in the launcher (CW11_Server: CW11_) and
# the group of its measures and meters (CW11)
$prefix = $Section -replace 'Server$', ''
$group = $prefix.TrimEnd('_')
$colors = @{ Text = $Text; Dim = $Dim; Accent = $Accent }
$stepValue = 5
if (-not [int]::TryParse($Step, [ref]$stepValue) -or $stepValue -lt 1) { $stepValue = 5 }
$utf8 = New-Object System.Text.UTF8Encoding $false

# The mode: the tile's widget setting
$mode = Get-AudioMode $Mode
if (-not $mode) { $mode = 'Devices' }

if ($Probe) {
    foreach ($m in 'Devices', 'Mixer') {
        Write-Output "$m`:"
        try {
            $list = $(if ($m -eq 'Mixer') { [RaintileAudio.Audio]::Mixer() } else { [RaintileAudio.Audio]::Devices() })
            foreach ($it in $list) { Write-Output ("  {0} | {1}% | muted {2} | default {3} | {4}" -f $it.Name, $it.Volume, $it.Mute, $it.Active, $it.Exe) }
        } catch { Write-Output "  error: $($_.Exception.Message)" }
    }
    foreach ($why in [RaintileAudio.Audio]::Skipped) { Write-Output "  session $why" }
    exit 0
}

# This copy owns the tile: an older one still running exits when it reads it
$cmdDir = Split-Path -Parent $Cmd
$tmp = "$Cmd.tmp"
[IO.File]::WriteAllText($tmp, "[Cmd]`r`nOwner=$PID`r`nDo=`r`n", $utf8)
if (Test-Path -LiteralPath $Cmd) { Remove-Item -LiteralPath $Cmd -Force }
Move-Item -LiteralPath $tmp -Destination $Cmd
$cmdStamp = (Get-Item -LiteralPath $Cmd).LastWriteTimeUtc

# Programs' icons, once per program, in icons\ of the widget's folder
$iconDir = Join-Path $cmdDir 'icons'
function Get-ProgramIcon([string]$Exe) {
    if (-not $Exe) { return '' }
    $name = ([IO.Path]::GetFileNameWithoutExtension($Exe) -replace '[^A-Za-z0-9._-]', '_') + '.png'
    $path = Join-Path $iconDir $name
    if (Test-Path -LiteralPath $path) { return $path }
    try {
        if (-not (Test-Path -LiteralPath $iconDir)) { New-Item -ItemType Directory -Path $iconDir | Out-Null }
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($Exe)
        if (-not $icon) { return '' }
        $bmp = $icon.ToBitmap()
        $part = "$path.tmp"
        $bmp.Save($part, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose(); $icon.Dispose()
        Move-Item -LiteralPath $part -Destination $path -Force
        return $path
    } catch { return '' }   # (a program of the Store, or one not readable: no icon)
}

function Read-Items {
    if ($mode -eq 'Mixer') {
        $list = [RaintileAudio.Audio]::Mixer()
        foreach ($it in $list) { $it.Icon = Get-ProgramIcon $it.Exe }
        return , $list
    }
    return , [RaintileAudio.Audio]::Devices()
}

function Invoke-AudioCommand($c) {
    $it = $null
    if ($c.Row -ge 1 -and $c.Row -le @($script:items).Count) { $it = @($script:items)[$c.Row - 1] }
    if (-not $it) { return }
    $device = $mode -eq 'Devices'
    switch ($c.Verb) {
        'pick' {
            if ($device) { [RaintileAudio.Audio]::SetDefault($it.Key) }
            else { [RaintileAudio.Audio]::SetProgram($it.Key, -1, -not $it.Mute) }
        }
        'mute' {
            if ($device) { [RaintileAudio.Audio]::SetDeviceMute($it.Key, -not $it.Mute) }
            else { [RaintileAudio.Audio]::SetProgram($it.Key, -1, -not $it.Mute) }
        }
        default {
            if ($c.Verb -eq 'set') { $v = [int][Math]::Round($c.Value) }
            elseif ($c.Verb -eq 'up') { $v = Get-SteppedVolume $it.Volume $stepValue 1 }
            else { $v = Get-SteppedVolume $it.Volume $stepValue -1 }
            if ($device) { [RaintileAudio.Audio]::SetDeviceVolume($it.Key, $v) }
            else { [RaintileAudio.Audio]::SetProgram($it.Key, $v, $false) }
        }
    }
}

$watcher = New-Object IO.FileSystemWatcher $cmdDir, (Split-Path -Leaf $Cmd)
$watcher.NotifyFilter = [IO.NotifyFilters]'LastWrite, Size, FileName'
$script:items = @()
$last = $null
$wait = 0
while ($true) {
    if ($wait -gt 0) { [void]$watcher.WaitForChanged([IO.WatcherChangeTypes]::All, $wait) }
    $wait = [Math]::Max(250, $Interval)
    if (-not [RaintileAudio.Audio]::RainmeterRunning()) { exit 0 }
    if ($Flag -and -not (Test-Path -LiteralPath $Flag)) { exit 0 }
    # a command: the file is newer (checked also without an event, in case
    # one was missed while the last one was applied)
    if (Test-Path -LiteralPath $Cmd) {
        $stamp = (Get-Item -LiteralPath $Cmd).LastWriteTimeUtc
        if ($stamp -ne $cmdStamp) {
            $cmdStamp = $stamp
            $file = Read-CommandFile $Cmd
            if ($file.Owner -and $file.Owner -ne [string]$PID) { exit 0 }
            $c = ConvertFrom-AudioCommand $file.Do
            if ($c -and $c.Verb -eq 'quit') { exit 0 }
            if ($c -and $c.Verb -ne 'show') {
                try { Invoke-AudioCommand $c } catch { }   # (a device gone meanwhile: the next read shows it)
            }
        }
    }
    $note = ''
    try { $script:items = Read-Items }
    catch { $script:items = @(); $note = Get-SafeText ('Sound not readable: ' + $_.Exception.Message) }
    $key = $note + '|' + (($script:items | ForEach-Object { $_.Key + '=' + $_.Name + '=' + $_.Volume + '=' + $_.Mute + '=' + $_.Active + '=' + $_.Icon }) -join ';')
    if ($key -ne $last) {
        $last = $key
        if (-not [RaintileAudio.Audio]::Send((Format-AudioBang $script:items $mode $prefix $group $Config $Rows $colors $Title $note))) { exit 0 }
    }
}
