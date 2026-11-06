// Raintile Options: "Auto find images" under All tiles. For every tile of the
// category without a background (or a logo) it searches online (Art.cs) and
// uses the first image found, one tile after the other, with a progress bar
// and a Stop button. Widgets are left out.

using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;

namespace RaintileOptions
{
    public partial class OptionsApp
    {
        FrameworkElement autoArtRow;
        Button autoArtBg, autoArtLogo, autoArtStop;
        Border autoArtTrack, autoArtFill;
        TextBlock autoArtStatus;
        bool autoArtBusy, autoArtStopAsked;

        FrameworkElement NewAutoArtRow()
        {
            var panel = NewPanel();
            var buttons = NewGrid("*", "8", "*", "8", "Auto");
            autoArtBg = NewButton("Background", "", "Search a background for every tile of the category without one");
            autoArtLogo = NewButton("Logo", "", "Search a logo for every tile of the category without one");
            autoArtStop = NewButton("Stop");
            autoArtStop.Visibility = Visibility.Collapsed;
            SetCol(autoArtLogo, 2);
            SetCol(autoArtStop, 4);
            buttons.Children.Add(autoArtBg); buttons.Children.Add(autoArtLogo); buttons.Children.Add(autoArtStop);
            AddTo(panel, buttons);
            autoArtFill = new Border { Width = 0, HorizontalAlignment = HorizontalAlignment.Left, CornerRadius = new CornerRadius(3), Background = ResBrush("AccentBrush") };
            autoArtTrack = new Border
            {
                Height = 6, Margin = T(0, 8, 0, 0), CornerRadius = new CornerRadius(3), Background = ResBrush("FieldBg"),
                Child = autoArtFill, Visibility = Visibility.Collapsed,
            };
            AddTo(panel, autoArtTrack);
            autoArtStatus = NewText("", 11.5, ResBrush("DimBrush"), false, true);
            autoArtStatus.Margin = T(0, 4, 0, 0);
            autoArtStatus.Visibility = Visibility.Collapsed;
            AddTo(panel, autoArtStatus);
            autoArtBg.Click += (s, e) => AutoFindArt("Background");
            autoArtLogo.Click += (s, e) => AutoFindArt("Logo");
            autoArtStop.Click += (s, e) => { autoArtStopAsked = true; autoArtStop.IsEnabled = false; };
            return NewFormRow("Auto find images", panel,
                "Every tile of the category without a background (or a logo) gets the first image found online: Steam, SteamGridDB (with the key; only a game or app of the same name), Dashboard Icons, the website of a link.");
        }

        void SetAutoArtProgress(double part)
        {
            double full = autoArtTrack.ActualWidth > 0 ? autoArtTrack.ActualWidth : 300;
            autoArtFill.Width = Math.Max(0, Math.Min(1, part)) * full;
        }

        async void AutoFindArt(string kind)
        {
            if (currentFile == null || autoArtBusy) return;
            string file = currentFile, b = GetCurrentBase();
            var model = GetModel(file);
            var tiles = Core.GetTiles(model)
                .Where(t => Core.GetKey(t, "Widget").Trim() == "" && Core.GetTileImage(b, t, kind) == null)
                .ToList();
            autoArtStatus.Visibility = Visibility.Visible;
            if (tiles.Count == 0)
            {
                autoArtStatus.Text = "Every tile of this category has a " + kind.ToLowerInvariant() + ".";
                return;
            }
            string key = Core.UnprotectSecret(V("SteamGridDBKey"));
            string lower = kind.ToLowerInvariant();
            autoArtBusy = true;
            autoArtStopAsked = false;
            autoArtBg.IsEnabled = autoArtLogo.IsEnabled = false;
            autoArtStop.IsEnabled = true;
            autoArtStop.Visibility = Visibility.Visible;
            autoArtTrack.Visibility = Visibility.Visible;
            SetAutoArtProgress(0);
            int done = 0, found = 0;
            try
            {
                foreach (var t in tiles)
                {
                    if (autoArtStopAsked) break;
                    string name = t.Name, command = Core.GetKey(t, "Command"), source = Core.GetKey(t, "Source");
                    autoArtStatus.Text = "Searching " + (done + 1) + " of " + tiles.Count + ": " + name + "\u2026";
                    string got = await Task.Run(() =>
                    {
                        try
                        {
                            foreach (var c in Art.Find(lower, name, command, source, key, true))
                            {
                                try { return Art.Download(c.Url); } catch { }
                            }
                        }
                        catch { }
                        return null;
                    });
                    if (got != null)
                    {
                        try
                        {
                            Core.CopyTileImage(b, lower, name, got);
                            Core.SetKey(t, kind, "");   // the default image just copied applies
                            if (kind == "Background") ResetFraming(t);
                            found++;
                        }
                        catch { }
                        finally { try { Directory.Delete(Path.GetDirectoryName(got), true); } catch { } }
                    }
                    done++;
                    SetAutoArtProgress((double)done / tiles.Count);
                }
            }
            finally
            {
                autoArtBusy = false;
                autoArtBg.IsEnabled = autoArtLogo.IsEnabled = true;
                autoArtStop.Visibility = Visibility.Collapsed;
            }
            if (found > 0)
            {
                SetChanged(file);
                if (currentFile == file) RefreshTiles(Math.Max(0, tilesList.SelectedIndex));
            }
            autoArtStatus.Text = (autoArtStopAsked ? "Stopped. " : "") + "Found " + found + " of " + done
                + (found > 0 ? ": save and refresh to see them in the launcher." : ".")
                + (key == "" && found < done ? " A SteamGridDB key (Options > Import) finds more." : "");
        }
    }
}
