// Raintile Options: the widget gallery (Widgets page). The list is
// widgets/index.json of the Raintile repository; each entry points to files on
// GitHub, in this repository or in its author's. Custom widgets are downloaded
// to Widgets\<id>\ in the data folder (and can be added as a tile to a category); skins
// (.rmskin) open with the Rainmeter installer.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;

namespace RaintileOptions
{
    class MarketEntry
    {
        public string Id, Name, Author, Description, Version, Kind, Base, Page, Skin, Package;
        public List<string> Files = new List<string>();
    }

    public partial class OptionsApp
    {
        public const string MarketIndex = "https://raw.githubusercontent.com/" + Core.Repository + "/main/widgets/index.json";
        StackPanel marketList;
        TextBlock marketStatus;

        static string WidgetsDir { get { return Path.Combine(Core.Data, "Widgets"); } }

        // Only files on GitHub over https: this repository or another author's
        static bool TestMarketUrl(string url)
        {
            Uri u;
            if (!Uri.TryCreate(url ?? "", UriKind.Absolute, out u) || u.Scheme != "https") return false;
            return u.Host == "raw.githubusercontent.com" || u.Host == "github.com" || u.Host == "objects.githubusercontent.com";
        }

        static bool SafeId(string id) { return Regex.IsMatch(id ?? "", @"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") && !id.Contains(".."); }
        static bool SafeFile(string f) { return Regex.IsMatch(f ?? "", @"^[A-Za-z0-9][A-Za-z0-9 ._-]{0,99}$") && !f.Contains(".."); }

        static List<MarketEntry> ParseMarket(string json)
        {
            var list = new List<MarketEntry>();
            var root = Json.Parse(json) as Dictionary<string, object>;
            object items;
            if (root == null || !root.TryGetValue("widgets", out items) || !(items is object[])) return list;
            foreach (var o in (object[])items)
            {
                var d = o as Dictionary<string, object>;
                if (d == null) continue;
                var e = new MarketEntry
                {
                    Id = Json.Str(d, "id"), Name = Json.Str(d, "name"), Author = Json.Str(d, "author"),
                    Description = Json.Str(d, "description"), Version = Json.Str(d, "version"), Kind = Json.Str(d, "kind"),
                    Base = Json.Str(d, "base"), Page = Json.Str(d, "page"), Skin = Json.Str(d, "skin"), Package = Json.Str(d, "package"),
                };
                object files;
                if (d.TryGetValue("files", out files) && files is object[])
                    foreach (var f in (object[])files) e.Files.Add(Convert.ToString(f));
                if (!SafeId(e.Id) || e.Name == "") continue;
                if (e.Kind == "custom" && (!TestMarketUrl(e.Base) || e.Files.Count == 0 || !e.Files.All(SafeFile))) continue;
                if (e.Kind == "skin" && !TestMarketUrl(e.Package)) continue;
                if (e.Kind != "custom" && e.Kind != "skin") continue;
                list.Add(e);
            }
            return list;
        }

        static string InstalledVersion(MarketEntry e)
        {
            string v = Path.Combine(WidgetsDir, e.Id, ".version");
            if (File.Exists(v)) { try { return File.ReadAllText(v).Trim(); } catch { } }
            return Directory.Exists(Path.Combine(WidgetsDir, e.Id)) ? "?" : null;
        }

        static WebClient NewWebClient()
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var wc = new WebClient { Encoding = System.Text.Encoding.UTF8 };
            wc.Headers.Add("User-Agent", "Raintile");
            return wc;
        }

        Border NewMarketCard()
        {
            var card = NewCard("Widget gallery", "Widgets made for Raintile, from its repository and from other authors on GitHub. A widget can run programs like any Rainmeter skin: install only the ones you trust.");
            var f = CardPanel(card);
            var head = NewGrid("Auto", "*");
            head.Margin = T(0, 2, 0, 10);
            var reload = NewButton("Load the list");
            head.Children.Add(reload);
            marketStatus = NewText("", 12, ResBrush("DimBrush"), false, true);
            marketStatus.VerticalAlignment = VerticalAlignment.Center;
            marketStatus.Margin = T(12, 0, 0, 0);
            SetCol(marketStatus, 1);
            head.Children.Add(marketStatus);
            AddTo(f, head);
            marketList = NewPanel();
            AddTo(f, marketList);
            var folder = NewButton("Open the Widgets folder", "LinkButton");
            folder.HorizontalAlignment = HorizontalAlignment.Left;
            folder.Margin = T(0, 8, 0, 6);
            folder.Click += (s, e) => { Directory.CreateDirectory(WidgetsDir); System.Diagnostics.Process.Start("explorer.exe", "\"" + WidgetsDir + "\""); };
            AddTo(f, folder);
            reload.Click += (s, e) => LoadMarket();
            LoadMarket();
            return card;
        }

