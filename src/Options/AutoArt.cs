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
        Button autoArtAll, autoArtBg, autoArtLogo, autoArtStop;
        Border autoArtTrack, autoArtFill;
        TextBlock autoArtStatus;
        bool autoArtBusy, autoArtStopAsked;

        FrameworkElement NewAutoArtRow()
        {
            var panel = NewPanel();
            autoArtAll = NewButton("All");
            autoArtBg = NewButton("Background");
            autoArtLogo = NewButton("Logo");
            AddTo(panel, NewEqualButtons(autoArtAll, autoArtBg, autoArtLogo));
            // Stop: under the buttons, with the progress, while a search runs
            autoArtStop = NewButton("Stop");
            autoArtStop.HorizontalAlignment = HorizontalAlignment.Left;
            autoArtStop.Margin = T(0, Gap.Control, 0, 0);
            autoArtStop.Visibility = Visibility.Collapsed;
            autoArtFill = new Border { Width = 0, HorizontalAlignment = HorizontalAlignment.Left, CornerRadius = new CornerRadius(3), Background = ResBrush("AccentBrush") };
            autoArtTrack = new Border
            {
                Height = 6, Margin = T(0, 8, 0, 0), CornerRadius = new CornerRadius(3), Background = ResBrush("FieldBg"),
                Child = autoArtFill, Visibility = Visibility.Collapsed,
            };
            AddTo(panel, autoArtTrack);
            autoArtStatus = NewHelp("");
            autoArtStatus.Margin = T(0, 4, 0, 0);
            autoArtStatus.Visibility = Visibility.Collapsed;
            AddTo(panel, autoArtStatus);
            AddTo(panel, autoArtStop);
            autoArtAll.Click += (s, e) => AutoFindArt(new[] { "Background", "Logo" });
            autoArtBg.Click += (s, e) => AutoFindArt(new[] { "Background" });
            autoArtLogo.Click += (s, e) => AutoFindArt(new[] { "Logo" });
            autoArtStop.Click += (s, e) => { autoArtStopAsked = true; autoArtStop.IsEnabled = false; };
            return NewFormRow("Auto find images", panel,
                "Every tile of the category without a background (or a logo) gets the first image found online: Steam, SteamGridDB (with the key; only a game or app of the same name), Dashboard Icons, the website of a link. " +
                "All looks for both, Background or Logo only for that one.");
        }

        void SetAutoArtProgress(double part)
        {
            double full = autoArtTrack.ActualWidth > 0 ? autoArtTrack.ActualWidth : 300;
            autoArtFill.Width = Math.Max(0, Math.Min(1, part)) * full;
        }

        // kinds: "Background", "Logo" or both (All): each tile gets what it is missing
        async void AutoFindArt(string[] kinds)
        {
            if (currentFile == null || autoArtBusy) return;
            string file = currentFile, b = GetCurrentBase();
            var model = GetModel(file);
            var tiles = Core.GetTiles(model)
                .Where(t => Core.GetKey(t, "Widget").Trim() == "" && kinds.Any(k => Core.GetTileImage(b, t, k) == null))
                .ToList();
            autoArtStatus.Visibility = Visibility.Visible;
            string what = kinds.Length > 1 ? "background and a logo" : kinds[0].ToLowerInvariant();
            if (tiles.Count == 0)
            {
                autoArtStatus.Text = "Every tile of this category has a " + what + ".";
                return;
            }
            string key = Core.UnprotectSecret(V("SteamGridDBKey"));
            autoArtBusy = true;
            autoArtStopAsked = false;
            autoArtAll.IsEnabled = autoArtBg.IsEnabled = autoArtLogo.IsEnabled = false;
            autoArtStop.IsEnabled = true;
            autoArtStop.Visibility = Visibility.Visible;
            autoArtTrack.Visibility = Visibility.Visible;
            SetAutoArtProgress(0);
            int done = 0, images = 0, wanted = 0;
            try
            {
                foreach (var t in tiles)
                {
                    if (autoArtStopAsked) break;
                    string name = t.Name, command = Core.GetKey(t, "Command"), source = Core.GetKey(t, "Source");
                    autoArtStatus.Text = "Searching " + (done + 1) + " of " + tiles.Count + ": " + name + "...";
                    foreach (var kind in kinds)
                    {
                        if (autoArtStopAsked) break;
                        if (Core.GetTileImage(b, t, kind) != null) continue;
                        wanted++;
                        string lower = kind.ToLowerInvariant();
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
                        if (got == null) continue;
                        try
                        {
                            Core.CopyTileImage(b, lower, name, got);
                            Core.SetKey(t, kind, "");   // the default image just copied applies
                            if (kind == "Background") ResetFraming(t);
                            images++;
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
                autoArtAll.IsEnabled = autoArtBg.IsEnabled = autoArtLogo.IsEnabled = true;
                autoArtStop.Visibility = Visibility.Collapsed;
            }
            if (images > 0)
            {
                SetChanged(file);
                if (currentFile == file) RefreshTiles(Math.Max(0, tilesList.SelectedIndex));
            }
            autoArtStatus.Text = (autoArtStopAsked ? "Stopped. " : "") + "Found " + images + " of " + wanted + " images (" + done + " tiles)"
                + (images > 0 ? ": save and refresh to see them in the launcher." : ".")
                + (key == "" && images < wanted ? " A SteamGridDB key (Options > Import) finds more." : "");
        }
    }
}
