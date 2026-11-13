// Raintile Options: what Scan.ps1 found (Generated\Found.json) becomes tiles.
// One way of adding, for Add selected on Found and for the games added by
// themselves (AutoAddGames): in the window, on its categories with their
// unsaved changes; without it (RaintileOptions.exe ... -Action autoadd, run by
// the skin after its search), on the category files.
//
// Games added by themselves: every game found that is not among the tiles and
// was never handled before. AutoAdded.txt (data folder) lists the ids handled,
// added or already there, so a tile removed later does not come back. The
// tiles added are new until they are shown in their category
// (Generated\NewTiles.txt, "<category file>|<tile name>"): a dot on the gear,
// on the category in the menu and on the tile in its category.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace RaintileOptions
{
    // What adding works on: the category models (file name -> model, read when
    // first needed), the settings, and what is told on the way
    class FoundAddContext
    {
        public Dictionary<string, CategoryModel> Models = new Dictionary<string, CategoryModel>(StringComparer.OrdinalIgnoreCase);
        public Func<string, string> Setting;
        public Action CategoryCreated;               // (the window rebuilds its menu)
        public Action<int, int, FoundItem> Progress; // (index, count, item)
        public readonly HashSet<string> Touched = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    }

    // A tile added: its category file and its name
    class AddedTile
    {
        public string File, Name;
    }

    public partial class OptionsApp
    {
        static string AutoAddedFile { get { return Path.Combine(Core.Data, "AutoAdded.txt"); } }
        static string NewTilesFile { get { return Path.Combine(Core.Generated, "NewTiles.txt"); } }

        static CategoryModel GetModel(Dictionary<string, CategoryModel> models, string file)
        {
            CategoryModel m;
            if (!models.TryGetValue(file, out m))
            {
                m = Core.ReadCategory(Path.Combine(Core.CategoriesDir, file));
                models[file] = m;
            }
            return m;
        }

        // Tiles of every category: name key / command -> category name
        class PresentMap
        {
            public Dictionary<string, string> Names = new Dictionary<string, string>();
            public Dictionary<string, string> Commands = new Dictionary<string, string>();
        }

        static PresentMap GetPresentMap(Dictionary<string, CategoryModel> models)
        {
            var map = new PresentMap();
            foreach (var f in Core.GetCategoryFiles())
            {
                var m = GetModel(models, f.Name);
                string name = Core.GetKey(Core.GetCategorySection(m), "Name");
                if (name == "") name = Path.GetFileNameWithoutExtension(f.Name);
                foreach (var s in Core.GetTiles(m))
                {
                    map.Names[Core.GetNameKey(s.Name)] = name;
                    string cmd = Core.GetKey(s, "Command");
                    if (cmd != "") map.Commands[cmd.ToLowerInvariant()] = name;
                }
                foreach (var n in Core.GetImportedNames(m)) map.Names[Core.GetNameKey(n)] = name;
            }
            return map;
        }

        static string GetPresentIn(FoundItem it, PresentMap map)
        {
            string c;
            if (map.Commands.TryGetValue((it.Command ?? "").ToLowerInvariant(), out c)) return c;
            return map.Names.TryGetValue(Core.GetNameKey(it.Name), out c) ? c : null;
        }

        // Category file for an added item; created if it does not exist yet
        static string GetCategoryFileFor(FoundAddContext ctx, string b)
        {
            if (ctx.Models.ContainsKey(b + ".ini") || File.Exists(Path.Combine(Core.CategoriesDir, b + ".ini"))) return b + ".ini";
            ctx.Models[b + ".ini"] = Core.CreateCategoryFile(b, b);
            if (ctx.CategoryCreated != null) ctx.CategoryCreated();
            return b + ".ini";
        }

        // The items as tiles of their category (target "auto": by type, a folder's
        // own category first, then the one of its kind; else that category file),
        // with their images; the files changed go into ctx.Touched, not written.
        // Returns the tiles added.
        static List<AddedTile> AddFoundItems(List<FoundItem> items, string target, FoundAddContext ctx)
        {
            string key = Core.UnprotectSecret(ctx.Setting("SteamGridDBKey"));
            var present = GetPresentMap(ctx.Models);
            var added = new List<AddedTile>();
            for (int i = 0; i < items.Count; i++)
            {
                var it = items[i];
                if (ctx.Progress != null) ctx.Progress(i, items.Count, it);
                if (GetPresentIn(it, present) != null) continue;
                string b = target != "auto" ? Path.GetFileNameWithoutExtension(target)
                    : !string.IsNullOrEmpty(it.Category) ? Core.GetTileName(it.Category)
                    : ctx.Setting(Schema.KindOf(it.Kind).CategoryKey);
                if (b == "") b = Schema.KindOf(it.Kind).DefaultCategory;
                string file = GetCategoryFileFor(ctx, b);
                var m = GetModel(ctx.Models, file);
                string name = Core.GetTileName(it.Name);
                if (name == "") continue;
                if (TestTileName(m, name)) name = name + " (" + it.Source + ")";
                if (TestTileName(m, name)) continue;
                var s = new IniSection { Name = name };
                Core.SetKey(s, "Command", it.Command);
                Core.SetKey(s, "Source", it.Id);
                Core.SetKey(s, "Added", DateTime.Now.ToString("yyyy-MM-dd"));   // for Not played yet
                AddFoundImages(it, b, name, key);
                m.Sections.Add(s);
                present.Names[Core.GetNameKey(name)] = b;
                present.Commands[(it.Command ?? "").ToLowerInvariant()] = b;
                ctx.Touched.Add(file);
                added.Add(new AddedTile { File = file, Name = name });
            }
            return added;
        }

        // Images in the default folders, named after the tile: the local ones;
        // for games Steam's servers, then SteamGridDB; for apps a logo of
        // Dashboard Icons, or SteamGridDB for a game/app of that very name; last
        // the program's icon
        static void AddFoundImages(FoundItem it, string b, string name, string key)
        {
            try
            {
                foreach (var kind in new[] { "background", "logo" })
                {
                    string local = kind == "background" ? it.Hero : it.Logo;
                    if (local != "" && File.Exists(local)) { Core.CopyTileImage(b, kind, name, local); continue; }
                    if (Schema.KindOf(it.Kind).GameArt)
                    {
                        if (DownloadTileImage(Art.SteamImage(it.SteamAppId, kind), b, kind, name)) continue;
                        if (key != "")
                        {
                            try { GetSGDBImage(key, kind == "background" ? "heroes" : "logos", name, it.SteamAppId, Path.Combine(Core.ImagesRoot, b, kind, name)); } catch { }
                        }
                        continue;
                    }
                    if (kind == "logo")
                    {
                        string icon = null;
                        try { icon = Art.DashboardIconNames(it.Name).FirstOrDefault(); } catch { }
                        if (icon != null && DownloadTileImage(Art.DashboardIconUrl(icon), b, kind, name)) continue;
                    }
                    if (key != "") AppSgdbImage(key, kind, it.Name, b, name);
                }
                if (Core.FindImage(Path.Combine(Core.ImagesRoot, b, "logo"), name) == null && it.Icon != "" && File.Exists(it.Icon))
                    Core.CopyTileImage(b, "logo", name, it.Icon);
            }
            catch { }
        }

        // --- Games added by themselves ------------------------------------------------

        static HashSet<string> ReadIdLines(string file)
        {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (File.Exists(file)) foreach (var l in File.ReadAllLines(file, Core.Utf8)) if (l != "") set.Add(l);
            return set;
        }

        // The games found and not handled yet that are not among the tiles go
        // through add (which writes them); all those games are handled from then
        // on. The tiles added are new (NewTiles.txt).
        static List<AddedTile> AutoAddGames(List<FoundItem> found, PresentMap present, Func<List<FoundItem>, List<AddedTile>> add)
        {
            var handled = ReadIdLines(AutoAddedFile);
            var games = found.Where(it => Schema.KindOf(it.Kind).Id == "game" && !handled.Contains(it.Id)).ToList();
            if (games.Count == 0) return new List<AddedTile>();
            var missing = games.Where(it => GetPresentIn(it, present) == null).ToList();
            var added = missing.Count > 0 ? add(missing) : new List<AddedTile>();
            handled.UnionWith(games.Select(it => it.Id));
            Core.WriteAllTextAtomic(AutoAddedFile, string.Join("\r\n", handled.OrderBy(x => x, StringComparer.OrdinalIgnoreCase)) + "\r\n");
            if (added.Count > 0) WriteNewTiles(ReadNewTiles().Concat(added.Select(t => t.File + "|" + t.Name)));
            return added;
        }

        // --- New tiles (added by themselves, not shown in their category yet) -----------

        static List<string> ReadNewTiles()
        {
            return File.Exists(NewTilesFile) ? File.ReadAllLines(NewTilesFile, Core.Utf8).Where(l => l.Contains("|")).ToList() : new List<string>();
        }

        // The list written again (gone when empty)
        static void WriteNewTiles(IEnumerable<string> lines)
        {
            var list = lines.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            if (list.Count > 0) Core.WriteAllTextAtomic(NewTilesFile, string.Join("\r\n", list) + "\r\n");
            else if (File.Exists(NewTilesFile)) File.Delete(NewTilesFile);
        }

        // In the window: the dots of the menu follow, the skin reads the list
        // again for the dot on the gear
        void NewTilesChanged()
        {
            InvokeRainmeter("!CommandMeasure MeasureScript \"OnNewTiles()\" \"" + Core.Config + "\"");
            UpdateNavDots(true);
        }

        // The new tiles that are still tiles of their category, as the window has
        // them (a tile renamed or removed since leaves the list); read again
        // after UpdateNavDots(true)
        List<AddedTile> newTiles;

        List<AddedTile> NewTiles()
        {
            if (newTiles != null) return newTiles;
            newTiles = new List<AddedTile>();
            var lines = ReadNewTiles();
            if (lines.Count == 0) return newTiles;
            var files = Core.GetCategoryFiles().ToDictionary(f => f.Name, f => f.Name, StringComparer.OrdinalIgnoreCase);
            foreach (var l in lines)
            {
                var p = l.Split(new[] { '|' }, 2);
                string file;
                if (!files.TryGetValue(p[0], out file) || !Core.GetTiles(GetModel(file)).Any(s => s.Name == p[1])) continue;
                newTiles.Add(new AddedTile { File = file, Name = p[1] });
            }
            if (newTiles.Count != lines.Count)
            {
                WriteNewTiles(newTiles.Select(t => t.File + "|" + t.Name));
                InvokeRainmeter("!CommandMeasure MeasureScript \"OnNewTiles()\" \"" + Core.Config + "\"");
            }
            return newTiles;
        }

        // The new tiles of the category shown when it was opened: their dot stays
        // in its strip while it is shown, the menu and the gear forget them at once
        HashSet<string> newShown = new HashSet<string>();

        // A category opened (null: the Categories page, every category): its new
        // tiles have been seen
        void SetNewTilesSeen(string file)
        {
            var seen = NewTiles().Where(t => file == null || string.Equals(t.File, file, StringComparison.OrdinalIgnoreCase)).ToList();
            if (file != null) newShown = new HashSet<string>(seen.Select(t => t.Name));
            if (seen.Count == 0) return;
            newTiles.RemoveAll(seen.Contains);
            WriteNewTiles(newTiles.Select(t => t.File + "|" + t.Name));
            NewTilesChanged();
        }

        static string AutoAddedText(List<AddedTile> tiles)
        {
            if (tiles.Count == 0) return "";
            const int shown = 5;
            string list = string.Join(", ", tiles.Take(shown).Select(t => t.Name)) + (tiles.Count > shown ? " and " + (tiles.Count - shown) + " more" : "");
            return (tiles.Count == 1 ? "1 game" : tiles.Count + " games") + " added: " + list + ".";
        }

        // -Action autoadd: after the skin's search, on the category files. The
        // skin runs it only with AutoAddGames=1 and the window closed (it adds
        // them itself when Found opens, or the setting is turned on): checked
        // again here, the setting may have changed meanwhile
        public static int RunAutoAdd()
        {
            if (AutoAddToFiles().Count > 0) InvokeRainmeter("!CommandMeasure MeasureScript \"OnAutoAdded()\" \"" + Core.Config + "\"");
            return 0;
        }

        // The games added to the category files, with AutoAddGames=1 in
        // Settings.inc; the names added (public: tests)
        public static List<string> AutoAddToFiles()
        {
            if (!File.Exists(Core.SettingsFile) || !File.Exists(Core.FoundFile)) return new List<string>();
            var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var item in Core.ReadSettings(Core.SettingsFile)) values[item.Key] = item.Value;
            Func<string, string> setting = k =>
            {
                string v;
                return values.TryGetValue(k, out v) || Schema.Defaults.TryGetValue(k, out v) ? v : "";
            };
            if (setting("AutoAddGames") != "1") return new List<string>();
            var found = ReadFoundItems(File.ReadAllText(Core.FoundFile));
            var ctx = new FoundAddContext { Setting = setting };
            return AutoAddGames(found, GetPresentMap(ctx.Models), list =>
            {
                var added = AddFoundItems(list, "auto", ctx);
                foreach (var f in ctx.Touched) Core.WriteCategory(Path.Combine(Core.CategoriesDir, f), GetModel(ctx.Models, f));
                return added;
            }).Select(t => t.Name).ToList();
        }
    }
}
