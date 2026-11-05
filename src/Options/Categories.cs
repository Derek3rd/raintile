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
    }

    public partial class OptionsApp
    {
        static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
        Dictionary<string, CategoryModel> models = new Dictionary<string, CategoryModel>(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, bool> changedFiles = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, string> logoColors = new Dictionary<string, string>();
        string currentFile;   // category whose tiles are shown (chosen in the menu)
        bool loading;

        // controls of the category pages
        ListBox catsList, tilesList;
        Border catCard, tileCard, importedCard, catIcon, bgThumb, logoThumb, preview;
        TextBlock catIconHint, gridHint, sizeHint, tileNote, previewLabel, bgPath, logoPath, zoomText, logoScaleText;
        Image previewBg, previewLogo;
        Panel frameRow, logoRow;
        Slider zoomSlider, logoSlider;
        Button tileKeyButton;
        TextBox catTileColor;
        ComboBox catOpacity, tileOpacity;
        Button catColorSwatch;
        ComboBox widgetKind, sizeCols, sizeRows;
        TextBox widgetParam;
        TextBlock widgetHint, placementHint;
        FrameworkElement widgetRow, widgetParamRow, placementRow;
        // the category page: preview column, All tiles card, inheritance chips
        Border allCard, previewCard, frameChip, logoChip;
        FrameworkElement previewOnRow;
        ComboBox previewOn;
        TextBlock allNote;
        Button btnFrameReset, btnLogoReset;
        Panel previewColumn;
        readonly Dictionary<string, TextBox> allFields = new Dictionary<string, TextBox>();
        BitmapSource placeholderBg, placeholderLogo;

        // Widgets of a Dashboard: kind, label in the list, what Param= means
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
            new[] { "temps", "Temperatures (HWiNFO)", "HWiNFO readings separated by ; (e.g. CPU Package; GPU Temperature; Total CPU Usage), =Name to rename one (GPU Hot Spot=GPU hot). Temperatures first, then any reading with that label. Empty: CPU, GPU and drives." },
            new[] { "fans", "Fans (HWiNFO)", "Like Temperatures, for fans. Empty: the first fans." },
            new[] { "skin", "An installed skin", "<config>\\<file>.ini of a skin in Rainmeter's Skins folder, e.g. illustro\\Clock\\Clock.ini. It is loaded over the tile while the Dashboard is shown." },
            new[] { "custom", "Custom widget", "The name of a widget in the Widgets folder of your data (Widgets\\<name>.ini or Widgets\\<name>\\<name>.ini)." },
        };

        bool IsDashboard(string file)
        {
            return file != null && string.Equals(Core.GetKey(Core.GetCategorySection(GetModel(file)), "Type").Trim(), "Dashboard", StringComparison.OrdinalIgnoreCase);
        }

        void UpdateWidgetHint()
        {
            var item = widgetKind.SelectedItem as ComboBoxItem;
            string kind = item != null ? (string)item.Tag : "";
            string hint = WIDGET_KINDS.Where(k => k[0] == kind).Select(k => k[2]).FirstOrDefault() ?? "";
            widgetHint.Text = hint;
            widgetParamRow.Visibility = hint != "" ? Visibility.Visible : Visibility.Collapsed;
        }
        Button colorSwatch;
        WrapPanel tagSuggestions;
        readonly Dictionary<string, TextBox> catFields = new Dictionary<string, TextBox>();
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

        void SetChanged(string file) { changedFiles[file] = true; UpdateDirty(); }

        // Square thumbnail: image (or colour) in a rounded box
        Border NewThumb(double size)
        {
            var b = new Border { Width = size, Height = size, CornerRadius = new CornerRadius(5), Background = ResBrush("FieldBg") };
            b.Child = new Image { Stretch = Stretch.Uniform, Margin = T(Math.Round(size / 8)) };
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
            thumb.Margin = T(0, 0, 10, 0);
            AddTo(sp, thumb);
            var texts = NewPanel();
            texts.VerticalAlignment = VerticalAlignment.Center;
            var t = NewText(title, 13);
            t.TextTrimming = TextTrimming.CharacterEllipsis;
            AddTo(texts, t);
            if (!string.IsNullOrEmpty(sub)) AddTo(texts, NewText(sub, 11, ResBrush("DimBrush")));
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
        // (the Dashboards have a page of their own: left out unless asked)
        List<CategoryEntry> GetCategoryEntries(bool withDashboards = false)
        {
            var list = new List<CategoryEntry>();
            foreach (var f in Core.GetCategoryFiles())
            {
                if (!withDashboards && IsDashboard(f.Name)) continue;
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
                var item = NewListEntry(e.Name, e.File + "   \u00B7   " + count, new ListTag { File = e.File }, 36);
                SetThumb(((ListTag)item.Tag).Thumb, e.Icon);
                item.Padding = T(12, 9);
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

        // Keys a tile can take from All tiles (framing, logo, TileColor, TileOpacity):
        // a tile with one of them has settings of its own (the dot in the strip)
        static readonly string[] OWN_KEYS = { "BgFocus", "BgZoom", "LogoPos", "LogoScale", "Color", "Opacity" };

        static bool HasOwnValues(IniSection s)
        {
            return s != null && OWN_KEYS.Any(k => Core.GetKey(s, k).Trim() != "");
        }

        // Entry of the tile strip: a small tile (background, logo) and the name below
        ListBoxItem NewStripEntry(string title, ListTag tag)
        {
            var item = new ListBoxItem { Width = 132, Padding = T(6), Margin = T(0, 0, 4, 0), VerticalContentAlignment = VerticalAlignment.Top };
            var sp = NewPanel();
            var g = new Grid();
            var thumb = new Border { Height = 68, CornerRadius = new CornerRadius(6), Background = ResBrush("FieldBg"), ClipToBounds = true };
            thumb.Child = new Image { Stretch = Stretch.Uniform, Margin = T(14, 10) };
            g.Children.Add(thumb);
            var dot = new Border
            {
                Width = 10, Height = 10, CornerRadius = new CornerRadius(5), Background = ResBrush("AccentBrush"),
                BorderBrush = ResBrush("CardBg"), BorderThickness = T(1.5), Margin = T(0, 5, 5, 0),
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top,
                Visibility = Visibility.Collapsed, ToolTip = "Its own colour, background, framing or logo, not the one of All tiles",
            };
            g.Children.Add(dot);
            AddTo(sp, g);
            var t = NewText(title, 12);
            t.TextTrimming = TextTrimming.CharacterEllipsis;
            t.Margin = T(2, 6, 2, 0);
            t.ToolTip = title;
            AddTo(sp, t);
            item.Content = sp;
            tag.Thumb = thumb; tag.Title = t; tag.Dot = dot;
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
            tag.Title.ToolTip = s.Name;
            SetStripThumb(tag, GetBitmap(bg, 264), GetBitmap(logo, 160), GetTileBrush(b, s, bg, logo));
            tag.Dot.Visibility = !tag.Imported && HasOwnValues(s) ? Visibility.Visible : Visibility.Collapsed;
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
                var text = new FormattedText("\uE7FC", CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
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
            SetThumb(catIcon, c != null ? Core.GetCategoryIcon(GetListBase(), c) : null);
            catIconHint.Text = file != null ? "Default: Images\\" + GetListBase() + "\\icon.png" : "";
            loading = false;
        }

        // Opacity of the tile background (colour and image): "" = the default, then 100% to 0%
        static ComboBox NewOpacityBox(string defaultLabel)
        {
            var box = new ComboBox();
            box.Items.Add(new ComboBoxItem { Content = defaultLabel, Tag = "" });
            for (int n = 100; n >= 0; n -= 10) box.Items.Add(new ComboBoxItem { Content = n + "%" + (n == 0 ? " (none)" : ""), Tag = n.ToString() });
            return box;
        }

        static void SelectOpacity(ComboBox box, string value)
        {
            int v;
            string tag = int.TryParse((value ?? "").Trim(), out v) ? (Math.Max(0, Math.Min(100, (int)Math.Round(v / 10.0) * 10))).ToString() : "";
            box.SelectedItem = box.Items.OfType<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == tag) ?? box.Items[0];
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
            public bool Dragging, Moved, Sync;
            public Point DragPoint; public double DragFX, DragFY;
        }
        class LogoState
        {
            public double X = 0.5, Y = 0.5, Scale = 1.0, Box = 96.0;
            public bool Dragging, Moved, Sync;
            public Point DragPoint; public double DragX, DragY;
        }
        readonly FrameState bgFrame = new FrameState();
        readonly LogoState logoPlace = new LogoState();

        // Size in pixels of a tile of category 'file' (only its proportions count)
        double[] GetTileSize(string file)
        {
            double[] area = null;
            try
            {
                var parts = File.ReadAllText(Path.Combine(Core.Generated, "Area.txt")).Trim().Split(',');
                if (parts.Length == 3) area = parts.Select(p => double.Parse(p, Inv)).ToArray();
            }
            catch { }
            if (area == null)
            {
                // skin not loaded yet: the screen without menu and margins, roughly
                area = new[] { screenPx[0] * 0.96, screenPx[1] * 0.88, 16 };
            }
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
        // BgFocus, BgZoom, LogoPos and LogoScale in [Category] are the placement of the
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

        // The category's value of a key, formatted as saved ("50,50" or "1" when it has none)
        static string GetCategoryPlace(CategoryModel model, string key)
        {
            string raw = Core.GetKey(Core.GetCategorySection(model), key);
            double x, y;
            if (key == "BgFocus" || key == "LogoPos")
                return ParsePair(raw, out x, out y) ? FormatPair(Math.Min(100.0, x) / 100, Math.Min(100.0, y) / 100) : "50,50";
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

        // Writes a point and a factor (BgFocus/BgZoom or LogoPos/LogoScale): under All
        // tiles to the category (the centre at 1 = no key), on a tile only where it
        // differs from the category
        void SavePlace(string posKey, string sizeKey, string pos, string size)
        {
            if (IsAllSelected())
            {
                var c = GetPlaceTarget();
                if (c == null) return;
                string p = pos == "50,50" ? "" : pos, z = size == "1" ? "" : size;
                if (Core.GetKey(c, posKey) == p && Core.GetKey(c, sizeKey) == z) return;
                Core.SetKey(c, posKey, p);
                Core.SetKey(c, sizeKey, z);
                SetChanged(currentFile);
                AfterCategoryPlace();
                return;
            }
            var t = GetCurrentTile();
            if (t == null) return;
            bool a = SetPlaceKey(t, posKey, pos);
            bool b = SetPlaceKey(t, sizeKey, size);
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
            bool frameOwn = has(t, "BgFocus", "BgZoom"), logoOwn = has(t, "LogoPos", "LogoScale");
            SetChip(frameChip, all ? null : (bool?)frameOwn);
            SetChip(logoChip, all ? null : (bool?)logoOwn);
            // the icon buttons have no disabled look of their own
            Action<Button, bool> enable = (b, on) => { b.IsEnabled = on; b.Opacity = on ? 1 : 0.35; };
            enable(btnFrameReset, all ? has(c, "BgFocus", "BgZoom") : frameOwn);
            enable(btnLogoReset, all ? has(c, "LogoPos", "LogoScale") : logoOwn);
            btnFrameReset.ToolTip = all ? "Back to the centre, at zoom 1" : "Back to the framing of All tiles";
            btnLogoReset.ToolTip = all ? "Back to the centre, at the normal size" : "Back to the logo placement of All tiles";
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
            chip.ToolTip = own.Value ? "This tile has its own; the x next to the slider gives it back the one of All tiles" : "Follows All tiles; move it to give this tile its own";
        }

        Border NewChip()
        {
            var t = NewText("", 11);
            return new Border { CornerRadius = new CornerRadius(9), Padding = T(8, 1, 8, 2), Margin = T(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, Child = t };
        }

        // Reset of a whole category: centre and normal size, for the category and every tile
        void ResetCategoryPlace(string file, string what, string[] keys)
        {
            var model = GetModel(file);
            var tiles = Core.GetTiles(model);
            var r = ShowDialog("Raintile", "Reset the " + what + " of all " + tiles.Count + " tiles of " + GetCategoryName(file) +
                "? They go back to the centre, at the normal size.", new[] { "Reset", "Cancel" });
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
            placementRow.Visibility = file != null && !IsDashboard(file) ? Visibility.Visible : Visibility.Collapsed;
            if (file == null) { SetLabelHint(placementHint, ""); return; }
            var model = GetModel(file);
            var tiles = Core.GetTiles(model);
            Func<string, string, string> describe = (pos, size) =>
            {
                string p = GetCategoryPlace(model, pos), z = GetCategoryPlace(model, size);
                string text = (p == "50,50" ? "centre" : p + "%") + (z == "1" ? "" : ", " + z + "\u00D7");
                int own = tiles.Count(t => Core.GetKey(t, pos) != "" || Core.GetKey(t, size) != "");
                return text + (own > 0 ? " (" + own + (own == 1 ? " tile has its own)" : " tiles have their own)") : "");
            };
            SetLabelHint(placementHint, "Logos: " + describe("LogoPos", "LogoScale") + ". Framing: " + describe("BgFocus", "BgZoom") +
                ". These buttons put every tile back at the centre, the ones with their own included.");
        }

        void ReadFraming(IniSection section)
        {
            bgFrame.FX = 0.5; bgFrame.FY = 0.5; bgFrame.Zoom = 1.0;
            if (section == null) return;
            double x, y, z;
            if (ParsePair(GetPlaceKey(section, "BgFocus"), out x, out y)) { bgFrame.FX = Math.Min(100.0, x) / 100; bgFrame.FY = Math.Min(100.0, y) / 100; }
            if (double.TryParse(GetPlaceKey(section, "BgZoom"), NumberStyles.Float, Inv, out z)) bgFrame.Zoom = Math.Min(4.0, Math.Max(1.0, z));
        }

        // Part of the image shown, in image pixels; S = preview pixels per image pixel
        struct FrameWindow { public double X, Y, W, H, S, IW, IH; }

        FrameWindow GetFrameWindow()
        {
            double iw = bgFrame.Bitmap.PixelWidth, ih = bgFrame.Bitmap.PixelHeight;
            double pw = preview.Width, ph = preview.Height;
            double s = Math.Max(pw / iw, ph / ih) * bgFrame.Zoom;
            double w = Math.Min(iw, pw / s), h = Math.Min(ih, ph / s);
            return new FrameWindow
            {
                X = Math.Min(iw - w, Math.Max(0.0, bgFrame.FX * iw - w / 2)),
                Y = Math.Min(ih - h, Math.Max(0.0, bgFrame.FY * ih - h / 2)),
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
            // as large as the preview column allows (it follows the window)
            double maxW = previewColumn != null && previewColumn.ActualWidth > 0 ? Math.Min(640.0, previewColumn.ActualWidth) : 384;
            double k = Math.Min(maxW / bgFrame.TW, 440 / bgFrame.TH);
            preview.Width = Math.Max(40.0, Math.Round(bgFrame.TW * k));
            preview.Height = Math.Max(40.0, Math.Round(bgFrame.TH * k));
            previewBg.Source = bgFrame.Bitmap;
            bool has = bgFrame.Bitmap != null;
            frameRow.IsEnabled = has;
            preview.Cursor = has || previewLogo.Source != null ? Cursors.SizeAll : null;
            bgFrame.Sync = true;
            zoomSlider.Value = bgFrame.Zoom;
            bgFrame.Sync = false;
            zoomText.Text = bgFrame.Zoom.ToString("0.00", Inv) + "\u00D7";
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
        // the image, as when zooming with the wheel under the mouse
        void SetFrameZoom(double zoom, Point? anchor = null)
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
            SaveFraming();
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
            if (ParsePair(GetPlaceKey(section, "LogoPos"), out x, out y)) { logoPlace.X = Math.Min(100.0, x) / 100; logoPlace.Y = Math.Min(100.0, y) / 100; }
            if (double.TryParse(GetPlaceKey(section, "LogoScale"), NumberStyles.Float, Inv, out z)) logoPlace.Scale = Math.Min(3.0, Math.Max(0.25, z));
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
            if (previewLogo.Source == null) return false;
            var r = GetLogoRect();
            return Math.Abs(pt.X - r.CX) <= r.VW / 2 + 6 && Math.Abs(pt.Y - r.CY) <= r.VH / 2 + 6;
        }

        void UpdateLogoPlace()
        {
            bool has = previewLogo.Source != null;
            logoRow.IsEnabled = has;
            logoPlace.Sync = true;
            logoSlider.Value = logoPlace.Scale;
            logoPlace.Sync = false;
            logoScaleText.Text = logoPlace.Scale.ToString("0.00", Inv) + "\u00D7";
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
            SavePlace("LogoPos", "LogoScale", FormatPair(logoPlace.X, logoPlace.Y), FormatFactor(logoPlace.Scale));
        }

        // The position is not limited here: a logo pushed into a corner stays there
        void SetLogoScale(double scale)
        {
            logoPlace.Scale = Math.Round(Math.Min(3.0, Math.Max(0.25, scale)), 2);
            UpdateLogoPlace();
            SaveLogoPlace();
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
            ReadFraming(s);
            var size = currentFile != null ? GetTileSize(currentFile) : new double[] { 16, 9 };
            // a tile of more cells (Size=): its own proportions (gaps left out)
            var span = Regex.Match(s != null && !all ? Core.GetKey(s, "Size") : "", @"^\s*(\d+)\s*[xX*]\s*(\d+)\s*$");
            if (span.Success)
            {
                size = new[] { size[0] * Math.Max(1, int.Parse(span.Groups[1].Value)), size[1] * Math.Max(1, int.Parse(span.Groups[2].Value)) };
            }
            bgFrame.TW = size[0]; bgFrame.TH = size[1];
            previewLogo.Source = all && sample == null ? GetPlaceholderLogo() : GetBitmap(logo, 384);
            ReadLogoPlace(s);
            logoPlace.Box = currentFile != null ? GetLogoBox(currentFile) : 96.0;
            UpdateFraming();
            UpdateLogoPlace();
            UpdatePlaceState();
            string label = s != null && !all ? Core.GetKey(s, "Label") : "";
            if (label == "" && s != null && !all && bg == null && logo == null) label = s.Name;
            previewLabel.Text = label;
            previewLabel.Visibility = label != "" && V("ShowLabels") != "0" ? Visibility.Visible : Visibility.Collapsed;
            if (all) return;
            SetThumb(bgThumb, bg);
            SetThumb(logoThumb, logo);
            SetLabelHint(bgPath, bg ?? (s != null ? "None. Default: Images\\" + b + "\\background\\" + s.Name + ".jpg" : ""));
            SetLabelHint(logoPath, logo ?? (s != null ? "None. Default: Images\\" + b + "\\logo\\" + s.Name + ".png" : ""));
            SetSwatch(colorSwatch, s != null ? Core.GetKey(s, "Color") : "");
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
                b.Margin = T(0, 0, 12, 0);
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
            tileKeyButton.Content = Schema.FormatHotKey(s != null ? Core.GetKey(s, "HotKey") : "");
            bool dashboard = IsDashboard(currentFile);
            widgetRow.Visibility = dashboard ? Visibility.Visible : Visibility.Collapsed;
            string kind = s != null ? Core.GetKey(s, "Widget").Trim().ToLowerInvariant() : "";
            widgetKind.SelectedItem = widgetKind.Items.OfType<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == kind) ?? widgetKind.Items[0];
            widgetParam.Text = s != null ? Core.GetKey(s, "Param") : "";
            UpdateWidgetHint();
            if (!dashboard) widgetParamRow.Visibility = Visibility.Collapsed;
            var size = Regex.Match(s != null ? Core.GetKey(s, "Size") : "", @"^\s*(\d+)\s*[xX*]\s*(\d+)\s*$");
            int sc = size.Success ? Math.Max(1, Math.Min(8, int.Parse(size.Groups[1].Value))) : 1;
            int sr = size.Success ? Math.Max(1, Math.Min(8, int.Parse(size.Groups[2].Value))) : 1;
            sizeCols.SelectedItem = sc.ToString();
            SelectOpacity(tileOpacity, s != null ? Core.GetKey(s, "Opacity") : "");
            sizeRows.SelectedItem = sr.ToString();
            tileFields["Name"].Text = s != null ? s.Name : "";
            tileNote.Text = sel == null ? "No tiles yet: add one with the + button." : "";
            tileNote.Visibility = tileNote.Text != "" ? Visibility.Visible : Visibility.Collapsed;
            // a Dashboard has widgets: no backgrounds or logos to place
            bool dash = IsDashboard(currentFile);
            frameRow.Visibility = logoRow.Visibility = dash ? Visibility.Collapsed : Visibility.Visible;
            loading = false;
            UpdateTilePreview();
        }

        // All tiles: the settings of the category (its [Category] section)
        void ShowAllTiles()
        {
            var c = currentFile != null ? Core.GetCategorySection(GetModel(currentFile)) : null;
            foreach (var kv in allFields) kv.Value.Text = c != null ? Core.GetKey(c, kv.Key) : "";
            SetLabelHint(gridHint, "Columns \u00D7 rows. Empty = default (" + V("NX") + " \u00D7 " + V("NY") + ", from Layout)");
            SetLabelHint(sizeHint, "Pixels or % of the screen height. Empty = default (" + V("IconSize") + ")");
            catTileColor.Text = c != null ? Core.GetKey(c, "TileColor") : "";
            SetSwatch(catColorSwatch, catTileColor.Text);
            SelectOpacity(catOpacity, c != null ? Core.GetKey(c, "TileOpacity") : "");
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

        // Every field of a form fills the column, so all of them share both edges; a
        // button after it (Browse..., the clear button) takes its room from the field.
        const double PairGap = 32;

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
                tb.Padding = T(8, 0);
                tb.FontSize = 13;
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

        Grid NewFormRow(string label, UIElement control, string hint = "", FrameworkElement hintBlock = null)
        {
            var g = NewGrid("118", "*");
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.Margin = T(0, 7);
            // centred on the control, not on the hint below it
            var l = NewText(label, 13, ResBrush("DimBrush"));
            l.VerticalAlignment = VerticalAlignment.Center;
            g.Children.Add(l);
            // A fixed hint is the tooltip of the label (dotted underline), to keep the form short;
            // hintBlock stays below the control: it shows current values or holds buttons.
            if (!string.IsNullOrEmpty(hint)) SetLabelHint(l, hint);
            // a field with its own width starts at the left edge (stretched, it would be centred)
            var fe = control as FrameworkElement;
            if (fe != null && !double.IsNaN(fe.Width)) fe.HorizontalAlignment = HorizontalAlignment.Left;
            FitFieldHeight(control);
            SetCol(control, 1);
            g.Children.Add(control);
            if (hintBlock != null)
            {
                hintBlock.Margin = T(0, 4, 0, 0);
                SetCol(hintBlock, 1);
                Grid.SetRow(hintBlock, 1);
                g.Children.Add(hintBlock);
            }
            return g;
        }

        // Two fields split the column around a dimmed x (grid, size)
        Grid NewPairRow(FrameworkElement a, FrameworkElement b)
        {
            var g = NewGrid("*", PairGap.ToString(System.Globalization.CultureInfo.InvariantCulture), "*");
            var by = NewText(((char)0xD7).ToString(), 13, ResBrush("DimBrush"));
            by.VerticalAlignment = VerticalAlignment.Center;
            by.HorizontalAlignment = HorizontalAlignment.Center;
            SetCol(by, 1); SetCol(b, 2);
            g.Children.Add(a); g.Children.Add(by); g.Children.Add(b);
            return g;
        }

        // A colour swatch shows its field: empty = the field background, as an empty field
        void SetSwatch(Button swatch, string value)
        {
            swatch.Background = (Brush)NewColorBrush(value, true) ?? ResBrush("FieldBg");
        }

        // The one button that empties a field (hot key, image, icon); the trash is for
        // deleting a tile or a category
        Button NewClearButton(string tip)
        {
            var b = NewIconButton(0xE711, tip);
            b.Margin = T(6, 0, 0, 0);
            return b;
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
                field.Margin = T(8, 0, 0, 0);
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

        static TextDecorationCollection hintUnderline;

        void SetLabelHint(TextBlock label, string hint)
        {
            if (string.IsNullOrEmpty(hint)) { label.TextDecorations = null; label.ClearValue(FrameworkElement.CursorProperty); label.ToolTip = null; return; }
            if (hintUnderline == null)
            {
                var dim = ResBrush("DimBrush") as SolidColorBrush;
                var brush = new SolidColorBrush(dim != null ? dim.Color : Colors.Gray) { Opacity = 0.6 };
                // 1 px dots 2 px apart (DashStyles.Dot has zero-length dashes: invisible with flat caps)
                var pen = new Pen(brush, 1) { DashStyle = new DashStyle(new double[] { 1, 2 }, 0) };
                pen.Freeze();
                hintUnderline = new TextDecorationCollection { new TextDecoration(TextDecorationLocation.Underline, pen, 2, TextDecorationUnit.FontRecommended, TextDecorationUnit.Pixel) };
                hintUnderline.Freeze();
            }
            label.TextDecorations = hintUnderline;
            label.Cursor = Cursors.Help;
            // the default tooltip neither wraps nor stays long enough for two lines of text
            label.ToolTip = new TextBlock { Text = hint, TextWrapping = TextWrapping.Wrap, MaxWidth = 340 };
            ToolTipService.SetInitialShowDelay(label, 250);
            ToolTipService.SetShowDuration(label, 60000);
        }

        Border NewListColumn(string title, UIElement list, params UIElement[] buttons)
        {
            var b = new Border { Style = ResStyle("Card"), Padding = T(8, 4, 8, 8), Margin = T(0, 0, 14, 0) };
            var dp = new DockPanel();
            b.Child = dp;
            var head = NewGrid("*", "Auto");
            head.Margin = T(6, 8, 0, 6);
            DockPanel.SetDock(head, Dock.Top);
            var h = NewText(title.ToUpperInvariant(), 11.5, ResBrush("DimBrush"), true);
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
        // tiles, the Dashboard and its widgets.
        void EnableTileDropOnNav()
        {
            ListBoxItem marked = null;
            Action unmark = () => { if (marked != null) marked.BorderThickness = T(0); marked = null; };
            Func<DragEventArgs, string> target = e =>
            {
                var tile = e.Data.GetData("RaintileItem") as ListBoxItem;
                if (tile == null || !tilesList.Items.Contains(tile) || currentFile == null || IsDashboard(currentFile)) return null;
                var over = ItemAt(nav, e.OriginalSource as DependencyObject);
                var tag = over != null ? over.Tag as NavTag : null;
                if (tag == null || tag.Type != "category" || tag.File == currentFile || IsDashboard(tag.File)) return null;
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
                if (err != null) { ShowDialog("Raintile", err); return; }
                RefreshTiles(Math.Max(0, index - 2));   // the tile before it (All tiles is entry 0)
            };
        }

        // The scroll viewer inside a control's template (the strip scrolls with the wheel)
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
            grid.Margin = T(36, 4, 36, 20);
            var dp = new DockPanel { Margin = T(0, 0, 16, 0) };
            grid.Children.Add(dp);
            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            SetCol(sv, 1);
            grid.Children.Add(sv);
            var side = NewPanel();
            side.MaxWidth = 600;
            side.HorizontalAlignment = HorizontalAlignment.Left;
            sv.Content = side;
            var bar = NewPanel(Orientation.Horizontal);
            bar.Margin = T(0, 0, 0, 12);
            DockPanel.SetDock(bar, Dock.Top);
            dp.Children.Add(bar);
            var btnNew = NewButton("New category", "AccentButton");
            var btnOpen = NewButton("Open");
            var btnUp = NewButton("Move up");
            var btnDown = NewButton("Move down");
            var btnDel = NewButton("Delete");
            btnDel.Foreground = ResBrush("DangerBrush");
            foreach (var b in new[] { btnNew, btnOpen, btnUp, btnDown, btnDel }) { b.Margin = T(0, 0, 8, 0); AddTo(bar, b); }
            var listCard = new Border { Style = ResStyle("Card"), Padding = T(8), Margin = T(0) };
            catsList = new ListBox();
            listCard.Child = catsList;
            dp.Children.Add(listCard);

            // Category card
            catCard = NewCard("Category", "");
            AddTo(side, catCard);
            var f = CardPanel(catCard);
            catFields["Name"] = new TextBox();
            AddTo(f, NewFormRow("Name", catFields["Name"], "Text shown in the menu."));
            catIcon = NewThumb(FieldHeight);
            var btnIcon = NewButton("Choose...");
            var btnIconDel = NewClearButton("Remove the icon");
            var iconRow = NewFieldRow(catIcon, btnIcon, btnIconDel);
            catIconHint = NewText("", 11.5, ResBrush("DimBrush"), false, true);
            AddTo(f, NewFormRow("Icon", iconRow, "", catIconHint));
            var more = NewText("Grid, logo size, tile colour and background, framing and logo of all its tiles: open the category (double click) and choose All tiles, the first entry above its tiles.", 12, ResBrush("DimBrush"), false, true);
            more.Margin = T(0, 6, 0, 10);
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
                SetThumb(catIcon, Core.GetCategoryIcon(GetListBase(), Core.GetCategorySection(GetModel(file))));
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
                    var r = ShowDialog("Raintile", "Move " + Path.GetFileName(icon) + " to the Recycle Bin?", new[] { "Remove", "Cancel" });
                    if (r.Button != "Remove") return;
                    RemoveToRecycleBin(icon);
                }
                Core.SetKey(c, "Icon", "");
                SetChanged(file);
                SetThumb(catIcon, null);
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
                if (file == "") { ShowDialog("Raintile", "Use at least one letter or digit."); return; }
                if (File.Exists(Path.Combine(Core.CategoriesDir, file + ".ini"))) { ShowDialog("Raintile", "The category '" + file + "' already exists."); return; }
                NewCategoryFile(file, r.Text);
                RefreshCats(file + ".ini");
                BuildNav(navCurrent);
            };
            btnDel.Click += (s, e) =>
            {
                var t = TagOf(catsList.SelectedItem);
                if (t == null) return;
                string file = t.File;
                var r = ShowDialog("Delete category", "Move the category " + file + " to the Recycle Bin? Its images stay in Images.", new[] { "Delete", "Cancel" });
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
            var grid = new Grid { Margin = T(36, 4, 36, 20) };
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
            var btnTileNew = NewIconButton(0xE710, "New tile");
            var btnTileDel = NewIconButton(0xE74D, "Delete tile");
            var btnTileUp = NewIconButton(0xE76B, "Move left");
            var btnTileDown = NewIconButton(0xE76C, "Move right");
            var strip = NewListColumn("Tiles", tilesList, btnTileNew, btnTileUp, btnTileDown, btnTileDel);
            strip.Margin = T(0, 0, 0, 14);
            Grid.SetColumnSpan(strip, 2);
            grid.Children.Add(strip);

            // Row 1, left: the preview, as the tile looks in the launcher
            var leftScroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = T(0, 0, 14, 0) };
            Grid.SetRow(leftScroll, 1);
            grid.Children.Add(leftScroll);
            previewCard = new Border { Style = ResStyle("Card"), Padding = T(20, 16, 20, 14), VerticalAlignment = VerticalAlignment.Top };
            leftScroll.Content = previewCard;
            var left = NewPanel();
            previewCard.Child = left;
            previewColumn = left;
            // the preview follows the width of the column
            left.SizeChanged += (s, e) => { if (e.WidthChanged && preview != null) { UpdateFraming(); UpdateLogoPlace(); } };

            // All tiles: the tile whose images show the category's values
            var por = NewPanel(Orientation.Horizontal);
            por.Margin = T(0, 0, 0, 12);
            var pol = NewText("Preview on", 13, ResBrush("DimBrush"));
            pol.VerticalAlignment = VerticalAlignment.Center;
            pol.Margin = T(0, 0, 10, 0);
            previewOn = new ComboBox { MinWidth = 200, Height = FieldHeight };
            AddTo(por, pol); AddTo(por, previewOn);
            previewOnRow = por;
            AddTo(left, por);
            previewOn.SelectionChanged += (s, e) => { if (!loading && IsAllSelected()) UpdateTilePreview(); };

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
            previewLabel = NewText("", 14, NewColorBrush(V("TextColor")));
            previewLabel.HorizontalAlignment = HorizontalAlignment.Left;
            previewLabel.VerticalAlignment = VerticalAlignment.Bottom;
            previewLabel.Margin = T(12, 0, 0, 10);
            previewLabel.Effect = new DropShadowEffect { BlurRadius = 6, ShadowDepth = 1, Opacity = 0.8 };
            // logo and label must not catch the drag (the preview tells them apart)
            previewLogo.IsHitTestVisible = false;
            previewLabel.IsHitTestVisible = false;
            pg.Children.Add(canvas);
            pg.Children.Add(previewLabel);
            AddTo(left, preview);
            var how = NewText("Drag the background to frame it and the logo to move it; the wheel zooms the background or resizes the logo under the mouse. The preview has the proportions of this category's tiles on this screen.", 11.5, ResBrush("DimBrush"), false, true);
            how.Margin = T(0, 8, 0, 4);
            AddTo(left, how);

            // framing and logo: name and value, the chip on the right; below, the
            // slider with its reset (x), as the fields with a clear button
            Func<string, Slider, TextBlock, Border, Button, StackPanel> placeBlock = (title, slider, value, chip, reset) =>
            {
                var block = NewPanel();
                block.Margin = T(0, 12, 0, 0);
                var head = NewGrid("Auto", "*", "Auto");
                var name = NewText(title, 13, null, true);
                name.VerticalAlignment = VerticalAlignment.Center;
                head.Children.Add(name);
                value.Margin = T(8, 0, 0, 0);
                value.VerticalAlignment = VerticalAlignment.Center;
                SetCol(value, 1);
                head.Children.Add(value);
                SetCol(chip, 2);
                head.Children.Add(chip);
                AddTo(block, head);
                var line = NewGrid("*", "Auto");
                line.Margin = T(0, 4, 0, 0);
                slider.VerticalAlignment = VerticalAlignment.Center;
                line.Children.Add(slider);
                reset.Margin = T(8, 0, 0, 0);
                reset.VerticalAlignment = VerticalAlignment.Center;
                SetCol(reset, 1);
                line.Children.Add(reset);
                AddTo(block, line);
                return block;
            };
            zoomSlider = new Slider { Minimum = 1, Maximum = 4, SmallChange = 0.05, LargeChange = 0.25 };
            zoomText = NewText("", 12, ResBrush("DimBrush"));
            frameChip = NewChip();
            btnFrameReset = NewIconButton(0xE711, "Reset the framing");
            var frameBlock = placeBlock("Framing", zoomSlider, zoomText, frameChip, btnFrameReset);
            frameRow = frameBlock;
            AddTo(left, frameBlock);
            logoSlider = new Slider { Minimum = 0.25, Maximum = 3, SmallChange = 0.05, LargeChange = 0.25 };
            logoScaleText = NewText("", 12, ResBrush("DimBrush"));
            logoChip = NewChip();
            btnLogoReset = NewIconButton(0xE711, "Reset the logo");
            var logoBlock = placeBlock("Logo", logoSlider, logoScaleText, logoChip, btnLogoReset);
            logoRow = logoBlock;
            AddTo(left, logoBlock);

            // a press on the logo moves the logo, anywhere else the background
            preview.MouseLeftButtonDown += (s, e) =>
            {
                if (GetPlaceTarget() == null) return;
                var pt = e.GetPosition(preview);
                if (TestOnLogo(pt))
                {
                    LimitLogoPos();
                    logoPlace.Dragging = true; logoPlace.DragPoint = pt; logoPlace.DragX = logoPlace.X; logoPlace.DragY = logoPlace.Y;
                    logoPlace.Moved = false;
                }
                else
                {
                    if (bgFrame.Bitmap == null) return;
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
                if (bgFrame.Bitmap == null) return;
                e.Handled = true;   // the page must not scroll
                SetFrameZoom(bgFrame.Zoom * Math.Pow(1.1, e.Delta / 120.0), pt);
            };
            logoSlider.ValueChanged += (s, e) =>
            {
                if (logoPlace.Sync || previewLogo.Source == null || GetPlaceTarget() == null) return;
                SetLogoScale(logoSlider.Value);
            };
            zoomSlider.ValueChanged += (s, e) =>
            {
                if (bgFrame.Sync || bgFrame.Bitmap == null || GetPlaceTarget() == null) return;
                SetFrameZoom(zoomSlider.Value);
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
            btnLogoReset.Click += (s, e) => resetPlace(new[] { "LogoPos", "LogoScale" });

            // Row 1, right: the settings of the tile, or of the category under All tiles
            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            Grid.SetRow(sv, 1);
            SetCol(sv, 1);
            grid.Children.Add(sv);
            var details = NewPanel();
            sv.Content = details;

            // Imported game: read-only, can become a normal tile
            importedCard = NewCard("Imported game", "");
            importedCard.Visibility = Visibility.Collapsed;
            AddTo(details, importedCard);
            var txt = NewText("From the old automatic import (written below its marker line), so it cannot be edited here. Make it a normal tile to edit or move it: its images are copied to the category folders. Opening Import turns all of them into normal tiles.", 12.5, ResBrush("DimBrush"), false, true);
            txt.Margin = T(0, 0, 0, 10);
            AddTo(CardPanel(importedCard), txt);
            var btnConvert = NewButton("Make it a normal tile", "AccentButton");
            btnConvert.HorizontalAlignment = HorizontalAlignment.Left;
            btnConvert.Margin = T(0, 0, 0, 10);
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
            allNote = NewText("", 12.5, ResBrush("AccentBrush"), false, true);
            allNote.Margin = T(0, 0, 0, 8);
            AddTo(af, allNote);
            foreach (var k in new[] { "NX", "NY", "IconSize" }) allFields[k] = new TextBox();
            var gridRow = NewPairRow(allFields["NX"], allFields["NY"]);
            // the hints of these rows change with the values: set on their labels by ShowAllTiles
            var gridFormRow = AddTo(af, NewFormRow("Grid", gridRow));
            gridHint = (TextBlock)gridFormRow.Children[0];
            var sizeFormRow = AddTo(af, NewFormRow("Logo size", allFields["IconSize"]));
            sizeHint = (TextBlock)sizeFormRow.Children[0];
            foreach (var kv in allFields)
            {
                string key = kv.Key;
                var tb = kv.Value;
                tb.TextChanged += (s, e) =>
                {
                    if (loading || currentFile == null) return;
                    Core.SetKey(Core.GetCategorySection(GetModel(currentFile)), key, tb.Text.Trim());
                    SetChanged(currentFile);
                    UpdateTilePreview();   // the tile's proportions and logo size
                };
            }
            catColorSwatch = NewButton("", "Swatch", "Pick a colour");
            catTileColor = new TextBox();
            var catColorClear = NewClearButton("No colour: the default tile colour");
            catColorClear.Click += (s, e) => catTileColor.Text = "";   // TextChanged writes it
            var catColorRow = NewFieldRow(catColorSwatch, catTileColor, catColorClear);
            AddTo(af, NewFormRow("Colour", catColorRow, "Colour of the tiles without one of their own (their Colour), used when there is no background image. Empty = the default tile colour (Appearance). R,G,B,A: the A makes it transparent."));
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
                UpdateTileEntries();
                UpdateTilePreview();
            };
            catOpacity = NewOpacityBox("100% (default)");
            AddTo(af, NewFormRow("Background", catOpacity, "Opacity of the colour and the image of the tiles without one of their own (their Background), e.g. lower for a Dashboard with skins over the tiles. Logos, texts and widgets stay as they are."));
            catOpacity.SelectionChanged += (s, e) =>
            {
                if (loading || currentFile == null) return;
                var item = catOpacity.SelectedItem as ComboBoxItem;
                if (item == null) return;
                Core.SetKey(Core.GetCategorySection(GetModel(currentFile)), "TileOpacity", (string)item.Tag);
                SetChanged(currentFile);
            };
            // framing and logo of every tile back to the centre, the ones with their own too
            // the two buttons share the column, as the two fields of Grid
            var placeButtons = NewGrid("*", "8", "*");
            var btnResetLogos = NewButton("Reset logos");
            var btnResetFraming = NewButton("Reset framing");
            SetCol(btnResetFraming, 2);
            placeButtons.Children.Add(btnResetLogos); placeButtons.Children.Add(btnResetFraming);
            var placeFormRow = NewFormRow("Every tile", placeButtons);
            placementHint = (TextBlock)placeFormRow.Children[0];   // its label: the summary is its tooltip
            placementRow = placeFormRow;
            AddTo(af, placementRow);
            btnResetLogos.Click += (s, e) => { if (currentFile != null) ResetCategoryPlace(currentFile, "logo placement", new[] { "LogoPos", "LogoScale" }); };
            btnResetFraming.Click += (s, e) => { if (currentFile != null) ResetCategoryPlace(currentFile, "background framing", new[] { "BgFocus", "BgZoom" }); };

            // Tile card
            tileCard = NewCard("Tile", "");
            AddTo(details, tileCard);
            var f = CardPanel(tileCard);
            tileNote = NewText("", 12.5, ResBrush("AccentBrush"), false, true);
            tileNote.Margin = T(0, 0, 0, 8);
            AddTo(f, tileNote);

            foreach (var k in new[] { "Name", "Command", "Label", "Color", "Tags" }) tileFields[k] = new TextBox();
            AddTo(f, NewFormRow("Name", tileFields["Name"], "Also the name of its images and what search looks at."));
            var cmdRow = NewGrid("*", "Auto");
            cmdRow.Children.Add(tileFields["Command"]);
            var btnCmd = NewButton("Browse...");
            btnCmd.Margin = T(8, 0, 0, 0);
            SetCol(btnCmd, 1);
            cmdRow.Children.Add(btnCmd);
            AddTo(f, NewFormRow("Command", cmdRow, "A program, a .lnk/.url shortcut, a URL (also steam://...), a folder or a Rainmeter bang."));
            // widgets: only in a Dashboard
            widgetKind = new ComboBox();
            foreach (var k in WIDGET_KINDS) widgetKind.Items.Add(new ComboBoxItem { Content = k[1], Tag = k[0] });
            widgetRow = NewFormRow("Widget", widgetKind, "What the tile shows in the Dashboard. A click opens its Command, or the tool that fits.");
            AddTo(f, widgetRow);
            widgetParam = new TextBox();
            widgetHint = NewText("", 11.5, ResBrush("DimBrush"), false, true);
            widgetParamRow = NewFormRow("Widget option", widgetParam, "", widgetHint);
            AddTo(f, widgetParamRow);
            widgetKind.SelectionChanged += (s, e) =>
            {
                UpdateWidgetHint();
                if (loading) return;
                var t = GetCurrentTile();
                var item = widgetKind.SelectedItem as ComboBoxItem;
                if (t == null || item == null) return;
                Core.SetKey(t, "Widget", (string)item.Tag);
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
            var colorClear = NewClearButton("No colour of its own: the one of All tiles");
            colorClear.Click += (s, e) => { if (GetCurrentTile() != null) tileFields["Color"].Text = ""; };
            var colorRow = NewFieldRow(colorSwatch, tileFields["Color"], colorClear);
            AddTo(f, NewFormRow("Colour", colorRow, "Used when there is no background image. Empty = the Colour of All tiles, or taken from the logo, or the default tile colour."));
            tileOpacity = NewOpacityBox("From All tiles");
            AddTo(f, NewFormRow("Background", tileOpacity, "Opacity of the colour and the image of the tile: 0% leaves only the logo, the label or the widget (a skin over the tile, without a box behind it)."));
            tileOpacity.SelectionChanged += (s, e) =>
            {
                if (loading) return;
                var t = GetCurrentTile();
                var item = tileOpacity.SelectedItem as ComboBoxItem;
                if (t == null || item == null) return;
                Core.SetKey(t, "Opacity", (string)item.Tag);
                SetChanged(currentFile);
                UpdateTileDots();
            };
            // cells taken in the grid (Size=<columns>x<rows>)
            sizeCols = new ComboBox();
            sizeRows = new ComboBox();
            for (int n = 1; n <= 8; n++) { sizeCols.Items.Add(n.ToString()); sizeRows.Items.Add(n.ToString()); }
            var sizeRow = NewPairRow(sizeCols, sizeRows);
            AddTo(f, NewFormRow("Size", sizeRow, "Cells the tile takes in the grid: columns \u00D7 rows (at most the grid of the category). The other tiles fill the space around it. Search, Favorites and Recent show it in one cell."));
            SelectionChangedEventHandler sizeChanged = (s, e) =>
            {
                if (loading) return;
                var t = GetCurrentTile();
                if (t == null) return;
                string c = (string)sizeCols.SelectedItem ?? "1", r = (string)sizeRows.SelectedItem ?? "1";
                Core.SetKey(t, "Size", c == "1" && r == "1" ? "" : c + "x" + r);
                SetChanged(currentFile);
                UpdateTilePreview();
            };
            sizeCols.SelectionChanged += sizeChanged;
            sizeRows.SelectionChanged += sizeChanged;
            tagSuggestions = new WrapPanel();
            AddTo(f, NewFormRow("Tags", tileFields["Tags"], "Separated by commas, e.g. multiplayer, coop. Search finds them, and each tag is a chip of the filter bar above the search results.", tagSuggestions));
            // hot key: click, then press the combination (with modifiers)
            tileKeyButton = NewButton("None", "KeyButton", "Click, then press the combination");
            var keyClear = NewClearButton("No hot key");
            var keyRow = NewFieldRow(null, tileKeyButton, keyClear);
            AddTo(f, NewFormRow("Hot key", keyRow, "Starts the tile also while the launcher is hidden, e.g. Ctrl + Alt + 1. Hold the modifiers, then press the key."));
            tileKeyButton.Click += (s, e) =>
            {
                if (GetCurrentTile() == null) return;
                capturing = tileKeyButton;
                tileKeyButton.Content = "Press the keys\u2026";
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
                    if (held.Count > 0) tileKeyButton.Content = Schema.FormatHotKey(string.Join(" ", held)) + " + \u2026";
                    return;
                }
                capturing = null;
                var t = GetCurrentTile();
                if (t == null) return;
                string other = HotKeyUser(value, t);
                if (other != null)
                {
                    tileKeyButton.Content = Schema.FormatHotKey(Core.GetKey(t, "HotKey"));
                    ShowDialog("Raintile", Schema.FormatHotKey(value) + " is already used by " + other + ".");
                    return;
                }
                Core.SetKey(t, "HotKey", value);
                tileKeyButton.Content = Schema.FormatHotKey(value);
                SetChanged(currentFile);
            };
            keyClear.Click += (s, e) =>
            {
                var t = GetCurrentTile();
                if (t == null) return;
                Core.SetKey(t, "HotKey", "");
                tileKeyButton.Content = Schema.FormatHotKey("");
                SetChanged(currentFile);
            };
            foreach (var kind in new[] { "Background", "Logo" })
            {
                var thumb = NewThumb(FieldHeight);
                var choose = NewButton("Choose...");
                var remove = NewClearButton("Remove the " + kind.ToLowerInvariant());
                var row = NewFieldRow(thumb, choose, remove);
                // the path of the image is the tooltip of the label (set with the tile)
                var imageRow = NewFormRow(kind, row);
                AddTo(f, imageRow);
                var pathLabel = (TextBlock)imageRow.Children[0];
                if (kind == "Background") { bgThumb = thumb; bgPath = pathLabel; } else { logoThumb = thumb; logoPath = pathLabel; }
                string k = kind;
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
                        var r = ShowDialog("Raintile", "Move " + Path.GetFileName(path) + " to the Recycle Bin?", new[] { "Remove", "Cancel" });
                        if (r.Button != "Remove") return;
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
            EnableDragReorder(tilesList, it => !((ListTag)it.Tag).Imported && !((ListTag)it.Tag).All, (from, to) =>
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
                    ShowDialog("Raintile", "There is already a tile called '" + n + "'.");
                    tb.Text = t.Name;
                    return;
                }
                if (Core.GetKey(t, "Image") == "" && !string.Equals(n, t.Name, StringComparison.OrdinalIgnoreCase)) Core.RenameTileImages(GetCurrentBase(), t.Name, n);
                t.Name = n;
                SetChanged(currentFile);
                UpdateTilePreview();
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
                if (TestTileName(m, name)) { ShowDialog("Raintile", "There is already a tile called '" + name + "'."); return; }
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
                var r = ShowDialog("Delete tile", "Delete the tile '" + t.Name + "'? Its images stay in Images.", new[] { "Delete", "Cancel" });
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
                    if (t == null) return;
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
