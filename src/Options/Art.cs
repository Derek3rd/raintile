// Raintile Options: images found online for a tile, for the Import page and
// the "Find online..." buttons of the tile editor. Sources, in this order:
//   - Steam's own servers (Steam games: their library background and logo,
//     no key needed),
//   - SteamGridDB (games of every store and many apps; needs the key),
//   - Dashboard Icons (github.com/homarr-labs/dashboard-icons, Apache-2.0:
//     logos of some 3500 apps and services, PNG),
//   - the icon of the website (links).
// Everything over https; downloads go to a temporary file first.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;

namespace RaintileOptions
{
    public class ArtChoice
    {
        public string Kind;      // "background" or "logo"
        public string Source;    // shown under the picture
        public string Thumb;     // small picture for the choice (https)
        public string Url;       // the image itself (https)
    }

    public static class Art
    {
        const string DashboardIcons = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/";
        static Dictionary<string, List<string>> diNames;   // normalised name or alias -> icon names

        static WebClient NewClient()
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var wc = new WebClient { Encoding = System.Text.Encoding.UTF8 };
            wc.Headers.Add("User-Agent", "Raintile");
            return wc;
        }

        // The image is there (a HEAD request answered 200 with an image)
        static bool Exists(string url)
        {
            try
            {
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                var req = (HttpWebRequest)WebRequest.Create(url);
                req.Method = "HEAD";
                req.UserAgent = "Raintile";
                req.Timeout = 8000;
                using (var r = (HttpWebResponse)req.GetResponse())
                    return r.StatusCode == HttpStatusCode.OK && (r.ContentType ?? "").StartsWith("image/");
            }
            catch { return false; }
        }

        // Steam app id of a tile: Source=Steam:<id> or a steam:// command
        public static string SteamId(string command, string source)
        {
            var m = Regex.Match(source ?? "", @"^steam:(\d+)$", RegexOptions.IgnoreCase);
            if (m.Success) return m.Groups[1].Value;
            m = Regex.Match(command ?? "", @"^steam://(?:rungameid|run|launch)/(\d{1,10})(?:\D|$)", RegexOptions.IgnoreCase);
            return m.Success ? m.Groups[1].Value : null;
        }

        // Name as Dashboard Icons writes it: "Visual Studio Code" -> visual-studio-code
        public static string Slug(string name)
        {
            string s = (name ?? "").ToLowerInvariant().Replace("&", " and ").Replace("+", " plus ");
            s = Regex.Replace(s, @"[^a-z0-9]+", "-").Trim('-');
            return s;
        }

        // --- Steam -------------------------------------------------------------

        static IEnumerable<string> SteamUrls(string id, string kind)
        {
            string file = kind == "background" ? "library_hero.jpg" : "logo.png";
            yield return "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/" + id + "/" + file;
            yield return "https://cdn.cloudflare.steamstatic.com/steam/apps/" + id + "/" + file;
        }

        // The first of Steam's addresses that has the image
        public static string SteamImage(string id, string kind)
        {
            if (string.IsNullOrEmpty(id)) return null;
            foreach (var url in SteamUrls(id, kind)) if (Exists(url)) return url;
            return null;
        }

        // --- SteamGridDB ---------------------------------------------------------

        static object SgdbGet(string key, string path)
        {
            using (var wc = NewClient())
            {
                wc.Headers.Add("Authorization", "Bearer " + key);
                var r = Json.Parse(wc.DownloadString("https://www.steamgriddb.com/api/v2/" + path)) as Dictionary<string, object>;
                return r != null && Json.Bool(r, "success") && r.ContainsKey("data") ? r["data"] : null;
            }
        }

