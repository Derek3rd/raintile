// Raintile Options: the Categories page (list, order, name, icon, grid) and the
// page of one category (its tiles, with the preview, framing and logo).

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;

namespace RaintileOptions
{
    class CategoryEntry
    {
        public string File, Base, Name, Icon;
        public int Order, Tiles, Imported;
        public bool Dashboard;
    }

    // What an entry of the lists holds
    class ListTag
    {
        public string File;
        public IniSection Section;
        public bool Imported;
        public bool All;   // the "All tiles" entry of a category: its own settings
        public Border Thumb;
        public TextBlock Title;
        public FrameworkElement Dot;   // a tile with settings of its own
        public FrameworkElement Pin;   // a pinned tile (Pinned=1)
    }

    public partial class OptionsApp
    {
        static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
        static readonly string Times = ((char)0xD7).ToString();   // unit of zoom and scale factors
        Dictionary<string, CategoryModel> models = new Dictionary<string, CategoryModel>(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, bool> changedFiles = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, string> logoColors = new Dictionary<string, string>();
        string currentFile;   // category whose tiles are shown (chosen in the menu)
        bool loading;

        // controls of the category pages
        ListBox catsList, tilesList;
        Border catCard, tileCard, importedCard, catIcon, bgThumb, logoThumb, preview;
        TextBlock catIconHint, gridColsHint, gridRowsHint, sizeHint, tileOpacityHint, tileNote, previewLabel, bgPath, logoPath;
        Image previewBg, previewLogo;
        Panel frameRow, logoRow;
        NumberField zoomField, logoField;
        Button tileKeyButton, tileKeyClear, catIconDel, bgDel, logoDel, catColorClear, tileColorClear;
        TextBox catTileColor;
        NumberField catOpacity, tileOpacity, gridCols, gridRows, sizeCols, sizeRows;
        SizeField catLogoSize;
        Button catOpacityReset, tileOpacityReset, gridColsReset, gridRowsReset, catLogoSizeReset;
        Button catNew, catOpen, catUp, catDown, catDel, tileNew, tileDel, tileUp, tileDown;
        Button catColorSwatch;
        ComboBox widgetKind;
        TextBox widgetParam;
        TextBlock widgetHint, placementHint;
        FrameworkElement widgetRow, widgetParamRow, placementRow;
        // the category page: preview column, All tiles card, inheritance chips
        Border allCard, previewCard, frameChip, logoChip;
        FrameworkElement previewOnRow, placeOnRow;
        ComboBox placeOn;
        Button resetFramingAll;   // All tiles: Reset every tile > Framing (none on the backdrop)
        TextBlock frameWhy, logoWhy;
        string infoNeverWhy;
        ComboBox previewOn;
        TextBlock allNote;
        Button btnFrameReset, btnLogoReset;
        // the play time line (InfoPos): its sample in the preview and its row
        Border previewInfo, infoChip;
        TextBlock infoPosText, infoWhy, placeHow;
        // rows of the grid only (Size=, NX, NY, IconSize) and their reason (UpdateGridOnlyRows)
        readonly List<Tuple<Grid, TextBlock>> gridOnlyRows = new List<Tuple<Grid, TextBlock>>();
        Button btnInfoReset;
        Panel infoRow;
        ScrollViewer previewScroll;
        BitmapSource placeholderBg, placeholderLogo;

        // Widgets: kind, label in the list, what Param= means
        static readonly string[][] WIDGET_KINDS =
        {
            new[] { "", "(none: a normal tile)", "" },
            new[] { "cpu", "CPU", "" },
            new[] { "gpu", "GPU", "" },
            new[] { "ram", "Memory", "" },
            new[] { "disk", "Disks", "A drive (C), or empty for all of them." },
            new[] { "network", "Network", "" },
            new[] { "processes", "Processes", "cpu or ram: what they are sorted by." },
            new[] { "system", "System", "" },
            new[] { "temps", "Temperatures (sensors)", "Sensor readings (LibreHardwareMonitor or HWiNFO) separated by ;, with temp:, load:, clock:, power:, fan: or volt: before one to pick that kind (load:GPU Core); (e.g. CPU Package; GPU Temperature; Total CPU Usage), =Name to rename one (GPU Hot Spot=GPU hot). Temperatures first, then any reading with that label. Empty: CPU, GPU and drives." },
            new[] { "fans", "Fans (sensors)", "Like Temperatures, for fans. Empty: the first fans." },
            new[] { "skin", "An installed skin", "<config>\\<file>.ini of a skin in Rainmeter's Skins folder, e.g. illustro\\Clock\\Clock.ini. It is loaded over the tile while its category is shown." },
            new[] { "custom", "Custom widget", "The name of a widget in the Widgets folder of your data (Widgets\\<name>.ini or Widgets\\<name>\\<name>.ini)." },
        };

        // A widget (Widget=): a tile of any category that shows data or a skin
        static bool IsWidget(IniSection s)
        {
            return s != null && Core.GetKey(s, "Widget").Trim() != "";
        }

        void UpdateWidgetHint()
        {
            string kind = ChoiceValue(widgetKind) ?? "";
            string hint = WIDGET_KINDS.Where(k => k[0] == kind).Select(k => k[2]).FirstOrDefault() ?? "";
            SetFormHelp(widgetHint, hint);
            widgetParamRow.Visibility = hint != "" ? Visibility.Visible : Visibility.Collapsed;
            if (widgetOptionRow != null) widgetOptionRow.Visibility = kind == "custom" ? Visibility.Visible : Visibility.Collapsed;
        }
        TextBox widgetOption;
        FrameworkElement widgetOptionRow;
        Button colorSwatch;
        WrapPanel tagSuggestions;
        readonly Dictionary<string, TextBox> catFields = new Dictionary<string, TextBox>();
        CheckBox catShown;
        readonly Dictionary<string, TextBox> tileFields = new Dictionary<string, TextBox>();

        CategoryModel GetModel(string file)
        {
            CategoryModel m;
            if (!models.TryGetValue(file, out m))
            {
                m = Core.ReadCategory(Path.Combine(Core.CategoriesDir, file));
                models[file] = m;
            }
            return m;
        }

        void SetChanged(string file) { changedFiles[file] = true; UpdateDirty(); PreviewChanged(file); }

        // Square thumbnail: image (or colour) in a rounded box
        Border NewThumb(double size)
        {
            var b = new Border { Width = size, Height = size, CornerRadius = new CornerRadius(5), Background = ResBrush("FieldBg") };
            b.Child = new Image { Stretch = Stretch.Uniform, Margin = T(Math.Round(size / 8)) };   // ui-exempt: drawn on the thumbnail
            return b;
        }

        void SetThumb(Border thumb, string path, Brush brush = null)
        {
            ((Image)thumb.Child).Source = GetBitmap(path, 96);
            thumb.Background = brush ?? ResBrush("FieldBg");
        }

        ListBoxItem NewListEntry(string title, string sub, ListTag tag, double thumbSize = 30)
        {
            var item = new ListBoxItem();
            var sp = NewPanel(Orientation.Horizontal);
            var thumb = NewThumb(thumbSize);
            thumb.Margin = T(0, 0, Gap.Text, 0);
            AddTo(sp, thumb);
            var texts = NewPanel();
            texts.VerticalAlignment = VerticalAlignment.Center;
            var t = NewText(title, Fs.Label);
            SetTrimmed(t);
            AddTo(texts, t);
            if (!string.IsNullOrEmpty(sub)) AddTo(texts, NewText(sub, Fs.Help, ResBrush("DimBrush")));
            AddTo(sp, texts);
            item.Content = sp;
            tag.Thumb = thumb;
            tag.Title = t;
            item.Tag = tag;
            return item;
        }

        static ListTag TagOf(object item) { var li = item as ListBoxItem; return li != null ? li.Tag as ListTag : null; }

        // category selected in the list of the Categories page
        string GetListFile() { var t = catsList != null ? TagOf(catsList.SelectedItem) : null; return t != null ? t.File : null; }
        string GetListBase() { var f = GetListFile(); return f != null ? Path.GetFileNameWithoutExtension(f) : null; }
        string GetCurrentBase() { return currentFile != null ? Path.GetFileNameWithoutExtension(currentFile) : null; }

        // Tile selected, if it can be edited (not imported)
        IniSection GetCurrentTile()
        {
            var t = tilesList != null ? TagOf(tilesList.SelectedItem) : null;
            if (t == null || t.Imported) return null;
            return t.Section;
        }

        // Tile selected, imported ones too
        IniSection GetShownTile()
        {
            var t = tilesList != null ? TagOf(tilesList.SelectedItem) : null;
            return t != null ? t.Section : null;
        }

        // An imported game as a section, read from the imported block
        static IniSection GetImportedSection(CategoryModel model, string name)
        {
            IniSection s = null;
            foreach (var line in Regex.Split(model.Imported ?? "", "\r?\n"))
            {
                string t = line.Trim();
                var m = Regex.Match(t, @"^\[(.+)\]$");
                if (m.Success)
                {
                    if (s != null) break;
                    if (string.Equals(m.Groups[1].Value.Trim(), name, StringComparison.OrdinalIgnoreCase))
                        s = new IniSection { Name = m.Groups[1].Value.Trim() };
                    continue;
                }
                if (s != null)
                {
                    m = Regex.Match(t, @"^([^;=][^=]*?)\s*=(.*)$");
                    if (m.Success) s.Keys.Add(new KeyValuePair<string, string>(m.Groups[1].Value.Trim(), m.Groups[2].Value.Trim()));
                }
            }
            return s;
        }

        static void RemoveImportedSection(CategoryModel model, string name)
        {
            var output = new List<string>();
            bool skip = false;
            foreach (var line in Regex.Split(model.Imported ?? "", "\r?\n"))
            {
                var m = Regex.Match(line.Trim(), @"^\[(.+)\]$");
                if (m.Success)
                {
                    skip = string.Equals(m.Groups[1].Value.Trim(), name, StringComparison.OrdinalIgnoreCase);
                    if (skip && output.Count > 0 && output[output.Count - 1].Trim() == "") output.RemoveAt(output.Count - 1);
                }
                if (!skip) output.Add(line);
            }
            model.Imported = string.Join("\r\n", output);
        }

        // Imported game -> hand-written tile, at the end of the tiles: its images
        // are copied to the default folders
        IniSection ConvertImportedTile(string file, string name)
        {
            var m = GetModel(file);
            var src = GetImportedSection(m, name);
            if (src == null) return null;
            string b = Path.GetFileNameWithoutExtension(file);
            var s = new IniSection { Name = src.Name };
            foreach (var kv in src.Keys)
            {
                if (kv.Key == "Background" || kv.Key == "Logo")
                {
                    string kind = kv.Key.ToLowerInvariant();
                    string path = Core.FindImage(Path.Combine(Core.ImagesRoot, b, kind), kv.Value);
                    if (path != null) { Core.CopyTileImage(b, kind, src.Name, path); continue; }
                }
                s.Keys.Add(kv);
            }
            RemoveImportedSection(m, name);
            m.Sections.Add(s);
            SetChanged(file);
            return s;
        }

        // Moves a tile and its images to another category; both files are written
        // at once. Returns an error message, or null.
        string MoveTileToCategory(string from, IniSection section, string to)
        {
            var dst = GetModel(to);
            if (dst.Sections.Any(x => string.Equals(x.Name, section.Name, StringComparison.OrdinalIgnoreCase)) || Core.GetImportedNames(dst).Contains(section.Name))
                return "There is already a tile called '" + section.Name + "' in that category.";
            string fromBase = Path.GetFileNameWithoutExtension(from), toBase = Path.GetFileNameWithoutExtension(to);
            string fromRoot = Path.Combine(Core.ImagesRoot, fromBase);
            foreach (var kind in new[] { "Background", "Logo" })
            {
                string path = Core.GetTileImage(fromBase, section, kind);
                if (path == null || !path.StartsWith(fromRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) continue;
                string dest = Path.Combine(Path.Combine(Core.ImagesRoot, toBase), path.Substring(fromRoot.Length + 1));
                Directory.CreateDirectory(Path.GetDirectoryName(dest));
                if (!File.Exists(dest)) File.Move(path, dest);
                // a full path to the old place follows the image
                string explicitName = Core.GetKey(section, kind).Trim('"');
                if (explicitName != "" && Path.IsPathRooted(explicitName)) Core.SetKey(section, kind, dest);
            }
            GetModel(from).Sections.Remove(section);
            dst.Sections.Add(section);
            foreach (var f in new[] { from, to })
            {
                Core.WriteCategory(Path.Combine(Core.CategoriesDir, f), GetModel(f));
                changedFiles.Remove(f);
            }
            UpdateDirty();
            return null;
        }

        // Colour of a tile as the skin shows it
        Brush GetTileBrush(string b, IniSection section, string bg, string logo)
        {
            Brush brush = NewColorBrush(section != null ? Core.GetKey(section, "Color") : "");
            if (brush != null) return brush;
            // the category's TileColor, as in Raintile.lua (it also turns AutoTileColor off)
            brush = currentFile != null ? NewColorBrush(Core.GetKey(Core.GetCategorySection(GetModel(currentFile)), "TileColor")) : null;
            if (brush != null) return brush;
            if (V("AutoTileColor") == "1" && logo != null && bg == null)
            {
                string c;
                try { if (logoColors.TryGetValue(Path.GetFullPath(logo), out c)) return NewColorBrush(c); } catch { }
            }
            brush = NewColorBrush(V("TileColor"));
            return brush ?? ResBrush("FieldBg");
        }

        static int ParseOrder(string text)
        {
            int order;
            if (!int.TryParse((text ?? "").Trim(), NumberStyles.Integer, Inv, out order) || order == 0) order = 9999;
            return order;
        }

        // Name, order and icon of the categories, for the menu. A category not
        // loaded yet is not parsed: only its [Category] section is read. A loaded
        // one may have unsaved changes and is read from its model.
        List<CategoryEntry> GetCategoryMenuEntries()
        {
            var list = new List<CategoryEntry>();
            foreach (var f in Core.GetCategoryFiles())
            {
                string name = "", orderText = "", iconText = "", typeText = "";
                CategoryModel model;
                if (models.TryGetValue(f.Name, out model))
                {
                    var c = Core.GetCategorySection(model);
                    name = Core.GetKey(c, "Name"); orderText = Core.GetKey(c, "Order"); iconText = Core.GetKey(c, "Icon"); typeText = Core.GetKey(c, "Type");
                }
                else
                {
                    string text;
                    try { text = File.ReadAllText(f.FullName); } catch { text = ""; }
                    var m = Regex.Match(text, @"(?ims)^[ \t]*\[Category\][ \t]*\r?$(.*?)(?=^[ \t]*\[|\z)");
                    if (m.Success)
                    {
                        foreach (Match kv in Regex.Matches(m.Groups[1].Value, @"(?im)^[ \t]*(Name|Order|Icon|Type)[ \t]*=(.*?)\r?$"))
                        {
                            string v = kv.Groups[2].Value.Trim();
                            switch (kv.Groups[1].Value.ToLowerInvariant())
                            {
                                case "name": if (name == "") name = v; break;
                                case "order": if (orderText == "") orderText = v; break;
                                case "icon": if (iconText == "") iconText = v; break;
                                case "type": if (typeText == "") typeText = v; break;
                            }
                        }
                    }
                }
                string b = Path.GetFileNameWithoutExtension(f.Name);
                list.Add(new CategoryEntry
                {
                    File = f.Name, Base = b, Order = ParseOrder(orderText), Name = name != "" ? name : b,
                    Icon = Core.FindImage(Path.Combine(Core.ImagesRoot, b), iconText != "" ? iconText : "icon"),
                    Dashboard = string.Equals(typeText.Trim(), "Dashboard", StringComparison.OrdinalIgnoreCase),
                });
            }
            return list.OrderBy(e => e.Order).ThenBy(e => e.File, StringComparer.OrdinalIgnoreCase).ToList();
        }

        // Categories in menu order, with their counts
        List<CategoryEntry> GetCategoryEntries(bool withDashboards = true)
        {
            var list = new List<CategoryEntry>();
            foreach (var f in Core.GetCategoryFiles())
            {
                var m = GetModel(f.Name);
                var c = Core.GetCategorySection(m);
                string b = Path.GetFileNameWithoutExtension(f.Name);
                string name = Core.GetKey(c, "Name");
                list.Add(new CategoryEntry
                {
                    File = f.Name, Base = b, Order = ParseOrder(Core.GetKey(c, "Order")), Name = name != "" ? name : b,
                    Icon = Core.GetCategoryIcon(b, c), Tiles = Core.GetTiles(m).Count, Imported = Core.GetImportedNames(m).Count,
                });
            }
            return list.OrderBy(e => e.Order).ThenBy(e => e.File, StringComparer.OrdinalIgnoreCase).ToList();
        }

        // List of the Categories page
        void RefreshCats(string selectFile = "")
        {
            if (catsList == null) return;
            catsList.Items.Clear();
            int index = 0, i = 0;
            foreach (var e in GetCategoryEntries())
            {
                string count = e.Tiles + " tile" + (e.Tiles != 1 ? "s" : "");
                if (e.Imported > 0) count += " + " + e.Imported + " imported";
                var item = NewListEntry(e.Name, e.File + "   " + Dot + "   " + count, new ListTag { File = e.File }, 36);
                SetThumb(((ListTag)item.Tag).Thumb, e.Icon);
                item.Padding = Gap.ListItem;
                catsList.Items.Add(item);
                if (e.File == selectFile) index = i;
                i++;
            }
            if (catsList.Items.Count > 0) catsList.SelectedIndex = index;
        }

        // Name and icon of a category in the menu and in the page title
        void UpdateNavCategory(string file)
        {
            var c = Core.GetCategorySection(GetModel(file));
            string name = Core.GetKey(c, "Name");
            string b = Path.GetFileNameWithoutExtension(file);
            if (name == "") name = b;
            foreach (ListBoxItem it in nav.Items)
            {
                var tag = (NavTag)it.Tag;
                if (tag.Id == "cat:" + file)
                {
                    tag.Title.Text = name;
                    if (tag.Icon != null) tag.Icon.Source = GetBitmap(Core.GetCategoryIcon(b, c), 40);
                }
            }
            if (catsList != null)
                foreach (ListBoxItem it in catsList.Items)
                {
                    var tag = (ListTag)it.Tag;
                    if (tag.File == file) { tag.Title.Text = name; SetThumb(tag.Thumb, Core.GetCategoryIcon(b, c)); }
                }
            if (currentFile == file && navCurrent == "cat:" + file) pageTitle.Text = name;
        }

        // Keys a tile can take from All tiles (framing, logo, play time line, TileColor,
        // TileOpacity): a tile with one of them has settings of its own (the dot in the strip)
        static readonly string[] OWN_KEYS = { "BgFocus", "BgZoom", "LogoPos", "LogoScale", "InfoPos", "BackLogoPos", "BackLogoScale", "BackInfoPos", "Color", "Opacity" };

        static bool HasOwnValues(IniSection s)
        {
            return s != null && OWN_KEYS.Any(k => Core.GetKey(s, k).Trim() != "");
        }

        // Entry of the tile strip: a small tile (background, logo) and the name below
        ListBoxItem NewStripEntry(string title, ListTag tag)
        {
            var item = new ListBoxItem { Width = 132, Padding = T(Gap.Icon), Margin = T(0, 0, Gap.Line, 0), VerticalContentAlignment = VerticalAlignment.Top };
            var sp = NewPanel();
            var g = new Grid();
            var thumb = new Border { Height = 68, CornerRadius = new CornerRadius(6), Background = ResBrush("FieldBg"), ClipToBounds = true };
            thumb.Child = new Image { Stretch = Stretch.Uniform, Margin = T(14, 10) };   // ui-exempt: drawn on the thumbnail
            g.Children.Add(thumb);
            var dot = new Border
            {
                Width = 10, Height = 10, CornerRadius = new CornerRadius(5), Background = ResBrush("AccentBrush"),
                BorderBrush = ResBrush("CardBg"), BorderThickness = T(1.5), Margin = T(0, 5, 5, 0),   // ui-exempt: drawn on the thumbnail
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top,
                Visibility = Visibility.Collapsed, ToolTip = "Its own colour, background, framing, logo or play time placement, not the one of All tiles",
            };
            g.Children.Add(dot);
            var pin = new Border
            {
                Width = 20, Height = 20, CornerRadius = new CornerRadius(10), Background = ResBrush("CardBg"),
                Margin = T(4, 4, 0, 0), HorizontalAlignment = HorizontalAlignment.Left,   // ui-exempt: drawn on the thumbnail VerticalAlignment = VerticalAlignment.Top,
                Visibility = Visibility.Collapsed, ToolTip = "Pinned: at the start of the category",
                Child = NewGlyph(Glyph.Pin, Fs.Badge),
            };
            ((TextBlock)pin.Child).HorizontalAlignment = HorizontalAlignment.Center;
            g.Children.Add(pin);
            AddTo(sp, g);
            // a caption under a thumbnail: help size, the full name when it is cut
            var t = NewText(title, Fs.Help);
            t.Margin = T(0, Gap.Icon, 0, 0);
            SetTrimmed(t);
            AddTo(sp, t);
            item.Content = sp;
            tag.Thumb = thumb; tag.Title = t; tag.Dot = dot; tag.Pin = pin;
            item.Tag = tag;
            return item;
        }

        // A small tile: the background filling it (or the colour) and the logo on it
        static void SetStripThumb(ListTag tag, ImageSource bg, ImageSource logo, Brush color)
        {
            tag.Thumb.Background = bg != null ? new ImageBrush(bg) { Stretch = Stretch.UniformToFill } : color;
            ((Image)tag.Thumb.Child).Source = logo;
        }

        void UpdateTileEntry(ListBoxItem item)
        {
            var tag = (ListTag)item.Tag;
            if (tag.All)
            {
                SetStripThumb(tag, GetPlaceholderBackground(), GetPlaceholderLogo(), null);
                return;
            }
            string b = GetCurrentBase();
            var s = tag.Section;
            string bg = Core.GetTileImage(b, s, "Background"), logo = Core.GetTileImage(b, s, "Logo");
            tag.Title.Text = s.Name;
            SetStripThumb(tag, GetBitmap(bg, 264), GetBitmap(logo, 160), GetTileBrush(b, s, bg, logo));
            tag.Dot.Visibility = !tag.Imported && HasOwnValues(s) ? Visibility.Visible : Visibility.Collapsed;
            tag.Pin.Visibility = !tag.Imported && IsPinned(s) ? Visibility.Visible : Visibility.Collapsed;
        }

        // Only the dots: placement changes leave the small tiles as they are
        void UpdateTileDots()
        {
            foreach (ListBoxItem it in tilesList.Items)
            {
                var tag = (ListTag)it.Tag;
                if (tag.Dot != null && !tag.All) tag.Dot.Visibility = !tag.Imported && HasOwnValues(tag.Section) ? Visibility.Visible : Visibility.Collapsed;
            }
        }

        void UpdateTileEntries()
        {
            foreach (ListBoxItem it in tilesList.Items) if (((ListTag)it.Tag).All || ((ListTag)it.Tag).Section != null) UpdateTileEntry(it);
        }

        // 'select': the tile to select (its index among the tiles, the imported ones
        // after them), -1 = All tiles, the first entry of the strip
        void RefreshTiles(int select = 0)
        {
            tilesList.Items.Clear();
            if (currentFile != null)
            {
                // a kept order (Order > Keep sorted): new and changed tiles to their place,
                // the one to select with them
                var before = Core.GetTiles(GetModel(currentFile));
                var wanted = select >= 0 && select < before.Count ? before[select] : null;
                if (ApplyKeptSort(currentFile) && wanted != null) select = Core.GetTiles(GetModel(currentFile)).IndexOf(wanted);
                var m = GetModel(currentFile);
                var all = NewStripEntry("All tiles", new ListTag { All = true });
                all.ToolTip = "Settings of every tile of this category";
                tilesList.Items.Add(all);
                UpdateTileEntry(all);
                foreach (var s in Core.GetTiles(m))
                {
                    var item = NewStripEntry(s.Name, new ListTag { Section = s });
                    tilesList.Items.Add(item);
                    UpdateTileEntry(item);
                }
                foreach (var n in Core.GetImportedNames(m))
                {
                    var item = NewStripEntry(n + " (imported)", new ListTag { Section = GetImportedSection(m, n), Imported = true });
                    item.Opacity = 0.7;
                    tilesList.Items.Add(item);
                    if (((ListTag)item.Tag).Section != null) UpdateTileEntry(item);
                }
            }
            if (tilesList.Items.Count > 0)
            {
                tilesList.SelectedIndex = Math.Max(0, Math.Min(select + 1, tilesList.Items.Count - 1));
                tilesList.ScrollIntoView(tilesList.SelectedItem);
            }
            else ShowTile();
        }

        bool IsAllSelected()
        {
            var t = tilesList != null ? TagOf(tilesList.SelectedItem) : null;
            return t != null && t.All;
        }

        // Background and logo standing in for any image under All tiles: a grid,
        // so moving and zooming show, and the category's icon (a game pad glyph
        // for a category without one)
        BitmapSource GetPlaceholderBackground()
        {
            if (placeholderBg != null) return placeholderBg;
            var dv = new DrawingVisual();
            using (var dc = dv.RenderOpen())
            {
                dc.DrawRectangle(new LinearGradientBrush(Color.FromRgb(0x24, 0x3B, 0x5E), Color.FromRgb(0x5B, 0x2C, 0x52), 35), null, new Rect(0, 0, 1920, 1080));
                var pen = new Pen(new SolidColorBrush(Color.FromArgb(0x2A, 255, 255, 255)), 2);
                for (int x = 0; x <= 1920; x += 120) dc.DrawLine(pen, new Point(x, 0), new Point(x, 1080));
                for (int y = 0; y <= 1080; y += 120) dc.DrawLine(pen, new Point(0, y), new Point(1920, y));
                var mark = new Pen(new SolidColorBrush(Color.FromArgb(0x70, 255, 255, 255)), 4);
                dc.DrawEllipse(null, mark, new Point(960, 540), 90, 90);
                dc.DrawLine(mark, new Point(900, 540), new Point(1020, 540));
                dc.DrawLine(mark, new Point(960, 480), new Point(960, 600));
            }
            var bmp = new RenderTargetBitmap(1920, 1080, 96, 96, PixelFormats.Pbgra32);
            bmp.Render(dv);
            bmp.Freeze();
            return placeholderBg = bmp;
        }

        BitmapSource GetPlaceholderLogo()
        {
            if (currentFile != null)
            {
                string icon = Core.GetCategoryIcon(GetCurrentBase(), Core.GetCategorySection(GetModel(currentFile)));
                var b = GetBitmap(icon, 256);
                if (b != null) return b;
            }
            if (placeholderLogo != null) return placeholderLogo;
            var dv = new DrawingVisual();
            using (var dc = dv.RenderOpen())
            {
                var text = new FormattedText("\uE7FC", CultureInfo.InvariantCulture, FlowDirection.LeftToRight,   // ui-exempt: drawn into the placeholder logo
                    new Typeface("Segoe MDL2 Assets"), 200, Brushes.White, 1.0);
                dc.DrawText(text, new Point((256 - text.Width) / 2, (256 - text.Height) / 2));
            }
            var bmp = new RenderTargetBitmap(256, 256, 96, 96, PixelFormats.Pbgra32);
            bmp.Render(dv);
            bmp.Freeze();
            return placeholderLogo = bmp;
        }

        // Tiles of the category chosen in the menu
        void ShowCategory()
        {
            if (tilesList == null) return;
            RefreshTiles();
        }

        // The tile opened from the launcher's menu (Edit this tile)
        void SelectTileByName(string name)
        {
            if (tilesList == null) return;
            for (int i = 0; i < tilesList.Items.Count; i++)
            {
                var tag = TagOf(tilesList.Items[i]);
                if (tag != null && tag.Section != null && string.Equals(tag.Section.Name, name, StringComparison.OrdinalIgnoreCase))
                {
                    tilesList.SelectedIndex = i;
                    tilesList.ScrollIntoView(tilesList.Items[i]);
                    break;
                }
            }
        }

        // Settings of the category selected in the list of the Categories page
        void ShowCategoryDetails()
        {
            if (catCard == null) return;
            loading = true;
            string file = GetListFile();
            catCard.IsEnabled = file != null;
            var c = file != null ? Core.GetCategorySection(GetModel(file)) : null;
            catFields["Name"].Text = c != null ? Core.GetKey(c, "Name") : "";
            catShown.IsChecked = c == null || Core.GetKey(c, "Hidden").Trim() != "1";
            string icon = c != null ? Core.GetCategoryIcon(GetListBase(), c) : null;
            SetThumb(catIcon, icon);
            SetActionVisible(catIconDel, icon != null);
            catIconHint.Text = file != null ? "Default: Images\\" + GetListBase() + "\\icon.png" : "";
            int i = catsList.SelectedIndex;
            catOpen.IsEnabled = catDel.IsEnabled = file != null;
            catUp.IsEnabled = file != null && i > 0;
            catDown.IsEnabled = file != null && i < catsList.Items.Count - 1;
            loading = false;
        }

        // A new category file and its image folders
        string NewCategoryFile(string b, string name)
        {
            var m = new CategoryModel { Header = "; Format: see Games.ini" };
            var c = Core.GetCategorySection(m);
            Core.SetKey(c, "Name", name);
            Core.SetKey(c, "Order", (Core.GetCategoryFiles().Count + 1).ToString());
            Directory.CreateDirectory(Core.CategoriesDir);
            Core.WriteCategory(Path.Combine(Core.CategoriesDir, b + ".ini"), m);
            foreach (var kind in new[] { "background", "logo" }) Directory.CreateDirectory(Path.Combine(Core.ImagesRoot, b, kind));
            models[b + ".ini"] = m;
            return b + ".ini";
        }

        static bool TestTileName(CategoryModel model, string name)
        {
            return model.Sections.Any(s => string.Equals(s.Name, name, StringComparison.OrdinalIgnoreCase)) || Core.GetImportedNames(model).Contains(name);
        }

        // --- Framing of the background (BgFocus, BgZoom) ----------------------------------
        // The preview has the proportions of this category's tiles on the current
        // screen (the skin writes its grid area to Generated\Area.txt) and shows the
        // part of the image the launcher shows with BgStyle=Crop. Dragging moves
        // BgFocus, the wheel and the slider set BgZoom. Same maths as frameRect in
        // Raintile.lua.

        class FrameState
        {
            public string Path; public BitmapSource Bitmap;
            public double FX = 0.5, FY = 0.5, Zoom = 1.0, TW = 16, TH = 9;
            public bool Dragging, Moved;
            public Point DragPoint; public double DragFX, DragFY;
        }
        class LogoState
        {
            public double X = 0.5, Y = 0.5, Scale = 1.0, Box = 96.0;
            public bool Dragging, Moved;
            public Point DragPoint; public double DragX, DragY;
        }
        // X, Y: InfoPos (0-1); DragX, DragY: where the line was, in preview pixels
        class InfoState
        {
            public double X, Y;
            public bool Dragging, Moved;
            public Point DragPoint; public double DragX, DragY;
        }
        readonly FrameState bgFrame = new FrameState();
        readonly LogoState logoPlace = new LogoState();
        readonly InfoState infoPlace = new InfoState();

        // The grid area of the launcher (under the top row, inside the margins):
        // width, height, gap
        double[] GetArea()
        {
            try
            {
                var parts = File.ReadAllText(Path.Combine(Core.Generated, "Area.txt")).Trim().Split(',');
                if (parts.Length == 3) return parts.Select(p => double.Parse(p, Inv)).ToArray();
            }
            catch { }
            // skin not loaded yet: the screen without menu and margins, roughly
            return new[] { screenPx[0] * 0.96, screenPx[1] * 0.88, 16 };
        }

        bool IsWheelLayout() { return V("ScrollMode").Equals("wheel", StringComparison.OrdinalIgnoreCase); }

        // The carousel: only odd columns (key NX) or rows (NY) along the scroll, as
        // on Tiles > Grid (their Item.Odd); for the grid of a category and Size=
        bool OddOf(string key)
        {
            Page page;
            var item = Schema.ItemOf(key, out page);
            return item != null && item.Odd != null && WhenHolds(item.Odd);
        }

        // Where the logo and the lines of a tile are placed, as the launcher draws
        // them: width, height and logo box (before LogoScale=), in pixels.
        //  - the grid: the tile of the category (NX, NY, its Size=), its IconSize;
        //  - the wheel: its thumbnail, a square (WheelTileSize), the logo 70% of it
        //    (M.wheelGeometry); Size=, NX, NY and IconSize are the grid's. The
        //    backdrop puts the logo and the lines where they sit on the thumbnail.
        double[] GetPlaceShape(string file, IniSection s, bool all)
        {
            var area = GetArea();
            if (!IsWheelLayout())
            {
                var size = GetTileSize(file, area);
                // a tile of more cells (Size=): its own proportions (gaps left out)
                var span = Regex.Match(s != null && !all ? Core.GetKey(s, "Size") : "", @"^\s*(\d+)\s*[xX*]\s*(\d+)\s*$");
                if (span.Success)
                    size = new[] { size[0] * Math.Max(1, int.Parse(span.Groups[1].Value)), size[1] * Math.Max(1, int.Parse(span.Groups[2].Value)) };
                return new[] { size[0], size[1], GetLogoBox(file) };
            }
            if (placeBack)
            {
                // the backdrop (Place on): the area under the top row, the logo
                // WheelBackdropLogoSize percent of its height (M.backdropLogo)
                double pct = 30, p;
                if (double.TryParse(V("WheelBackdropLogoSize").Trim(), NumberStyles.Float, Inv, out p)) pct = Math.Min(80, Math.Max(5, p));
                return new[] { area[0], area[1], Math.Max(8, area[1] * pct / 100) };
            }
            double ts = 25, q;
            if (double.TryParse(V("WheelTileSize").Trim(), NumberStyles.Float, Inv, out q)) ts = Math.Min(80, Math.Max(3, q));
            double sz = Math.Max(16, Math.Min(Math.Floor(ts * Math.Min(screenPx[0], screenPx[1]) / 100), Math.Floor(Math.Min(area[0], area[1]))));
            return new[] { sz, sz, Math.Floor(sz * 0.7) };
        }

        // How the preview of the tile editor works, and what it shows (GetPlaceShape)
        string PlaceHowText()
        {
            string shape = !IsWheelLayout()
                ? "The preview has the proportions of this category's tiles on this screen."
                : placeBack
                    ? "The preview is the wheel's backdrop under the top row: the selected tile's logo and lines go there, at their own place and size (Place on: Its thumbnail places them on the thumbnail). The backdrop is not framed: its image fills it from the centre."
                    : "The preview is a thumbnail of the wheel: a square, whatever its size in the grid.";
            return "Drag the background to frame it, the logo or the play time line to move them; the wheel zooms the background or resizes the logo under the mouse. With the gamepad: A on the preview. " +
                shape + " A tile follows All tiles until you move something on it (Own); its reset gives it back the placement of All tiles.";
        }

        // A stacked row of the editor that applies only with the grid (Size=, NX,
        // NY, IconSize): the reason under its help, shown in the wheel
        // (docs/OptionsUI.md, "What does not apply")
        TextBlock AddGridOnlyReason(Grid row)
        {
            var help = FormHelp(row);
            row.Children.Remove(help);
            var why = NewHelp(WhenReason("ScrollMode=Grid", null), ResBrush("AccentBrush"));
            why.Margin = T(0, Gap.Help, 0, 0);
            var both = NewPanel();
            AddTo(both, help);
            AddTo(both, why);
            Grid.SetRow(both, 1);
            row.Children.Add(both);
            gridOnlyRows.Add(new Tuple<Grid, TextBlock>(row, why));
            return why;
        }

        // The rows of the grid only: disabled in the wheel, with the reason
        void UpdateGridOnlyRows()
        {
            bool on = !IsWheelLayout();
            foreach (var r in gridOnlyRows)
            {
                var label = (TextBlock)r.Item1.Children[0];
                if (on) label.ClearValue(TextBlock.ForegroundProperty);
                else label.Foreground = ResBrush("DimBrush");
                foreach (UIElement c in r.Item1.Children)
                    if (Grid.GetRow(c) == 2) c.IsEnabled = on;
                r.Item2.Visibility = on ? Visibility.Collapsed : Visibility.Visible;
            }
        }

        // Size in pixels of a tile of category 'file' in the grid (only its proportions count)
        double[] GetTileSize(string file, double[] area)
        {
            var c = Core.GetCategorySection(GetModel(file));
            var n = new Dictionary<string, int>();
            foreach (var k in new[] { "NX", "NY" })
            {
                int v;
                if (!int.TryParse(Core.GetKey(c, k), out v) || v < 1) int.TryParse(V(k), out v);
                n[k] = Math.Max(1, v);
            }
            return new[]
            {
                Math.Max(1, Math.Floor((area[0] - (n["NX"] - 1) * area[2]) / n["NX"])),
                Math.Max(1, Math.Floor((area[1] - (n["NY"] - 1) * area[2]) / n["NY"])),
            };
        }

        static bool ParsePair(string text, out double x, out double y)
        {
            x = y = 0;
            var m = Regex.Match(text ?? "", @"^\s*([\d.]+)\s*,\s*([\d.]+)\s*$");
            return m.Success && double.TryParse(m.Groups[1].Value, NumberStyles.Float, Inv, out x) && double.TryParse(m.Groups[2].Value, NumberStyles.Float, Inv, out y);
        }

        // --- Placement keys of the category ----------------------------------------------
        // BgFocus, BgZoom, LogoPos, LogoScale and InfoPos in [Category] are the placement of the
        // tiles without their own, as in Raintile.lua: one setting moves them all.
        // A tile keeps a key only when it differs from the category's.

        // Value of a placement key for a tile: its own, else the category's
        string GetPlaceKey(IniSection tile, string key)
        {
            string v = tile != null ? Core.GetKey(tile, key).Trim() : "";
            if (v != "" || currentFile == null) return v;
            return Core.GetKey(Core.GetCategorySection(GetModel(currentFile)), key).Trim();
        }

        // As saved: a point in % (fractions given) and a factor
        static string FormatPair(double x, double y) { return Math.Round(x * 100, 1).ToString("0.#", Inv) + "," + Math.Round(y * 100, 1).ToString("0.#", Inv); }
        static string FormatFactor(double z) { return Math.Round(z, 2).ToString("0.##", Inv); }

        // Point of a placement key when nobody sets it: the centre, the top left for
        // the play time line (InfoPos, BackInfoPos)
        static string DefaultPos(string key) { return key.EndsWith("InfoPos") ? "0,0" : "50,50"; }

        // The place being edited: in the wheel with the logo or the lines on the
        // backdrop, the backdrop (Place on), with its own keys; otherwise the tile
        // (the grid's, or the wheel's thumbnail)
        bool placeBack;
        string LogoPosKey { get { return placeBack ? "BackLogoPos" : "LogoPos"; } }
        string LogoScaleKey { get { return placeBack ? "BackLogoScale" : "LogoScale"; } }
        string InfoPosKey { get { return placeBack ? "BackInfoPos" : "InfoPos"; } }

        // The wheel's backdrop shows the selected tile's logo, its lines (WheelLogoOn,
        // WheelInfoOn = Background, with WheelBackdrop: M.readWheel)
        bool BackdropOn() { return IsWheelLayout() && V("WheelBackdrop") != "0"; }
        bool LogoOnBack() { return BackdropOn() && V("WheelLogoOn").Equals("background", StringComparison.OrdinalIgnoreCase); }
        bool InfoOnBack() { return BackdropOn() && V("WheelInfoOn").Equals("background", StringComparison.OrdinalIgnoreCase); }

        // The category's value of a key, formatted as saved (the default point or "1" when it has none)
        static string GetCategoryPlace(CategoryModel model, string key)
        {
            string raw = Core.GetKey(Core.GetCategorySection(model), key);
            double x, y;
            if (key == "BgFocus" || key.EndsWith("Pos"))
                return ParsePair(raw, out x, out y) ? FormatPair(Math.Min(100.0, x) / 100, Math.Min(100.0, y) / 100) : DefaultPos(key);
            if (!double.TryParse(raw, NumberStyles.Float, Inv, out x)) return "1";
            return FormatFactor(key == "BgZoom" ? Math.Min(4.0, Math.Max(1.0, x)) : Math.Min(3.0, Math.Max(0.25, x)));
        }

        // Writes a placement key of the current tile: removed when it is the category's
        bool SetPlaceKey(IniSection tile, string key, string value)
        {
            if (value == GetCategoryPlace(GetModel(currentFile), key)) value = "";
            if (Core.GetKey(tile, key) == value) return false;
            Core.SetKey(tile, key, value);
            return true;
        }

        // The tile back to the category's placement (its own keys removed)
        void ClearPlaceKeys(IniSection tile, params string[] keys)
        {
            bool changed = false;
            foreach (var k in keys) if (Core.GetKey(tile, k) != "") { Core.SetKey(tile, k, ""); changed = true; }
            if (changed) SetChanged(currentFile);
        }

        // Category name as in the menu
        string GetCategoryName(string file)
        {
            string n = Core.GetKey(Core.GetCategorySection(GetModel(file)), "Name").Trim();
            return n != "" ? n : Path.GetFileNameWithoutExtension(file);
        }

        // What the framing and the logo editor write: the category under All tiles,
        // else the selected tile (null: nothing to edit)
        IniSection GetPlaceTarget()
        {
            if (IsAllSelected()) return currentFile != null ? Core.GetCategorySection(GetModel(currentFile)) : null;
            return GetCurrentTile();
        }

        // Writes a point and a factor (BgFocus/BgZoom or LogoPos/LogoScale; InfoPos has
        // no factor: sizeKey null): under All tiles to the category (the default point
        // at 1 = no key), on a tile only where it differs from the category
        void SavePlace(string posKey, string sizeKey, string pos, string size)
        {
            if (IsAllSelected())
            {
                var c = GetPlaceTarget();
                if (c == null) return;
                string p = pos == DefaultPos(posKey) ? "" : pos, z = size == "1" ? "" : size;
                if (Core.GetKey(c, posKey) == p && (sizeKey == null || Core.GetKey(c, sizeKey) == z)) return;
                Core.SetKey(c, posKey, p);
                if (sizeKey != null) Core.SetKey(c, sizeKey, z);
                SetChanged(currentFile);
                AfterCategoryPlace();
                return;
            }
            var t = GetCurrentTile();
            if (t == null) return;
            bool a = SetPlaceKey(t, posKey, pos);
            bool b = sizeKey != null && SetPlaceKey(t, sizeKey, size);
            if (!a && !b) return;
            SetChanged(currentFile);
            UpdatePlaceState();
            UpdateTileDots();
        }

        // The category's placement changed: the dots, the chips and the summary
        void AfterCategoryPlace()
        {
            UpdateTileDots();
            UpdatePlaceState();
            UpdatePlacementHint();
        }

        // Chip and reset (x) of the framing and logo rows
        void UpdatePlaceState()
        {
            if (frameChip == null) return;
            bool all = IsAllSelected();
            var t = GetCurrentTile();
            var c = currentFile != null ? Core.GetCategorySection(GetModel(currentFile)) : null;
            Func<IniSection, string, string, bool> has = (s, a, b) => s != null && (Core.GetKey(s, a) != "" || Core.GetKey(s, b) != "");
            bool frameOwn = has(t, "BgFocus", "BgZoom"), logoOwn = has(t, LogoPosKey, LogoScaleKey);
            SetChip(frameChip, all ? null : (bool?)frameOwn);
            SetChip(logoChip, all ? null : (bool?)logoOwn);
            // a reset that would change nothing is hidden (docs/OptionsUI.md, 2)
            SetActionVisible(btnFrameReset, all ? has(c, "BgFocus", "BgZoom") : frameOwn);
            SetActionVisible(btnLogoReset, all ? has(c, LogoPosKey, LogoScaleKey) : logoOwn);
            btnFrameReset.ToolTip = all ? "Back to the centre, at zoom 1" : "Back to the framing of All tiles";
            btnLogoReset.ToolTip = all ? "Back to the centre, at the normal size" : "Back to the logo placement of All tiles";
            bool infoOwn = t != null && Core.GetKey(t, InfoPosKey) != "";
            SetChip(infoChip, all ? null : (bool?)infoOwn);
            SetActionVisible(btnInfoReset, all ? c != null && Core.GetKey(c, InfoPosKey) != "" : infoOwn);
            btnInfoReset.ToolTip = all ? "Back to the top left" : "Back to the play time placement of All tiles";
        }

        // A placement row of the tile editor that does not apply (as SetRowApplies):
        // its controls disabled, its name dimmed, the reason shown
        void SetPlaceApplies(Panel block, bool on, TextBlock why)
        {
            var name = (TextBlock)((Grid)block.Children[0]).Children[0];
            if (on) name.ClearValue(TextBlock.ForegroundProperty);
            else name.Foreground = ResBrush("DimBrush");
            foreach (UIElement c in block.Children) if (c != block.Children[0] && c != why) c.IsEnabled = on;
            why.Visibility = on ? Visibility.Collapsed : Visibility.Visible;
        }

        // own: true = Own, false = From All tiles, null = hidden (All tiles itself)
        void SetChip(Border chip, bool? own)
        {
            chip.Visibility = own == null ? Visibility.Collapsed : Visibility.Visible;
            if (own == null) return;
            var text = (TextBlock)chip.Child;
            text.Text = own.Value ? "Own" : "From All tiles";
            text.Foreground = own.Value ? ResBrush("AccentBrush") : ResBrush("DimBrush");
            chip.Background = own.Value ? ResBrush("AccentSoftBrush") : ResBrush("FieldBg");
        }

        Border NewChip()
        {
            var t = NewText("", Fs.Badge);
            return new Border { CornerRadius = new CornerRadius(9), Padding = Gap.Chip, Margin = T(Gap.Control, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, Child = t };
        }

        // Reset of a whole category: the default place ('back'), for the category and every tile
        void ResetCategoryPlace(string file, string what, string[] keys, string back = "the centre, at the normal size")
        {
            var model = GetModel(file);
            var tiles = Core.GetTiles(model);
            var r = ShowDialog("Reset every tile", "Reset the " + what + " of all " + tiles.Count + " tiles of " + GetCategoryName(file) +
                "? They go back to " + back + ".", new[] { "Reset", "Cancel" }, null, true);
            if (r.Button != "Reset") return;
            foreach (var s in new[] { Core.GetCategorySection(model) }.Concat(tiles)) foreach (var k in keys) Core.SetKey(s, k, "");
            SetChanged(file);
            AfterCategoryPlace();
            UpdateTilePreview();
        }

        // Summary under All tiles: the category's placement and the tiles with their own
        void UpdatePlacementHint()
        {
            string file = currentFile;
            if (placementHint == null) return;
            placementRow.Visibility = file != null ? Visibility.Visible : Visibility.Collapsed;
            if (autoArtRow != null)
            {
                autoArtRow.Visibility = placementRow.Visibility;
                sortRow.Visibility = placementRow.Visibility;
                UpdateSortRow();
                // a run of another category is still going: its bar and text stay there
                if (!autoArtBusy) { autoArtStatus.Visibility = Visibility.Collapsed; autoArtTrack.Visibility = Visibility.Collapsed; }
            }
            if (file == null) { SetFormHelp(placementHint, ""); return; }
            var model = GetModel(file);
            var tiles = Core.GetTiles(model);
            // size null: a point only (InfoPos)
            Func<string, string, string> describe = (pos, size) =>
            {
                string p = GetCategoryPlace(model, pos), z = size != null ? GetCategoryPlace(model, size) : "1";
                string text = (p == "50,50" ? "centre" : p == "0,0" ? "top left" : p + "%") + (z == "1" ? "" : ", " + z + Times);
                int own = tiles.Count(t => Core.GetKey(t, pos) != "" || (size != null && Core.GetKey(t, size) != ""));
                return text + (own > 0 ? " (" + own + (own == 1 ? " tile has its own)" : " tiles have their own)") : "");
            };
            SetFormHelp(placementHint, "Puts every tile back at the default place (the centre, the top left for the play time), the ones with their own included" +
                (placeBack ? ", on the backdrop (Place on)" : "") + ". Now: logos " +
                describe(LogoPosKey, LogoScaleKey) + (placeBack ? "" : "; framing " + describe("BgFocus", "BgZoom")) + "; play time " + describe(InfoPosKey, null) + ".");
        }

        void ReadFraming(IniSection section)
        {
            bgFrame.FX = 0.5; bgFrame.FY = 0.5; bgFrame.Zoom = 1.0;
            if (section == null) return;
            double x, y, z;
            // the backdrop is not framed: the image fills it from its centre
            if (placeBack) return;
            if (ParsePair(GetPlaceKey(section, "BgFocus"), out x, out y)) { bgFrame.FX = Math.Min(100.0, x) / 100; bgFrame.FY = Math.Min(100.0, y) / 100; }
            if (double.TryParse(GetPlaceKey(section, "BgZoom"), NumberStyles.Float, Inv, out z)) bgFrame.Zoom = Math.Min(4.0, Math.Max(1.0, z));
        }

        // Part of the image shown, in image pixels; S = preview pixels per image pixel
        struct FrameWindow { public double X, Y, W, H, S, IW, IH; }

        FrameWindow GetFrameWindow()
        {
            return FrameWindowOf(bgFrame.Bitmap.PixelWidth, bgFrame.Bitmap.PixelHeight, preview.Width, preview.Height, bgFrame.FX, bgFrame.FY, bgFrame.Zoom);
        }

        // The part of an iw x ih image a pw x ph tile shows, framed at focus fx, fy
        // (0-1) and zoom (BgFocus, BgZoom): also the Preview window's thumbnails
        static FrameWindow FrameWindowOf(double iw, double ih, double pw, double ph, double fx, double fy, double zoom)
        {
            double s = Math.Max(pw / iw, ph / ih) * zoom;
            double w = Math.Min(iw, pw / s), h = Math.Min(ih, ph / s);
            return new FrameWindow
            {
                X = Math.Min(iw - w, Math.Max(0.0, fx * iw - w / 2)),
                Y = Math.Min(ih - h, Math.Max(0.0, fy * ih - h / 2)),
                W = w, H = h, S = s, IW = iw, IH = ih,
            };
        }

        // The focus goes back to the centre of what is shown
        void LimitFocus()
        {
            var v = GetFrameWindow();
            bgFrame.FX = (v.X + v.W / 2) / v.IW;
            bgFrame.FY = (v.Y + v.H / 2) / v.IH;
        }

        void UpdateFraming()
        {
            // as large as the preview column allows (it follows the window). Taken
            // from the scroller, whose width the scroll bar does not change, less
            // the room kept for the bar, the card's padding and its border: the
            // inner column narrows while the bar shows, and a preview following it
            // got shorter, hid the bar, grew and showed it again, over and over.
            double col = previewScroll != null ? previewScroll.ActualWidth - Gap.ScrollBar - 2 * Gap.CardPadding - 2 : 0;
            double maxW = col > 0 ? Math.Min(640.0, col) : 384;
            double k = Math.Min(maxW / bgFrame.TW, 440 / bgFrame.TH);
            preview.Width = Math.Max(40.0, Math.Round(bgFrame.TW * k));
            preview.Height = Math.Max(40.0, Math.Round(bgFrame.TH * k));
            previewBg.Source = bgFrame.Bitmap;
            bool has = bgFrame.Bitmap != null;
            frameRow.IsEnabled = has && !placeBack;   // (the backdrop is not framed)
            preview.Cursor = has || previewLogo.Source != null || previewInfo.Visibility == Visibility.Visible ? Cursors.SizeAll : null;
            zoomField.Show(bgFrame.Zoom.ToString("0.00", Inv), bgFrame.Zoom);
            if (!has) return;
            var v = GetFrameWindow();
            previewBg.Width = v.IW * v.S;
            previewBg.Height = v.IH * v.S;
            Canvas.SetLeft(previewBg, -v.X * v.S);
            Canvas.SetTop(previewBg, -v.Y * v.S);
        }

        // Writes BgFocus/BgZoom; the category's framing (the centre at zoom 1 by
        // default) removes them
        void SaveFraming()
        {
            SavePlace("BgFocus", "BgZoom", FormatPair(bgFrame.FX, bgFrame.FY), FormatFactor(bgFrame.Zoom));
        }

        // New zoom; 'anchor' (a point of the preview) keeps showing the same part of
        // the image, as when zooming with the wheel under the mouse. save: false while
        // the pad places it (written when it is done, PadPlace.cs)
        void SetFrameZoom(double zoom, Point? anchor = null, bool save = true)
        {
            zoom = Math.Round(Math.Min(4.0, Math.Max(1.0, zoom)), 2);
            if (anchor != null)
            {
                var a = anchor.Value;
                var v = GetFrameWindow();
                double ix = v.X + a.X / v.S, iy = v.Y + a.Y / v.S;
                bgFrame.Zoom = zoom;
                v = GetFrameWindow();
                bgFrame.FX = (ix - a.X / v.S + v.W / 2) / v.IW;
                bgFrame.FY = (iy - a.Y / v.S + v.H / 2) / v.IH;
            }
            else bgFrame.Zoom = zoom;
            LimitFocus();
            UpdateFraming();
            if (save) SaveFraming();
        }

        // A new or removed background: the old framing no longer applies
        void ResetFraming(IniSection section)
        {
            Core.SetKey(section, "BgFocus", "");
            Core.SetKey(section, "BgZoom", "");
            bgFrame.Path = null;
        }

        // --- Placement of the logo (LogoPos, LogoScale) -----------------------------------
        // Same maths as logoCentre in Raintile.lua: what is visible of the logo
        // stays inside the tile.

        void ReadLogoPlace(IniSection section)
        {
            logoPlace.X = 0.5; logoPlace.Y = 0.5; logoPlace.Scale = 1.0;
            if (section == null) return;
            double x, y, z;
            if (ParsePair(GetPlaceKey(section, LogoPosKey), out x, out y)) { logoPlace.X = Math.Min(100.0, x) / 100; logoPlace.Y = Math.Min(100.0, y) / 100; }
            if (double.TryParse(GetPlaceKey(section, LogoScaleKey), NumberStyles.Float, Inv, out z)) logoPlace.Scale = Math.Min(3.0, Math.Max(0.25, z));
        }

        // Logo size of category 'file' in pixels (IconSize: pixels or % of the
        // screen height; empty = the default from Settings)
        double GetLogoBox(string file)
        {
            string raw = Core.GetKey(Core.GetCategorySection(GetModel(file)), "IconSize");
            if (raw == "") raw = V("IconSize");
            double n;
            var m = Regex.Match(raw, @"^\s*([\d.]+)\s*%\s*$");
            if (m.Success && double.TryParse(m.Groups[1].Value, NumberStyles.Float, Inv, out n)) return Math.Max(1.0, n * screenPx[1] / 100);
            if (double.TryParse(raw.Trim(), NumberStyles.Float, Inv, out n) && n > 0) return n;
            return 96.0;
        }

        // The logo in the preview: box side S and centre CX, CY, in preview pixels;
        // VW, VH = its visible part (the image fits in the square box)
        struct LogoRect { public double S, VW, VH, CX, CY; }

        LogoRect GetLogoRect()
        {
            double pw = preview.Width, ph = preview.Height;
            double s = logoPlace.Box * logoPlace.Scale * pw / bgFrame.TW;
            double vw = s, vh = s;
            var b = previewLogo.Source as BitmapSource;
            if (b != null && b.PixelHeight > 0)
            {
                double r = (double)b.PixelWidth / b.PixelHeight;
                if (r >= 1) vh = s / r; else vw = s * r;
            }
            Func<double, double, double, double> place = (p, n, total) => n >= total ? total / 2 : Math.Min(total - n / 2, Math.Max(n / 2, p * total));
            return new LogoRect { S = s, VW = vw, VH = vh, CX = place(logoPlace.X, vw, pw), CY = place(logoPlace.Y, vh, ph) };
        }

        void LimitLogoPos()
        {
            var r = GetLogoRect();
            logoPlace.X = r.CX / preview.Width;
            logoPlace.Y = r.CY / preview.Height;
        }

        // Point of the preview on the logo (a little margin for small logos)
        bool TestOnLogo(Point pt)
        {
            if (previewLogo.Source == null || previewLogo.Visibility != Visibility.Visible) return false;
            var r = GetLogoRect();
            return Math.Abs(pt.X - r.CX) <= r.VW / 2 + 6 && Math.Abs(pt.Y - r.CY) <= r.VH / 2 + 6;
        }

        void UpdateLogoPlace()
        {
            bool has = previewLogo.Source != null && previewLogo.Visibility == Visibility.Visible;
            logoRow.IsEnabled = has;
            logoField.Show(logoPlace.Scale.ToString("0.00", Inv), logoPlace.Scale);
            if (!has) return;
            var r = GetLogoRect();
            previewLogo.Width = r.S;
            previewLogo.Height = r.S;
            Canvas.SetLeft(previewLogo, r.CX - r.S / 2);
            Canvas.SetTop(previewLogo, r.CY - r.S / 2);
        }

        // Writes LogoPos/LogoScale; the category's placement (the centre at scale 1
        // by default) removes them
        void SaveLogoPlace()
        {
            SavePlace(LogoPosKey, LogoScaleKey, FormatPair(logoPlace.X, logoPlace.Y), FormatFactor(logoPlace.Scale));
        }

        // The position is not limited here: a logo pushed into a corner stays there
        void SetLogoScale(double scale, bool save = true)
        {
            logoPlace.Scale = Math.Round(Math.Min(3.0, Math.Max(0.25, scale)), 2);
            UpdateLogoPlace();
            if (save) SaveLogoPlace();
        }

        // --- Placement of the play time line (InfoPos) ------------------------------------
        // Same maths as infoPlacement in Raintile.lua: InfoPos is where the line goes in
        // the room it leaves inside the margins (LabelPad), 0,0 = top left, so it stays
        // in the tile whatever it says. The preview shows a sample line at the size
        // the skin draws it.

        void ReadInfoPlace(IniSection section)
        {
            infoPlace.X = 0; infoPlace.Y = 0;
            if (section == null) return;
            double x, y;
            if (ParsePair(GetPlaceKey(section, InfoPosKey), out x, out y)) { infoPlace.X = Math.Min(100.0, x) / 100; infoPlace.Y = Math.Min(100.0, y) / 100; }
        }

        // Preview pixels per screen pixel, and the margin of the line (LabelPad: pixels
        // or % of the screen height)
        double PreviewScale() { return preview.Width / bgFrame.TW; }

        double GetInfoPad()
        {
            string raw = V("LabelPad");
            double n;
            var m = Regex.Match(raw, @"^\s*([\d.]+)\s*%\s*$");
            if (m.Success && double.TryParse(m.Groups[1].Value, NumberStyles.Float, Inv, out n)) n = n * screenPx[1] / 100;
            else if (!double.TryParse(raw.Trim(), NumberStyles.Float, Inv, out n) || n < 0) n = 14;
            return n * PreviewScale();
        }

        // The line in the preview, in preview pixels (measured by UpdateInfoPlace)
        Rect GetInfoRect()
        {
            double pad = GetInfoPad();
            var d = previewInfo.DesiredSize;
            double fw = Math.Max(0.0, preview.Width - 2 * pad - d.Width), fh = Math.Max(0.0, preview.Height - 2 * pad - d.Height);
            return new Rect(pad + infoPlace.X * fw, pad + infoPlace.Y * fh, d.Width, d.Height);
        }

        bool TestOnInfo(Point pt)
        {
            if (previewInfo.Visibility != Visibility.Visible) return false;
            var r = GetInfoRect();
            r.Inflate(4, 4);
            return r.Contains(pt);
        }

        // The line moved to (left, top) in the preview: back to InfoPos, close to an
        // edge it snaps to it (top right is 100,0, not 99.4,0.3). Not with the pad,
        // whose small steps would never leave the edge (PadPlace.cs)
        void MoveInfo(double left, double top, bool snapToEdge = true)
        {
            double pad = GetInfoPad();
            var d = previewInfo.DesiredSize;
            double fw = preview.Width - 2 * pad - d.Width, fh = preview.Height - 2 * pad - d.Height;
            Func<double, double> snap = v => { v = Math.Min(1.0, Math.Max(0.0, v)); return !snapToEdge ? v : v < 0.03 ? 0 : v > 0.97 ? 1 : v; };
            if (fw > 0) infoPlace.X = snap((left - pad) / fw);
            if (fh > 0) infoPlace.Y = snap((top - pad) / fh);
        }

        void UpdateInfoPlace()
        {
            if (previewInfo == null) return;
            bool top = infoPlace.X == 0 && infoPlace.Y == 0;
            infoPosText.Text = top ? "top left" : FormatPair(infoPlace.X, infoPlace.Y).Replace(",", ", ") + "%";
            if (previewInfo.Visibility != Visibility.Visible) return;
            // as the skin: InfoFontSize in points, Padding=7,3,7,4 (StyleTileInfo)
            double k = PreviewScale(), font;
            if (!double.TryParse(V("InfoFontSize"), NumberStyles.Float, Inv, out font) || font <= 0) font = 10;
            var text = (TextBlock)previewInfo.Child;
            text.FontSize = Math.Max(1.0, font * 96 / 72 * k);
            text.Foreground = NewColorBrush(V("TextColor"));
            if (V("FontFace") != "") text.FontFamily = new FontFamily(V("FontFace"));
            previewInfo.Padding = new Thickness(7 * k, 3 * k, 7 * k, 4 * k);   // ui-exempt: preview of the launcher
            previewInfo.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            var r = GetInfoRect();
            Canvas.SetLeft(previewInfo, r.X);
            Canvas.SetTop(previewInfo, r.Y);
        }

        void SaveInfoPlace()
        {
            SavePlace(InfoPosKey, null, FormatPair(infoPlace.X, infoPlace.Y), null);
        }

        void UpdateTilePreview()
        {
            bool all = IsAllSelected();
            var s = GetShownTile();
            string b = GetCurrentBase();
            // All tiles: the category's values on the images of the tile chosen in
            // Preview on, or on the placeholders
            var sampleItem = all && previewOn != null ? previewOn.SelectedItem as ComboBoxItem : null;
            var sample = sampleItem != null ? sampleItem.Tag as IniSection : null;
            var images = all ? sample : s;
            string bg = images != null ? Core.GetTileImage(b, images, "Background") : null;
            string logo = images != null ? Core.GetTileImage(b, images, "Logo") : null;
            preview.Background = all ? GetTileBrush(b, null, bg, logo) : s != null ? GetTileBrush(b, s, bg, logo) : ResBrush("FieldBg");
            // decoded large enough to stay sharp when zoomed in
            string bgKey = all && sample == null ? "*placeholder" : bg;
            if (bgFrame.Path != bgKey) { bgFrame.Path = bgKey; bgFrame.Bitmap = bgKey == "*placeholder" ? GetPlaceholderBackground() : GetBitmap(bg, 1200); }
            if (bgKey == null) bgFrame.Bitmap = null;
            if (all) s = currentFile != null ? Core.GetCategorySection(GetModel(currentFile)) : null;
            // the wheel with the logo or the lines on the backdrop: Place on chooses
            // the thumbnail or the backdrop, each with its keys
            bool canBack = currentFile != null && (LogoOnBack() || InfoOnBack());
            placeOnRow.Visibility = canBack ? Visibility.Visible : Visibility.Collapsed;
            placeBack = canBack && placeOn.SelectedIndex == 1;
            ReadFraming(s);
            // the tile in the grid, the square of the wheel, or the wheel's background
            var shape = currentFile != null ? GetPlaceShape(currentFile, s, all) : new double[] { 16, 9, 96 };
            bgFrame.TW = shape[0]; bgFrame.TH = shape[1];
            if (placeHow != null) placeHow.Text = PlaceHowText();
            UpdateGridOnlyRows();
            previewLogo.Source = all && sample == null ? GetPlaceholderLogo() : GetBitmap(logo, 384);
            ReadLogoPlace(s);
            logoPlace.Box = shape[2];
            ReadInfoPlace(s);
            // the lines are not drawn with TileInfo and UpdateInfo Never, nor on
            // widgets (the place is the block of both: the update line and the
            // play time): a widget has none (its row hidden), with both Never
            // the row says why it is off
            bool lineKind = currentFile != null && !IsWidget(all ? null : s);
            bool lineOn = !(V("TileInfo").Equals("never", StringComparison.OrdinalIgnoreCase) && V("UpdateInfo").Equals("never", StringComparison.OrdinalIgnoreCase));
            // in the wheel the lines are on the thumbnails or on the backdrop, not both
            bool lineHere = placeBack ? InfoOnBack() : !InfoOnBack();
            infoWhy.Text = !lineOn ? infoNeverWhy : WhenReason(placeBack ? "WheelInfoOn=Background" : "WheelInfoOn=Tile", null);
            previewInfo.Visibility = lineKind && lineOn && lineHere ? Visibility.Visible : Visibility.Collapsed;
            infoRow.Visibility = lineKind ? Visibility.Visible : Visibility.Collapsed;
            SetPlaceApplies(infoRow, lineOn && lineHere, infoWhy);
            // the backdrop: not framed; the logo only when it goes there
            bool logoHere = !placeBack || LogoOnBack();
            previewLogo.Visibility = logoHere ? Visibility.Visible : Visibility.Collapsed;
            SetPlaceApplies(frameRow, !placeBack, frameWhy);
            SetPlaceApplies(logoRow, logoHere, logoWhy);
            if (resetFramingAll != null) resetFramingAll.IsEnabled = !placeBack;
            UpdateFraming();
            UpdateLogoPlace();
            UpdateInfoPlace();
            UpdatePlaceState();
            string label = s != null && !all ? Core.GetKey(s, "Label") : "";
            if (label == "" && s != null && !all && bg == null && logo == null) label = s.Name;
            previewLabel.Text = label;
            // (the label is on the tile, never on the backdrop)
            previewLabel.Visibility = label != "" && V("ShowLabels") != "0" && !placeBack ? Visibility.Visible : Visibility.Collapsed;
            if (all) return;
            SetThumb(bgThumb, bg);
            SetThumb(logoThumb, logo);
            // where the image comes from, shown under the row
            SetFormHelp(bgPath, bg ?? (s != null ? "None. Default: Images\\" + b + "\\background\\" + s.Name + ".jpg" : ""));
            SetFormHelp(logoPath, logo ?? (s != null ? "None. Default: Images\\" + b + "\\logo\\" + s.Name + ".png" : ""));
            SetActionVisible(bgDel, bg != null);
            SetActionVisible(logoDel, logo != null);
            SetSwatch(colorSwatch, s != null ? Core.GetKey(s, "Color") : "");
            SetActionVisible(tileColorClear, s != null && Core.GetKey(s, "Color").Trim() != "");
            var sel = tilesList.SelectedItem as ListBoxItem;
            if (sel != null && ((ListTag)sel.Tag).Section != null) UpdateTileEntry(sel);
        }

        // Who already uses a hot key: the open/close key or another tile (null if free)
        string HotKeyUser(string value, IniSection self)
        {
            if (string.Equals(V("OpenHotKey").Trim(), value, StringComparison.OrdinalIgnoreCase)) return "Open / close the launcher";
            foreach (var f in Core.GetCategoryFiles())
                foreach (var t in Core.GetTiles(GetModel(f.Name)))
                    if (t != self && string.Equals(Core.GetKey(t, "HotKey").Trim(), value, StringComparison.OrdinalIgnoreCase))
                        return "the tile " + t.Name;
            return null;
        }

        // Tags of every tile (as in the window), for the suggestions under the field
        List<string> GetAllTags()
        {
            var tags = new Dictionary<string, string>();
            foreach (var f in Core.GetCategoryFiles())
                foreach (var t in Core.GetTiles(GetModel(f.Name)))
                    foreach (var raw in Core.GetKey(t, "Tags").Split(',', ';'))
                    {
                        string tag = raw.Trim();
                        if (tag != "" && !tags.ContainsKey(tag.ToLowerInvariant())) tags[tag.ToLowerInvariant()] = tag;
                    }
            return tags.Keys.OrderBy(k => k, StringComparer.Ordinal).Select(k => tags[k]).ToList();
        }

        // The tags used elsewhere and not on this tile: a click adds one
        void UpdateTagSuggestions()
        {
            if (tagSuggestions == null) return;
            tagSuggestions.Children.Clear();
            var t = GetCurrentTile();
            if (t == null) return;
            var mine = Core.GetKey(t, "Tags").Split(',', ';').Select(x => x.Trim().ToLowerInvariant()).Where(x => x != "").ToList();
            foreach (var tag in GetAllTags())
            {
                if (mine.Contains(tag.ToLowerInvariant())) continue;
                var b = NewButton("+ " + tag, "LinkButton", "Add this tag");
                b.Margin = T(0, 0, Gap.Group, 0);
                string value = tag;
                b.Click += (s, e) =>
                {
                    var box = tileFields["Tags"];
                    box.Text = box.Text.Trim() != "" ? box.Text.Trim().TrimEnd(',', ';') + ", " + value : value;
                    UpdateTagSuggestions();
                };
                tagSuggestions.Children.Add(b);
            }
        }

        void ShowTile()
        {
            loading = true;
            var s = GetShownTile();
            var sel = TagOf(tilesList.SelectedItem);
            bool imported = sel != null && sel.Imported;
            bool all = sel != null && sel.All;
            tileCard.IsEnabled = s != null && !imported;
            tileCard.Visibility = all ? Visibility.Collapsed : Visibility.Visible;
            allCard.Visibility = all ? Visibility.Visible : Visibility.Collapsed;
            previewOnRow.Visibility = all ? Visibility.Visible : Visibility.Collapsed;
            importedCard.Visibility = imported ? Visibility.Visible : Visibility.Collapsed;
            if (all) ShowAllTiles();
            foreach (var k in new[] { "Command", "Label", "Color", "Tags" }) tileFields[k].Text = s != null ? Core.GetKey(s, k) : "";
            UpdateTagSuggestions();
            ShowPinned(s);
            string hotKey = s != null ? Core.GetKey(s, "HotKey") : "";
            tileKeyButton.Content = Schema.FormatHotKey(hotKey);
            SetActionVisible(tileKeyClear, hotKey.Trim() != "");
            // every tile can be a widget
            widgetRow.Visibility = Visibility.Visible;
            string kind = s != null ? Core.GetKey(s, "Widget").Trim().ToLowerInvariant() : "";
            if (!SelectChoice(widgetKind, kind)) widgetKind.SelectedIndex = 0;
            widgetParam.Text = s != null ? Core.GetKey(s, "Param") : "";
            widgetOption.Text = s != null ? Core.GetKey(s, "WidgetOption") : "";
            UpdateWidgetHint();
            var size = Regex.Match(s != null ? Core.GetKey(s, "Size") : "", @"^\s*(\d+)\s*[xX*]\s*(\d+)\s*$");
            int sc = size.Success ? Math.Max(1, Math.Min(8, int.Parse(size.Groups[1].Value))) : 1;
            int sr = size.Success ? Math.Max(1, Math.Min(8, int.Parse(size.Groups[2].Value))) : 1;
            sizeCols.Show(sc.ToString(), 1);
            sizeRows.Show(sr.ToString(), 1);
            ShowTileOpacity(s);
            tileFields["Name"].Text = s != null ? s.Name : "";
            tileNote.Text = sel == null ? "No tiles yet: add one with the + button." : "";
            tileNote.Visibility = tileNote.Text != "" ? Visibility.Visible : Visibility.Collapsed;
            UpdateTileButtons();
            // a widget: no background framing or logo to place
            bool dash = !all && IsWidget(s);
            frameRow.Visibility = logoRow.Visibility = dash ? Visibility.Collapsed : Visibility.Visible;
            loading = false;
            UpdateTilePreview();
        }

        // Opacity of a tile; empty = the one of All tiles, where the slider rests
        void ShowTileOpacity(IniSection s)
        {
            string own = s != null ? Core.GetKey(s, "Opacity").Trim() : "";
            string inherited = currentFile != null ? Core.GetKey(Core.GetCategorySection(GetModel(currentFile)), "TileOpacity").Trim() : "";
            double inh;
            if (!Core.TryNumber(inherited, out inh)) inh = 100;
            tileOpacity.Show(own, inh);
            SetActionVisible(tileOpacityReset, own != "");
            SetFormHelp(tileOpacityHint, "Opacity of the colour and the image of the tile: 0 leaves only the logo, the label or the widget (a skin over the tile, without a box behind it). Empty = the one of All tiles (" +
                Core.FormatNumber(inh, 1) + "%).");
        }

        // The buttons of the tiles strip that can act on the selection (docs/OptionsUI.md, 2)
        void UpdateTileButtons()
        {
            if (tileDel == null) return;
            var t = GetCurrentTile();
            var tiles = currentFile != null ? Core.GetTiles(GetModel(currentFile)) : new List<IniSection>();
            int i = t != null ? tiles.IndexOf(t) : -1;
            // a category that keeps an order moves only its pinned tiles
            bool movable = t != null && (GetKeptSort(currentFile) == null || IsPinned(t));
            tileNew.IsEnabled = currentFile != null;
            tileDel.IsEnabled = t != null;
            tileUp.IsEnabled = movable && i > 0;
            tileDown.IsEnabled = movable && i >= 0 && i < tiles.Count - 1;
        }

        // All tiles: the settings of the category (its [Category] section)
        void ShowAllTiles()
        {
            var c = currentFile != null ? Core.GetCategorySection(GetModel(currentFile)) : null;
            Func<string, string> key = k => c != null ? Core.GetKey(c, k).Trim() : "";
            double nx, ny;
            if (!Core.TryNumber(V("NX"), out nx)) nx = 1;
            if (!Core.TryNumber(V("NY"), out ny)) ny = 1;
            // empty = the default of Layout, where the slider rests
            gridCols.Show(key("NX"), nx);
            gridRows.Show(key("NY"), ny);
            catLogoSize.Show(key("IconSize"));
            SetActionVisible(gridColsReset, key("NX") != "");
            SetActionVisible(gridRowsReset, key("NY") != "");
            SetActionVisible(catLogoSizeReset, key("IconSize") != "");
            SetFormHelp(gridColsHint, "Empty = the default (" + V("NX") + ", Tiles > Grid).");
            SetFormHelp(gridRowsHint, "Empty = the default (" + V("NY") + ", Tiles > Grid).");
            SetFormHelp(sizeHint, "Pixels or % of the screen height. Empty = the default (" + V("IconSize") + ", Tiles > Grid).");
            catTileColor.Text = key("TileColor");
            SetSwatch(catColorSwatch, catTileColor.Text);
            SetActionVisible(catColorClear, catTileColor.Text.Trim() != "");
            catOpacity.Show(key("TileOpacity"), 100);
            SetActionVisible(catOpacityReset, key("TileOpacity") != "");
            int count = currentFile != null ? Core.GetTiles(GetModel(currentFile)).Count : 0;
            allNote.Text = count == 0 ? "No tiles yet: add one with the + button." : "";
            allNote.Visibility = count == 0 ? Visibility.Visible : Visibility.Collapsed;
            // Preview on: the placeholders or a tile with images
            var keep = previewOn.SelectedItem as ComboBoxItem;
            var keepTile = keep != null ? keep.Tag as IniSection : null;
            previewOn.Items.Clear();
            previewOn.Items.Add(new ComboBoxItem { Content = "Placeholder images", Tag = null });
            string b = GetCurrentBase();
            if (currentFile != null)
                foreach (var t in Core.GetTiles(GetModel(currentFile)))
                    if (Core.GetTileImage(b, t, "Background") != null || Core.GetTileImage(b, t, "Logo") != null)
                        previewOn.Items.Add(new ComboBoxItem { Content = t.Name, Tag = t });
            previewOn.SelectedItem = previewOn.Items.OfType<ComboBoxItem>().FirstOrDefault(i => i.Tag == keepTile) ?? previewOn.Items[0];
            UpdatePlacementHint();
        }

        // Every field of a form is as high as a button (Choose...), so all the rows
        // have the same height: text boxes, lists, buttons, swatches, thumbnails
        const double FieldHeight = 30;

        void FitFieldHeight(DependencyObject d)
        {
            var tb = d as TextBox;
            if (tb != null)
            {
                // the style's 5 px above and below would cut the text at this height;
                // centred anyway, in the size of the labels
                tb.Height = FieldHeight;
                tb.Padding = T(Gap.Control, 0);
                tb.FontSize = 13;   // ui-exempt: the text size of the fields
                return;
            }
            if (d is ComboBox) { ((ComboBox)d).Height = FieldHeight; return; }
            var b = d as Button;
            if (b != null)
            {
                if (b.Style == ResStyle("IconButton")) return;   // the small x keeps its size
                b.Height = FieldHeight;
                if (b.Style == ResStyle("Swatch")) b.Width = FieldHeight;
                return;
            }
            var p = d as Panel;
            if (p != null) foreach (UIElement c in p.Children) FitFieldHeight(c);
        }

        // A stacked row (docs/OptionsUI.md, 4): the label and its help on top, the
        // control below filling the column, then hintBlock (current values, buttons).
        // On the right of the control, always, the action column: its reset or clear
        // button, or nothing, so every control ends at the same edge. The help can
        // change later: SetFormHelp(FormHelp(row), ...).
        Grid NewFormRow(string label, UIElement control, string hint = "", FrameworkElement hintBlock = null, FrameworkElement action = null)
        {
            var g = NewGrid("*", Gap.ActionColumn.ToString(Inv));
            g.Margin = T(0, Gap.StackedRow);
            for (int i = 0; i < 4; i++) g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.Children.Add(NewText(label, Fs.Label, null, false, true));
            var help = NewHelp("");
            help.Margin = T(0, Gap.Help, 0, 0);
            SetFormHelp(help, hint);
            Grid.SetRow(help, 1);
            g.Children.Add(help);
            g.Tag = help;
            // a field with its own width starts at the left edge (stretched, it would be centred)
            var fe = control as FrameworkElement;
            if (fe != null && !double.IsNaN(fe.Width)) fe.HorizontalAlignment = HorizontalAlignment.Left;
            FitFieldHeight(control);
            var holder = new Border { Margin = T(0, Gap.Icon, 0, 0), Child = control };
            Grid.SetRow(holder, 2);
            g.Children.Add(holder);
            if (action != null)
            {
                action.Margin = T(Gap.Icon, Gap.Icon, 0, 0);
                action.VerticalAlignment = VerticalAlignment.Center;
                Grid.SetRow(action, 2);
                SetCol(action, 1);
                g.Children.Add(action);
            }
            if (hintBlock != null)
            {
                hintBlock.Margin = T(0, Gap.Line, 0, 0);
                Grid.SetRow(hintBlock, 3);
                g.Children.Add(hintBlock);
            }
            return g;
        }

        static TextBlock FormHelp(Grid formRow) { return (TextBlock)formRow.Tag; }

        static void SetFormHelp(TextBlock help, string text)
        {
            help.Text = text ?? "";
            help.Visibility = help.Text != "" ? Visibility.Visible : Visibility.Collapsed;
        }

        // A colour swatch shows its field: empty = the field background, as an empty field
        void SetSwatch(Button swatch, string value)
        {
            swatch.Background = (Brush)NewColorBrush(value, true) ?? ResBrush("FieldBg");
        }

        // A field that fills the column between an optional element before it
        // (swatch, thumbnail) and one after it (clear button)
        Grid NewFieldRow(FrameworkElement lead, FrameworkElement field, FrameworkElement tail)
        {
            var g = NewGrid("Auto", "*", "Auto");
            if (lead != null)
            {
                lead.VerticalAlignment = VerticalAlignment.Center;
                g.Children.Add(lead);
                field.Margin = T(Gap.Control, 0, 0, 0);
            }
            field.VerticalAlignment = VerticalAlignment.Center;
            SetCol(field, 1);
            g.Children.Add(field);
            if (tail != null)
            {
                tail.VerticalAlignment = VerticalAlignment.Center;
                SetCol(tail, 2);
                g.Children.Add(tail);
            }
            return g;
        }

        Border NewListColumn(string title, UIElement list, params UIElement[] buttons)
        {
            var b = new Border { Style = ResStyle("Card"), Padding = T(Gap.Control, Gap.Line, Gap.Control, Gap.Control) };
            var dp = new DockPanel();
            b.Child = dp;
            var head = NewGrid("*", "Auto");
            head.Margin = T(Gap.Icon, Gap.Control, 0, Gap.Icon);
            DockPanel.SetDock(head, Dock.Top);
            var h = NewSectionTitle(title);
            h.VerticalAlignment = VerticalAlignment.Center;
            head.Children.Add(h);
            var bar = NewPanel(Orientation.Horizontal);
            foreach (var btn in buttons) AddTo(bar, btn);
            SetCol(bar, 1);
            head.Children.Add(bar);
            dp.Children.Add(head);
            dp.Children.Add(list);
            return b;
        }

        // Drag and drop in a list: 'move(from, to)' moves the item at index 'from'
        // to index 'to' (both in the list as it is before the move). A thin line
        // shows where it goes. 'canDrag' leaves some items out (imported tiles).
        void EnableDragReorder(ListBox list, Func<ListBoxItem, bool> canDrag, Action<int, int> move, bool horizontal = false)
        {
            list.AllowDrop = true;
            Point start = new Point();
            ListBoxItem pressed = null;
            list.PreviewMouseLeftButtonDown += (s, e) =>
            {
                start = e.GetPosition(list);
                pressed = ItemAt(list, e.OriginalSource as DependencyObject);
            };
            list.PreviewMouseMove += (s, e) =>
            {
                if (e.LeftButton != MouseButtonState.Pressed || pressed == null || !canDrag(pressed)) return;
                var p = e.GetPosition(list);
                if (Math.Abs(p.X - start.X) < SystemParameters.MinimumHorizontalDragDistance
                    && Math.Abs(p.Y - start.Y) < SystemParameters.MinimumVerticalDragDistance) return;
                var item = pressed;
                pressed = null;
                DragDrop.DoDragDrop(list, new DataObject("RaintileItem", item), DragDropEffects.Move);
                ClearDropMark(list);
            };
            list.DragOver += (s, e) =>
            {
                e.Effects = e.Data.GetDataPresent("RaintileItem") ? DragDropEffects.Move : DragDropEffects.None;
                e.Handled = true;
                int to = DropIndex(list, e, horizontal);
                ClearDropMark(list);
                if (to < list.Items.Count) ((ListBoxItem)list.Items[to]).BorderThickness = horizontal ? T(2, 0, 0, 0) : T(0, 2, 0, 0);
                else if (list.Items.Count > 0) ((ListBoxItem)list.Items[list.Items.Count - 1]).BorderThickness = horizontal ? T(0, 0, 2, 0) : T(0, 0, 0, 2);
            };
            list.DragLeave += (s, e) => ClearDropMark(list);
            list.Drop += (s, e) =>
            {
                ClearDropMark(list);
                var item = e.Data.GetData("RaintileItem") as ListBoxItem;
                if (item == null) return;
                int from = list.Items.IndexOf(item), to = DropIndex(list, e, horizontal);
                if (from < 0) return;
                if (to > from) to--;   // the item leaves its place first
                if (to != from) move(from, to);
            };
        }

        // A tile of the strip dropped on another category of the menu moves there
        // with its images (both category files are saved at once). Not for imported
        // tiles.
        void EnableTileDropOnNav()
        {
            ListBoxItem marked = null;
            Action unmark = () => { if (marked != null) marked.BorderThickness = T(0); marked = null; };
            Func<DragEventArgs, string> target = e =>
            {
                var tile = e.Data.GetData("RaintileItem") as ListBoxItem;
                if (tile == null || !tilesList.Items.Contains(tile) || currentFile == null) return null;
                var over = ItemAt(nav, e.OriginalSource as DependencyObject);
                var tag = over != null ? over.Tag as NavTag : null;
                if (tag == null || tag.Type != "category" || tag.File == currentFile) return null;
                return tag.File;
            };
            nav.AllowDrop = true;
            nav.DragOver += (s, e) =>
            {
                unmark();
                e.Handled = true;
                if (target(e) == null) { e.Effects = DragDropEffects.None; return; }
                e.Effects = DragDropEffects.Move;
                marked = ItemAt(nav, e.OriginalSource as DependencyObject);
                marked.BorderBrush = ResBrush("AccentBrush");
                marked.BorderThickness = T(1);
            };
            nav.DragLeave += (s, e) => unmark();
            nav.Drop += (s, e) =>
            {
                unmark();
                string to = target(e);
                if (to == null) return;
                var tile = (ListBoxItem)e.Data.GetData("RaintileItem");
                int index = tilesList.Items.IndexOf(tile);
                string err = MoveTileToCategory(currentFile, ((ListTag)tile.Tag).Section, to);
                if (err != null) { ShowDialog("Move tile", err); return; }
                RefreshTiles(Math.Max(0, index - 2));   // the tile before it (All tiles is entry 0)
            };
        }

        // The scroll viewer inside a control's template (the strip scrolls with the wheel)
        // The room of the vertical scrollbar kept also when there is none, so the
        // content's width never changes with it. The preview follows the width of
        // its column and with it its height: without this, at some window sizes
        // the bar showed (narrower: the preview shorter, everything fits), hid
        // (wider: taller, it no longer fits) and showed again, over and over.
        static void KeepScrollBarRoom(ScrollViewer sv, FrameworkElement content)
        {
            content.Margin = T(content.Margin.Left, content.Margin.Top, Gap.ScrollBar, content.Margin.Bottom);
            sv.ScrollChanged += (s, e) =>
            {
                double right = sv.ComputedVerticalScrollBarVisibility == Visibility.Visible ? 0 : Gap.ScrollBar;
                if (content.Margin.Right != right) content.Margin = T(content.Margin.Left, content.Margin.Top, right, content.Margin.Bottom);
            };
        }

        static ScrollViewer FindScrollViewer(DependencyObject d)
        {
            var sv = d as ScrollViewer;
            if (sv != null) return sv;
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(d); i++)
            {
                sv = FindScrollViewer(VisualTreeHelper.GetChild(d, i));
                if (sv != null) return sv;
            }
            return null;
        }

        static ListBoxItem ItemAt(ListBox list, DependencyObject element)
        {
            return element != null ? ItemsControl.ContainerFromElement(list, element) as ListBoxItem : null;
        }

        // Index the dragged item would take: before the item under the mouse, or
        // after it in its lower (horizontal list: right) half
        static int DropIndex(ListBox list, DragEventArgs e, bool horizontal = false)
        {
            var over = ItemAt(list, e.OriginalSource as DependencyObject);
            if (over == null) return list.Items.Count;
            int i = list.Items.IndexOf(over);
            var p = e.GetPosition(over);
            return (horizontal ? p.X > over.ActualWidth / 2 : p.Y > over.ActualHeight / 2) ? i + 1 : i;
        }

        void ClearDropMark(ListBox list)
        {
            foreach (ListBoxItem it in list.Items)
            {
                it.BorderThickness = T(0);
                it.BorderBrush = ResBrush("AccentBrush");
            }
        }

        // Categories page: the list of categories, to create, reorder and delete them
        UIElement NewCategoryListPage()
        {
            var grid = NewGrid("440", "*");
            grid.Margin = Gap.Page;
            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            SetCol(sv, 1);
            grid.Children.Add(sv);
            var side = NewPanel();
            sv.Content = side;
            // the list with its actions in its header, as the tiles strip
            catNew = NewIconButton(Glyph.Add, "New category");
            catUp = NewIconButton(Glyph.Up, "Move up");
            catDown = NewIconButton(Glyph.Down, "Move down");
            catDel = NewIconButton(Glyph.Delete, "Delete category");
            catOpen = NewButton("Open", "", "Its tiles (also a double click or Enter)");
            catOpen.Margin = T(0, 0, Gap.Control, 0);
            catOpen.VerticalAlignment = VerticalAlignment.Center;
            catsList = new ListBox();
            var listCard = NewListColumn("Categories", catsList, catOpen, catNew, catUp, catDown, catDel);
            listCard.Margin = T(0, 0, Gap.Card, 0);
            grid.Children.Add(listCard);
            var btnNew = catNew; var btnOpen = catOpen; var btnUp = catUp; var btnDown = catDown; var btnDel = catDel;

            // Category card
            catCard = NewCard("Category", "");
            AddTo(side, catCard);
            var f = CardPanel(catCard);
            catFields["Name"] = new TextBox();
            AddTo(f, NewFormRow("Name", catFields["Name"], "Text shown in the menu."));
            // Hidden=1: kept with its tiles, but not in the launcher's menu
            catShown = new CheckBox { Content = "Show in the menu", VerticalAlignment = VerticalAlignment.Center };
            AddTo(f, NewFormRow("In the launcher", catShown, "Off: the category stays in its file with its tiles, but is not in the launcher (and its widgets measure nothing)."));
            catShown.Click += (s, e) =>
            {
                string file = GetListFile();
                if (file == null) return;
                Core.SetKey(Core.GetCategorySection(GetModel(file)), "Hidden", catShown.IsChecked == true ? "" : "1");
                SetChanged(file);
            };
            catIcon = NewThumb(FieldHeight);
            var btnIcon = NewButton("Browse...");
            // x: no icon (its file goes to the Recycle Bin, asked first)
            var btnIconDel = NewClearButton("Clear the icon");
            catIconDel = btnIconDel;
            var iconRow = NewFieldRow(catIcon, btnIcon, null);
            catIconHint = NewHelp("");
            AddTo(f, NewFormRow("Icon", iconRow, "In the menu, left of the name.", catIconHint, btnIconDel));
            var more = NewHelp("Grid, logo size, tile colour and background, framing and logo of all its tiles: open the category (double click) and choose All tiles, the first entry above its tiles.");
            more.Margin = T(0, Gap.Icon, 0, Gap.Text);
            AddTo(f, more);

            catsList.SelectionChanged += (s, e) => ShowCategoryDetails();
            // drag a category to change the order of the menu
            EnableDragReorder(catsList, it => true, (from, to) =>
            {
                var files = catsList.Items.OfType<ListBoxItem>().Select(it => ((ListTag)it.Tag).File).ToList();
                string moved = files[from];
                files.RemoveAt(from);
                files.Insert(to, moved);
                for (int n = 0; n < files.Count; n++)
                {
                    var c = Core.GetCategorySection(GetModel(files[n]));
                    if (Core.GetKey(c, "Order") != (n + 1).ToString()) { Core.SetKey(c, "Order", (n + 1).ToString()); SetChanged(files[n]); }
                }
                RefreshCats(moved);
                BuildNav(navCurrent);
            });
            foreach (var kv in catFields)
            {
                string key = kv.Key;
                var tb = kv.Value;
                tb.TextChanged += (s, e) =>
                {
                    if (loading) return;
                    string file = GetListFile();
                    if (file == null) return;
                    Core.SetKey(Core.GetCategorySection(GetModel(file)), key, tb.Text.Trim());
                    SetChanged(file);
                    if (key == "Name") UpdateNavCategory(file);
                };
            }
            btnIcon.Click += (s, e) =>
            {
                string file = GetListFile();
                if (file == null) return;
                string src = SelectFile(ImageFilter);
                if (src == null) return;
                string dir = Path.Combine(Core.ImagesRoot, GetListBase());
                Directory.CreateDirectory(dir);
                string dest = Path.Combine(dir, "icon" + Path.GetExtension(src).ToLowerInvariant());
                foreach (var old in Directory.GetFiles(dir))
                    if (string.Equals(Path.GetFileNameWithoutExtension(old), "icon", StringComparison.OrdinalIgnoreCase)
                        && !string.Equals(Path.GetFullPath(old), Path.GetFullPath(src), StringComparison.OrdinalIgnoreCase))
                        File.Delete(old);
                if (!string.Equals(Path.GetFullPath(dest), Path.GetFullPath(src), StringComparison.OrdinalIgnoreCase)) File.Copy(src, dest, true);
                Core.SetKey(Core.GetCategorySection(GetModel(file)), "Icon", "");   // the default icon just copied applies
                SetChanged(file);
                string now = Core.GetCategoryIcon(GetListBase(), Core.GetCategorySection(GetModel(file)));
                SetThumb(catIcon, now);
                SetActionVisible(catIconDel, now != null);
                UpdateNavCategory(file);
            };
            btnIconDel.Click += (s, e) =>
            {
                string file = GetListFile();
                if (file == null) return;
                var c = Core.GetCategorySection(GetModel(file));
                string icon = Core.GetCategoryIcon(GetListBase(), c);
                if (icon != null && icon.StartsWith(Core.ImagesRoot, StringComparison.OrdinalIgnoreCase))
                {
                    var r = ShowDialog("Clear icon", "No icon for this category: " + Path.GetFileName(icon) + " goes to the Recycle Bin.", new[] { "Clear", "Cancel" }, null, true);
                    if (r.Button != "Clear") return;
                    RemoveToRecycleBin(icon);
                }
                Core.SetKey(c, "Icon", "");
                SetChanged(file);
                SetThumb(catIcon, null);
                SetActionVisible(catIconDel, false);
                UpdateNavCategory(file);
            };

            Action openSelected = () => { var t = TagOf(catsList.SelectedItem); if (t != null) OpenCategory(t.File); };
            catsList.MouseDoubleClick += (s, e) => openSelected();
            catsList.KeyDown += (s, e) => { if (e.Key == Key.Return) openSelected(); };
            btnOpen.Click += (s, e) => openSelected();

            btnNew.Click += (s, e) =>
            {
                var r = ShowDialog("New category", "Name of the new category (e.g. Emulators):", new[] { "Create", "Cancel" }, "");
                if (r.Button != "Create" || string.IsNullOrEmpty(r.Text)) return;
                string file = Regex.Replace(r.Text, "[^A-Za-z0-9_-]", "");
                if (file == "") { ShowDialog("New category", "Use at least one letter or digit."); return; }
                if (File.Exists(Path.Combine(Core.CategoriesDir, file + ".ini"))) { ShowDialog("New category", "The category '" + file + "' already exists."); return; }
                NewCategoryFile(file, r.Text);
                RefreshCats(file + ".ini");
                BuildNav(navCurrent);
            };
            btnDel.Click += (s, e) =>
            {
                var t = TagOf(catsList.SelectedItem);
                if (t == null) return;
                string file = t.File;
                var r = ShowDialog("Delete category", "Move the category " + file + " to the Recycle Bin? Its images stay in Images.", new[] { "Delete", "Cancel" }, null, true);
                if (r.Button != "Delete") return;
                RemoveToRecycleBin(Path.Combine(Core.CategoriesDir, file));
                models.Remove(file); changedFiles.Remove(file);
                if (currentFile == file) currentFile = null;
                UpdateDirty();
                RefreshCats();
                BuildNav(navCurrent);
            };
            foreach (var pair in new[] { Tuple.Create(btnUp, -1), Tuple.Create(btnDown, 1) })
            {
                int delta = pair.Item2;
                pair.Item1.Click += (s, e) =>
                {
                    int i = catsList.SelectedIndex, j = i + delta;
                    if (i < 0 || j < 0 || j >= catsList.Items.Count) return;
                    var files = catsList.Items.OfType<ListBoxItem>().Select(it => ((ListTag)it.Tag).File).ToList();
                    string tmp = files[i]; files[i] = files[j]; files[j] = tmp;
                    for (int n = 0; n < files.Count; n++)
                    {
                        var c = Core.GetCategorySection(GetModel(files[n]));
                        if (Core.GetKey(c, "Order") != (n + 1).ToString()) { Core.SetKey(c, "Order", (n + 1).ToString()); SetChanged(files[n]); }
                    }
                    RefreshCats(files[j]);
                    BuildNav(navCurrent);
                };
            }
            return grid;
        }

        // Page of one category (the same page for all: ShowCategory fills it). On
        // top the strip of its tiles, All tiles first; below, the preview with the
        // framing and the logo on the left, the settings on the right.
        UIElement NewCategoryPage()
        {
            var grid = new Grid { Margin = Gap.Page };
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(11, GridUnitType.Star), MinWidth = 260 });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10, GridUnitType.Star), MinWidth = 330 });

            // Row 0: the tiles side by side, scrolled with the wheel
            tilesList = new ListBox();
            var ip = new FrameworkElementFactory(typeof(StackPanel));
            ip.SetValue(StackPanel.OrientationProperty, Orientation.Horizontal);
            tilesList.ItemsPanel = new ItemsPanelTemplate(ip);
            ScrollViewer.SetHorizontalScrollBarVisibility(tilesList, ScrollBarVisibility.Auto);
            ScrollViewer.SetVerticalScrollBarVisibility(tilesList, ScrollBarVisibility.Disabled);
            tilesList.PreviewMouseWheel += (s, e) =>
            {
                var scroll = FindScrollViewer(tilesList);
                if (scroll == null) return;
                for (int n = 0; n < 2; n++) { if (e.Delta > 0) scroll.LineLeft(); else scroll.LineRight(); }
                e.Handled = true;
            };
            var btnTileNew = tileNew = NewIconButton(Glyph.Add, "New tile");
            var btnTileDel = tileDel = NewIconButton(Glyph.Delete, "Delete tile");
            var btnTileUp = tileUp = NewIconButton(Glyph.Left, "Move left");
            var btnTileDown = tileDown = NewIconButton(Glyph.Right, "Move right");
            var strip = NewListColumn("Tiles", tilesList, btnTileNew, btnTileUp, btnTileDown, btnTileDel);
            strip.Margin = T(0, 0, 0, Gap.Card);
            Grid.SetColumnSpan(strip, 2);
            grid.Children.Add(strip);

            // Row 1, left: the preview, as the tile looks in the launcher
            var leftScroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = T(0, 0, Gap.Card, 0) };
            Grid.SetRow(leftScroll, 1);
            grid.Children.Add(leftScroll);
            previewCard = new Border { Style = ResStyle("Card"), Padding = T(Gap.CardPadding, Gap.Card, Gap.CardPadding, Gap.Card), VerticalAlignment = VerticalAlignment.Top };
            leftScroll.Content = previewCard;
            KeepScrollBarRoom(leftScroll, previewCard);
            var left = NewPanel();
            previewCard.Child = left;
            previewScroll = leftScroll;
            // the preview follows the width of the column (UpdateFraming)
            leftScroll.SizeChanged +=(s, e) => { if (e.WidthChanged && preview != null) { UpdateFraming(); UpdateLogoPlace(); UpdateInfoPlace(); } };

            // All tiles: the tile whose images show the category's values
            var por = NewPanel(Orientation.Horizontal);
            por.Margin = T(0, 0, 0, Gap.Group);
            var pol = NewText("Preview on", Fs.Label);
            pol.VerticalAlignment = VerticalAlignment.Center;
            pol.Margin = T(0, 0, Gap.Control, 0);
            previewOn = new ComboBox { MinWidth = FieldWidth.M, Height = FieldHeight };
            AddTo(por, pol); AddTo(por, previewOn);
            previewOnRow = por;
            AddTo(left, por);
            previewOn.SelectionChanged += (s, e) => { if (!loading && IsAllSelected()) UpdateTilePreview(); };

            // The wheel with the logo or the lines on the backdrop: placed on the
            // thumbnail (LogoPos, LogoScale, InfoPos) or on the backdrop (BackLogoPos,
            // BackLogoScale, BackInfoPos)
            var pon = NewPanel(Orientation.Horizontal);
            pon.Margin = T(0, 0, 0, Gap.Group);
            var ponl = NewText("Place on", Fs.Label);
            ponl.VerticalAlignment = VerticalAlignment.Center;
            ponl.Margin = T(0, 0, Gap.Control, 0);
            placeOn = new ComboBox { MinWidth = FieldWidth.M, Height = FieldHeight };
            placeOn.Items.Add(new ComboBoxItem { Content = "Its thumbnail" });
            placeOn.Items.Add(new ComboBoxItem { Content = "The backdrop" });
            placeOn.SelectedIndex = 1;
            AddTo(pon, ponl); AddTo(pon, placeOn);
            placeOnRow = pon;
            AddTo(left, pon);
            placeOn.SelectionChanged += (s, e) => { if (!loading) { UpdateTilePreview(); UpdatePlacementHint(); } };

            // the background sits on a canvas, positioned by the framing (sized by UpdateFraming)
            preview = new Border
            {
                Width = 384, Height = 216, CornerRadius = new CornerRadius(8), HorizontalAlignment = HorizontalAlignment.Center,
                ClipToBounds = true,
            };
            var pg = new Grid();
            preview.Child = pg;
            var canvas = new Canvas();
            previewBg = new Image { Stretch = Stretch.Fill };
            canvas.Children.Add(previewBg);
            // the logo on the same canvas, positioned by UpdateLogoPlace
            previewLogo = new Image { Stretch = Stretch.Uniform };
            canvas.Children.Add(previewLogo);
            // the play time line over the logo, as in the skin: a sample text, placed
            // by UpdateInfoPlace
            previewInfo = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(150, 0, 0, 0)), IsHitTestVisible = false,
                Child = new TextBlock { Text = "24 h played - yesterday", FontWeight = FontWeights.SemiBold },
            };
            canvas.Children.Add(previewInfo);
            // what the pad is moving (PadPlace.cs)
            canvas.Children.Add(NewPlaceMark());
            previewLabel =NewText("", 14, NewColorBrush(V("TextColor")));   // ui-exempt: preview of the launcher
            previewLabel.HorizontalAlignment = HorizontalAlignment.Left;
            previewLabel.VerticalAlignment = VerticalAlignment.Bottom;
            previewLabel.Margin = T(12, 0, 0, 10);   // ui-exempt: preview of the launcher
            previewLabel.Effect = new DropShadowEffect { BlurRadius = 6, ShadowDepth = 1, Opacity = 0.8 };
            // logo and label must not catch the drag (the preview tells them apart)
            previewLogo.IsHitTestVisible = false;
            previewLabel.IsHitTestVisible = false;
            pg.Children.Add(canvas);
            pg.Children.Add(previewLabel);
            AddTo(left, preview);
            // with the pad: A on the preview moves its parts
            AddPadArea(preview, StartPlace);
            AddTo(left, NewPlaceHint());
            var how = NewHelp(PlaceHowText());
            how.Margin = T(0, Gap.Control, 0, Gap.Line);
            placeHow = how;
            AddTo(left, how);

            // framing, logo, play time: the name and the chip (Own / From All tiles) on
            // top; below, the slider with its value and unit, the reset in the action column
            Func<string, FrameworkElement, Border, Button, StackPanel> placeBlock = (title, line, chip, reset) =>
            {
                var block = NewPanel();
                block.Margin = T(0, Gap.Group, 0, 0);
                var head = NewGrid("Auto", "*");
                var name = NewText(title, Fs.Label);
                name.VerticalAlignment = VerticalAlignment.Center;
                head.Children.Add(name);
                chip.HorizontalAlignment = HorizontalAlignment.Left;
                SetCol(chip, 1);
                head.Children.Add(chip);
                AddTo(block, head);
                var row = NewFieldRow(null, line, reset);
                row.Margin = T(0, Gap.Line, 0, 0);
                AddTo(block, row);
                return block;
            };
            // the value typed is applied as it is typed; the slider and the wheel write it too
            zoomField = NewNumberField(1, 4, 0.01, Times, t =>
            {
                double n;
                if (bgFrame.Bitmap == null || placeBack || GetPlaceTarget() == null || !Core.TryNumber(t, out n)) return;
                SetFrameZoom(n);
            }, true, 0.05);
            FitFieldHeight(zoomField.Root);
            frameChip = NewChip();
            btnFrameReset = NewResetIcon("Back to the framing of All tiles");
            var frameBlock = placeBlock("Framing", zoomField.Root, frameChip, btnFrameReset);
            // on the backdrop: off, with the reason
            frameWhy = NewHelp("The backdrop is not framed: its image fills it from the centre. The framing is the thumbnail's.", ResBrush("AccentBrush"));
            frameWhy.Margin = T(0, Gap.Help, 0, 0);
            frameBlock.Children.Insert(1, frameWhy);
            frameRow = frameBlock;
            AddTo(left, frameBlock);
            logoField = NewNumberField(0.25, 3, 0.01, Times, t =>
            {
                double n;
                if (previewLogo.Source == null || GetPlaceTarget() == null || !Core.TryNumber(t, out n)) return;
                SetLogoScale(n);
            }, true, 0.05);
            FitFieldHeight(logoField.Root);
            logoChip = NewChip();
            btnLogoReset = NewResetIcon("Back to the logo placement of All tiles");
            var logoBlock = placeBlock("Logo", logoField.Root, logoChip, btnLogoReset);
            // on the backdrop with the logo on the thumbnail: off, with the reason
            logoWhy = NewHelp(WhenReason("WheelLogoOn=Background", null), ResBrush("AccentBrush"));
            logoWhy.Margin = T(0, Gap.Help, 0, 0);
            logoBlock.Children.Insert(1, logoWhy);
            logoRow = logoBlock;
            AddTo(left, logoBlock);
            // play time line: only a place, shown as text where the others have a slider
            infoPosText = NewHelp("");
            infoPosText.VerticalAlignment = VerticalAlignment.Center;
            infoChip = NewChip();
            btnInfoReset = NewResetIcon("Back to the play time placement of All tiles");
            var infoBlock = placeBlock("Play time", infoPosText, infoChip, btnInfoReset);
            var infoHelp = NewHelp("The line with the play time and the last launch, and the Steam update above it (Tiles > Play time and updates): drag it in the preview.");
            infoHelp.Margin = T(0, Gap.Help, 0, 0);
            infoBlock.Children.Insert(1, infoHelp);
            // with TileInfo and UpdateInfo Never: disabled, with the reason
            // (docs/OptionsUI.md, 0): either of the two is enough, their page once
            Page linesPage;
            Schema.ItemOf("TileInfo", out linesPage);
            string either = WhenReason("TileInfo=Hover|Always", linesPage).TrimEnd('.') + ", or "
                + WhenReason("UpdateInfo=Hover|Always", linesPage).Substring("Only with ".Length).TrimEnd('.')
                + (linesPage != null ? " (" + linesPage.Title + " page)." : ".");
            infoNeverWhy = either;
            infoWhy = NewHelp(either, ResBrush("AccentBrush"));
            infoWhy.Margin = T(0, Gap.Help, 0, 0);
            infoBlock.Children.Insert(2, infoWhy);
            infoRow = infoBlock;
            AddTo(left, infoBlock);

            // a press on the play time line moves it, on the logo the logo, anywhere
            // else the background (the line is drawn over the logo)
            preview.MouseLeftButtonDown += (s, e) =>
            {
                if (GetPlaceTarget() == null) return;
                var pt = e.GetPosition(preview);
                if (TestOnInfo(pt))
                {
                    var r = GetInfoRect();
                    infoPlace.Dragging = true; infoPlace.DragPoint = pt; infoPlace.DragX = r.X; infoPlace.DragY = r.Y;
                    infoPlace.Moved = false;
                }
                else if (TestOnLogo(pt))
                {
                    LimitLogoPos();
                    logoPlace.Dragging = true; logoPlace.DragPoint = pt; logoPlace.DragX = logoPlace.X; logoPlace.DragY = logoPlace.Y;
                    logoPlace.Moved = false;
                }
                else
                {
                    if (bgFrame.Bitmap == null || placeBack) return;
                    LimitFocus();
                    bgFrame.Dragging = true; bgFrame.DragPoint = pt; bgFrame.DragFX = bgFrame.FX; bgFrame.DragFY = bgFrame.FY;
                    bgFrame.Moved = false;
                }
                preview.CaptureMouse();
                e.Handled = true;
            };
            preview.MouseMove += (s, e) =>
            {
                var pt = e.GetPosition(preview);
                if (infoPlace.Dragging)
                {
                    MoveInfo(infoPlace.DragX + pt.X - infoPlace.DragPoint.X, infoPlace.DragY + pt.Y - infoPlace.DragPoint.Y);
                    infoPlace.Moved = true;
                    UpdateInfoPlace();
                    return;
                }
                if (logoPlace.Dragging)
                {
                    logoPlace.X = logoPlace.DragX + (pt.X - logoPlace.DragPoint.X) / preview.Width;
                    logoPlace.Y = logoPlace.DragY + (pt.Y - logoPlace.DragPoint.Y) / preview.Height;
                    LimitLogoPos();
                    logoPlace.Moved = true;
                    UpdateLogoPlace();
                    return;
                }
                if (!bgFrame.Dragging) return;
                var v = GetFrameWindow();
                bgFrame.FX = bgFrame.DragFX - (pt.X - bgFrame.DragPoint.X) / (v.S * v.IW);
                bgFrame.FY = bgFrame.DragFY - (pt.Y - bgFrame.DragPoint.Y) / (v.S * v.IH);
                LimitFocus();
                bgFrame.Moved = true;
                UpdateFraming();
            };
            preview.MouseLeftButtonUp += (s, e) => preview.ReleaseMouseCapture();
            // end of the drag (also when the capture is lost): written once
            preview.LostMouseCapture += (s, e) =>
            {
                if (infoPlace.Dragging)
                {
                    infoPlace.Dragging = false;
                    if (infoPlace.Moved) SaveInfoPlace();
                }
                if (logoPlace.Dragging)
                {
                    logoPlace.Dragging = false;
                    if (logoPlace.Moved) SaveLogoPlace();
                }
                if (!bgFrame.Dragging) return;
                bgFrame.Dragging = false;
                if (bgFrame.Moved) SaveFraming();
            };
            preview.MouseWheel += (s, e) =>
            {
                if (GetPlaceTarget() == null) return;
                var pt = e.GetPosition(preview);
                if (TestOnLogo(pt))
                {
                    e.Handled = true;
                    SetLogoScale(logoPlace.Scale * Math.Pow(1.1, e.Delta / 120.0));
                    return;
                }
                if (bgFrame.Bitmap == null || placeBack) return;
                e.Handled = true;   // the page must not scroll
                SetFrameZoom(bgFrame.Zoom * Math.Pow(1.1, e.Delta / 120.0), pt);
            };
            // Reset: a tile goes back to All tiles, All tiles to the centre
            Action<string[]> resetPlace = keys =>
            {
                var t = GetPlaceTarget();
                if (t == null) return;
                ClearPlaceKeys(t, keys);
                if (IsAllSelected()) AfterCategoryPlace();
                else { UpdatePlaceState(); UpdateTileDots(); }
                UpdateTilePreview();
            };
            btnFrameReset.Click += (s, e) => resetPlace(new[] { "BgFocus", "BgZoom" });
            btnLogoReset.Click += (s, e) => resetPlace(new[] { LogoPosKey, LogoScaleKey });
            btnInfoReset.Click += (s, e) => resetPlace(new[] { InfoPosKey });

            // Row 1, right: the settings of the tile, or of the category under All tiles
            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            Grid.SetRow(sv, 1);
            SetCol(sv, 1);
            grid.Children.Add(sv);
            var details = NewPanel();
            sv.Content = details;
            KeepScrollBarRoom(sv, details);

            // Imported game: read-only, can become a normal tile
            importedCard = NewCard("Imported game", "");
            importedCard.Visibility = Visibility.Collapsed;
            AddTo(details, importedCard);
            var txt = NewHelp("From the old automatic import (written below its marker line), so it cannot be edited here. Make it a normal tile to edit or move it: its images are copied to the category folders. Opening Import turns all of them into normal tiles.");
            txt.Margin = T(0, 0, 0, Gap.Text);
            AddTo(CardPanel(importedCard), txt);
            var btnConvert = NewButton("Make it a normal tile", "AccentButton");
            btnConvert.HorizontalAlignment = HorizontalAlignment.Left;
            btnConvert.Margin = T(0, 0, 0, Gap.Text);
            AddTo(CardPanel(importedCard), btnConvert);
            btnConvert.Click += (s, e) =>
            {
                var sel = TagOf(tilesList.SelectedItem);
                if (sel == null || !sel.Imported || sel.Section == null) return;
                var n = ConvertImportedTile(currentFile, sel.Section.Name);
                if (n != null) RefreshTiles(Core.GetTiles(GetModel(currentFile)).Count - 1);
            };

            // All tiles: the settings of the category ([Category])
            allCard = NewCard("All tiles", "Settings of every tile of this category. A tile can have its own colour, background, framing and logo; a dot in the strip marks the tiles with one of them.");
            allCard.Visibility = Visibility.Collapsed;
            AddTo(details, allCard);
            var af = CardPanel(allCard);
            allNote = NewHelp("", ResBrush("AccentBrush"));
            allNote.Margin = T(0, 0, 0, Gap.Control);
            AddTo(af, allNote);
            // a key of the category; the reset next to it shows while it has a value
            Action<string, string, Button> setCatKey = (key, value, reset) =>
            {
                if (loading || currentFile == null) return;
                Core.SetKey(Core.GetCategorySection(GetModel(currentFile)), key, value);
                SetChanged(currentFile);
                SetActionVisible(reset, value != "");
                UpdateTilePreview();   // the tile's proportions and logo size
            };
            // grid and logo size as on Tiles > Grid; empty = its default (help set by ShowAllTiles)
            gridColsReset = NewResetIcon("Back to the default (Tiles > Grid)");
            gridRowsReset = NewResetIcon("Back to the default (Tiles > Grid)");
            catLogoSizeReset = NewResetIcon("Back to the default (Tiles > Grid)");
            gridCols = NewNumberField(1, 12, 1, "", t => setCatKey("NX", t, gridColsReset), true, 0, () => OddOf("NX"));
            gridRows = NewNumberField(1, 8, 1, "", t => setCatKey("NY", t, gridRowsReset), true, 0, () => OddOf("NY"));
            catLogoSize = NewSizeField("H", v => setCatKey("IconSize", v, catLogoSizeReset));
            var colsRow = AddTo(af, NewFormRow("Columns", gridCols.Root, "", null, gridColsReset));
            gridColsHint = FormHelp(colsRow);
            AddGridOnlyReason(colsRow);
            var rowsRow = AddTo(af, NewFormRow("Rows", gridRows.Root, "", null, gridRowsReset));
            gridRowsHint = FormHelp(rowsRow);
            AddGridOnlyReason(rowsRow);
            var sizeFormRow = AddTo(af, NewFormRow("Logo size", catLogoSize.Root, "", null, catLogoSizeReset));
            sizeHint = FormHelp(sizeFormRow);
            AddGridOnlyReason(sizeFormRow);
            Func<string, double> layout = k => { double n; return Core.TryNumber(V(k), out n) ? n : 1; };
            gridColsReset.Click += (s, e) => { setCatKey("NX", "", gridColsReset); gridCols.Show("", layout("NX")); };
            gridRowsReset.Click += (s, e) => { setCatKey("NY", "", gridRowsReset); gridRows.Show("", layout("NY")); };
            catLogoSizeReset.Click += (s, e) => { setCatKey("IconSize", "", catLogoSizeReset); catLogoSize.Show(""); };
            catColorSwatch = NewButton("", "Swatch", "Pick a colour");
            catTileColor = new TextBox();
            catColorClear = NewClearButton("Clear the colour: the default tile colour");
            catColorClear.Click += (s, e) => catTileColor.Text = "";   // TextChanged writes it
            var catColorRow = NewFieldRow(catColorSwatch, catTileColor, null);
            AddTo(af, NewFormRow("Colour", catColorRow, "Colour of the tiles without one of their own (their Colour), used when there is no background image. Empty = the default tile colour (Tiles page). R,G,B,A: the A makes it transparent.", null, catColorClear));
            catColorSwatch.Click += (s, e) =>
            {
                if (currentFile == null) return;
                string n = SelectColor(catTileColor.Text);
                if (n != null) catTileColor.Text = n;
            };
            catTileColor.TextChanged += (s, e) =>
            {
                if (loading || currentFile == null) return;
                Core.SetKey(Core.GetCategorySection(GetModel(currentFile)), "TileColor", catTileColor.Text.Trim());
                SetChanged(currentFile);
                SetSwatch(catColorSwatch, catTileColor.Text);
                SetActionVisible(catColorClear, catTileColor.Text.Trim() != "");
                UpdateTileEntries();
                UpdateTilePreview();
            };
            // opacity in %, as written to the file; empty = 100
            catOpacityReset = NewResetIcon("Restore default (100%)");
            catOpacity = NewNumberField(0, 100, 1, "%", t => setCatKey("TileOpacity", t, catOpacityReset), true, 5);
            catOpacityReset.Click += (s, e) => { setCatKey("TileOpacity", "", catOpacityReset); catOpacity.Show("", 100); };
            AddTo(af, NewFormRow("Background", catOpacity.Root, "Opacity of the colour and the image of the tiles without one of their own (their Background), e.g. lower for a Dashboard with skins over the tiles. Logos, texts and widgets stay as they are. Empty = 100%.", null, catOpacityReset));
            // framing, logo and play time line of every tile back to their default place,
            // the ones with their own too; the buttons share the column
            var btnResetLogos = NewButton("Logos");
            var btnResetFraming = resetFramingAll = NewButton("Framing");
            var btnResetInfo = NewButton("Play time");
            var placeFormRow = NewFormRow("Reset every tile", NewEqualButtons(btnResetLogos, btnResetFraming, btnResetInfo));
            placementHint = FormHelp(placeFormRow);   // what the buttons do and the current placement
            placementRow = placeFormRow;
            AddTo(af, placementRow);
            autoArtRow = NewAutoArtRow();
            AddTo(af, autoArtRow);
            AddTo(af, NewSortRow());
            btnResetLogos.Click += (s, e) => { if (currentFile != null) ResetCategoryPlace(currentFile, placeBack ? "logo placement on the backdrop" : "logo placement", new[] { LogoPosKey, LogoScaleKey }); };
            btnResetFraming.Click += (s, e) => { if (currentFile != null) ResetCategoryPlace(currentFile, "background framing", new[] { "BgFocus", "BgZoom" }); };
            btnResetInfo.Click += (s, e) => { if (currentFile != null) ResetCategoryPlace(currentFile, placeBack ? "play time placement on the backdrop" : "play time placement", new[] { InfoPosKey }, "the top left"); };

            // Tile card
            tileCard = NewCard("Tile", "");
            AddTo(details, tileCard);
            var f = CardPanel(tileCard);
            tileNote = NewHelp("", ResBrush("AccentBrush"));
            tileNote.Margin = T(0, 0, 0, Gap.Control);
            AddTo(f, tileNote);

            foreach (var k in new[] { "Name", "Command", "Label", "Color", "Tags" }) tileFields[k] = new TextBox();
            AddTo(f, NewFormRow("Name", tileFields["Name"], "Also the name of its images and what search looks at."));
            var cmdRow = NewGrid("*", "Auto");
            cmdRow.Children.Add(tileFields["Command"]);
            var btnCmd = NewButton("Browse...");
            btnCmd.Margin = T(Gap.Control, 0, 0, 0);
            SetCol(btnCmd, 1);
            cmdRow.Children.Add(btnCmd);
            AddTo(f, NewFormRow("Command", cmdRow, "A program, a .lnk/.url shortcut, a URL (also steam://...), a folder or a Rainmeter bang."));
            // widgets: any tile, in any category
            widgetKind = NewChoiceBox(WIDGET_KINDS, "", null);
            widgetRow = NewFormRow("Widget", widgetKind, "What the tile shows instead of images. A click opens its Command, or the tool that fits.");
            AddTo(f, widgetRow);
            widgetParam = new TextBox();
            var paramRow = NewFormRow("Widget option", widgetParam);
            widgetHint = FormHelp(paramRow);   // what the option means for the kind chosen
            widgetParamRow = paramRow;
            AddTo(f, widgetParamRow);
            // a custom widget's setting for this tile (#WIDGETOPTION#)
            widgetOption = new TextBox();
            widgetOptionRow = NewFormRow("Widget setting", widgetOption, "A setting of this tile for its custom widget, if it takes one (its page says which): e.g. the Steam app id of a game.");
            AddTo(f, widgetOptionRow);
            widgetOption.TextChanged += (s, e) =>
            {
                if (loading) return;
                var t = GetCurrentTile();
                if (t == null) return;
                Core.SetKey(t, "WidgetOption", widgetOption.Text.Trim());
                SetChanged(currentFile);
            };
            widgetKind.SelectionChanged += (s, e) =>
            {
                UpdateWidgetHint();
                if (loading) return;
                var t = GetCurrentTile();
                string kind = ChoiceValue(widgetKind);
                if (t == null || kind == null) return;
                Core.SetKey(t, "Widget", kind);
                SetChanged(currentFile);
            };
            widgetParam.TextChanged += (s, e) =>
            {
                if (loading) return;
                var t = GetCurrentTile();
                if (t == null) return;
                Core.SetKey(t, "Param", widgetParam.Text.Trim());
                SetChanged(currentFile);
            };
            AddTo(f, NewFormRow("Label", tileFields["Label"], "Text at the bottom left. Empty = none (tiles without images show their name)."));
            colorSwatch = NewButton("", "Swatch", "Pick a colour");
            var colorClear = tileColorClear = NewClearButton("Clear the colour: the one of All tiles");
            colorClear.Click += (s, e) => { if (GetCurrentTile() != null) tileFields["Color"].Text = ""; };
            var colorRow = NewFieldRow(colorSwatch, tileFields["Color"], null);
            AddTo(f, NewFormRow("Colour", colorRow, "Used when there is no background image. Empty = the Colour of All tiles, or taken from the logo, or the default tile colour.", null, colorClear));
            // opacity in %, as written to the file; empty = the one of All tiles (help set by ShowTile)
            tileOpacityReset = NewResetIcon("Back to the value of All tiles");
            tileOpacity = NewNumberField(0, 100, 1, "%", t =>
            {
                if (loading) return;
                var tile = GetCurrentTile();
                if (tile == null) return;
                Core.SetKey(tile, "Opacity", t);
                SetChanged(currentFile);
                SetActionVisible(tileOpacityReset, t != "");
                UpdateTileDots();
            }, true, 5);
            tileOpacityReset.Click += (s, e) =>
            {
                var tile = GetCurrentTile();
                if (tile == null) return;
                Core.SetKey(tile, "Opacity", "");
                SetChanged(currentFile);
                UpdateTileDots();
                ShowTileOpacity(tile);
            };
            var opacityRow = AddTo(f, NewFormRow("Background", tileOpacity.Root, "", null, tileOpacityReset));
            tileOpacityHint = FormHelp(opacityRow);
            // cells taken in the grid (Size=<columns>x<rows>), as the grid of the category
            Action<string> sizeChanged = x =>
            {
                if (loading) return;
                var t = GetCurrentTile();
                if (t == null) return;
                double nc, nr;
                int c = Core.TryNumber(sizeCols.Box.Text, out nc) ? Math.Max(1, Math.Min(8, (int)Math.Round(nc))) : 1;
                int r = Core.TryNumber(sizeRows.Box.Text, out nr) ? Math.Max(1, Math.Min(8, (int)Math.Round(nr))) : 1;
                Core.SetKey(t, "Size", c == 1 && r == 1 ? "" : c + "x" + r);
                SetChanged(currentFile);
                UpdateTilePreview();
            };
            sizeCols = NewNumberField(1, 8, 1, "columns", sizeChanged, true, 0, () => OddOf("NX"));
            sizeRows = NewNumberField(1, 8, 1, "rows", sizeChanged, true, 0, () => OddOf("NY"));
            AddGridOnlyReason(AddTo(f, NewFormRow("Width", sizeCols.Root, "Cells the tile takes in the grid (at most the grid of the category); the other tiles fill the space around it. Search, Favorites and Recent show it in one cell.")));
            AddGridOnlyReason(AddTo(f, NewFormRow("Height", sizeRows.Root)));
            tagSuggestions = new WrapPanel();
            AddTo(f, NewFormRow("Tags", tileFields["Tags"], "Separated by commas, e.g. multiplayer, coop. Search finds them, and each tag is a chip of the filter bar above the search results.", tagSuggestions));
            AddTo(f, NewPinRow());
            // hot key: click, then press the key with its modifiers (as the keys of Settings)
            tileKeyButton = NewButton("None", "KeyButton", "Click, then press a key");
            var keyClear = tileKeyClear = NewClearButton("Clear the key");
            AddTo(f, NewFormRow("Hot key", tileKeyButton, "Starts the tile also while the launcher is hidden, e.g. Ctrl + Alt + 1. Hold the modifiers, then press the key.", null, keyClear));
            tileKeyButton.Click += (s, e) =>
            {
                if (GetCurrentTile() == null) return;
                capturing = tileKeyButton;
                tileKeyButton.Content = "Press a key...";
                tileKeyButton.Focus();
            };
            tileKeyButton.LostKeyboardFocus += (s, e) =>
            {
                if (capturing != tileKeyButton) return;
                capturing = null;
                var t = GetCurrentTile();
                tileKeyButton.Content = Schema.FormatHotKey(t != null ? Core.GetKey(t, "HotKey") : "");
            };
            tileKeyButton.PreviewKeyDown += (s, e) =>
            {
                if (capturing != tileKeyButton) return;
                e.Handled = true;
                var k = e.Key == Key.System ? e.SystemKey : e.Key;
                var mods = Keyboard.Modifiers;
                bool ctrl = (mods & ModifierKeys.Control) != 0, alt = (mods & ModifierKeys.Alt) != 0;
                bool shift = (mods & ModifierKeys.Shift) != 0, winKey = (mods & ModifierKeys.Windows) != 0;
                string value = Schema.ToHotKey(KeyInterop.VirtualKeyFromKey(k), ctrl, alt, shift, winKey, true);
                if (value == null)
                {
                    var held = new List<string>();
                    if (ctrl) held.Add("CTRL");
                    if (alt) held.Add("ALT");
                    if (shift) held.Add("SHIFT");
                    if (winKey) held.Add("LWIN");
                    if (held.Count > 0) tileKeyButton.Content = Schema.FormatHotKey(string.Join(" ", held)) + " + ...";
                    return;
                }
                capturing = null;
                var t = GetCurrentTile();
                if (t == null) return;
                string other = HotKeyUser(value, t);
                if (other != null)
                {
                    tileKeyButton.Content = Schema.FormatHotKey(Core.GetKey(t, "HotKey"));
                    ShowDialog("Hot key", Schema.FormatHotKey(value) + " is already used by " + other + ".");
                    return;
                }
                Core.SetKey(t, "HotKey", value);
                tileKeyButton.Content = Schema.FormatHotKey(value);
                SetActionVisible(tileKeyClear, true);
                SetChanged(currentFile);
            };
            keyClear.Click += (s, e) =>
            {
                var t = GetCurrentTile();
                if (t == null) return;
                Core.SetKey(t, "HotKey", "");
                tileKeyButton.Content = Schema.FormatHotKey("");
                SetActionVisible(tileKeyClear, false);
                SetChanged(currentFile);
            };
            foreach (var kind in new[] { "Background", "Logo" })
            {
                var thumb = NewThumb(FieldHeight);
                var choose = NewButton("Browse...");
                var online = NewButton("Find online...");
                // x: no image (its file goes to the Recycle Bin, asked first)
                var remove = NewClearButton("Clear the " + kind.ToLowerInvariant());
                var buttons = NewPanel(Orientation.Horizontal);
                online.Margin = T(Gap.Control, 0, 0, 0);
                AddTo(buttons, choose); AddTo(buttons, online);
                var row = NewFieldRow(thumb, buttons, null);
                // where the image comes from: the help of the row (set with the tile)
                var imageRow = NewFormRow(kind, row, "", kind == "Logo" ? NewHelp("Find online...: images of this game or app from Steam, SteamGridDB, Dashboard Icons or its website.") : null, remove);
                AddTo(f, imageRow);
                var pathLabel = FormHelp(imageRow);
                if (kind == "Background") { bgThumb = thumb; bgPath = pathLabel; bgDel = remove; } else { logoThumb = thumb; logoPath = pathLabel; logoDel = remove; }
                string k = kind;
                online.Click += (s, e) => FindTileArt(k);
                choose.Click += (s, e) =>
                {
                    var t = GetCurrentTile();
                    if (t == null) return;
                    string src = SelectFile(ImageFilter);
                    if (src == null) return;
                    Core.CopyTileImage(GetCurrentBase(), k.ToLowerInvariant(), t.Name, src);
                    Core.SetKey(t, k, "");   // the default image just copied applies
                    if (k == "Background") ResetFraming(t);
                    SetChanged(currentFile);
                    UpdateTilePreview();
                };
                remove.Click += (s, e) =>
                {
                    var t = GetCurrentTile();
                    if (t == null) return;
                    string path = Core.GetTileImage(GetCurrentBase(), t, k);
                    if (path != null && path.StartsWith(Core.ImagesRoot, StringComparison.OrdinalIgnoreCase))
                    {
                        var r = ShowDialog("Clear " + k.ToLowerInvariant(), "No " + k.ToLowerInvariant() + " for this tile: " + Path.GetFileName(path) + " goes to the Recycle Bin.", new[] { "Clear", "Cancel" }, null, true);
                        if (r.Button != "Clear") return;
                        RemoveToRecycleBin(path);
                    }
                    Core.SetKey(t, k, "");
                    if (k == "Background") ResetFraming(t);
                    SetChanged(currentFile);
                    UpdateTilePreview();
                };
            }

            // --- events
            tilesList.SelectionChanged += (s, e) => ShowTile();
            // drag a tile to change its place (hand-written tiles; the imported
            // ones stay at the end)
            // (while the category keeps an order, Order > Keep sorted, only the pinned ones)
            EnableDragReorder(tilesList, it => !((ListTag)it.Tag).Imported && !((ListTag)it.Tag).All
                && (GetKeptSort(currentFile) == null || IsPinned(((ListTag)it.Tag).Section)), (from, to) =>
            {
                // indices of the strip: All tiles comes first
                from--; to = Math.Max(0, to - 1);
                var m = GetModel(currentFile);
                var tiles = Core.GetTiles(m);
                if (from >= tiles.Count) return;
                to = Math.Min(to, tiles.Count - 1);
                var t = tiles[from];
                var target = tiles[to];
                m.Sections.Remove(t);
                int ins = m.Sections.IndexOf(target);
                // after the target when moving down, before it when moving up
                m.Sections.Insert(to > from ? ins + 1 : ins, t);
                SetChanged(currentFile);
                RefreshTiles(to);
            }, true);
            EnableTileDropOnNav();
            foreach (var k in new[] { "Command", "Label", "Color", "Tags" })
            {
                string key = k;
                var tb = tileFields[k];
                tb.TextChanged += (s, e) =>
                {
                    if (loading) return;
                    var t = GetCurrentTile();
                    if (t == null) return;
                    Core.SetKey(t, key, tb.Text.Trim());
                    SetChanged(currentFile);
                    if (key == "Color") SetActionVisible(tileColorClear, tb.Text.Trim() != "");
                    UpdateTilePreview();
                };
            }
            // renaming: checked when editing ends (duplicates); the images follow
            tileFields["Name"].LostKeyboardFocus += (s, e) =>
            {
                var tb = tileFields["Name"];
                var t = GetCurrentTile();
                if (t == null) return;
                string n = Core.GetTileName(tb.Text);
                if (n == "" || n == t.Name) { tb.Text = t.Name; return; }
                var m = GetModel(currentFile);
                if (m.Sections.Any(x => x != t && string.Equals(x.Name, n, StringComparison.OrdinalIgnoreCase)) || Core.GetImportedNames(m).Contains(n))
                {
                    ShowDialog("Rename tile", "There is already a tile called '" + n + "'.");
                    tb.Text = t.Name;
                    return;
                }
                if (Core.GetKey(t, "Image") == "" && !string.Equals(n, t.Name, StringComparison.OrdinalIgnoreCase)) Core.RenameTileImages(GetCurrentBase(), t.Name, n);
                t.Name = n;
                SetChanged(currentFile);
                UpdateTilePreview();
                // sorted by name: the tile to its new place, once the click that ended
                // the editing is done (it may select another tile)
                if (ApplyKeptSort(currentFile))
                    tilesList.Dispatcher.BeginInvoke(new Action(() =>
                    {
                        var cur = GetCurrentTile();
                        RefreshTiles(cur != null ? Core.GetTiles(GetModel(currentFile)).IndexOf(cur) : -1);
                    }), System.Windows.Threading.DispatcherPriority.Background);
            };
            tileFields["Name"].KeyDown += (s, e) => { if (e.Key == Key.Return) tilesList.Focus(); };
            btnCmd.Click += (s, e) =>
            {
                string src = SelectFile("Programs and shortcuts|*.exe;*.lnk;*.url;*.bat;*.cmd|All files|*.*");
                if (src != null) tileFields["Command"].Text = "\"" + src + "\"";
            };
            colorSwatch.Click += (s, e) =>
            {
                if (GetCurrentTile() == null) return;
                string n = SelectColor(tileFields["Color"].Text);
                if (n != null) tileFields["Color"].Text = n;
            };
            // tiles: new, delete, reorder (hand-written ones only)
            btnTileNew.Click += (s, e) =>
            {
                if (currentFile == null) return;
                var m = GetModel(currentFile);
                var r = ShowDialog("New tile", "Name of the new tile (also the name of its images):", new[] { "Create", "Cancel" }, "");
                string name = Core.GetTileName(r.Text ?? "");
                if (r.Button != "Create" || name == "") return;
                if (TestTileName(m, name)) { ShowDialog("New tile", "There is already a tile called '" + name + "'."); return; }
                var added = new IniSection { Name = name };
                Core.SetKey(added, "Added", DateTime.Now.ToString("yyyy-MM-dd"));   // for Not played yet
                m.Sections.Add(added);
                SetChanged(currentFile);
                RefreshTiles(Core.GetTiles(m).Count - 1);
                tileFields["Command"].Focus();
            };
            btnTileDel.Click += (s, e) =>
            {
                var t = GetCurrentTile();
                if (t == null) return;
                var r = ShowDialog("Delete tile", "Delete the tile '" + t.Name + "'? Its images stay in Images.", new[] { "Delete", "Cancel" }, null, true);
                if (r.Button != "Delete") return;
                GetModel(currentFile).Sections.Remove(t);
                SetChanged(currentFile);
                RefreshTiles(Math.Max(0, tilesList.SelectedIndex - 2));   // the tile before it (All tiles is entry 0)
            };
            foreach (var pair in new[] { Tuple.Create(btnTileUp, -1), Tuple.Create(btnTileDown, 1) })
            {
                int delta = pair.Item2;
                pair.Item1.Click += (s, e) =>
                {
                    var t = GetCurrentTile();
                    // disabled while the category keeps an order (only pinned tiles move)
                    if (t == null || (GetKeptSort(currentFile) != null && !IsPinned(t))) return;
                    var m = GetModel(currentFile);
                    var tiles = Core.GetTiles(m);
                    int i = tiles.IndexOf(t), j = i + delta;
                    if (j < 0 || j >= tiles.Count) return;
                    int a = m.Sections.IndexOf(t), b = m.Sections.IndexOf(tiles[j]);
                    m.Sections[a] = tiles[j]; m.Sections[b] = t;
                    SetChanged(currentFile);
                    RefreshTiles(j);
                };
            }
            return grid;
        }
    }
}
