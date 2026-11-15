// Raintile Options: "Find online..." in the tile editor. A window with the
// images found for the tile (see Art.cs): click one, then Use it; it is
// downloaded and becomes the tile's background or logo, like a picked file.

using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace RaintileOptions
{
    public partial class OptionsApp
    {
        // kind: "Background" or "Logo"
        void FindTileArt(string kind)
        {
            var t = GetCurrentTile();
            if (t == null) return;
            string b = GetCurrentBase();
            string name = t.Name, command = Core.GetKey(t, "Command"), source = Core.GetKey(t, "Source");
            string key = Core.UnprotectSecret(V("SteamGridDBKey"));
            bool background = kind == "Background";

            var d = new Window
            {
                Title = kind + " for " + name, Owner = win, WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Width = 820, Height = 600, ShowInTaskbar = false,
                Background = ResBrush("CardBg"), Foreground = ResBrush("TextBrush"),
                FontFamily = new FontFamily("Segoe UI"), FontSize = 13,   // ui-exempt: base size of a window, as the main window
            };
            d.SourceInitialized += (s, e) => SetDarkTitle(d);
            var root = new DockPanel { Margin = Gap.Dialog };
            d.Content = root;

            var status = NewHelp("Searching...");
            status.Margin = T(0, 0, 0, Gap.Text);
            DockPanel.SetDock(status, Dock.Top);
            root.Children.Add(status);

            var bar = NewPanel(Orientation.Horizontal);
            bar.HorizontalAlignment = HorizontalAlignment.Right;
            bar.Margin = T(0, Gap.DialogBar, 0, 0);
            DockPanel.SetDock(bar, Dock.Bottom);
            root.Children.Add(bar);
            var use = NewButton("Use it", "AccentButton");
            use.MinWidth = 90;
            use.IsEnabled = false;
            var cancel = NewButton("Cancel");
            cancel.MinWidth = 90;
            cancel.Margin = T(Gap.Control, 0, 0, 0);
            cancel.Click += (s, e) => d.Close();
            AddTo(bar, use);
            AddTo(bar, cancel);

            var wrap = new WrapPanel();
            root.Children.Add(new ScrollViewer { Content = wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });

            ArtChoice chosen = null;
            Border chosenBox = null;
            double w = background ? 236 : 136, h = background ? 124 : 112;

            Action<List<ArtChoice>> show = list =>
            {
                if (list.Count == 0)
                {
                    status.Text = "Nothing found for " + name + "." + (key == "" ? " A SteamGridDB key (Options > Import) finds more." : "");
                    return;
                }
                status.Text = list.Count + " found: click one, then Use it." + (key == "" ? " A SteamGridDB key (Options > Import) finds more." : "");
                bool anyLowRes = false;
                foreach (var c in list)
                {
                    var img = new Image { Stretch = Stretch.Uniform, Width = w, Height = h - 22 };
                    try
                    {
                        var bmp = new BitmapImage();
                        bmp.BeginInit();
                        bmp.UriSource = new Uri(c.Thumb);
                        bmp.DecodePixelWidth = (int)(w * 1.5);
                        bmp.CacheOption = BitmapCacheOption.OnLoad;
                        bmp.EndInit();
                        img.Source = bmp;
                    }
                    catch { }
                    var panel = NewPanel();
                    AddTo(panel, img);
                    // a background: its size, in the accent colour when it is too
                    // small for this screen (the note of the Background field)
                    bool lowRes = background && c.Width > 0 && BackgroundLowResNote(new[] { c.Width, c.Height }, t) != "";
                    anyLowRes |= lowRes;
                    string size = background && c.Width > 0 ? " " + Dot + " " + c.Width + Times + c.Height + (lowRes ? ", low resolution" : "") : "";
                    var label = NewText(c.Source + size, Fs.Badge, ResBrush(lowRes ? "AccentBrush" : "DimBrush"));
                    label.HorizontalAlignment = HorizontalAlignment.Center;
                    AddTo(panel, label);
                    var box = new Border
                    {
                        Child = panel, Padding = T(Gap.Icon), Margin = T(0, 0, Gap.Text, Gap.Text), CornerRadius = new CornerRadius(6),
                        BorderThickness = T(2), BorderBrush = Brushes.Transparent, Background = ResBrush("FieldBg"),
                        Cursor = System.Windows.Input.Cursors.Hand,
                    };
                    var choice = c;
                    box.MouseLeftButtonUp += (s, e) =>
                    {
                        if (chosenBox != null) chosenBox.BorderBrush = Brushes.Transparent;
                        chosen = choice;
                        chosenBox = box;
                        box.BorderBrush = ResBrush("AccentBrush");
                        use.IsEnabled = true;
                    };
                    wrap.Children.Add(box);
                }
                if (anyLowRes) status.Text += " Low resolution: enlarged more than " + LowResLimit.ToString("0.#", Inv) + Times + " on this screen, it looks blurry.";
            };

            use.Click += async (s, e) =>
            {
                if (chosen == null) return;
                use.IsEnabled = false;
                status.Text = "Downloading...";
                string url = chosen.Url, file = null;
                try { file = await Task.Run(() => Art.Download(url)); }
                catch (Exception ex) { status.Text = "Download failed: " + ex.Message; use.IsEnabled = true; return; }
                try
                {
                    Core.CopyTileImage(b, kind.ToLowerInvariant(), name, file);
                    Core.SetKey(t, kind, "");   // the default image just copied applies
                    if (background) ResetFraming(t);
                    SetChanged(currentFile);
                    UpdateTilePreview();
                }
                catch (Exception ex) { status.Text = ex.Message; use.IsEnabled = true; return; }
                finally { try { Directory.Delete(Path.GetDirectoryName(file), true); } catch { } }
                d.Close();
            };

            d.ContentRendered += async (s, e) =>
            {
                List<ArtChoice> list;
                try { list = await Task.Run(() => Art.Find(background ? "background" : "logo", name, command, source, key)); }
                catch (Exception ex) { status.Text = "The search failed: " + ex.Message; return; }
                show(list);
            };
            d.KeyDown += (s, e) => { if (e.Key == System.Windows.Input.Key.Escape) d.Close(); };
            d.ShowDialog();
        }
    }
}
