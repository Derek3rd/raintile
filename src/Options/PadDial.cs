// Raintile Options: picking the buttons of a gamepad setting (NewPadControl),
// held together, up to PadMax. With the mouse or the keys the field opens a
// dial around it: the buttons of the controller on a ring, where they are on
// it (Schema.GAMEPAD_BUTTONS), the ones of the combination lit; a click, or
// the arrows and Enter, put one in or take it out, Esc or a click elsewhere
// close it, a button of the pad goes in or out by itself. With the pad, A on
// the field waits for buttons held together (B and Start too), taken when
// they are all released: nothing else of the window acts meanwhile. Moving
// the mouse, a key or 5 s without a button stop waiting.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;

namespace RaintileOptions
{
    public partial class OptionsApp
    {
        // The XInput bit of each button (Gamepad.cs)
        static readonly Dictionary<string, int> PadBits = new Dictionary<string, int>
        {
            { "UP", PadUp }, { "DOWN", PadDown }, { "LEFT", PadLeft }, { "RIGHT", PadRight }, { "START", PadStart }, { "BACK", PadView },
            { "LS", PadLS }, { "RS", PadRS }, { "LB", PadLB }, { "RB", PadRB }, { "A", PadA }, { "B", PadB },
            { "X", PadX }, { "Y", PadY }, { "LT", PadLT }, { "RT", PadRT },
        };
        const int PadCaptureMs = 5000;

        int padRaw, padRawPrev;           // buttons as they are (no stick), this read and the one before
        bool padIgnoreHeld;               // a button was picked: the pad does nothing until all are released
        Button padCaptureField;           // the field waiting for buttons of the pad
        string padCaptureKey;
        int padCaptureHeld;               // the buttons held so far, together
        long padCaptureUntil;
        bool padCaptureReady;             // A, which started it, was released

        Popup padDial;
        Border[] padDialKeys;
        string padDialKey;
        int padDialSel;
        Button padDialField;

        // The first button of 'buttons' in the order of the dial
        static string PadButtonIn(int buttons)
        {
            return Schema.GAMEPAD_BUTTONS.FirstOrDefault(b => (buttons & PadBits[b]) != 0);
        }

        // --- Waiting for a button of the pad -----------------------------------------

        void StartPadCapture(string key)
        {
            EndPadCapture();
            Ctl c;
            if (!ctl.TryGetValue(key, out c)) return;
            padCaptureField = c.Button;
            padCaptureKey = key;
            padCaptureHeld = 0;
            padCaptureReady = false;
            padCaptureUntil = padClock.ElapsedMilliseconds + PadCaptureMs;
            padCaptureField.Content = "Hold the buttons";
            padCaptureField.ToolTip = null;
        }

        // The buttons of a mask in the order of the dial, at most PadMax
        static List<string> PadButtonsIn(int buttons)
        {
            return Schema.GAMEPAD_BUTTONS.Where(b => (buttons & PadBits[b]) != 0).Take(PadMax).ToList();
        }

        // Stops waiting; the field shows its value again
        void EndPadCapture()
        {
            if (padCaptureField == null) return;
            padCaptureField = null;
            ShowPadSlots(padCaptureKey);
        }

        // The pad while the field waits (PadTick): after A was released, the
        // buttons held together, shown while they are; when all of them are
        // released they are the new combination
        void PadCaptureInput()
        {
            if (!padCaptureReady)
            {
                if (padClock.ElapsedMilliseconds > padCaptureUntil) { EndPadCapture(); return; }
                if (padRaw == 0) padCaptureReady = true;
                return;
            }
            if (padRaw != 0)
            {
                int before = padCaptureHeld;
                padCaptureHeld |= padRaw;
                if (padCaptureHeld != before) padCaptureField.Content = NewPadCombo(PadButtonsIn(padCaptureHeld));
                return;
            }
            if (padCaptureHeld == 0)
            {
                if (padClock.ElapsedMilliseconds > padCaptureUntil) EndPadCapture();
                return;
            }
            string key = padCaptureKey;
            var list = PadButtonsIn(padCaptureHeld);
            padCaptureField = null;
            SetPadCombo(key, list);
        }

        // --- The dial ----------------------------------------------------------------

        void OpenPadDial(string key)
        {
            Ctl c;
            if (!ctl.TryGetValue(key, out c)) return;
            ClosePadDial();
            if (padDial == null) BuildPadDial();
            padDialKey = key;
            padDialField = c.Button;
            var list = PadButtons(PadValue(key));
            padDialSel = list.Count > 0 ? Array.IndexOf(Schema.GAMEPAD_BUTTONS, list[0]) : -1;
            RenderPadDial();
            padDial.PlacementTarget = padDialField;
            padDial.IsOpen = true;
            padDialField.PreviewKeyDown += PadDialKeyDown;
        }

        void ClosePadDial()
        {
            if (padDial == null || padDialField == null) return;
            padDialField.PreviewKeyDown -= PadDialKeyDown;
            var field = padDialField;
            padDialField = null;
            padDial.IsOpen = false;
            ShowPadSlots(padDialKey);
            field.Focus();
        }

        // A button of the dial in or out of the combination; the dial stays
        void PickPadDial(int index)
        {
            if (padDialField == null || index < 0) return;
            padDialSel = index;
            TogglePadButton(padDialKey, Schema.GAMEPAD_BUTTONS[index]);
            RenderPadDial();
        }

