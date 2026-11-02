// Raintile Options: schema of the pages (data in SchemaData.cs) and key names.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace RaintileOptions
{
    // Kinds: bool, choice (Choices = value, label), int / float (slider: Min,
    // Max, Step, Unit), size (pixels or % of the screen: Axis W/H), color,
    // text, font, category, stores, pad (gamepad buttons), key, combo (key with
    // modifiers), keys (two keys for one action: Pair), screen (ScreenX/Y/W/H),
    // info (text only), action (button), secret (hidden, saved encrypted).
    public class Item
    {
        public string Kind, Key, Label, Help = "";
        public List<string[]> Choices;
        public string[] Pair;
        public double Min, Max, Step = 1;
        public string Unit = "", Axis = "H";
    }

    public class Group
    {
        public string Title, Help;
        public bool Found, Other;
        public List<Item> Items = new List<Item>();
    }

    public class Page
    {
        public string Id, Title, Desc;
        public int Icon;
        public List<Group> Groups = new List<Group>();
    }

    // Menu on the left: a page, a group with sub-pages, or the categories
    public class NavNode
    {
        public string Page, Id, Title;
        public int Icon;
        public string[] Children;
        public bool Categories;
    }

    public static partial class Schema
    {
        public static Page ById(string id)
        {
            return Pages.FirstOrDefault(p => p.Id == id);
        }

        // Settings.inc keys the schema shows on a page
        public static List<string> SchemaKeys()
        {
            var keys = new List<string>();
            foreach (var page in Pages)
                foreach (var g in page.Groups)
                    foreach (var it in g.Items)
                    {
                        if (it.Kind == "screen") keys.AddRange(new[] { "ScreenX", "ScreenY", "ScreenW", "ScreenH" });
                        else if (it.Kind == "keys") keys.AddRange(it.Pair);
                        else if (it.Kind != "info" && it.Kind != "action") keys.Add(it.Key);
                    }
            return keys;
        }

        // --- Keys (HotKey plugin names) -------------------------------------------------

        static Dictionary<int, string> vkNames;
        static readonly int[] MODIFIER_VKS = { 0x10, 0x11, 0x12, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C };

        static Dictionary<int, string> VkNames
        {
            get
            {
                if (vkNames != null) return vkNames;
                var d = new Dictionary<int, string>
                {
                    { 0x08, "BACKSPACE" }, { 0x09, "TAB" }, { 0x0D, "ENTER" }, { 0x13, "PAUSE" }, { 0x14, "CAPSLOCK" }, { 0x1B, "ESCAPE" },
                    { 0x20, "SPACE" }, { 0x21, "PAGEUP" }, { 0x22, "PAGEDOWN" }, { 0x23, "END" }, { 0x24, "HOME" },
                    { 0x25, "LEFT" }, { 0x26, "UP" }, { 0x27, "RIGHT" }, { 0x28, "DOWN" }, { 0x2C, "PRINTSCREEN" }, { 0x2D, "INSERT" }, { 0x2E, "DELETE" },
                    { 0x5B, "LWIN" }, { 0x5C, "RWIN" }, { 0x5D, "MENU" },
                    { 0x6A, "MULT" }, { 0x6B, "ADD" }, { 0x6D, "SUBTRACT" }, { 0x6E, "DECIMAL" }, { 0x6F, "DIVIDE" },
                    { 0x90, "NUMLOCK" }, { 0x91, "SCROLLLOCK" },
                    { 0x10, "SHIFT" }, { 0x11, "CTRL" }, { 0x12, "ALT" },
                    { 0xA0, "LSHIFT" }, { 0xA1, "RSHIFT" }, { 0xA2, "LCTRL" }, { 0xA3, "RCTRL" }, { 0xA4, "LALT" }, { 0xA5, "RALT" },
                    { 0xBA, "COLON" }, { 0xBB, "PLUS" }, { 0xBC, "COMMA" }, { 0xBD, "MINUS" }, { 0xBE, "PERIOD" }, { 0xBF, "FORWARDSLASH" },
                    { 0xC0, "BACKTICK" }, { 0xDB, "LBRACKET" }, { 0xDC, "BACKSLASH" }, { 0xDD, "RBRACKET" }, { 0xDE, "QUOTE" },
                };
                for (int c = 0x30; c <= 0x39; c++) d[c] = ((char)c).ToString();
                for (int c = 0x41; c <= 0x5A; c++) d[c] = ((char)c).ToString();
                for (int n = 0; n <= 9; n++) d[0x60 + n] = "NUM" + n;
                for (int n = 1; n <= 24; n++) d[0x6F + n] = "F" + n;
                vkNames = d;
                return d;
            }
        }

        // Value written to Settings.inc for a key press: just the key, or (combo)
        // the held modifiers too ("CTRL ALT G"). null for keys without a name and,
        // in combos, for modifiers alone.
        public static string ToHotKey(int vk, bool ctrl, bool alt, bool shift, bool win, bool combo)
        {
            string name;
            if (!VkNames.TryGetValue(vk, out name)) return null;
            if (!combo) return name;
            if (MODIFIER_VKS.Contains(vk)) return null;
            var parts = new List<string>();
            if (ctrl) parts.Add("CTRL");
            if (alt) parts.Add("ALT");
            if (shift) parts.Add("SHIFT");
            if (win) parts.Add("LWIN");
            parts.Add(name);
            return string.Join(" ", parts);
        }

        // Readable form of a HotKey value: "CTRL ALT G" -> "Ctrl + Alt + G"
        public static string FormatHotKey(string value)
        {
            var tokens = Regex.Split((value ?? "").Trim(), @"\s+").Where(t => t != "").ToList();
            if (tokens.Count == 0) return "None";
            var labels = tokens.Select(t =>
            {
                string u = t.ToUpperInvariant(), l;
                if (KEY_LABELS.TryGetValue(u, out l)) return l;
                var m = Regex.Match(u, @"^NUM(\d)$");
                if (m.Success) return "Num " + m.Groups[1].Value;
                if (Regex.IsMatch(u, @"^(F\d{1,2}|.)$")) return u;
                return u.Substring(0, 1) + u.Substring(1).ToLowerInvariant();
            });
            return string.Join(" + ", labels);
        }
    }
}
