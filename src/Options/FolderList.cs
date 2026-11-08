// Raintile Options: your folders (ImportFolders, entries separated by |) as a
// grid: a row per folder with its name, the folder, whether its programs are
// games or apps and the category they go to, a button to remove it, and
// "Add folder..." with the Windows folder picker. An entry is
// "Name=X:\Folder>Kind>Category", every part but the folder optional, as
// Scan.ps1 reads it (Split-FolderEntry).

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;

namespace RaintileOptions
{
    class FolderEntry
    {
        public string Name, Path, Kind, Category;
        public bool OwnName;   // a name of its own, not the folder's
    }

    public partial class OptionsApp
    {
        readonly Dictionary<string, Action> folderLists = new Dictionary<string, Action>();

        static List<string> SplitFolders(string value)
        {
            return (value ?? "").Split('|').Select(f => f.Trim()).Where(f => f != "").ToList();
        }

        static string FolderLeaf(string path)
        {
            return path.TrimEnd('\\', '/').Split('\\', '/').Last();
        }

        // An entry of ImportFolders: a name has no \ / : = > | or ", a folder always
        // has \ and never > (Windows refuses it in names)
        static FolderEntry SplitFolderEntry(string entry)
        {
            var m = Regex.Match(entry.Trim(), "^([^\\\\/:=|>\"]+?)\\s*=\\s*(.+)$");
            string name = m.Success ? m.Groups[1].Value.Trim() : "";
            var parts = (m.Success ? m.Groups[2].Value : entry).Split('>');
            string path = parts[0].Trim().Trim('"');
            string kind = parts.Length > 1 ? parts[1].Trim().ToLowerInvariant() : "";
            kind = kind.StartsWith("app") ? "app" : kind.StartsWith("game") ? "game" : "";
            return new FolderEntry
            {
                Name = name != "" ? name : FolderLeaf(path), Path = path, Kind = kind,
                Category = parts.Length > 2 ? parts[2].Trim() : "", OwnName = name != "" && name != FolderLeaf(path),
            };
        }

        // The entry again: only the parts that are set (a name only when it is
        // not the folder's own); the characters an entry cannot hold leave them
        static string JoinFolderEntry(FolderEntry e)
        {
            string name = Regex.Replace(e.Name ?? "", "[\\\\/:=|>\"]", "").Trim();
            string cat = Regex.Replace(e.Category ?? "", "[|>\"]", "").Trim();
            string s = (name == "" || name == FolderLeaf(e.Path) ? "" : name + "=") + e.Path;
            if (e.Kind != "" || cat != "") s += ">" + (e.Kind == "app" ? "App" : e.Kind == "game" ? "Game" : "");
            if (cat != "") s += ">" + cat;
            return s;
        }

