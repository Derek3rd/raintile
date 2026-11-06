// Raintile Options: "Order" under All tiles. The tiles of the category sorted
// by name, by when they were added, by play (last launch, launches, play
// time): once with "Sort now", or always with "Keep sorted" (Sort= in
// [Category]: the launcher sorts them each time it loads or opens, and here
// they are sorted again after every change; dragging is off).

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;

namespace RaintileOptions
{
    public partial class OptionsApp
    {
        // key of Sort=, shown name; the same keys as the launcher (Raintile.lua M.SORTS)
        static readonly string[][] SORTS =
        {
            new[] { "name", "Name A\u2013Z" },
            new[] { "name-desc", "Name Z\u2013A" },
            new[] { "added", "Recently added" },
            new[] { "recent", "Recently played" },
            new[] { "played", "Most launched" },
            new[] { "playtime", "Most play time" },
        };

        FrameworkElement sortRow;
        ComboBox sortBox;
        CheckBox sortKeep;
        Button sortNow;
        bool sortLoading;

        FrameworkElement NewSortRow()
        {
            var grid = NewGrid("*", "8", "Auto", "12", "Auto");
            sortBox = new ComboBox();
            foreach (var s in SORTS) sortBox.Items.Add(new ComboBoxItem { Content = s[1], Tag = s[0] });
            sortBox.SelectedIndex = 0;
            sortNow = NewButton("Sort now", "", "Put the tiles of the category in this order once; you can still drag them afterwards");
            sortKeep = new CheckBox
            {
                Content = "Keep sorted", VerticalAlignment = VerticalAlignment.Center,
                ToolTip = "Always in this order: new and changed tiles go to their place, and the launcher works the order out again each time it opens (play changes it). Dragging is off.",
            };
            SetCol(sortNow, 2);
            SetCol(sortKeep, 4);
            grid.Children.Add(sortBox); grid.Children.Add(sortNow); grid.Children.Add(sortKeep);
            sortNow.Click += (s, e) =>
            {
                if (currentFile == null) return;
                SortCategory(currentFile, SelectedSort());
                SetChanged(currentFile);
                RefreshTiles(-1);
            };
            sortKeep.Checked += (s, e) => SetKeepSorted(true);
            sortKeep.Unchecked += (s, e) => SetKeepSorted(false);
            sortBox.SelectionChanged += (s, e) => { if (sortKeep.IsChecked == true) SetKeepSorted(true); };
            return sortRow = NewFormRow("Order", grid,
                "Played: the launches counted by Raintile, Steam's last launch and play time, and the play time measured for the other games. Ties keep the order they had.");
        }

        string SelectedSort()
        {
            var item = sortBox.SelectedItem as ComboBoxItem;
            return item != null ? (string)item.Tag : "name";
        }

        // Sort= of the category: the order it keeps, null for none (the order of the file)
        string GetKeptSort(string file)
        {
            if (file == null) return null;
            string key = Core.GetKey(Core.GetCategorySection(GetModel(file)), "Sort").Trim().ToLowerInvariant();
            return SORTS.Any(s => s[0] == key) ? key : null;
        }

        void SetKeepSorted(bool on)
        {
            if (sortLoading || currentFile == null) return;
            Core.SetKey(Core.GetCategorySection(GetModel(currentFile)), "Sort", on ? SelectedSort() : "");
            if (on) SortCategory(currentFile, SelectedSort());
            SetChanged(currentFile);
            RefreshTiles(-1);
        }

        // The row as the category has it (under All tiles)
        void UpdateSortRow()
        {
            if (sortRow == null) return;
            string kept = GetKeptSort(currentFile);
            sortLoading = true;
            sortKeep.IsChecked = kept != null;
            if (kept != null) sortBox.SelectedItem = sortBox.Items.OfType<ComboBoxItem>().First(i => (string)i.Tag == kept);
            sortLoading = false;
        }