        // Its game for a Steam id or a name (exact: only a game of that very name)
        public static Dictionary<string, object> SgdbGame(string key, string name, string steamId, bool exact)
        {
            if (string.IsNullOrEmpty(key)) return null;
            if (!string.IsNullOrEmpty(steamId))
                return SgdbGet(key, "games/steam/" + steamId) as Dictionary<string, object>;
            var list = SgdbGet(key, "search/autocomplete/" + Uri.EscapeDataString(name)) as object[];
            if (list == null) return null;
            foreach (var o in list)
            {
                var g = o as Dictionary<string, object>;
                if (g == null) continue;
                // (the same name apart from case, spaces and signs like (TM))
                if (!exact || Slug(Json.Str(g, "name")) == Slug(name)) return g;
            }
            return null;
        }

        static List<ArtChoice> SgdbImages(string key, string gameId, string kind, int max)
        {
            var list = new List<ArtChoice>();
            var data = SgdbGet(key, (kind == "background" ? "heroes" : "logos") + "/game/" + gameId) as object[];
            if (data == null) return list;
            foreach (var o in data)
            {
                var d = o as Dictionary<string, object>;
                string url = Json.Str(d, "url"), thumb = Json.Str(d, "thumb");
                if (!url.StartsWith("https://")) continue;
                list.Add(new ArtChoice { Kind = kind, Source = "SteamGridDB", Url = url, Thumb = thumb.StartsWith("https://") ? thumb : url });
                if (list.Count >= max) break;
            }
            return list;
        }

        // --- Dashboard Icons -------------------------------------------------------

        // Its list (names, aliases, light and dark versions), kept in
        // Generated\DashboardIcons.json and read again once a week
        static void LoadDashboardIcons()
        {
            if (diNames != null) return;
            string file = Path.Combine(Core.Generated, "DashboardIcons.json");
            string text = null;
            try
            {
                if (!File.Exists(file) || (DateTime.Now - File.GetLastWriteTime(file)).TotalDays > 7)
                {
                    using (var wc = NewClient()) text = wc.DownloadString(DashboardIcons + "metadata.json");
                    File.WriteAllText(file, text, Core.Utf8);
                }
            }
            catch { }
            try { if (text == null && File.Exists(file)) text = File.ReadAllText(file); } catch { }
            var names = new Dictionary<string, List<string>>();
            var root = text != null ? Json.Parse(text) as Dictionary<string, object> : null;
            if (root != null)
                foreach (var kv in root)
                {
                    var d = kv.Value as Dictionary<string, object>;
                    var icons = new List<string> { kv.Key };
                    var colors = d != null && d.ContainsKey("colors") ? d["colors"] as Dictionary<string, object> : null;
                    if (colors != null) foreach (var c in colors.Values) { string n = Convert.ToString(c); if (n != "" && !icons.Contains(n)) icons.Add(n); }
                    var keys = new List<string> { kv.Key };
                    var aliases = d != null && d.ContainsKey("aliases") ? d["aliases"] as object[] : null;
                    if (aliases != null) foreach (var a in aliases) keys.Add(Slug(Convert.ToString(a)));
                    foreach (var k in keys)
                        if (k != "" && !names.ContainsKey(k)) names[k] = icons;
                }
            diNames = names;
        }

        // Icons of an app: its name, then without words like "launcher" or "app"
        public static List<string> DashboardIconNames(string name)
        {
            LoadDashboardIcons();
            string slug = Slug(name);
            var tries = new List<string> { slug, Regex.Replace(slug, @"-(launcher|client|app|desktop|for-windows|beta|x64|64-bit)$", "") };
            foreach (var prefix in new[] { "microsoft-", "mozilla-", "the-" })
                if (slug.StartsWith(prefix)) tries.Add(slug.Substring(prefix.Length));
            foreach (var t in tries)
            {
                List<string> icons;
                if (t != "" && diNames.TryGetValue(t, out icons)) return icons;
            }
            return new List<string>();
        }

        public static string DashboardIconUrl(string icon) { return DashboardIcons + "png/" + icon + ".png"; }

        // --- Websites ----------------------------------------------------------------

