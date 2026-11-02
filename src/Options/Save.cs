// Raintile Options: saving, "Save and refresh" with its progress bar, backup
// and restore, actions of the Info page.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace RaintileOptions
{
    public partial class OptionsApp
    {
        bool needsRefresh;      // tiles written by the lists: the skin needs a refresh
        bool refreshing;
        bool skipSavePrompt;
        DateTime refreshStart;
        DispatcherTimer refreshTimer;
        readonly Random random = new Random();
        double[] planTimes, planValues;
        double planTotal;
        Grid overlay;
        Border progressTrack, progressBar;
        TextBlock progressPercent, progressStage;

        void SaveAll(bool noRefresh = false)
        {
            var changed = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var kv in values)
            {
                string f;
                fileValues.TryGetValue(kv.Key, out f);
                if (kv.Value != f) changed[kv.Key] = kv.Value;
            }
            if (changed.Count > 0)
            {
                Core.WriteSettings(Core.SettingsFile, changed);
                foreach (var kv in changed) fileValues[kv.Key] = kv.Value;
            }
            foreach (var file in changedFiles.Keys.ToList())
            {
                string path = Path.Combine(Core.CategoriesDir, file);
                if (File.Exists(path)) Core.WriteCategory(path, models[file]);
            }
            changedFiles.Clear();
            if (!noRefresh) needsRefresh = false;
            UpdateDirty();
            status.Text = "Saved";
            if (!noRefresh) InvokeRainmeter("!Refresh \"" + Core.Config + "\"");
        }

        // "Save and refresh": saves, shows a progress bar for 2.5 to 3.5 seconds,
        // then closes the window and refreshes the skin, which shows the launcher
        // once it has reloaded. The bar goes through a few random steps, some
        // quick, some slow, like a real loading.
        void InitProgress()
        {
            overlay = (Grid)win.FindName("Overlay");
            progressTrack = (Border)win.FindName("ProgressTrack");
            progressBar = (Border)win.FindName("ProgressBar");
            progressPercent = (TextBlock)win.FindName("ProgressPercent");
            progressStage = (TextBlock)win.FindName("ProgressStage");
            refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(30) };
            refreshTimer.Tick += (s, e) =>
            {
                double p = PlannedProgress((DateTime.Now - refreshStart).TotalMilliseconds);
                progressBar.Width = p * progressTrack.ActualWidth;
                progressPercent.Text = (int)Math.Floor(p * 100) + "%";
                progressStage.Text = p < 0.3 ? "Saving the settings\u2026" : p < 0.85 ? "Refreshing the skin\u2026" : "Opening the launcher\u2026";
                if (p >= 1)
                {
                    refreshTimer.Stop();
                    overlay.Visibility = Visibility.Collapsed;
                    refreshing = false;
                    // the launcher shows itself when it has reloaded; the window
                    // closes first, so the launcher does not open over it
                    WriteShowOnLoad();
                    win.Close();
                    InvokeRainmeter("!Refresh \"" + Core.Config + "\"");
                }
            };
        }

        static void WriteShowOnLoad()
        {
            try { File.WriteAllText(Path.Combine(Core.Generated, "ShowOnLoad"), "", Core.Utf8); } catch { }
        }

        // Steps of the bar: times (ms from the start) and values (0-1), both rising
        void NewProgressPlan()
        {
            double total = 2500 + random.Next(0, 1001);
            int steps = 5 + random.Next(0, 3);
            var timeW = Enumerable.Range(0, steps).Select(_ => 0.4 + random.NextDouble()).ToArray();
            // some steps barely move: pauses
            var valueW = Enumerable.Range(0, steps).Select(_ => random.NextDouble() < 0.3 ? 0.02 : 0.2 + random.NextDouble()).ToArray();
            double tSum = timeW.Sum(), vSum = valueW.Sum(), t = 0, v = 0;
            planTimes = new double[steps + 1];
            planValues = new double[steps + 1];
            for (int i = 0; i < steps; i++)
            {
                t += timeW[i] / tSum * total;
                v += valueW[i] / vSum;
                planTimes[i + 1] = t;
                planValues[i + 1] = v;
            }
            planValues[steps] = 1.0;
            planTotal = total;
        }

        // Progress (0-1) after 'elapsed' ms: each step eases out
        double PlannedProgress(double elapsed)
        {
            if (elapsed >= planTotal) return 1.0;
            for (int i = 0; i < planTimes.Length - 1; i++)
            {
                if (elapsed < planTimes[i + 1])
                {
                    double f = (elapsed - planTimes[i]) / (planTimes[i + 1] - planTimes[i]);
                    f = 1 - (1 - f) * (1 - f);
                    return planValues[i] + (planValues[i + 1] - planValues[i]) * f;
                }
            }
            return 1.0;
        }

        void StartSaveAndRefresh()
        {
            if (refreshing) return;
            needsRefresh = false;
            SaveAll(true);   // the refresh comes at the end of the bar
            refreshing = true;
            NewProgressPlan();
            progressBar.Width = 0;
            progressPercent.Text = "0%";
            progressStage.Text = "Saving the settings\u2026";
            overlay.Visibility = Visibility.Visible;
            refreshStart = DateTime.Now;
            refreshTimer.Start();
        }

        // Info > Back up: the data folder to a zip (unsaved changes are saved first)
        void InvokeBackup()
        {
            if (Core.Data == Core.Resources) { ShowDialog("Raintile", "Your data folder is not ready yet: refresh the skin once, then try again."); return; }
            if (dirtySettings) SaveAll(true);
            var dlg = new Microsoft.Win32.SaveFileDialog
            {
                Filter = "Raintile backup|*.zip",
                FileName = "Raintile-backup-" + DateTime.Now.ToString("yyyy-MM-dd") + ".zip",
                InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            };
            if (dlg.ShowDialog(win) != true) return;
            try
            {
                Core.NewDataBackup(Core.Data, dlg.FileName);
                ShowDialog("Raintile", "Backup saved:\r\n" + dlg.FileName);
            }
            catch (Exception e) { ShowDialog("Raintile", "The backup could not be saved: " + e.Message); }
        }

        // Info > Restore: replaces the data folder with a backup, then the window
        // closes and the skin reloads
        void InvokeRestore()
        {
            if (Core.Data == Core.Resources) { ShowDialog("Raintile", "Your data folder is not ready yet: refresh the skin once, then try again."); return; }
            string zip = SelectFile("Raintile backup|*.zip|All files|*.*");
            if (zip == null) return;
            string problem = Core.TestDataBackup(zip);
            if (problem != null) { ShowDialog("Raintile", "This file can not be restored: " + problem + "."); return; }
            var r = ShowDialog("Restore backup", "Replace your settings, categories, images, favorites and usage with this backup?\r\n\r\n" +
                "Your current data is not deleted: it is kept in a folder next to it. Unsaved changes in this window are lost.", new[] { "Restore", "Cancel" });
            if (r.Button != "Restore") return;
            string kept;
            try { kept = Core.RestoreDataBackup(zip, Core.Data); }
            catch (Exception e) { ShowDialog("Raintile", "The backup could not be restored, nothing was changed: " + e.Message); return; }
            ShowDialog("Raintile", "Backup restored. Your previous data is in:\r\n" + kept);
            // the launcher shows itself once reloaded; nothing left to save here
            WriteShowOnLoad();
            skipSavePrompt = true;
            win.Close();
            InvokeRainmeter("!Refresh \"" + Core.Config + "\"");
        }

        void InvokeAction(string action)
        {
            try
            {
                switch (action)
                {
                    case "Backup": InvokeBackup(); break;
                    case "Restore": InvokeRestore(); break;
                    case "OpenSettings": Process.Start("notepad.exe", "\"" + Core.SettingsFile + "\""); break;
                    case "OpenFolder": Process.Start("explorer.exe", "\"" + Core.Data + "\""); break;
                    case "OpenSkinFolder": Process.Start("explorer.exe", "\"" + Path.GetDirectoryName(Core.Resources) + "\""); break;
                    case "OpenRainmeter": InvokeRainmeter("!Manage"); break;
                    case "OpenGuide": OpenUrl("https://github.com/Derek3rd/raintile/blob/main/docs/Guide.md"); break;
                }
            }
            catch (Exception e) { ShowDialog("Raintile", e.Message); }
        }
    }
}
