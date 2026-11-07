// Raintile Options: the example Dashboard (Widgets page). Widgets can go in
// any category; the Dashboard of the skin (system widgets on a 5 x 4 grid) is
// a normal category, kept as an example: added again here if it is missing.

using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;

namespace RaintileOptions
{
    public partial class OptionsApp
    {
        Border NewDashCard()
        {
            var card = NewCard("Widgets", "Any tile can be a widget, in any category: processor, graphics card, memory, disks, network, temperatures, your skins. Pick Widget in the tile editor.");
            var f = CardPanel(card);
            bool has = File.Exists(Path.Combine(Core.CategoriesDir, "Dashboard.ini"));
            AddTo(f, NewText(has
                ? "The example Dashboard is a normal category: find it under Categories."
                : "The example Dashboard (system widgets on a 5 \u00D7 4 grid) is not among your categories.", 12.5, ResBrush("DimBrush"), false, true));
            if (!has)
            {
                var create = NewButton("Add the example Dashboard", "AccentButton");
                create.HorizontalAlignment = HorizontalAlignment.Left;
                create.Margin = T(0, 10, 0, 4);
                create.Click += (s, e) => CreateDashboard();
                AddTo(f, create);
            }
            return card;
        }

        // The example Dashboard of the skin, copied to the data folder (with its icon)
        void CreateDashboard()
        {
            string name = "Dashboard.ini";
            try
            {
                string src = Path.Combine(Core.Resources, "Categories", "Dashboard.ini");
                for (int n = 2; File.Exists(Path.Combine(Core.CategoriesDir, name)); n++) name = "Dashboard" + n + ".ini";
                File.Copy(src, Path.Combine(Core.CategoriesDir, name));
                string images = Path.Combine(Core.Resources, "Images", "Dashboard");
                string dest = Path.Combine(Core.ImagesRoot, Path.GetFileNameWithoutExtension(name));
                Directory.CreateDirectory(dest);
                if (Directory.Exists(images))
                    foreach (var img in Directory.GetFiles(images))
                    {
                        string to = Path.Combine(dest, Path.GetFileName(img));
                        if (!File.Exists(to)) File.Copy(img, to);
                    }
            }
            catch (Exception ex)
            {
                ShowDialog("Raintile", "The Dashboard could not be added: " + ex.Message);
                return;
            }
            needsRefresh = true;
            UpdateDirty();
            pages.Remove("dashboard");
            OpenCategory(name);
        }
    }
}
