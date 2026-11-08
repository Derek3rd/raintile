// Raintile Options: profiles, saved sets of the settings (General > Profiles).
// A profile is Profiles\<name>.ini in the data folder: the settings of
// Settings.inc but those of Schema.PROFILE_EXCLUDED, the look of each category
// (Schema.CATEGORY_LOOK of its [Category]) and the settings of the widgets
// installed (not their secrets). Picking one puts its values in the window, as
// if they had been set by hand: Save and refresh applies them. Saving, saving
// as new and deleting a profile write its file at once. Profiles\Current.txt
// names the profile the launcher uses ("*": the default settings), written
// with the settings.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace RaintileOptions
{
    // What a profile holds: settings (key -> value), the look of categories
    // (file name without .ini -> key -> value) and the settings of widgets (id ->
    // option -> value). An empty value is kept: none of its own (the category
    // follows the launcher's setting).
    public class ProfileData
    {
        public Dictionary<string, string> Settings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, Dictionary<string, string>> Categories = new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, Dictionary<string, string>> Widgets = new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);
    }

    public partial class OptionsApp
    {
        const string DefaultProfileLabel = "Default settings";
        const string DefaultProfileMark = "*";   // the default settings, in the combo and in Current.txt

        Border profilesCard;
        ComboBox profileBox;
        Button profileLoad, profileSave, profileDelete;
        TextBlock profileNote;
        // the entry shown in the combo, and the one Current.txt names: null none,
        // "" the default settings, otherwise the name of a profile
        string profileShown, profileSaved;
        ProfileData profileData;   // the values of the entry shown
        bool profilesRead, profileBusy, profileQueued, profilePicking;
        // the look of the category files not loaded, read once per card
        readonly Dictionary<string, Dictionary<string, string>> diskLooks = new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);

        static string ProfilesDir { get { return Path.Combine(Core.Data, "Profiles"); } }

        // until the data folder is prepared there is nowhere to keep profiles
        static bool ProfilesReady { get { return Core.Data != Core.Resources; } }

        // the profile shown is not the one Current.txt names: Save and refresh writes it
        bool ProfileUnsaved { get { return profileShown != profileSaved; } }

        // --- Files (public: tests/ps/Options.Tests.ps1) ------------------------------

        // A name a profile can have, "" when none: cleaned as a tile's name (no \ /
        // : * ? " < > |), at most 40 characters, not a name Windows keeps for its
        // devices (CON, NUL, COM1...)
        public static string CleanProfileName(string name)
        {
            string n = Core.GetTileName(name);
            if (n.Length > 40) n = n.Substring(0, 40).Trim().Trim('.', ' ');
            if (Regex.IsMatch(n, @"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$", RegexOptions.IgnoreCase)) return "";
            return n;
        }

        // The file of a profile in 'dir', null when the name cannot be one
        public static string GetProfilePath(string dir, string name)
        {
            string n = CleanProfileName(name);
            if (n == "") return null;
            string path = Path.Combine(dir, n + ".ini");
            return Core.TestInFolder(path, dir) ? path : null;
        }

        // The profiles in 'dir', by name
        public static List<string> GetProfileNames(string dir)
        {
            var list = new List<string>();
            if (!Directory.Exists(dir)) return list;
            foreach (var f in Directory.GetFiles(dir, "*.ini"))
            {
                // (*.ini also finds *.inix: the short names of Windows)
                if (!string.Equals(Path.GetExtension(f), ".ini", StringComparison.OrdinalIgnoreCase)) continue;
                string n = Path.GetFileNameWithoutExtension(f);
                if (CleanProfileName(n) == n) list.Add(n);
            }
            return list.OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToList();
        }

        // A profile file, null when it cannot be read. It comes from the data
        // folder, maybe edited by hand: only what a profile holds is kept
        // ([Settings], [Category <file>], [Widget <id>], keys of letters, digits
        // and _), the rest is passed over. Names in it never become paths: they
        // are looked up among the categories and widgets there are.
        public static ProfileData ReadProfile(string path)
        {
            string[] lines;
            try { lines = File.ReadAllLines(path, Core.Utf8); }
            catch { return null; }
            var p = new ProfileData();
            Dictionary<string, string> current = null;
            foreach (var line in lines)
            {
                string t = line.Trim();
                if (t == "" || t.StartsWith(";")) continue;
                var m = Regex.Match(t, @"^\[(.+)\]$");
                if (m.Success)
                {
                    string name = m.Groups[1].Value.Trim();
                    current = null;
                    if (name.Equals("Settings", StringComparison.OrdinalIgnoreCase)) current = p.Settings;
                    else if ((m = Regex.Match(name, @"^Category\s+([^\[\]]{1,128})$", RegexOptions.IgnoreCase)).Success)
                        current = ProfileSection(p.Categories, m.Groups[1].Value.Trim());
                    else if ((m = Regex.Match(name, @"^Widget\s+(.+)$", RegexOptions.IgnoreCase)).Success && SafeId(m.Groups[1].Value.Trim()))
                        current = ProfileSection(p.Widgets, m.Groups[1].Value.Trim());
                    continue;
                }
                if (current == null) continue;
                m = Regex.Match(t, @"^([A-Za-z0-9_]{1,64})\s*=(.*)$");
                if (m.Success) current[m.Groups[1].Value] = m.Groups[2].Value.Trim();
            }
            return p;
        }

        static Dictionary<string, string> ProfileSection(Dictionary<string, Dictionary<string, string>> sections, string name)
        {
            Dictionary<string, string> d;
            if (!sections.TryGetValue(name, out d)) sections[name] = d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            return d;
        }

        // A profile file, written whole (a .tmp first), one line per value
        public static void WriteProfile(string path, ProfileData p)
        {
            var sb = new StringBuilder("; Raintile profile (Options > General > Profiles). An empty value: none of its own.\r\n");
            Action<string, Dictionary<string, string>> section = (name, d) =>
            {
                sb.Append("\r\n[").Append(name).Append("]\r\n");
                foreach (var kv in d.OrderBy(kv => kv.Key, StringComparer.OrdinalIgnoreCase))
                    sb.Append(kv.Key).Append('=').Append(Regex.Replace(kv.Value ?? "", @"[\r\n]+", " ")).Append("\r\n");
            };
            section("Settings", p.Settings);
            foreach (var c in p.Categories.OrderBy(kv => kv.Key, StringComparer.OrdinalIgnoreCase)) section("Category " + c.Key, c.Value);
            foreach (var w in p.Widgets.OrderBy(kv => kv.Key, StringComparer.OrdinalIgnoreCase)) section("Widget " + w.Key, w.Value);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            Core.WriteAllTextAtomic(path, sb.ToString());
        }

        // The profile the launcher uses, as Current.txt names it: null for none
        // (or one that is not there any more), "" for the default settings, else
        // the name as the file has it
        public static string ReadCurrentProfile(string dir)
        {
            string t;
            try { t = File.ReadAllText(Path.Combine(dir, "Current.txt"), Core.Utf8).Trim(); }
            catch { return null; }
            if (t == DefaultProfileMark) return "";
            return GetProfileNames(dir).FirstOrDefault(n => n.Equals(t, StringComparison.OrdinalIgnoreCase));
        }

        // null: no profile (the file goes); "": the default settings
        public static void WriteCurrentProfile(string dir, string name)
        {
            string f = Path.Combine(dir, "Current.txt");
            if (name == null) { if (File.Exists(f)) File.Delete(f); return; }
            Directory.CreateDirectory(dir);
            Core.WriteAllTextAtomic(f, (name == "" ? DefaultProfileMark : name) + "\r\n");
        }

        // A setting a profile holds: in Settings.inc, not excluded, not a secret
        public static bool TestProfileKey(string key)
        {
            if (string.IsNullOrEmpty(key) || !Schema.Defaults.ContainsKey(key)) return false;
            if (Schema.PROFILE_EXCLUDED.Contains(key, StringComparer.OrdinalIgnoreCase)) return false;
            Page page;
            var item = Schema.ItemOf(key, out page);
            return item == null || item.Kind != "secret";
        }

        // The settings of a profile put into 'values' (the window's): only the
        // ones 'values' has and a profile holds; the keys changed
        public static List<string> MergeProfileSettings(Dictionary<string, string> values, Dictionary<string, string> profile)
        {
            var changed = new List<string>();
            foreach (var kv in profile)
            {
                string have;
                if (!TestProfileKey(kv.Key) || !values.TryGetValue(kv.Key, out have)) continue;
                string want = kv.Value ?? "";
                if (have == want) continue;
                values[kv.Key] = want;
                changed.Add(kv.Key);
            }
            return changed;
        }

        // The look of a category in a profile put into its [Category] section: the
        // keys of Schema.CATEGORY_LOOK the profile has ("" takes the key away: the
        // category follows the launcher's setting); the keys changed
        public static List<string> MergeCategoryLook(IniSection category, Dictionary<string, string> look)
        {
            var changed = new List<string>();
            foreach (var key in Schema.CATEGORY_LOOK)
            {
                string want;
                if (!look.TryGetValue(key, out want)) continue;
                want = (want ?? "").Trim();
                if (Core.GetKey(category, key).Trim() == want) continue;
                Core.SetKey(category, key, want);
                changed.Add(key);
            }
            return changed;
        }

        // The settings of a widget in a profile put into its values (its
        // settings.inc): only the options 'defaults' has (name -> its Default; the
        // secrets are not there), a value equal to its default taken away so the
        // option follows the widget's; the options changed
        public static List<string> MergeWidgetValues(Dictionary<string, string> values, Dictionary<string, string> defaults, Dictionary<string, string> profile)
        {
            var changed = new List<string>();
            foreach (var d in defaults)
            {
                string want, have;
                if (!profile.TryGetValue(d.Key, out want)) continue;
                want = want ?? "";
                if (!values.TryGetValue(d.Key, out have)) have = d.Value;
                if (have == want) continue;
                if (want == d.Value) values.Remove(d.Key);
                else values[d.Key] = want;
                changed.Add(d.Key);
            }
            return changed;
        }

        // --- What the window has ------------------------------------------------------

        // The options of a widget a profile holds: name -> its default
        static Dictionary<string, string> WidgetDefaults(string id)
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var o in WidgetOptions(id)) if (o.Kind != "secret") d[o.Name] = o.Default;
            return d;
        }

        // The categories a profile can name: file name without .ini -> file name
        static Dictionary<string, string> ProfileCategoryFiles()
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var f in Core.GetCategoryFiles())
            {
                string n = Path.GetFileNameWithoutExtension(f.Name);
                if (Regex.IsMatch(n, @"^[^\[\]]{1,128}$")) d[n] = f.Name;
            }
            return d;
        }

        // The look keys of the [Category] section of a category file (all of
        // them, "" where it has none), without reading its tiles
        static Dictionary<string, string> ReadCategoryLook(string path)
        {
            var look = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var k in Schema.CATEGORY_LOOK) look[k] = "";
            string text;
            try { text = File.Exists(path) ? File.ReadAllText(path) : ""; }
            catch { text = ""; }
            var m = Regex.Match(text, @"(?ims)^[ \t]*\[Category\][ \t]*\r?$(.*?)(?=^[ \t]*\[|\z)");
            if (!m.Success) return look;
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (Match kv in Regex.Matches(m.Groups[1].Value, @"(?m)^[ \t]*([A-Za-z0-9_]+)[ \t]*=(.*?)\r?$"))
            {
                // the first one counts, as Core.GetKey reads it
                string k = kv.Groups[1].Value;
                if (look.ContainsKey(k) && seen.Add(k)) look[k] = kv.Groups[2].Value.Trim();
            }
            return look;
        }

        // The look of a category as the window has it: from its model when it is
        // loaded (it may have changes not saved yet), otherwise from its file
        Dictionary<string, string> GetCategoryLook(string file)
        {
            CategoryModel model;
            if (models.TryGetValue(file, out model))
            {
                // (not Core.GetCategorySection: it would add a [Category] to the model)
                var c = model.Sections.FirstOrDefault(s => string.Equals(s.Name, "Category", StringComparison.OrdinalIgnoreCase));
                var look = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (var k in Schema.CATEGORY_LOOK) look[k] = Core.GetKey(c, k).Trim();
                return look;
            }
            Dictionary<string, string> read;
            if (!diskLooks.TryGetValue(file, out read)) diskLooks[file] = read = ReadCategoryLook(Path.Combine(Core.CategoriesDir, file));
            return new Dictionary<string, string>(read, StringComparer.OrdinalIgnoreCase);
        }

        // The window's settings as a profile: what Save writes
        ProfileData TakeProfile()
        {
            var p = new ProfileData();
            foreach (var kv in values) if (TestProfileKey(kv.Key)) p.Settings[kv.Key] = kv.Value ?? "";
            foreach (var kv in ProfileCategoryFiles()) p.Categories[kv.Key] = GetCategoryLook(kv.Value);
            foreach (var id in InstalledWidgets())
            {
                var have = GetWidgetValues(id);
                var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (var o in WidgetDefaults(id)) { string v; d[o.Key] = have.TryGetValue(o.Key, out v) ? v : o.Value; }
                if (d.Count > 0) p.Widgets[id] = d;
            }
            return p;
        }

        // The default settings as a profile: the settings of the skin's
        // Settings.inc, for each category the look of the skin's copy of it (the
        // example Dashboard keeps its grid; a category of yours has none of its
        // own) and the widgets' defaults
        ProfileData GetDefaultProfile()
        {
            var p = new ProfileData();
            foreach (var item in Core.ReadSettings(Path.Combine(Core.Resources, "Settings.inc")))
                if (TestProfileKey(item.Key)) p.Settings[item.Key] = item.Value;
            foreach (var kv in ProfileCategoryFiles())
                p.Categories[kv.Key] = ReadCategoryLook(Path.Combine(Core.Resources, "Categories", kv.Value));
            foreach (var id in InstalledWidgets()) p.Widgets[id] = WidgetDefaults(id);
            return p;
        }

        // The values of an entry of the combo: null when it cannot be read
        ProfileData ReadProfileEntry(string name)
        {
            if (name == null) return null;
            if (name == "") return GetDefaultProfile();
            string path = GetProfilePath(ProfilesDir, name);
            return path != null ? ReadProfile(path) : null;
        }

        static string ProfileLabel(string name) { return name == "" ? "the default settings" : name; }

        // A control that cannot show a value (a value of its own in a combo, a
        // formula in a size, an area not of the list): its page is built again
        bool ControlShows(string key)
        {
            Ctl c;
            if (!ctl.TryGetValue(key, out c)) return true;
            string v = V(key);
            switch (c.Kind)
            {
                case "choice": return string.Equals(ChoiceValue((ComboBox)c.Input) ?? "", v, StringComparison.OrdinalIgnoreCase);
                case "size": return Regex.IsMatch(v, @"^\s*-?[\d.]+\s*%?\s*$");
                case "screen": return Core.ScreenAreaFrom(values) != null;
            }
            return true;
        }

        // Puts a profile's values in the window (apply), or only counts what that
        // would change: its settings, the look of the categories still there, the
        // settings of the widgets still installed. What it does not name stays.
        int ApplyProfile(ProfileData p, bool apply)
        {
            var target = apply ? values : new Dictionary<string, string>(values, StringComparer.OrdinalIgnoreCase);
            var keys = MergeProfileSettings(target, p.Settings);
            int n = keys.Count;
            var files = ProfileCategoryFiles();
            foreach (var c in p.Categories)
            {
                string file;
                if (!files.TryGetValue(c.Key, out file)) continue;
                // counted on a copy, so a category is loaded only to change it
                var copy = new IniSection { Name = "Category" };
                foreach (var kv in GetCategoryLook(file)) if (kv.Value != "") copy.Keys.Add(kv);
                int changed = MergeCategoryLook(copy, c.Value).Count;
                if (changed == 0) continue;
                n += changed;
                if (!apply) continue;
                MergeCategoryLook(Core.GetCategorySection(GetModel(file)), c.Value);
                SetChanged(file);
            }
            var installed = InstalledWidgets();
            foreach (var w in p.Widgets)
            {
                string id = installed.FirstOrDefault(x => x.Equals(w.Key, StringComparison.OrdinalIgnoreCase));
                if (id == null) continue;
                var widget = GetWidgetValues(id);
                int changed = MergeWidgetValues(widget, WidgetDefaults(id), w.Value).Count;
                if (changed == 0) continue;
                n += changed;
                if (apply) SetWidgetValues(id, widget);
            }
            if (!apply) return n;
            // the pages built show the new values; a page whose controls cannot is
            // built again (the others read the values when they are first shown)
            foreach (var k in keys) UpdateControl(k);
            var rebuild = new HashSet<string>();
            foreach (var k in keys)
            {
                if (ControlShows(k)) continue;
                Page page;
                Schema.ItemOf(Regex.IsMatch(k, "^Screen[XYWH]$", RegexOptions.IgnoreCase) ? "ScreenX" : k, out page);
                if (page != null) rebuild.Add(page.Id);
            }
            foreach (var id in rebuild) pages.Remove(id);
            UpdateResets();
            UpdateKeyConflicts();
            UpdateWhenRows();
            UpdateDirty();
            if (wheelCanvas != null) DrawWheel();
            if (rebuild.Contains("general") && navCurrent == "page:general")
                win.Dispatcher.BeginInvoke(new Action(() => ShowPage(Schema.ById("general"))));
            return n;
        }

        // --- The card ---------------------------------------------------------------------

        Border NewProfilesCard(Group group)
        {
            // (the card is built again with its page: the profile shown stays)
            if (!profilesRead && ProfilesReady)
            {
                profilesRead = true;
                profileSaved = profileShown = ReadCurrentProfile(ProfilesDir);
                profileData = ReadProfileEntry(profileShown);
            }
            diskLooks.Clear();
            var card = NewCard(group.Title, "A profile holds the settings of these pages (not where Import looks, the updates and the diagnostics), the look of each category (its grid, colours and places, not its tiles) and the settings of the widgets. Your tiles, categories and images are not part of it.");
            var f = CardPanel(card);
            profileBox = new ComboBox();
            AddTo(f, NewRow("Profile", "Picking one puts its settings in the window, on every page: Save and refresh applies them. Default settings: the ones Raintile comes with.", profileBox, null));
            profileLoad = NewButton("Load");
            profileSave = NewButton("Save");
            profileDelete = NewButton("Delete");
            var row = NewRow("Settings in the window", "Load puts the profile's settings back in the window. Save writes the window's settings into the profile, and Delete moves it to the Recycle Bin, at once.", NewEqualButtons(profileLoad, profileSave, profileDelete), null);
            profileNote = AddRowNote(row, "");
            profileNote.Visibility = Visibility.Collapsed;
            AddTo(f, row);
            var saveAs = NewButton("Save as new...");
            saveAs.HorizontalAlignment = HorizontalAlignment.Right;
            AddTo(f, NewRow("New profile", "The settings in the window as a new profile, written at once to Profiles in your data folder.", saveAs, null));
            profilesCard = card;
            if (!ProfilesReady)
            {
                var why = AddCardReason(card, "Your data folder is not ready yet: refresh the skin once, then come back.");
                SetCardApplies(card, false, why);
                return card;
            }
            FillProfileBox();
            // picked: once the list closes (the gamepad and the arrows of the open
            // list change the selection at every step), or by the arrows on the closed combo
            profileBox.SelectionChanged += (s, e) => { if (!profileBusy && !profileBox.IsDropDownOpen) QueueProfilePick(); };
            profileBox.DropDownClosed += (s, e) => { if (!profileBusy) QueueProfilePick(); };
            profileLoad.Click += (s, e) => InvokeProfileLoad();
            profileSave.Click += (s, e) => InvokeProfileSave();
            profileDelete.Click += (s, e) => InvokeProfileDelete();
            saveAs.Click += (s, e) => InvokeProfileSaveAs();
            card.IsVisibleChanged += (s, e) => QueueProfileState();
            QueueProfileState();
            return card;
        }

        // The combo again: the default settings, then the profiles; the one shown selected
        void FillProfileBox()
        {
            if (profileBox == null) return;
            var choices = new List<string[]> { new[] { DefaultProfileMark, DefaultProfileLabel } };
            choices.AddRange(GetProfileNames(ProfilesDir).Select(n => new[] { n, n }));
            profileBusy = true;
            try { SetChoices(profileBox, choices, profileShown == null ? null : profileShown == "" ? DefaultProfileMark : profileShown); }
            finally { profileBusy = false; }
        }

        void QueueProfileState()
        {
            if (profilesCard == null || profileQueued) return;
            profileQueued = true;
            win.Dispatcher.BeginInvoke(new Action(() => { profileQueued = false; UpdateProfileState(); }), DispatcherPriority.Background);
        }

        // The buttons and the note follow the entry shown and the window (only
        // while the card is seen: it compares every setting)
        void UpdateProfileState()
        {
            if (profilesCard == null || !profilesCard.IsVisible || !ProfilesReady) return;
            bool mine = !string.IsNullOrEmpty(profileShown);
            int n = profileData != null ? ApplyProfile(profileData, false) : 0;
            profileLoad.IsEnabled = n > 0;
            profileSave.IsEnabled = mine;
            profileDelete.IsEnabled = mine;
            profileNote.Text = profileShown == null ? "" : "The settings in the window differ from " + ProfileLabel(profileShown) + ".";
            profileNote.Visibility = n > 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        void QueueProfilePick()
        {
            win.Dispatcher.BeginInvoke(new Action(PickProfile));
        }

        // An entry picked in the combo: its values in the window. When the window
        // has settings that are in no profile (changed since the one shown, or no
        // profile shown), it asks first.
        void PickProfile()
        {
            string v = ChoiceValue(profileBox);
            string name = v == null ? null : v == DefaultProfileMark ? "" : v;
            // (one pick at a time: its question lets the window handle other events)
            if (name == null || name == profileShown || profilePicking) return;
            profilePicking = true;
            try { LoadPickedProfile(name); }
            finally { profilePicking = false; }
        }

        void LoadPickedProfile(string name)
        {
            var p = ReadProfileEntry(name);
            if (p == null)
            {
                ShowDialog("Load profile", "The profile " + name + " could not be read.");
                FillProfileBox();
                return;
            }
            bool keep = profileShown == null ? ApplyProfile(p, false) > 0 : profileData != null && ApplyProfile(profileData, false) > 0;
            if (keep)
            {
                string now = profileShown == null ? "are not saved in a profile" : "differ from " + ProfileLabel(profileShown);
                var r = ShowDialog("Load profile", "The settings in the window " + now + ". Load " + ProfileLabel(name) + " instead?\r\n\r\n" +
                    "Nothing is written until Save and refresh: Close without saving keeps the settings you have.", new[] { "Load", "Cancel" });
                if (r.Button != "Load") { FillProfileBox(); return; }
            }
            profileShown = name;
            profileData = p;
            ApplyProfile(p, true);
        }

        // Load: the entry's values in the window again (read again: its file may
        // have changed)
        void InvokeProfileLoad()
        {
            var p = ReadProfileEntry(profileShown);
            if (p == null) { ShowDialog("Load profile", "The profile " + profileShown + " could not be read."); return; }
            profileData = p;
            ApplyProfile(p, true);
        }

        // Save: the window's settings into the profile shown, at once
        void InvokeProfileSave()
        {
            if (string.IsNullOrEmpty(profileShown)) return;
            string path = GetProfilePath(ProfilesDir, profileShown);
            var p = TakeProfile();
            try { WriteProfile(path, p); }
            catch (Exception e) { ShowDialog("Save profile", "The profile could not be saved: " + e.Message); return; }
            profileData = p;
            NoteProfileInUse();
            status.Text = "Profile " + profileShown + " saved.";
        }

        // Save as new: the window's settings as a new profile, shown in the combo
        void InvokeProfileSaveAs()
        {
            var r = ShowDialog("Save as new profile", "Name of the new profile (e.g. Desk, Couch):", new[] { "Save", "Cancel" }, "");
            if (r.Button != "Save" || string.IsNullOrWhiteSpace(r.Text)) return;
            string name = CleanProfileName(r.Text);
            string path = GetProfilePath(ProfilesDir, name);
            if (path == null) { ShowDialog("Save as new profile", "This name cannot be a file name: use letters and digits."); return; }
            if (name.Equals(DefaultProfileLabel, StringComparison.OrdinalIgnoreCase) || GetProfileNames(ProfilesDir).Any(x => x.Equals(name, StringComparison.OrdinalIgnoreCase)))
            {
                ShowDialog("Save as new profile", "The profile '" + name + "' already exists: pick it, then Save to update it.");
                return;
            }
            var p = TakeProfile();
            try { WriteProfile(path, p); }
            catch (Exception e) { ShowDialog("Save as new profile", "The profile could not be saved: " + e.Message); return; }
            profileShown = name;
            profileData = p;
            FillProfileBox();
            NoteProfileInUse();
            status.Text = "Profile " + name + " saved.";
        }

        // Delete: the profile shown to the Recycle Bin (asked); the window keeps its settings
        void InvokeProfileDelete()
        {
            if (string.IsNullOrEmpty(profileShown)) return;
            string name = profileShown, path = GetProfilePath(ProfilesDir, name);
            var r = ShowDialog("Delete profile", "Move the profile " + name + " to the Recycle Bin? The settings in the window stay as they are.", new[] { "Delete", "Cancel" }, null, true);
            if (r.Button != "Delete") return;
            try { if (path != null && File.Exists(path)) RemoveToRecycleBin(path); }
            catch (Exception e) { ShowDialog("Delete profile", "The profile could not be deleted: " + e.Message); return; }
            if (profileSaved == name)
            {
                // a Current.txt left naming it reads as no profile (ReadCurrentProfile)
                try { WriteCurrentProfile(ProfilesDir, null); }
                catch (Exception e) { ShowDialog("Delete profile", "Current.txt could not be updated: " + e.Message); }
                profileSaved = null;
            }
            profileShown = null;
            profileData = null;
            FillProfileBox();
            UpdateDirty();
        }

        // The profile shown is the one in use: noted in Current.txt at once when
        // the launcher already has the window's settings, otherwise by Save and
        // refresh (until then the window has unsaved changes)
        void NoteProfileInUse()
        {
            if (!SettingsUnsaved()) SaveCurrentProfile();
            UpdateDirty();
        }

        // Save and refresh (SaveAll): Current.txt names the profile shown
        void SaveCurrentProfile()
        {
            if (!ProfileUnsaved || !ProfilesReady) return;
            try
            {
                WriteCurrentProfile(ProfilesDir, profileShown);
                profileSaved = profileShown;
            }
            catch (Exception e) { ShowDialog("Save", "The profile in use could not be written to Current.txt: " + e.Message); }
        }
    }
}
