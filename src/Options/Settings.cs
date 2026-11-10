// Raintile Options: settings values, a control for each kind of setting, rows,
// cards and settings pages.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Automation;
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
        public List<CheckBox> Boxes;   // stores: one switch per store
        public TextBox Text;
        public Button Swatch, Button, Clear;
        public Control Input;   // text, font, category, secret, choice
        public ComboBox Area, Monitor;
        public NumberField Num;
        public SizeField Size;
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

        // Something in the window that Save and refresh would write: settings,
        // category files, widget settings (the profile in use aside)
        bool SettingsUnsaved()
        {
            bool changed = values.Any(kv => { string f; fileValues.TryGetValue(kv.Key, out f); return kv.Value != f; });
            return changed || changedFiles.Count > 0 || needsRefresh || widgetValues.Count > 0;
        }

        void UpdateDirty()
        {
            bool dirty = SettingsUnsaved() || ProfileUnsaved;
            dirtySettings = dirty;
            status.Text = dirty ? "Unsaved changes." : "";
            status.Foreground = dirty ? ResBrush("AccentBrush") : ResBrush("DimBrush");
            win.Title = dirty ? "Raintile - Options *" : "Raintile - Options";
            QueueProfileState();
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
                SetActionVisible(r.Button, differs);
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
            UpdateWhenRows();
            // the wheel's preview follows every setting (sizes, mode, colours)
            if (wheelCanvas != null) DrawWheel();
        }

        // Rows that apply only with other settings (Item.When): disabled, with
        // the reason under their label, so they are seen and can be found
        class WhenRow { public string When, GroupWhen; public Border Row; public TextBlock Why; }
        readonly List<WhenRow> whenRows = new List<WhenRow>();
        // and whole cards (Group.When)
        // (Outer: the page's switch, Own: the group's When, whose reason Why shows)
        class WhenCard { public string Outer, Own; public Border Card; public TextBlock Why; public UIElement Keep; }
        readonly List<WhenCard> whenCards = new List<WhenCard>();

        // "Key=a|b;Key2=c": every condition holds (one of its values)
        bool WhenHolds(string when)
        {
            foreach (var cond in when.Split(';'))
            {
                var kv = cond.Split(new[] { '=' }, 2);
                // (a list, ImportStores "Steam|Folders": one of its values is enough)
                var have = V(kv[0]).Split('|').Select(x => x.Trim().Replace(".", ""));
                if (!kv[1].Split('|').Any(x => have.Contains(x, StringComparer.OrdinalIgnoreCase))) return false;
            }
            return true;
        }

        // "Only with Layout: Wheel (Tiles page)": the settings it needs by their
        // labels, with their page when it is another one
        static string WhenReason(string when, Page here)
        {
            var parts = new List<string>();
            foreach (var cond in when.Split(';'))
            {
                var kv = cond.Split(new[] { '=' }, 2);
                Page page; var item = Schema.ItemOf(kv[0], out page);
                if (item == null) { parts.Add(cond); continue; }
                string what = item.Kind == "bool" ? item.Label + " on"
                    : item.Label + ": " + string.Join(" or ", kv[1].Split('|').Select(v =>
                        { var c = item.Choices == null ? null : item.Choices.FirstOrDefault(x => string.Equals(x[0], v, StringComparison.OrdinalIgnoreCase)); return c != null ? c[1] : v; }));
                if (page != null && page != here) what += " (" + page.Title + " page)";
                parts.Add(what);
            }
            return "Only with " + string.Join(" and ", parts) + ".";
        }

        void UpdateWhenRows()
        {
            foreach (var c in whenCards)
            {
                bool outer = c.Outer == null || WhenHolds(c.Outer), own = c.Own == null || WhenHolds(c.Own);
                SetCardApplies(c.Card, outer && own, null);
                // a card with a header switch (Group.Store): what is not a row (the
                // folders' grid) follows it too, the switch stays usable
                if (c.Keep != null)
                    foreach (UIElement x in CardPanel(c.Card).Children)
                        if (x != c.Keep && !(x is Border) && !(x is TextBlock)) x.IsEnabled = outer && own;
                if (c.Why != null) c.Why.Visibility = outer && !own ? Visibility.Visible : Visibility.Collapsed;
            }
            foreach (var w in whenRows)
            {
                // in a card that does not apply: disabled, the reason is the card's
                bool card = w.GroupWhen == null || WhenHolds(w.GroupWhen), own = WhenHolds(w.When);
                SetRowApplies(w.Row, card && own, w.Why, card && !own);
            }
            UpdateNavApplies();
        }

        // Shows the current value of 'key' in its controls (after a reset)
        void UpdateControl(string key)
        {
            UpdateWhenRows();
            Ctl c;
            if (!ctl.TryGetValue(key, out c)) return;
            string v = V(key);
            updating = true;
            // a value put back (reset) is valid again
            if (c.Text != null) MarkInvalid(c.Text, false);
            try
            {
                switch (c.Kind)
                {
                    case "bool": c.Box.IsChecked = v == "1"; break;
                    case "choice": SelectChoice((ComboBox)c.Input, v); break;
                    case "int":
                    case "float": c.Num.Show(v, c.Num.Slider.Minimum); break;
                    case "size": c.Size.Show(v); break;
                    case "color": c.Text.Text = v; c.Swatch.Background = NewColorBrush(v, true); break;
                    case "text": ((TextBox)c.Input).Text = v; break;
                    case "folders": Action redraw; if (folderLists.TryGetValue(key, out redraw)) redraw(); break;
                    case "font": ((ComboBox)c.Input).Text = v; break;
                    case "secret": ((PasswordBox)c.Input).Password = Core.UnprotectSecret(v); break;
                    case "category": ((ComboBox)c.Input).SelectedItem = v; break;
                    case "stores":
                        foreach (var cb in c.Boxes) cb.IsChecked = v.Split('|').Select(x => x.Trim().Replace(".", "")).Contains(((string[])cb.Tag)[1]);
                        break;
                    case "pad": ShowPadSlots(key); break;
                    case "key":
                    case "combo": c.Button.Content = Schema.FormatHotKey(v); SetActionVisible(c.Clear, v.Trim() != ""); break;
                    case "screen":
                        var sa = Core.ScreenAreaFrom(values);
                        if (sa != null) { SelectChoice(c.Area, sa[0]); SelectChoice(c.Monitor, sa[1]); }
                        break;
                }
            }
            finally { updating = false; }
        }

        // --- Controls for each kind of setting ----------------------------------------

        UIElement NewBoolControl(string key)
        {
            var cb = new CheckBox { Tag = key, IsChecked = V(key) == "1", HorizontalAlignment = HorizontalAlignment.Right };
            cb.Click += (s, e) => SetValue(key, cb.IsChecked == true ? "1" : "0");
            ctl[key] = new Ctl { Kind = "bool", Box = cb };
            return cb;
        }

        // one of a fixed set: a combo filling the control column
        UIElement NewChoiceControl(string key, List<string[]> choices)
        {
            var cb = NewChoiceBox(choices, V(key), v => SetValue(key, v));
            ctl[key] = new Ctl { Kind = "choice", Input = cb };
            return cb;
        }

        UIElement NewNumberControl(Item item)
        {
            string key = item.Key;
            // an identifier or a huge range (a port): no slider
            var f = NewNumberField(item.Min, item.Max, item.Step, item.Unit, t => SetValue(key, t), !item.NoSlider);
            f.Show(V(key), item.Min);
            ctl[key] = new Ctl { Kind = item.Kind, Num = f, Text = f.Box };
            return f.Root;
        }

        UIElement NewSizeControl(Item item)
        {
            string key = item.Key;
            var f = NewSizeField(item.Axis, v => SetValue(key, v));
            f.Root.HorizontalAlignment = HorizontalAlignment.Right;
            f.Show(V(key));
            ctl[key] = new Ctl { Kind = "size", Size = f, Text = f.Box };
            return f.Root;
        }

        UIElement NewColorControl(string key)
        {
            // the swatch, then the field filling the column
            var sp = NewGrid("Auto", "*");
            var sw = NewButton("", "Swatch", "Pick a colour");
            sw.Background = NewColorBrush(V(key), true);
            var tb = new TextBox { Margin = T(Gap.Control, 0, 0, 0), Text = V(key) };
            SetCol(tb, 1);
            sp.Children.Add(sw); sp.Children.Add(tb);
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
                    MarkInvalid(tb, false);
                    SetValue(key, tb.Text.Trim());
                }
                else MarkInvalid(tb, true);
            };
            return sp;
        }

        // Hidden text (the SteamGridDB key): shown as dots, saved encrypted
        UIElement NewSecretControl(string key)
        {
            var pb = new PasswordBox { Password = Core.UnprotectSecret(V(key)) };
            pb.PasswordChanged += (s, e) => SetValue(key, Core.ProtectSecret(pb.Password));
            ctl[key] = new Ctl { Kind = "secret", Input = pb };
            return pb;
        }

        // text fields fill the control column
        UIElement NewTextControl(string key)
        {
            var tb = new TextBox { Text = V(key) };
            tb.TextChanged += (s, e) => SetValue(key, tb.Text.Trim());
            ctl[key] = new Ctl { Kind = "text", Input = tb };
            return tb;
        }

        UIElement NewFontControl(string key)
        {
            var cb = new ComboBox { IsEditable = true };
            foreach (var f in Fonts.SystemFontFamilies.Select(x => x.Source).Distinct().OrderBy(x => x, StringComparer.OrdinalIgnoreCase)) cb.Items.Add(f);
            cb.Text = V(key);
            cb.AddHandler(TextBoxBase.TextChangedEvent, new TextChangedEventHandler((s, e) => SetValue(key, cb.Text.Trim())));
            ctl[key] = new Ctl { Kind = "font", Input = cb };
            return cb;
        }

        UIElement NewCategoryControl(string key)
        {
            var cb = new ComboBox();
            var names = Core.GetCategoryFiles().Select(f => System.IO.Path.GetFileNameWithoutExtension(f.Name)).ToList();
            if (V(key) != "" && !names.Contains(V(key))) names.Add(V(key));
            foreach (var n in names) cb.Items.Add(n);
            cb.SelectedItem = V(key);
            cb.SelectionChanged += (s, e) => { if (cb.SelectedItem != null) SetValue(key, (string)cb.SelectedItem); };
            ctl[key] = new Ctl { Kind = "category", Input = cb };
            return cb;
        }

        // Where to look (ImportStores, "Steam|Epic|..."): a row per store with its
        // switch, as any other setting; the stores of an item (Item.Stores) in
        // their group, the folders' one in the header of Your folders. All the
        // switches write the one list, in the order of Schema.SOURCES.
        CheckBox NewStoreBox(string key, string store)
        {
            Ctl c;
            if (!ctl.TryGetValue(key, out c) || c.Boxes == null) ctl[key] = c = new Ctl { Kind = "stores", Boxes = new List<CheckBox>() };
            var boxes = c.Boxes;
            var current = V(key).Split('|').Select(x => x.Trim().Replace(".", "")).ToList();
            var cb = new CheckBox { Tag = new[] { key, store }, IsChecked = current.Contains(store), HorizontalAlignment = HorizontalAlignment.Right };
            cb.Click += (s, e) =>
            {
                var on = boxes.Where(x => x.IsChecked == true).Select(x => ((string[])x.Tag)[1]).ToList();
                SetValue(key, string.Join("|", Schema.SOURCES.Where(on.Contains)));
            };
            boxes.Add(cb);
            return cb;
        }

        List<UIElement> NewStoresRows(Item item)
        {
            var rows = new List<UIElement>();
            foreach (var store in item.Stores ?? Schema.SOURCES)
            {
                string help;
                if (!Schema.STORE_HELP.TryGetValue(store, out help)) help = "Games";
                rows.Add(NewRow(Schema.STORE_LABELS[store], help, NewStoreBox(item.Key, store), null));
            }
            return rows;
        }

        // Gamepad buttons (GamepadToggle, GamepadConfirm...): one field as the
        // keys of the Keyboard page, the glyphs of its buttons in it (A + LB),
        // all held together, up to PadMax. Clicked (mouse, keys) it opens the
        // dial of the buttons around it, where each one picked goes in or out
        // of the combination; pressed with the pad it waits for the buttons
        // held together, taken when they are released (PadDial.cs).
        const int PadMax = 4;

        UIElement NewPadControl(string key)
        {
            var sp = NewPanel(Orientation.Horizontal);
            sp.HorizontalAlignment = HorizontalAlignment.Right;
            var b = NewButton("", "KeyButton");
            var clear = NewClearButton("Clear the buttons");
            AddTo(sp, b); AddTo(sp, clear);
            ctl[key] = new Ctl { Kind = "pad", Button = b, Clear = clear };
            b.Click += (s, e) =>
            {
                if (padMode) StartPadCapture(key);
                else OpenPadDial(key);
            };
            clear.Click += (s, e) => SetPadCombo(key, new List<string>());
            ShowPadSlots(key);
            return sp;
        }

        // The buttons of a pad setting: "BACK START" -> BACK, START (as the
        // helper reads them; more than PadMax written by hand stay)
        static List<string> PadButtons(string value)
        {
            return Regex.Split((value ?? "").ToUpperInvariant(), @"[\s+|,]+").Where(x => x != "").Distinct().ToList();
        }

        // "A + Left bumper" (the names of the buttons), "None" without any
        static string PadNames(List<string> list)
        {
            string name;
            return list.Count == 0 ? "None" : string.Join(" + ", list.Select(x => Schema.PAD_LABELS.TryGetValue(x, out name) ? name : x));
        }

        // The value of a pad field: a setting, or the pad shortcut of the tile
        // being edited (TilePadKey: PadKey= of the tile, Categories.cs)
        const string TilePadKey = "@TilePadKey";

        string PadValue(string key)
        {
            if (key != TilePadKey) return V(key);
            var t = GetCurrentTile();
            return t != null ? Core.GetKey(t, "PadKey") : "";
        }

        void SetPadValue(string key, string value)
        {
            if (key != TilePadKey) { SetValue(key, value); return; }
            var t = GetCurrentTile();
            if (t == null || loading) return;
            Core.SetKey(t, "PadKey", value);
            SetChanged(currentFile);
        }

        void SetPadCombo(string key, List<string> buttons)
        {
            SetPadValue(key, string.Join(" ", buttons));
            ShowPadSlots(key);
        }

        // A button picked on the dial: in the combination, or out of it (no
        // more than PadMax)
        void TogglePadButton(string key, string button)
        {
            var list = PadButtons(PadValue(key));
            if (list.Contains(button)) list.Remove(button);
            else if (list.Count < PadMax) list.Add(button);
            else return;
            SetPadCombo(key, list);
        }

        void ShowPadSlots(string key)
        {
            Ctl c;
            if (!ctl.TryGetValue(key, out c) || c.Kind != "pad") return;
            var list = PadButtons(PadValue(key));
            c.Button.Content = NewPadCombo(list);
            AutomationProperties.SetName(c.Button, PadNames(list));
            SetActionVisible(c.Clear, list.Count > 0);
            UpdatePadConflicts();
        }

        // The same buttons on two actions: only the first one acts (Helper.ps1),
        // both are marked. After every change of a pad setting (ShowPadSlots, also
        // from UpdateControl: a reset, a profile)
        void UpdatePadConflicts()
        {
            var pads = ctl.Where(kv => kv.Value.Kind == "pad" && kv.Value.Button != null).ToList();
            Func<string, string> combo = k => string.Join(" ", PadButtons(PadValue(k)).OrderBy(x => x, StringComparer.Ordinal));
            foreach (var kv in pads)
            {
                string mine = combo(kv.Key);
                var others = mine == "" ? new List<string>() : pads.Where(o => o.Key != kv.Key && combo(o.Key) == mine)
                    .Select(o => { if (o.Key == TilePadKey) return "the pad shortcut of the tile being edited"; Page pg; var it = Schema.ItemOf(o.Key, out pg); return it != null ? it.Label : o.Key; }).ToList();
                var list = PadButtons(PadValue(kv.Key));
                var b = kv.Value.Button;
                if (b == padCaptureField) continue;
                string tip = list.Count > 0 ? PadNames(list) + ". " : "";
                if (others.Count > 0)
                {
                    b.BorderBrush = ResBrush("DangerBrush");
                    b.ToolTip = tip + "Also used by: " + string.Join(", ", others) + " (only the first one acts)";
                }
                else
                {
                    b.ClearValue(Control.BorderBrushProperty);
                    b.ToolTip = tip + "Click to pick the buttons, or press A on the pad and then hold the buttons together";
                }
            }
        }

        // Key binding: click, then press the key (with the modifiers for 'combo')
        FrameworkElement NewKeyControl(string key, bool combo = false)
        {
            var sp = NewPanel(Orientation.Horizontal);
            sp.HorizontalAlignment = HorizontalAlignment.Right;
            var b = NewButton(Schema.FormatHotKey(V(key)), "KeyButton", "Click, then press a key");
            var clear = NewClearButton("Clear the key");
            AddTo(sp, b); AddTo(sp, clear);
            ctl[key] = new Ctl { Kind = combo ? "combo" : "key", Button = b, Clear = clear };
            SetActionVisible(clear, V(key).Trim() != "");
            keyButtons[key] = b;

            b.Click += (s, e) =>
            {
                capturing = b;
                b.Content = "Press a key...";
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
                        if (held.Count > 0) b.Content = Schema.FormatHotKey(string.Join(" ", held)) + " + ...";
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
                SetActionVisible(clear, true);
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
            // the area and the monitor side by side, filling the column
            var area = NewChoiceBox(new[] { new[] { "SCREENAREA", "Whole screen" }, new[] { "WORKAREA", "Work area" } }, sa[0], null);
            var mon = NewChoiceBox(new[] { new[] { "", "Main monitor" }, new[] { "1", "Monitor 1" }, new[] { "2", "Monitor 2" }, new[] { "3", "Monitor 3" }, new[] { "4", "Monitor 4" } }, sa[1], null);
            var c = new Ctl { Kind = "screen", Area = area, Monitor = mon };
            ctl["ScreenX"] = c;
            SelectionChangedEventHandler changed = (s, e) =>
            {
                if (updating) return;
                var n = Core.ScreenAreaTo(ChoiceValue(area) ?? "SCREENAREA", ChoiceValue(mon) ?? "");
                foreach (var kv in n) values[kv.Key] = kv.Value;
                SetValue("ScreenX", n["ScreenX"]);
            };
            area.SelectionChanged += changed;
            mon.SelectionChanged += changed;
            ctl["ScreenY"] = c; ctl["ScreenW"] = c; ctl["ScreenH"] = c;
            return NewEqualButtons(area, mon);
        }

        UIElement NewActionControl(string action, string label)
        {
            var b = NewButton(label, action == "Import" ? "AccentButton" : "");
            b.HorizontalAlignment = HorizontalAlignment.Right;
            b.Click += (s, e) => InvokeAction(action);
            return b;
        }

        // --- Rows, cards, pages ---------------------------------------------------------

        Button NewResetButton(string[] keys)
        {
            var b = NewResetIcon("Restore default");
            SetActionVisible(b, false);
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
            // the control column has the same width on every page (UpdateControlColumn):
            // fields and sliders fill it, the other controls end at its right edge,
            // the action column follows
            var g = NewGrid("*", "Auto", Gap.ActionColumn.ToString(CultureInfo.InvariantCulture));
            g.ColumnDefinitions[1].SetResourceReference(ColumnDefinition.WidthProperty, FieldWidth.ControlKey);
            g.Margin = T(0, Gap.Row);
            var left = NewLabelBlock(label, help);
            left.VerticalAlignment = VerticalAlignment.Center;
            left.Margin = T(0, 0, Gap.Column, 0);
            g.Children.Add(left);
            if (control != null)
            {
                var fe = control as FrameworkElement;
                if (fe != null) fe.VerticalAlignment = VerticalAlignment.Center;
                SetCol(control, 1);
                g.Children.Add(control);
            }
            else Grid.SetColumnSpan(left, 3);   // text only: the whole row
            if (reset != null) { SetCol(reset, 2); g.Children.Add(reset); }
            return new CardRow(ResBrush("LineBrush")) { Child = g };
        }

        public Border NewCard(string title, string help)
        {
            var b = new Border { Style = ResStyle("Card") };
            var sp = new CardStack();
            b.Child = sp;
            if (!string.IsNullOrEmpty(title))
            {
                var h = NewSectionTitle(title);
                h.Margin = T(0, Gap.Group, 0, Gap.Line);
                AddTo(sp, h);
            }
            if (!string.IsNullOrEmpty(help))
            {
                var x = NewHelp(help);
                x.Margin = T(0, 0, 0, Gap.Control);
                AddTo(sp, x);
            }
            return b;
        }

        // A card whose header is a switch (Group.Switch): its label as the title,
        // the switch and its reset in the control and action columns, its help
        // (or the group's) below
        Border NewSwitchCard(Item sw, string help)
        {
            var b = new Border { Style = ResStyle("Card") };
            var sp = new CardStack();
            b.Child = sp;
            var g = NewGrid("*", "Auto", Gap.ActionColumn.ToString(CultureInfo.InvariantCulture));
            g.ColumnDefinitions[1].SetResourceReference(ColumnDefinition.WidthProperty, FieldWidth.ControlKey);
            g.Margin = T(0, Gap.Group, 0, Gap.Line);
            var h = NewSectionTitle(sw.Label);
            h.VerticalAlignment = VerticalAlignment.Center;
            g.Children.Add(h);
            var control = NewBoolControl(sw.Key);
            ((FrameworkElement)control).VerticalAlignment = VerticalAlignment.Center;
            SetCol(control, 1);
            g.Children.Add(control);
            var reset = NewResetButton(new[] { sw.Key });
            SetCol(reset, 2);
            g.Children.Add(reset);
            AddTo(sp, g);
            string text = !string.IsNullOrEmpty(help) ? help : sw.Help;
            if (!string.IsNullOrEmpty(text))
            {
                var x = NewHelp(text);
                x.Margin = T(0, 0, 0, Gap.Control);
                AddTo(sp, x);
            }
            return b;
        }

        // A card whose header is the switch of a source of ImportStores
        // (Group.Store): the group's title, the switch of that source
        Border NewStoreSwitchCard(Group group)
        {
            var b = new Border { Style = ResStyle("Card") };
            var sp = new CardStack();
            b.Child = sp;
            var g = NewGrid("*", "Auto", Gap.ActionColumn.ToString(CultureInfo.InvariantCulture));
            g.ColumnDefinitions[1].SetResourceReference(ColumnDefinition.WidthProperty, FieldWidth.ControlKey);
            g.Margin = T(0, Gap.Group, 0, Gap.Line);
            var h = NewSectionTitle(group.Title);
            h.VerticalAlignment = VerticalAlignment.Center;
            g.Children.Add(h);
            var control = NewStoreBox("ImportStores", group.Store);
            control.VerticalAlignment = VerticalAlignment.Center;
            SetCol(control, 1);
            g.Children.Add(control);
            AddTo(sp, g);
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
                            var row = NewGrid("64", "*");
                            row.Margin = T(0, 0, 0, Gap.Line);
                            var l = NewText(sk, Fs.Help, ResBrush("DimBrush"));
                            l.VerticalAlignment = VerticalAlignment.Center;
                            var field = NewTextControl(sk);
                            SetCol(field, 1);
                            row.Children.Add(l); row.Children.Add(field);
                            AddTo(sp, row);
                        }
                        return NewRow(item.Label, "Custom values: written as they are.", sp, NewResetButton(screenKeys));
                    }
                    return NewRow(item.Label, item.Help, NewScreenControl(), NewResetButton(screenKeys));
                case "keys":
                    var present = item.Pair.Where(values.ContainsKey).ToArray();
                    if (present.Length == 0) return null;
                    var kp = NewPanel(Orientation.Horizontal);
                    kp.HorizontalAlignment = HorizontalAlignment.Right;
                    foreach (var kk in present)
                    {
                        var kc = NewKeyControl(kk);
                        kc.Margin = T(Gap.Control, 0, 0, 0);
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
                case "text": control = k == "ImportFolders" ? NewFoldersControl(k) : NewTextControl(k); break;
                case "secret": control = NewSecretControl(k); break;
                case "font": control = NewFontControl(k); break;
                case "category": control = NewCategoryControl(k); break;
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
            // as wide as the window: the rows stretch and their help text wraps less
            sp.Margin = Gap.Page;
            sv.Content = sp;
            // the room of the scrollbar is kept also when there is none, so the cards
            // and their columns are in the same place on every page
            var panel = sp;
            sv.ScrollChanged += (s, e) =>
            {
                double right = Gap.Page.Right + (sv.ComputedVerticalScrollBarVisibility == Visibility.Visible ? 0 : Gap.ScrollBar);
                if (panel.Margin.Right != right) panel.Margin = new Thickness(Gap.Page.Left, Gap.Page.Top, right, Gap.Page.Bottom);
            };
            return sv;
        }

        UIElement NewSettingsPage(Page page)
        {
            StackPanel sp;
            var sv = NewPageScroller(out sp);
            var schemaKeys = new HashSet<string>(Schema.SchemaKeys(), StringComparer.OrdinalIgnoreCase);
            // the page's switch beside its title (ShowPage), the page applying with it
            string pageWhen = null;
            Item pageSw = null;
            if (page.Switch != null)
            {
                pageSw = page.Groups[0].Items.First(i => i.Key == page.Switch);
                pageWhen = page.Switch + "=1";
                var head = NewPanel(Orientation.Horizontal);
                var control = NewBoolControl(page.Switch);
                AutomationProperties.SetName(control, pageSw.Label);
                ((FrameworkElement)control).VerticalAlignment = VerticalAlignment.Center;
                AddTo(head, control);
                var reset = NewResetButton(new[] { page.Switch });
                reset.Margin = T(Gap.Icon, 0, 0, 0);
                AddTo(head, reset);
                pageSwitches[page.Id] = head;
            }
            foreach (var group in page.Groups)
            {
                // a group with a switch: the switch in the header, its label the title
                var sw = group.Switch == null ? null : group.Items.First(i => i.Key == group.Switch);
                var card = sw != null ? NewSwitchCard(sw, group.Help) : group.Store != null ? NewStoreSwitchCard(group) : NewCard(group.Title, group.Help);
                string own = group.When ?? (sw != null ? sw.Key + "=1" : group.Store != null ? "ImportStores=" + group.Store : null);
                string groupWhen = pageWhen == null ? own : own == null ? pageWhen : pageWhen + ";" + own;
                int rows = 0;
                if (group.Found)
                {
                    // tiles of games no longer installed, then the list of the games
                    // and apps found (cards of their own)
                    AddTo(sp, NewMissingCard());
                    AddTo(sp, NewFoundCard());
                    continue;
                }
                if (group.Dash) { AddTo(sp, NewDashCard()); continue; }
                if (group.Profiles) { AddTo(sp, NewProfilesCard(group)); continue; }
                if (group.Market)
                {
                    // widgets to download (its own card)
                    AddTo(sp, NewMarketCard());
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
                        if (item == sw || item == pageSw) { rows++; continue; }
                        if (item.Kind == "stores")
                        {
                            foreach (var r in NewStoresRows(item)) { CardPanel(card).Children.Add(r); rows++; }
                            continue;
                        }
                        // your folders: a grid as wide as the card (name, folder, kind, category)
                        if (item.Key == "ImportFolders")
                        {
                            var help = NewHelp(item.Help);
                            help.Margin = T(0, 0, 0, Gap.Control);
                            AddTo(CardPanel(card), help);
                            AddTo(CardPanel(card), NewFoldersControl(item.Key));
                            rows++;
                            continue;
                        }
                        var row = NewItemRow(item);
                        if (row != null) { CardPanel(card).Children.Add(row); rows++; }
                        var b = row as Border;
                        // the categories the carousel cannot centre (UpdateCarouselNote)
                        if (b != null && !string.IsNullOrEmpty(item.When))
                            whenRows.Add(new WhenRow { When = item.When, GroupWhen = groupWhen, Row = b, Why = AddRowReason(b, WhenReason(item.When, page)) });
                    }
                }
                // (with a switch, no reason: the switch is in the header)
                if (rows > 0 && groupWhen != null)
                    whenCards.Add(new WhenCard { Outer = pageWhen, Own = own, Card = card, Why = sw != null || group.When == null ? null : AddCardReason(card, WhenReason(group.When, page)), Keep = group.Store != null ? ((Grid)CardPanel(card).Children[0]) : null });
                if (rows > 0) AddTo(sp, card);
            }
            UpdateWhenRows();
            return sv;
        }
    }
}
