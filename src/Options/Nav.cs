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
        public string Type, Group, File, Id;
        public Page Page;
        public TextBlock Title;
        public Image Icon;
        public Ellipse Dot;
        public string DotTip;   // what the dot means, while it is shown
    }

    public partial class OptionsApp
    {
        ListBox nav, navBottom;
        Grid pageHost;
        // the switch of the page shown (Page.Switch), beside its title
        ContentControl pageSwitch;
        readonly Dictionary<string, UIElement> pageSwitches = new Dictionary<string, UIElement>();
        TextBlock pageTitle, pageDesc, status;
        Button btnSave;
        string version = "", information = "";
        readonly Dictionary<string, UIElement> pages = new Dictionary<string, UIElement>();
        readonly Dictionary<string, bool> navOpen = new Dictionary<string, bool> { { "tiles", true }, { "toprow", true }, { "keybindings", true }, { "import", true }, { "categories", true } };
        bool navBuilding;
        string navCurrent, navPending;
        // what the dots of the menu show, read again after a change (UpdateNavDots)
        class NavDotState { public bool Found, Update; public HashSet<string> NewTileFiles; }
        NavDotState navDots;
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
            // the tile editor wants room, but smaller screens get what they have
            var work = SystemParameters.WorkArea;
            win.Width = Math.Max(win.MinWidth, Math.Min(win.Width, work.Width - 40));
            win.Height = Math.Max(win.MinHeight, Math.Min(win.Height, work.Height - 40));
            if (offscreen)
            {
                // cloaked (DWMWA_CLOAK, as the windows of another virtual desktop): not
                // drawn on screen, never under the mouse, but still rendered, so the
                // tools shoot it with PrintWindow and reach its pages with UI
                // Automation. Off every monitor instead, WPF would not render it.
                win.ShowActivated = false;
                win.ShowInTaskbar = false;
                win.WindowStartupLocation = WindowStartupLocation.Manual;
                win.Left = 0;
                win.Top = 0;
                win.SourceInitialized += (s, e) =>
                {
                    var hwnd = new System.Windows.Interop.WindowInteropHelper(win).Handle;
                    int on = 1;
                    Win32.DwmSetWindowAttribute(hwnd, 13, ref on, sizeof(int));
                    // What the tools change, they ask with a message, lParam the point on
                    // the screen of what they mean: UI Automation's Select and Scroll would
                    // activate the window (they do with any WPF window) and take the focus
                    // from the user. WM_APP + 1: select the entry there (of the menu, of
                    // the tiles); WM_APP + 2: the page there to its top (wParam 0) or one
                    // screen down (1). Answer 1: done; 0: nothing there to do it to.
                    System.Windows.Interop.HwndSource.FromHwnd(hwnd).AddHook((IntPtr h, int msg, IntPtr wp, IntPtr lp, ref bool handled) =>
                    {
                        if (msg != 0x8001 && msg != 0x8002) return IntPtr.Zero;
                        handled = true;
                        long v = lp.ToInt64();
                        var hit = win.InputHitTest(win.PointFromScreen(new Point((short)(v & 0xFFFF), (short)((v >> 16) & 0xFFFF)))) as DependencyObject;
                        // the entry, or the outermost list that scrolls: the page, not a list in it
                        DependencyObject found = null;
                        for (; hit != null; hit = hit is Visual ? VisualTreeHelper.GetParent(hit) : LogicalTreeHelper.GetParent(hit))
                        {
                            if (msg == 0x8001 && hit is ListBoxItem) { found = hit; break; }
                            var sv = hit as ScrollViewer;
                            if (msg == 0x8002 && sv != null && sv.ScrollableHeight > 0) found = sv;
                        }
                        if (found == null) return IntPtr.Zero;
                        if (msg == 0x8001) ((ListBoxItem)found).IsSelected = true;
                        else if (wp == IntPtr.Zero) ((ScrollViewer)found).ScrollToTop();
                        else ((ScrollViewer)found).PageDown();
                        win.UpdateLayout();
                        return (IntPtr)1;
                    });
                };
            }
            ((TextBlock)win.FindName("Version")).Text = version;
            AddStartStep("window");
            nav = (ListBox)win.FindName("Nav");
            navBottom = (ListBox)win.FindName("NavBottom");
            pageHost = (Grid)win.FindName("PageHost");
            pageSwitch = (ContentControl)win.FindName("PageSwitch");
            UpdateControlColumn();
            pageHost.SizeChanged += (s, e) => UpdateControlColumn();
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
                ShowNavTarget((NavTag)sel.Tag);
            };
            InitSearch();
            // Up and down go round the menu; up from its first entry, to the search
            foreach (var list in new[] { nav, navBottom })
                list.PreviewKeyDown += (s, e) =>
                {
                    if ((e.Key != Key.Up && e.Key != Key.Down) || Keyboard.Modifiers != ModifierKeys.None) return;
                    e.Handled = true;
                    if (e.Key == Key.Up && NavEntries().IndexOf((nav.SelectedItem ?? navBottom.SelectedItem) as ListBoxItem) == 0) { FocusSearch(); return; }
                    var next = NavStep(e.Key == Key.Down ? 1 : -1);
                    if (next != null) next.Focus();
                };

            btnSave.Click += (s, e) => StartSaveAndRefresh();
            ((Button)win.FindName("BtnClose")).Click += (s, e) => win.Close();
            win.PreviewKeyDown += (s, e) =>
            {
                if (refreshing || autoAdding) { e.Handled = true; return; }   // waiting for the skin, or for the games added
                if (e.Key == Key.S && Keyboard.Modifiers == ModifierKeys.Control && capturing == null)
                {
                    e.Handled = true;
                    StartSaveAndRefresh();
                }
                else if (e.Key == Key.F && Keyboard.Modifiers == ModifierKeys.Control && capturing == null)
                {
                    e.Handled = true;
                    FocusSearch();
                }
            };
            win.Closing += (s, e) =>
            {
                if (!dirtySettings || skipSavePrompt) return;
                var r = ShowDialog("Unsaved changes", "Save the changes before closing?", new[] { "Save", "Don't save", "Cancel" });
                if (r.Button == "Save") SaveAll();
                else if (r.Button != "Don't save") e.Cancel = true;
            };
            win.SourceInitialized += (s, e) => SetDarkTitle(win);
            InitGamepad();
            InitPreview();
            // Started without a console: bring the window to the foreground explicitly
            // (not in a run of the UI tools: the focus stays where the user is working)
            win.ContentRendered += (s, e) =>
            {
                if (!offscreen)
                {
                    win.Topmost = true;
                    win.Activate();
                    win.Topmost = false;
                    Win32.SetForegroundWindow(new System.Windows.Interop.WindowInteropHelper(win).Handle);
                }
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
            // (-Page new: the category of the first tile added by itself, not shown yet)
            if (openPage == "new") { var t = NewTiles().FirstOrDefault(); if (t != null) editTile = new[] { t.File, "" }; }
            // The menu is built before the window appears, the page right after
            if (openPage == "info") BuildNav("");
            else if (editTile != null) { navOpen["categories"] = true; BuildNav("cat:" + editTile[0]); }
            else BuildNav(openPage == "import" ? "page:found" : "page:general");
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
                if (editTile[1] != "") SelectTileByName(editTile[1]);
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
            var g = NewGrid("Auto", "*", "Auto", "Auto");
            if (level == 0)
            {
                var gl = NewGlyph(glyph, 15);   // ui-exempt: menu chrome
                gl.Width = 22;
                gl.Margin = T(0, 0, Gap.Text, 0);
                g.Children.Add(gl);
                item.Padding = Gap.ListItem;
            }
            else
            {
                var img = new Image { Width = 16, Height = 16, Margin = T(0, 0, Gap.Text, 0), Source = GetBitmap(icon, 40) };
                g.Children.Add(img);
                tag.Icon = img;
                item.Padding = T(44, 7, 12, 7);   // ui-exempt: menu chrome, the entries of a group
            }
            var t = NewText(title, Fs.Label);
            t.VerticalAlignment = VerticalAlignment.Center;
            t.TextTrimming = TextTrimming.CharacterEllipsis;
            SetCol(t, 1);
            g.Children.Add(t);
            // the tooltip: the full name when it is cut, and what the dot means (UpdateNavDots)
            item.ToolTip = "";
            item.ToolTipOpening += (s, e) =>
            {
                string tip = IsTrimmed(t) ? t.Text : "";
                if (tag.DotTip != null) tip += (tip != "" ? "\r\n" : "") + tag.DotTip;
                if (tip == "") { e.Handled = true; return; }
                item.ToolTip = tip;
            };
            // the dot of the gear in the launcher, on the entries it leads to (a
            // group too, also closed)
            var dot = new Ellipse
            {
                Width = 8, Height = 8, Fill = ResBrush("AccentBrush"), Margin = T(Gap.Control, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center, Visibility = Visibility.Collapsed,
            };
            SetCol(dot, 2);
            g.Children.Add(dot);
            tag.Dot = dot;
            if (open != null)
            {
                var ch = NewGlyph(open.Value ? Glyph.GroupOpen : Glyph.GroupClosed, 9);   // ui-exempt: menu chrome
                ch.Foreground = ResBrush("DimBrush");
                ch.Margin = T(Gap.Control, 0, 0, 0);
                SetCol(ch, 3);
                g.Children.Add(ch);
                item.PreviewMouseLeftButtonDown += (s, e) => SwitchNavGroup(item, e);
            }
            item.Content = g;
            tag.Id = id;
            tag.Title = t;
            item.Tag = tag;
            SetNavApplies(item);
            return item;
        }

        // The title of a section of the menu (NavNode.Section), above its entries:
        // not an entry, never selected nor passed over (NavEntries leaves out the
        // disabled ones)
        ListBoxItem NewNavSection(string title)
        {
            var t = NewSectionTitle(title);
            t.TextTrimming = TextTrimming.CharacterEllipsis;
            return new ListBoxItem
            {
                Content = t, IsEnabled = false, IsHitTestVisible = false, Focusable = false,
                Padding = T(Gap.Group, nav.Items.Count == 0 ? Gap.Line : Gap.Card, Gap.Group, Gap.Line),
                Tag = new NavTag { Type = "section" },
            };
        }

        // The page of a mode not in use (Page.When: Grid, Wheel): its entry greyed
        // out and passed over, until the setting it needs changes
        void SetNavApplies(ListBoxItem item)
        {
            var tag = (NavTag)item.Tag;
            if (tag.Page == null || string.IsNullOrEmpty(tag.Page.When)) return;
            bool on = WhenHolds(tag.Page.When);
            item.IsEnabled = on;
            if (on) tag.Title.ClearValue(TextBlock.ForegroundProperty);
            else tag.Title.Foreground = ResBrush("DimBrush");
        }

        void UpdateNavApplies()
        {
            if (nav == null) return;
            foreach (ListBoxItem it in nav.Items) SetNavApplies(it);
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
            if (reload || navDots == null)
            {
                newTiles = null;
                navDots = new NavDotState
                {
                    Found = TestNewFound() || TestMissingAny(), Update = TestUpdateAvailable(),
                    NewTileFiles = new HashSet<string>(NewTiles().Select(t => t.File), StringComparer.OrdinalIgnoreCase),
                };
            }
            foreach (var it in nav.Items.OfType<ListBoxItem>().Concat(navBottom.Items.OfType<ListBoxItem>()))
            {
                var tag = (NavTag)it.Tag;
                if (tag.Dot == null) continue;
                string tip = null;
                if ((tag.Id == "page:import" || tag.Id == "page:found") && navDots.Found) tip = "New games or apps found, or tiles of games no longer installed.";
                else if (tag.Id == "page:info" && navDots.Update) tip = "A new version of Raintile is available.";
                else if ((tag.Id == "categories" && navDots.NewTileFiles.Count > 0) || (tag.Type == "category" && navDots.NewTileFiles.Contains(tag.File)))
                    tip = "Games added by themselves: open the category to see them.";
                tag.Dot.Visibility = tip != null ? Visibility.Visible : Visibility.Collapsed;
                tag.DotTip = tip;
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
                    if (node.Section != null) nav.Items.Add(NewNavSection(node.Section));
                    if (node.Children != null)
                    {
                        // a page with sub-pages below it: a click on it shows it and
                        // opens them, a click when it is shown closes them
                        var page = Schema.ById(node.Page);
                        bool open = navOpen.ContainsKey(node.Page) && navOpen[node.Page];
                        nav.Items.Add(NewNavItem("page:" + node.Page, page.Title, page.Icon, 0, new NavTag { Type = "page", Group = node.Page, Page = page }, "", open));
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
                        // Widgets: below it the installed widgets that have settings, a group that opens and closes
                        var withSettings = node.Page == "dashboard" ? InstalledWidgets().Where(id => WidgetOptions(id).Count > 0).ToList() : null;
                        if (withSettings != null && withSettings.Count > 0)
                        {
                            bool open = navOpen.ContainsKey("widgets") && navOpen["widgets"];
                            nav.Items.Add(NewNavItem("page:" + node.Page, page.Title, page.Icon, 0, new NavTag { Type = "page", Group = "widgets", Page = page }, "", open));
                            if (open)
                                foreach (var id in withSettings)
                                {
                                    string name = WidgetInfo(id, "Name");
                                    nav.Items.Add(NewNavItem("widget:" + id, name != "" ? name : id, 0, 1, new NavTag { Type = "widget", File = id }));
                                }
                        }
                        else nav.Items.Add(NewNavItem("page:" + node.Page, page.Title, page.Icon, 0, new NavTag { Type = "page", Page = page }));
                    }
                }
                foreach (ListBoxItem it in nav.Items) if (((NavTag)it.Tag).Id == selectId) nav.SelectedItem = it;
                UpdateNavDots();
            }
            finally { navBuilding = false; }
        }

        // The entries of the menu in order, the bottom ones (Info) last; not the
        // disabled ones
        List<ListBoxItem> NavEntries()
        {
            return nav.Items.OfType<ListBoxItem>().Concat(navBottom.Items.OfType<ListBoxItem>()).Where(it => it.IsEnabled).ToList();
        }

        // Selects the entry 'delta' steps from the selected one, round the end of
        // the menu (keyboard arrows, D-pad, LB / RB).
        ListBoxItem NavStep(int delta)
        {
            var entries = NavEntries();
            if (entries.Count == 0) return null;
            int i = entries.IndexOf((nav.SelectedItem ?? navBottom.SelectedItem) as ListBoxItem);
            int n = i < 0 ? 0 : ((i + delta) % entries.Count + entries.Count) % entries.Count;
            var next = entries[n];
            if (navBottom.Items.Contains(next)) navBottom.SelectedItem = next;
            else nav.SelectedItem = next;
            if (nav.Items.Contains(next)) nav.ScrollIntoView(next);
            return next;
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

        // Click on a page with entries below it (sub-pages, categories, widgets):
        // it opens on the first click and only closes when its page is already shown.
        void SwitchNavGroup(ListBoxItem item, MouseButtonEventArgs e)
        {
            var tag = (NavTag)item.Tag;
            bool open = navOpen.ContainsKey(tag.Group) && navOpen[tag.Group];
            if (navCurrent == tag.Id)
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
            if (page.Id == "info" || page.Id == "dashboard") pages.Remove(page.Id);   // counts and Dashboard file may have changed
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
            UIElement sw;
            pageSwitch.Content = pageSwitches.TryGetValue(page.Id, out sw) ? sw : null;
        }

        void ShowCategoryPage(string file)
        {
            if (!pages.ContainsKey("category")) pages["category"] = NewCategoryPage();
            currentFile = file;
            ShowCategory();
            PreviewFollow(file);
            pageHost.Children.Clear();
            pageHost.Children.Add(pages["category"]);
            var c = Core.GetCategorySection(GetModel(file));
            string name = Core.GetKey(c, "Name");
            pageTitle.Text = name != "" ? name : System.IO.Path.GetFileNameWithoutExtension(file);
            pageSwitch.Content = null;
            pageDesc.Text = "Categories\\" + file + ": its tiles. All tiles, the first entry, holds the settings of the whole category; name and icon are on the Categories page.";
        }

        void ShowNavTarget(NavTag tag)
        {
            // another page from the menu (or LB / RB): the menu back in place of the
            // results; not for the page of a result (OpenSearchHit)
            if (navSearch != null && SearchShown && !keepSearch) navSearch.Text = "";
            keepSearch = false;
            switch (tag.Type)
            {
                case "page": ShowPage(tag.Page); break;
                case "category": ShowCategoryPage(tag.File); break;
                case "widget": ShowWidgetPage(tag.File); break;
                default: return;
            }
            // the Categories page: the tiles added by themselves have been seen
            if (tag.Id == "categories") SetNewTilesSeen(null);
            navCurrent = tag.Id;
        }

        // --- Updates (Info page) ----------------------------------------------------------
        // Update.ps1 keeps the last check in Update.json (data folder). "Download and
        // install" downloads the release's .rmskin and opens it: the Rainmeter
        // installer takes over (your data is not in the skin folder, so it stays).

        TextBlock updInstalled, updLatest, updStatus, updNotes, updHow;
        Border updNotesBox;
        Button updInstall, updInstaller, updPage, updCheck;

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
                if (DateTime.TryParse(Json.Str(info, "Checked"), out d)) when = "   " + Dot + "   checked " + d.ToString("g");
                string latest = Json.Str(info, "Latest");
                updLatest.Text = (latest != "" ? latest : "unknown") + when;
            }
            bool newer = info != null && Json.Bool(info, "Newer") && Json.Str(info, "Current") == installed;
            updStatus.Text = newer ? "Raintile " + Json.Str(info, "Latest") + " is available." : info != null && Json.Str(info, "Error") == "" ? "Raintile is up to date." : "";
            updStatus.Foreground = newer ? ResBrush("AccentBrush") : ResBrush("DimBrush");
            updNotes.Text = newer ? Json.Str(info, "Notes") : "";
            updNotesBox.Visibility = updNotes.Text != "" ? Visibility.Visible : Visibility.Collapsed;
            updInstall.Visibility = newer ? Visibility.Visible : Visibility.Collapsed;
            bool asset = newer && Json.Str(info, "Asset") != "";
            updInstall.Content = asset ? "Direct update" : "Open the release page";
            updInstaller.Visibility = asset ? Visibility.Visible : Visibility.Collapsed;
            if (updHow != null) updHow.Visibility = updInstaller.Visibility;
            updPage.Visibility = info != null && Json.Str(info, "Page") != "" ? Visibility.Visible : Visibility.Collapsed;
            UpdateNavDots(true);
        }

        // Asks GitHub through Update.ps1 (in the background), then shows the result
        void InvokeCheckNow()
        {
            updStatus.Text = "Checking...";
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

        // Downloads the release's .rmskin and installs it: directly (its files over
        // the skin folder, after a backup in Skins\@Backup\, then Rainmeter
        // reloads) or with the Rainmeter installer
        void InstallUpdate(bool direct)
        {
            var info = Core.ReadUpdateInfo();
            if (info == null) return;
            string asset = Json.Str(info, "Asset");
            if (!Core.TestReleaseUrl(asset)) { OpenReleasePage(info); return; }
            string latest = Json.Str(info, "Latest");
            string skinDir = System.IO.Path.GetDirectoryName(Core.Resources);
            var r = direct
                ? ShowDialog("Update Raintile", "Download Raintile " + latest + " and install it now?\r\n\r\n" +
                    "Its files replace the ones of the skin folder (" + skinDir + "); a copy of the current ones is kept in Skins\\@Backup. " +
                    "Your settings, categories and images stay: they are in " + Core.Data + ". Then Rainmeter reloads.", new[] { "Direct update", "Cancel" })
                : ShowDialog("Update Raintile", "Download Raintile " + latest + " and open the Rainmeter installer?\r\n\r\n" +
                    "Your settings, categories and images stay: they are in " + Core.Data + ", which the installer does not touch. " +
                    "In the installer keep the default options and press Install.", new[] { "Rainmeter installer", "Cancel" });
            if (r.Button != "Direct update" && r.Button != "Rainmeter installer") return;
            // a new folder of its own, and a name made here: nothing else can be
            // put in its place before it is opened
            string ver = Core.GetSafeVersion(latest);
            string folder = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "Raintile-update-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(folder);
            string dest = System.IO.Path.Combine(folder, ver != "" ? "Raintile_" + ver + ".rmskin" : "Raintile_update.rmskin");
            updStatus.Text = "Downloading...";
            updInstall.IsEnabled = false;
            updInstaller.IsEnabled = false;
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var wc = new WebClient();
            wc.Headers.Add("User-Agent", "Raintile");
            wc.DownloadFileCompleted += (s, e) =>
            {
                wc.Dispose();
                updInstall.IsEnabled = true;
                updInstaller.IsEnabled = true;
                if (e.Error != null) { updStatus.Text = "Download failed: " + e.Error.Message; return; }
                if (!Core.TestRmskinPackage(dest))
                {
                    try { Directory.Delete(folder, true); } catch { }
                    updStatus.Text = "The downloaded file is not a Rainmeter package: nothing was installed.";
                    return;
                }
                if (!direct)
                {
                    // .rmskin files open with the Rainmeter skin installer; this
                    // window closes so that nothing of the skin folder is in use
                    try { Process.Start(new ProcessStartInfo(dest) { UseShellExecute = true }); }
                    catch (Exception ex) { updStatus.Text = "The installer could not be opened: " + ex.Message; return; }
                    win.Close();
                    return;
                }
                updStatus.Text = "Installing...";
                win.Cursor = Cursors.Wait;
                string backup = null;
                try
                {
                    using (var zip = Core.OpenRmskin(dest))
                    {
                        string problem = Core.TestUpdatePackage(zip);
                        if (problem != null) { updStatus.Text = "This package cannot be installed: " + problem + ". Nothing was changed."; return; }
                        backup = Core.BackupSkin(skinDir, Core.GetInstalledVersion());
                        Core.InstallUpdatePackage(zip, skinDir, backup);
                    }
                }
                catch (Exception ex)
                {
                    updStatus.Text = "The update failed, the previous files were put back: " + ex.Message;
                    return;
                }
                finally
                {
                    win.Cursor = null;
                    try { Directory.Delete(folder, true); } catch { }
                }
                ShowDialog("Update Raintile", "Raintile " + latest + " is installed. Rainmeter reloads now.\r\n\r\nThe previous files are in:\r\n" + backup);
                // every skin is reloaded (new skins and scripts are seen);
                // the launcher shows itself once loaded
                WriteShowOnLoad();
                win.Close();
                InvokeRainmeter("!RefreshApp");
            };
            wc.DownloadFileAsync(new Uri(asset), dest);
        }

        Border NewUpdateCard()
        {
            var card = NewCard("Updates", "");
            var f = CardPanel(card);
            // its settings (the Updates group of the Info page in the schema)
            foreach (var item in Schema.ById("info").Groups[0].Items)
            {
                var row = NewItemRow(item);
                if (row != null) f.Children.Add(row);
            }
            updInstalled = NewHelp("", ResBrush("TextBrush"));
            updLatest = NewHelp("", ResBrush("TextBrush"));
            foreach (var row in new[] { Tuple.Create(updInstalled, "Installed"), Tuple.Create(updLatest, "Latest version") })
            {
                row.Item1.MaxWidth = FieldWidth.Wrap;
                row.Item1.TextAlignment = TextAlignment.Right;
                f.Children.Add(NewRow(row.Item2, "", row.Item1, null));
            }
            updStatus = NewText("", Fs.Label, null, false, true);
            updStatus.Margin = T(0, Gap.Group, 0, Gap.Icon);
            AddTo(f, updStatus);
            updNotesBox = new Border { Background = ResBrush("FieldBg"), CornerRadius = new CornerRadius(8), Padding = T(Gap.Group, Gap.Text), Margin = T(0, 0, 0, Gap.Text) };
            var sv = new ScrollViewer { MaxHeight = 220, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            updNotes = NewHelp("");
            sv.Content = updNotes;
            updNotesBox.Child = sv;
            AddTo(f, updNotesBox);
            // the two ways to install first (main one, then the installer), then the
            // check, the link last
            var bar = NewPanel(Orientation.Horizontal);
            bar.Margin = T(0, Gap.Line, 0, Gap.Text);
            updInstall = NewButton("Direct update", "AccentButton");
            updInstall.Margin = T(0, 0, Gap.Control, 0);
            updInstaller = NewButton("Rainmeter installer");
            updInstaller.Margin = T(0, 0, Gap.Control, 0);
            updCheck = NewButton("Check now");
            updCheck.Margin = T(0, 0, Gap.Control, 0);
            updPage = NewButton("Release page", "LinkButton");
            updPage.VerticalAlignment = VerticalAlignment.Center;
            AddTo(bar, updInstall); AddTo(bar, updInstaller); AddTo(bar, updCheck); AddTo(bar, updPage);
            AddTo(f, bar);
            updHow = NewHelp("Direct update replaces the files of the skin folder and keeps a copy of them; Rainmeter installer opens the package with the skin installer of Rainmeter.");
            updHow.Margin = T(0, 0, 0, Gap.Text);
            AddTo(f, updHow);
            updInstall.Click += (s, e) => InstallUpdate(true);
            updInstaller.Click += (s, e) => InstallUpdate(false);
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
            var head = NewPanel(Orientation.Horizontal);
            head.Margin = T(0, Gap.Card, 0, 0);
            AddTo(head, NewText("Raintile", Fs.Title, null, true));
            if (version != "")
            {
                var badge = new Border
                {
                    Background = ResBrush("AccentSoftBrush"), CornerRadius = new CornerRadius(4), Padding = Gap.Chip,
                    Margin = T(Gap.Group, Gap.Line, 0, 0), VerticalAlignment = VerticalAlignment.Center,
                    Child = NewText(version, Fs.Badge, ResBrush("AccentBrush"), true),
                };
                AddTo(head, badge);
            }
            AddTo(CardPanel(card), head);
            var about = NewText(information != "" ? information : "Full-screen tile launcher for Rainmeter.", Fs.Label, ResBrush("DimBrush"), false, true);
            about.Margin = T(0, Gap.Control, 0, 0);
            AddTo(CardPanel(card), about);
            var more = NewHelp("Categories in a menu at the top, tiles with background art and logo, mouse, keyboard and gamepad, search, games and apps found on this PC. Every setting is described in the Guide, on GitHub.");
            more.Margin = T(0, Gap.Icon, 0, Gap.Group);
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
                var v = NewHelp(row[1], ResBrush("TextBrush"));
                v.MaxWidth = FieldWidth.Wrap;
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
            backupButtons.HorizontalAlignment = HorizontalAlignment.Right;
            var b = (FrameworkElement)NewActionControl("Backup", "Back up...");
            b.Margin = T(0, 0, Gap.Control, 0);
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
