// Raintile Options: the Dashboard card (Dashboard page). The Dashboard is a
// category file with Type=Dashboard, kept apart from the other categories in
// the menu: here it is turned on and off (Hidden=1), named and given its grid;
// its widgets are edited under Dashboard > Widgets, like the tiles of a
// category.

using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;

namespace RaintileOptions
{
    public partial class OptionsApp
    {
        string FirstDashboard()
        {
            return Core.GetCategoryFiles().Select(f => f.Name).FirstOrDefault(IsDashboard);
        }

        Border NewDashCard()
        {
            var card = NewCard("Dashboard", "A page of widgets in the menu: processor, graphics card, memory, disks, network, temperatures, your skins.");
            var f = CardPanel(card);
            string file = FirstDashboard();
            if (file == null)
            {
                AddTo(f, NewText("There is no Dashboard in your categories.", 12.5, ResBrush("DimBrush"), false, true));
                var create = NewButton("Create the Dashboard", "AccentButton");
                create.HorizontalAlignment = HorizontalAlignment.Left;
                create.Margin = T(0, 10, 0, 4);
                create.Click += (s, e) => CreateDashboard();
                AddTo(f, create);
                return card;
            }
            var c = Core.GetCategorySection(GetModel(file));
            Action changed = () => { SetChanged(file); needsRefresh = true; UpdateDirty(); };

            var on = new CheckBox { Content = "Show the Dashboard in the menu", IsChecked = Core.GetKey(c, "Hidden").Trim() != "1" };
            AddTo(f, NewFormRow("Dashboard", on, "Off: it stays in Categories\\" + file + " with its widgets, but is not in the launcher (and nothing is measured)."));
            on.Click += (s, e) => { Core.SetKey(c, "Hidden", on.IsChecked == true ? "" : "1"); changed(); };

            var name = new TextBox { Text = Core.GetKey(c, "Name") };
            AddTo(f, NewFormRow("Name", name, "In the menu. Empty = the file name."));
            name.TextChanged += (s, e) => { Core.SetKey(c, "Name", name.Text.Trim()); changed(); };

            var nx = new TextBox { Text = Core.GetKey(c, "NX") };
            var ny = new TextBox { Text = Core.GetKey(c, "NY") };
            var grid = NewPairRow(nx, ny);
            AddTo(f, NewFormRow("Grid", grid, "Columns × rows of cells on screen; a widget can take more cells (Size). Empty = default (" + V("NX") + " × " + V("NY") + ")."));
            nx.TextChanged += (s, e) => { Core.SetKey(c, "NX", nx.Text.Trim()); changed(); };
            ny.TextChanged += (s, e) => { Core.SetKey(c, "NY", ny.Text.Trim()); changed(); };

            var opacity = NewOpacityBox("100% (default)");
            SelectOpacity(opacity, Core.GetKey(c, "TileOpacity"));
            AddTo(f, NewFormRow("Widget background", opacity, "Opacity of the box behind the widgets that have no Background of their own."));
            opacity.SelectionChanged += (s, e) =>
            {
                var item = opacity.SelectedItem as ComboBoxItem;
                if (item == null) return;
                Core.SetKey(c, "TileOpacity", (string)item.Tag);
                changed();
            };

            var edit = NewButton("Edit the widgets", "AccentButton");
            edit.HorizontalAlignment = HorizontalAlignment.Left;
            edit.Margin = T(0, 10, 0, 4);
            edit.Click += (s, e) => OpenNav("cat:" + file);
            AddTo(f, edit);
            return card;
        }

        // The default Dashboard of the skin, copied to the data folder (with its icon)
        void CreateDashboard()
        {
            try
            {
                string src = Path.Combine(Core.Resources, "Categories", "Dashboard.ini");
                string name = "Dashboard.ini";
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
                ShowDialog("Raintile", "The Dashboard could not be created: " + ex.Message);
                return;
            }
            needsRefresh = true;
            UpdateDirty();
            pages.Remove("dashboard");
            OpenNav("page:dashboard");
        }
    }
}
