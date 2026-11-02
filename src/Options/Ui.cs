// Raintile Options: start, small helpers to build elements, dialogs.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace RaintileOptions
{
    static class Win32
    {
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hdc);
        [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int index);
    }

    static class Program
    {
        // Arguments as in Options.ps1: -Resources <dir> -Data <dir> -Config <name> -Page <page>
        [STAThread]
        static int Main(string[] args)
        {
            var clock = Stopwatch.StartNew();
            string resources = null, data = "", config = "Raintile", page = "";
            for (int i = 0; i + 1 < args.Length; i++)
            {
                string a = args[i].TrimStart('-', '/').ToLowerInvariant();
                if (a == "resources") resources = args[++i];
                else if (a == "data") data = args[++i];
                else if (a == "config") config = args[++i];
                else if (a == "page" || a == "openpage") page = args[++i];
            }
            if (resources == null)
            {
                // next to the skin: <skin>\@Resources\Scripts\ or <skin>\@Resources\Bin\
                string exeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
                resources = Path.GetDirectoryName(exeDir);
            }
            try
            {
                Core.Init(resources, data, config);
                var app = new OptionsApp(page, clock);
                return app.Run();
            }
            catch (Exception e)
            {
                OptionsApp.WriteErrorLog(e.ToString());
                MessageBox.Show("Error in the Options window:\r\n\r\n" + e.Message, "Raintile");
                return 1;
            }
        }
    }

    public partial class OptionsApp
    {
        Application app;
        Window win;
        readonly string openPage;
        readonly Stopwatch startClock;
        readonly List<string> startSteps = new List<string>();
        bool firstShown;

        public OptionsApp(string page, Stopwatch clock)
        {
            openPage = page ?? "";
            startClock = clock;
        }

        void AddStartStep(string name)
        {
            startSteps.Add(string.Format("{0,6} ms  {1}", startClock.ElapsedMilliseconds, name));
        }

        public static void WriteErrorLog(string msg)
        {
            try { File.WriteAllText(Path.Combine(Core.Generated ?? ".", "Options.log"), msg, Core.Utf8); } catch { }
        }

        // --- Helpers -----------------------------------------------------------------

        public object Res(string name) { return app.Resources[name]; }
        public Style ResStyle(string name) { return (Style)app.Resources[name]; }
        public Brush ResBrush(string name) { return (Brush)app.Resources[name]; }

        public static Thickness T(double a) { return new Thickness(a); }
        public static Thickness T(double a, double b) { return new Thickness(a, b, a, b); }
        public static Thickness T(double a, double b, double c, double d) { return new Thickness(a, b, c, d); }

        public TextBlock NewText(string text, double size = 13, Brush brush = null, bool bold = false, bool wrap = false)
        {
            var t = new TextBlock { Text = text ?? "", FontSize = size };
            if (brush != null) t.Foreground = brush;
            if (bold) t.FontWeight = FontWeights.SemiBold;
            if (wrap) t.TextWrapping = TextWrapping.Wrap;
            return t;
        }

        public TextBlock NewGlyph(int code, double size = 14)
        {
            var t = NewText(((char)code).ToString(), size);
            t.FontFamily = new FontFamily("Segoe MDL2 Assets");
            t.VerticalAlignment = VerticalAlignment.Center;
            return t;
        }

        public Button NewButton(string text, string style = "", string tip = "")
        {
            var b = new Button { Content = text };
            if (!string.IsNullOrEmpty(style)) b.Style = ResStyle(style);
            if (!string.IsNullOrEmpty(tip)) b.ToolTip = tip;
            return b;
        }

        public Button NewIconButton(int glyph, string tip)
        {
            return NewButton(((char)glyph).ToString(), "IconButton", tip);
        }

        public static StackPanel NewPanel(Orientation o = Orientation.Vertical)
        {
            return new StackPanel { Orientation = o };
        }

        public static T2 AddTo<T2>(Panel panel, T2 child) where T2 : UIElement
        {
            panel.Children.Add(child);
            return child;
        }

        public static Grid NewGrid(params string[] columns)
        {
            var g = new Grid();
            foreach (var w in columns)
            {
                var cd = new ColumnDefinition();
                if (w == "*") cd.Width = new GridLength(1, GridUnitType.Star);
                else if (w == "Auto") cd.Width = GridLength.Auto;
                else cd.Width = new GridLength(double.Parse(w, System.Globalization.CultureInfo.InvariantCulture));
                g.ColumnDefinitions.Add(cd);
            }
            return g;
        }

        public static void SetCol(UIElement e, int col) { Grid.SetColumn(e, col); }

        public static SolidColorBrush NewColorBrush(string text, bool opaque = false)
        {
            var v = Core.ColorFromText(text);
            if (v == null) return null;
            byte a = (byte)(opaque || v.Length < 4 ? 255 : Clamp255(v[3]));
            var brush = new SolidColorBrush(Color.FromArgb(a, (byte)Clamp255(v[0]), (byte)Clamp255(v[1]), (byte)Clamp255(v[2])));
            brush.Freeze();
            return brush;
        }

        static int Clamp255(int v) { return Math.Max(0, Math.Min(255, v)); }

        // Image without locking the file; decoded small for thumbnails
        public static BitmapImage GetBitmap(string path, int width = 0)
        {
            if (string.IsNullOrEmpty(path)) return null;
            try
            {
                var b = new BitmapImage();
                b.BeginInit();
                b.CacheOption = BitmapCacheOption.OnLoad;
                b.CreateOptions = BitmapCreateOptions.IgnoreImageCache;
                b.UriSource = new Uri(path);
                if (width > 0) b.DecodePixelWidth = width;
                b.EndInit();
                b.Freeze();
                return b;
            }
            catch { return null; }
        }

        public string SelectFile(string filter)
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Filter = filter };
            return dlg.ShowDialog(win) == true ? dlg.FileName : null;
        }

        public const string ImageFilter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.ico|All files|*.*";

        // Windows colour picker; returns the colour in the format of 'old', or null
        public string SelectColor(string old)
        {
            using (var dlg = new System.Windows.Forms.ColorDialog { FullOpen = true })
            {
                var v = Core.ColorFromText(old);
                if (v != null) dlg.Color = System.Drawing.Color.FromArgb(255, Clamp255(v[0]), Clamp255(v[1]), Clamp255(v[2]));
                if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK) return null;
                return Core.FormatPickedColor(old, dlg.Color.R, dlg.Color.G, dlg.Color.B);
            }
        }

        public static void RemoveToRecycleBin(string path)
        {
            Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile(path, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs,
                Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
        }

        // Dark title bar (Windows 10 2004+ / 11)
        public static void SetDarkTitle(Window w)
        {
            try
            {
                var h = new WindowInteropHelper(w).Handle;
                int on = 1;
                foreach (int attr in new[] { 20, 19 }) if (Win32.DwmSetWindowAttribute(h, attr, ref on, 4) == 0) break;
            }
            catch { }
        }

        // Resolution of the main screen in real pixels (for px <-> % conversion)
        static int[] GetScreenPixels()
        {
            var dc = Win32.GetDC(IntPtr.Zero);
            try { return new[] { Win32.GetDeviceCaps(dc, 118), Win32.GetDeviceCaps(dc, 117) }; }
            finally { Win32.ReleaseDC(IntPtr.Zero, dc); }
        }

        public class DialogResultInfo { public string Button; public string Text; }

        // Dialog in the window's style: message, optional text field, buttons (the
        // first is the default)
        public DialogResultInfo ShowDialog(string title, string message, string[] buttons = null, string inputText = null)
        {
            if (buttons == null) buttons = new[] { "OK" };
            var d = new Window
            {
                Title = title, Owner = win, WindowStartupLocation = WindowStartupLocation.CenterOwner,
                SizeToContent = SizeToContent.WidthAndHeight, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false,
                Background = ResBrush("CardBg"), Foreground = ResBrush("TextBrush"),
                FontFamily = new FontFamily("Segoe UI"), FontSize = 13,
            };
            if (win == null || !win.IsLoaded) { d.Owner = null; d.WindowStartupLocation = WindowStartupLocation.CenterScreen; }
            string result = null;
            d.SourceInitialized += (s, e) => SetDarkTitle(d);
            var sp = NewPanel();
            sp.Margin = T(24, 20, 24, 18);
            sp.MinWidth = 380;
            sp.MaxWidth = 520;
            d.Content = sp;
            AddTo(sp, NewText(message, 13.5, null, false, true));
            TextBox tb = null;
            if (inputText != null)
            {
                tb = new TextBox { Text = inputText, Margin = T(0, 14, 0, 0) };
                AddTo(sp, tb);
            }
            var bar = NewPanel(Orientation.Horizontal);
            bar.HorizontalAlignment = HorizontalAlignment.Right;
            bar.Margin = T(0, 20, 0, 0);
            AddTo(sp, bar);
            for (int i = 0; i < buttons.Length; i++)
            {
                var b = NewButton(buttons[i], i == 0 ? "AccentButton" : "");
                b.Margin = T(8, 0, 0, 0);
                b.MinWidth = 90;
                string label = buttons[i];
                if (i == 0) b.IsDefault = true;
                b.Click += (s, e) => { result = label; d.Close(); };
                AddTo(bar, b);
            }
            d.KeyDown += (s, e) => { if (e.Key == System.Windows.Input.Key.Escape) d.Close(); };
            if (tb != null) d.ContentRendered += (s, e) => { tb.Focus(); tb.SelectAll(); };
            d.ShowDialog();
            return new DialogResultInfo { Button = result, Text = tb != null ? tb.Text.Trim() : null };
        }

        // Sends a bang to Rainmeter (Rainmeter.exe !Bang ...)
        public static void InvokeRainmeter(string bang)
        {
            try
            {
                string exe = null;
                foreach (var p in Process.GetProcessesByName("Rainmeter"))
                {
                    try { exe = p.MainModule.FileName; break; } catch { }
                }
                if (exe == null) exe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Rainmeter", "Rainmeter.exe");
                if (File.Exists(exe)) Process.Start(new ProcessStartInfo(exe, bang) { UseShellExecute = false });
            }
            catch { }
        }

        public static void OpenUrl(string url)
        {
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
        }

        // A PowerShell script of the skin, hidden; returns the process
        public static Process StartScript(string script, string arguments)
        {
            string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
            var psi = new ProcessStartInfo(ps, "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + Path.Combine(Core.ScriptsDir, script) + "\" " + arguments)
            {
                UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden,
            };
            return Process.Start(psi);
        }

        // "C:\x\" as an argument: the trailing backslash would escape the quote
        public static string Arg(string path)
        {
            return "\"" + (path ?? "").TrimEnd('\\') + "\"";
        }
    }
}
