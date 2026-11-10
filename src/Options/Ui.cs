// Raintile Options: start, small helpers to build elements, dialogs.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
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
        [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
        [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point p);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    }

    // The rules of docs/OptionsUI.md as code: every page takes its glyphs, type
    // sizes, spacing and field widths from here.

    // One glyph per action (Segoe MDL2 Assets)
    static class Glyph
    {
        public const int Reset = 0xE7A7;    // a field back to its default or to the value of All tiles
        public const int Clear = 0xE711;    // a field emptied (its image or icon file to the Recycle Bin, asked)
        public const int Delete = 0xE74D;   // an entry of a list goes away (list header only): always asked
        public const int Add = 0xE710;
        public const int Edit = 0xE70F;     // a row of a list shown read-only: edit it in place (Done again)
        public const int Up = 0xE74A, Down = 0xE74B, Left = 0xE72B, Right = 0xE72A;   // move an entry
        public const int GroupOpen = 0xE70D, GroupClosed = 0xE76C;   // menu groups only
        public const int Pin = 0xE718;      // marks a pinned tile (not a button)
        // the pad button that presses a button, before its text while the pad is in use
        // (AddPadHint), and on the keys and the hint line of the on-screen keyboard
        public const int PadA = 0xF093, PadB = 0xF094, PadY = 0xF095, PadX = 0xF096, PadStart = 0xEDE3;
        public const int PadLT = 0xF10A, PadRT = 0xF10B, PadLB = 0xF10C, PadRB = 0xF10D;
        // and as the value of a gamepad setting (NewPadFace), with the ones above
        public const int PadBack = 0xEECA, PadLS = 0xF108, PadRS = 0xF109, PadDpad = 0xF10E;
        public static readonly FontFamily Font = new FontFamily("Segoe MDL2 Assets");
    }

    // Type sizes
    static class Fs
    {
        public const double Title = 24;      // page title
        public const double Section = 11.5;  // card title, upper case
        public const double Label = 13.5;    // labels, names of entries
        public const double Help = 12;       // help, hints, statuses, values
        public const double Badge = 11;      // badges and chips
    }

    // Spacing: every margin and padding of the pages is one of these (or 0)
    static class Gap
    {
        public const double Help = 3;        // a label to its help below
        public const double Line = 4;        // a hint or status under its control, the lines of a list
        public const double Icon = 6;        // before an icon button (it has its own padding); small insets
        public const double Control = 8;     // between controls and between buttons
        public const double Text = 10;       // a thumbnail or icon to its text; a header or note to what follows
        public const double Group = 12;      // between groups in a card; a status after its buttons; a slider to its box
        public const double Card = 16;       // between cards
        public const double Indent = 18;     // a switch that belongs to the one above
        public const double Column = 24;     // the label column to the control column
        public const double DialogBar = 20;  // above the buttons of a dialog
        public const double Row = 11;        // above and below a side-by-side row
        public const double StackedRow = 8;  // above and below a stacked row
        public const double ActionColumn = 34;   // the reset / clear column of a row
        public const double ScrollBar = 9;       // the page scrollbar (Options.xaml), kept also when hidden
        public const double CardPadding = 20;    // left and right, the Card style
        public static readonly Thickness Page = new Thickness(36, 4, 36, 24);
        public static readonly Thickness Dialog = new Thickness(24, 20, 24, 18);   // inside a dialog
        public static readonly Thickness Chip = new Thickness(8, 1, 8, 2);         // padding of badges and chips
        public static readonly Thickness ListItem = new Thickness(12, 9, 12, 9);  // padding of menu and category entries
    }

    // Widths of fields
    static class FieldWidth
    {
        public const double S = 120;     // numbers (with their unit inside), sizes
        public const double M = 220;     // short fields outside rows (filters, lists)
        public const double L = 300;
        public const double Wrap = 470;  // panels of chips or switches
        public const double Unit = 72;   // the px / % combo after a size box
        // the control column of side-by-side rows: one width for every page, half
        // the room of a card between these two (UpdateControlColumn); text fields
        // and sliders fill it
        public const double ControlMin = 300, ControlMax = 440;
        public const string ControlKey = "ControlColumn";   // its GridLength in the resources
    }

    // A row of a card (NewRow): the line above it parts it from what comes
    // before. First: nothing comes before it, the card's border is there.
    public class CardRow : Border
    {
        readonly Brush line;
        public CardRow(Brush line) { this.line = line; BorderBrush = line; BorderThickness = OptionsApp.T(0, 1, 0, 0); }
        public bool First
        {
            // (only the colour: the row keeps its height)
            set { var b = value ? Brushes.Transparent : line; if (BorderBrush != b) BorderBrush = b; }
        }
    }

    // The panel of a card (NewCard, NewSwitchCard): the first thing shown in it,
    // when it is a row, has no line, also when what was above it (a reason, a
    // row of the tile editor) is hidden. docs/OptionsUI.md, "A card".
    public class CardStack : StackPanel
    {
        protected override Size MeasureOverride(Size available)
        {
            bool first = true;
            foreach (UIElement c in InternalChildren)
            {
                if (c == null || c.Visibility == Visibility.Collapsed) continue;
                var row = c as CardRow;
                if (row != null) row.First = first;
                first = false;
            }
            return base.MeasureOverride(available);
        }
    }

    // A number: slider + text box + unit (NewNumberField). Show() puts a value in
    // it without reporting a change.
    public class NumberField
    {
        public Slider Slider;
        public TextBox Box;
        public FrameworkElement Root;
        public bool Sync;

        // 'fallback' places the slider when the text is empty or not a number; the
        // text being typed is left alone. A value put in (a reset, another tile) is
        // valid again.
        public void Show(string value, double fallback)
        {
            Sync = true;
            try
            {
                if (!Box.IsKeyboardFocused)
                {
                    Box.Text = value ?? "";
                    Box.ClearValue(Control.BorderBrushProperty);
                }
                double n;
                if (!Core.TryNumber(value, out n)) n = fallback;
                Slider.Value = Math.Min(Slider.Maximum, Math.Max(Slider.Minimum, n));
            }
            finally { Sync = false; }
        }
    }

    // A length in pixels or in % of the screen: text box + px / % combo (NewSizeField)
    public class SizeField
    {
        public TextBox Box;
        public ComboBox Unit;   // item 0 px, item 1 %
        public FrameworkElement Root;
        public bool Sync;

        public bool IsPct { get { return Unit.SelectedIndex == 1; } }

        public void Show(string value)
        {
            Sync = true;
            try
            {
                string v = (value ?? "").Trim();
                Box.Text = v.TrimEnd('%').Trim();
                Box.ClearValue(Control.BorderBrushProperty);   // a value put in is valid again
                Unit.SelectedIndex = v.EndsWith("%") ? 1 : 0;
            }
            finally { Sync = false; }
        }

        // as written to the file: "" when empty
        public string Value
        {
            get { string t = Box.Text.Trim(); return t == "" ? "" : t + (IsPct ? "%" : ""); }
        }
    }

    static class Program
    {
        // Arguments: -Resources <dir> -Data <dir> -Config <name> -Page <page>, or
        // -Action runas|remove for the tile menu (TileAction.cs, no window)
        [STAThread]
        static int Main(string[] args)
        {
            var clock = Stopwatch.StartNew();
            string resources = null, data = "", config = "Raintile", page = "", action = "";
            for (int i = 0; i + 1 < args.Length; i++)
            {
                string a = args[i].TrimStart('-', '/').ToLowerInvariant();
                if (a == "resources") resources = args[++i];
                else if (a == "data") data = args[++i];
                else if (a == "config") config = args[++i];
                else if (a == "page" || a == "openpage") page = args[++i];
                else if (a == "action") action = args[++i].ToLowerInvariant();
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
                if (action == "runas" || action == "remove") return TileAction.Run(action);
                Core.DeleteOldUpdateFiles();
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

        // separator between the parts of a sub-line ("Steam   .   game")
        public static readonly string Dot = ((char)0xB7).ToString();

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
            t.FontFamily = Glyph.Font;
            t.VerticalAlignment = VerticalAlignment.Center;
            return t;
        }

        // A gamepad button (Schema.GAMEPAD_BUTTONS) as it shows in its field and on
        // the dial: its glyph; the D-pad's with the arrow of the direction
        public static int PadGlyphOf(string button)
        {
            switch (button)
            {
                case "A": return Glyph.PadA;
                case "B": return Glyph.PadB;
                case "X": return Glyph.PadX;
                case "Y": return Glyph.PadY;
                case "LB": return Glyph.PadLB;
                case "RB": return Glyph.PadRB;
                case "LT": return Glyph.PadLT;
                case "RT": return Glyph.PadRT;
                case "BACK": return Glyph.PadBack;
                case "START": return Glyph.PadStart;
                case "LS": return Glyph.PadLS;
                case "RS": return Glyph.PadRS;
                default: return Glyph.PadDpad;
            }
        }

        public FrameworkElement NewPadFace(string button, Brush brush = null)
        {
            if (string.IsNullOrEmpty(button)) return NewText("None", Fs.Label, brush, true);
            var sp = NewPanel(Orientation.Horizontal);
            sp.HorizontalAlignment = HorizontalAlignment.Center;
            var g = NewGlyph(PadGlyphOf(button), Fs.Label);
            if (brush != null) g.Foreground = brush;
            AddTo(sp, g);
            if (button == "UP" || button == "DOWN" || button == "LEFT" || button == "RIGHT")
            {
                var arrow = NewText(Schema.FormatHotKey(button), Fs.Label, brush, true);
                arrow.Margin = T(Gap.Line, 0, 0, 0);
                AddTo(sp, arrow);
            }
            return sp;
        }

        // The buttons of a gamepad combination in one field: A + LB (None without any)
        public FrameworkElement NewPadCombo(IList<string> buttons, Brush brush = null)
        {
            if (buttons == null || buttons.Count == 0) return NewPadFace("", brush);
            var sp = NewPanel(Orientation.Horizontal);
            sp.HorizontalAlignment = HorizontalAlignment.Center;
            for (int i = 0; i < buttons.Count; i++)
            {
                if (i > 0)
                {
                    var plus = NewText("+", Fs.Label, brush, true);
                    plus.Margin = T(Gap.Line, 0, Gap.Line, 0);
                    AddTo(sp, plus);
                }
                AddTo(sp, NewPadFace(buttons[i], brush));
            }
            return sp;
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

        // One width of the control column for every page: half the room inside a card
        // (page width without its margins, the scrollbar, the card padding and border),
        // between FieldWidth.ControlMin and ControlMax; set again with the window size
        void UpdateControlColumn()
        {
            double page = pageHost != null && pageHost.ActualWidth > 0 ? pageHost.ActualWidth : 1064;
            double room = page - Gap.Page.Left - Gap.Page.Right - Gap.ScrollBar - 2 * Gap.CardPadding - 2;
            double w = Math.Max(FieldWidth.ControlMin, Math.Min(FieldWidth.ControlMax, Math.Round(room * 0.5)));
            var old = app.Resources[FieldWidth.ControlKey] as GridLength?;
            if (old == null || old.Value.Value != w) app.Resources[FieldWidth.ControlKey] = new GridLength(w);
        }

        // Help under a label, hints, statuses (dim, wrapped)
        public TextBlock NewHelp(string text, Brush brush = null)
        {
            return NewText(text, Fs.Help, brush ?? ResBrush("DimBrush"), false, true);
        }

        // Title of a card or of a list
        public TextBlock NewSectionTitle(string title)
        {
            return NewText((title ?? "").ToUpperInvariant(), Fs.Section, ResBrush("DimBrush"), true);
        }

        // A row that applies only with other settings (Item.When): the reason under
        // its label, shown while it does not apply (SetRowApplies)
        public TextBlock AddRowReason(Border row, string reason)
        {
            return AddRowNote(row, reason);
        }

        // A note in the accent colour under the label of a row, after its help:
        // a reason (AddRowReason) or a state to notice (the settings in the window
        // differ from the profile). Its caller shows and hides it.
        public TextBlock AddRowNote(Border row, string text)
        {
            var left = (StackPanel)((Grid)row.Child).Children[0];
            var note = NewHelp(text, ResBrush("AccentBrush"));
            note.Margin = T(0, Gap.Help, 0, 0);
            AddTo(left, note);
            return note;
        }

        // A row that does not apply: its controls disabled (the gamepad passes
        // over them), its label dimmed, the reason shown
        public void SetRowApplies(Border row, bool on, TextBlock why)
        {
            SetRowApplies(row, on, why, !on);
        }

        // explain: the reason shown (not when the whole card does not apply: it
        // says why under its title)
        public void SetRowApplies(Border row, bool on, TextBlock why, bool explain)
        {
            var g = (Grid)row.Child;
            var left = (StackPanel)g.Children[0];
            var label = (TextBlock)left.Children[0];
            if (on) label.ClearValue(TextBlock.ForegroundProperty);
            else label.Foreground = ResBrush("DimBrush");
            foreach (UIElement c in g.Children) if (c != left) c.IsEnabled = on;
            if (why != null) why.Visibility = explain ? Visibility.Visible : Visibility.Collapsed;
        }

        // A card (group) that applies only with other settings (Group.When): the
        // reason under its title, shown while it does not apply (SetCardApplies)
        public TextBlock AddCardReason(Border card, string reason)
        {
            var sp = (StackPanel)card.Child;
            var why = NewHelp(reason, ResBrush("AccentBrush"));
            why.Margin = T(0, 0, 0, Gap.Control);
            // under the title (the first child when the card has one)
            sp.Children.Insert(sp.Children.Count > 0 && sp.Children[0] is TextBlock ? 1 : 0, why);
            return why;
        }

        // A card that does not apply: every row of it as SetRowApplies, the reason
        // under the title instead of under each row
        public void SetCardApplies(Border card, bool on, TextBlock why)
        {
            foreach (var row in ((StackPanel)card.Child).Children.Cast<UIElement>().OfType<Border>())
                if (row.Child is Grid && ((Grid)row.Child).Children.Count > 0 && ((Grid)row.Child).Children[0] is StackPanel)
                    SetRowApplies(row, on, null, false);
            if (why != null) why.Visibility = on ? Visibility.Collapsed : Visibility.Visible;
        }

        // Label with its help below: the left part of a row, or the top of a stacked one
        public StackPanel NewLabelBlock(string label, string help)
        {
            var sp = NewPanel();
            AddTo(sp, NewText(label, Fs.Label, null, false, true));
            if (!string.IsNullOrEmpty(help))
            {
                var h = NewHelp(help);
                h.Margin = T(0, Gap.Help, 0, 0);
                AddTo(sp, h);
            }
            return sp;
        }

        Button NewActionIcon(int glyph, string tip)
        {
            var b = NewIconButton(glyph, tip);
            b.Margin = T(Gap.Icon, 0, 0, 0);
            b.VerticalAlignment = VerticalAlignment.Center;
            return b;
        }

        // Empties a field (an image or icon file goes to the Recycle Bin: its click asks first)
        public Button NewClearButton(string tip) { return NewActionIcon(Glyph.Clear, tip); }
        public Button NewEditButton(string tip) { return NewActionIcon(Glyph.Edit, tip); }

        // Deletes an entry of a list: its click asks first
        public Button NewDeleteButton(string tip) { return NewActionIcon(Glyph.Delete, tip); }

        // Back to the default, or to the value of All tiles
        public Button NewResetIcon(string tip) { return NewActionIcon(Glyph.Reset, tip); }

        // An icon button that would do nothing is hidden: its room stays, nothing moves
        public static void SetActionVisible(UIElement b, bool canAct)
        {
            if (b != null) b.Visibility = canAct ? Visibility.Visible : Visibility.Hidden;
        }

        // A value that is not valid: red border until it is fixed
        public void MarkInvalid(Control c, bool invalid)
        {
            if (invalid) c.BorderBrush = ResBrush("DangerBrush");
            else c.ClearValue(Control.BorderBrushProperty);
        }

        // Text cut with an ellipsis when it does not fit; the full text (or 'full')
        // as its tooltip, only while it is cut
        public static void SetTrimmed(TextBlock t, string full = null)
        {
            t.TextTrimming = TextTrimming.CharacterEllipsis;
            t.ToolTip = full ?? t.Text;
            t.ToolTipOpening += (s, e) =>
            {
                if (full != null) return;
                if (!IsTrimmed(t)) { e.Handled = true; return; }
                t.ToolTip = t.Text;   // the text may have changed since
            };
        }

        public static bool IsTrimmed(TextBlock t)
        {
            var m = new TextBlock { Text = t.Text, FontSize = t.FontSize, FontFamily = t.FontFamily, FontWeight = t.FontWeight, FontStyle = t.FontStyle };
            m.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            return m.DesiredSize.Width > t.ActualWidth + 0.5;
        }

        // Slider + text box for a number in a range (docs/OptionsUI.md, 3): the slider
        // fills the row, the box (always FieldWidth.S) ends it with the unit written
        // inside it, on the right. 'changed' gets the text (empty allowed: the caller
        // says what it means); text that is not a number gets the red border and is
        // not reported. slider false: the box only (a port).
        public NumberField NewNumberField(double min, double max, double step, string unit, Action<string> changed,
            bool slider = true, double smallChange = 0)
        {
            var f = new NumberField();
            var g = NewGrid(slider ? "*" : "Auto", "Auto");
            double small = smallChange > 0 ? smallChange : step;
            var sl = new Slider { Minimum = min, Maximum = max, TickFrequency = step, SmallChange = small, LargeChange = small, VerticalAlignment = VerticalAlignment.Center };
            var tb = new TextBox { Width = FieldWidth.S, TextAlignment = TextAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
            if (slider) { tb.Margin = T(Gap.Group, 0, 0, 0); g.Children.Add(sl); }
            if (!slider) g.HorizontalAlignment = HorizontalAlignment.Right;
            SetCol(tb, 1);
            g.Children.Add(tb);
            // the unit inside the box, on the right (UnitBox style: the unit is the Tag)
            tb.Style = ResStyle("UnitBox");
            if (!string.IsNullOrEmpty(unit)) tb.Tag = unit;
            NumericOnly(tb, min < 0, step != Math.Floor(step));
            f.Slider = sl; f.Box = tb; f.Root = g;
            sl.ValueChanged += (s, e) =>
            {
                if (f.Sync) return;
                double v = sl.Value;
                string t = Core.FormatNumber(v, step);
                f.Sync = true;
                tb.Text = t;
                f.Sync = false;
                MarkInvalid(tb, false);
                changed(t);
            };
            tb.TextChanged += (s, e) =>
            {
                if (f.Sync) return;
                string t = tb.Text.Trim();
                double n;
                bool bad = t != "" && !Core.TryNumber(t, out n);
                MarkInvalid(tb, bad);
                if (bad) return;
                if (Core.TryNumber(t, out n))
                {
                    f.Sync = true;
                    sl.Value = Math.Min(max, Math.Max(min, n));
                    f.Sync = false;
                }
                changed(t);
            };
            return f;
        }

        // Text box + px / % combo for a length; switching the unit converts the number on
        // the main screen (axis "W" or "H"). 'changed' gets the value as written ("" when empty).
        public SizeField NewSizeField(string axis, Action<string> changed)
        {
            var f = new SizeField();
            var sp = NewPanel(Orientation.Horizontal);
            var tb = new TextBox { Width = FieldWidth.S, TextAlignment = TextAlignment.Right, Margin = T(0, 0, Gap.Control, 0), VerticalAlignment = VerticalAlignment.Center };
            NumericOnly(tb, false, true);   // a length: never below 0
            var unit = NewChoiceBox(new[] { new[] { "px", "px" }, new[] { "%", "%" } }, "px", null);
            unit.Width = FieldWidth.Unit;
            unit.VerticalAlignment = VerticalAlignment.Center;
            AddTo(sp, tb); AddTo(sp, unit);
            f.Box = tb; f.Unit = unit; f.Root = sp;
            tb.TextChanged += (s, e) =>
            {
                if (f.Sync) return;
                double n;
                bool bad = tb.Text.Trim() != "" && !Core.TryNumber(tb.Text.Trim(), out n);
                MarkInvalid(tb, bad);
                if (!bad) changed(f.Value);
            };
            unit.SelectionChanged += (s, e) =>
            {
                if (f.Sync) return;
                int full = axis == "W" ? screenPx[0] : screenPx[1];
                string t = tb.Text.Trim();
                double n;
                if (full > 0 && Core.TryNumber(t, out n))
                    t = f.IsPct ? Core.FormatNumber(n * 100 / full, 0.01) : Core.FormatNumber(n * full / 100, 1);
                f.Sync = true;
                tb.Text = t;
                f.Sync = false;
                changed(f.Value);
            };
            return f;
        }

        // One of a fixed set (docs/OptionsUI.md, 3): a combo of { value, label } pairs,
        // 'current' selected; 'changed' (may be null) gets the value picked. Callers
        // that put a value in (SelectChoice) keep their own guard against the echo.
        public static ComboBox NewChoiceBox(IEnumerable<string[]> choices, string current, Action<string> changed)
        {
            var cb = new ComboBox();
            if (!SetChoices(cb, choices, current) && cb.Items.Count > 0) cb.SelectedIndex = 0;
            if (changed != null)
                cb.SelectionChanged += (s, e) => { string v = ChoiceValue(cb); if (v != null) changed(v); };
            return cb;
        }

        // The { value, label } pairs of a combo, again (a list read from disk that
        // changed), 'current' selected; false when it is not one of them (nothing
        // selected). It reports the change like a pick: callers keep their guard.
        public static bool SetChoices(ComboBox cb, IEnumerable<string[]> choices, string current)
        {
            cb.SelectedIndex = -1;
            cb.Items.Clear();
            foreach (var c in choices) cb.Items.Add(new ComboBoxItem { Content = c[1], Tag = c[0] });
            return SelectChoice(cb, current);
        }

        // Selects the item with this value (case-insensitive); false when there is none
        public static bool SelectChoice(ComboBox cb, string value)
        {
            foreach (var o in cb.Items)
            {
                var i = o as ComboBoxItem;
                if (i != null && string.Equals(i.Tag as string, value ?? "", StringComparison.OrdinalIgnoreCase))
                {
                    cb.SelectedItem = i;
                    return true;
                }
            }
            return false;
        }

        // The value of the item selected, null when none
        public static string ChoiceValue(ComboBox cb)
        {
            var i = cb.SelectedItem as ComboBoxItem;
            return i != null ? i.Tag as string : null;
        }

        // The characters a box of NumericOnly takes, null for any other field (the
        // on-screen keyboard shows its number pad with them)
        static readonly ConditionalWeakTable<TextBox, string> numericChars = new ConditionalWeakTable<TextBox, string>();

        public static string NumericChars(FrameworkElement field)
        {
            string chars;
            var tb = field as TextBox;
            return tb != null && numericChars.TryGetValue(tb, out chars) ? chars : null;
        }

        // Text a number box can hold while it is written: digits, the minus sign once
        // and at the start, the decimal point once, each only if 'chars' has it.
        // The keyboard, a paste and the on-screen keyboard go through it.
        public static bool IsPartialNumber(string chars, string text)
        {
            int i = text.Length > 0 && text[0] == '-' && chars.IndexOf('-') >= 0 ? 1 : 0;
            bool dot = false;
            for (; i < text.Length; i++)
            {
                char ch = text[i];
                if (ch >= '0' && ch <= '9') continue;
                if (ch == '.' && !dot && chars.IndexOf('.') >= 0) { dot = true; continue; }
                return false;
            }
            return true;
        }

        // A box for numbers only: typing and pasting change it only into what can
        // still be a number (IsPartialNumber; a comma becomes the decimal point).
        // What is not a number yet (a lone "-") gets MarkInvalid. A value that was
        // not a number to begin with (a formula) can only be deleted.
        public static void NumericOnly(TextBox tb, bool negative, bool decimals)
        {
            string chars = "0123456789" + (decimals ? "." : "") + (negative ? "-" : "");
            numericChars.Remove(tb);
            numericChars.Add(tb, chars);
            // the text with the selection replaced by 's'
            Func<string, string> after = s => tb.Text.Remove(tb.SelectionStart, tb.SelectionLength).Insert(tb.SelectionStart, s);
            InputMethod.SetIsInputMethodEnabled(tb, false);
            tb.PreviewTextInput += (s, e) =>
            {
                string t = decimals && e.Text == "," ? "." : e.Text;
                e.Handled = true;
                if (!IsPartialNumber(chars, after(t))) return;
                if (t == e.Text) { e.Handled = false; return; }
                int at = tb.SelectionStart;
                tb.SelectedText = t;
                tb.CaretIndex = at + t.Length;
            };
            // Space does not come as text input
            tb.PreviewKeyDown += (s, e) => { if (e.Key == Key.Space) e.Handled = true; };
            DataObject.AddPastingHandler(tb, (s, e) =>
            {
                var text = e.DataObject.GetDataPresent(DataFormats.UnicodeText) ? e.DataObject.GetData(DataFormats.UnicodeText) as string : null;
                if (text == null || !IsPartialNumber(chars, after(text.Trim()))) e.CancelCommand();
            });
        }

        // Buttons of the same width filling a row, 8 apart (docs/OptionsUI.md, 4)
        public static Grid NewEqualButtons(params FrameworkElement[] items)
        {
            var g = new Grid();
            for (int i = 0; i < items.Length; i++)
            {
                if (i > 0) g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Gap.Control) });
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                SetCol(items[i], i * 2);
                g.Children.Add(items[i]);
            }
            return g;
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
        // first is the main action and the default). Titled with the action, not
        // "Raintile". danger: the first button deletes or cannot be undone: it is
        // red, and the last one (Cancel) is the default for Enter and Escape.
        public DialogResultInfo ShowDialog(string title, string message, string[] buttons = null, string inputText = null, bool danger = false)
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
            sp.Margin = Gap.Dialog;
            sp.MinWidth = 380;
            sp.MaxWidth = 520;
            d.Content = sp;
            AddTo(sp, NewText(message, Fs.Label, null, false, true));
            TextBox tb = null;
            if (inputText != null)
            {
                tb = new TextBox { Text = inputText, Margin = T(0, Gap.Group, 0, 0) };
                AddTo(sp, tb);
            }
            var bar = NewPanel(Orientation.Horizontal);
            bar.HorizontalAlignment = HorizontalAlignment.Right;
            bar.Margin = T(0, Gap.DialogBar, 0, 0);
            AddTo(sp, bar);
            for (int i = 0; i < buttons.Length; i++)
            {
                var b = NewButton(buttons[i], i == 0 ? (danger && buttons.Length > 1 ? "DangerButton" : "AccentButton") : "");
                b.Margin = T(Gap.Control, 0, 0, 0);
                b.MinWidth = 90;
                string label = buttons[i];
                bool isDefault = danger && buttons.Length > 1 ? i == buttons.Length - 1 : i == 0;
                if (isDefault) b.IsDefault = true;
                b.Click += (s, e) => { result = label; d.Close(); };
                AddTo(bar, b);
                // B closes the dialog as its last button (Cancel, or the only one)
                if (i == buttons.Length - 1)
                {
                    var hint = AddPadHint(b, Glyph.PadB);
                    d.Closed += (s, e) => RemovePadHint(hint);
                }
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
