// Raintile Options: what Scan.ps1 found (Generated\Found.json) becomes tiles.
// One way of adding, for Add selected on Found and for the games added by
// themselves (AutoAddGames): in the window, on its categories with their
// unsaved changes; without it (RaintileOptions.exe ... -Action autoadd, run by
// the skin after its search), on the category files.
//
// Games added by themselves: every game found that is not among the tiles and
// was never handled before. AutoAdded.txt (data folder) lists the ids handled,
// added or already there, so a tile removed later does not come back; the
// names added are listed in Generated\AutoAddedNames.txt for the dot on the
// gear until Found is shown.

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

    public partial class OptionsApp
    {
        static string AutoAddedFile { get { return Path.Combine(Core.Data, "AutoAdded.txt"); } }
        static string AutoAddedNoticeFile { get { return Path.Combine(Core.Generated, "AutoAddedNames.txt"); } }

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
        // Returns the names of the tiles added.
        static List<string> AddFoundItems(List<FoundItem> items, string target, FoundAddContext ctx)
        {
            string key = Core.UnprotectSecret(ctx.Setting("SteamGridDBKey"));
            var present = GetPresentMap(ctx.Models);
            var added = new List<string>();
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
                added.Add(name);
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
        // on. Returns the names added.
        static List<string> AutoAddGames(List<FoundItem> found, PresentMap present, Func<List<FoundItem>, List<string>> add)
        {
            var handled = ReadIdLines(AutoAddedFile);
            var games = found.Where(it => Schema.KindOf(it.Kind).Id == "game" && !handled.Contains(it.Id)).ToList();
            if (games.Count == 0) return new List<string>();
            var missing = games.Where(it => GetPresentIn(it, present) == null).ToList();
            var added = missing.Count > 0 ? add(missing) : new List<string>();
            handled.UnionWith(games.Select(it => it.Id));
            Core.WriteAllTextAtomic(AutoAddedFile, string.Join("\r\n", handled.OrderBy(x => x, StringComparer.OrdinalIgnoreCase)) + "\r\n");
            return added;
        }

        // Names added by themselves and not shown on Found yet
        static List<string> ReadAutoAddedNotice()
        {
            return File.Exists(AutoAddedNoticeFile) ? File.ReadAllLines(AutoAddedNoticeFile, Core.Utf8).Where(l => l != "").ToList() : new List<string>();
        }

        static string AutoAddedText(List<string> names)
        {
            if (names.Count == 0) return "";
            const int shown = 5;
            string list = string.Join(", ", names.Take(shown)) + (names.Count > shown ? " and " + (names.Count - shown) + " more" : "");
            return (names.Count == 1 ? "1 game" : names.Count + " games") + " added by themselves: " + list + ".";
        }

        // -Action autoadd: after the skin's search, on the category files. The
        // skin runs it only with AutoAddGames=1 and the window closed (it adds
        // them itself when Found opens): checked again here, the setting may
        // have changed meanwhile
        public static int RunAutoAdd()
        {
            var added = AutoAddToFiles();
            if (added.Count == 0) return 0;
            Core.WriteAllTextAtomic(AutoAddedNoticeFile, string.Join("\r\n", ReadAutoAddedNotice().Concat(added)) + "\r\n");
            InvokeRainmeter("!CommandMeasure MeasureScript \"OnAutoAdded()\" \"" + Core.Config + "\"");
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
                var names = AddFoundItems(list, "auto", ctx);
                foreach (var f in ctx.Touched) Core.WriteCategory(Path.Combine(Core.CategoriesDir, f), GetModel(ctx.Models, f));
                return names;
            });
        }
    }
}