        // Icons a website declares (apple-touch-icon, icon), largest first
        static List<string> SiteIcons(string address)
        {
            var list = new List<string>();
            Uri page;
            if (!Uri.TryCreate(address, UriKind.Absolute, out page) || (page.Scheme != "https" && page.Scheme != "http")) return list;
            var home = new Uri("https://" + page.Host + "/");
            var found = new List<KeyValuePair<int, string>>();
            try
            {
                string html;
                using (var wc = NewClient()) html = wc.DownloadString(home);
                if (html.Length > 600000) html = html.Substring(0, 600000);
                foreach (Match m in Regex.Matches(html, @"<link\b[^>]*>", RegexOptions.IgnoreCase))
                {
                    string tag = m.Value;
                    string rel = Regex.Match(tag, @"rel\s*=\s*[""']([^""']+)", RegexOptions.IgnoreCase).Groups[1].Value.ToLowerInvariant();
                    if (!rel.Contains("icon")) continue;
                    string href = WebUtility.HtmlDecode(Regex.Match(tag, @"href\s*=\s*[""']([^""']+)", RegexOptions.IgnoreCase).Groups[1].Value);
                    Uri u;
                    if (href == "" || !Uri.TryCreate(home, href, out u) || u.Scheme != "https") continue;
                    if (u.AbsolutePath.EndsWith(".svg", StringComparison.OrdinalIgnoreCase)) continue;
                    var size = Regex.Match(tag, @"sizes\s*=\s*[""'](\d+)", RegexOptions.IgnoreCase);
                    int px = size.Success ? int.Parse(size.Groups[1].Value) : rel.Contains("apple") ? 180 : 32;
                    found.Add(new KeyValuePair<int, string>(px, u.ToString()));
                }
            }
            catch { }
            found.Add(new KeyValuePair<int, string>(180, new Uri(home, "/apple-touch-icon.png").ToString()));
            foreach (var f in found.OrderByDescending(f => f.Key))
                if (!list.Contains(f.Value) && f.Key >= 64 && Exists(f.Value)) list.Add(f.Value);
            return list.Take(4).ToList();
        }

        // --- All together --------------------------------------------------------------

        // The choices for one kind of image of a tile (slow: call it off the
        // window's thread)
        public static List<ArtChoice> Find(string kind, string name, string command, string source, string sgdbKey, bool exactName = false)
        {
            var list = new List<ArtChoice>();
            string steamId = SteamId(command, source);
            try
            {
                string steam = SteamImage(steamId, kind);
                if (steam != null) list.Add(new ArtChoice { Kind = kind, Source = "Steam", Url = steam, Thumb = steam });
            }
            catch { }
            try
            {
                var game = SgdbGame(sgdbKey, name, steamId, exactName);
                string id = Json.Str(game, "id");
                if (id != "") list.AddRange(SgdbImages(sgdbKey, id, kind, 18));
            }
            catch { }
            if (kind == "logo")
            {
                try
                {
                    foreach (var icon in DashboardIconNames(name))
                    {
                        string url = DashboardIconUrl(icon);
                        list.Add(new ArtChoice { Kind = kind, Source = "Dashboard Icons", Url = url, Thumb = url });
                    }
                }
                catch { }
                if (Regex.IsMatch(command ?? "", @"^https?://", RegexOptions.IgnoreCase))
                {
                    try { foreach (var url in SiteIcons(command)) list.Add(new ArtChoice { Kind = kind, Source = "Website", Url = url, Thumb = url }); }
                    catch { }
                }
            }
            return list;
        }

        // Downloads a choice to a temporary file (its extension from the address);
        // the caller copies it to the tile's folder
        public static string Download(string url)
        {
            Uri u;
            if (!Uri.TryCreate(url, UriKind.Absolute, out u) || u.Scheme != "https") throw new Exception("not an https address");
            string ext = Path.GetExtension(u.AbsolutePath).ToLowerInvariant();
            if (!Core.IMAGE_EXTS.Contains(ext)) ext = ".png";
            string dir = Path.Combine(Path.GetTempPath(), "Raintile-art-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            string file = Path.Combine(dir, "image" + ext);
            using (var wc = NewClient()) wc.DownloadFile(u, file);
            return file;
        }
    }
}
