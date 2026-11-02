// Raintile Options: the Import page. Games and apps found by Scan.ps1
// (Generated\Found.json): the picked ones become normal tiles, with their
// images (local, SteamGridDB for games, the program icon for apps). Tiles of
// games no longer installed (Generated\Missing.txt): remove or keep them.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace RaintileOptions
{
    class FoundItem
    {
        public string Id, Kind, Store, Name, Command, Hero, Logo, Icon, SteamAppId;
        public bool New;
    }

    class MissingTile
    {
        public string Id, File, Name;
        public IniSection Section;
    }

    public partial class OptionsApp
    {
        List<FoundItem> foundItems = new List<FoundItem>();
        string foundScanned = "";
        readonly HashSet<string> foundSelected = new HashSet<string>();
        string foundKind = "all", foundFilter = "";
        bool foundShowAdded, foundCovers = true, foundBuilding;
        Process scanProcess;
        DispatcherTimer scanTimer;
        Button foundScanButton, foundAddButton;
        TextBlock foundStatus, foundEmpty;
        ListBox foundList;
        ComboBox foundTarget;

        void InitFound()
        {
            // Search in the background (a separate PowerShell): the window stays usable
            scanTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
            scanTimer.Tick += (s, e) =>
            {
                if (scanProcess == null || !scanProcess.HasExited) return;
                scanTimer.Stop();
                foundScanButton.IsEnabled = true;
                ReadFound();
                RefreshFoundList();
                UpdateFoundStatus();
                SetFoundSeen();
                RefreshMissingList();
                InvokeRainmeter("!CommandMeasure MeasureScript \"OnMissing()\" \"" + Core.Config + "\"");
                UpdateNavDots(true);
            };
        }

        static List<FoundItem> ReadFoundItems(string text)
        {
            var list = new List<FoundItem>();
            Dictionary<string, object> j;
            try { j = Json.Parse(text) as Dictionary<string, object>; } catch { return list; }
            object items;
            if (j == null || !j.TryGetValue("Items", out items) || !(items is object[])) return list;
            foreach (var o in (object[])items)
            {
                var d = o as Dictionary<string, object>;
                if (d == null) continue;
                list.Add(new FoundItem
                {
                    Id = Json.Str(d, "Id"), Kind = Json.Str(d, "Kind"), Store = Json.Str(d, "Store"), Name = Json.Str(d, "Name"),
                    Command = Json.Str(d, "Command"), Hero = Json.Str(d, "Hero"), Logo = Json.Str(d, "Logo"), Icon = Json.Str(d, "Icon"),
                    SteamAppId = Json.Str(d, "SteamAppId"), New = Json.Bool(d, "New"),
                });
            }
            return list;
        }

        void ReadFound()
        {
            foundItems = new List<FoundItem>();
            foundScanned = "";
            if (!File.Exists(Core.FoundFile)) return;
            try
            {
                string text = File.ReadAllText(Core.FoundFile);
                foundItems = ReadFoundItems(text);
                var j = Json.Parse(text) as Dictionary<string, object>;
                foundScanned = Json.Str(j, "Scanned");
            }
            catch { }
        }

        // Tiles of every category (as in the window, unsaved changes too):
        // name key / command -> category name
        class PresentMap
        {
            public Dictionary<string, string> Names = new Dictionary<string, string>();
            public Dictionary<string, string> Commands = new Dictionary<string, string>();
        }

        PresentMap GetPresentMap()
        {
            var map = new PresentMap();
            foreach (var e in GetCategoryEntries())
            {
                var m = GetModel(e.File);
                foreach (var s in Core.GetTiles(m))
                {
                    map.Names[Core.GetNameKey(s.Name)] = e.Name;
                    string cmd = Core.GetKey(s, "Command");
                    if (cmd != "") map.Commands[cmd.ToLowerInvariant()] = e.Name;
                }
                foreach (var n in Core.GetImportedNames(m)) map.Names[Core.GetNameKey(n)] = e.Name;
            }
            return map;
        }

        static string GetPresentIn(FoundItem it, PresentMap map)
        {
            string c;
            if (map.Commands.TryGetValue((it.Command ?? "").ToLowerInvariant(), out c)) return c;
            return map.Names.TryGetValue(Core.GetNameKey(it.Name), out c) ? c : null;
        }

        // Everything in the list has been seen: no dot on the gear until something
        // else turns up
        void SetFoundSeen()
        {
            var ids = new HashSet<string>();
            if (File.Exists(Core.SeenFile)) foreach (var l in File.ReadAllLines(Core.SeenFile)) if (l != "") ids.Add(l);
            int before = ids.Count;
            foreach (var it in foundItems) ids.Add(it.Id);
            if (ids.Count == before) return;
            Directory.CreateDirectory(Path.GetDirectoryName(Core.SeenFile));
            File.WriteAllLines(Core.SeenFile, ids.ToArray(), Core.Utf8);
            InvokeRainmeter("!CommandMeasure MeasureScript \"OnFoundSeen()\" \"" + Core.Config + "\"");
            UpdateNavDots(true);
        }

        // The old automatic import block becomes normal tiles (once)
        int ConvertOldImports()
        {
            int n = 0;
            foreach (var f in Core.GetCategoryFiles())
            {
                var m = GetModel(f.Name);
                if (string.IsNullOrEmpty(m.Imported)) continue;
                foreach (var name in Core.GetImportedNames(m).ToList()) if (ConvertImportedTile(f.Name, name) != null) n++;
                m.Imported = "";   // the marker and its comments go too
                Core.WriteCategory(Path.Combine(Core.CategoriesDir, f.Name), m);
                changedFiles.Remove(f.Name);
                needsRefresh = true;
            }
            UpdateDirty();
            return n;
        }

        void UpdateFoundCount()
        {
            int n = foundSelected.Count;
            foundAddButton.Content = n > 0 ? "Add " + n + " selected" : "Add selected";
            foundAddButton.IsEnabled = n > 0;
        }

        void UpdateFoundStatus(string extra = "")
        {
            int games = foundItems.Count(i => i.Kind == "game"), apps = foundItems.Count(i => i.Kind == "app");
            string when = "";
            DateTime d;
            if (DateTime.TryParse(foundScanned, out d)) when = ", searched " + d.ToString("g");
            foundStatus.Text = foundScanned != "" ? games + " games and " + apps + " apps found" + when + "." : "Not searched yet.";
            if (extra != "") foundStatus.Text = extra + " " + foundStatus.Text;
        }

        ListBoxItem NewFoundEntry(FoundItem it, string inCategory)
        {
            var li = new ListBoxItem { Tag = it, Padding = T(8, 6) };
            var g = NewGrid("Auto", "Auto", "*", "Auto");
            var tick = new CheckBox { Style = ResStyle("Tick"), IsHitTestVisible = false, VerticalAlignment = VerticalAlignment.Center, Margin = T(2, 0, 12, 0) };
            var binding = new Binding("IsSelected") { RelativeSource = new RelativeSource(RelativeSourceMode.FindAncestor, typeof(ListBoxItem), 1) };
            tick.SetBinding(ToggleButton.IsCheckedProperty, binding);
            g.Children.Add(tick);
            if (foundCovers)
            {
                var b = new Border { Width = 96, Height = 45, CornerRadius = new CornerRadius(4), ClipToBounds = true, Background = ResBrush("FieldBg"), Margin = T(0, 0, 12, 0) };
                var img = new Image();
                if (it.Hero != "" && File.Exists(it.Hero))
                {
                    img.Stretch = Stretch.UniformToFill;
                    img.Source = GetBitmap(it.Hero, 192);
                }
                else
                {
                    img.Stretch = Stretch.Uniform;
                    img.Margin = T(8, 5, 8, 5);
                    img.Source = GetBitmap(it.Logo != "" ? it.Logo : it.Icon, 96);
                }
                b.Child = img;
                SetCol(b, 1);
                g.Children.Add(b);
            }
            var texts = NewPanel();
            texts.VerticalAlignment = VerticalAlignment.Center;
            var title = NewPanel(Orientation.Horizontal);
            var t = NewText(it.Name, 13.5);
            t.TextTrimming = TextTrimming.CharacterEllipsis;
            AddTo(title, t);
            if (it.New)
            {
                var badge = new Border
                {
                    Background = ResBrush("AccentSoftBrush"), CornerRadius = new CornerRadius(3), Padding = T(5, 0, 5, 1), Margin = T(8, 0, 0, 0),
                    VerticalAlignment = VerticalAlignment.Center, Child = NewText("NEW", 10, ResBrush("AccentBrush"), true),
                };
                AddTo(title, badge);
            }
            AddTo(texts, title);
            string store;
            if (!Schema.STORE_LABELS.TryGetValue(it.Store ?? "", out store)) store = it.Store;
            AddTo(texts, NewText(store + "   \u00B7   " + (it.Kind == "game" ? "game" : "app"), 11.5, ResBrush("DimBrush")));
            SetCol(texts, 2);
            g.Children.Add(texts);
            if (inCategory != null)
            {
                var note = NewText("in " + inCategory, 12, ResBrush("DimBrush"));
                note.VerticalAlignment = VerticalAlignment.Center;
                note.Margin = T(12, 0, 4, 0);
                SetCol(note, 3);
                g.Children.Add(note);
                li.IsEnabled = false;
                li.Opacity = 0.55;
            }
            li.Content = g;
            return li;
        }

        void RefreshFoundList()
        {
            if (foundList == null) return;
            foundBuilding = true;
            try
            {
                foundList.Items.Clear();
                var present = GetPresentMap();
                var words = Regex.Split(foundFilter.ToLowerInvariant(), @"\s+").Where(w => w != "").ToList();
                foreach (var it in foundItems)
                {
                    if (foundKind != "all" && it.Kind != foundKind) continue;
                    string inCat = GetPresentIn(it, present);
                    if (inCat != null) foundSelected.Remove(it.Id);
                    if (inCat != null && !foundShowAdded) continue;
                    string hay = (it.Name + " " + it.Store).ToLowerInvariant();
                    if (words.Any(w => !hay.Contains(w))) continue;
                    var item = NewFoundEntry(it, inCat);
                    foundList.Items.Add(item);
                    if (inCat == null && foundSelected.Contains(it.Id)) item.IsSelected = true;
                }
                foundEmpty.Visibility = foundList.Items.Count > 0 ? Visibility.Collapsed : Visibility.Visible;
                foundEmpty.Text = scanProcess != null && !scanProcess.HasExited ? "Searching\u2026"
                    : foundItems.Count == 0 ? "Nothing found yet: press Search again."
                    : "Nothing to show: everything is already in the launcher, or hidden by the filters.";
            }
            finally { foundBuilding = false; }
            UpdateFoundCount();
        }

        void StartFoundScan()
        {
            if (scanProcess != null && !scanProcess.HasExited) return;
            foundScanButton.IsEnabled = false;
            foundStatus.Text = "Searching the stores and the Start menu\u2026";
            try
            {
                scanProcess = StartScript("Scan.ps1", "-Resources " + Arg(Core.Resources) + " -Data " + Arg(Core.Data) + " -Stores \"" + V("ImportStores") + "\"");
            }
            catch (Exception e)
            {
                foundScanButton.IsEnabled = true;
                foundStatus.Text = "The search could not start: " + e.Message;
                return;
            }
            RefreshFoundList();
            scanTimer.Start();
        }

        // Category file for an added item; created if it does not exist yet
        string GetCategoryFileFor(string b)
        {
            if (models.ContainsKey(b + ".ini") || File.Exists(Path.Combine(Core.CategoriesDir, b + ".ini"))) return b + ".ini";
            string file = NewCategoryFile(b, b);
            BuildNav(navCurrent);
            return file;
        }

        // --- SteamGridDB --------------------------------------------------------------------

        static object SgdbGet(string key, string path)
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            using (var wc = new WebClient())
            {
                wc.Headers.Add("Authorization", "Bearer " + key);
                wc.Headers.Add("User-Agent", "Raintile");
                wc.Encoding = System.Text.Encoding.UTF8;
                var r = Json.Parse(wc.DownloadString("https://www.steamgriddb.com/api/v2/" + path)) as Dictionary<string, object>;
                return r != null && Json.Bool(r, "success") && r.ContainsKey("data") ? r["data"] : null;
            }
        }

        static Dictionary<string, object> First(object data)
        {
            var arr = data as object[];
            if (arr != null) return arr.Length > 0 ? arr[0] as Dictionary<string, object> : null;
            return data as Dictionary<string, object>;
        }

        // Downloads a hero ('heroes') or logo ('logos') to <destBase>.<ext>; returns
        // the file, or null
        static string GetSGDBImage(string key, string kind, string name, string steamAppId, string destBase)
        {
            if (string.IsNullOrEmpty(key)) return null;
            Dictionary<string, object> game = !string.IsNullOrEmpty(steamAppId)
                ? First(SgdbGet(key, "games/steam/" + steamAppId))
                : First(SgdbGet(key, "search/autocomplete/" + Uri.EscapeDataString(name)));
            string id = Json.Str(game, "id");
            if (id == "") return null;
            var img = First(SgdbGet(key, kind + "/game/" + id));
            string url = Json.Str(img, "url");
            if (!url.StartsWith("https://")) return null;
            string ext = Path.GetExtension(new Uri(url).AbsolutePath).ToLowerInvariant();
            if (!Core.IMAGE_EXTS.Contains(ext)) ext = ".png";
            Directory.CreateDirectory(Path.GetDirectoryName(destBase));
            using (var wc = new WebClient())
            {
                wc.Headers.Add("User-Agent", "Raintile");
                wc.DownloadFile(url, destBase + ext);
            }
            return destBase + ext;
        }

        void AddSelectedFound()
        {
            var sel = foundItems.Where(i => foundSelected.Contains(i.Id)).ToList();
            if (sel.Count == 0) return;
            string target = (string)((ComboBoxItem)foundTarget.SelectedItem).Tag;
            string key = Core.UnprotectSecret(V("SteamGridDBKey"));
            var present = GetPresentMap();
            var touched = new HashSet<string>();
            int added = 0;
            win.Cursor = Cursors.Wait;
            try
            {
                for (int i = 0; i < sel.Count; i++)
                {
                    var it = sel[i];
                    foundStatus.Text = "Adding " + (i + 1) + " of " + sel.Count + ": " + it.Name + "\u2026";
                    win.Dispatcher.Invoke(new Action(() => { }), DispatcherPriority.Background);
                    foundSelected.Remove(it.Id);
                    if (GetPresentIn(it, present) != null) continue;
                    string b = target != "auto" ? Path.GetFileNameWithoutExtension(target) : it.Kind == "game" ? V("ImportCategory") : V("AppsCategory");
                    if (b == "") b = it.Kind == "game" ? "Games" : "Apps";
                    string file = GetCategoryFileFor(b);
                    var m = GetModel(file);
                    string name = Core.GetTileName(it.Name);
                    if (name == "") continue;
                    if (TestTileName(m, name)) name = name + " (" + it.Store + ")";
                    if (TestTileName(m, name)) continue;
                    var s = new IniSection { Name = name };
                    Core.SetKey(s, "Command", it.Command);
                    Core.SetKey(s, "Source", it.Id);
                    // images in the default folders, named after the tile
                    try
                    {
                        if (it.Hero != "" && File.Exists(it.Hero)) Core.CopyTileImage(b, "background", name, it.Hero);
                        else if (it.Kind == "game" && key != "")
                        {
                            try { GetSGDBImage(key, "heroes", name, it.SteamAppId, Path.Combine(Core.ImagesRoot, b, "background", name)); } catch { }
                        }
                        if (it.Logo != "" && File.Exists(it.Logo)) Core.CopyTileImage(b, "logo", name, it.Logo);
                        else if (it.Kind == "game" && key != "")
                        {
                            try { GetSGDBImage(key, "logos", name, it.SteamAppId, Path.Combine(Core.ImagesRoot, b, "logo", name)); } catch { }
                        }
                        if (Core.FindImage(Path.Combine(Core.ImagesRoot, b, "logo"), name) == null && it.Icon != "" && File.Exists(it.Icon))
                            Core.CopyTileImage(b, "logo", name, it.Icon);
                    }
                    catch { }
                    m.Sections.Add(s);
                    present.Names[Core.GetNameKey(name)] = b;
                    present.Commands[(it.Command ?? "").ToLowerInvariant()] = b;
                    touched.Add(file);
                    added++;
                }
            }
            finally { win.Cursor = null; }
            foreach (var f in touched)
            {
                Core.WriteCategory(Path.Combine(Core.CategoriesDir, f), GetModel(f));
                changedFiles.Remove(f);
            }
            if (added > 0) needsRefresh = true;
            UpdateDirty();
            RefreshFoundList();
            UpdateFoundStatus(added > 0 ? "Added " + added + ": save and refresh to see them in the launcher." : "Nothing added: already in the launcher.");
        }

        Border NewFoundCard()
        {
            var card = NewCard("Found on this PC", "");
            var f = CardPanel(card);

            int converted = ConvertOldImports();
            if (converted > 0)
            {
                var note = NewText(converted + " games of the old automatic import are now normal tiles: you can edit and move them.", 12.5, ResBrush("AccentBrush"), false, true);
                note.Margin = T(0, 0, 0, 8);
                AddTo(f, note);
            }

            // search again + status
            var head = NewGrid("Auto", "*");
            head.Margin = T(0, 2, 0, 10);
            foundScanButton = NewButton("Search again");
            head.Children.Add(foundScanButton);
            foundStatus = NewText("", 12, ResBrush("DimBrush"), false, true);
            foundStatus.VerticalAlignment = VerticalAlignment.Center;
            foundStatus.Margin = T(12, 0, 0, 0);
            SetCol(foundStatus, 1);
            head.Children.Add(foundStatus);
            AddTo(f, head);

            // filters: type, text, already added, covers
            var filters = new WrapPanel { Margin = T(0, 0, 0, 10) };
            foreach (var k in new[] { new[] { "all", "All" }, new[] { "game", "Games" }, new[] { "app", "Apps" } })
            {
                var rb = new RadioButton { Style = ResStyle("Segment"), Content = k[1], GroupName = "found_kind", IsChecked = foundKind == k[0] };
                string kind = k[0];
                rb.Click += (s, e) => { foundKind = kind; RefreshFoundList(); };
                filters.Children.Add(rb);
            }
            var search = new TextBox { Width = 200, Margin = T(10, 2, 16, 2), ToolTip = "Filter by name or store" };
            search.TextChanged += (s, e) => { foundFilter = search.Text; RefreshFoundList(); };
            filters.Children.Add(search);
            var showAdded = new CheckBox { Content = "Show added", Margin = T(0, 4, 16, 4), IsChecked = foundShowAdded };
            showAdded.Click += (s, e) => { foundShowAdded = showAdded.IsChecked == true; RefreshFoundList(); };
            filters.Children.Add(showAdded);
            var covers = new CheckBox { Content = "Covers", Margin = T(0, 4, 16, 4), IsChecked = foundCovers };
            covers.Click += (s, e) => { foundCovers = covers.IsChecked == true; RefreshFoundList(); };
            filters.Children.Add(covers);
            AddTo(f, filters);

            // the list
            var frame = new Border { BorderBrush = ResBrush("LineBrush"), BorderThickness = T(1), CornerRadius = new CornerRadius(8), Padding = T(4), Height = 440 };
            var grid = new Grid();
            frame.Child = grid;
            foundList = new ListBox { SelectionMode = SelectionMode.Multiple };
            grid.Children.Add(foundList);
            foundEmpty = NewText("", 13, ResBrush("DimBrush"), false, true);
            foundEmpty.HorizontalAlignment = HorizontalAlignment.Center;
            foundEmpty.VerticalAlignment = VerticalAlignment.Center;
            foundEmpty.IsHitTestVisible = false;
            grid.Children.Add(foundEmpty);
            AddTo(f, frame);
            foundList.SelectionChanged += (s, e) =>
            {
                if (foundBuilding) return;
                foreach (ListBoxItem i in e.AddedItems) foundSelected.Add(((FoundItem)i.Tag).Id);
                foreach (ListBoxItem i in e.RemovedItems) foundSelected.Remove(((FoundItem)i.Tag).Id);
                UpdateFoundCount();
            };

            // select all / none, where, add
            var bottom = NewGrid("Auto", "Auto", "*", "Auto", "Auto");
            bottom.Margin = T(0, 10, 0, 6);
            var all = NewButton("Select all", "LinkButton");
            var none = NewButton("Select none", "LinkButton");
            SetCol(none, 1);
            bottom.Children.Add(all); bottom.Children.Add(none);
            all.Click += (s, e) => { foreach (ListBoxItem i in foundList.Items) if (i.IsEnabled) i.IsSelected = true; };
            none.Click += (s, e) => { foundList.UnselectAll(); foundSelected.Clear(); UpdateFoundCount(); };
            foundTarget = new ComboBox { Width = 290, Margin = T(0, 0, 10, 0) };
            foundTarget.Items.Add(new ComboBoxItem { Content = "By type: games to " + V("ImportCategory") + ", apps to " + V("AppsCategory"), Tag = "auto" });
            foreach (var e in GetCategoryEntries()) foundTarget.Items.Add(new ComboBoxItem { Content = "All to " + e.Name, Tag = e.File });
            foundTarget.SelectedIndex = 0;
            SetCol(foundTarget, 3);
            bottom.Children.Add(foundTarget);
            foundAddButton = NewButton("Add selected", "AccentButton");
            foundAddButton.Click += (s, e) => AddSelectedFound();
            SetCol(foundAddButton, 4);
            bottom.Children.Add(foundAddButton);
            AddTo(f, bottom);

            foundScanButton.Click += (s, e) => StartFoundScan();
            ReadFound();
            UpdateFoundStatus();
            RefreshFoundList();
            if (foundItems.Count > 0) SetFoundSeen(); else StartFoundScan();
            return card;
        }

        // --- Tiles of games no longer installed -------------------------------------------
        // Remove takes the tile out of its category (its images stay), Keep adds it
        // to KeepMissing.txt (data folder): it is not reported again.

        Border missingCard;
        StackPanel missingList;
        TextBlock missingCount;

        // Tiles still in their category (as in the window) and not kept
        List<MissingTile> GetMissingList()
        {
            var list = new List<MissingTile>();
            if (!File.Exists(Core.MissingFile)) return list;
            var keep = Core.ReadKeepMissing();
            var files = Core.GetCategoryFiles().ToDictionary(f => f.Name.ToLowerInvariant(), f => f.Name);
            foreach (var line in File.ReadAllLines(Core.MissingFile, Core.Utf8))
            {
                var parts = line.Split(new[] { '|' }, 2);
                if (parts.Length != 2 || keep.Contains(line)) continue;
                string file;
                if (!files.TryGetValue(parts[0].ToLowerInvariant(), out file)) continue;
                var section = Core.GetTiles(GetModel(file)).FirstOrDefault(s => s.Name == parts[1]);
                if (section != null) list.Add(new MissingTile { Id = line, File = file, Name = parts[1], Section = section });
            }
            return list;
        }

        // A tile to review (for the menu dot; only the categories named in
        // Missing.txt are read)
        bool TestMissingAny()
        {
            try
            {
                if (!File.Exists(Core.MissingFile) || new FileInfo(Core.MissingFile).Length == 0) return false;
                return GetMissingList().Count > 0;
            }
            catch { return false; }
        }

        // Missing.txt without the given tiles; the launcher reads it again
        void RemoveMissingLines(IEnumerable<string> ids)
        {
            if (!File.Exists(Core.MissingFile)) return;
            var drop = new HashSet<string>(ids, StringComparer.OrdinalIgnoreCase);
            var left = File.ReadAllLines(Core.MissingFile, Core.Utf8).Where(l => l != "" && !drop.Contains(l)).ToArray();
            File.WriteAllLines(Core.MissingFile, left, Core.Utf8);
            InvokeRainmeter("!CommandMeasure MeasureScript \"OnMissing()\" \"" + Core.Config + "\"");
            UpdateNavDots(true);
        }

        void RemoveMissingTiles(List<MissingTile> tiles)
        {
            var touched = new HashSet<string>();
            foreach (var t in tiles) { GetModel(t.File).Sections.Remove(t.Section); touched.Add(t.File); }
            foreach (var f in touched)
            {
                Core.WriteCategory(Path.Combine(Core.CategoriesDir, f), GetModel(f));
                changedFiles.Remove(f);
            }
            if (touched.Count > 0) needsRefresh = true;
            RemoveMissingLines(tiles.Select(t => t.Id));
            UpdateDirty();
            RefreshMissingList();
            if (pages.ContainsKey("category") && currentFile != null && touched.Contains(currentFile)) ShowCategory();
        }

        void KeepMissingTiles(List<MissingTile> tiles)
        {
            var keep = Core.ReadKeepMissing();
            var lines = File.Exists(Core.KeepMissingFile) ? File.ReadAllLines(Core.KeepMissingFile, Core.Utf8).Where(l => l != "").ToList() : new List<string>();
            foreach (var t in tiles) if (!keep.Contains(t.Id)) lines.Add(t.Id);
            Directory.CreateDirectory(Path.GetDirectoryName(Core.KeepMissingFile));
            File.WriteAllLines(Core.KeepMissingFile, lines.ToArray(), Core.Utf8);
            RemoveMissingLines(tiles.Select(t => t.Id));
            RefreshMissingList();
        }

        void RefreshMissingList()
        {
            if (missingCard == null) return;
            var tiles = GetMissingList();
            missingCard.Visibility = tiles.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
            missingList.Children.Clear();
            var names = GetCategoryEntries().ToDictionary(e => e.File, e => e.Name);
            foreach (var t in tiles)
            {
                var row = NewGrid("*", "Auto", "Auto");
                row.Margin = T(0, 3);
                var texts = NewPanel();
                texts.VerticalAlignment = VerticalAlignment.Center;
                var name = NewText(t.Name, 13.5);
                name.TextTrimming = TextTrimming.CharacterEllipsis;
                AddTo(texts, name);
                string catName;
                names.TryGetValue(t.File, out catName);
                var sub = NewText("in " + catName + "   \u00B7   " + Core.GetKey(t.Section, "Command"), 11.5, ResBrush("DimBrush"));
                sub.TextTrimming = TextTrimming.CharacterEllipsis;
                AddTo(texts, sub);
                row.Children.Add(texts);
                var tile = t;
                var remove = NewButton("Remove", "", "Takes the tile out of its category. Its images stay in the Images folder.");
                remove.Margin = T(10, 0, 0, 0);
                remove.Click += (s, e) => RemoveMissingTiles(new List<MissingTile> { tile });
                SetCol(remove, 1);
                row.Children.Add(remove);
                var keepBtn = NewButton("Keep", "", "Keeps the tile as it is and stops reporting it.");
                keepBtn.Margin = T(6, 0, 0, 0);
                keepBtn.Click += (s, e) => KeepMissingTiles(new List<MissingTile> { tile });
                SetCol(keepBtn, 2);
                row.Children.Add(keepBtn);
                missingList.Children.Add(row);
            }
            missingCount.Text = tiles.Count + " tile" + (tiles.Count != 1 ? "s" : "") + " of games that are no longer installed, or whose program file is gone. In the launcher they are greyed out and do not start.";
        }

        Border NewMissingCard()
        {
            missingCard = NewCard("No longer installed", "");
            var f = CardPanel(missingCard);
            missingCount = NewText("", 12, ResBrush("DimBrush"), false, true);
            missingCount.Margin = T(0, 0, 0, 8);
            AddTo(f, missingCount);
            missingList = NewPanel();
            AddTo(f, missingList);
            var bottom = NewPanel(Orientation.Horizontal);
            bottom.Margin = T(0, 10, 0, 6);
            var all = NewButton("Remove all");
            all.Click += (s, e) => RemoveMissingTiles(GetMissingList());
            AddTo(bottom, all);
            var keepAll = NewButton("Keep all");
            keepAll.Margin = T(8, 0, 0, 0);
            keepAll.Click += (s, e) => KeepMissingTiles(GetMissingList());
            AddTo(bottom, keepAll);
            AddTo(f, bottom);
            RefreshMissingList();
            return missingCard;
        }
    }
}
