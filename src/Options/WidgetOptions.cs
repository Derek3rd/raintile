// Raintile Options: the settings of each installed widget (Widgets > <widget>
// in the menu). A widget declares them in its .ini, one [Option:<Name>]
// section each (Label=, Kind= text|secret|bool|number|choice, Help=,
// Default=, Choices=a|b|c); their values go to Widgets\<Id>\settings.inc, in
// the widget's folder ("<Name>=<value>"; secrets encrypted with DPAPI, like
// the SteamGridDB key). The launcher writes the values in place of
// #OPTION:<Name># (not the secrets); the widget's scripts read the file.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;

namespace RaintileOptions
{
    class WidgetOptionDef
    {
        public string Name, Label, Kind, Help, Default, When;
        public string[] Choices;
    }

    public partial class OptionsApp
    {
        static string WidgetFile(string id) { return Path.Combine(WidgetsDir, id, id + ".ini"); }
        static string WidgetSettingsFile(string id) { return Path.Combine(WidgetsDir, id, "settings.inc"); }

        // Widgets installed in the data folder (Widgets\<Id>\<Id>.ini)
        static List<string> InstalledWidgets()
        {
            var list = new List<string>();
            try
            {
                if (Directory.Exists(WidgetsDir))
                    foreach (var d in Directory.GetDirectories(WidgetsDir))
                    {
                        string id = Path.GetFileName(d);
                        if (SafeId(id) && File.Exists(WidgetFile(id))) list.Add(id);
                    }
            }
            catch { }
            return list.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList();
        }

        static List<IniSection> WidgetSections(string id)
        {
            try { return Core.ReadCategory(WidgetFile(id)).Sections; }
            catch { return new List<IniSection>(); }
        }

        static List<WidgetOptionDef> WidgetOptions(string id)
        {
            var list = new List<WidgetOptionDef>();
            foreach (var s in WidgetSections(id))
            {
                if (!s.Name.StartsWith("Option:", StringComparison.OrdinalIgnoreCase)) continue;
                string name = s.Name.Substring(7).Trim();
                if (!System.Text.RegularExpressions.Regex.IsMatch(name, @"^[A-Za-z0-9_]{1,40}$")) continue;
                string kind = Core.GetKey(s, "Kind").Trim().ToLowerInvariant();
                if (kind != "secret" && kind != "bool" && kind != "number" && kind != "choice") kind = "text";
                string label = Core.GetKey(s, "Label").Trim();
                list.Add(new WidgetOptionDef
                {
                    Name = name, Kind = kind, Label = label != "" ? label : name,
                    Help = Core.GetKey(s, "Help").Trim(), Default = Core.GetKey(s, "Default").Trim(), When = Core.GetKey(s, "When").Trim(),
                    Choices = Core.GetKey(s, "Choices").Split('|').Select(c => c.Trim()).Where(c => c != "").ToArray(),
                });
            }
            return list;
        }

        // Its name and what it is, from [Metadata] (Name=, Information=)
        static string WidgetInfo(string id, string key)
        {
            var meta = WidgetSections(id).FirstOrDefault(s => s.Name.Equals("Metadata", StringComparison.OrdinalIgnoreCase));
            return meta != null ? Core.GetKey(meta, key).Trim() : "";
        }

        static Dictionary<string, string> ReadWidgetSettings(string id)
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                string f = WidgetSettingsFile(id);
                if (File.Exists(f))
                    foreach (var line in File.ReadAllLines(f))
                    {
                        int eq = line.IndexOf('=');
                        if (eq > 0 && !line.TrimStart().StartsWith(";")) d[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
                    }
            }
            catch { }
            return d;
        }

        // The whole file again (a .tmp first): one line per value
        static void WriteWidgetSettings(string id, Dictionary<string, string> values)
        {
            var sb = new StringBuilder("; Settings of this widget, written by Raintile's Options window\r\n");
            foreach (var kv in values.OrderBy(kv => kv.Key, StringComparer.OrdinalIgnoreCase))
                sb.Append(kv.Key).Append('=').Append(System.Text.RegularExpressions.Regex.Replace(kv.Value ?? "", @"[\r\n]+", " ")).Append("\r\n");
            string f = WidgetSettingsFile(id);
            File.WriteAllText(f + ".tmp", sb.ToString(), Core.Utf8);
            if (File.Exists(f)) File.Delete(f);
            File.Move(f + ".tmp", f);
        }

        void ShowWidgetPage(string id)
        {
            pageHost.Children.Clear();
            pageHost.Children.Add(NewWidgetPage(id));
            string name = WidgetInfo(id, "Name");
            pageTitle.Text = name != "" ? name : id;
            pageSwitch.Content = null;
            // what the widget is, then where its settings go
            string info = WidgetInfo(id, "Information");
            pageDesc.Text = (info != "" ? info.TrimEnd('.') + ". " : "") + "Its settings are saved in its folder (settings.inc); what a single tile shows (e.g. which game) is its Widget setting, in the tile editor.";
        }