        async void LoadMarket()
        {
            marketStatus.Text = "Loading\u2026";
            marketList.Children.Clear();
            string json;
            try
            {
                using (var wc = NewWebClient()) json = await wc.DownloadStringTaskAsync(new Uri(MarketIndex));
            }
            catch (Exception e)
            {
                marketStatus.Text = "The list could not be loaded: " + e.Message;
                return;
            }
            List<MarketEntry> entries;
            try { entries = ParseMarket(json); }
            catch (Exception e) { marketStatus.Text = "The list could not be read: " + e.Message; return; }
            marketStatus.Text = entries.Count + " widget" + (entries.Count != 1 ? "s" : "") + " in the gallery.";
            foreach (var e in entries) marketList.Children.Add(NewMarketRow(e));
        }

        UIElement NewMarketRow(MarketEntry e)
        {
            var row = NewGrid("*", "Auto");
            row.Margin = T(0, 6);
            var texts = NewPanel();
            texts.VerticalAlignment = VerticalAlignment.Center;
            var title = NewPanel(Orientation.Horizontal);
            AddTo(title, NewText(e.Name, 13.5));
            string sub = (e.Kind == "skin" ? "skin" : "widget") + (e.Author != "" ? "   \u00B7   by " + e.Author : "") + (e.Version != "" ? "   \u00B7   " + e.Version : "");
            AddTo(texts, title);
            AddTo(texts, NewText(sub, 11.5, ResBrush("DimBrush")));
            if (e.Description != "") AddTo(texts, NewText(e.Description, 12, ResBrush("DimBrush"), false, true));
            row.Children.Add(texts);
            var bar = NewPanel(Orientation.Horizontal);
            bar.VerticalAlignment = VerticalAlignment.Center;
            SetCol(bar, 1);
            row.Children.Add(bar);
            string installed = e.Kind == "custom" ? InstalledVersion(e) : null;
            if (e.Kind == "custom" && installed != null)
            {
                if (e.Version != "" && installed != e.Version)
                {
                    var update = NewButton("Update", "AccentButton");
                    update.Margin = T(8, 0, 0, 0);
                    update.Click += async (s, a) => await InstallWidget(e, false);
                    AddTo(bar, update);
                }
                var add = NewButton("Add as a tile");
                add.Margin = T(8, 0, 0, 0);
                add.Click += (s, a) => AddWidgetTile(e);
                AddTo(bar, add);
                var remove = NewButton("Remove");
                remove.Margin = T(8, 0, 0, 0);
                remove.Click += (s, a) =>
                {
                    var r = ShowDialog("Raintile", "Remove the widget " + e.Name + "? Its folder goes to the Recycle Bin; tiles using it stay empty.", new[] { "Remove", "Cancel" });
                    if (r.Button != "Remove") return;
                    try { Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory(Path.Combine(WidgetsDir, e.Id), Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs, Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin); }
                    catch (Exception ex) { ShowDialog("Raintile", ex.Message); }
                    LoadMarket();
                };
                AddTo(bar, remove);
            }
            else
            {
                var install = NewButton("Install", "AccentButton");
                install.Margin = T(8, 0, 0, 0);
                install.Click += async (s, a) =>
                {
                    install.IsEnabled = false;
                    await InstallWidget(e, true);
                    install.IsEnabled = true;
                };
                AddTo(bar, install);
            }
            if (TestMarketUrl(e.Page))
            {
                var page = NewButton("Page", "LinkButton");
                page.Margin = T(8, 0, 0, 0);
                page.VerticalAlignment = VerticalAlignment.Center;
                page.Click += (s, a) => OpenUrl(e.Page);
                AddTo(bar, page);
            }
            return new Border { BorderBrush = ResBrush("LineBrush"), BorderThickness = T(0, 1, 0, 0), Child = row, Padding = T(0, 4) };
        }