        // The keys of the field while the dial is open: the arrows turn round it
        // (right and down clockwise), Enter or Space pick, Esc and Tab close
        void PadDialKeyDown(object sender, KeyEventArgs e)
        {
            int n = Schema.GAMEPAD_BUTTONS.Length;
            switch (e.Key)
            {
                case Key.Right:
                case Key.Down:
                    padDialSel = (padDialSel + 1) % n;
                    break;
                case Key.Left:
                case Key.Up:
                    padDialSel = padDialSel <= 0 ? n - 1 : padDialSel - 1;
                    break;
                case Key.Enter:
                case Key.Space:
                    e.Handled = true;
                    PickPadDial(padDialSel);
                    return;
                case Key.Escape:
                case Key.Tab:
                    e.Handled = e.Key == Key.Escape;
                    ClosePadDial();
                    return;
                default: return;
            }
            e.Handled = true;
            RenderPadDial();
        }

        // The pad while the dial is open (PadTick): a button pressed picks itself
        void PadDialInput()
        {
            string b = PadButtonIn(padRaw & ~padRawPrev);
            if (b == null) return;
            padIgnoreHeld = true;
            PickPadDial(Array.IndexOf(Schema.GAMEPAD_BUTTONS, b));
        }

        void BuildPadDial()
        {
            // a ring of round keys around the field, which shows in its middle
            const double key = 38, radius = 116, ring = 52;   // ui-exempt: drawing of the dial
            double size = 2 * radius + key + 2 * Gap.Card;
            var canvas = new Canvas { Width = size, Height = size };
            // (almost transparent: a click in the middle closes the dial instead
            // of reaching the field under it)
            canvas.Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
            canvas.MouseLeftButtonUp += (s, e) => { if (e.OriginalSource == canvas) ClosePadDial(); };
            var back = new Ellipse
            {
                Width = 2 * radius + ring, Height = 2 * radius + ring, Stroke = ResBrush("CardBg"), StrokeThickness = ring,
                Effect = new DropShadowEffect { BlurRadius = 24, ShadowDepth = 4, Opacity = 0.5 },   // ui-exempt: as the on-screen keyboard
            };
            Canvas.SetLeft(back, size / 2 - back.Width / 2);
            Canvas.SetTop(back, size / 2 - back.Height / 2);
            canvas.Children.Add(back);
            var edge = new Ellipse { Width = back.Width, Height = back.Height, Stroke = ResBrush("AccentBrush"), StrokeThickness = 1, IsHitTestVisible = false };
            Canvas.SetLeft(edge, Canvas.GetLeft(back));
            Canvas.SetTop(edge, Canvas.GetTop(back));
            canvas.Children.Add(edge);
            var inner = new Ellipse { Width = back.Width - 2 * ring, Height = back.Height - 2 * ring, Stroke = ResBrush("LineBrush"), StrokeThickness = 1, IsHitTestVisible = false };
            Canvas.SetLeft(inner, size / 2 - inner.Width / 2);
            Canvas.SetTop(inner, size / 2 - inner.Height / 2);
            canvas.Children.Add(inner);

            int n = Schema.GAMEPAD_BUTTONS.Length;
            padDialKeys = new Border[n];
            for (int i = 0; i < n; i++)
            {
                int index = i;
                string name;
                // clockwise from the top, half a step off it: the bumpers on its two sides
                double a = (-90 + 360.0 / n * (i + 0.5)) * Math.PI / 180;
                var k = new Border { Width = key, Height = key, CornerRadius = new CornerRadius(key / 2), Cursor = Cursors.Hand, BorderThickness = T(1) };
                k.ToolTip = Schema.PAD_LABELS.TryGetValue(Schema.GAMEPAD_BUTTONS[i], out name) ? name : Schema.GAMEPAD_BUTTONS[i];
                Canvas.SetLeft(k, size / 2 + radius * Math.Cos(a) - key / 2);
                Canvas.SetTop(k, size / 2 + radius * Math.Sin(a) - key / 2);
                k.MouseEnter += (s, e) => { padDialSel = index; RenderPadDial(); };
                k.MouseLeftButtonUp += (s, e) => { e.Handled = true; PickPadDial(index); };
                padDialKeys[i] = k;
                canvas.Children.Add(k);
            }
            padDial = new Popup
            {
                AllowsTransparency = true, StaysOpen = false, Placement = PlacementMode.Center, Focusable = false,
                PopupAnimation = PopupAnimation.Fade, Child = canvas,
            };
            padDial.Closed += (s, e) => { if (padDialField != null) ClosePadDial(); };
        }

        // The keys: the one under the mouse or the arrows in accent, the ones of
        // the combination softly; the field shows the combination
        void RenderPadDial()
        {
            var combo = PadButtons(PadValue(padDialKey));
            for (int i = 0; i < padDialKeys.Length; i++)
            {
                bool sel = i == padDialSel, cur = combo.Contains(Schema.GAMEPAD_BUTTONS[i]);
                var k = padDialKeys[i];
                k.Background = ResBrush(sel ? "AccentBrush" : cur ? "AccentSoftBrush" : "FieldBg");
                k.BorderBrush = ResBrush(cur && !sel ? "AccentBrush" : "LineBrush");
                k.Child = NewPadFace(Schema.GAMEPAD_BUTTONS[i], ResBrush(sel ? "OnAccentBrush" : cur ? "AccentBrush" : "TextBrush"));
            }
            if (padDialField != null) padDialField.Content = NewPadCombo(combo);
        }
    }
}
