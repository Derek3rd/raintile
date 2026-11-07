// Raintile Options: actions of the tile context menu that the skin cannot do
// itself, run without the window (RaintileOptions.exe ... -Action <action>):
//
//   runas   starts the tile's program as administrator (Windows asks for
//           confirmation, UAC)
//   remove  removes the tile from its category file, after asking, and
//           refreshes the skin (its images stay in Images\)
//
// The tile is read from Generated\TileAction.txt ("<file>|<tile name>"),
// written by the skin: the file must be one of the category files, and the
// command is read from that file, not taken from the command line.

using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;

namespace RaintileOptions
{
    static class TileAction
    {
        public static int Run(string action)
        {
            string tileFile = Path.Combine(Core.Generated, "TileAction.txt");
            if (!File.Exists(tileFile)) return 0;
            var parts = File.ReadAllText(tileFile, Core.Utf8).Split(new[] { '|' }, 2);
            try { File.Delete(tileFile); } catch { }
            if (parts.Length != 2) return 0;
            var file = Core.GetCategoryFiles().FirstOrDefault(f => f.Name.Equals(parts[0].Trim(), StringComparison.OrdinalIgnoreCase));
            string name = parts[1].Trim();
            if (file == null) return 0;
            var model = Core.ReadCategory(file.FullName);
            var section = Core.GetTiles(model).FirstOrDefault(s => s.Name == name);
            if (section == null)
            {
                if (Core.GetImportedNames(model).Contains(name))
                    Message("'" + name + "' comes from the old automatic import. Open Options > Import once: it becomes a normal tile, which can then be removed.");
                return 0;
            }

            if (action == "runas")
            {
                var target = SplitCommand(Core.GetKey(section, "Command"));
                if (target == null) return 0;
                try
                {
                    Process.Start(new ProcessStartInfo(target[0], target[1]) { UseShellExecute = true, Verb = "runas" });
                }
                catch (Win32Exception e) when (e.NativeErrorCode == 1223)
                {
                    // cancelled in the Windows prompt
                }
                catch (Exception e)
                {
                    Message("Could not start '" + name + "' as administrator: " + e.Message, MessageBoxImage.Warning);
                }
                return 0;
            }

            // remove
            string label = Core.GetKey(Core.GetCategorySection(model), "Name");
            if (label == "") label = Path.GetFileNameWithoutExtension(file.Name);
            if (Message("Remove '" + name + "' from " + label + "?\r\n\r\nIts images stay in the Images folder.",
                    MessageBoxImage.Question, MessageBoxButton.YesNo) != MessageBoxResult.Yes) return 0;
            model.Sections.Remove(section);
            Core.WriteCategory(file.FullName, model);
            OptionsApp.InvokeRainmeter("!Refresh \"" + Core.Config + "\"");
            return 0;
        }

        // Program and arguments of a command, as the skin reads it: "C:\x\a.exe" -b,
        // a.exe -b. null for URLs and bangs.
        static string[] SplitCommand(string command)
        {
            string c = command.Trim();
            if (c == "" || c.StartsWith("[") || c.Contains("://")) return null;
            var m = Regex.Match(c, "^\"([^\"]+)\"\\s*(.*)$");
            if (!m.Success) m = Regex.Match(c, "^(\\S+)\\s*(.*)$");
            return m.Success ? new[] { m.Groups[1].Value, m.Groups[2].Value } : null;
        }

        // A message box on top of the launcher (which covers the screen)
        static MessageBoxResult Message(string text, MessageBoxImage icon = MessageBoxImage.Information, MessageBoxButton buttons = MessageBoxButton.OK)
        {
            return MessageBox.Show(text, "Raintile", buttons, icon, MessageBoxResult.None, MessageBoxOptions.DefaultDesktopOnly);
        }
    }
}
