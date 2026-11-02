// Raintile Options: the menu on the left, the pages, the Info page with the
// updates, and the start of the window.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace RaintileOptions
{
    // What a menu entry leads to. Ids: page:<id>, group:<id>, categories, cat:<file>
    class NavTag
    {
        public string Type, Group, First, File, Id;
        public Page Page;
        public TextBlock Title;
        public Image Icon;
        public Ellipse Dot;
    }

    public partial class OptionsApp
    {
        ListBox nav, navBottom;
        Grid pageHost;
        TextBlock pageTitle, pageDesc, status;
        Button btnSave;
        string version = "", information = "";
        readonly Dictionary<string, UIElement> pages = new Dictionary<string, UIElement>();
        readonly Dictionary<string, bool> navOpen = new Dictionary<string, bool> { { "keybindings", true }, { "categories", true } };
        bool navBuilding;
        string navCurrent, navPending;
        bool[] navDots;   // new found / missing, update
        string[] editTile;

        public int Run()
        {
            AddStartStepLead();
            app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            app.Resources = (ResourceDictionary)XamlReader.Parse(File.ReadAllText(System.IO.Path.Combine(Core.ScriptsDir, "Options.xaml")));
            AddStartStep("styles (Options.xaml)");
            // An error in an event handler: shown and logged, the window stays open
            app.DispatcherUnhandledException += (s, e) =>
            {
                e.Handled = true;
                WriteErrorLog(e.Exception.ToString());
                MessageBox.Show("Something went wrong:\r\n\r\n" + e.Exception.Message + "\r\n\r\nDetails in Generated\\Options.log", "Raintile");
            };

            try
            {
                string ini = File.ReadAllText(System.IO.Path.Combine(System.IO.Path.GetDirectoryName(Core.Resources), "Raintile.ini"));
                var m = Regex.Match(ini, @"(?m)^\s*Version\s*=\s*(.+?)\s*$");
                if (m.Success) version = "v" + m.Groups[1].Value;
                m = Regex.Match(ini, @"(?m)^\s*Information\s*=\s*(.+?)\s*$");
                if (m.Success) information = m.Groups[1].Value;
            }
            catch { }

            win = (Window)XamlReader.Parse(WindowXaml.Text);
            ((TextBlock)win.FindName("Version")).Text = version;
            AddStartStep("window");
            nav = (ListBox)win.FindName("Nav");
            navBottom = (ListBox)win.FindName("NavBottom");
            pageHost = (Grid)win.FindName("PageHost");
            pageTitle = (TextBlock)win.FindName("PageTitle");
            pageDesc = (TextBlock)win.FindName("PageDesc");
            status = (TextBlock)win.FindName("Status");
            btnSave = (Button)win.FindName("BtnSave");

            ReadValues();
            AddStartStep("settings read");
            logoColors = Core.ReadLogoColors();
            InitProgress();
            InitFound();

            // Info, at the bottom of the menu: a list of its own, only one of the
            // two lists has a selection
            navBottom.Items.Add(NewNavItem("page:info", "Info", Schema.ById("info").Icon, 0, new NavTag { Type = "page", Page = Schema.ById("info") }));
            navBottom.SelectionChanged += (s, e) =>
            {
                if (navBuilding || navBottom.SelectedItem == null) return;
                navBuilding = true;
                nav.SelectedItem = null;
                navBuilding = false;
                ShowNavTarget((NavTag)((ListBoxItem)navBottom.SelectedItem).Tag);
            };
            nav.SelectionChanged += (s, e) =>
            {
                if (navBuilding) return;
                var sel = nav.SelectedItem as ListBoxItem;
                if (sel == null) return;
                navBuilding = true;
                navBottom.SelectedItem = null;
                navBuilding = false;
                var tag = (NavTag)sel.Tag;
                if (tag.Type == "group")
                {
                    // reached with the keyboard: open the group on its first entry
                    navOpen[tag.Group] = true;
                    OpenNav(tag.First);
                    return;
                }
                ShowNavTarget(tag);
            };

            btnSave.Click += (s, e) => StartSaveAndRefresh();
            ((Button)win.FindName("BtnClose")).Click += (s, e) => win.Close();
            win.PreviewKeyDown += (s, e) =>
            {
                if (refreshing) { e.Handled = true; return; }   // waiting for the skin
                if (e.Key == Key.S && Keyboard.Modifiers == ModifierKeys.Control && capturing == null)
                {
                    e.Handled = true;
                    StartSaveAndRefresh();
                }
            };
            win.Closing += (s, e) =>
            {
                if (!dirtySettings || skipSavePrompt) return;
                var r = ShowDialog("Raintile", "Save the changes before closing?", new[] { "Save", "Don't save", "Cancel" });
                if (r.Button == "Save") SaveAll();
                else if (r.Button != "Don't save") e.Cancel = true;
            };
            win.SourceInitialized += (s, e) => SetDarkTitle(win);
            // Started without a console: bring the window to the foreground explicitly
            win.ContentRendered += (s, e) =>
            {
                win.Topmost = true;
                win.Activate();
                win.Topmost = false;
                Win32.SetForegroundWindow(new System.Windows.Interop.WindowInteropHelper(win).Handle);
                if (!firstShown)
                {
                    firstShown = true;
                    AddStartStep("window shown");
                    // the first page, once the window is on screen
                    win.Dispatcher.BeginInvoke(new Action(() =>
                    {
                        try { ShowFirstPage(); }
                        finally
                        {
                            startClock.Stop();
                            try { File.WriteAllLines(System.IO.Path.Combine(Core.Generated, "Options-startup.log"), startSteps, Core.Utf8); } catch { }
                        }
                    }), DispatcherPriority.Background);
                }
            };

            AddStartStep("  rest of the setup");
            updating = false;
            editTile = openPage == "tile" ? ReadEditTile() : null;
            // The menu is built before the window appears, the page right after
            if (openPage == "info") BuildNav("");
            else if (editTile != null) { navOpen["categories"] = true; BuildNav("cat:" + editTile[0]); }
            else BuildNav(openPage == "import" ? "page:import" : "page:general");
            AddStartStep("menu");
            UpdateDirty();
            win.ShowDialog();
            app.Shutdown();
            return 0;
        }

        void AddStartStepLead()
        {
            int lead;
            try { lead = (int)(DateTime.Now - Process.GetCurrentProcess().StartTime).TotalMilliseconds; } catch { lead = -1; }
            startSteps.Add(string.Format("{0,6} ms  program started (before the first step)", lead));
            AddStartStep("program loaded");
        }

        void ShowFirstPage()
        {
            if (openPage == "info")
            {
                // Info is in the list at the bottom: selecting it shows it
                navBottom.SelectedIndex = 0;
            }
            else if (editTile != null)
            {
                var sel = nav.SelectedItem as ListBoxItem;
                if (sel != null) ShowNavTarget((NavTag)sel.Tag);
                SelectTileByName(editTile[1]);
            }
            else
            {
                var sel = nav.SelectedItem as ListBoxItem;
                if (sel != null) ShowNavTarget((NavTag)sel.Tag);
            }
            UpdateDirty();
            AddStartStep("first page");
            UpdateNavDots(true);
            AddStartStep("menu dots (new games, update)");
        }

        // Tile to open on (-Page tile): "file|name" left by the skin, used once
        string[] ReadEditTile()
        {
            string path = System.IO.Path.Combine(Core.Generated, "EditTile.txt");
            if (!File.Exists(path)) return null;
            string[] parts;
            try
            {
                parts = File.ReadAllText(path).Split(new[] { '|' }, 2);
                File.Delete(path);
            }
            catch { return null; }
            if (parts.Length != 2) return null;
            string file = parts[0].Trim();
            var match = Core.GetCategoryFiles().FirstOrDefault(f => string.Equals(f.Name, file, StringComparison.OrdinalIgnoreCase));
            if (match == null) return null;
            return new[] { match.Name, parts[1].Trim() };
        }

        // --- Menu ---------------------------------------------------------------------

        // Entry of the menu: level 0 with a glyph (and an arrow for groups), level 1
        // indented, with the category icon if any
        ListBoxItem NewNavItem(string id, string title, int glyph, int level, NavTag tag, string icon = "", bool? open = null)
        {
            var item = new ListBoxItem();
            var g = NewGrid("Auto", "*", "Auto");
            if (level == 0)
            {
                var gl = NewGlyph(glyph, 15);
                gl.Width = 22;
                gl.Margin = T(0, 0, 10, 0);
                g.Children.Add(gl);
                item.Padding = T(12, 9);
            }
            else
            {
                var img = new Image { Width = 16, Height = 16, Margin = T(0, 0, 10, 0), Source = GetBitmap(icon, 40) };
                g.Children.Add(img);
                tag.Icon = img;
                item.Padding = T(44, 7, 12, 7);
            }
            var t = NewText(title, level == 0 ? 13.5 : 13);
            t.VerticalAlignment = VerticalAlignment.Center;
            t.TextTrimming = TextTrimming.CharacterEllipsis;
            SetCol(t, 1);
            g.Children.Add(t);
            if (open != null)
            {
                var ch = NewGlyph(open.Value ? 0xE70D : 0xE76C, 9);
                ch.Foreground = ResBrush("DimBrush");
                ch.Margin = T(8, 0, 0, 0);
                SetCol(ch, 2);
                g.Children.Add(ch);
                item.PreviewMouseLeftButtonDown += (s, e) => SwitchNavGroup(item, e);
            }
            else if (level == 0)
            {
                // the dot of the gear in the launcher, on the entry it leads to
                var dot = new Ellipse
                {
                    Width = 8, Height = 8, Fill = ResBrush("AccentBrush"), Margin = T(8, 0, 0, 0),
                    VerticalAlignment = VerticalAlignment.Center, Visibility = Visibility.Collapsed,
                };
                SetCol(dot, 2);
                g.Children.Add(dot);
                tag.Dot = dot;
            }
            item.Content = g;
            tag.Id = id;
            tag.Title = t;
            item.Tag = tag;
            return item;
        }

        // Import: games or apps found and not seen in the list yet
        bool TestNewFound()
        {
            if (!File.Exists(Core.FoundFile)) return false;
            string text;
            try { text = File.ReadAllText(Core.FoundFile); } catch { return false; }
            if (!Regex.IsMatch(text, "\"New\"\\s*:\\s*true")) return false;
            var items = ReadFoundItems(text);
            var seen = Core.ReadSeen();
            return items.Any(it => it.New && !seen.Contains(it.Id));
        }

        bool TestUpdateAvailable()
        {
            var info = Core.ReadUpdateInfo();
            return info != null && Json.Bool(info, "Newer") && Json.Str(info, "Error") == "" && Json.Str(info, "Current") == Core.GetInstalledVersion();
        }

        // The files are read again only after a change (reload): the menu is rebuilt
        // often (opening a group, a category)
        void UpdateNavDots(bool reload = false)
        {
            // while the window opens the files are not read: ShowFirstPage does it
            if (!reload && navDots == null && !firstShown) return;
            if (reload || navDots == null) navDots = new[] { TestNewFound() || TestMissingAny(), TestUpdateAvailable() };
            bool newFound = navDots[0], update = navDots[1];
            foreach (var it in nav.Items.OfType<ListBoxItem>().Concat(navBottom.Items.OfType<ListBoxItem>()))
            {
                var tag = (NavTag)it.Tag;
                if (tag.Dot == null) continue;
                bool on = (tag.Id == "page:import" && newFound) || (tag.Id == "page:info" && update);
                tag.Dot.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
                it.ToolTip = !on ? null : (update && tag.Id == "page:info") ? "A new version of Raintile is available"
                    : "New games or apps found, or tiles of games no longer installed";
            }
        }

        void BuildNav(string selectId)
        {
            navBuilding = true;
            try
            {
                nav.Items.Clear();
                foreach (var node in Schema.NavTree)
                {
                    if (node.Children != null)
                    {
                        bool open = navOpen.ContainsKey(node.Id) && navOpen[node.Id];
                        nav.Items.Add(NewNavItem("group:" + node.Id, node.Title, node.Icon, 0,
                            new NavTag { Type = "group", Group = node.Id, First = "page:" + node.Children[0] }, "", open));
                        if (open)
                            foreach (var c in node.Children)
                                nav.Items.Add(NewNavItem("page:" + c, Schema.ById(c).Title, 0, 1, new NavTag { Type = "page", Page = Schema.ById(c) }));
                    }
                    else if (node.Categories)
                    {
                        if (!firstShown) AddStartStep("  menu: pages");
                        var page = Schema.ById(node.Page);
                        bool open = navOpen["categories"];
                        nav.Items.Add(NewNavItem("categories", page.Title, page.Icon, 0, new NavTag { Type = "page", Group = "categories", Page = page }, "", open));
                        if (open)
                        {
                            var entries = GetCategoryMenuEntries();
                            if (!firstShown) AddStartStep("  menu: categories read (" + entries.Count + ")");
                            foreach (var e in entries)
                                nav.Items.Add(NewNavItem("cat:" + e.File, e.Name, 0, 1, new NavTag { Type = "category", File = e.File }, e.Icon));
                            if (!firstShown) AddStartStep("  menu: categories added");
                        }
                    }
                    else
                    {
                        var page = Schema.ById(node.Page);
                        nav.Items.Add(NewNavItem("page:" + node.Page, page.Title, page.Icon, 0, new NavTag { Type = "page", Page = page }));
                    }
                }
                foreach (ListBoxItem it in nav.Items) if (((NavTag)it.Tag).Id == selectId) nav.SelectedItem = it;
                UpdateNavDots();
            }
            finally { navBuilding = false; }
        }

        // Goes to a menu entry (after the current event: the menu may be rebuilt)
        void OpenNav(string id)
        {
            navPending = id;
            win.Dispatcher.BeginInvoke(new Action(() =>
            {
                BuildNav(navPending);
                var sel = nav.SelectedItem as ListBoxItem;
                if (sel != null) ShowNavTarget((NavTag)sel.Tag);
            }));
        }

        void OpenCategory(string file)
        {
            navOpen["categories"] = true;
            OpenNav("cat:" + file);
        }

        // Click on a group: opens or closes it. Keybindings has no page of its own
        // and goes to its first entry; Categories opens on the first click and only
        // closes when its page is already shown.
        void SwitchNavGroup(ListBoxItem item, MouseButtonEventArgs e)
        {
            var tag = (NavTag)item.Tag;
            bool open = navOpen.ContainsKey(tag.Group) && navOpen[tag.Group];
            if (tag.Type == "group")
            {
                e.Handled = true;
                navOpen[tag.Group] = !open;
                OpenNav(!open ? tag.First : navCurrent);
            }
            else if (navCurrent == tag.Id)
            {
                e.Handled = true;
                navOpen[tag.Group] = !open;
                OpenNav(navCurrent);
            }
            else if (!open)
            {
                e.Handled = true;
                navOpen[tag.Group] = true;
                OpenNav(tag.Id);
            }
        }

        void ShowPage(Page page)
        {
            if (page.Id == "info") pages.Remove("info");   // the counts may have changed
            if (!pages.ContainsKey(page.Id))
            {
                updating = true;
                try
                {
                    pages[page.Id] = page.Id == "categories" ? NewCategoryListPage() : page.Id == "info" ? NewInfoPage() : NewSettingsPage(page);
                }
                finally { updating = false; }
                UpdateResets();
                UpdateKeyConflicts();
            }
            if (page.Id == "categories") RefreshCats(currentFile);
            pageHost.Children.Clear();
            pageHost.Children.Add(pages[page.Id]);
            pageTitle.Text = page.Title;
            pageDesc.Text = page.Desc;
        }

        void ShowCategoryPage(string file)
        {
            if (!pages.ContainsKey("category")) pages["category"] = NewCategoryPage();
            currentFile = file;
            ShowCategory();
            pageHost.Children.Clear();
            pageHost.Children.Add(pages["category"]);
            var c = Core.GetCategorySection(GetModel(file));
            string name = Core.GetKey(c, "Name");
            pageTitle.Text = name != "" ? name : System.IO.Path.GetFileNameWithoutExtension(file);
            pageDesc.Text = "Categories\\" + file + ": its tiles. Name, icon and grid of the category are on the Categories page.";
        }

        void ShowNavTarget(NavTag tag)
        {
            switch (tag.Type)
            {
                case "page": ShowPage(tag.Page); break;
                case "category": ShowCategoryPage(tag.File); break;
                default: return;
            }
            navCurrent = tag.Id;
        }

        // --- Updates (Info page) ----------------------------------------------------------
        // Update.ps1 keeps the last check in Update.json (data folder). "Download and
        // install" downloads the release's .rmskin and opens it: the Rainmeter
        // installer takes over (your data is not in the skin folder, so it stays).

        TextBlock updInstalled, updLatest, updStatus, updNotes;
        Border updNotesBox;
        Button updInstall, updPage, updCheck;

        void ShowUpdateInfo()
        {
            if (updStatus == null) return;
            var info = Core.ReadUpdateInfo();
            string installed = Core.GetInstalledVersion();
            updInstalled.Text = installed;
            if (info == null) updLatest.Text = "Not checked yet";
            else if (Json.Str(info, "Error") != "") updLatest.Text = "Check failed: " + Json.Str(info, "Error");
            else
            {
                string when = "";
                DateTime d;
                if (DateTime.TryParse(Json.Str(info, "Checked"), out d)) when = "   \u00B7   checked " + d.ToString("g");
                string latest = Json.Str(info, "Latest");
                updLatest.Text = (latest != "" ? latest : "unknown") + when;
            }
            bool newer = info != null && Json.Bool(info, "Newer") && Json.Str(info, "Current") == installed;
            updStatus.Text = newer ? "Raintile " + Json.Str(info, "Latest") + " is available." : info != null && Json.Str(info, "Error") == "" ? "Raintile is up to date." : "";
            updStatus.Foreground = newer ? ResBrush("AccentBrush") : ResBrush("DimBrush");
            updNotes.Text = newer ? Json.Str(info, "Notes") : "";
            updNotesBox.Visibility = updNotes.Text != "" ? Visibility.Visible : Visibility.Collapsed;
            updInstall.Visibility = newer ? Visibility.Visible : Visibility.Collapsed;
            updInstall.Content = newer && Json.Str(info, "Asset") != "" ? "Download and install" : "Open the release page";
            updPage.Visibility = info != null && Json.Str(info, "Page") != "" ? Visibility.Visible : Visibility.Collapsed;
            UpdateNavDots(true);
        }

        // Asks GitHub through Update.ps1 (in the background), then shows the result
        void InvokeCheckNow()
        {
            updStatus.Text = "Checking\u2026";
            updCheck.IsEnabled = false;
            Process p;
            try { p = StartScript("Update.ps1", "-Resources " + Arg(Core.Resources) + " -Data " + Arg(Core.Data) + " -Force"); }
            catch (Exception e) { updStatus.Text = "Check failed: " + e.Message; updCheck.IsEnabled = true; return; }
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
            timer.Tick += (s, e) =>
            {
                if (!p.HasExited) return;
                timer.Stop();
                updCheck.IsEnabled = true;
                ShowUpdateInfo();
                var info = Core.ReadUpdateInfo();
                // no dot on the gear without an update
                if (info != null && Json.Str(info, "Error") == "" && !Json.Bool(info, "Newer"))
                    InvokeRainmeter("!CommandMeasure MeasureScript \"OnUpdateSeen()\" \"" + Core.Config + "\"");
            };
            timer.Start();
        }

        // Opens the release page (only a GitHub page of this repository)
        static void OpenReleasePage(Dictionary<string, object> info)
        {
            string page = info != null && Core.TestReleaseUrl(Json.Str(info, "Page")) ? Json.Str(info, "Page") : "https://github.com/" + Core.Repository + "/releases";
            OpenUrl(page);
        }

        void InstallUpdate()
        {
            var info = Core.ReadUpdateInfo();
            if (info == null) return;
            string asset = Json.Str(info, "Asset");
            if (!Core.TestReleaseUrl(asset)) { OpenReleasePage(info); return; }
            var r = ShowDialog("Update Raintile", "Download Raintile " + Json.Str(info, "Latest") + " and open the Rainmeter installer?\r\n\r\n" +
                "Your settings, categories and images stay: they are in " + Core.Data + ", which the installer does not touch. " +
                "In the installer keep the default options and press Install.\r\n\r\n" +
                "This is still experimental: keep a copy of your data folder first.", new[] { "Download and install", "Cancel" });
            if (r.Button != "Download and install") return;
            // a new folder of its own, and a name made here: nothing else can be
            // put in its place before it is opened
            string ver = Core.GetSafeVersion(Json.Str(info, "Latest"));
            string folder = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "Raintile-update-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(folder);
            string dest = System.IO.Path.Combine(folder, ver != "" ? "Raintile_" + ver + ".rmskin" : "Raintile_update.rmskin");
            updStatus.Text = "Downloading\u2026";
            updInstall.IsEnabled = false;
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var wc = new WebClient();
            wc.Headers.Add("User-Agent", "Raintile");
            wc.DownloadFileCompleted += (s, e) =>
            {
                wc.Dispose();
                updInstall.IsEnabled = true;
                if (e.Error != null) { updStatus.Text = "Download failed: " + e.Error.Message; return; }
                if (!Core.TestRmskinPackage(dest))
                {
                    try { Directory.Delete(folder, true); } catch { }
                    updStatus.Text = "The downloaded file is not a Rainmeter package: nothing was installed.";
                    return;
                }
                // .rmskin files open with the Rainmeter skin installer; this window
                // closes so that nothing of the skin folder is in use
                try { Process.Start(new ProcessStartInfo(dest) { UseShellExecute = true }); }
                catch (Exception ex) { updStatus.Text = "The installer could not be opened: " + ex.Message; return; }
                win.Close();
            };
            wc.DownloadFileAsync(new Uri(asset), dest);
        }

        Border NewUpdateCard()
        {
            var card = NewCard("Updates", "");
            var f = CardPanel(card);
            var beta = NewText("Experimental: installing updates from here is still being tested and could cause problems. " +
                "Before installing, keep a copy of your data folder; if something goes wrong, the release page has the package to install by hand.", 12.5, ResBrush("AccentBrush"), false, true);
            beta.Margin = T(0, 0, 0, 6);
            AddTo(f, beta);
            updInstalled = NewText("", 13, null, false, true);
            updLatest = NewText("", 13, null, false, true);
            foreach (var row in new[] { Tuple.Create(updInstalled, "Installed"), Tuple.Create(updLatest, "Latest version") })
            {
                row.Item1.MaxWidth = 460;
                row.Item1.TextAlignment = TextAlignment.Right;
                f.Children.Add(NewRow(row.Item2, "", row.Item1, null));
            }
            updStatus = NewText("", 13.5, null, false, true);
            updStatus.Margin = T(0, 12, 0, 6);
            AddTo(f, updStatus);
            updNotesBox = new Border { Background = ResBrush("FieldBg"), CornerRadius = new CornerRadius(8), Padding = T(14, 10), Margin = T(0, 0, 0, 10) };
            var sv = new ScrollViewer { MaxHeight = 220, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            updNotes = NewText("", 12.5, ResBrush("DimBrush"), false, true);
            sv.Content = updNotes;
            updNotesBox.Child = sv;
            AddTo(f, updNotesBox);
            var bar = NewPanel(Orientation.Horizontal);
            bar.Margin = T(0, 4, 0, 10);
            updInstall = NewButton("Download and install", "AccentButton");
            updInstall.Margin = T(0, 0, 8, 0);
            updCheck = NewButton("Check now");
            updCheck.Margin = T(0, 0, 8, 0);
            updPage = NewButton("Release page", "LinkButton");
            updPage.VerticalAlignment = VerticalAlignment.Center;
            AddTo(bar, updInstall); AddTo(bar, updCheck); AddTo(bar, updPage);
            AddTo(f, bar);
            updInstall.Click += (s, e) => InstallUpdate();
            updCheck.Click += (s, e) => InvokeCheckNow();
            updPage.Click += (s, e) => OpenReleasePage(Core.ReadUpdateInfo());
            ShowUpdateInfo();
            return card;
        }

        // Info page: what Raintile is, version, where it is, and its files
        UIElement NewInfoPage()
        {
            StackPanel sp;
            var sv = NewPageScroller(out sp);

            var card = NewCard("", "");
            card.Padding = T(24, 20, 24, 20);
            var head = NewPanel(Orientation.Horizontal);
            AddTo(head, NewText("Raintile", 26, null, true));
            if (version != "")
            {
                var badge = new Border
                {
                    Background = ResBrush("AccentSoftBrush"), CornerRadius = new CornerRadius(4), Padding = T(8, 2, 8, 2),
                    Margin = T(12, 4, 0, 0), VerticalAlignment = VerticalAlignment.Center,
                    Child = NewText(version, 12, ResBrush("AccentBrush"), true),
                };
                AddTo(head, badge);
            }
            AddTo(CardPanel(card), head);
            var about = NewText(information != "" ? information : "Full-screen tile launcher for Rainmeter.", 13.5, ResBrush("DimBrush"), false, true);
            about.Margin = T(0, 8, 0, 0);
            AddTo(CardPanel(card), about);
            var more = NewText("Categories in a menu at the top, tiles with background art and logo, mouse, keyboard and gamepad, search, games and apps found on this PC. Every setting is described in the Guide, on GitHub.", 12.5, ResBrush("DimBrush"), false, true);
            more.Margin = T(0, 6, 0, 0);
            AddTo(CardPanel(card), more);
            AddTo(sp, card);

            var entries = GetCategoryEntries();
            int tiles = entries.Sum(e => e.Tiles), imported = entries.Sum(e => e.Imported);
            card = NewCard("Details", "");
            foreach (var row in new[]
            {
                new[] { "Version", version != "" ? version.Substring(1) : "unknown" },
                new[] { "Rainmeter skin", Core.Config },
                new[] { "Your data", Core.Data },
                new[] { "Skin folder", System.IO.Path.GetDirectoryName(Core.Resources) },
                new[] { "Categories", entries.Count.ToString() },
                new[] { "Tiles", tiles + " written by hand, " + imported + " imported" },
            })
            {
                var v = NewText(row[1], 13, null, false, true);
                v.MaxWidth = 460;
                v.TextAlignment = TextAlignment.Right;
                CardPanel(card).Children.Add(NewRow(row[0], "", v, null));
            }
            AddTo(sp, card);

            AddTo(sp, NewUpdateCard());

            card = NewCard("Files", "");
            var cp = CardPanel(card);
            cp.Children.Add(NewRow("Settings", "Settings.inc, in Notepad.", NewActionControl("OpenSettings", "Open Settings.inc"), null));
            cp.Children.Add(NewRow("Your data", "Settings, categories and images: updates never touch this folder.", NewActionControl("OpenFolder", "Open the folder"), null));
            var backupButtons = NewPanel(Orientation.Horizontal);
            var b = (FrameworkElement)NewActionControl("Backup", "Back up...");
            b.Margin = T(0, 0, 8, 0);
            AddTo(backupButtons, b);
            AddTo(backupButtons, NewActionControl("Restore", "Restore..."));
            cp.Children.Add(NewRow("Backup", "Your data in a zip file, to keep it safe or move it to another PC (the SteamGridDB key only works for the same Windows user).", backupButtons, null));
            cp.Children.Add(NewRow("Skin folder", "Scripts and the default files of this version.", NewActionControl("OpenSkinFolder", "Open the folder"), null));
            cp.Children.Add(NewRow("Rainmeter", "The Manage window: skins, Rainmeter settings and log.", NewActionControl("OpenRainmeter", "Open Rainmeter"), null));
            cp.Children.Add(NewRow("Guide", "Every setting, the controls and troubleshooting, on GitHub.", NewActionControl("OpenGuide", "Open the Guide"), null));
            AddTo(sp, card);
            return sv;
        }
    }
}
