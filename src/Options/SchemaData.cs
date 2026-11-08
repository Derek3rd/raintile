// Raintile Options: the settings schema. The pages and their groups and items
// (Kind, Key, Label, Help...), the menu (NavTree), the default values, the
// gamepad buttons, the image sources and the labels of stores and keys.
// A new setting goes here and into @Resources/Settings.inc (tools/check.py
// compares the two); Data.ps1 merges it into the user's file.
using System.Collections.Generic;
namespace RaintileOptions
{
    public static partial class Schema
    {
        public static readonly List<Page> Pages = new List<Page>
        {
            new Page { Id = "general", Title = "General", Icon = 0xE713, Desc = "Where the launcher appears, its margins, and how it opens and closes.", Groups = new List<Group>
            {
                new Group { Title = "Screen", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "screen", Key = "ScreenX", Label = "Area", Help = "Where the launcher shows: a monitor, or its work area (the taskbar stays free)." },
                    new Item { Kind = "choice", Key = "LauncherMode", Label = "Mode", Help = "Full screen: all of the area. Window: drag an empty part of it to move it; it stays open when you click elsewhere. Docked: on a side of the screen, it comes in from there.", Choices = new List<string[]> { new[] { "Fullscreen", "Full screen" }, new[] { "Window", "Window" }, new[] { "Dock", "Docked on a side" } } },
                    new Item { Kind = "size", Key = "WindowW", Label = "Window width", Help = "", Axis = "W", When = "LauncherMode=Window" },
                    new Item { Kind = "size", Key = "WindowH", Label = "Window height", Help = "", Axis = "H", When = "LauncherMode=Window" },
                    new Item { Kind = "choice", Key = "DockSide", Label = "Docked side", Help = "", Choices = new List<string[]> { new[] { "Left", "Left" }, new[] { "Right", "Right" }, new[] { "Top", "Top" }, new[] { "Bottom", "Bottom" } }, When = "LauncherMode=Dock" },
                    new Item { Kind = "size", Key = "DockSize", Label = "Docked size", Help = "Width when docked left or right; height (of the screen height) when docked at the top or bottom.", Axis = "W", When = "LauncherMode=Dock" },
                    new Item { Kind = "bool", Key = "DockEdge", Label = "Open from the edge", Help = "Docked: it also opens when the mouse rests on that edge of the screen. Not while a full-screen program (e.g. a game) is in front.", When = "LauncherMode=Dock" },
                    new Item { Kind = "int", Key = "DockEdgeDelay", Label = "Edge delay", Help = "How long the mouse rests on the edge before it opens.", Min = 0.0, Max = 2000.0, Step = 50.0, Unit = "ms", When = "LauncherMode=Dock;DockEdge=1" },
                } },
                new Group { Title = "Margins", Help = "In pixels, or as a percentage of the screen.", Items = new List<Item>
                {
                    new Item { Kind = "size", Key = "PadX", Label = "Side margins", Help = "Also holds the vertical scrollbar.", Axis = "W" },
                    new Item { Kind = "size", Key = "PadY", Label = "Top and bottom margins", Help = "Also holds the horizontal scrollbar.", Axis = "H" },
                } },
                new Group { Title = "Opening and closing", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "StartHidden", Label = "Start hidden", Help = "Stay hidden when Rainmeter starts, until you open it with the shortcut or the gamepad." },
                    new Item { Kind = "bool", Key = "AutoHide", Label = "Hide when it loses focus", Help = "A click outside the launcher (e.g. on another monitor) or another program coming to the foreground hides it." },
                    new Item { Kind = "bool", Key = "CloseOnLaunch", Label = "Hide after launching a tile", Help = "" },
                    new Item { Kind = "choice", Key = "CloseAction", Label = "Close button (X)", Help = "Unloading frees memory, but the next opening is slower.", Choices = new List<string[]> { new[] { "[!CommandMeasure MeasureScript \"Hide()\"]", "Hide" }, new[] { "[!DeactivateConfig]", "Unload the skin" } } },
                    new Item { Kind = "choice", Key = "ShowZPos", Label = "Window level when shown", Help = "On the desktop, hiding on focus loss does not work.", Choices = new List<string[]> { new[] { "1", "On top" }, new[] { "2", "Always on top" }, new[] { "0", "Normal" }, new[] { "-2", "On the desktop" }, new[] { "", "Unchanged" } } },
                    new Item { Kind = "int", Key = "FadeDuration", Label = "Fade when opening and closing", Help = "Applies from the next time Rainmeter loads the skin.", Min = 0.0, Max = 1000.0, Step = 10.0, Unit = "ms" },
                } },
            } },
            new Page { Id = "tiles", Title = "Tiles", Icon = 0xE8A9, Desc = "How the tiles are laid out, on a grid or on a wheel (the pages below), and how they look.", Groups = new List<Group>
            {
                new Group { Title = null, Help = null, Items = new List<Item>
                {
                    new Item { Kind = "choice", Key = "ScrollMode", Label = "Layout", Help = "Grid: rows and columns. Wheel: one line of tiles on an arc, the selected one in the middle (all tiles one cell), suggested docked. Each has its page below; the page of the other one is greyed out in the menu.", Choices = new List<string[]> { new[] { "Grid", "Grid" }, new[] { "Wheel", "Wheel" } } },
                    new Item { Kind = "bool", Key = "InfiniteScroll", Label = "Infinite scroll", Help = "After the last row the first one comes back; with few tiles they repeat, so it still scrolls round." },
                } },
                new Group { Title = "Tile", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "color", Key = "TileColor", Label = "Default tile colour", Help = "" },
                    new Item { Kind = "bool", Key = "AutoTileColor", Label = "Colour from the logo", Help = "Tiles with a logo but no background image and no colour of their own get a dark colour taken from the logo." },
                    new Item { Kind = "int", Key = "TileRadius", Label = "Rounded corners", Help = "Radius of the corners of the tiles and of the highlight. 0 = square.", Min = 0.0, Max = 60.0, Step = 1.0, Unit = "px" },
                    new Item { Kind = "size", Key = "IconSize", Label = "Logo size", Help = "Box the tile logo fits in.", Axis = "H" },
                    new Item { Kind = "bool", Key = "LogoGreyscale", Label = "Greyscale logos", Help = "They turn to colour under the mouse." },
                    new Item { Kind = "bool", Key = "TileHover", Label = "Highlight the tile under the mouse", Help = "" },
                } },
                new Group { Title = "Labels", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "ShowLabels", Label = "Show tile labels", Help = "" },
                    new Item { Kind = "int", Key = "LabelFontSize", Label = "Label font size", Help = "", Min = 6.0, Max = 40.0, Step = 1.0, Unit = "pt", When = "ShowLabels=1" },
                    new Item { Kind = "size", Key = "LabelPad", Label = "Label margin", Help = "", Axis = "H", When = "ShowLabels=1" },
                } },
            } },
            new Page { Id = "grid", When = "ScrollMode=Grid", Title = "Grid", Icon = 0, Desc = "Rows and columns, scrolled by rows or columns. Each category can have its own grid (Categories).", Groups = new List<Group>
            {
                new Group { Title = "Grid", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "int", Key = "NX", Label = "Columns", Help = "", Min = 1.0, Max = 12.0, Step = 1.0, Unit = "" },
                    new Item { Kind = "int", Key = "NY", Label = "Rows", Help = "", Min = 1.0, Max = 8.0, Step = 1.0, Unit = "" },
                    new Item { Kind = "choice", Key = "ScrollDir", Label = "Scroll direction", Help = "", Choices = new List<string[]> { new[] { "V", "Vertical" }, new[] { "H", "Horizontal" } } },
                    new Item { Kind = "int", Key = "ScrollStep", Label = "Rows per mouse wheel notch", Help = "", Min = 1.0, Max = 5.0, Step = 1.0, Unit = "" },
                    new Item { Kind = "size", Key = "Gap", Label = "Space between tiles", Help = "", Axis = "H" },
                    new Item { Kind = "bool", Key = "EdgeFade", Label = "Fade at the edge of the grid", Help = "Tiles cut by the edge (e.g. a tall tile only partly on screen) fade into the background there, to show they go on." },
                } },
                new Group { Title = "Scrollbar", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "size", Key = "ScrollBarSize", Label = "Scrollbar thickness", Help = "", Axis = "H" },
                    new Item { Kind = "color", Key = "ScrollTrackColor", Label = "Scrollbar track", Help = "" },
                    new Item { Kind = "color", Key = "ScrollThumbColor", Label = "Scrollbar thumb", Help = "" },
                } },
            } },
            new Page { Id = "wheel", When = "ScrollMode=Wheel", Title = "Wheel", Icon = 0xE7AD, Desc = "One line of tiles on an arc, the selected tile in the middle, the categories on an inner wheel. Made for the docked launcher; it works in every mode. The Preview button (at the bottom) shows it as you change it.", Groups = new List<Group>
            {
                new Group { Title = "Wheel", Help = "Sizes in percent: of the launcher's length for the radius, of a tile for the spacing, of the screen for the tiles.", Items = new List<Item>
                {
                    new Item { Kind = "choice", Key = "WheelAxis", Label = "Direction", Help = "Auto: along the side when docked, across otherwise.", Choices = new List<string[]> { new[] { "Auto", "Auto" }, new[] { "Vertical", "Vertical" }, new[] { "Horizontal", "Horizontal" } } },
                    new Item { Kind = "choice", Key = "WheelCurve", Label = "Curve", Help = "", Choices = new List<string[]> { new[] { "Out", "Bulging towards the screen" }, new[] { "In", "Hollow" } } },
                    new Item { Kind = "int", Key = "WheelRadius", Label = "Radius", Help = "", Min = 25.0, Max = 300.0, Step = 5.0, Unit = "%" },
                    new Item { Kind = "int", Key = "WheelSpacing", Label = "Space between tiles", Help = "Under 100 the tiles overlap; the middle one stays on top.", Min = 30.0, Max = 160.0, Step = 2.0, Unit = "%" },
                    new Item { Kind = "int", Key = "WheelAnchor", Label = "Place of the selected tile", Help = "Across the launcher, from its docked side.", Min = 10.0, Max = 90.0, Step = 1.0, Unit = "%" },
                    new Item { Kind = "int", Key = "WheelTileSize", Label = "Tile size", Help = "", Min = 8.0, Max = 40.0, Step = 1.0, Unit = "%" },
                    new Item { Kind = "int", Key = "WheelVisible", Label = "Tiles shown", Help = "", Min = 3.0, Max = 15.0, Step = 2.0, Unit = "" },
                    new Item { Kind = "int", Key = "WheelFade", Label = "Fade at the ends", Help = "", Min = 0.0, Max = 90.0, Step = 1.0, Unit = "%" },
                    new Item { Kind = "choice", Key = "WheelLabels", Label = "Names", Help = "", Choices = new List<string[]> { new[] { "Center", "Middle tile only" }, new[] { "All", "All tiles" } } },
                } },
                new Group { Title = "Turning", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "int", Key = "WheelStepTime", Label = "Turn time", Help = "For one tile.", Min = 60.0, Max = 600.0, Step = 10.0, Unit = "ms" },
                    new Item { Kind = "choice", Key = "WheelHover", Label = "Mouse on a side tile", Help = "", Choices = new List<string[]> { new[] { "Turn", "Turns the wheel to it" }, new[] { "Highlight", "Highlights it" } } },
                    new Item { Kind = "choice", Key = "WheelClick", Label = "Click on a side tile", Help = "", Choices = new List<string[]> { new[] { "Launch", "Launches it" }, new[] { "Center", "Brings it to the middle" } } },
                } },
                new Group { Title = "Categories", Help = "Sizes in percent of a tile.", Items = new List<Item>
                {
                    new Item { Kind = "choice", Key = "WheelMenu", Label = "Categories", Help = "Ring: on an inner wheel, Q / E or LB / RB turn it.", Choices = new List<string[]> { new[] { "Ring", "Inner wheel" }, new[] { "Bar", "Menu at the top" } } },
                    new Item { Kind = "int", Key = "WheelMenuGap", Label = "Inner wheel: distance", Help = "From the wheel of tiles.", Min = 10.0, Max = 150.0, Step = 2.0, Unit = "%", When = "WheelMenu=Ring" },
                    new Item { Kind = "int", Key = "WheelMenuSize", Label = "Inner wheel: entries", Help = "", Min = 20.0, Max = 80.0, Step = 1.0, Unit = "%", When = "WheelMenu=Ring" },
                } },
                new Group { Title = "Look", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "WheelIconsOnly", Label = "Logos only", Help = "The tiles show their logo on a colour taken from it. Tiles without a logo keep their background." },
                    new Item { Kind = "bool", Key = "WheelBackdrop", Label = "Background of the selected tile", Help = "The launcher's background takes the background image of the tile in the middle." },
                    new Item { Kind = "int", Key = "WheelBackdropOpacity", Label = "Its opacity", Help = "Over the launcher's background colour.", Min = 5.0, Max = 100.0, Step = 5.0, Unit = "%", When = "WheelBackdrop=1" },
                    new Item { Kind = "color", Key = "TopBarColor", Label = "Band behind the top row", Help = "With the wheel showing the selected tile's background: one rounded band behind the clock, the search and the buttons.", When = "WheelBackdrop=1" },
                } },
            } },
            new Page { Id = "backgrounds", Title = "Backgrounds", Icon = 0xE91B, Desc = "How the background images of the tiles move.", Groups = new List<Group>
            {
                new Group { Title = "Tile backgrounds", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "choice", Key = "BgStyle", Label = "Style", Help = "Crop: fixed. Pan: under the mouse the image slowly slides. Parallax: it moves slower than the tile while scrolling. Zoom: it grows slightly under the mouse.", Choices = new List<string[]> { new[] { "Crop", "Crop" }, new[] { "Pan", "Pan" }, new[] { "Parallax", "Parallax" }, new[] { "Zoom", "Zoom" } } },
                    new Item { Kind = "float", Key = "BgOverscan", Label = "Overscan", Help = "How much larger than the tile the image is: room to move.", Min = 1.0, Max = 1.5, Step = 0.01, Unit = "\u00D7", When = "BgStyle=Pan|Parallax|Zoom" },
                    new Item { Kind = "int", Key = "BgPanFrames", Label = "Pan length", Help = "", Min = 30.0, Max = 600.0, Step = 10.0, Unit = "steps", When = "BgStyle=Pan" },
                    new Item { Kind = "float", Key = "BgHoverZoom", Label = "Zoom amount", Help = "", Min = 1.0, Max = 1.3, Step = 0.01, Unit = "\u00D7", When = "BgStyle=Zoom" },
                } },
            } },
            new Page { Id = "playtime", Title = "Play time and updates", Icon = 0, Desc = "The line on the tiles with the play time and the last launch, and the Steam updates waiting.", Groups = new List<Group>
            {
                new Group { Title = "Play time", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "choice", Key = "TileInfo", Label = "Play time and last launch", Help = "A line on the tile, at the top left unless moved in the preview of the tile: hours played (Steam games) and when it was last launched. Tiles of games no longer installed always say so.", Choices = new List<string[]> { new[] { "Hover", "On the highlighted tile" }, new[] { "Always", "Always" }, new[] { "Never", "Never" } } },
                    new Item { Kind = "int", Key = "InfoFontSize", Label = "Play time font size", Help = "", Min = 6.0, Max = 30.0, Step = 1.0, Unit = "pt", When = "TileInfo=Hover|Always" },
                    new Item { Kind = "bool", Key = "TrackPlaytime", Label = "Measure play time outside Steam", Help = "The background helper looks for the game a tile starts and counts how long it runs." },
                } },
                new Group { Title = "Steam updates", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "GameUpdates", Label = "Steam updates waiting", Help = "Steam games with an update to download say so on a line above the play time, always shown, and their tile gets a border. While it downloads the line follows it live." },
                    new Item { Kind = "text", Key = "DownloadInfo", Label = "What the update line says", Help = "Any of: percent, size (downloaded / total), speed, eta (time left), schedule (when Steam will download it), separated by spaces.", When = "GameUpdates=1" },
                    new Item { Kind = "choice", Key = "DownloadStyle", Label = "Download on the tile", Help = "How the progress of a download shows on its tile.", Choices = new List<string[]> { new[] { "Bar", "A bar along the bottom" }, new[] { "Greyscale", "Background in greyscale, coloured again as it goes" }, new[] { "Both", "Both" } }, When = "GameUpdates=1" },
                    new Item { Kind = "color", Key = "DownloadColor1", Label = "Colour 1", Help = "Border of a tile with an update (a gradient from 1 to 2) and the bar.", When = "GameUpdates=1" },
                    new Item { Kind = "color", Key = "DownloadColor2", Label = "Colour 2", Help = "Other end of the border gradient.", When = "GameUpdates=1" },
                    new Item { Kind = "int", Key = "UpdateGlowTime", Label = "Border turning", Help = "Seconds the border turns when the launcher opens. 0 = it stays still.", Min = 0.0, Max = 10.0, Step = 1.0, Unit = "s", When = "GameUpdates=1" },
                } },
            } },
            new Page { Id = "toprow", Title = "Top row", Icon = 0xE700, Desc = "The row at the top: the category menu and the buttons; the shortcuts, the clock and the search on the pages below.", Groups = new List<Group>
            {
                new Group { Title = "Category menu", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "choice", Key = "MenuMode", Label = "Show", Help = "A category without an icon always shows its name.", Choices = new List<string[]> { new[] { "IconText", "Icon and text" }, new[] { "Icon", "Icon only" }, new[] { "Text", "Text only" } } },
                    new Item { Kind = "int", Key = "MenuFontSize", Label = "Menu font size", Help = "", Min = 6.0, Max = 40.0, Step = 1.0, Unit = "pt" },
                    new Item { Kind = "size", Key = "MenuH", Label = "Height", Help = "", Axis = "H" },
                    new Item { Kind = "size", Key = "MenuIconSize", Label = "Icon size", Help = "", Axis = "H" },
                    new Item { Kind = "size", Key = "MenuIconGap", Label = "Space between icon and text", Help = "", Axis = "W" },
                    new Item { Kind = "size", Key = "MenuItemPad", Label = "Entry padding", Help = "", Axis = "W" },
                    new Item { Kind = "size", Key = "MenuGap", Label = "Space between entries", Help = "", Axis = "W" },
                    new Item { Kind = "size", Key = "MenuRadius", Label = "Corner radius", Help = "", Axis = "H" },
                    new Item { Kind = "int", Key = "MenuIconDimAlpha", Label = "Opacity of inactive icons", Help = "0 = invisible, 255 = as the active one.", Min = 0.0, Max = 255.0, Step = 5.0, Unit = "/ 255" },
                    new Item { Kind = "color", Key = "ActiveCategoryColor", Label = "Active category", Help = "" },
                    new Item { Kind = "color", Key = "HoverCategoryColor", Label = "Category under the mouse", Help = "" },
                } },
                new Group { Title = "Buttons", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "int", Key = "CloseSize", Label = "Size of the X and gear buttons", Help = "", Min = 8.0, Max = 40.0, Step = 1.0, Unit = "pt" },
                    new Item { Kind = "bool", Key = "ShowPower", Label = "Power button", Help = "Left of the gear: Lock, Sleep, Restart, Shut down. Restart and Shut down want a second click." },
                } },
            } },
            new Page { Id = "shortcuts", Title = "Favorites and Recent", Icon = 0, Desc = "Categories made of the tiles of the others: the icon buttons right of the clock.", Groups = new List<Group>
            {
                new Group { Title = "Favorites, Recent, Not played yet", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "ShowFavorites", Label = "Favorites", Help = "Right click a tile > Add to Favorites." },
                    new Item { Kind = "bool", Key = "ShowRecent", Label = "Recent", Help = "" },
                    new Item { Kind = "choice", Key = "RecentOrder", Label = "Recent shows", Help = "", Choices = new List<string[]> { new[] { "Recent", "Last launched" }, new[] { "MostUsed", "Most used" } }, When = "ShowRecent=1" },
                    new Item { Kind = "int", Key = "RecentCount", Label = "Tiles in Recent", Help = "", Min = 1.0, Max = 48.0, Step = 1.0, Unit = "", When = "ShowRecent=1" },
                    new Item { Kind = "bool", Key = "ShowUnplayed", Label = "Not played yet", Help = "Tiles never launched, the ones added last first." },
                    new Item { Kind = "int", Key = "UnplayedCount", Label = "Tiles in Not played yet", Help = "", Min = 1.0, Max = 96.0, Step = 1.0, Unit = "", When = "ShowUnplayed=1" },
                } },
            } },
            new Page { Id = "clock", Title = "Clock", Icon = 0, Desc = "At the top left, updated every minute while the launcher is visible.", Groups = new List<Group>
            {
                new Group { Title = "Clock", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "ShowClock", Label = "Clock", Help = "" },
                    new Item { Kind = "bool", Key = "ShowDate", Label = "Date", Help = "Next to the time, in the language of Windows.", When = "ShowClock=1" },
                    new Item { Kind = "text", Key = "ClockFormat", Label = "Time format", Help = "%H:%M = 14:05, %#I:%M %p = 2:05 PM.", When = "ShowClock=1" },
                    new Item { Kind = "text", Key = "DateFormat", Label = "Date format", Help = "%A %#d %B = Monday 2 November, %#d/%m/%Y = 2/11/2026.", When = "ShowClock=1;ShowDate=1" },
                    new Item { Kind = "int", Key = "ClockFontSize", Label = "Time font size", Help = "", Min = 8.0, Max = 60.0, Step = 1.0, Unit = "pt", When = "ShowClock=1" },
                } },
            } },
            new Page { Id = "search", Title = "Search", Icon = 0xE721, Desc = "The search bar at the top left searches the tiles of every category.", Groups = new List<Group>
            {
                new Group { Title = "Search bar", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "SearchHover", Label = "Open on hover", Help = "Only the magnifier until the mouse is over it; it stays open while you type and while a search is shown." },
                    new Item { Kind = "size", Key = "SearchW", Label = "Width", Help = "When open.", Axis = "W" },
                    new Item { Kind = "text", Key = "SearchPlaceholder", Label = "Text in the empty bar", Help = "" },
                } },
                new Group { Title = "Filter bar", Help = "Chips above the search results, one per tag (Tags of the tiles) and per store: a click shows only the results that have it.", Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "FilterBar", Label = "Filter bar", Help = "" },
                    new Item { Kind = "bool", Key = "FilterStores", Label = "A chip per store", Help = "Only when the tiles come from at least two stores.", When = "FilterBar=1" },
                    new Item { Kind = "size", Key = "FilterH", Label = "Chip height", Help = "", Axis = "H", When = "FilterBar=1" },
                    new Item { Kind = "size", Key = "FilterGap", Label = "Space between chips", Help = "", Axis = "W", When = "FilterBar=1" },
                    new Item { Kind = "size", Key = "FilterPad", Label = "Chip padding", Help = "", Axis = "W", When = "FilterBar=1" },
                    new Item { Kind = "int", Key = "FilterFontSize", Label = "Font size", Help = "", Min = 6.0, Max = 30.0, Step = 1.0, Unit = "pt", When = "FilterBar=1" },
                } },
            } },
            new Page { Id = "theme", Title = "Theme", Icon = 0xE790, Desc = "The font and the colours the whole launcher shares; the colours of one part are on its page. Colours can be written as R,G,B,A or #RRGGBBAA: click the swatch to pick one.", Groups = new List<Group>
            {
                new Group { Title = "Text", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "font", Key = "FontFace", Label = "Font", Help = "" },
                    new Item { Kind = "color", Key = "TextColor", Label = "Text", Help = "" },
                    new Item { Kind = "color", Key = "TextDimColor", Label = "Dimmed text", Help = "" },
                } },
                new Group { Title = "Colours", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "color", Key = "BgColor", Label = "Launcher background", Help = "" },
                    new Item { Kind = "color", Key = "AccentColor", Label = "Accent", Help = "Highlight border, scrollbar, buttons under the mouse." },
                    new Item { Kind = "color", Key = "HoverColor", Label = "Highlight fill", Help = "" },
                } },
            } },
            new Page { Id = "animations", Title = "Animations", Icon = 0xE945, Desc = "They only run while something moves: at rest the launcher uses no CPU. Lengths are in steps of 16 ms.", Groups = new List<Group>
            {
                new Group { Title = "Effects", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "AnimOpen", Label = "Tiles appear when opening", Help = "" },
                    new Item { Kind = "bool", Key = "AnimCategory", Label = "Tiles appear on category change", Help = "The menu pill slides too." },
                    new Item { Kind = "bool", Key = "AnimHover", Label = "Sliding highlight", Help = "" },
                    new Item { Kind = "bool", Key = "AnimScroll", Label = "Smooth scrolling", Help = "" },
                    new Item { Kind = "bool", Key = "AnimLogoZoom", Label = "Logo zoom under the mouse", Help = "" },
                    new Item { Kind = "float", Key = "HoverLogoScale", Label = "Logo zoom", Help = "", Min = 1.0, Max = 2.0, Step = 0.05, Unit = "\u00D7", When = "AnimLogoZoom=1" },
                } },
                new Group { Title = "Appearing tiles", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "int", Key = "AnimAppearFrames", Label = "Length", Help = "", Min = 1.0, Max = 60.0, Step = 1.0, Unit = "steps" },
                    new Item { Kind = "int", Key = "AnimStagger", Label = "Delay between one tile and the next", Help = "", Min = 0.0, Max = 10.0, Step = 1.0, Unit = "steps" },
                    new Item { Kind = "int", Key = "AnimSlide", Label = "Upward slide", Help = "", Min = 0.0, Max = 200.0, Step = 1.0, Unit = "px" },
                } },
                new Group { Title = "Smoothing", Help = "Lower is smoother and slower, 1 is instant.", Items = new List<Item>
                {
                    new Item { Kind = "float", Key = "AnimSmooth", Label = "Base", Help = "", Min = 0.05, Max = 1.0, Step = 0.01, Unit = "" },
                    new Item { Kind = "float", Key = "AnimScrollSmooth", Label = "Scrolling", Help = "", Min = 0.05, Max = 1.0, Step = 0.01, Unit = "" },
                    new Item { Kind = "float", Key = "AnimHoverSmooth", Label = "Highlight", Help = "", Min = 0.05, Max = 1.0, Step = 0.01, Unit = "" },
                    new Item { Kind = "float", Key = "AnimPillSmooth", Label = "Menu pill", Help = "", Min = 0.05, Max = 1.0, Step = 0.01, Unit = "" },
                    new Item { Kind = "float", Key = "AnimLogoSmooth", Label = "Logo zoom and colour", Help = "", Min = 0.05, Max = 1.0, Step = 0.01, Unit = "" },
                } },
                new Group { Title = "Tile launch", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "LaunchAnimation", Label = "Full-screen expansion", Help = "The tile expands to full screen before the launcher hides." },
                    new Item { Kind = "int", Key = "LaunchAnimFrames", Label = "Expansion length", Help = "", Min = 1.0, Max = 60.0, Step = 1.0, Unit = "steps", When = "LaunchAnimation=1" },
                    new Item { Kind = "int", Key = "LaunchHold", Label = "Time at full screen", Help = "", Min = 0.0, Max = 5000.0, Step = 100.0, Unit = "ms", When = "LaunchAnimation=1" },
                    new Item { Kind = "size", Key = "LaunchLogoSize", Label = "Logo size at full screen", Help = "", Axis = "H", When = "LaunchAnimation=1" },
                    new Item { Kind = "int", Key = "LaunchFontSize", Label = "Text size for tiles without a logo", Help = "", Min = 8.0, Max = 120.0, Step = 1.0, Unit = "pt", When = "LaunchAnimation=1" },
                } },
            } },
            new Page { Id = "keybindings", Title = "Keybindings", Icon = 0xE765, Desc = "Click a key and press the new one: the keys that open and close the launcher here, the keyboard and the gamepad on the pages below.", Groups = new List<Group>
            {
                new Group { Title = "Open and close", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "combo", Key = "OpenHotKey", Label = "Open / close the launcher", Help = "Works everywhere, also while the launcher is hidden. Hold the modifiers, then press the key." },
                    new Item { Kind = "key", Key = "CloseHotKey", Label = "Close", Help = "Closes the search first, if it is open." },
                    new Item { Kind = "choice", Key = "TileKeysWhen", Label = "Tile hot keys", Help = "When the key combinations of the tiles (tile editor > Hot key) start them. Only with the launcher open, the keys stay free for other programs the rest of the time.", Choices = new List<string[]> { new[] { "Always", "Always, also with the launcher closed" }, new[] { "Open", "Only with the launcher open" } } },
                } },
            } },
            new Page { Id = "keys", Title = "Keyboard", Icon = 0xE765, Desc = "Navigation keys only work while the launcher is visible.", Groups = new List<Group>
            {
                new Group { Title = "Navigation", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "KeyboardNav", Label = "Keyboard navigation", Help = "" },
                    new Item { Kind = "keys", Key = "NavUp", Label = "Move up", Help = "", Pair = new[] { "NavUp", "NavUp2" }, When = "KeyboardNav=1" },
                    new Item { Kind = "keys", Key = "NavDown", Label = "Move down", Help = "", Pair = new[] { "NavDown", "NavDown2" }, When = "KeyboardNav=1" },
                    new Item { Kind = "keys", Key = "NavLeft", Label = "Move left", Help = "", Pair = new[] { "NavLeft", "NavLeft2" }, When = "KeyboardNav=1" },
                    new Item { Kind = "keys", Key = "NavRight", Label = "Move right", Help = "", Pair = new[] { "NavRight", "NavRight2" }, When = "KeyboardNav=1" },
                    new Item { Kind = "keys", Key = "NavConfirm", Label = "Launch the highlighted tile", Help = "Acts when the key is released.", Pair = new[] { "NavConfirm", "NavConfirm2" }, When = "KeyboardNav=1" },
                    new Item { Kind = "key", Key = "NavPrevCategory", Label = "Previous category", Help = "", When = "KeyboardNav=1" },
                    new Item { Kind = "key", Key = "NavNextCategory", Label = "Next category", Help = "", When = "KeyboardNav=1" },
                    new Item { Kind = "key", Key = "NavSearch", Label = "Search", Help = "", When = "KeyboardNav=1" },
                } },
            } },
            new Page { Id = "gamepad", Title = "Gamepad", Icon = 0xE7FC, Desc = "Xbox and compatible (XInput) controllers, read by a small background helper.", Groups = new List<Group>
            {
                new Group { Title = "Controller", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "Gamepad", Label = "Gamepad support", Help = "" },
                    new Item { Kind = "pad", Key = "GamepadToggle", Label = "Open / close", Help = "Buttons to hold together.", When = "Gamepad=1" },
                    new Item { Kind = "int", Key = "GamepadDeadZone", Label = "Stick dead zone", Help = "How far the stick moves before it counts.", Min = 0.0, Max = 32767.0, Step = 500.0, Unit = "/ 32767", When = "Gamepad=1" },
                    new Item { Kind = "int", Key = "GamepadRepeatDelay", Label = "Repeat delay", Help = "Holding a direction: wait before it repeats.", Min = 50.0, Max = 1000.0, Step = 10.0, Unit = "ms", When = "Gamepad=1" },
                    new Item { Kind = "int", Key = "GamepadRepeatRate", Label = "Repeat interval", Help = "", Min = 30.0, Max = 500.0, Step = 10.0, Unit = "ms", When = "Gamepad=1" },
                } },
                new Group { Title = "Buttons", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "info", Key = "", Label = "D-pad / left stick", Help = "Move the highlight" },
                    new Item { Kind = "info", Key = "", Label = "A", Help = "Launch the highlighted tile" },
                    new Item { Kind = "info", Key = "", Label = "B", Help = "Close the search, or the launcher" },
                    new Item { Kind = "info", Key = "", Label = "LB / RB", Help = "Previous / next category" },
                    new Item { Kind = "pad", Key = "GamepadSearch", Label = "Search with the on-screen keyboard", Help = "D-pad/stick move on it, A types, X deletes, Start keeps the results, B closes.", When = "Gamepad=1" },
                    new Item { Kind = "info", Key = "", Label = "LT / RT", Help = "Filter chips of the search results" },
                    new Item { Kind = "pad", Key = "GamepadOptions", Label = "Open these options", Help = "As the gear. RS is the right stick click. Not on a button of the search or of Open / close.", When = "Gamepad=1" },
                } },
            } },
            new Page { Id = "dashboard", Title = "Widgets", Icon = 0xE9D2, Desc = "Tiles that show something instead of starting it, in any category: CPU, GPU, memory, disks, network, processes, system, temperatures, skins and custom widgets.", Groups = new List<Group>
            {
                new Group { Title = null, Help = null, Dash = true, Items = new List<Item>
                {
                } },
                new Group { Title = "Data", Help = "Any tile becomes a widget with Widget in the tile editor (Categories > the category > the tile), with its size and background.", Items = new List<Item>
                {
                    new Item { Kind = "int", Key = "DashInterval", Label = "Update every", Help = "Only while a category with widgets is on screen.", Min = 250.0, Max = 5000.0, Step = 250.0, Unit = "ms" },
                    new Item { Kind = "info", Key = "", Label = "Temperatures and fans", Help = "From LibreHardwareMonitor (free, open source): keep it running with Options > Remote Web Server > Run on (and Run On Windows Startup). Without it, from HWiNFO with Settings > Shared Memory Support on (its free version turns it off after 12 hours)." },
                    new Item { Kind = "int", Key = "SensorPort", Label = "LibreHardwareMonitor port", Help = "The port of its web server: Options > Remote Web Server > Port in LibreHardwareMonitor (8085 unless changed).", Min = 1.0, Max = 65535.0, Step = 1.0, Unit = "", NoSlider = true },
                    new Item { Kind = "info", Key = "", Label = "Custom widgets", Help = "Rainmeter .ini files in the Widgets folder of your data: Widget=custom, Param=<file name>." },
                } },
                new Group { Title = null, Help = null, Market = true, Items = new List<Item>
                {
                } },
            } },
            new Page { Id = "import", Title = "Import", Icon = 0xE896, Desc = "Games and apps installed on this PC: pick the ones to add, they become normal tiles with their images. Nothing is added by itself.", Groups = new List<Group>
            {
                new Group { Title = null, Help = null, Found = true, Items = new List<Item>
                {
                } },
                new Group { Title = "Search", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "stores", Key = "ImportStores", Label = "Where to look", Help = "" },
                    new Item { Kind = "text", Key = "ImportFolders", Label = "Your folders", Help = "With Your folders on: folders of programs (portable games, emulators...). Every .exe in them and in their subfolders is listed, named after its file; installers, uninstallers and helpers are left out. (In Settings.inc: separated by |, e.g. D:\\Games|E:\\Emulators.)" },
                    new Item { Kind = "choice", Key = "ImportFoldersKind", Label = "They are", Help = "Where the programs of your folders go when added.", Choices = new List<string[]> { new[] { "Game", "Games (Category for games)" }, new[] { "App", "Apps (Category for apps)" } } },
                    new Item { Kind = "bool", Key = "ScanOnStart", Label = "Look for new ones on start", Help = "In the background, each time the skin loads: new games or apps, and tiles of games no longer installed, light a dot on the gear." },
                    new Item { Kind = "category", Key = "ImportCategory", Label = "Category for games", Help = "" },
                    new Item { Kind = "category", Key = "AppsCategory", Label = "Category for apps", Help = "" },
                    new Item { Kind = "secret", Key = "SteamGridDBKey", Label = "SteamGridDB API key", Help = "Free, from steamgriddb.com > Preferences > API. When adding a game without local images, its background and logo are downloaded. Saved encrypted: only your Windows user on this PC can read it." },
                } },
            } },
            new Page { Id = "advanced", Title = "Advanced", Icon = 0xE90F, Desc = "Performance, diagnostics and the entries that have no page of their own.", Groups = new List<Group>
            {
                new Group { Title = "Performance", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "Thumbnails", Label = "Thumbnails", Help = "Uses copies of the images at the exact displayed size, made in the background." },
                    new Item { Kind = "choice", Key = "FrameRate", Label = "Animation steps", Help = "Rainmeter draws the whole window on every step: on very large screens fewer steps keep the animations smooth. Automatic: 30 per second from about 3 million pixels (e.g. 3440x1440), otherwise 60. Animations last the same either way.", Choices = new List<string[]> { new[] { "Auto", "Automatic" }, new[] { "60", "60 per second" }, new[] { "30", "30 per second" } } },
                } },
                new Group { Title = "Updates", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "CheckUpdates", Label = "Check for updates", Help = "Once a day, on GitHub. A new version lights the dot on the gear and is shown in Info." },
                    new Item { Kind = "choice", Key = "UpdateChannel", Label = "Updates", Help = "Nightly: also the build made on every change (e.g. 1.2.1.5, the 5th after the release 1.2.1): the newest features, not tested as much. A copy of the skin is kept in Skins\\@Backup before each update.", Choices = new List<string[]> { new[] { "Release", "Releases" }, new[] { "Nightly", "Nightly builds" } }, When = "CheckUpdates=1" },
                } },
                new Group { Title = "Diagnostics", Help = null, Items = new List<Item>
                {
                    new Item { Kind = "bool", Key = "DebugLog", Label = "Debug log", Help = "Writes details to the Rainmeter log (Manage > Log)." },
                } },
                new Group { Title = "Other settings", Help = null, Other = true, Items = new List<Item>
                {
                } },
            } },
            new Page { Id = "info", Title = "Info", Icon = 0xE946, Desc = "About Raintile, and its files.", Groups = new List<Group>
            {
            } },
            new Page { Id = "categories", Title = "Categories", Icon = 0xECA5, Desc = "One file per category in Categories\\. Select a category to edit it; double-click it, or pick it in the menu, for its tiles.", Groups = new List<Group>
            {
            } },
        };

        public static readonly List<NavNode> NavTree = new List<NavNode>
        {
            new NavNode { Page = "general" },
            new NavNode { Page = "tiles", Children = new[] { "grid", "wheel", "backgrounds", "playtime" } },
            new NavNode { Page = "toprow", Children = new[] { "shortcuts", "clock", "search" } },
            new NavNode { Page = "theme" },
            new NavNode { Page = "animations" },
            new NavNode { Page = "keybindings", Children = new[] { "keys", "gamepad" } },
            new NavNode { Page = "dashboard" },
            new NavNode { Page = "import" },
            new NavNode { Page = "advanced" },
            new NavNode { Page = "categories", Categories = true },
        };

        public static readonly Dictionary<string, string> Defaults = new Dictionary<string, string>(System.StringComparer.OrdinalIgnoreCase)
        {
            { "AccentColor", "0,210,180,255" },
            { "ActiveCategoryColor", "0,210,180,70" },
            { "AnimAppearFrames", "12" },
            { "AnimCategory", "1" },
            { "AnimHover", "1" },
            { "AnimHoverSmooth", "0.3" },
            { "AnimLogoSmooth", "0.2" },
            { "AnimLogoZoom", "1" },
            { "AnimOpen", "1" },
            { "AnimPillSmooth", "0.25" },
            { "AnimScroll", "1" },
            { "AnimScrollSmooth", "0.15" },
            { "AnimSlide", "30" },
            { "AnimSmooth", "0.3" },
            { "AnimStagger", "2" },
            { "AppsCategory", "Apps" },
            { "AutoHide", "1" },
            { "AutoTileColor", "1" },
            { "BgColor", "8,8,12,200" },
            { "BgHoverZoom", "1.08" },
            { "BgOverscan", "1.15" },
            { "BgPanFrames", "180" },
            { "BgStyle", "Parallax" },
            { "CheckUpdates", "1" },
            { "ClockFontSize", "18" },
            { "ClockFormat", "%H:%M" },
            { "CloseAction", "[!CommandMeasure MeasureScript \"Hide()\"]" },
            { "CloseHotKey", "ESCAPE" },
            { "CloseOnLaunch", "1" },
            { "CloseSize", "14" },
            { "DashInterval", "1000" },
            { "DateFormat", "%A %#d %B" },
            { "DebugLog", "0" },
            { "DockEdge", "1" },
            { "DockEdgeDelay", "300" },
            { "DockSide", "Left" },
            { "DockSize", "30%" },
            { "DownloadColor1", "0,210,180,255" },
            { "DownloadColor2", "120,90,255,255" },
            { "DownloadInfo", "percent speed eta size schedule" },
            { "DownloadStyle", "Bar" },
            { "EdgeFade", "1" },
            { "FadeDuration", "0" },
            { "FilterBar", "1" },
            { "FilterFontSize", "10" },
            { "FilterGap", "6" },
            { "FilterH", "30" },
            { "FilterPad", "12" },
            { "FilterStores", "1" },
            { "FontFace", "Segoe UI" },
            { "FrameRate", "Auto" },
            { "Gamepad", "1" },
            { "GamepadDeadZone", "12000" },
            { "GamepadOptions", "RS" },
            { "GamepadRepeatDelay", "350" },
            { "GamepadRepeatRate", "110" },
            { "GamepadSearch", "Y" },
            { "GamepadToggle", "BACK START" },
            { "GameUpdates", "1" },
            { "Gap", "18" },
            { "HoverCategoryColor", "255,255,255,20" },
            { "HoverColor", "255,255,255,25" },
            { "HoverLogoScale", "1.25" },
            { "IconSize", "96" },
            { "ImportCategory", "Games" },
            { "ImportFolders", "" },
            { "ImportFoldersKind", "Game" },
            { "ImportStores", "Steam|Epic|GOG|Ubisoft|Battlenet|EA|Xbox|Folders|Apps" },
            { "InfiniteScroll", "1" },
            { "InfoFontSize", "10" },
            { "KeyboardNav", "1" },
            { "LabelFontSize", "14" },
            { "LabelPad", "14" },
            { "LaunchAnimation", "1" },
            { "LaunchAnimFrames", "15" },
            { "LauncherMode", "Fullscreen" },
            { "LaunchFontSize", "48" },
            { "LaunchHold", "1500" },
            { "LaunchLogoSize", "33%" },
            { "LogoGreyscale", "1" },
            { "MenuFontSize", "12" },
            { "MenuGap", "6" },
            { "MenuH", "44" },
            { "MenuIconDimAlpha", "150" },
            { "MenuIconGap", "8" },
            { "MenuIconSize", "24" },
            { "MenuItemPad", "16" },
            { "MenuMode", "IconText" },
            { "MenuRadius", "22" },
            { "NavConfirm", "SPACE" },
            { "NavConfirm2", "ENTER" },
            { "NavDown", "S" },
            { "NavDown2", "DOWN" },
            { "NavLeft", "A" },
            { "NavLeft2", "LEFT" },
            { "NavNextCategory", "E" },
            { "NavPrevCategory", "Q" },
            { "NavRight", "D" },
            { "NavRight2", "RIGHT" },
            { "NavSearch", "F" },
            { "NavUp", "W" },
            { "NavUp2", "UP" },
            { "NX", "4" },
            { "NY", "2" },
            { "OpenHotKey", "CTRL ALT G" },
            { "PadX", "40" },
            { "PadY", "24" },
            { "RecentCount", "12" },
            { "RecentOrder", "Recent" },
            { "ScanOnStart", "1" },
            { "ScreenH", "#SCREENAREAHEIGHT#" },
            { "ScreenW", "#SCREENAREAWIDTH#" },
            { "ScreenX", "#SCREENAREAX#" },
            { "ScreenY", "#SCREENAREAY#" },
            { "ScrollBarSize", "4" },
            { "ScrollDir", "V" },
            { "ScrollMode", "Grid" },
            { "ScrollStep", "1" },
            { "ScrollThumbColor", "0,210,180,200" },
            { "ScrollTrackColor", "255,255,255,25" },
            { "SearchHover", "1" },
            { "SearchPlaceholder", "Search" },
            { "SearchW", "320" },
            { "SensorPort", "8085" },
            { "ShowClock", "1" },
            { "ShowDate", "1" },
            { "ShowFavorites", "1" },
            { "ShowLabels", "1" },
            { "ShowPower", "1" },
            { "ShowRecent", "1" },
            { "ShowUnplayed", "1" },
            { "ShowZPos", "1" },
            { "StartHidden", "0" },
            { "SteamGridDBKey", "" },
            { "TextColor", "240,240,245,255" },
            { "TextDimColor", "150,150,160,255" },
            { "Thumbnails", "1" },
            { "TileColor", "36,36,44,255" },
            { "TileHover", "1" },
            { "TileInfo", "Hover" },
            { "TileKeysWhen", "Always" },
            { "TileRadius", "0" },
            { "TopBarColor", "0,0,0,255" },
            { "TrackPlaytime", "1" },
            { "UnplayedCount", "24" },
            { "UpdateChannel", "Release" },
            { "UpdateGlowTime", "3" },
            { "WheelAnchor", "69" },
            { "WheelAxis", "Auto" },
            { "WheelBackdrop", "1" },
            { "WheelBackdropOpacity", "40" },
            { "WheelClick", "Launch" },
            { "WheelCurve", "Out" },
            { "WheelFade", "65" },
            { "WheelHover", "Turn" },
            { "WheelIconsOnly", "0" },
            { "WheelLabels", "Center" },
            { "WheelMenu", "Ring" },
            { "WheelMenuGap", "50" },
            { "WheelMenuSize", "50" },
            { "WheelRadius", "70" },
            { "WheelSpacing", "50" },
            { "WheelStepTime", "350" },
            { "WheelTileSize", "25" },
            { "WheelVisible", "11" },
            { "WindowH", "70%" },
            { "WindowW", "60%" },
        };

        public static readonly string[] GAMEPAD_BUTTONS = { "A", "B", "X", "Y", "LB", "RB", "BACK", "START", "LS", "RS", "UP", "DOWN", "LEFT", "RIGHT" };
        public static readonly string[] SOURCES = { "Steam", "Epic", "GOG", "Ubisoft", "Battlenet", "EA", "Xbox", "Folders", "Apps" };
        public static readonly Dictionary<string, string> STORE_LABELS = new Dictionary<string, string>
        {
            { "Apps", "Start menu apps" },
            { "Battle.net", "Battle.net" },
            { "Battlenet", "Battle.net" },
            { "EA", "EA app" },
            { "Epic", "Epic Games" },
            { "Folders", "Your folders" },
            { "GOG", "GOG" },
            { "Steam", "Steam" },
            { "Ubisoft", "Ubisoft Connect" },
            { "Xbox", "Xbox / Store" },
        };
        public static readonly Dictionary<string, string> KEY_LABELS = new Dictionary<string, string>
        {
            { "ADD", "Num +" },
            { "ALT", "Alt" },
            { "BACKSLASH", "\\" },
            { "BACKSPACE", "Backspace" },
            { "BACKTICK", "`" },
            { "CAPSLOCK", "Caps Lock" },
            { "COLON", ";" },
            { "COMMA", "," },
            { "CTRL", "Ctrl" },
            { "DECIMAL", "Num ." },
            { "DIVIDE", "Num /" },
            { "DOWN", "\u2193" },
            { "ENTER", "Enter" },
            { "ESCAPE", "Esc" },
            { "FORWARDSLASH", "/" },
            { "LALT", "Left Alt" },
            { "LBRACKET", "[" },
            { "LCTRL", "Left Ctrl" },
            { "LEFT", "\u2190" },
            { "LSHIFT", "Left Shift" },
            { "LWIN", "Win" },
            { "MINUS", "-" },
            { "MULT", "Num *" },
            { "NUMLOCK", "Num Lock" },
            { "PAGEDOWN", "Page Down" },
            { "PAGEUP", "Page Up" },
            { "PERIOD", "." },
            { "PLUS", "=" },
            { "PRINTSCREEN", "Print Screen" },
            { "QUOTE", "'" },
            { "RALT", "Right Alt" },
            { "RBRACKET", "]" },
            { "RCTRL", "Right Ctrl" },
            { "RIGHT", "\u2192" },
            { "RSHIFT", "Right Shift" },
            { "RWIN", "Right Win" },
            { "SCROLLLOCK", "Scroll Lock" },
            { "SHIFT", "Shift" },
            { "SPACE", "Space" },
            { "SUBTRACT", "Num -" },
            { "TAB", "Tab" },
            { "UP", "\u2191" },
            { "WIN", "Win" },
        };
    }
}
