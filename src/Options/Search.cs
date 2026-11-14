// Raintile Options: the search above the menu. Schema.Search finds the pages,
// cards and settings that have every word typed (the start of one of their
// words: labels, help, keys and Keywords, the words people use for them); the
// window shows the results in place of the menu, and a result opens its page on
// its row, lit for a moment; the results stay, to try another one, until the
// field is emptied. docs/OptionsUI.md, "Search".

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace RaintileOptions
{
    // A page, a card or a setting found: Title as the menu or the row names it,
    // Path where it is (its page, its card)
    public class SearchHit
    {
        public Page Page;
        public Group Group;
        public Item Item;
        public string Title, Path;
        public int Score;
    }

    // How a row found by the search is lit: its background in the accent colour
    // at this opacity, kept for a moment, then fading out
    static class FoundFlash
    {
        public const double Opacity = 0.3;
        public const int HoldMs = 700, FadeMs = 1500;
    }

    public static partial class Schema
    {
        public const int SearchMax = 40;

        // The words of a text, lower case; a key gives its parts too
        // (BgColor: bgcolor, bg, color)
        public static List<string> SearchWords(string text)
        {
            var words = new List<string>();
            if (string.IsNullOrEmpty(text)) return words;
            foreach (Match m in Regex.Matches(text, "[A-Za-z0-9]+"))
            {
                words.Add(m.Value.ToLowerInvariant());
                var parts = Regex.Matches(m.Value, "[A-Z]?[a-z]+|[A-Z]+(?![a-z])|[0-9]+");
                if (parts.Count > 1) foreach (Match p in parts) words.Add(p.Value.ToLowerInvariant());
            }
            return words;
        }

        // How much a field counts when a word typed starts one of its words
        class SearchField
        {
            public List<string> Words;
            public int Weight;
            public SearchField(string text, int weight) { Words = SearchWords(text); Weight = weight; }
        }

        const int TitleWeight = 10, KeywordWeight = 8, KeyWeight = 6, HelpWeight = 3, PlaceWeight = 2;

        // Every word typed must be in the entry or in where it is (its card, its
        // page), and one at least in the entry itself: "animations" lists the
        // page, not every setting on it. A whole word counts more than its start.
        static int SearchScore(List<string> query, List<SearchField> own, List<SearchField> place)
        {
            int score = 0;
            bool inOwn = false;
            foreach (var q in query)
            {
                int best = 0;
                foreach (var f in own.Concat(place))
                    foreach (var w in f.Words)
                        if (w.StartsWith(q, StringComparison.Ordinal))
                        {
                            int s = f.Weight * 2 + (w == q ? 1 : 0);
                            if (s > best) best = s;
                            if (own.Contains(f)) inOwn = true;
                        }
                if (best == 0) return 0;
                score += best;
            }
            return inOwn ? score : 0;
        }

        // The pages, cards and settings that have every word of the query, the
        // best first (then in the order of the menu)
        public static List<SearchHit> Search(string query)
        {
            var words = SearchWords(query).Distinct().ToList();
            var hits = new List<SearchHit>();
            if (words.Count == 0) return hits;
            foreach (var page in MenuPages())
            {
                var parent = NavTree.FirstOrDefault(n => n.Children != null && n.Children.Contains(page.Id));
                string pagePath = parent != null ? ById(parent.Page).Title + " > " + page.Title : page.Title;
                var pagePlace = new List<SearchField> { new SearchField(pagePath, PlaceWeight) };
                Add(hits, words, new SearchHit { Page = page, Title = page.Title, Path = parent != null ? ById(parent.Page).Title : "" },
                    new List<SearchField> { new SearchField(page.Title, TitleWeight), new SearchField(page.Desc, HelpWeight), new SearchField(page.Keywords, KeywordWeight) },
                    parent != null ? new List<SearchField> { new SearchField(ById(parent.Page).Title, PlaceWeight) } : new List<SearchField>());
                foreach (var group in page.Groups)
                {
                    // a card with a switch is found as its switch (below); the
                    // first card without a title is the page itself
                    var sw = group.Switch == null ? null : group.Items.FirstOrDefault(i => i.Key == group.Switch);
                    string card = group.Title ?? (sw != null ? sw.Label : null);
                    if (group.Title != null && sw == null)
                        Add(hits, words, new SearchHit { Page = page, Group = group, Title = group.Title, Path = pagePath },
                            new List<SearchField> { new SearchField(group.Title, TitleWeight), new SearchField(group.Help, HelpWeight), new SearchField(group.Keywords, KeywordWeight) },
                            pagePlace);
                    var place = card == null ? pagePlace : pagePlace.Concat(new[] { new SearchField(card, PlaceWeight) }).ToList();
                    foreach (var item in group.Items)
                    {
                        bool isSwitch = item == sw;
                        var own = new List<SearchField>
                        {
                            new SearchField(item.Label, TitleWeight), new SearchField(item.Help, HelpWeight),
                            new SearchField(item.Key, KeyWeight), new SearchField(item.Keywords, KeywordWeight),
                        };
                        if (isSwitch) own.Add(new SearchField(group.Help, HelpWeight));
                        // every colour is found as one, whatever its label
                        if (item.Kind == "color") own.Add(new SearchField("colour color", KeywordWeight));
                        Add(hits, words, new SearchHit { Page = page, Group = group, Item = item, Title = item.Label, Path = isSwitch || card == null ? pagePath : pagePath + " > " + card },
                            own, isSwitch ? pagePlace : place);
                    }
                }
            }
            // (OrderBy is stable: equal scores keep the order of the menu)
            return hits.OrderByDescending(h => h.Score).Take(SearchMax).ToList();
        }

        static void Add(List<SearchHit> hits, List<string> words, SearchHit hit, List<SearchField> own, List<SearchField> place)
        {
            hit.Score = SearchScore(words, own, place);
            if (hit.Score > 0) hits.Add(hit);
        }

        // The pages in the order of the menu: its entries and their sub-pages,
        // Info (at the bottom) last
        static IEnumerable<Page> MenuPages()
        {
            foreach (var n in NavTree)
            {
                yield return ById(n.Page);
                if (n.Children != null) foreach (var c in n.Children) yield return ById(c);
            }
            yield return ById("info");
        }
    }

    public partial class OptionsApp
    {
        TextBox navSearch;
        ListBox navResults;
        bool resultsFilling;
        bool keepSearch;   // a result is opening its page: the results stay (ShowNavTarget)
        // what a result lights when its page is shown: the row of a setting (the
        // header of a card with a switch, the switch beside the page title), the
        // card of a group (NewSettingsPage)
        readonly Dictionary<object, FrameworkElement> foundTargets = new Dictionary<object, FrameworkElement>();

        void InitSearch()
        {
            Grid box;
            navSearch = NewSearchBox("Search settings (Ctrl+F)", out box);
            ((Grid)win.FindName("NavSearchHost")).Children.Add(box);
            navResults = (ListBox)win.FindName("NavResults");
            navSearch.TextChanged += (s, e) => ShowSearchResults();
            navSearch.PreviewKeyDown += (s, e) =>
            {
                if (Keyboard.Modifiers != ModifierKeys.None) return;
                if (e.Key == Key.Escape && navSearch.Text != "") { e.Handled = true; navSearch.Text = ""; }
                else if (e.Key == Key.Enter) { e.Handled = true; var first = SearchResultItems().FirstOrDefault(); if (first != null) OpenSearchResult(first); }
                else if (e.Key == Key.Down) { e.Handled = true; SearchStepDown(); }
            };
            navResults.SelectionChanged += (s, e) =>
            {
                var it = navResults.SelectedItem as ListBoxItem;
                if (!resultsFilling && it != null && it.Tag is SearchHit) OpenSearchHit((SearchHit)it.Tag);
            };
            // the arrows move the focus, not the selection: selecting opens
            navResults.PreviewKeyDown += (s, e) =>
            {
                if (Keyboard.Modifiers != ModifierKeys.None) return;
                var items = SearchResultItems();
                int i = items.IndexOf(Keyboard.FocusedElement as ListBoxItem);
                if (e.Key == Key.Down || e.Key == Key.Up)
                {
                    e.Handled = true;
                    int n = i + (e.Key == Key.Down ? 1 : -1);
                    if (n < 0) navSearch.Focus();
                    else if (n < items.Count) items[n].Focus();
                }
                else if ((e.Key == Key.Enter || e.Key == Key.Space) && i >= 0) { e.Handled = true; OpenSearchResult(items[i]); }
                else if (e.Key == Key.Escape) { e.Handled = true; navSearch.Text = ""; navSearch.Focus(); }
            };
        }

        void FocusSearch()
        {
            navSearch.Focus();
            navSearch.SelectAll();
        }

        // Down from the search box: the first result, or the menu
        void SearchStepDown()
        {
            var first = SearchResultItems().FirstOrDefault();
            if (first != null) { first.Focus(); if (padMode) PadSetFocus(first); return; }
            var sel = (nav.SelectedItem ?? navBottom.SelectedItem) as ListBoxItem;
            if (sel == null) return;
            if (padMode) PadSetFocus(sel); else sel.Focus();
        }

        List<ListBoxItem> SearchResultItems()
        {
            return navResults.Items.OfType<ListBoxItem>().Where(it => it.Tag is SearchHit).ToList();
        }

        bool SearchShown { get { return navResults.Visibility == Visibility.Visible; } }

        // The results in place of the menu while something is typed
        void ShowSearchResults()
        {
            string q = navSearch.Text.Trim();
            resultsFilling = true;
            try
            {
                navResults.Items.Clear();
                if (q != "")
                {
                    var hits = Schema.Search(q);
                    foreach (var h in hits) navResults.Items.Add(NewSearchResult(h));
                    if (hits.Count == 0)
                    {
                        var none = new ListBoxItem { Content = NewHelp("Nothing found: try another word (e.g. colour, size, speed, keys)."), IsEnabled = false, Focusable = false };
                        navResults.Items.Add(none);
                    }
                }
            }
            finally { resultsFilling = false; }
            bool wasShown = SearchShown;
            navResults.Visibility = q != "" ? Visibility.Visible : Visibility.Collapsed;
            nav.Visibility = q != "" ? Visibility.Collapsed : Visibility.Visible;
            // the menu back: on the page shown, so it says where it lives
            if (wasShown && q == "")
                win.Dispatcher.BeginInvoke(new Action(() => { if (nav.SelectedItem != null) nav.ScrollIntoView(nav.SelectedItem); }), DispatcherPriority.Loaded);
        }

        ListBoxItem NewSearchResult(SearchHit h)
        {
            var sp = NewPanel();
            var t = NewText(h.Title, Fs.Label, null, false, true);
            AddTo(sp, t);
            if (h.Path != "")
            {
                var p = NewHelp(h.Path);
                p.Margin = T(0, Gap.Help, 0, 0);
                AddTo(sp, p);
            }
            var item = new ListBoxItem { Content = sp, Tag = h, Padding = Gap.ListItem };
            AutomationProperties.SetName(item, h.Path != "" ? h.Title + ", " + h.Path : h.Title);
            // a click on the result already open lights its row again
            item.PreviewMouseLeftButtonDown += (s, e) => { if (item.IsSelected) OpenSearchHit(h); };
            return item;
        }

        // A result picked with the keys: marked as the one open, the focus stays
        // on it (the next one is an arrow away)
        void OpenSearchResult(ListBoxItem item)
        {
            resultsFilling = true;
            try { navResults.SelectedItem = item; }
            finally { resultsFilling = false; }
            item.Focus();
            OpenSearchHit((SearchHit)item.Tag);
        }

        // Opens the page of a result (its group in the menu open, for when the
        // menu comes back), then lights its row; the results stay
        void OpenSearchHit(SearchHit h)
        {
            var page = h.Page;
            keepSearch = true;
            if (page.Id == "info")
            {
                // (selected again: Info may be the page shown)
                navBottom.SelectedIndex = -1;
                navBottom.SelectedIndex = 0;
            }
            else
            {
                var parent = Schema.NavTree.FirstOrDefault(n => n.Children != null && n.Children.Contains(page.Id));
                if (parent != null) navOpen[parent.Page] = true;
                OpenNav(page.Id == "categories" ? "categories" : "page:" + page.Id);
            }
            // after OpenNav (Normal) and once the page is laid out, also what it
            // fills after it is shown (the store rows of Import)
            win.Dispatcher.BeginInvoke(new Action(() => ShowSearchTarget(h)), DispatcherPriority.ApplicationIdle);
        }

        void ShowSearchTarget(SearchHit h)
        {
            // a page for a mode not in use (Wheel with the grid): said in the status line
            status.Text = !string.IsNullOrEmpty(h.Page.When) && !WhenHolds(h.Page.When) ? h.Page.Title + ": " + WhenReason(h.Page.When, null) : "";
            // (a page, or a row not on the page shown: the page only)
            FrameworkElement fe;
            if (!foundTargets.TryGetValue((object)h.Item ?? h.Group ?? (object)h.Page, out fe)) return;
            // a fine tuning: its More settings opened first
            var details = LogicalTreeHelper.GetParent(fe) as CardDetails;
            if (details != null && !details.Open) { SetDetailsOpen(details, true); fe.UpdateLayout(); }
            if (!fe.IsVisible) return;
            // the focus stays on the result: the row is scrolled into view with
            // room around it and lit, its control a click (or right) away
            BringIntoViewWithRoom(fe);
            FlashFound(fe);
        }

        // The row found: its background lit in the accent colour, fading out
        void FlashFound(FrameworkElement fe)
        {
            var bg = fe is Border ? Border.BackgroundProperty : fe is Panel ? Panel.BackgroundProperty : null;
            if (bg == null) return;
            var old = fe.ReadLocalValue(bg);
            var brush = new SolidColorBrush(((SolidColorBrush)ResBrush("AccentBrush")).Color) { Opacity = FoundFlash.Opacity };
            fe.SetValue(bg, brush);
            var a = new DoubleAnimation(FoundFlash.Opacity, 0, new Duration(TimeSpan.FromMilliseconds(FoundFlash.FadeMs))) { BeginTime = TimeSpan.FromMilliseconds(FoundFlash.HoldMs) };
            a.Completed += (s, e) => { if (old == DependencyProperty.UnsetValue) fe.ClearValue(bg); else fe.SetValue(bg, old); };
            brush.BeginAnimation(Brush.OpacityProperty, a);
        }

        // Search with the pad: down from the box to the results (or the menu), up
        // from the first result or the first entry of the menu to the box
        bool SearchPadMove(int dir)
        {
            if (padFocus == navSearch)
            {
                if (dir == PadDown) SearchStepDown();
                return dir == PadDown || dir == PadUp || dir == PadLeft;
            }
            if (dir != PadUp) return false;
            var item = padFocus as ListBoxItem;
            if (item == null) return false;
            var list = ItemsControl.ItemsControlFromItemContainer(item);
            bool first = list == navResults ? SearchResultItems().IndexOf(item) == 0
                : list == nav && NavEntries().IndexOf(item) == 0;
            if (!first) return false;
            PadSetFocus(navSearch);
            return true;
        }

        // B in the search box or the results: the search closed, back to the menu
        bool SearchPadBack()
        {
            var item = padFocus as ListBoxItem;
            if (padFocus != navSearch && (item == null || ItemsControl.ItemsControlFromItemContainer(item) != navResults)) return false;
            navSearch.Text = "";
            var sel = (nav.SelectedItem ?? navBottom.SelectedItem) as ListBoxItem;
            if (sel != null) PadSetFocus(sel);
            return true;
        }
    }
}
