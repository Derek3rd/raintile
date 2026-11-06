// Raintile Options: a list of folders for a setting kept as "a|b|c"
// (ImportFolders): each folder on a row with a button to remove it, and
// "Add folder..." with the Windows folder picker.

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

        UIElement NewFoldersControl(string key)
        {
            var root = NewPanel();
            root.MinWidth = 320;
            root.MaxWidth = 470;
            root.HorizontalAlignment = HorizontalAlignment.Right;
            var rows = NewPanel();
            AddTo(root, rows);
            var add = NewButton("Add folder...");
            add.HorizontalAlignment = HorizontalAlignment.Left;
            add.Margin = T(0, 4, 0, 0);
            AddTo(root, add);

            Action render = null;
            render = () =>
            {
                rows.Children.Clear();
                var folders = SplitFolders(V(key));
                if (folders.Count == 0)
                    AddTo(rows, NewText("No folders yet.", 12, ResBrush("DimBrush")));
                foreach (var folder in folders)
                {
                    var row = NewGrid("*", "Auto");
                    row.Margin = T(0, 0, 0, 4);
                    var path = NewText(folder, 12.5);
                    path.TextTrimming = TextTrimming.CharacterEllipsis;
                    path.ToolTip = folder;
                    path.VerticalAlignment = VerticalAlignment.Center;
                    if (!System.IO.Directory.Exists(System.Environment.ExpandEnvironmentVariables(folder)))
                    {
                        path.Foreground = ResBrush("DimBrush");
                        path.ToolTip = folder + " (not found: a drive not connected?)";
                    }
                    row.Children.Add(path);
                    var remove = NewClearButton("Remove this folder from the list (nothing is deleted)");
                    remove.Margin = T(8, 0, 0, 0);
                    SetCol(remove, 1);
                    row.Children.Add(remove);
                    string f = folder;
                    remove.Click += (s, e) =>
                    {
                        var list = SplitFolders(V(key));
                        list.RemoveAll(x => string.Equals(x, f, StringComparison.OrdinalIgnoreCase));
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
                    if (list.Any(x => picked.Equals(x.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)
                        || picked.StartsWith(x.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))) return;
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
