// Raintile Options: a list of folders for a setting kept as "a|b|c"
// (ImportFolders): each folder on a row with its name (alias) and a button to
// remove it, and "Add folder..." with the Windows folder picker. An entry is
// "Alias=X:\Folder" or just the folder (its name: the folder's own), as
// Scan.ps1 reads it (Split-FolderEntry).

using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;

namespace RaintileOptions
{
    public partial class OptionsApp
    {
        readonly Dictionary<string, Action> folderLists = new Dictionary<string, Action>();

        static List<string> SplitFolders(string value)
        {
            return (value ?? "").Split('|').Select(f => f.Trim()).Where(f => f != "").ToList();
        }

        // { alias (the folder's name without one), path, whether the alias is its own }
        static string[] SplitFolderEntry(string entry)
        {
            var m = System.Text.RegularExpressions.Regex.Match(entry.Trim(), "^([^\\\\/:=|\"]+?)\\s*=\\s*(.+)$");
            string alias = m.Success ? m.Groups[1].Value.Trim() : "";
            string path = (m.Success ? m.Groups[2].Value : entry).Trim().Trim('"');
            string leaf = path.TrimEnd('\\', '/').Split('\\', '/').Last();
            return new[] { alias != "" ? alias : leaf, path, alias != "" && alias != leaf ? "1" : "" };
        }

        // An entry again: the alias only when it is not the folder's own name;
        // the characters an entry cannot hold leave the alias
        static string JoinFolderEntry(string alias, string path)
        {
            alias = System.Text.RegularExpressions.Regex.Replace(alias ?? "", "[\\\\/:=|\"]", "").Trim();
            string leaf = path.TrimEnd('\\', '/').Split('\\', '/').Last();
            return alias == "" || alias == leaf ? path : alias + "=" + path;
        }

        UIElement NewFoldersControl(string key)
        {
            var root = NewPanel();
            // fills the control column, as the text fields
            var rows = NewPanel();
            AddTo(root, rows);
            var add = NewButton("Add folder...");
            add.HorizontalAlignment = HorizontalAlignment.Left;
            add.Margin = T(0, Gap.Line, 0, 0);
            AddTo(root, add);

            Action render = null;
            render = () =>
            {
                rows.Children.Clear();
                var folders = SplitFolders(V(key));
                if (folders.Count == 0)
                    AddTo(rows, NewHelp("No folders yet: add one with Add folder..."));
                foreach (var entry in folders)
                {
                    var parts = SplitFolderEntry(entry);
                    string folder = parts[1];
                    var row = NewGrid("Auto", "*", "Auto");
                    row.Margin = T(0, 0, 0, Gap.Line);
                    // its name: shown in the list of found ones, and a filter there
                    var alias = new TextBox { Text = parts[0], Width = FieldWidth.S, VerticalAlignment = VerticalAlignment.Center, Margin = T(0, 0, Gap.Control, 0), ToolTip = "Its name in the list of found ones" };
                    row.Children.Add(alias);
                    string own = entry;
                    alias.LostFocus += (s, e) =>
                    {
                        var list = SplitFolders(V(key));
                        int i = list.IndexOf(own);
                        if (i < 0) return;
                        list[i] = JoinFolderEntry(alias.Text, folder);
                        if (list[i] == own) return;
                        SetValue(key, string.Join("|", list));
                        render();
                    };
                    var cell = NewPanel();
                    cell.VerticalAlignment = VerticalAlignment.Center;
                    SetCol(cell, 1);
                    var path = NewText(folder, Fs.Label);
                    SetTrimmed(path);
                    AddTo(cell, path);
                    // shown, not only in a tooltip: a folder that is not there finds nothing
                    if (!System.IO.Directory.Exists(System.Environment.ExpandEnvironmentVariables(folder)))
                    {
                        path.Foreground = ResBrush("DimBrush");
                        AddTo(cell, NewHelp("Not found: a drive not connected?"));
                    }
                    row.Children.Add(cell);
                    var remove = NewClearButton("Remove this folder from the list (nothing is deleted)");
                    SetCol(remove, 2);
                    row.Children.Add(remove);
                    remove.Click += (s, e) =>
                    {
                        var list = SplitFolders(V(key));
                        list.RemoveAll(x => string.Equals(x, own, StringComparison.OrdinalIgnoreCase));
                        SetValue(key, string.Join("|", list));
                        render();
                    };
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
                    if (list.Select(x => SplitFolderEntry(x)[1].TrimEnd('\\')).Any(x => picked.Equals(x, StringComparison.OrdinalIgnoreCase)
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