        // Sorts the tile sections of the category in place ([Category] stays where it is)
        void SortCategory(string file, string key)
        {
            var model = GetModel(file);
            var slots = new List<int>();
            for (int i = 0; i < model.Sections.Count; i++)
                if (!string.Equals(model.Sections[i].Name, "Category", StringComparison.OrdinalIgnoreCase)) slots.Add(i);
            var tiles = slots.Select(i => model.Sections[i]).ToList();
            var play = key == "recent" || key == "played" || key == "playtime" ? ReadPlayData() : null;
            string cat = Path.GetFileName(file);
            Func<IniSection, IComparable> value = t =>
            {
                if (key == "name" || key == "name-desc") return t.Name.ToLowerInvariant();
                if (key == "added") return Core.GetKey(t, "Added").Trim();
                string id = cat + "|" + t.Name;
                string steam = Art.SteamId(Core.GetKey(t, "Command").Trim(), Core.GetKey(t, "Source").Trim());
                long[] u, s, m;
                play.Usage.TryGetValue(id, out u);
                play.Steam.TryGetValue(steam ?? "", out s);
                play.Measured.TryGetValue(id, out m);
                if (key == "played") return u != null ? u[0] : 0L;
                if (key == "playtime") return (s != null ? s[0] : 0L) + (m != null ? m[0] : 0L);
                return Math.Max(u != null ? u[1] : 0L, Math.Max(s != null ? s[1] : 0L, m != null ? m[1] : 0L));
            };
            var values = tiles.ToDictionary(t => t, value);
            var order = tiles.Select((t, i) => new { t, i });
            // names A-Z (ordinal, as the launcher compares them); the rest the largest first
            var sorted = (key == "name"
                ? order.OrderBy(o => (string)values[o.t], StringComparer.Ordinal)
                : key == "name-desc" || key == "added"
                    ? order.OrderByDescending(o => (string)values[o.t], StringComparer.Ordinal)
                    : order.OrderByDescending(o => (long)values[o.t]))
                .ThenBy(o => o.i).Select(o => o.t).ToList();
            for (int n = 0; n < slots.Count; n++) model.Sections[slots[n]] = sorted[n];
        }

        // A kept order applied again after a change (new, renamed, imported tiles);
        // true if the order changed
        bool ApplyKeptSort(string file)
        {
            string key = GetKeptSort(file);
            if (key == null) return false;
            var before = Core.GetTiles(GetModel(file));
            SortCategory(file, key);
            return !before.SequenceEqual(Core.GetTiles(GetModel(file)));
        }

        class PlayData
        {
            public Dictionary<string, long[]> Usage = new Dictionary<string, long[]>();    // file|tile -> launches, last
            public Dictionary<string, long[]> Steam = new Dictionary<string, long[]>();    // app id -> minutes, last
            public Dictionary<string, long[]> Measured = new Dictionary<string, long[]>(); // file|tile -> minutes, last
        }

        static PlayData ReadPlayData()
        {
            var d = new PlayData();
            ReadPlayFile(Path.Combine(Core.Data, "Usage.txt"), d.Usage);
            ReadPlayFile(Path.Combine(Core.Generated, "Playtime.txt"), d.Steam);
            ReadPlayFile(Path.Combine(Core.Data, "TimePlayed.txt"), d.Measured);
            return d;
        }

        // Lines "<id>|<number>|<number>"
        static void ReadPlayFile(string path, Dictionary<string, long[]> into)
        {
            try
            {
                if (!File.Exists(path)) return;
                foreach (var line in File.ReadAllLines(path))
                {
                    var m = Regex.Match(line, @"^(.*)\|(\d+)\|(\d+)$");
                    long a, b;
                    if (m.Success && long.TryParse(m.Groups[2].Value, out a) && long.TryParse(m.Groups[3].Value, out b))
                        into[m.Groups[1].Value] = new[] { a, b };
                }
            }
            catch { }
        }
    }
}
