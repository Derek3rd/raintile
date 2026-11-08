// Raintile Options: your folders (ImportFolders, entries separated by |) as a
// grid: a row per folder with its name, the folder, the kind of its programs
// (Schema.IMPORT_KINDS) and the category they go to, a button to remove it,
// and "Add folder..." with the Windows folder picker. A row is read-only; its
// pencil (shown with the mouse over the row, or the focus in it) edits it in
// place, and again ends the editing. An entry is
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
        int folderEditing = -1;   // the row of Your folders being edited (-1: none)

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
            // one of the kinds (Game, App...; empty: the default one)
            string k = parts.Length > 1 ? parts[1].Trim().ToLowerInvariant() : "";
            var kd = k == "" ? null : Schema.IMPORT_KINDS.Find(x => x.Id.StartsWith(k));
            string kind = kd != null ? kd.Id : "";
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
            // (written as Game, App...)
            string kind = e.Kind == "" ? "" : char.ToUpperInvariant(e.Kind[0]) + e.Kind.Substring(1);
            if (e.Kind != "" || cat != "") s += ">" + kind;
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
                var g = NewGrid(FieldWidth.S.ToString(), "*", FieldWidth.S.ToString(), FieldWidth.M.ToString(), (2 * Gap.ActionColumn).ToString());
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
                    bool editing = folderEditing == index;
                    var row = newRow();
                    // (the mouse goes onto the row even between its cells)
                    row.Background = System.Windows.Media.Brushes.Transparent;
                    if (editing)
                    {
                        // its name: shown in the list of found ones, and a filter there
                        var name = new TextBox { Text = e.Name };
                        name.LostFocus += (s, ev) => { e.Name = name.Text; save(index, e); };
                        name.KeyDown += (s, ev) => { if (ev.Key == System.Windows.Input.Key.Enter) { e.Name = name.Text; save(index, e); folderEditing = -1; render(); } };
                        put(row, name, 0);
                    }
                    else
                    {
                        var name = NewText(e.Name, Fs.Label);
                        SetTrimmed(name);
                        put(row, name, 0);
                    }
                    var cell = NewPanel();
                    var path = NewText(e.Path, Fs.Help, ResBrush("DimBrush"));
                    SetTrimmed(path);
                    AddTo(cell, path);
                    // shown, not only in a tooltip: a folder that is not there finds nothing
                    if (!System.IO.Directory.Exists(Environment.ExpandEnvironmentVariables(e.Path)))
                        AddTo(cell, NewHelp("Not found: a drive not connected?", ResBrush("DangerBrush")));
                    put(row, cell, 1);
                    var kind = Schema.KindOf(e.Kind);
                    if (editing)
                    {
                        var kindBox = NewChoiceBox(Schema.IMPORT_KINDS.Select(k => new[] { k.Id, k.Plural }), kind.Id, v => { e.Kind = v ?? ""; save(index, e); });
                        put(row, kindBox, 2);
                        var catList = cats.ToList();
                        if (e.Category != "" && !catList.Any(x => x[0] == e.Category)) catList.Add(new[] { e.Category, e.Category });
                        var cat = NewChoiceBox(catList, e.Category, v => { e.Category = v ?? ""; save(index, e); });
                        put(row, cat, 3);
                    }
                    else
                    {
                        put(row, NewText(kind.Plural, Fs.Label), 2);
                        // no category of its own: the one of its kind, dimmed
                        var cat = e.Category != "" ? NewText(e.Category, Fs.Label) : NewText(V(kind.CategoryKey) != "" ? V(kind.CategoryKey) : kind.DefaultCategory, Fs.Label, ResBrush("DimBrush"));
                        SetTrimmed(cat);
                        put(row, cat, 3);
                    }
                    var actions = NewPanel(Orientation.Horizontal);
                    actions.HorizontalAlignment = HorizontalAlignment.Right;
                    var edit = NewEditButton(editing ? "Done" : "Edit this folder's name, kind and category");
                    edit.Click += (s, ev) =>
                    {
                        // (a name being typed was saved as the button took the focus)
                        folderEditing = editing ? -1 : index;
                        render();
                    };
                    var remove = NewClearButton("Remove this folder from the list (nothing is deleted)");
                    remove.Click += (s, ev) =>
                    {
                        var list = SplitFolders(V(key));
                        if (index < list.Count) list.RemoveAt(index);
                        folderEditing = -1;
                        SetValue(key, string.Join("|", list));
                        render();
                    };
                    AddTo(actions, edit);
                    AddTo(actions, remove);
                    put(row, actions, 4);
                    // the pencil: with the mouse over the row or the focus in it (the
                    // keyboard and the pad reach it), always while editing; only
                    // faded out, so it stays a stop of the pad
                    Action showEdit = () => edit.Opacity = editing || row.IsMouseOver || row.IsKeyboardFocusWithin ? 1 : 0;
                    row.MouseEnter += (s, ev) => showEdit();
                    row.MouseLeave += (s, ev) => showEdit();
                    row.IsKeyboardFocusWithinChanged += (s, ev) => showEdit();
                    showEdit();
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
