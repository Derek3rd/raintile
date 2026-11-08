// Raintile Options: the preview of the launcher (its window: PreviewWindow.cs)
// and of the wheel. The launcher as the settings shape it (mode, docked side,
// sizes, margins) on the main screen; with ScrollMode=Wheel the tiles of a
// category on their arc and the categories on the inner wheel, drawn with the
// formulas of the launcher (M.wheelFrame,
// M.wheelPx, M.wheelAssign, M.ringRender in Raintile.lua): the same numbers
// give the same picture. It turns like the launcher: the mouse wheel, a click,
// the mouse resting on a side tile, the arrows and Q / E; every change of a
// setting redraws it.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace RaintileOptions
{
    public partial class OptionsApp
    {
        class WheelTile { public string Name, Label, LogoPath; public ImageSource Bg, Logo, BgFull; public Brush Color, LogoColor; public int Cols = 1, Rows = 1; }
        class WheelCat { public string File, Name; public ImageSource Icon; }

        Canvas wheelCanvas;
        Viewbox wheelBox;
        ComboBox wheelCatBox;
        List<WheelCat> wheelCats = new List<WheelCat>();
        List<WheelTile> wheelTiles = new List<WheelTile>();
        int wheelCatIdx;
        // positions: the tiles' (pos, animated towards target) and the ring's
        double wheelPos, wheelTarget, wheelFrom, wheelDur;
        double ringPos, ringTarget, ringFrom, ringDur;
        readonly Stopwatch wheelClock = new Stopwatch(), ringClock = new Stopwatch();
        bool wheelAnimating;
        DispatcherTimer wheelDwell;
        int wheelDwellK;
        // where the mouse was when it last turned the wheel: a tile that comes under
        // the still mouse with the turn does not turn it again
        Point wheelTurnMouse = new Point(double.NaN, double.NaN);

        // --- data ---------------------------------------------------------------------

        void LoadWheelCategories()
        {
            wheelCats.Clear();
            if (wheelCatBox != null) wheelCatBox.Items.Clear();
            foreach (var e in GetCategoryMenuEntries())
            {
                wheelCats.Add(new WheelCat { File = e.File, Name = e.Name, Icon = GetBitmap(e.Icon, 128) });
                if (wheelCatBox != null) wheelCatBox.Items.Add(e.Name);
            }
            wheelCatIdx = -1;
            if (wheelCats.Count > 0)
            {
                // the category with the most tiles: something to turn
                int best = 0, most = -1;
                for (int i = 0; i < wheelCats.Count; i++)
                {
                    int n = Core.GetTiles(GetModel(wheelCats[i].File)).Count;
                    if (n > most) { best = i; most = n; }
                }
                SetWheelCategory(best);
                ringPos = ringTarget = best;
            }
        }

        // keep: the same category drawn again (a tile changed): where it was
        void SetWheelCategory(int i, bool keep = false)
        {
            if (i < 0 || i >= wheelCats.Count) return;
            int prev = keep ? -1 : wheelCatIdx;
            wheelCatIdx = i;
            if (wheelCatBox != null && wheelCatBox.SelectedIndex != i) wheelCatBox.SelectedIndex = i;
            var model = GetModel(wheelCats[i].File);
            string b = System.IO.Path.GetFileNameWithoutExtension(wheelCats[i].File);
            wheelTiles = Core.GetTiles(model).Select(t => new WheelTile
            {
                Name = t.Name,
                Label = Core.GetKey(t, "Label") != "" ? Core.GetKey(t, "Label") : t.Name,
                Bg = GetBitmap(Core.GetTileImage(b, t, "Background"), 320),
                BgFull = GetBitmap(Core.GetTileImage(b, t, "Background"), 960),
                Logo = GetBitmap(Core.GetTileImage(b, t, "Logo"), 160),
                LogoPath = Core.GetTileImage(b, t, "Logo"),
                Color = NewColorBrush(Core.GetKey(t, "Color")) ?? NewColorBrush(Core.GetKey(Core.GetCategorySection(model), "TileColor"))
                    ?? NewColorBrush(V("TileColor")) ?? ResBrush("FieldBg"),
                // the colour taken from the logo (Generated\Colors.txt), unless the tile or its category sets one
                LogoColor = NewColorBrush(Core.GetKey(t, "Color")) ?? NewColorBrush(Core.GetKey(Core.GetCategorySection(model), "TileColor")) ?? WheelLogoColor(Core.GetTileImage(b, t, "Logo")),
                Cols = TileSpan(Core.GetKey(t, "Size"), 0), Rows = TileSpan(Core.GetKey(t, "Size"), 1),
            }).ToList();
            if (!keep) { wheelPos = wheelTarget = 0; gridScroll = 0; }
            // the ring turns the shorter way round to the new category
            int n = wheelCats.Count;
            if (prev >= 0 && n > 0)
            {
                double d = ((i - ringTarget) % n + n + n / 2.0) % n - n / 2.0;
                ringFrom = ringPos; ringTarget = ringTarget + d; ringDur = WheelStepMs() * Math.Sqrt(Math.Max(1, Math.Abs(d)));
                ringClock.Restart();
                StartWheelAnimation();
            }
            DrawWheel();
        }

        // Size=2x1: the columns (part 0) or the rows (part 1) a tile takes
        static int TileSpan(string size, int part)
        {
            var m = System.Text.RegularExpressions.Regex.Match(size ?? "", @"^\s*(\d+)\s*[xX*]\s*(\d+)");
            int n;
            return m.Success && int.TryParse(m.Groups[part + 1].Value, out n) ? Math.Max(1, n) : 1;
        }

        Brush WheelLogoColor(string logo)
        {
            if (logo == null) return null;
            string c;
            try { if (logoColors.TryGetValue(System.IO.Path.GetFullPath(logo), out c)) return NewColorBrush(c); } catch { }
            return null;
        }

        // --- settings, as the launcher reads them -------------------------------------

        double WNum(string key, double def)
        {
            double v;
            return double.TryParse(V(key).Trim().TrimEnd('%'), NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : def;
        }

        // A size setting in pixels, or in percent of 'total'
        double WSize(string key, double total, double def)
        {
            string v = V(key).Trim();
            double n;
            bool pct = v.EndsWith("%");
            if (!double.TryParse(v.TrimEnd('%'), NumberStyles.Float, CultureInfo.InvariantCulture, out n)) return def;
            return pct ? n * total / 100 : n;
        }

        string WWord(string key, string def) { string v = V(key).Trim().ToLowerInvariant(); return v == "" ? def : v; }
        double WheelStepMs() { return Math.Max(16, WNum("WheelStepTime", 350)); }
        int WheelVisible() { int v = Math.Max(1, (int)WNum("WheelVisible", 11)); return v % 2 == 0 ? v + 1 : v; }
        bool WheelInfinite() { return WNum("InfiniteScroll", 1) != 0 && wheelTiles.Count > 1; } // (few tiles repeat)

        bool WheelVertical()
        {
            string axis = WWord("WheelAxis", "auto"), mode = WWord("LauncherMode", "fullscreen"), side = WWord("DockSide", "left");
            if (axis == "vertical") return true;
            if (axis == "horizontal") return false;
            return mode == "dock" && (side == "left" || side == "right");
        }

        class WheelGeo
        {
            public double MonW, MonH, LX, LY, LW, LH, GX, GY, GW, GH, S, R, Sgn, Cx, Cy, Step, Half;
            public double[] N, T;
        }

        WheelGeo WheelGeometry()
        {
            var g = new WheelGeo();
            g.MonW = screenPx[0] > 0 ? screenPx[0] : 1920;
            g.MonH = screenPx[1] > 0 ? screenPx[1] : 1080;
            string mode = WWord("LauncherMode", "fullscreen"), side = WWord("DockSide", "left");
            g.LX = 0; g.LY = 0; g.LW = g.MonW; g.LH = g.MonH;
            if (mode == "window")
            {
                g.LW = Math.Min(g.MonW, WSize("WindowW", g.MonW, g.MonW * 0.6));
                g.LH = Math.Min(g.MonH, WSize("WindowH", g.MonH, g.MonH * 0.7));
                g.LX = (g.MonW - g.LW) / 2; g.LY = (g.MonH - g.LH) / 2;
            }
            else if (mode == "dock")
            {
                bool lr = side == "left" || side == "right";
                double d = Math.Min(lr ? g.MonW : g.MonH, WSize("DockSize", lr ? g.MonW : g.MonH, (lr ? g.MonW : g.MonH) * 0.3));
                if (lr) { g.LW = d; g.LX = side == "right" ? g.MonW - d : 0; }
                else { g.LH = d; g.LY = side == "bottom" ? g.MonH - d : 0; }
            }
            // the grid area: inside the margins, under the menu (as GridClip)
            double padX = WSize("PadX", g.MonW, 40), padY = WSize("PadY", g.MonH, 24);
            double menuH = WSize("MenuH", g.MonH, 44), gap = WSize("Gap", g.MonH, 18);
            g.GX = g.LX + padX; g.GY = g.LY + padY + menuH + gap;
            g.GW = Math.Max(1, g.LW - 2 * padX); g.GH = Math.Max(1, g.LH - 2 * padY - menuH - gap);
            // square tiles: WheelTileSize percent of the smaller side of the screen
            double sz = Math.Floor(WNum("WheelTileSize", 25) * Math.Min(g.MonW, g.MonH) / 100);
            g.S = Math.Max(16, Math.Min(sz, Math.Floor(Math.Min(g.GW, g.GH))));
            // the circle (M.wheelFrame)
            bool vertical = WheelVertical();
            if (vertical) g.N = mode == "dock" && side == "right" ? new[] { -1.0, 0 } : new[] { 1.0, 0 };
            else if (mode == "dock") g.N = side == "bottom" ? new[] { 0, -1.0 } : new[] { 0, 1.0 };
            else g.N = new[] { 0, -1.0 };
            g.T = vertical ? new[] { 0, 1.0 } : new[] { 1.0, 0 };
            double along = vertical ? g.GH : g.GW, across = vertical ? g.GW : g.GH;
            double anchor = Math.Min(100, Math.Max(0, WNum("WheelAnchor", 69)));
            double a = (g.N[0] + g.N[1] > 0 ? anchor : 100 - anchor) / 100 * across;
            double cx = vertical ? a : g.GW / 2, cy = vertical ? g.GH / 2 : a;
            g.R = Math.Max(1, Math.Max(5, WNum("WheelRadius", 70)) / 100 * along);
            g.Sgn = WWord("WheelCurve", "out") == "in" ? -1 : 1;
            g.Cx = cx - g.Sgn * g.N[0] * g.R;
            g.Cy = cy - g.Sgn * g.N[1] * g.R;
            g.Step = (g.S * Math.Max(5, WNum("WheelSpacing", 50)) / 100) / g.R;
            g.Half = (WheelVisible() - 1) / 2.0;
            return g;
        }

        // A point of the circle of radius r at angle th, in the grid
        static Point WheelPoint(WheelGeo g, double r, double th)
        {
            double c = g.Sgn * r * Math.Cos(th), s = r * Math.Sin(th);
            return new Point(g.Cx + c * g.N[0] + s * g.T[0], g.Cy + c * g.N[1] + s * g.T[1]);
        }

        // --- drawing ----------------------------------------------------------------------

        void DrawWheel()
        {
            if (wheelCanvas == null) return;
            var g = WheelGeometry();
            wheelCanvas.Children.Clear();
            wheelCanvas.Width = g.MonW;
            wheelCanvas.Height = g.MonH;
            bool wheel = IsWheel();
            // the screen and the launcher on it
            wheelCanvas.Children.Add(new Rectangle { Width = g.MonW, Height = g.MonH, Fill = new LinearGradientBrush(
                Color.FromRgb(0x24, 0x40, 0x5a), Color.FromRgb(0x0b, 0x12, 0x1a), 60) });
            var launcher = new Rectangle { Width = g.LW, Height = g.LH, Fill = NewColorBrush(V("BgColor")) ?? new SolidColorBrush(Color.FromArgb(200, 8, 8, 12)) };
            Canvas.SetLeft(launcher, g.LX); Canvas.SetTop(launcher, g.LY);
            wheelCanvas.Children.Add(launcher);
            // the selected tile's background over it (WheelBackdrop)
            if (wheel && WNum("WheelBackdrop", 1) != 0 && wheelTiles.Count > 0)
            {
                int L = wheelTiles.Count;
                var sel = wheelTiles[(((int)Math.Round(wheelTarget)) % L + L) % L];
                if (sel.BgFull != null)
                {
                    var back = new Image { Source = sel.BgFull, Stretch = Stretch.UniformToFill, Width = g.LW, Height = g.LH,
                        Opacity = Math.Min(100, Math.Max(0, WNum("WheelBackdropOpacity", 40))) / 100, ClipToBounds = true };
                    Canvas.SetLeft(back, g.LX); Canvas.SetTop(back, g.LY);
                    wheelCanvas.Children.Add(back);
                }
            }
            // what stays of the menu at the top: a faint bar
            double padY = WSize("PadY", g.MonH, 24), menuH = WSize("MenuH", g.MonH, 44);
            var bar = new Rectangle { Width = Math.Max(1, g.GW), Height = menuH, RadiusX = menuH / 2, RadiusY = menuH / 2, Fill = new SolidColorBrush(Color.FromArgb(18, 255, 255, 255)) };
            Canvas.SetLeft(bar, g.GX); Canvas.SetTop(bar, g.LY + padY);
            // with the selected tile's background: one band behind the whole top row (TopBarColor)
            if (wheel && WNum("WheelBackdrop", 1) != 0)
            {
                // (as MeterTopBar: from the search to the close button, a little larger than the menu's pills)
                double padX = WSize("PadX", g.MonW, 40), r = WSize("MenuRadius", g.MonH, 22) + 6;
                var band = new Rectangle { Width = Math.Max(1, g.LW - 2 * padX + 16), Height = menuH + 12, RadiusX = r, RadiusY = r,
                    Fill = NewColorBrush(V("TopBarColor")) ?? Brushes.Black };
                Canvas.SetLeft(band, g.LX + padX - 8); Canvas.SetTop(band, g.LY + padY - 6);
                wheelCanvas.Children.Add(band);
            }
            wheelCanvas.Children.Add(bar);
            // the grid area clips the tiles, as GridClip
            var grid = new Canvas { Width = g.GW, Height = g.GH, ClipToBounds = true };
            Canvas.SetLeft(grid, g.GX); Canvas.SetTop(grid, g.GY);
            bool ring = wheel && WWord("WheelMenu", "ring") != "bar";
            if (ring) DrawRing(g); else DrawMenu(g);
            wheelCanvas.Children.Add(grid);
            if (wheel) DrawTiles(g, grid); else DrawGridTiles(g, grid);
        }

        void DrawTiles(WheelGeo g, Canvas grid)
        {
            int L = wheelTiles.Count;
            if (L == 0) return;
            bool inf = WheelInfinite();
            double fade = Math.Min(100, Math.Max(0, WNum("WheelFade", 65)));
            bool labelsAll = WWord("WheelLabels", "center") == "all" && WNum("ShowLabels", 1) != 0;
            bool labels = WNum("ShowLabels", 1) != 0;
            double radius = Math.Min(WSize("TileRadius", g.MonH, 0), g.S / 2);
            var list = new List<double[]>(); // k, d, alpha
            for (int k = (int)Math.Ceiling(wheelPos - g.Half - 1); k <= (int)Math.Floor(wheelPos + g.Half + 1); k++)
            {
                if (!inf && (k < 0 || k >= L)) continue;
                double d = k - wheelPos, ad = Math.Abs(d);
                double a = 1 - fade / 100 * Math.Min(1, ad / Math.Max(0.5, g.Half + 0.5));
                if (ad > g.Half + 0.5) a *= Math.Max(0, 1 - (ad - g.Half - 0.5) * 2);
                if (a > 0.01) list.Add(new[] { k, d, a });
            }
            // the farthest first: the middle one on top
            foreach (var e in list.OrderByDescending(e => Math.Abs(e[1])))
            {
                int k = (int)e[0];
                var tile = wheelTiles[((k % L) + L) % L];
                var p = WheelPoint(g, g.R, e[1] * g.Step);
                var box = NewPreviewTile(tile, g.S, g.S, radius, labels && (labelsAll || Math.Abs(e[1]) < 0.5), WNum("WheelIconsOnly", 0) != 0, g);
                box.Opacity = e[2];
                box.Cursor = Cursors.Hand;
                Canvas.SetLeft(box, p.X - g.S / 2);
                Canvas.SetTop(box, p.Y - g.S / 2);
                int kk = k;
                box.MouseLeftButtonUp += (s, ev) => { ev.Handled = true; WheelClick(kk); };
                box.MouseEnter += (s, ev) =>
                {
                    if (wheelAnimating || WWord("WheelHover", "turn") != "turn" || Math.Abs(kk - wheelTarget) < 0.5) return;
                    var at = Mouse.GetPosition(wheelCanvas);
                    if (Math.Abs(at.X - wheelTurnMouse.X) + Math.Abs(at.Y - wheelTurnMouse.Y) < 3) return;
                    wheelDwellK = kk;
                    wheelDwell.Stop(); wheelDwell.Start();
                };
                box.MouseLeave += (s, ev) => wheelDwell.Stop();
                grid.Children.Add(box);
            }
        }

        // A tile as the launcher draws it: its colour, its background (not with
        // logos only), its logo (IconSize, at most most of the tile), its name
        Grid NewPreviewTile(WheelTile tile, double w, double h, double radius, bool label, bool iconsOnly, WheelGeo g)
        {
            var box = new Grid { Width = w, Height = h };
            box.Clip = new RectangleGeometry(new Rect(0, 0, w, h), radius, radius);
            iconsOnly = iconsOnly && tile.Logo != null;
            box.Children.Add(new Rectangle { Fill = iconsOnly ? (tile.LogoColor ?? tile.Color) : tile.Color });
            if (tile.Bg != null && !iconsOnly) box.Children.Add(new Image { Source = tile.Bg, Stretch = Stretch.UniformToFill });
            if (tile.Logo != null)
            {
                double ls = Math.Min(WSize("IconSize", g.MonH, 96), Math.Min(w, h) * (IsWheel() ? 0.7 : 0.9));
                box.Children.Add(new Image { Source = tile.Logo, Width = ls, Height = ls, Stretch = Stretch.Uniform });
            }
            if (label)
            {
                double labelPx = Math.Max(1, WNum("LabelFontSize", 14) * 4 / 3);
                var name = new TextBlock { Text = tile.Label, Foreground = NewColorBrush(V("TextColor")) ?? Brushes.White, FontSize = labelPx, FontWeight = FontWeights.SemiBold,
                    VerticalAlignment = VerticalAlignment.Bottom, HorizontalAlignment = HorizontalAlignment.Left, TextTrimming = TextTrimming.CharacterEllipsis };
                name.Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = labelPx / 2, ShadowDepth = 0, Opacity = 0.8 };
                box.Children.Add(new Border { Child = name, Padding = new Thickness(WSize("LabelPad", g.MonH, 14)) });   // ui-exempt: preview of the launcher (its LabelPad)
            }
            return box;
        }

        // The inner wheel of categories (M.ringRender)
        void DrawRing(WheelGeo g)
        {
            int n = wheelCats.Count;
            if (n == 0) return;
            double rad = Math.Max(10, g.R - g.Sgn * g.S * (0.5 + Math.Max(0, WNum("WheelMenuGap", 50)) / 100));
            double d = Math.Max(12, Math.Floor(g.S * Math.Min(150, Math.Max(10, WNum("WheelMenuSize", 50))) / 100));
            double stepA = d * 1.35 / rad;
            var accent = NewColorBrush(V("AccentColor")) ?? ResBrush("AccentBrush");
            var activeFill = NewColorBrush(V("ActiveCategoryColor")) ?? new SolidColorBrush(Color.FromArgb(70, 0, 210, 180));
            for (int j = 0; j < n; j++)
            {
                double dd = ((j - ringPos) % n + n + n / 2.0) % n - n / 2.0;
                double a = Math.Abs(dd);
                var p = WheelPoint(g, rad, dd * stepA);
                double sz = Math.Floor(d * (1 - 0.35 * Math.Min(1, a / 2)) + 0.5);
                double alpha = Math.Max(0, 1 - 0.45 * a);
                bool on = j == wheelCatIdx;
                var disc = new Grid { Width = sz, Height = sz, Opacity = alpha, Cursor = Cursors.Hand };
                disc.Children.Add(new Ellipse { Fill = on ? activeFill : new SolidColorBrush(Color.FromArgb(20, 255, 255, 255)),
                    Stroke = on ? accent : new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)), StrokeThickness = 2 });
                var c = wheelCats[j];
                if (c.Icon != null) disc.Children.Add(new Image { Source = c.Icon, Width = sz * 0.56, Height = sz * 0.56, Opacity = on ? 1 : 0.7 });
                else disc.Children.Add(new TextBlock { Text = c.Name.Substring(0, Math.Min(1, c.Name.Length)).ToUpperInvariant(), Foreground = Brushes.White,
                    FontSize = Math.Max(6, sz * 0.3) * 4 / 3, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
                Canvas.SetLeft(disc, g.GX + p.X - sz / 2);
                Canvas.SetTop(disc, g.GY + p.Y - sz / 2);
                int jj = j;
                disc.MouseLeftButtonUp += (s, ev) => { ev.Handled = true; SetWheelCategory(jj); };
                wheelCanvas.Children.Add(disc);
                if (on && a < 0.5)
                {
                    var name = new TextBlock { Text = c.Name, Foreground = accent, FontWeight = FontWeights.Bold, FontSize = Math.Max(1, WNum("MenuFontSize", 12) * 0.85 * 4 / 3) };
                    name.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
                    bool vertical = WheelVertical();
                    double x = vertical ? g.GX + p.X - name.DesiredSize.Width / 2 : g.GX + p.X + sz / 2 + 8;
                    double y = vertical ? g.GY + p.Y - sz / 2 - 4 - name.DesiredSize.Height : g.GY + p.Y - name.DesiredSize.Height / 2;
                    Canvas.SetLeft(name, Math.Max(g.LX + 4, x));
                    Canvas.SetTop(name, y);
                    wheelCanvas.Children.Add(name);
                }
            }
        }

        // --- turning ------------------------------------------------------------------------

        void WheelStep(int dir) { WheelTurnTo(Math.Round(wheelTarget) + dir); }

        void WheelTurnTo(double k)
        {
            int L = wheelTiles.Count;
            if (L == 0) return;
            if (!WheelInfinite()) k = Math.Max(0, Math.Min(L - 1, k));
            if (k == wheelTarget) return;
            wheelFrom = wheelPos; wheelTarget = k;
            wheelDur = WheelStepMs() * Math.Sqrt(Math.Max(1, Math.Abs(k - wheelPos)));
            wheelClock.Restart();
            StartWheelAnimation();
        }

        void WheelClick(int k)
        {
            wheelDwell.Stop();
            // the middle tile, or a side one with WheelClick=Launch: it would start (here it only flashes)
            if (Math.Abs(k - wheelTarget) < 0.5 || WWord("WheelClick", "launch") != "center") { FlashWheel(); return; }
            WheelTurnTo(k);
        }

        void FlashWheel()
        {
            var anim = new System.Windows.Media.Animation.DoubleAnimation(0.55, 1, TimeSpan.FromMilliseconds(250));
            wheelCanvas.BeginAnimation(UIElement.OpacityProperty, anim);
        }

        void RingStep(int dir)
        {
            int n = wheelCats.Count;
            if (n == 0) return;
            SetWheelCategory(((wheelCatIdx + dir) % n + n) % n);
        }

        void StartWheelAnimation()
        {
            if (wheelAnimating) return;
            wheelAnimating = true;
            CompositionTarget.Rendering += WheelFrame;
        }

        static double EaseOut(double p) { return 1 - Math.Pow(1 - p, 3); }

        void WheelFrame(object sender, EventArgs e)
        {
            bool moving = false;
            if (wheelPos != wheelTarget)
            {
                double p = Math.Min(1, wheelClock.Elapsed.TotalMilliseconds / Math.Max(1, wheelDur));
                wheelPos = p >= 1 ? wheelTarget : wheelFrom + (wheelTarget - wheelFrom) * EaseOut(p);
                moving |= wheelPos != wheelTarget;
            }
            if (ringPos != ringTarget)
            {
                double p = Math.Min(1, ringClock.Elapsed.TotalMilliseconds / Math.Max(1, ringDur));
                ringPos = p >= 1 ? ringTarget : ringFrom + (ringTarget - ringFrom) * EaseOut(p);
                moving |= ringPos != ringTarget;
            }
            DrawWheel();
            if (!moving)
            {
                CompositionTarget.Rendering -= WheelFrame;
                wheelAnimating = false;
            }
        }
    }
}