        // The settings of a widget, as the rows of the other pages: its name and
        // help on the left, the control and its reset on the right; a setting
        // with When= (Name=value) disabled while the other one is not so
        UIElement NewWidgetPage(string id)
        {
            StackPanel sp;
            var sv = NewPageScroller(out sp);
            var card = NewCard(null, null);
            var f = CardPanel(card);
            AddTo(sp, card);
            var defs = WidgetOptions(id);
            var values = ReadWidgetSettings(id);
            Func<WidgetOptionDef, string> value = d => { string v; return values.TryGetValue(d.Name, out v) ? v : d.Default; };
            var whens = new List<Action>();
            Action updateWhens = () => { foreach (var a in whens) a(); };
            Action<string, string> save = (name, v) =>
            {
                values[name] = v;
                try { WriteWidgetSettings(id, values); }
                catch (Exception ex) { ShowDialog("Raintile", "The settings could not be saved: " + ex.Message); return; }
                // the launcher writes the values into its widgets when it loads
                needsRefresh = true;
                UpdateDirty();
                updateWhens();
            };
            foreach (var d in defs)
            {
                var def = d;
                string v = value(def);
                FrameworkElement control;
                Action<string> show;   // the control showing a value again (reset)
                switch (def.Kind)
                {
                    case "secret":
                        var pb = new PasswordBox { Password = Core.UnprotectSecret(v) };
                        pb.LostFocus += (s, e) => save(def.Name, pb.Password == "" ? "" : Core.ProtectSecret(pb.Password));
                        control = pb;
                        show = x => pb.Password = Core.UnprotectSecret(x);
                        break;
                    case "bool":
                        var cb = new CheckBox { IsChecked = v == "1" || v.Equals("true", StringComparison.OrdinalIgnoreCase), HorizontalAlignment = HorizontalAlignment.Right };
                        cb.Click += (s, e) => save(def.Name, cb.IsChecked == true ? "1" : "0");
                        control = cb;
                        show = x => cb.IsChecked = x == "1" || x.Equals("true", StringComparison.OrdinalIgnoreCase);
                        break;
                    case "choice":
                        var box = NewChoiceBox(def.Choices.Select(c => new[] { c, c }), def.Choices.FirstOrDefault(c => c.Equals(v, StringComparison.OrdinalIgnoreCase)) ?? def.Choices.FirstOrDefault(), x => save(def.Name, x));
                        control = box;
                        show = x => SelectChoice(box, x);
                        break;
                    default:
                        var tb = new TextBox { Text = v };
                        if (def.Kind == "number") NumericOnly(tb, true, true);
                        tb.LostFocus += (s, e) =>
                        {
                            string t = tb.Text.Trim();
                            double n;
                            // what is still not a number (a lone "-") keeps the red border and is not saved
                            bool bad = def.Kind == "number" && t != "" && !Core.TryNumber(t, out n);
                            MarkInvalid(tb, bad);
                            if (!bad && t != value(def)) save(def.Name, t);
                        };
                        control = tb;
                        show = x => { tb.Text = x; MarkInvalid(tb, false); };
                        break;
                }
                // a secret has no default to go back to
                Button reset = null;
                if (def.Kind != "secret")
                {
                    reset = NewResetIcon("Restore default");
                    Action showReset = () => SetActionVisible(reset, value(def) != def.Default);
                    reset.Click += (s, e) => { show(def.Default); save(def.Name, def.Default); };
                    whens.Add(showReset);
                }
                var row = NewRow(def.Label, def.Help + (def.Kind == "secret" ? " Saved encrypted: only your Windows user on this PC can read it." : ""), control, reset);
                AddTo(f, row);
                var kv = def.When.Split(new[] { '=' }, 2);
                var other = kv.Length == 2 ? defs.FirstOrDefault(x => x.Name.Equals(kv[0].Trim(), StringComparison.OrdinalIgnoreCase)) : null;
                if (other != null)
                {
                    string want = kv[1].Trim();
                    var why = AddRowReason(row, "Only with " + other.Label + (other.Kind == "bool" ? " on." : ": " + want + "."));
                    whens.Add(() => SetRowApplies(row, value(other).Equals(want, StringComparison.OrdinalIgnoreCase), why));
                }
            }
            updateWhens();
            // its folder: a card of its own
            var files = NewCard("Files", null);
            var folder = NewButton("Open the folder");
            folder.HorizontalAlignment = HorizontalAlignment.Right;
            folder.Click += (s, e) => System.Diagnostics.Process.Start("explorer.exe", "\"" + Path.Combine(WidgetsDir, id) + "\"");
            AddTo(CardPanel(files), NewRow("Its folder", "Widgets\\" + id + ": its files and settings.inc. An update from the gallery keeps settings.inc.", folder, null));
            AddTo(sp, files);
            return sv;
        }
    }
}