        async Task InstallWidget(MarketEntry e, bool offerTile)
        {
            if (e.Kind == "skin")
            {
                // an .rmskin: the Rainmeter installer takes over
                string folder = Path.Combine(Path.GetTempPath(), "Raintile-widget-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(folder);
                string dest = Path.Combine(folder, e.Id + ".rmskin");
                marketStatus.Text = "Downloading " + e.Name + "\u2026";
                try { using (var wc = NewWebClient()) await wc.DownloadFileTaskAsync(new Uri(e.Package), dest); }
                catch (Exception ex) { marketStatus.Text = "Download failed: " + ex.Message; return; }
                if (!Core.TestRmskinPackage(dest)) { marketStatus.Text = "The downloaded file is not a Rainmeter package."; return; }
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(dest) { UseShellExecute = true });
                marketStatus.Text = "The Rainmeter installer opened " + e.Name + ".";
                if (offerTile && e.Skin != "") AddWidgetTile(e);
                return;
            }
            // a custom widget: its files in Widgets\<id>\ (a new folder first,
            // then moved in place)
            string dir = Path.Combine(WidgetsDir, e.Id);
            string tmp = dir + ".download";
            marketStatus.Text = "Downloading " + e.Name + "\u2026";
            try
            {
                if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
                Directory.CreateDirectory(tmp);
                using (var wc = NewWebClient())
                {
                    foreach (var file in e.Files)
                    {
                        var url = new Uri(e.Base.TrimEnd('/') + "/" + Uri.EscapeDataString(file));
                        if (!TestMarketUrl(url.ToString())) throw new Exception("not a GitHub address: " + url);
                        await wc.DownloadFileTaskAsync(url, Path.Combine(tmp, file));
                    }
                }
                if (!File.Exists(Path.Combine(tmp, e.Id + ".ini"))) throw new Exception("the widget has no " + e.Id + ".ini");
                File.WriteAllText(Path.Combine(tmp, ".version"), e.Version, Core.Utf8);
                if (Directory.Exists(dir)) Directory.Delete(dir, true);
                Directory.Move(tmp, dir);
            }
            catch (Exception ex)
            {
                try { if (Directory.Exists(tmp)) Directory.Delete(tmp, true); } catch { }
                marketStatus.Text = "The widget could not be installed: " + ex.Message;
                return;
            }
            needsRefresh = true;
            UpdateDirty();
            marketStatus.Text = e.Name + " installed: save and refresh to see it.";
            if (offerTile) AddWidgetTile(e);
            LoadMarket();
        }

        // A tile with the widget, at the end of a category (asked first): the
        // category open last, otherwise the example Dashboard, otherwise the first
        void AddWidgetTile(MarketEntry e)
        {
            var files = Core.GetCategoryFiles().Select(f => f.Name).ToList();
            if (files.Count == 0)
            {
                ShowDialog("Raintile", "There are no categories yet: create one, then add the widget.");
                return;
            }
            string file = currentFile != null && files.Contains(currentFile) ? currentFile
                : files.FirstOrDefault(f => string.Equals(f, "Dashboard.ini", StringComparison.OrdinalIgnoreCase)) ?? files[0];
            var r = ShowDialog("Raintile", "Add " + e.Name + " to " + GetCategoryName(file) + "? You can drag it to another category afterwards.", new[] { "Add", "Not now" });
            if (r.Button != "Add") return;
            var m = GetModel(file);
            string name = Core.GetTileName(e.Name);
            for (int n = 2; TestTileName(m, name); n++) name = Core.GetTileName(e.Name) + " " + n;
            var t = new IniSection { Name = name };
            Core.SetKey(t, "Widget", e.Kind);
            Core.SetKey(t, "Param", e.Kind == "skin" ? e.Skin : e.Id);
            m.Sections.Add(t);
            Core.WriteCategory(Path.Combine(Core.CategoriesDir, file), m);
            changedFiles.Remove(file);
            needsRefresh = true;
            UpdateDirty();
            marketStatus.Text = e.Name + " is in " + GetCategoryName(file) + ": save and refresh to see it.";
        }
    }
}