        UIElement NewFoldersControl(string key)
        {
            var root = NewPanel();
            var rows = NewPanel();
            AddTo(root, rows);
            var add = NewButton("Add folder...");
            add.HorizontalAlignment = HorizontalAlignment.Left;
            add.Margin = T(0, Gap.Line, 0, 0);
            AddTo(root, add);

            // the columns of a row: name, folder, kind, category, remove
            Func<Grid> newRow = () =>
            {
                var g = NewGrid(FieldWidth.S.ToString(), "*", FieldWidth.S.ToString(), FieldWidth.M.ToString(), Gap.ActionColumn.ToString());
                g.Margin = T(0, 0, 0, Gap.Line);
                return g;
            };
            Action<Grid, UIElement, int> put = (g, el, col) =>
            {
                var fe = el as FrameworkElement;
                if (fe != null) { fe.VerticalAlignment = VerticalAlignment.Center; if (col < 3) fe.Margin = T(0, 0, Gap.Control, 0); }
                SetCol(el, col);
                g.Children.Add(el);
            };
            // a change of a row: the whole value again
            Action<int, FolderEntry> save = null;
            Action render = null;
            save = (i, e) =>
            {
                var list = SplitFolders(V(key));
                if (i < 0 || i >= list.Count) return;
                string entry = JoinFolderEntry(e);
                if (entry == list[i]) return;
                list[i] = entry;
                SetValue(key, string.Join("|", list));
            };

            render = () =>
            {
                rows.Children.Clear();
                var folders = SplitFolders(V(key));
                if (folders.Count == 0) { AddTo(rows, NewHelp("No folders yet: add one with Add folder...")); return; }
                var head = newRow();
                int c = 0;
                foreach (var title in new[] { "Name", "Folder", "Programs are", "They go to" })
                    put(head, NewSectionTitle(title), c++);
                AddTo(rows, head);
                var cats = new[] { new[] { "", "The category of their kind" } }
                    .Concat(Core.GetCategoryFiles().Select(f => System.IO.Path.GetFileNameWithoutExtension(f.Name)).Select(n => new[] { n, n })).ToList();
                for (int i = 0; i < folders.Count; i++)
                {
                    int index = i;
                    var e = SplitFolderEntry(folders[i]);
                    var row = newRow();
                    // its name: shown in the list of found ones, and a filter there
                    var name = new TextBox { Text = e.Name };
                    name.LostFocus += (s, ev) => { e.Name = name.Text; save(index, e); };
                    put(row, name, 0);
                    var cell = NewPanel();
                    var path = NewText(e.Path, Fs.Label);
                    SetTrimmed(path);
                    AddTo(cell, path);
                    // shown, not only in a tooltip: a folder that is not there finds nothing
                    if (!System.IO.Directory.Exists(Environment.ExpandEnvironmentVariables(e.Path)))
                    {
                        path.Foreground = ResBrush("DimBrush");
                        AddTo(cell, NewHelp("Not found: a drive not connected?"));
                    }
                    put(row, cell, 1);
                    var kind = NewChoiceBox(new[] { new[] { "game", "Games" }, new[] { "app", "Apps" } }, e.Kind == "app" ? "app" : "game", v => { e.Kind = v ?? "game"; save(index, e); });
                    put(row, kind, 2);
                    var catList = cats.ToList();
                    if (e.Category != "" && !catList.Any(x => x[0] == e.Category)) catList.Add(new[] { e.Category, e.Category });
                    var cat = NewChoiceBox(catList, e.Category, v => { e.Category = v ?? ""; save(index, e); });
                    put(row, cat, 3);
                    var remove = NewClearButton("Remove this folder from the list (nothing is deleted)");
                    remove.Click += (s, ev) =>
                    {
                        var list = SplitFolders(V(key));
                        if (index < list.Count) list.RemoveAt(index);
                        SetValue(key, string.Join("|", list));
                        render();
                    };
                    put(row, remove, 4);
                    AddTo(rows, row);
                }
            };
            add.Click += (s, e) =>
            {
                using (var dlg = new System.Windows.Forms.FolderBrowserDialog { Description = "A folder with programs (portable games, emulators...): its subfolders are searched too.", ShowNewFolderButton = false })
                {
                    if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK || string.IsNullOrEmpty(dlg.SelectedPath)) return;
                    var list = SplitFolders(V(key));
                    // a folder in the list already (or inside one of them) adds nothing
                    string picked = dlg.SelectedPath.TrimEnd('\\');
                    if (list.Select(x => SplitFolderEntry(x).Path.TrimEnd('\\')).Any(x => picked.Equals(x, StringComparison.OrdinalIgnoreCase)
                        || picked.StartsWith(x + "\\", StringComparison.OrdinalIgnoreCase))) return;
                    list.Add(picked);
                    SetValue(key, string.Join("|", list));
                    render();
                }
            };
            folderLists[key] = render;
            ctl[key] = new Ctl { Kind = "folders", Panel = root };
            render();
            return root;
        }
    }
}
