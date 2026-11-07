// Raintile Options: on-screen keyboard for the gamepad (A on a text field).
// The layout of the launcher's one (GamepadSearch, Raintile.lua) on a grid of
// 10 columns, with Shift for capitals and a page of symbols for paths and
// commands. The text being written shows above the keys (the field may be
// under the keyboard); every key goes into the field at once, B puts back what
// was there.
//
//   D-pad / stick  move on the keys     A  type the key    X  delete    Y  space
//   LB / RB        move the cursor      LT Shift           RT symbols
//   Start / Done   keep the text        B  cancel
//
// The keys can be clicked with the mouse too; a click elsewhere in the window
// or a key on the keyboard closes it and keeps the text.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media.Effects;

namespace RaintileOptions
{
    public partial class OptionsApp
    {
        class OskKey
        {
            public int Row, Col, Span = 1;
            public int Char = -1;     // position in the page of characters, or -1
            public string Value;      // otherwise BACK, SHIFT, SYM, SPACE, DONE
            public Border Box;
            public TextBlock Label;
        }

        // Rows of 10, 10, 10 and 8 characters (then Delete), as in the launcher
        const string OskLetters = "1234567890qwertyuiopasdfghjkl-zxcvbnm.";
        const string OskSymbols = "1234567890!@#$%^&*()\\/:;_=+'\",[]{}<>|?";

        Popup osk;
        List<OskKey> oskKeys;
        Run oskBefore, oskAfter;
        FrameworkElement oskTarget;   // the field being written, null when closed
        string oskOriginal = "", oskText = "";
        int oskCaret, oskRow, oskCol;
        bool oskShift, oskSymbols;

