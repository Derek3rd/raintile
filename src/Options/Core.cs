// Raintile Options: files and data, without user interface.
// A C# port of the first part of Scripts\Options.ps1 (and of the helpers it
// used from Scan.ps1 and Update.ps1): Settings.inc, category files, images,
// the encrypted SteamGridDB key, backups, the lists written by the scan and
// the update check.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace RaintileOptions
{
    // One Settings.inc entry
    public class SettingItem
    {
        public string Section, Key, Value, Description;
        public int Line;
    }

    // A section of a category file: [Category] or a tile
    public class IniSection
    {
        public string Name;
        public List<string> Comments = new List<string>();
        public List<KeyValuePair<string, string>> Keys = new List<KeyValuePair<string, string>>();
    }

    // A category file: text before the first section, the sections, and the
    // old automatic import block (from its marker on, kept as it is)
    public class CategoryModel
    {
        public string Header = "";
        public List<IniSection> Sections = new List<IniSection>();
        public string Imported = "";
    }

    public static class Core
    {
        public const string IMPORT_MARKER = "; ===== IMPORTED AUTOMATICALLY =====";
        public const string OLD_IMPORT_MARKER = "; ===== IMPORTATI AUTOMATICAMENTE =====";
        public static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
        public static readonly string[] IMAGE_EXTS = { ".png", ".jpg", ".jpeg", ".bmp", ".ico", ".gif" };
        public const string Repository = "Derek3rd/raintile";

        public static string Resources, Data, Config = "Raintile";
        public static string SettingsFile, CategoriesDir, ImagesRoot, Generated;
        public static string FoundFile, SeenFile, MissingFile, KeepMissingFile, UpdateFile, IconDir;

        public static void Init(string resources, string data, string config)
        {
            Resources = Path.GetFullPath(resources).TrimEnd('\\', '/');
            // until the data folder is prepared, the skin's own files are used
            Data = !string.IsNullOrEmpty(data) && File.Exists(Path.Combine(data, "Settings.inc"))
                ? Path.GetFullPath(data).TrimEnd('\\', '/') : Resources;
            if (!string.IsNullOrEmpty(config)) Config = config;
            SettingsFile = Path.Combine(Data, "Settings.inc");
            CategoriesDir = Path.Combine(Data, "Categories");
            ImagesRoot = Path.Combine(Data, "Images");
            Generated = Path.Combine(Resources, "Generated");
            FoundFile = Path.Combine(Generated, "Found.json");
            IconDir = Path.Combine(Generated, "Found");
            SeenFile = Path.Combine(Data, "Seen.txt");
            MissingFile = Path.Combine(Generated, "Missing.txt");
            KeepMissingFile = Path.Combine(Data, "KeepMissing.txt");
            UpdateFile = Path.Combine(Data, "Update.json");
        }

        public static string ScriptsDir { get { return Path.Combine(Resources, "Scripts"); } }

        // --- Settings.inc ------------------------------------------------------------

        public static List<SettingItem> ReadSettings(string path)
        {
            var lines = File.ReadAllLines(path);
            var items = new List<SettingItem>();
            string section = "General";
            var comment = new List<string>();
            for (int i = 0; i < lines.Length; i++)
            {
                string t = lines[i].Trim();
                var m = Regex.Match(t, @"^;\s*---\s*(.+?)\s*-*$");
                if (m.Success) { section = m.Groups[1].Value; comment.Clear(); continue; }
                if (t.StartsWith(";")) { comment.Add(t.TrimStart(';').Trim()); continue; }
                if (t == "" || t.StartsWith("[")) { comment.Clear(); continue; }
                m = Regex.Match(t, @"^([^=]+?)\s*=(.*)$");
                if (m.Success)
                {
                    // computed values are not editable
                    if (!Regex.IsMatch(section, "^Computed"))
                        items.Add(new SettingItem
                        {
                            Section = section, Key = m.Groups[1].Value.Trim(), Value = m.Groups[2].Value.Trim(),
                            Description = string.Join(" ", comment), Line = i
                        });
                    comment.Clear();
                }
            }
            return items;
        }

        // Writes the new values changing only those lines
        public static void WriteSettings(string path, IDictionary<string, string> values)
        {
            var lines = File.ReadAllLines(path);
            var re = new Regex(@"^(\s*)([^;=\[][^=]*?)(\s*=)(.*)$");
            var byKey = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var kv in values) byKey[kv.Key] = kv.Value;
            for (int i = 0; i < lines.Length; i++)
            {
                var m = re.Match(lines[i]);
                if (!m.Success) continue;
                string key = m.Groups[2].Value.Trim();
                string v;
                // one line: a value can not add keys or sections
                if (byKey.TryGetValue(key, out v))
                    lines[i] = m.Groups[1].Value + m.Groups[2].Value + m.Groups[3].Value + Regex.Replace(v ?? "", @"[\r\n]+", " ");
            }
            File.WriteAllText(path, string.Join("\r\n", lines) + "\r\n", Utf8);
        }

        // --- Colours -----------------------------------------------------------------

        // R, G, B[, A] from "R,G,B[,A]" or hex RRGGBB[AA] (with or without # or 0x)
        public static int[] ColorFromText(string text)
        {
            string t = (text ?? "").Trim();
            if (Regex.IsMatch(t, @"^\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}(\s*,\s*\d{1,3})?$"))
                return Regex.Split(t, @"\s*,\s*").Select(s => int.Parse(s, CultureInfo.InvariantCulture)).ToArray();
            string hex = Regex.Replace(Regex.Replace(t, "^#", ""), "^0[xX]", "");
            if (Regex.IsMatch(hex, "^[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$"))
            {
                var r = new int[hex.Length / 2];
                for (int i = 0; i < r.Length; i++) r[i] = Convert.ToInt32(hex.Substring(i * 2, 2), 16);
                return r;
            }
            return null;
        }

        // A colour picked as R,G,B written in the format of the old value, keeping
        // its opacity
        public static string FormatPickedColor(string old, int r, int g, int b)
        {
            old = (old ?? "").Trim();
            var v = ColorFromText(old);
            if (old != "" && !old.Contains(","))
            {
                string prefix = old.StartsWith("#") ? "#" : Regex.IsMatch(old, "^0[xX]") ? "0x" : "#";
                string a = v != null && v.Length >= 4 ? v[3].ToString("X2") : "";
                return prefix + r.ToString("X2") + g.ToString("X2") + b.ToString("X2") + a;
            }
            string alpha = v != null && v.Length >= 4 ? "," + v[3] : old == "" ? ",255" : "";
            return r + "," + g + "," + b + alpha;
        }

        // --- Numbers and screen area ---------------------------------------------------

        public static string FormatNumber(double value, double step)
        {
            double r = Math.Round(value / step) * step;
            if (step >= 1) return ((long)Math.Round(r)).ToString(CultureInfo.InvariantCulture);
            return r.ToString("0.###", CultureInfo.InvariantCulture);
        }

        public static bool TryNumber(string text, out double v)
        {
            return double.TryParse((text ?? "").Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out v);
        }

        // "#SCREENAREAX#", "#WORKAREAWIDTH@2#", ... -> area and monitor (null if the
        // four values are not of that form)
        public static string[] ScreenAreaFrom(IDictionary<string, string> v)
        {
            string area = null, mon = null;
            var parts = new[] { new[] { "ScreenX", "X" }, new[] { "ScreenY", "Y" }, new[] { "ScreenW", "WIDTH" }, new[] { "ScreenH", "HEIGHT" } };
            foreach (var p in parts)
            {
                string val;
                v.TryGetValue(p[0], out val);
                var m = Regex.Match(val ?? "", "^#(SCREENAREA|WORKAREA)" + p[1] + @"(@\d+)?#$");
                if (!m.Success) return null;
                string a = m.Groups[1].Value, mo = m.Groups[2].Success ? m.Groups[2].Value.Substring(1) : "";
                if (area != null && (a != area || mo != mon)) return null;
                area = a; mon = mo;
            }
            return new[] { area, mon };
        }

        public static Dictionary<string, string> ScreenAreaTo(string area, string monitor)
        {
            string at = string.IsNullOrEmpty(monitor) ? "" : "@" + monitor;
            return new Dictionary<string, string>
            {
                { "ScreenX", "#" + area + "X" + at + "#" }, { "ScreenY", "#" + area + "Y" + at + "#" },
                { "ScreenW", "#" + area + "WIDTH" + at + "#" }, { "ScreenH", "#" + area + "HEIGHT" + at + "#" },
            };
        }

        // --- Secrets -----------------------------------------------------------------
        // The SteamGridDB key is kept encrypted with Windows DPAPI (current user):
        // "dpapi:<base64>". A value written by hand without the prefix is used as
        // it is and encrypted the next time the Options window saves.

        public const string SECRET_PREFIX = "dpapi:";
        static readonly byte[] SECRET_ENTROPY = Encoding.UTF8.GetBytes("Raintile SteamGridDB key");

        public static string ProtectSecret(string plain)
        {
            if (string.IsNullOrEmpty(plain)) return "";
            var bytes = ProtectedData.Protect(Encoding.UTF8.GetBytes(plain), SECRET_ENTROPY, DataProtectionScope.CurrentUser);
            return SECRET_PREFIX + Convert.ToBase64String(bytes);
        }

        public static string UnprotectSecret(string stored)
        {
            if (string.IsNullOrEmpty(stored)) return "";
            if (!stored.StartsWith(SECRET_PREFIX)) return stored;
            try
            {
                var bytes = ProtectedData.Unprotect(Convert.FromBase64String(stored.Substring(SECRET_PREFIX.Length)), SECRET_ENTROPY, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(bytes);
            }
            catch { return ""; }
        }

        // --- Backup of the data folder ---------------------------------------------------

        public static void NewDataBackup(string dataDir, string zipPath)
        {
            if (File.Exists(zipPath)) File.Delete(zipPath);
            ZipFile.CreateFromDirectory(dataDir, zipPath, CompressionLevel.Optimal, false);
        }

        // null if the zip is a Raintile backup that can be restored, otherwise why not
        public static string TestDataBackup(string zipPath)
        {
            ZipArchive zip;
            try { zip = ZipFile.OpenRead(zipPath); }
            catch (Exception e) { return "it is not a zip file (" + e.Message + ")"; }
            using (zip)
            {
                var names = zip.Entries.Select(e => e.FullName.Replace('\\', '/')).ToList();
                if (!names.Contains("Settings.inc")) return "it is not a Raintile backup (no Settings.inc)";
                foreach (var n in names)
                    if (n.StartsWith("/") || Regex.IsMatch(n, @"(^|/)\.\.(/|$)") || n.Contains(":")) return "it contains an unsafe path: " + n;
                return null;
            }
        }

        // Replaces the data folder with the backup; returns the folder where the
        // previous data was kept. On errors the previous data is put back.
        public static string RestoreDataBackup(string zipPath, string dataDir)
        {
            dataDir = Path.GetFullPath(dataDir).TrimEnd('\\', '/');
            string kept = dataDir + ".before-restore-" + DateTime.Now.ToString("yyyyMMdd-HHmmss");
            if (Directory.Exists(dataDir)) Directory.Move(dataDir, kept);
            try
            {
                Directory.CreateDirectory(dataDir);
                string root = dataDir + Path.DirectorySeparatorChar;
                using (var zip = ZipFile.OpenRead(zipPath))
                {
                    foreach (var entry in zip.Entries)
                    {
                        string dest = Path.GetFullPath(Path.Combine(dataDir, entry.FullName.Replace('/', Path.DirectorySeparatorChar).Replace('\\', Path.DirectorySeparatorChar)));
                        if (!dest.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new Exception("unsafe path in the backup: " + entry.FullName);
                        if (entry.FullName.EndsWith("/") || entry.FullName.EndsWith("\\")) { Directory.CreateDirectory(dest); continue; }
                        Directory.CreateDirectory(Path.GetDirectoryName(dest));
                        entry.ExtractToFile(dest, true);
                    }
                }
            }
            catch
            {
                try { Directory.Delete(dataDir, true); } catch { }
                if (Directory.Exists(kept)) Directory.Move(kept, dataDir);
                throw;
            }
            return kept;
        }

        // --- Category files ------------------------------------------------------------

        public static CategoryModel ReadCategory(string path)
        {
            string text = File.Exists(path) ? File.ReadAllText(path) : "";
            string imported = "";
            int i = text.IndexOf(IMPORT_MARKER, StringComparison.Ordinal);
            if (i < 0) i = text.IndexOf(OLD_IMPORT_MARKER, StringComparison.Ordinal);
            if (i >= 0) { imported = text.Substring(i); text = text.Substring(0, i); }

            var model = new CategoryModel { Imported = imported };
            var header = new List<string>();
            var pending = new List<string>();
            IniSection current = null;
            foreach (var line in Regex.Split(text, "\r?\n"))
            {
                string t = line.Trim();
                var m = Regex.Match(t, @"^\[(.+)\]$");
                if (m.Success)
                {
                    current = new IniSection { Name = m.Groups[1].Value.Trim(), Comments = new List<string>(pending) };
                    model.Sections.Add(current);
                    pending.Clear();
                }
                else if (t.StartsWith(";") || t == "")
                {
                    if (current != null) { if (t != "") pending.Add(line); }
                    else header.Add(line);
                }
                else if (current != null)
                {
                    m = Regex.Match(t, @"^([^=]+?)\s*=(.*)$");
                    if (m.Success) current.Keys.Add(new KeyValuePair<string, string>(m.Groups[1].Value.Trim(), m.Groups[2].Value.Trim()));
                }
            }
            model.Header = string.Join("\r\n", header).TrimEnd();
            return model;
        }

        public static string GetKey(IniSection s, string key)
        {
            if (s == null) return "";
            foreach (var kv in s.Keys) if (string.Equals(kv.Key, key, StringComparison.OrdinalIgnoreCase)) return kv.Value;
            return "";
        }

        public static void SetKey(IniSection s, string key, string value)
        {
            value = Regex.Replace(value ?? "", @"[\r\n]+", " ");   // one line: no extra keys or sections
            for (int i = 0; i < s.Keys.Count; i++)
            {
                if (string.Equals(s.Keys[i].Key, key, StringComparison.OrdinalIgnoreCase))
                {
                    if (value == "") s.Keys.RemoveAt(i);
                    else s.Keys[i] = new KeyValuePair<string, string>(s.Keys[i].Key, value);
                    return;
                }
            }
            if (value != "") s.Keys.Add(new KeyValuePair<string, string>(key, value));
        }

        public static void WriteCategory(string path, CategoryModel model)
        {
            var sb = new StringBuilder();
            if (!string.IsNullOrEmpty(model.Header)) sb.Append(model.Header + "\r\n");
            foreach (var s in model.Sections)
            {
                sb.Append("\r\n");
                foreach (var c in s.Comments) sb.Append(c + "\r\n");
                sb.Append("[" + s.Name + "]\r\n");
                foreach (var kv in s.Keys) sb.Append(kv.Key + "=" + kv.Value + "\r\n");
            }
            if (!string.IsNullOrEmpty(model.Imported)) sb.Append("\r\n" + model.Imported.TrimEnd() + "\r\n");
            File.WriteAllText(path, sb.ToString(), Utf8);
        }

        public static IniSection GetCategorySection(CategoryModel model)
        {
            foreach (var s in model.Sections) if (string.Equals(s.Name, "Category", StringComparison.OrdinalIgnoreCase)) return s;
            var n = new IniSection { Name = "Category" };
            model.Sections.Insert(0, n);
            return n;
        }

        public static List<IniSection> GetTiles(CategoryModel model)
        {
            return model.Sections.Where(s => !string.Equals(s.Name, "Category", StringComparison.OrdinalIgnoreCase)).ToList();
        }

        // Names of the tiles of the old automatic import (read-only)
        public static List<string> GetImportedNames(CategoryModel model)
        {
            return Regex.Matches(model.Imported ?? "", @"(?m)^\[(.+)\]\s*$").Cast<Match>().Select(m => m.Groups[1].Value.TrimEnd('\r')).ToList();
        }

        // --- Images ----------------------------------------------------------------------

        // Image 'name' in 'dir' (or an absolute path), with or without extension, as
        // the skin looks for it; null if not found
        public static string FindImage(string dir, string name)
        {
            string p = (name ?? "").Trim().Trim('"');
            if (p == "") return null;
            try
            {
                if (!Path.IsPathRooted(p)) p = Path.Combine(dir, p);
                if (Regex.IsMatch(p, @"\.\w+$")) return File.Exists(p) ? p : null;
                foreach (var e in IMAGE_EXTS) if (File.Exists(p + e)) return p + e;
            }
            catch { }
            return null;
        }

        // Background or logo of a tile: its Background=/Logo= key, otherwise the
        // image named after Image= or the tile
        public static string GetTileImage(string categoryBase, IniSection section, string kind)
        {
            string dir = Path.Combine(ImagesRoot, categoryBase, kind.ToLowerInvariant());
            string explicitName = GetKey(section, kind);
            if (explicitName != "") return FindImage(dir, explicitName);
            string image = GetKey(section, "Image");
            if (image == "") image = section.Name;
            return FindImage(dir, image);
        }

        public static string GetCategoryIcon(string categoryBase, IniSection catSection)
        {
            string icon = GetKey(catSection, "Icon");
            if (icon == "") icon = "icon";
            return FindImage(Path.Combine(ImagesRoot, categoryBase), icon);
        }

        // True if 'path' is a file directly inside 'folder' (a name with ..\ or a
        // full path can not lead anywhere else)
        public static bool TestInFolder(string path, string folder)
        {
            try
            {
                string parent = Path.GetDirectoryName(Path.GetFullPath(path));
                return string.Equals(parent, Path.GetFullPath(folder).TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }

        // Copies a picked image to the tile's default folder
        public static string CopyTileImage(string category, string kind, string tile, string source)
        {
            string dir = Path.Combine(ImagesRoot, category, kind);
            string dest = Path.Combine(dir, tile + Path.GetExtension(source).ToLowerInvariant());
            if (!TestInFolder(dest, dir)) throw new Exception("Not a valid tile name for an image file: " + tile);
            Directory.CreateDirectory(dir);
            // remove any previous image with another extension
            foreach (var f in Directory.GetFiles(dir))
                if (string.Equals(Path.GetFileNameWithoutExtension(f), tile, StringComparison.OrdinalIgnoreCase)
                    && !string.Equals(Path.GetFullPath(f), Path.GetFullPath(source), StringComparison.OrdinalIgnoreCase))
                    File.Delete(f);
            if (!string.Equals(Path.GetFullPath(dest), Path.GetFullPath(source), StringComparison.OrdinalIgnoreCase))
                File.Copy(source, dest, true);
            return dest;
        }

        // Renaming a tile: its default images follow it
        public static void RenameTileImages(string category, string oldName, string newName)
        {
            foreach (var kind in new[] { "background", "logo" })
            {
                string dir = Path.Combine(ImagesRoot, category, kind);
                if (!Directory.Exists(dir)) continue;
                foreach (var f in Directory.GetFiles(dir))
                {
                    if (!string.Equals(Path.GetFileNameWithoutExtension(f), oldName, StringComparison.OrdinalIgnoreCase)) continue;
                    string dest = Path.Combine(dir, newName + Path.GetExtension(f));
                    if (!TestInFolder(dest, dir)) continue;
                    if (!File.Exists(dest)) File.Move(f, dest);
                }
            }
        }

        public static List<FileInfo> GetCategoryFiles()
        {
            if (!Directory.Exists(CategoriesDir)) return new List<FileInfo>();
            return new DirectoryInfo(CategoriesDir).GetFiles("*.ini").OrderBy(f => f.Name, StringComparer.OrdinalIgnoreCase).ToList();
        }

        // Tile colours computed from the logos by Thumbs.ps1: logo path -> colour
        public static Dictionary<string, string> ReadLogoColors()
        {
            var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            string file = Path.Combine(Generated, "Colors.txt");
            if (!File.Exists(file)) return map;
            foreach (var line in File.ReadAllLines(file))
            {
                var parts = line.Split(new[] { '|' }, 3);
                if (parts.Length == 3 && parts[1] != "")
                {
                    try { map[Path.GetFullPath(parts[2])] = parts[1]; } catch { }
                }
            }
            return map;
        }

        // --- Names (as Scan.ps1) ----------------------------------------------------------

        // Name usable as an INI section and as a file name
        public static string GetTileName(string name)
        {
            string n = Regex.Replace(name ?? "", @"[\x00-\x1F\x7F]", " ");
            n = Regex.Replace(n, @"[\[\]]", "");
            n = Regex.Replace(n, "[\u2122\u00AE\u00A9]", "");
            n = Regex.Replace(n, @"[\\/:*?""<>|]", " ");
            n = Regex.Replace(n, @"\s+", " ").Trim().Trim('.', ' ').TrimStart(';').Trim('.', ' ');
            return n;
        }

        // Key to compare names: lower case, without spaces and light punctuation
        public static string GetNameKey(string name)
        {
            return Regex.Replace(GetTileName(name).ToLowerInvariant(), "[\\s\\-_:.,'!\u2019]", "");
        }

        public static HashSet<string> ReadSeen()
        {
            var seen = new HashSet<string>();
            if (File.Exists(SeenFile)) foreach (var l in File.ReadAllLines(SeenFile)) if (l != "") seen.Add(l);
            return seen;
        }

        public static HashSet<string> ReadKeepMissing()
        {
            var keep = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (File.Exists(KeepMissingFile)) foreach (var l in File.ReadAllLines(KeepMissingFile, Utf8)) if (l != "") keep.Add(l);
            return keep;
        }

        // --- Update check (as Update.ps1) -------------------------------------------------

        public static string GetInstalledVersion()
        {
            try
            {
                string ini = Path.Combine(Path.GetDirectoryName(Resources), "Raintile.ini");
                var m = Regex.Match(File.ReadAllText(ini), @"(?m)^\s*Version\s*=\s*(.+?)\s*$");
                if (m.Success) return m.Groups[1].Value;
            }
            catch { }
            return "0";
        }

        // Only addresses of this repository on GitHub, over https
        public static bool TestReleaseUrl(string url)
        {
            Uri u;
            if (!Uri.TryCreate(url ?? "", UriKind.Absolute, out u)) return false;
            return u.Scheme == "https" && u.Host == "github.com" && u.AbsolutePath.StartsWith("/" + Repository + "/", StringComparison.OrdinalIgnoreCase);
        }

        public static string GetSafeVersion(string text)
        {
            return Regex.IsMatch(text ?? "", @"^\d+(\.\d+){1,3}$") ? text : "";
        }

        // True if the file is a Rainmeter package (footer checked like the installer)
        public static bool TestRmskinPackage(string path)
        {
            try
            {
                var bytes = File.ReadAllBytes(path);
                if (bytes.Length < 32) return false;
                long size = BitConverter.ToInt64(bytes, bytes.Length - 16);
                string key = Encoding.ASCII.GetString(bytes, bytes.Length - 7, 7);
                return key == "RMSKIN\0" && size == bytes.Length - 16 && bytes[0] == 0x50 && bytes[1] == 0x4B;
            }
            catch { return false; }
        }

        public static Dictionary<string, object> ReadUpdateInfo()
        {
            if (!File.Exists(UpdateFile)) return null;
            try { return Json.Parse(File.ReadAllText(UpdateFile)) as Dictionary<string, object>; }
            catch { return null; }
        }
    }

    // Minimal JSON reader (objects, arrays, strings, numbers, booleans, null)
    public static class Json
    {
        public static object Parse(string text)
        {
            var ser = new System.Web.Script.Serialization.JavaScriptSerializer { MaxJsonLength = int.MaxValue };
            return ser.DeserializeObject(text);
        }

        public static string Str(Dictionary<string, object> o, string key)
        {
            object v;
            if (o == null || !o.TryGetValue(key, out v) || v == null) return "";
            if (v is bool) return (bool)v ? "True" : "False";
            return Convert.ToString(v, CultureInfo.InvariantCulture);
        }

        public static bool Bool(Dictionary<string, object> o, string key)
        {
            object v;
            if (o == null || !o.TryGetValue(key, out v) || v == null) return false;
            if (v is bool) return (bool)v;
            return string.Equals(Convert.ToString(v), "true", StringComparison.OrdinalIgnoreCase);
        }
    }
}
