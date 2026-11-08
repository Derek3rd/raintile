// Raintile Options: the preview window. The launcher as the settings shape it
// (mode, docked side, sizes, margins, colours) on the main screen, with the
// tiles of a category: the grid (ScrollMode=Grid) or the wheel (Wheel, drawn
// by WheelPreview.cs). A window of its own, anchored to the right side of the
// Options window (or its left, when there is no room), shown on every page
// and opened or closed with the Preview button at the bottom. Moved or sized
// by hand it lets go of Options and stays where it was put, the next time
// too, until Attach puts it back beside Options. It follows the
// category open in the Categories page and every change of a setting or of
// a tile, before saving. The mouse wheel scrolls it (turns the wheel).

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace RaintileOptions
{
    public partial class OptionsApp
    {
        Window previewWin;
        Button btnPreview;
        Button btnAttach;
        int gridScroll; // first line shown in the grid preview
        // moved or sized by hand: where it was put (null: beside Options)
        Rect? previewFree;
        bool previewWanted = true, previewMax;

        // open by default; the choice and the place are kept for the next
        // time: "1" or "0", then "x y w h" when it was let go of Options, then
        // "max" when it was maximized (x y w h: where it goes back to)
        static string PreviewStateFile { get { return System.IO.Path.Combine(Core.Generated, "OptionsPreview.txt"); } }
        void LoadPreviewState()
        {
            try
            {
                if (!File.Exists(PreviewStateFile)) return;
                var p = File.ReadAllText(PreviewStateFile).Trim().Split(' ');
                previewWanted = p[0] != "0";
                double x, y, w, h;
                var inv = System.Globalization.CultureInfo.InvariantCulture;
                previewMax = p.Length == 6 && p[5] == "max";
                if (p.Length >= 5 && double.TryParse(p[1], System.Globalization.NumberStyles.Float, inv, out x)
                    && double.TryParse(p[2], System.Globalization.NumberStyles.Float, inv, out y)
                    && double.TryParse(p[3], System.Globalization.NumberStyles.Float, inv, out w)
                    && double.TryParse(p[4], System.Globalization.NumberStyles.Float, inv, out h) && w > 50 && h > 50)
                {
                    // a screen that is not there any more: back beside Options
                    var screen = new Rect(SystemParameters.VirtualScreenLeft, SystemParameters.VirtualScreenTop,
                        SystemParameters.VirtualScreenWidth, SystemParameters.VirtualScreenHeight);
                    var r = new Rect(x, y, w, h);
                    r.Intersect(screen);
                    if (!r.IsEmpty && r.Width >= 50 && r.Height >= 50) previewFree = new Rect(x, y, w, h);
                }
            }
            catch { }
        }
        void SavePreviewState()
        {
            var inv = System.Globalization.CultureInfo.InvariantCulture;
            string text = previewWanted ? "1" : "0";
            if (previewFree.HasValue)
            {
                var r = previewFree.Value;
                text += string.Format(inv, " {0:0} {1:0} {2:0} {3:0}", r.X, r.Y, r.Width, r.Height);
                if (previewMax) text += " max";
            }
            try { File.WriteAllText(PreviewStateFile, text); } catch { }
        }

        void InitPreview()
        {
            btnPreview = (Button)win.FindName("BtnPreview");
            LoadPreviewState();
            btnPreview.Click += (s, e) =>
            {
                previewWanted = previewWin == null;
                SavePreviewState();
                if (previewWanted) OpenPreview(); else ClosePreview();
            };
            win.LocationChanged += (s, e) => PlacePreview();
            win.SizeChanged += (s, e) => PlacePreview();
            // (minimized with Options and back by Windows itself: an owned window.
            // Shown again by hand it failed once maximized, as it is not activated.)
            win.StateChanged += (s, e) => PlacePreview();
            win.Closed += (s, e) => { if (previewWin != null) previewWin.Close(); };
            win.ContentRendered += (s, e) => { if (previewWin == null && previewWanted) OpenPreview(); };
        }

        void OpenPreview()
        {
            if (previewWin != null) return;
            var w = new Window
            {
                Title = "Raintile - Preview", Owner = win, ShowInTaskbar = false, ResizeMode = ResizeMode.CanResize,
                WindowStyle = WindowStyle.ToolWindow, Background = ResBrush("WindowBg") ?? ResBrush("CardBg"),
                Foreground = ResBrush("TextBrush"), ShowActivated = false,
            };
            var root = new DockPanel { Margin = Gap.Dialog };
            // the category shown: the one open in the Categories page, or chosen here
            var head = NewPanel(Orientation.Horizontal);
            head.Margin = T(0, 0, 0, Gap.Control);
            DockPanel.SetDock(head, Dock.Top);
            var lbl = NewText("Category", Fs.Label);
            lbl.VerticalAlignment = VerticalAlignment.Center;
            lbl.Margin = T(0, 0, Gap.Control, 0);
            wheelCatBox = new ComboBox { MinWidth = FieldWidth.M, Height = FieldHeight };
            wheelCatBox.SelectionChanged += (s, e) =>
            {
                if (wheelCatBox.SelectedIndex < 0 || wheelCatBox.SelectedIndex == wheelCatIdx) return;
                SetWheelCategory(wheelCatBox.SelectedIndex);
            };
            AddTo(head, lbl); AddTo(head, wheelCatBox);
            // let go of Options (moved or sized by hand): back beside it
            btnAttach = NewButton("Attach", "", "Put the preview back beside the Options window, following it.");
            btnAttach.Click += (s, e) =>
            {
                previewFree = null;
                previewMax = false;
                if (previewWin.WindowState != WindowState.Normal) previewWin.WindowState = WindowState.Normal;
                SavePreviewState(); UpdateAttachButton(); PlacePreview();
            };
            root.Children.Add(head);
            // at the bottom: the hint, and Attach on the right
            var foot = new DockPanel { Margin = T(0, Gap.Control, 0, 0) };
            DockPanel.SetDock(foot, Dock.Bottom);
            btnAttach.Margin = T(Gap.Control, 0, 0, 0);
            btnAttach.VerticalAlignment = VerticalAlignment.Bottom;
            DockPanel.SetDock(btnAttach, Dock.Right);
            foot.Children.Add(btnAttach);
            var hint = NewHelp("The launcher with these settings, before saving: the mouse wheel scrolls it (turns the wheel), Q / E change category. Nothing is launched.");
            hint.VerticalAlignment = VerticalAlignment.Center;
            foot.Children.Add(hint);
            root.Children.Add(foot);
            wheelCanvas = new Canvas { ClipToBounds = true, Focusable = true, Background = Brushes.Transparent };
            wheelBox = new Viewbox { Stretch = Stretch.Uniform, Child = wheelCanvas, StretchDirection = StretchDirection.Both };
            var frame = new Border { Child = wheelBox, BorderBrush = ResBrush("LineBrush"), BorderThickness = new Thickness(1), ClipToBounds = true, VerticalAlignment = VerticalAlignment.Top };
            root.Children.Add(frame);
            w.Content = root;
            wheelCanvas.MouseWheel += (s, e) => { e.Handled = true; PreviewStep(e.Delta < 0 ? 1 : -1); };
            wheelCanvas.MouseDown += (s, e) => wheelCanvas.Focus();
            wheelCanvas.KeyDown += (s, e) =>
            {
                bool vertical = IsWheel() ? WheelVertical() : WWord("ScrollDir", "v").StartsWith("v");
                if (e.Key == (vertical ? Key.Down : Key.Right)) { PreviewStep(1); e.Handled = true; }
                else if (e.Key == (vertical ? Key.Up : Key.Left)) { PreviewStep(-1); e.Handled = true; }
                else if (e.Key == Key.Q || e.Key == Key.PageUp) { RingStep(-1); e.Handled = true; }
                else if (e.Key == Key.E || e.Key == Key.PageDown) { RingStep(1); e.Handled = true; }
            };
            wheelDwell = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
            wheelDwell.Tick += (s, e) =>
            {
                wheelDwell.Stop();
                if (wheelAnimating) return;
                wheelTurnMouse = Mouse.GetPosition(wheelCanvas);
                WheelTurnTo(wheelDwellK);
            };
            w.SourceInitialized += (s, e) =>
            {
                SetDarkTitle(w);
                // the end of a move or a resize by the person (not by PlacePreview):
                // it stays there
                HwndSource.FromHwnd(new WindowInteropHelper(w).Handle).AddHook((IntPtr hwnd, int msg, IntPtr wp, IntPtr lp, ref bool handled) =>
                {
                    const int WM_EXITSIZEMOVE = 0x0232;
                    if (msg == WM_EXITSIZEMOVE && previewWin != null)
                    {
                        previewFree = new Rect(previewWin.Left, previewWin.Top, previewWin.ActualWidth, previewWin.ActualHeight);
                        SavePreviewState();
                        UpdateAttachButton();
                    }
                    return IntPtr.Zero;
                });
            };
            // maximized: let go of Options, back where it was when restored
            w.StateChanged += (s, e) =>
            {
                if (w.WindowState == WindowState.Minimized) return;
                previewMax = w.WindowState == WindowState.Maximized;
                if (previewMax || !previewFree.HasValue) previewFree = w.RestoreBounds;
                SavePreviewState();
                UpdateAttachButton();
            };
            w.Closed += (s, e) => { previewWin = null; wheelCanvas = null; wheelCatBox = null; btnAttach = null; UpdatePreviewButton(); };
            previewWin = w;
            LoadWheelCategories();
            if (currentFile != null) PreviewFollow(currentFile);
            PlacePreview();
            w.Show();
            if (previewMax && previewFree.HasValue) w.WindowState = WindowState.Maximized;
            DrawWheel();
            UpdatePreviewButton();
            UpdateAttachButton();
        }

        void ClosePreview()
        {
            if (previewWin != null) previewWin.Close();
        }

        void UpdateAttachButton()
        {
            if (btnAttach != null) btnAttach.Visibility = previewFree.HasValue ? Visibility.Visible : Visibility.Collapsed;
        }

        void UpdatePreviewButton()
        {
            if (btnPreview == null) return;
            btnPreview.Content = previewWin != null ? "Hide preview" : "Preview";
        }

        // Beside the Options window, as tall as it, as wide as the screen's
        // proportions want: on its right, or on its left when the right has no
        // room. Let go of Options: where it was put.
        void PlacePreview()
        {
            if (previewWin == null || win.WindowState == WindowState.Minimized) return;
            if (previewWin.WindowState != WindowState.Normal) return;   // maximized: where Windows put it
            if (previewFree.HasValue)
            {
                var r = previewFree.Value;
                if (previewWin.Left != r.X) previewWin.Left = r.X;
                if (previewWin.Top != r.Y) previewWin.Top = r.Y;
                if (previewWin.Width != r.Width) previewWin.Width = r.Width;
                if (previewWin.Height != r.Height) previewWin.Height = r.Height;
                return;
            }
            var work = SystemParameters.WorkArea;
            double monW = screenPx[0] > 0 ? screenPx[0] : 16, monH = screenPx[1] > 0 ? screenPx[1] : 9;
            double h = Math.Min(win.ActualHeight, work.Height);
            if (h <= 0) return;
            // the picture's proportions plus the room of the header and the hint
            double chrome = Fs.Title * 6;
            double w = Math.Max(Fs.Title * 12, Math.Min(work.Width * 0.45, (h - chrome) * monW / monH + Fs.Title * 2));
            double right = work.Right - (win.Left + win.ActualWidth), left = win.Left - work.Left;
            double x = right >= w || right >= left ? win.Left + win.ActualWidth : win.Left - w;
            x = Math.Max(work.Left, Math.Min(x, work.Right - w));
            previewWin.Left = x;
            previewWin.Top = Math.Max(work.Top, win.Top);
            previewWin.Width = w;
            previewWin.Height = h;
        }

        // The Categories page opened a category: the preview shows it
        void PreviewFollow(string file)
        {
            if (previewWin == null || file == null) return;
            int i = wheelCats.FindIndex(c => string.Equals(c.File, file, StringComparison.OrdinalIgnoreCase));
            if (i < 0) { LoadWheelCategories(); i = wheelCats.FindIndex(c => string.Equals(c.File, file, StringComparison.OrdinalIgnoreCase)); }
            if (i >= 0 && i != wheelCatIdx) SetWheelCategory(i);
        }

        // A tile or the category changed (not saved yet): drawn again from the model
        void PreviewChanged(string file)
        {
            if (previewWin == null) return;
            if (wheelCatIdx >= 0 && wheelCatIdx < wheelCats.Count && string.Equals(wheelCats[wheelCatIdx].File, file, StringComparison.OrdinalIgnoreCase))
                SetWheelCategory(wheelCatIdx, true);
        }

        bool IsWheel() { return WWord("ScrollMode", "grid") == "wheel"; }

        void PreviewStep(int dir)
        {
            if (IsWheel()) { WheelStep(dir); return; }
            int L = GridLines();
            int step = Math.Max(1, (int)WNum("ScrollStep", 1));
            int vis = GridVisibleLines();
            int next = gridScroll + dir * step;
            if (!WheelInfinite()) next = Math.Max(0, Math.Min(Math.Max(0, L - vis), next));
            if (next == gridScroll) return;
            gridScroll = next;
            DrawWheel();
        }

        // --- the grid ---------------------------------------------------------------------

        class GridPlace { public WheelTile Tile; public int Line, Cross, Lines, Cells; }

        int GridNx() { return Math.Max(1, (int)CatNum("NX", WNum("NX", 4))); }
        int GridNy() { return Math.Max(1, (int)CatNum("NY", WNum("NY", 2))); }
        bool GridHorizontal() { return WWord("ScrollDir", "v").StartsWith("h"); }
        int GridVisibleLines() { return GridHorizontal() ? GridNx() : GridNy(); }

        double CatNum(string key, double def)
        {
            if (wheelCatIdx < 0 || wheelCatIdx >= wheelCats.Count) return def;
            double v;
            string s = Core.GetKey(Core.GetCategorySection(GetModel(wheelCats[wheelCatIdx].File)), key).Trim();
            return double.TryParse(s, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out v) ? v : def;
        }

        // Tiles in order, each in the first free spot where it fits (packTiles in Raintile.lua)
        List<GridPlace> GridPack(out int lines)
        {
            bool hz = GridHorizontal();
            int P = hz ? GridNy() : GridNx();
            var cell = new Dictionary<int, HashSet<int>>();
            var count = new Dictionary<int, int>();
            var list = new List<GridPlace>();
            int first = 0;
            lines = 0;
            foreach (var t in wheelTiles)
            {
                int cols = Math.Min(GridNx(), t.Cols), rows = Math.Min(GridNy(), t.Rows);
                int ls = hz ? cols : rows, cs = Math.Min(P, hz ? rows : cols);
                int l = first, placed = -1;
                while (placed < 0)
                {
                    for (int x = 0; x <= P - cs && placed < 0; x++)
                    {
                        bool free = true;
                        for (int a = l; a < l + ls && free; a++)
                            for (int b = x; b < x + cs && free; b++)
                                if (cell.ContainsKey(a) && cell[a].Contains(b)) free = false;
                        if (free) placed = x;
                    }
                    if (placed < 0) l++;
                }
                for (int a = l; a < l + ls; a++)
                {
                    if (!cell.ContainsKey(a)) cell[a] = new HashSet<int>();
                    for (int b = placed; b < placed + cs; b++) cell[a].Add(b);
                    count[a] = (count.ContainsKey(a) ? count[a] : 0) + cs;
                }
                list.Add(new GridPlace { Tile = t, Line = l, Cross = placed, Lines = ls, Cells = cs });
                lines = Math.Max(lines, l + ls);
                while (count.ContainsKey(first) && count[first] >= P) first++;
            }
            return list;
        }

        int GridLines() { int lines; GridPack(out lines); return lines; }

        void DrawGridTiles(WheelGeo g, Canvas grid)
        {
            if (wheelTiles.Count == 0) return;
            bool hz = GridHorizontal();
            int nx = GridNx(), ny = GridNy();
            double gap = WSize("Gap", g.MonH, 18);
            double tw = Math.Floor((g.GW - (nx - 1) * gap) / nx), th = Math.Floor((g.GH - (ny - 1) * gap) / ny);
            int lines;
            var places = GridPack(out lines);
            if (lines == 0) return;
            bool inf = WheelInfinite();
            int vis = hz ? nx : ny;
            double radius = WSize("TileRadius", g.MonH, 0);
            bool labels = WNum("ShowLabels", 1) != 0;
            // with infinite scroll the lines repeat (also when they all fit)
            int r0 = inf ? (int)Math.Floor((double)gridScroll / lines) - 1 : 0, r1 = inf ? r0 + 2 + vis / Math.Max(1, lines) + 1 : 0;
            for (int rep = r0; rep <= r1; rep++)
                foreach (var p in places)
                {
                    int line = p.Line + rep * lines - gridScroll;
                    if (line + p.Lines <= 0 || line > vis) continue;
                    double w = hz ? p.Lines * (tw + gap) - gap : p.Cells * (tw + gap) - gap;
                    double h = hz ? p.Cells * (th + gap) - gap : p.Lines * (th + gap) - gap;
                    double x = hz ? line * (tw + gap) : p.Cross * (tw + gap);
                    double y = hz ? p.Cross * (th + gap) : line * (th + gap);
                    var e = NewPreviewTile(p.Tile, w, h, Math.Min(radius, Math.Min(w, h) / 2), labels, false, g);
                    Canvas.SetLeft(e, x); Canvas.SetTop(e, y);
                    grid.Children.Add(e);
                }
        }

        // The categories at the top, as the menu shows them (the active one lit)
        void DrawMenu(WheelGeo g)
        {
            double padY = WSize("PadY", g.MonH, 24), menuH = WSize("MenuH", g.MonH, 44);
            double fontPx = Math.Max(1, WNum("MenuFontSize", 12) * 4 / 3);
            double pad = WSize("MenuItemPad", g.MonW, 16);
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            var activeFill = NewColorBrush(V("ActiveCategoryColor")) ?? new SolidColorBrush(Color.FromArgb(70, 0, 210, 180));
            for (int i = 0; i < wheelCats.Count; i++)
            {
                var t = new TextBlock { Text = wheelCats[i].Name, FontSize = fontPx, Foreground = NewColorBrush(V(i == wheelCatIdx ? "TextColor" : "TextDimColor")) ?? Brushes.White, VerticalAlignment = VerticalAlignment.Center };
                row.Children.Add(new Border { Child = t, Height = menuH, Padding = new Thickness(pad, 0, pad, 0), CornerRadius = new CornerRadius(menuH / 2),
                    Background = i == wheelCatIdx ? activeFill : Brushes.Transparent });
            }
            row.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            Canvas.SetLeft(row, g.LX + Math.Max(0, (g.LW - row.DesiredSize.Width) / 2));
            Canvas.SetTop(row, g.LY + padY);
            wheelCanvas.Children.Add(row);
        }
    }
}
