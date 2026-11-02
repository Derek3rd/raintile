// Raintile Options: settings values, a control for each kind of setting, rows,
// cards and settings pages.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;

namespace RaintileOptions
{
    // Controls of one setting
    class Ctl
    {
        public string Kind;
        public CheckBox Box;
        public Panel Panel;
        public TextBox Text;
        public Slider Slider;
        public double Step;
        public RadioButton Px, Pct;
        public string Axis;
        public Button Swatch, Button;
        public Control Input;   // text, font, category, secret
        public WrapPanel Area, Monitor;
    }

    class ResetInfo { public string[] KeyList; public Button Button; }

    public partial class OptionsApp
    {
        List<SettingItem> settings;
        Dictionary<string, string> fileValues = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);   // as in Settings.inc
        Dictionary<string, string> values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);       // as in the window
        Dictionary<string, Ctl> ctl = new Dictionary<string, Ctl>(StringComparer.OrdinalIgnoreCase);
        List<ResetInfo> resets = new List<ResetInfo>();
        Dictionary<string, Button> keyButtons = new Dictionary<string, Button>(StringComparer.OrdinalIgnoreCase);
        bool updating = true;
        Button capturing;
        bool dirtySettings;
        int[] screenPx = { 0, 0 };

        string V(string key)
        {
            string v;
            return values.TryGetValue(key, out v) && v != null ? v : "";
        }

        void ReadValues()
        {
            settings = Core.ReadSettings(Core.SettingsFile);
            foreach (var item in settings) { fileValues[item.Key] = item.Value; values[item.Key] = item.Value; }
            // a SteamGridDB key written in clear is encrypted in Settings.inc right away
            string key = V("SteamGridDBKey");
            if (key != "" && !key.StartsWith(Core.SECRET_PREFIX))
            {
                try
                {
                    string enc = Core.ProtectSecret(key);
                    Core.WriteSettings(Core.SettingsFile, new Dictionary<string, string> { { "SteamGridDBKey", enc } });
                    values["SteamGridDBKey"] = enc;
                    fileValues["SteamGridDBKey"] = enc;
                }
                catch { }
            }
            try { screenPx = GetScreenPixels(); } catch { }
        }

        void UpdateDirty()
        {
            bool changed = values.Any(kv => { string f; fileValues.TryGetValue(kv.Key, out f); return kv.Value != f; });
            bool dirty = changed || changedFiles.Count > 0 || needsRefresh;
            dirtySettings = dirty;
            status.Text = dirty ? "Unsaved changes" : "";
            status.Foreground = dirty ? ResBrush("AccentBrush") : ResBrush("DimBrush");
            win.Title = dirty ? "Raintile - Options *" : "Raintile - Options";
        }

        void UpdateResets()
        {
            foreach (var r in resets)
            {
                bool differs = false;
                foreach (var k in r.KeyList)
                {
                    string d;
                    if (Schema.Defaults.TryGetValue(k, out d) && V(k) != d) differs = true;
                }
                r.Button.Visibility = differs ? Visibility.Visible : Visibility.Hidden;
            }
        }

        // The same key used by two actions: both are marked
        void UpdateKeyConflicts()
        {
            var byKey = new Dictionary<string, List<string>>();
            foreach (var k in keyButtons.Keys)
            {
                if (string.Equals(k, "OpenHotKey", StringComparison.OrdinalIgnoreCase)) continue;
                string v = V(k).Trim().ToUpperInvariant();
                if (v == "") continue;
                if (!byKey.ContainsKey(v)) byKey[v] = new List<string>();
                byKey[v].Add(k);
            }
            foreach (var kv in keyButtons)
            {
                var b = kv.Value;
                string v = V(kv.Key).Trim().ToUpperInvariant();
                var others = v != "" && byKey.ContainsKey(v) ? byKey[v].Where(x => x != kv.Key).ToList() : new List<string>();
                if (others.Count > 0)
                {
                    b.BorderBrush = ResBrush("DangerBrush");
                    b.ToolTip = "Also used by: " + string.Join(", ", others);
                }
                else
                {
                    b.ClearValue(Control.BorderBrushProperty);
                    b.ToolTip = "Click, then press a key";
                }
            }
        }

        void SetValue(string key, string value)
        {
            if (updating) return;
            values[key] = value;
            UpdateDirty();
            UpdateResets();
            if (keyButtons.ContainsKey(key)) UpdateKeyConflicts();
        }

        static bool TryNum(string t, out double n) { return Core.TryNumber(t, out n); }

        // Shows the current value of 'key' in its controls (after a reset)
        void UpdateControl(string key)
        {
            Ctl c;
            if (!ctl.TryGetValue(key, out c)) return;
            string v = V(key);
            updating = true;
            try
            {
                switch (c.Kind)
                {
                    case "bool": c.Box.IsChecked = v == "1"; break;
                    case "choice":
                        foreach (RadioButton rb in c.Panel.Children) rb.IsChecked = string.Equals(((string[])rb.Tag)[1], v, StringComparison.OrdinalIgnoreCase);
                        break;
                    case "int":
                    case "float":
                        c.Text.Text = v;
                        double n;
                        if (TryNum(v, out n)) c.Slider.Value = Math.Min(c.Slider.Maximum, Math.Max(c.Slider.Minimum, n));
                        break;
                    case "size":
                        bool pct = v.Trim().EndsWith("%");
                        c.Text.Text = v.Trim().TrimEnd('%').Trim();
                        c.Pct.IsChecked = pct;
                        c.Px.IsChecked = !pct;
                        break;
                    case "color": c.Text.Text = v; c.Swatch.Background = NewColorBrush(v, true); break;
                    case "text": ((TextBox)c.Input).Text = v; break;
                    case "font": ((ComboBox)c.Input).Text = v; break;
                    case "secret": ((PasswordBox)c.Input).Password = Core.UnprotectSecret(v); break;
                    case "category": ((ComboBox)c.Input).SelectedItem = v; break;
                    case "stores":
                        foreach (CheckBox cb in c.Panel.Children) cb.IsChecked = v.Split('|').Contains(((string[])cb.Tag)[1]);
                        break;
                    case "pad":
                        foreach (ToggleButton tb in c.Panel.Children) tb.IsChecked = Regex.Split(v, @"\s+").Contains(((string[])tb.Tag)[1]);
                        break;
                    case "key":
                    case "combo": c.Button.Content = Schema.FormatHotKey(v); break;
                    case "screen":
                        var sa = Core.ScreenAreaFrom(values);
                        if (sa != null)
                        {
                            foreach (RadioButton rb in c.Area.Children) rb.IsChecked = ((string[])rb.Tag)[1] == sa[0];
                            foreach (var rb in c.Monitor.Children.OfType<RadioButton>()) rb.IsChecked = ((string[])rb.Tag)[1] == sa[1];
                        }
                        break;
                }
            }
            finally { updating = false; }
        }

        // --- Controls for each kind of setting ----------------------------------------

        UIElement NewBoolControl(string key)
        {
            var cb = new CheckBox { Tag = key, IsChecked = V(key) == "1" };
            cb.Click += (s, e) => SetValue(key, cb.IsChecked == true ? "1" : "0");
            ctl[key] = new Ctl { Kind = "bool", Box = cb };
            return cb;
        }

        UIElement NewChoiceControl(string key, List<string[]> choices)
        {
            var wp = new WrapPanel { MaxWidth = 460, HorizontalAlignment = HorizontalAlignment.Right };
            foreach (var c in choices)
            {
                var rb = new RadioButton { Style = ResStyle("Segment"), Content = c[1], GroupName = "choice_" + key, Tag = new[] { key, c[0] } };
                rb.IsChecked = string.Equals(V(key), c[0], StringComparison.OrdinalIgnoreCase);
                string val = c[0];
                rb.Click += (s, e) => SetValue(key, val);
                wp.Children.Add(rb);
            }
            ctl[key] = new Ctl { Kind = "choice", Panel = wp };
            return wp;
        }

        UIElement NewNumberControl(Item item)
        {
            string key = item.Key;
            var sp = NewPanel(Orientation.Horizontal);
            var sl = new Slider { Width = 220, Minimum = item.Min, Maximum = item.Max, TickFrequency = item.Step, SmallChange = item.Step, LargeChange = item.Step };
            var tb = new TextBox { Width = 72, Margin = T(12, 0, 0, 0), TextAlignment = TextAlignment.Right, Text = V(key) };
            double n;
            if (TryNum(V(key), out n)) sl.Value = Math.Min(item.Max, Math.Max(item.Min, n));
            var unit = NewText(item.Unit, 12, ResBrush("DimBrush"));
            unit.Width = 40;
            unit.Margin = T(8, 0, 0, 0);
            unit.VerticalAlignment = VerticalAlignment.Center;
            AddTo(sp, sl); AddTo(sp, tb); AddTo(sp, unit);
            var c = new Ctl { Kind = item.Kind, Slider = sl, Text = tb, Step = item.Step };
            ctl[key] = c;
            sl.ValueChanged += (s, e) =>
            {
                if (updating) return;
                string txt = Core.FormatNumber(sl.Value, c.Step);
                updating = true;
                tb.Text = txt;
                updating = false;
                SetValue(key, txt);
            };
            tb.TextChanged += (s, e) =>
            {
                if (updating) return;
                string t = tb.Text.Trim();
                double m;
                if (t != "" && !TryNum(t, out m)) return;
                if (t != "" && TryNum(t, out m))
                {
                    updating = true;
                    sl.Value = Math.Min(sl.Maximum, Math.Max(sl.Minimum, m));
                    updating = false;
                }
                SetValue(key, t);
            };
            return sp;
        }

        UIElement NewSizeControl(Item item)
        {
            string key = item.Key;
            string v = V(key).Trim();
            var sp = NewPanel(Orientation.Horizontal);
            var tb = new TextBox { Width = 80, TextAlignment = TextAlignment.Right, Margin = T(0, 0, 10, 0), Text = v.TrimEnd('%').Trim() };
            var px = new RadioButton();
            var pct = new RadioButton();
            foreach (var p in new[] { Tuple.Create(px, "px"), Tuple.Create(pct, "%") })
            {
                p.Item1.Style = ResStyle("Segment");
                p.Item1.Content = p.Item2;
                p.Item1.GroupName = "size_" + key;
                p.Item1.MinWidth = 42;
            }
            bool isPct = v.EndsWith("%");
            pct.IsChecked = isPct;
            px.IsChecked = !isPct;
            AddTo(sp, tb); AddTo(sp, px); AddTo(sp, pct);
            var c = new Ctl { Kind = "size", Text = tb, Px = px, Pct = pct, Axis = item.Axis };
            ctl[key] = c;
            tb.TextChanged += (s, e) =>
            {
                if (updating) return;
                SetValue(key, tb.Text.Trim() + (pct.IsChecked == true ? "%" : ""));
            };
            // switching unit converts the number (on the main screen)
            RoutedEventHandler unitClick = (s, e) =>
            {
                bool toPct = pct.IsChecked == true;
                int full = c.Axis == "W" ? screenPx[0] : screenPx[1];
                string t = tb.Text.Trim();
                double n;
                if (full > 0 && TryNum(t, out n))
                    t = toPct ? Core.FormatNumber(n * 100 / full, 0.01) : Core.FormatNumber(n * full / 100, 1);
                updating = true;
                tb.Text = t;
                updating = false;
                SetValue(key, t + (toPct ? "%" : ""));
            };
            px.Click += unitClick;
            pct.Click += unitClick;
            return sp;
        }

        UIElement NewColorControl(string key)
        {
            var sp = NewPanel(Orientation.Horizontal);
            var sw = NewButton("", "Swatch", "Pick a colour");
            sw.Background = NewColorBrush(V(key), true);
            var tb = new TextBox { Width = 170, Margin = T(10, 0, 0, 0), Text = V(key) };
            AddTo(sp, sw); AddTo(sp, tb);
            ctl[key] = new Ctl { Kind = "color", Swatch = sw, Text = tb };
            sw.Click += (s, e) =>
            {
                string n = SelectColor(tb.Text);
                if (n != null) tb.Text = n;
            };
            tb.TextChanged += (s, e) =>
            {
                if (updating) return;
                var brush = NewColorBrush(tb.Text, true);
                if (brush != null)
                {
                    sw.Background = brush;
                    tb.ClearValue(Control.BorderBrushProperty);
                    SetValue(key, tb.Text.Trim());
                }
                else tb.BorderBrush = ResBrush("DangerBrush");
            };
            return sp;
        }

        // Hidden text (the SteamGridDB key): shown as dots, saved encrypted
        UIElement NewSecretControl(string key)
        {
            var pb = new PasswordBox { Width = 300, Password = Core.UnprotectSecret(V(key)) };
            pb.PasswordChanged += (s, e) => SetValue(key, Core.ProtectSecret(pb.Password));
            ctl[key] = new Ctl { Kind = "secret", Input = pb };
            return pb;
        }

        UIElement NewTextControl(string key, double width = 300)
        {
            var tb = new TextBox { Width = width, Text = V(key) };
            tb.TextChanged += (s, e) => SetValue(key, tb.Text.Trim());
            ctl[key] = new Ctl { Kind = "text", Input = tb };
            return tb;
        }

        UIElement NewFontControl(string key)
        {
            var cb = new ComboBox { Width = 300, IsEditable = true };
            foreach (var f in Fonts.SystemFontFamilies.Select(x => x.Source).Distinct().OrderBy(x => x, StringComparer.OrdinalIgnoreCase)) cb.Items.Add(f);
            cb.Text = V(key);
            cb.AddHandler(TextBoxBase.TextChangedEvent, new TextChangedEventHandler((s, e) => SetValue(key, cb.Text.Trim())));
            ctl[key] = new Ctl { Kind = "font", Input = cb };
            return cb;
        }

        UIElement NewCategoryControl(string key)
        {
            var cb = new ComboBox { Width = 220 };
            var names = Core.GetCategoryFiles().Select(f => System.IO.Path.GetFileNameWithoutExtension(f.Name)).ToList();
            if (V(key) != "" && !names.Contains(V(key))) names.Add(V(key));
            foreach (var n in names) cb.Items.Add(n);
            cb.SelectedItem = V(key);
            cb.SelectionChanged += (s, e) => { if (cb.SelectedItem != null) SetValue(key, (string)cb.SelectedItem); };
            ctl[key] = new Ctl { Kind = "category", Input = cb };
            return cb;
        }

        UIElement NewStoresControl(string key)
        {
            var wp = new WrapPanel { MaxWidth = 470, HorizontalAlignment = HorizontalAlignment.Right };
            var current = V(key).Split('|').Select(x => x.Trim().Replace(".", "")).ToList();
            foreach (var store in Schema.SOURCES)
            {
                var cb = new CheckBox { Content = Schema.STORE_LABELS[store], Margin = T(18, 4, 0, 4), Tag = new[] { key, store }, IsChecked = current.Contains(store) };
                cb.Click += (s, e) =>
                {
                    var on = wp.Children.OfType<CheckBox>().Where(x => x.IsChecked == true).Select(x => ((string[])x.Tag)[1]);
                    SetValue(key, string.Join("|", on));
                };
                wp.Children.Add(cb);
            }
            ctl[key] = new Ctl { Kind = "stores", Panel = wp };
            return wp;
        }

        UIElement NewPadControl(string key)
        {
            var wp = new WrapPanel { MaxWidth = 470, HorizontalAlignment = HorizontalAlignment.Right };
            var current = Regex.Split(V(key).ToUpperInvariant(), @"\s+");
            foreach (var b in Schema.GAMEPAD_BUTTONS)
            {
                var tb = new ToggleButton { Style = ResStyle("Segment"), Content = b, Tag = new[] { key, b }, IsChecked = current.Contains(b) };
                tb.Click += (s, e) =>
                {
                    var on = wp.Children.OfType<ToggleButton>().Where(x => x.IsChecked == true).Select(x => ((string[])x.Tag)[1]);
                    SetValue(key, string.Join(" ", on));
                };
                wp.Children.Add(tb);
            }
            ctl[key] = new Ctl { Kind = "pad", Panel = wp };
            return wp;
        }

        // Key binding: click, then press the key (with the modifiers for 'combo')
        FrameworkElement NewKeyControl(string key, bool combo = false)
        {
            var sp = NewPanel(Orientation.Horizontal);
            var b = NewButton(Schema.FormatHotKey(V(key)), "KeyButton", "Click, then press a key");
            var clear = NewIconButton(0xE711, "No key");
            AddTo(sp, b); AddTo(sp, clear);
            ctl[key] = new Ctl { Kind = combo ? "combo" : "key", Button = b };
            keyButtons[key] = b;

            b.Click += (s, e) =>
            {
                capturing = b;
                b.Content = "Press a key\u2026";
                b.Focus();
            };
            b.LostKeyboardFocus += (s, e) =>
            {
                if (capturing == b)
                {
                    capturing = null;
                    b.Content = Schema.FormatHotKey(V(key));
                }
            };
            b.PreviewKeyDown += (s, e) =>
            {
                if (capturing != b) return;
                e.Handled = true;
                var k = e.Key == Key.System ? e.SystemKey : e.Key;
                int vk = KeyInterop.VirtualKeyFromKey(k);
                var mods = Keyboard.Modifiers;
                bool ctrl = (mods & ModifierKeys.Control) != 0, alt = (mods & ModifierKeys.Alt) != 0;
                bool shift = (mods & ModifierKeys.Shift) != 0, winKey = (mods & ModifierKeys.Windows) != 0;
                string value;
                if (combo)
                {
                    value = Schema.ToHotKey(vk, ctrl, alt, shift, winKey, true);
                    if (value == null)
                    {
                        // modifiers only so far: show them and wait for the key
                        var held = new List<string>();
                        if (ctrl) held.Add("CTRL");
                        if (alt) held.Add("ALT");
                        if (shift) held.Add("SHIFT");
                        if (winKey) held.Add("LWIN");
                        if (held.Count > 0) b.Content = Schema.FormatHotKey(string.Join(" ", held)) + " + \u2026";
                        return;
                    }
                }
                else
                {
                    value = Schema.ToHotKey(vk, false, false, false, false, false);
                    if (value == null) return;
                }
                capturing = null;
                b.Content = Schema.FormatHotKey(value);
                SetValue(key, value);
            };
            clear.Click += (s, e) =>
            {
                SetValue(key, "");
                UpdateControl(key);
            };
            return sp;
        }

        UIElement NewScreenControl()
        {
            var sa = Core.ScreenAreaFrom(values) ?? new[] { "", "" };
            var sp = NewPanel();
            sp.HorizontalAlignment = HorizontalAlignment.Right;
            var area = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Right };
            var mon = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Right, Margin = T(0, 6, 0, 0) };
            foreach (var a in new[] { new[] { "SCREENAREA", "Whole screen" }, new[] { "WORKAREA", "Work area" } })
            {
                var rb = new RadioButton { Style = ResStyle("Segment"), Content = a[1], GroupName = "screen_area", Tag = new[] { "area", a[0] }, IsChecked = sa[0] == a[0] };
                area.Children.Add(rb);
            }
            var monLabel = NewText("Monitor", 12, ResBrush("DimBrush"));
            monLabel.Margin = T(0, 0, 10, 0);
            monLabel.VerticalAlignment = VerticalAlignment.Center;
            mon.Children.Add(monLabel);
            foreach (var m in new[] { new[] { "", "Main" }, new[] { "1", "1" }, new[] { "2", "2" }, new[] { "3", "3" }, new[] { "4", "4" } })
            {
                var rb = new RadioButton { Style = ResStyle("Segment"), Content = m[1], GroupName = "screen_monitor", Tag = new[] { "monitor", m[0] }, MinWidth = 38, IsChecked = sa[1] == m[0] };
                mon.Children.Add(rb);
            }
            AddTo(sp, area); AddTo(sp, mon);
            var c = new Ctl { Kind = "screen", Area = area, Monitor = mon };
            ctl["ScreenX"] = c;
            foreach (var rb in area.Children.OfType<RadioButton>().Concat(mon.Children.OfType<RadioButton>()))
            {
                rb.Click += (s, e) =>
                {
                    var ar = area.Children.OfType<RadioButton>().FirstOrDefault(x => x.IsChecked == true);
                    var mr = mon.Children.OfType<RadioButton>().FirstOrDefault(x => x.IsChecked == true);
                    var n = Core.ScreenAreaTo(ar != null ? ((string[])ar.Tag)[1] : "SCREENAREA", mr != null ? ((string[])mr.Tag)[1] : "");
                    foreach (var kv in n) values[kv.Key] = kv.Value;
                    SetValue("ScreenX", n["ScreenX"]);
                };
            }
            ctl["ScreenY"] = c; ctl["ScreenW"] = c; ctl["ScreenH"] = c;
            return sp;
        }

        UIElement NewActionControl(string action, string label)
        {
            var b = NewButton(label, action == "Import" ? "AccentButton" : "");
            b.Click += (s, e) => InvokeAction(action);
            return b;
        }

        // --- Rows, cards, pages ---------------------------------------------------------

        Button NewResetButton(string[] keys)
        {
            var b = NewIconButton(0xE7A7, "Restore default");
            b.Margin = T(6, 0, 0, 0);
            b.VerticalAlignment = VerticalAlignment.Center;
            b.Visibility = Visibility.Hidden;
            b.Click += (s, e) =>
            {
                foreach (var k in keys) { string d; if (Schema.Defaults.TryGetValue(k, out d)) values[k] = d; }
                foreach (var k in keys) UpdateControl(k);
                UpdateDirty();
                UpdateResets();
                UpdateKeyConflicts();
            };
            resets.Add(new ResetInfo { KeyList = keys, Button = b });
            return b;
        }

        Border NewRow(string label, string help, UIElement control, UIElement reset)
        {
            var g = NewGrid("*", "Auto", "34");
            g.Margin = T(0, 11);
            var left = NewPanel();
            left.VerticalAlignment = VerticalAlignment.Center;
            left.Margin = T(0, 0, 24, 0);
            AddTo(left, NewText(label, 13.5));
            if (!string.IsNullOrEmpty(help))
            {
                var h = NewText(help, 12, ResBrush("DimBrush"), false, true);
                h.Margin = T(0, 3, 0, 0);
                AddTo(left, h);
            }
            g.Children.Add(left);
            if (control != null)
            {
                var fe = control as FrameworkElement;
                if (fe != null) fe.VerticalAlignment = VerticalAlignment.Center;
                SetCol(control, 1);
                g.Children.Add(control);
            }
            if (reset != null) { SetCol(reset, 2); g.Children.Add(reset); }
            return new Border { BorderBrush = ResBrush("LineBrush"), BorderThickness = T(0, 1, 0, 0), Child = g };
        }

        public Border NewCard(string title, string help)
        {
            var b = new Border { Style = ResStyle("Card") };
            var sp = NewPanel();
            b.Child = sp;
            if (!string.IsNullOrEmpty(title))
            {
                var h = NewText(title.ToUpperInvariant(), 11.5, ResBrush("DimBrush"), true);
                h.Margin = T(0, 12, 0, 4);
                AddTo(sp, h);
            }
            if (!string.IsNullOrEmpty(help))
            {
                var x = NewText(help, 12, ResBrush("DimBrush"), false, true);
                x.Margin = T(0, 0, 0, 8);
                AddTo(sp, x);
            }
            return b;
        }

        static StackPanel CardPanel(Border card) { return (StackPanel)card.Child; }

        // Row of one schema item (null if its settings are not in Settings.inc)
        UIElement NewItemRow(Item item)
        {
            string k = item.Key;
            var screenKeys = new[] { "ScreenX", "ScreenY", "ScreenW", "ScreenH" };
            switch (item.Kind)
            {
                case "info": return NewRow(item.Label, item.Help, null, null);
                case "action": return NewRow(item.Label, item.Help, NewActionControl(item.Key, item.Key == "Import" ? "Import games" : "Open"), null);
                case "screen":
                    if (!screenKeys.All(values.ContainsKey)) return null;
                    if (Core.ScreenAreaFrom(values) == null)
                    {
                        // custom values (formulas, coordinates): plain fields
                        var sp = NewPanel();
                        foreach (var sk in screenKeys)
                        {
                            var row = NewPanel(Orientation.Horizontal);
                            row.Margin = T(0, 2);
                            var l = NewText(sk, 12, ResBrush("DimBrush"));
                            l.Width = 64;
                            l.VerticalAlignment = VerticalAlignment.Center;
                            AddTo(row, l); AddTo(row, NewTextControl(sk, 230));
                            AddTo(sp, row);
                        }
                        return NewRow(item.Label, "Custom values: written as they are.", sp, NewResetButton(screenKeys));
                    }
                    return NewRow(item.Label, item.Help, NewScreenControl(), NewResetButton(screenKeys));
                case "keys":
                    var present = item.Pair.Where(values.ContainsKey).ToArray();
                    if (present.Length == 0) return null;
                    var kp = NewPanel(Orientation.Horizontal);
                    foreach (var kk in present)
                    {
                        var kc = NewKeyControl(kk);
                        kc.Margin = T(6, 0, 0, 0);
                        AddTo(kp, kc);
                    }
                    return NewRow(item.Label, item.Help, kp, NewResetButton(present));
            }
            if (!values.ContainsKey(k)) return null;
            UIElement control = null;
            switch (item.Kind)
            {
                case "bool": control = NewBoolControl(k); break;
                case "choice":
                    // a value of its own: plain field
                    control = item.Choices.Any(c => c[0] == V(k)) ? NewChoiceControl(k, item.Choices) : NewTextControl(k);
                    break;
                case "int":
                case "float": control = NewNumberControl(item); break;
                case "size": control = Regex.IsMatch(V(k), @"^\s*-?[\d.]+\s*%?\s*$") ? NewSizeControl(item) : NewTextControl(k); break;
                case "color": control = NewColorControl(k); break;
                case "text": control = NewTextControl(k); break;
                case "secret": control = NewSecretControl(k); break;
                case "font": control = NewFontControl(k); break;
                case "category": control = NewCategoryControl(k); break;
                case "stores": control = NewStoresControl(k); break;
                case "pad": control = NewPadControl(k); break;
                case "key": control = NewKeyControl(k); break;
                case "combo": control = NewKeyControl(k, true); break;
            }
            return NewRow(item.Label, item.Help, control, NewResetButton(new[] { k }));
        }

        ScrollViewer NewPageScroller(out StackPanel sp)
        {
            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            sp = NewPanel();
            sp.Margin = T(36, 4, 36, 24);
            sp.MaxWidth = 920;
            sp.HorizontalAlignment = HorizontalAlignment.Left;
            sv.Content = sp;
            return sv;
        }

        UIElement NewSettingsPage(Page page)
        {
            StackPanel sp;
            var sv = NewPageScroller(out sp);
            var schemaKeys = new HashSet<string>(Schema.SchemaKeys(), StringComparer.OrdinalIgnoreCase);
            foreach (var group in page.Groups)
            {
                var card = NewCard(group.Title, group.Help);
                int rows = 0;
                if (group.Found)
                {
                    // tiles of games no longer installed, then the list of the games
                    // and apps found (cards of their own)
                    AddTo(sp, NewMissingCard());
                    AddTo(sp, NewFoundCard());
                    continue;
                }
                if (group.Other)
                {
                    // Settings.inc entries without a page of their own
                    foreach (var item in settings)
                    {
                        if (schemaKeys.Contains(item.Key)) continue;
                        CardPanel(card).Children.Add(NewRow(item.Key, item.Description, NewTextControl(item.Key), null));
                        rows++;
                    }
                }
                else
                {
                    foreach (var item in group.Items)
                    {
                        var row = NewItemRow(item);
                        if (row != null) { CardPanel(card).Children.Add(row); rows++; }
                    }
                }
                if (rows > 0) AddTo(sp, card);
            }
            return sv;
        }
    }
}
