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
        public string Name, Label, Kind, Help, Default;
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
                    Help = Core.GetKey(s, "Help").Trim(), Default = Core.GetKey(s, "Default").Trim(),
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
            pageDesc.Text = "Widgets\\" + id + ": its settings, saved in its folder (settings.inc). The settings of a single tile (e.g. which game) are in the tile, as its Widget setting.";
        }

        UIElement NewWidgetPage(string id)
        {
            var sp = NewPanel();
            var card = NewCard("Settings", WidgetInfo(id, "Information"));
            var f = CardPanel(card);
            AddTo(sp, card);
            var defs = WidgetOptions(id);
            var values = ReadWidgetSettings(id);
            if (defs.Count == 0) AddTo(f, NewText("This widget has no settings.", Fs.Help, ResBrush("DimBrush"), false, true));
            Action<string, string> save = (name, value) =>
            {
                values[name] = value;
                try { WriteWidgetSettings(id, values); }
                catch (Exception ex) { ShowDialog("Raintile", "The settings could not be saved: " + ex.Message); return; }
                // the launcher writes the values into its widgets when it loads
                needsRefresh = true;
                UpdateDirty();
            };
            foreach (var d in defs)
            {
                var def = d;
                string v;
                if (!values.TryGetValue(def.Name, out v)) v = def.Default;
                FrameworkElement control;
                switch (def.Kind)
                {
                    case "secret":
                        var pb = new PasswordBox { Password = Core.UnprotectSecret(v) };
                        pb.LostFocus += (s, e) => save(def.Name, pb.Password == "" ? "" : Core.ProtectSecret(pb.Password));
                        control = pb;
                        break;
                    case "bool":
                        var cb = new CheckBox { IsChecked = v == "1" || v.Equals("true", StringComparison.OrdinalIgnoreCase), VerticalAlignment = VerticalAlignment.Center };
                        cb.Click += (s, e) => save(def.Name, cb.IsChecked == true ? "1" : "0");
                        control = cb;
                        break;
                    case "choice":
                        var box = new ComboBox();
                        foreach (var c in def.Choices) box.Items.Add(c);
                        box.SelectedItem = def.Choices.FirstOrDefault(c => c.Equals(v, StringComparison.OrdinalIgnoreCase)) ?? def.Choices.FirstOrDefault();
                        box.SelectionChanged += (s, e) => { if (box.SelectedItem != null) save(def.Name, (string)box.SelectedItem); };
                        control = box;
                        break;
                    default:
                        var tb = new TextBox { Text = v };
                        tb.LostFocus += (s, e) =>
                        {
                            string t = tb.Text.Trim();
                            double n;
                            if (def.Kind == "number" && t != "" && !double.TryParse(t, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out n))
                            {
                                ShowDialog("Raintile", def.Label + ": a number, please.");
                                return;
                            }
                            save(def.Name, t);
                        };
                        control = tb;
                        break;
                }
                AddTo(f, NewFormRow(def.Label, control, def.Help + (def.Kind == "secret" ? " Saved encrypted: only your Windows user on this PC can read it." : "")));
            }
            var folder = NewButton("Open its folder", "LinkButton");
            folder.HorizontalAlignment = HorizontalAlignment.Left;
            folder.Margin = T(0, Gap.Control, 0, Gap.Line);
            folder.Click += (s, e) => System.Diagnostics.Process.Start("explorer.exe", "\"" + Path.Combine(WidgetsDir, id) + "\"");
            AddTo(f, folder);
            return sp;
        }
    }
}
