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
// As on the buttons of the window (AddPadHint), the pad buttons show as their
// glyphs: on the keys they press (Delete, Space, Shift, symbols, Done), the
// others (A, LB / RB, B) on the hint line under the keys.
//
// The keys can be clicked with the mouse too; a click elsewhere in the window
// or a key on the keyboard closes it and keeps the text.
//
// A box for numbers only (NumericOnly) gets a number pad instead, as on a phone.
// A key that cannot type at that point (- after the start, a second ., a sign the
// box does not take) is dimmed and skipped when moving, as typing in the box.

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
            public int Pad;           // the glyph of the pad button that presses it, or 0
            public Border Box;
            public TextBlock Label, PadGlyph;
        }

        // Rows of 10, 10, 10 and 8 characters (then Delete), as in the launcher
        const string OskLetters = "1234567890qwertyuiopasdfghjkl-zxcvbnm.";
        const string OskSymbols = "1234567890!@#$%^&*()\\/:;_=+'\",[]{}<>|?";
        // the number pad: 1 2 3 / 4 5 6 - / 7 8 9 . / 0
        const string OskDigits = "123456789-.0";

        Popup osk;
        List<OskKey> oskKeys;
        Run oskBefore, oskAfter;
        FrameworkElement oskTarget;   // the field being written, null when closed
        string oskOriginal = "", oskText = "";
        int oskCaret, oskRow, oskCol, oskCols, oskRows;
        bool oskShift, oskSymbols;
        string oskNumeric;            // the characters a numeric box takes, null for the letters

        void BuildOsk(bool numeric)
        {
            oskKeys = new List<OskKey>();
            if (numeric)
            {
                oskCols = 4; oskRows = 4;
                for (int r = 0; r < 3; r++)
                    for (int i = 0; i < 3; i++) oskKeys.Add(new OskKey { Row = r, Col = i, Char = r * 3 + i });
                oskKeys.Add(new OskKey { Row = 0, Col = 3, Value = "BACK", Pad = Glyph.PadX });
                oskKeys.Add(new OskKey { Row = 1, Col = 3, Char = 9 });
                oskKeys.Add(new OskKey { Row = 2, Col = 3, Char = 10 });
                oskKeys.Add(new OskKey { Row = 3, Col = 0, Span = 2, Char = 11 });
                oskKeys.Add(new OskKey { Row = 3, Col = 2, Span = 2, Value = "DONE", Pad = Glyph.PadStart });
            }
            else
            {
                oskCols = 10; oskRows = 5;
                int c = 0;
                for (int r = 0; r < 4; r++)
                    for (int i = 0; i < (r < 3 ? 10 : 8); i++) oskKeys.Add(new OskKey { Row = r, Col = i, Char = c++ });
                oskKeys.Add(new OskKey { Row = 3, Col = 8, Span = 2, Value = "BACK", Pad = Glyph.PadX });
                oskKeys.Add(new OskKey { Row = 4, Col = 0, Span = 2, Value = "SHIFT", Pad = Glyph.PadLT });
                oskKeys.Add(new OskKey { Row = 4, Col = 2, Span = 2, Value = "SYM", Pad = Glyph.PadRT });
                oskKeys.Add(new OskKey { Row = 4, Col = 4, Span = 4, Value = "SPACE", Pad = Glyph.PadY });
                oskKeys.Add(new OskKey { Row = 4, Col = 8, Span = 2, Value = "DONE", Pad = Glyph.PadStart });
            }

            const double size = 50;
            var grid = new Grid();
            // the number pad's last column is two keys wide: Delete with its glyph
            for (int i = 0; i < oskCols; i++)
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(numeric && i == oskCols - 1 ? 2 * size : size) });
            for (int i = 0; i < oskRows; i++) grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(size - 4) });
            foreach (var k in oskKeys)
            {
                var key = k;
                k.Label = NewText("", 15, null, true);   // ui-exempt: on-screen keyboard
                k.Label.VerticalAlignment = VerticalAlignment.Center;
                // the pad button's glyph before the name of the key
                var content = NewPanel(Orientation.Horizontal);
                content.HorizontalAlignment = HorizontalAlignment.Center;
                if (k.Pad != 0)
                {
                    k.PadGlyph = NewGlyph(k.Pad, Fs.Label);
                    k.PadGlyph.Margin = T(0, 0, Gap.Icon, 0);
                    AddTo(content, k.PadGlyph);
                }
                AddTo(content, k.Label);
                k.Box = new Border { CornerRadius = new CornerRadius(6), Margin = T(3), Child = content, Cursor = Cursors.Hand };   // ui-exempt: on-screen keyboard
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
                CornerRadius = new CornerRadius(6), Padding = T(10, 7), Margin = T(3, 0, 3, 10), Child = text, MinHeight = 36,   // ui-exempt: on-screen keyboard
            };
            // the pad buttons that are not on a key, as glyphs
            var hint = NewText("", Fs.Help, ResBrush("DimBrush"), false, true);
            foreach (var h in new[] { new object[] { new[] { Glyph.PadA }, "type" }, new object[] { new[] { Glyph.PadLB, Glyph.PadRB }, "cursor" }, new object[] { new[] { Glyph.PadB }, "cancel" } })
            {
                foreach (int g in (int[])h[0]) hint.Inlines.Add(new Run(((char)g).ToString()) { FontFamily = Glyph.Font });
                hint.Inlines.Add(new Run(" " + h[1] + "     "));
            }
            hint.Margin = T(3, 10, 3, 0);   // ui-exempt: on-screen keyboard
            var sp = NewPanel();
            sp.Width = grid.ColumnDefinitions.Sum(c => c.Width.Value);
            AddTo(sp, field); AddTo(sp, grid); AddTo(sp, hint);
            var card = new Border
            {
                Background = ResBrush("CardBg"), BorderBrush = ResBrush("AccentBrush"), BorderThickness = T(1),
                CornerRadius = new CornerRadius(12), Padding = T(14), Margin = T(16), Child = sp,   // ui-exempt: on-screen keyboard
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
            oskNumeric = NumericChars(field);
            // built again when the other kind is needed (letters or number pad)
            if (osk == null || (oskCols == 4) != (oskNumeric != null)) BuildOsk(oskNumeric != null);
            oskTarget = field;
            oskOriginal = OskRead(field);
            oskText = oskOriginal;
            oskCaret = oskText.Length;
            oskShift = false;
            oskSymbols = false;
            oskRow = oskNumeric != null ? 0 : 1;   // on the 1, or on the first letter
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
            string page = OskPage();
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
                k.Box.Opacity = OskEnabled(k) ? 1 : 0.35;   // ui-exempt: on-screen keyboard, a key that cannot type here
                bool on = (k.Value == "SHIFT" && oskShift) || (k.Value == "SYM" && oskSymbols);
                k.Box.Background = ResBrush(k == sel ? "AccentBrush" : on ? "AccentSoftBrush" : "FieldBg");
                k.Label.Foreground = ResBrush(k == sel ? "OnAccentBrush" : on ? "AccentBrush" : "TextBrush");
                if (k.PadGlyph != null) k.PadGlyph.Foreground = k.Label.Foreground;
            }
            string shown = oskTarget is PasswordBox ? new string('\u2022', oskText.Length) : oskText;
            oskBefore.Text = shown.Substring(0, oskCaret);
            oskAfter.Text = shown.Substring(oskCaret);
        }

        string OskPage()
        {
            return oskNumeric != null ? OskDigits : oskSymbols ? OskSymbols : OskLetters;
        }

        // A numeric box takes 's' at the caret only if the text can still be a number
        // (as typing in it, NumericOnly)
        bool OskTakes(string s)
        {
            return oskNumeric == null || IsPartialNumber(oskNumeric, oskText.Insert(oskCaret, s));
        }

        bool OskEnabled(OskKey k)
        {
            return k.Char < 0 || OskTakes(OskPage()[k.Char].ToString());
        }

        void OskInsert(string s)
        {
            if (!OskTakes(s)) return;
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
                string ch = OskPage()[k.Char].ToString();
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

        // To the next key in that direction that can type here; at the edge it stays
        void OskMove(int dir)
        {
            int row = oskRow, col = oskCol;
            while (true)
            {
                var k = OskKeyAt(row, col);
                if (dir == PadLeft && k.Col > 0) col = k.Col - 1;
                else if (dir == PadRight && k.Col + k.Span < oskCols) col = k.Col + k.Span;
                else if (dir == PadUp && row > 0) row--;
                else if (dir == PadDown && row < oskRows - 1) row++;
                else return;
                if (OskEnabled(OskKeyAt(row, col))) break;
            }
            oskRow = row;
            oskCol = col;
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
            else if ((fire & PadLT) != 0 && oskNumeric == null) { oskShift = !oskShift; OskRender(); }
            else if ((fire & PadRT) != 0 && oskNumeric == null) { oskSymbols = !oskSymbols; OskRender(); }
            else if ((fire & PadB) != 0) CloseOsk(false);
            else if (start) CloseOsk(true);
        }
    }
}