        void BuildOsk()
        {
            oskKeys = new List<OskKey>();
            int c = 0;
            for (int r = 0; r < 4; r++)
                for (int i = 0; i < (r < 3 ? 10 : 8); i++) oskKeys.Add(new OskKey { Row = r, Col = i, Char = c++ });
            oskKeys.Add(new OskKey { Row = 3, Col = 8, Span = 2, Value = "BACK" });
            oskKeys.Add(new OskKey { Row = 4, Col = 0, Span = 2, Value = "SHIFT" });
            oskKeys.Add(new OskKey { Row = 4, Col = 2, Span = 2, Value = "SYM" });
            oskKeys.Add(new OskKey { Row = 4, Col = 4, Span = 4, Value = "SPACE" });
            oskKeys.Add(new OskKey { Row = 4, Col = 8, Span = 2, Value = "DONE" });

            const double size = 50;
            var grid = new Grid();
            for (int i = 0; i < 10; i++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(size) });
            for (int i = 0; i < 5; i++) grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(size - 4) });
            foreach (var k in oskKeys)
            {
                var key = k;
                k.Label = NewText("", 15, null, true);   // ui-exempt: on-screen keyboard
                k.Label.HorizontalAlignment = HorizontalAlignment.Center;
                k.Label.VerticalAlignment = VerticalAlignment.Center;
                k.Box = new Border { CornerRadius = new CornerRadius(6), Margin = T(3), Child = k.Label, Cursor = Cursors.Hand };
                Grid.SetRow(k.Box, k.Row);
                Grid.SetColumn(k.Box, k.Col);
                Grid.SetColumnSpan(k.Box, k.Span);
                k.Box.MouseLeftButtonUp += (s, e) => { oskRow = key.Row; oskCol = key.Col; OskPress(key); };
                grid.Children.Add(k.Box);
            }

            var text = new TextBlock { FontSize = 15, TextWrapping = TextWrapping.Wrap };   // ui-exempt: on-screen keyboard
            oskBefore = new Run();
            oskAfter = new Run();
            text.Inlines.Add(oskBefore);
            text.Inlines.Add(new Run("|") { Foreground = ResBrush("AccentBrush") });
            text.Inlines.Add(oskAfter);
            var field = new Border
            {
                Background = ResBrush("FieldBg"), BorderBrush = ResBrush("AccentBrush"), BorderThickness = T(1),
                CornerRadius = new CornerRadius(6), Padding = T(10, 7), Margin = T(3, 0, 3, 10), Child = text, MinHeight = 36,
            };
            var hint = NewText("A type   X delete   Y space   LB/RB cursor   LT Shift   RT symbols   Start done   B cancel", Fs.Help, ResBrush("DimBrush"), false, true);
            hint.Margin = T(3, 10, 3, 0);
            var sp = NewPanel();
            sp.Width = 10 * size;
            AddTo(sp, field); AddTo(sp, grid); AddTo(sp, hint);
            var card = new Border
            {
                Background = ResBrush("CardBg"), BorderBrush = ResBrush("AccentBrush"), BorderThickness = T(1),
                CornerRadius = new CornerRadius(12), Padding = T(14), Margin = T(16), Child = sp,
                Effect = new DropShadowEffect { BlurRadius = 24, ShadowDepth = 4, Opacity = 0.5 },
            };
            osk = new Popup { AllowsTransparency = true, StaysOpen = true, Placement = PlacementMode.Relative, Focusable = false, Child = card };
        }

        static string OskRead(FrameworkElement field)
        {
            var tb = field as TextBox;
            if (tb != null) return tb.Text ?? "";
            var pb = field as PasswordBox;
            return pb != null ? pb.Password : "";
        }

        void OpenOsk(FrameworkElement field)
        {
            var root = Window.GetWindow(field);
            var target = root != null ? root.Content as FrameworkElement : null;
            if (target == null) return;
            if (osk == null) BuildOsk();
            oskTarget = field;
            oskOriginal = OskRead(field);
            oskText = oskOriginal;
            oskCaret = oskText.Length;
            oskShift = false;
            oskSymbols = false;
            oskRow = 1;   // on the first letter
            oskCol = 0;
            OskRender();
            var card = (FrameworkElement)osk.Child;
            card.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            var size = card.DesiredSize;
            osk.PlacementTarget = target;
            osk.HorizontalOffset = (target.ActualWidth - size.Width) / 2;
            // at the bottom of the window; below a small one (a dialog)
            osk.VerticalOffset = target.ActualHeight > size.Height + 160 ? target.ActualHeight - size.Height : target.ActualHeight;
            osk.IsOpen = true;
        }

        void CloseOsk(bool keep)
        {
            if (oskTarget == null) return;
            if (!keep && OskRead(oskTarget) != oskOriginal)
            {
                oskText = oskOriginal;
                oskCaret = oskText.Length;
                OskWrite();
            }
            oskTarget = null;
            osk.IsOpen = false;
        }

        // The text into the field: its own handlers save the value, as when typing
        void OskWrite()
        {
            var tb = oskTarget as TextBox;
            if (tb != null) { tb.Text = oskText; tb.CaretIndex = oskCaret; }
            var pb = oskTarget as PasswordBox;
            if (pb != null && pb.Password != oskText) pb.Password = oskText;
            OskRender();
        }

        OskKey OskKeyAt(int row, int col)
        {
            return oskKeys.First(k => k.Row == row && col >= k.Col && col < k.Col + k.Span);
        }

        void OskRender()
        {
            string page = oskSymbols ? OskSymbols : OskLetters;
            var sel = OskKeyAt(oskRow, oskCol);
            foreach (var k in oskKeys)
            {
                string label;
                if (k.Char >= 0)
                {
                    label = page[k.Char].ToString();
                    if (oskShift && !oskSymbols) label = label.ToUpperInvariant();
                }
                else if (k.Value == "BACK") label = "Delete";
                else if (k.Value == "SHIFT") label = "Shift";
                else if (k.Value == "SYM") label = oskSymbols ? "abc" : "#+=";
                else if (k.Value == "SPACE") label = "Space";
                else label = "Done";
                k.Label.Text = label;
                bool on = (k.Value == "SHIFT" && oskShift) || (k.Value == "SYM" && oskSymbols);
                k.Box.Background = ResBrush(k == sel ? "AccentBrush" : on ? "AccentSoftBrush" : "FieldBg");
                k.Label.Foreground = ResBrush(k == sel ? "OnAccentBrush" : on ? "AccentBrush" : "TextBrush");
            }
            string shown = oskTarget is PasswordBox ? new string('\u2022', oskText.Length) : oskText;
            oskBefore.Text = shown.Substring(0, oskCaret);
            oskAfter.Text = shown.Substring(oskCaret);
        }

        void OskInsert(string s)
        {
            oskText = oskText.Insert(oskCaret, s);
            oskCaret += s.Length;
            OskWrite();
        }

        void OskDelete()
        {
            if (oskCaret == 0) return;
            oskText = oskText.Remove(oskCaret - 1, 1);
            oskCaret--;
            OskWrite();
        }

        void OskMoveCaret(int step)
        {
            oskCaret = Math.Max(0, Math.Min(oskText.Length, oskCaret + step));
            var tb = oskTarget as TextBox;
            if (tb != null) tb.CaretIndex = oskCaret;
            OskRender();
        }

        void OskPress(OskKey k)
        {
            if (oskTarget == null) return;
            if (k.Char >= 0)
            {
                string ch = (oskSymbols ? OskSymbols : OskLetters)[k.Char].ToString();
                OskInsert(oskShift && !oskSymbols ? ch.ToUpperInvariant() : ch);
                return;
            }
            switch (k.Value)
            {
                case "BACK": OskDelete(); break;
                case "SHIFT": oskShift = !oskShift; OskRender(); break;
                case "SYM": oskSymbols = !oskSymbols; OskRender(); break;
                case "SPACE": OskInsert(" "); break;
                default: CloseOsk(true); break;
            }
        }

        void OskMove(int dir)
        {
            var k = OskKeyAt(oskRow, oskCol);
            if (dir == PadLeft && k.Col > 0) oskCol = k.Col - 1;
            else if (dir == PadRight && k.Col + k.Span < 10) oskCol = k.Col + k.Span;
            else if (dir == PadUp && oskRow > 0) oskRow--;
            else if (dir == PadDown && oskRow < 4) oskRow++;
            OskRender();
        }

        void OskInput(int fire, bool start)
        {
            int d = FirstDir(fire);
            if (d != 0) OskMove(d);
            else if ((fire & PadA) != 0) OskPress(OskKeyAt(oskRow, oskCol));
            else if ((fire & PadX) != 0) OskDelete();
            else if ((fire & PadY) != 0) OskInsert(" ");
            else if ((fire & PadLB) != 0) OskMoveCaret(-1);
            else if ((fire & PadRB) != 0) OskMoveCaret(1);
            else if ((fire & PadLT) != 0) { oskShift = !oskShift; OskRender(); }
            else if ((fire & PadRT) != 0) { oskSymbols = !oskSymbols; OskRender(); }
            else if ((fire & PadB) != 0) CloseOsk(false);
            else if (start) CloseOsk(true);
        }
    }
}
