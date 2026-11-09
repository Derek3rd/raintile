// Raintile Options: the window driven by a gamepad (XInput, Xbox and
// compatible controllers, as the launcher's helper). The controllers are read
// every 16 ms only while a window of this program is active and Gamepad
// support is on. A ring marks the control the pad is on; it goes away when the
// mouse moves or a key is pressed, and the first pad input brings it back
// without acting. In the menu there is no ring: up and down select the entry
// (its page shows at once, its background marks it), round the end of the menu;
// right goes to the first control of the page. While the pad is in use the
// buttons a pad button presses show its glyph (Start on Save and refresh, B on
// Close and on the last button of a dialog).
//
//   D-pad / left stick   move between controls (on a slider: left/right change it)
//   A                    press, switch, open a list, or type in a field (OskOpen);
//                        on the tile preview: move its parts (PadPlace.cs)
//   B                    back to the menu; in the menu: close; in a dialog: cancel
//   LB / RB              previous / next page
//   Start                Save and refresh (alone, on release: Back + Start is the
//                        launcher's toggle, read by the helper)
//   right stick          scrolls
//   (on the field of a gamepad setting, A waits for the button to pick: PadDial.cs)

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace RaintileOptions
{
    static class XInput
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct State
        {
            public uint PacketNumber;
            public ushort Buttons;
            public byte LeftTrigger, RightTrigger;
            public short ThumbLX, ThumbLY, ThumbRX, ThumbRY;
        }

        [DllImport("xinput1_4.dll", EntryPoint = "XInputGetState")]
        static extern uint GetState14(uint index, out State state);

        [DllImport("xinput9_1_0.dll", EntryPoint = "XInputGetState")]
        static extern uint GetState910(uint index, out State state);

        static bool use14 = true, none;

        public static bool GetState(uint index, out State state)
        {
            state = new State();
            if (none) return false;
            if (use14)
            {
                try { return GetState14(index, out state) == 0; }
                catch (DllNotFoundException) { use14 = false; }
                catch (EntryPointNotFoundException) { use14 = false; }
            }
            try { return GetState910(index, out state) == 0; }
            catch (DllNotFoundException) { none = true; }
            catch (EntryPointNotFoundException) { none = true; }
            return false;
        }
    }

    // The ring around the control the pad is on (drawn above the window, not
    // clipped by lists and scroll areas)
    class PadRing : Adorner
    {
        readonly Pen pen;

        public PadRing(UIElement element, Brush brush) : base(element)
        {
            IsHitTestVisible = false;
            pen = new Pen(brush, 2);
            pen.Freeze();
        }

        protected override void OnRender(DrawingContext dc)
        {
            var s = AdornedElement.RenderSize;
            dc.DrawRoundedRectangle(null, pen, new Rect(-4, -4, s.Width + 8, s.Height + 8), 9, 9);
        }
    }

    public partial class OptionsApp
    {
        // XInput buttons, and the triggers pressed past half way (as Helper.ps1)
        const int PadUp = 0x1, PadDown = 0x2, PadLeft = 0x4, PadRight = 0x8, PadStart = 0x10,
            PadLB = 0x100, PadRB = 0x200, PadA = 0x1000, PadB = 0x2000, PadX = 0x4000, PadY = 0x8000,
            PadLT = 0x10000, PadRT = 0x20000;
        const int PadDirs = PadUp | PadDown | PadLeft | PadRight;

        DispatcherTimer padTimer;
        readonly Stopwatch padClock = Stopwatch.StartNew();
        readonly bool[] padConnected = new bool[4];
        long padNextScan, padRepeatAt, padRepeatXAt, padLastRead;
        double padLX, padLY, padLT, padRT;   // left stick past the dead zone (-1..1), triggers (0..1)
        int padPrev, padRepeatDir;
        bool padStartAlone, padRepeatX;
        bool padMode;                 // the ring is shown: the last input came from the pad
        FrameworkElement padFocus;    // the control the pad is on
        PadRing padRing;
        Win32.Point padCursor;
        ComboBox padCombo;            // list opened with A
        int padComboStart;
        Slider padSlider;             // slider being changed: A on it, until A or B
        double padSliderStart;
        // Tag of the slider being changed: its thumb turns accent (Options.xaml)
        const string PadEditTag = "PadEdit";
        readonly List<TextBlock> padHints = new List<TextBlock>();   // glyphs of the pad buttons on buttons
        readonly uint padProcess = (uint)Process.GetCurrentProcess().Id;

        static readonly MethodInfo buttonOnClick = typeof(ButtonBase).GetMethod("OnClick", BindingFlags.Instance | BindingFlags.NonPublic);

        // A timer whose work runs in a dispatcher operation of its own, not in its
        // Tick: the work may open a modal dialog (the pad pressing a button that
        // asks something), and a DispatcherTimer does not tick while its own Tick
        // is inside one, so the pad would stop in the dialog. This way the work
        // runs inside the dialog's loop too, one call queued at a time.
        public static DispatcherTimer NewLoopTimer(TimeSpan interval, DispatcherPriority priority, Action work)
        {
            var t = new DispatcherTimer(priority) { Interval = interval };
            bool queued = false;
            t.Tick += (s, e) =>
            {
                if (queued) return;
                queued = true;
                t.Dispatcher.BeginInvoke(new Action(() => { queued = false; if (t.IsEnabled) work(); }), priority);
            };
            return t;
        }

        void InitGamepad()
        {
            padTimer = NewLoopTimer(TimeSpan.FromMilliseconds(16), DispatcherPriority.Input, PadTick);
            // only while this program is in the foreground (its dialogs too)
            app.Activated += (s, e) => StartPad();
            win.Activated += (s, e) => StartPad();
            app.Deactivated += (s, e) => StopPad();
            win.Closed += (s, e) => StopPad();
            // a click or a key: mouse and keyboard take over
            EventManager.RegisterClassHandler(typeof(Window), UIElement.PreviewMouseDownEvent, new MouseButtonEventHandler((s, e) => PadModeOff(true)));
            EventManager.RegisterClassHandler(typeof(Window), UIElement.PreviewKeyDownEvent, new KeyEventHandler((s, e) => PadModeOff(true)));
            AddPadHint((Button)win.FindName("BtnPreview"), Glyph.PadY);
            AddPadHint(btnSave, Glyph.PadStart);
            AddPadHint((Button)win.FindName("BtnClose"), Glyph.PadB);
        }

        // A new text for a button with a pad hint, its glyph kept
        static void SetPadHintText(Button b, string text)
        {
            var sp = b.Content as StackPanel;
            var t = sp != null && sp.Children.Count > 0 ? sp.Children[sp.Children.Count - 1] as TextBlock : null;
            if (t != null) t.Text = text; else b.Content = text;
            AutomationProperties.SetName(b, text);
        }

        // The glyph of the pad button that presses b, before its text, shown only
        // while the pad is in use. Returns it, to drop it with RemovePadHint.
        TextBlock AddPadHint(Button b, int glyph)
        {
            string text = b.Content as string ?? "";
            var g = NewGlyph(glyph, Fs.Label);
            g.Margin = T(0, 0, Gap.Text, 0);
            g.Visibility = padMode ? Visibility.Visible : Visibility.Collapsed;
            var sp = NewPanel(Orientation.Horizontal);
            AddTo(sp, g);
            AddTo(sp, new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center });
            b.Content = sp;
            AutomationProperties.SetName(b, text);
            padHints.Add(g);
            return g;
        }

        void RemovePadHint(TextBlock g) { padHints.Remove(g); }

        void SetPadHints(bool on)
        {
            foreach (var g in padHints) g.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        }

        // An entry of the menu on the left
        bool InMenu(FrameworkElement fe)
        {
            var list = fe is ListBoxItem ? ItemsControl.ItemsControlFromItemContainer(fe) : null;
            return list != null && (list == nav || list == navBottom);
        }

        void StartPad()
        {
            if (V("Gamepad") == "0" || padTimer.IsEnabled) return;
            // buttons already held when the window comes back do not count
            padNextScan = 0;
            int rx, ry;
            padPrev = ReadPad(out rx, out ry);
            padRepeatDir = 0;
            padRepeatX = false;
            padStartAlone = false;
            Win32.GetCursorPos(out padCursor);
            padTimer.Start();
        }

        void StopPad()
        {
            padTimer.Stop();
            CloseOsk(true);
            EndPlace(true);
            EndSliderEdit(true);
            EndPadCapture();
            padIgnoreHeld = false;
            padCombo = null;
        }

        void PadModeOff(bool closeOsk)
        {
            if (closeOsk) { CloseOsk(true); EndPlace(true); }
            EndSliderEdit(true);
            EndPadCapture();
            if (!padMode) return;
            padMode = false;
            HideRing();
            SetPadHints(false);
        }

        int PadSetting(string key, int fallback, int min, int max)
        {
            double n;
            if (!Core.TryNumber(V(key), out n)) return fallback;
            return (int)Math.Max(min, Math.Min(max, n));
        }

        // Buttons of all the controllers together; the left stick counts as the D-pad.
        // Disconnected controllers are checked again every 2 s (the call on an empty
        // slot is slow).
        int ReadPad(out int rx, out int ry)
        {
            long now = padClock.ElapsedMilliseconds;
            bool scan = now >= padNextScan;
            if (scan) padNextScan = now + 2000;
            int buttons = 0, lx = 0, ly = 0, lt = 0, rt = 0;
            rx = 0; ry = 0;
            for (uint i = 0; i < 4; i++)
            {
                if (!padConnected[i] && !scan) continue;
                XInput.State st;
                padConnected[i] = XInput.GetState(i, out st);
                if (!padConnected[i]) continue;
                buttons |= st.Buttons;
                if (st.LeftTrigger > 128) buttons |= PadLT;
                if (st.RightTrigger > 128) buttons |= PadRT;
                lt = Math.Max(lt, st.LeftTrigger);
                rt = Math.Max(rt, st.RightTrigger);
                if (Math.Abs((int)st.ThumbLX) > Math.Abs(lx)) lx = st.ThumbLX;
                if (Math.Abs((int)st.ThumbLY) > Math.Abs(ly)) ly = st.ThumbLY;
                if (Math.Abs((int)st.ThumbRX) > Math.Abs(rx)) rx = st.ThumbRX;
                if (Math.Abs((int)st.ThumbRY) > Math.Abs(ry)) ry = st.ThumbRY;
            }
            // as they are, for picking a button (PadDial.cs)
            padRawPrev = padRaw;
            padRaw = buttons;
            int dead = PadSetting("GamepadDeadZone", 12000, 0, 32767);
            if (Math.Abs(lx) > dead || Math.Abs(ly) > dead)
                buttons |= Math.Abs(lx) > Math.Abs(ly) ? (lx > 0 ? PadRight : PadLeft) : (ly > 0 ? PadUp : PadDown);
            if (Math.Abs(rx) <= dead) rx = 0;
            if (Math.Abs(ry) <= dead) ry = 0;
            // as amounts, for placing in the preview (PadPlace.cs): from 0 at the
            // dead zone to 1 at full tilt; the triggers past a light touch
            Func<int, int, int, double> amount = (v, zone, full) => Math.Abs(v) <= zone ? 0 : Math.Sign(v) * Math.Min(1.0, (Math.Abs(v) - zone) / (double)Math.Max(1, full - zone));
            padLX = amount(lx, dead, 32767);
            padLY = amount(ly, dead, 32767);
            padLT = amount(lt, 30, 255);
            padRT = amount(rt, 30, 255);
            return buttons;
        }

        static int FirstDir(int buttons)
        {
            foreach (int d in new[] { PadUp, PadDown, PadLeft, PadRight }) if ((buttons & d) != 0) return d;
            return 0;
        }

        static Window ActiveWindow()
        {
            foreach (Window w in Application.Current.Windows) if (w.IsActive) return w;
            return null;
        }

        void PadTick()
        {
            if (V("Gamepad") == "0") { StopPad(); return; }
            int rx, ry;
            int buttons = ReadPad(out rx, out ry);
            int prev = padPrev;
            padPrev = buttons;
            long now = padClock.ElapsedMilliseconds;
            // moving in the preview is time-based: a late read moves more, up to a limit
            double dt = Math.Min(0.1, Math.Max(0, now - padLastRead) / 1000.0);
            padLastRead = now;

            // the mouse moved: the ring goes (the on-screen keyboard stays, its keys can be clicked)
            Win32.Point c;
            if (Win32.GetCursorPos(out c))
            {
                if (Math.Abs(c.X - padCursor.X) + Math.Abs(c.Y - padCursor.Y) > 3) PadModeOff(false);
                padCursor = c;
            }

            // one direction held repeats, as in the launcher; X too (delete, on the keyboard)
            int fire = buttons & ~prev & ~(PadDirs | PadX);
            int dir = FirstDir(buttons);
            if (dir == 0) padRepeatDir = 0;
            else if (dir != padRepeatDir)
            {
                padRepeatDir = dir;
                padRepeatAt = now + PadSetting("GamepadRepeatDelay", 350, 50, 1000);
                fire |= dir;
            }
            else if (now >= padRepeatAt)
            {
                padRepeatAt = now + PadSetting("GamepadRepeatRate", 110, 30, 500);
                fire |= dir;
            }
            if ((buttons & PadX) == 0) padRepeatX = false;
            else if (!padRepeatX)
            {
                padRepeatX = true;
                padRepeatXAt = now + PadSetting("GamepadRepeatDelay", 350, 50, 1000);
                fire |= PadX;
            }
            else if (now >= padRepeatXAt)
            {
                padRepeatXAt = now + PadSetting("GamepadRepeatRate", 110, 30, 500);
                fire |= PadX;
            }
            // Start alone, on release
            if ((buttons & ~prev & PadStart) != 0) padStartAlone = buttons == PadStart;
            else if ((buttons & PadStart) != 0 && buttons != PadStart) padStartAlone = false;
            bool start = (prev & PadStart) != 0 && (buttons & PadStart) == 0 && padStartAlone;
            if (start) padStartAlone = false;

            var root = ActiveWindow();
            if (root == null)
            {
                // another program in the foreground: stop until a window of this
                // one is active again (a colour or file dialog of its own: wait)
                uint pid;
                Win32.GetWindowThreadProcessId(Win32.GetForegroundWindow(), out pid);
                if (pid != padProcess) StopPad();
                return;
            }
            if (root == win && refreshing) return;

            // a button was just picked (PadDial.cs): it does nothing more, Start
            // does not save on its release
            if (padIgnoreHeld)
            {
                if (buttons == 0) { padIgnoreHeld = false; padStartAlone = false; }
                return;
            }
            if (padCaptureField != null) { PadCaptureInput(); return; }
            if (padDial != null && padDial.IsOpen) { PadDialInput(); return; }

            if (oskTarget != null) { OskInput(fire, start); return; }
            if (padCombo != null)
            {
                if (padCombo.IsDropDownOpen) { PadComboInput(fire); return; }
                padCombo = null;
            }
            if (padSlider != null) { PadSliderInput(fire); return; }
            if (placePart >= 0 && root == win) { PadPlaceInput(fire, start, dt); return; }
            if (rx != 0 || ry != 0) PadScroll(root, rx, ry);
            if (padMode)
            {
                // the control may be gone (page rebuilt, dialog opened or closed)
                EnsurePadFocus(root);
                ShowRing();
            }
            if (fire == 0 && !start) return;

            // first input after the mouse: shows where the pad is
            if (!padMode)
            {
                padMode = true;
                SetPadHints(true);
                EnsurePadFocus(root);
                ShowRing();
                if ((fire & (PadDirs | PadA)) != 0) return;
            }

            int d = FirstDir(fire);
            if (d != 0) PadMove(root, d);
            else if ((fire & PadA) != 0) PadActivate();
            else if ((fire & PadB) != 0) PadBack(root);
            else if ((fire & PadLB) != 0 && root == win) PadPage(-1);
            else if ((fire & PadRB) != 0 && root == win) PadPage(1);
            // the preview beside the window, as its button in the footer
            else if ((fire & PadY) != 0 && root == win && btnPreview != null) btnPreview.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            else if (start && root == win)
            {
                // the button takes the focus first, as with a click: fields that
                // keep their value when left (tile name) do so
                btnSave.Focus();
                StartSaveAndRefresh();
            }
            ShowRing();
        }

        // --- Where the pad is --------------------------------------------------------

        static bool IsPadTarget(FrameworkElement fe)
        {
            return fe is ButtonBase || fe is TextBox || fe is PasswordBox || fe is ComboBox || fe is Slider || fe is ListBoxItem || padAreas.ContainsKey(fe);
        }

        static void CollectPadTargets(DependencyObject d, List<FrameworkElement> list)
        {
            var fe = d as FrameworkElement;
            if (fe != null)
            {
                if (!fe.IsVisible || !fe.IsEnabled || fe is ScrollBar) return;
                if (IsPadTarget(fe))
                {
                    if (fe.Focusable) list.Add(fe);
                    return;
                }
            }
            int n = VisualTreeHelper.GetChildrenCount(d);
            for (int i = 0; i < n; i++) CollectPadTargets(VisualTreeHelper.GetChild(d, i), list);
        }

        static bool PadUsable(FrameworkElement fe, Window root)
        {
            return fe != null && fe.IsVisible && fe.IsEnabled && IsPadTarget(fe) && Window.GetWindow(fe) == root;
        }

        void EnsurePadFocus(Window root)
        {
            if (PadUsable(padFocus, root)) return;
            FrameworkElement next = null;
            // the control with the keyboard focus (the field of an editable list: the list)
            var focused = Keyboard.FocusedElement as FrameworkElement;
            if (focused is TextBox && focused.TemplatedParent is ComboBox) focused = (ComboBox)focused.TemplatedParent;
            if (PadUsable(focused, root)) next = focused;
            else if (root == win) next = (nav.SelectedItem ?? navBottom.SelectedItem) as ListBoxItem;
            if (!PadUsable(next, root))
            {
                var all = new List<FrameworkElement>();
                CollectPadTargets(root, all);
                // a dialog that asks for a text (a name): its field, ready for A
                // (the keyboard), whether or not it has the focus yet
                next = (root != win ? all.OfType<TextBox>().FirstOrDefault(t => !t.IsReadOnly) : null)
                    ?? all.OfType<Button>().FirstOrDefault(b => b.IsDefault) ?? all.FirstOrDefault();
            }
            if (next != null) PadSetFocus(next, false);
        }

        void PadSetFocus(FrameworkElement fe, bool scroll = true)
        {
            padFocus = fe;
            fe.Focus();
            // some room around it: the title of its card, the next row
            if (scroll) fe.BringIntoView(new Rect(-24, -56, fe.ActualWidth + 48, fe.ActualHeight + 112));
            ShowRing();
        }

        void ShowRing()
        {
            if (!padMode || padFocus == null) return;
            // in the menu the background of the selected entry is enough (the
            // ring would be cut by the list at its sides); a slider being changed
            // shows it with its thumb
            if (InMenu(padFocus) || padSlider != null) { HideRing(); return; }
            if (padRing != null && padRing.AdornedElement == padFocus) return;
            HideRing();
            var layer = AdornerLayer.GetAdornerLayer(padFocus);
            if (layer == null) return;
            padRing = new PadRing(padFocus, ResBrush("AccentBrush"));
            layer.Add(padRing);
        }

        void HideRing()
        {
            if (padRing == null) return;
            var layer = AdornerLayer.GetAdornerLayer(padRing.AdornedElement);
            if (layer != null) layer.Remove(padRing);
            padRing = null;
        }

        // --- Moving ------------------------------------------------------------------

        static Rect PadRect(FrameworkElement fe, Visual root)
        {
            try { return fe.TransformToAncestor(root).TransformBounds(new Rect(0, 0, fe.ActualWidth, fe.ActualHeight)); }
            catch (InvalidOperationException) { return Rect.Empty; }
        }

        static ScrollViewer PadScope(DependencyObject d)
        {
            for (var p = VisualTreeHelper.GetParent(d); p != null; p = VisualTreeHelper.GetParent(p))
            {
                var sv = p as ScrollViewer;
                if (sv != null) return sv;
            }
            return null;
        }

        // Outside the scroll areas the pad is in, only what they show counts:
        // the rest of a page is not under the buttons at the bottom
        bool PadShown(FrameworkElement fe, Rect r, Visual root)
        {
            for (var p = VisualTreeHelper.GetParent(fe); p != null; p = VisualTreeHelper.GetParent(p))
            {
                var sv = p as ScrollViewer;
                if (sv == null || sv.IsAncestorOf(padFocus)) continue;
                var view = Rect.Intersect(PadRect(sv, root), r);
                if (view.IsEmpty || view.Width < 2 || view.Height < 2) return false;
            }
            return true;
        }

        // Is b in direction 'dir' from a? major: the distance that way; gap: how far
        // apart they are across (0 when they overlap); center: their centers across
        static bool PadDirTo(Rect a, Rect b, int dir, out double major, out double gap, out double center)
        {
            double acx = a.Left + a.Width / 2, acy = a.Top + a.Height / 2;
            double bcx = b.Left + b.Width / 2, bcy = b.Top + b.Height / 2;
            major = gap = center = 0;
            bool vertical = dir == PadUp || dir == PadDown;
            if (dir == PadDown && (bcy <= acy + 1 || b.Bottom <= a.Bottom)) return false;
            if (dir == PadUp && (bcy >= acy - 1 || b.Top >= a.Top)) return false;
            if (dir == PadRight && (bcx <= acx + 1 || b.Right <= a.Right)) return false;
            if (dir == PadLeft && (bcx >= acx - 1 || b.Left >= a.Left)) return false;
            switch (dir)
            {
                case PadDown: major = b.Top - a.Bottom; break;
                case PadUp: major = a.Top - b.Bottom; break;
                case PadRight: major = b.Left - a.Right; break;
                default: major = a.Left - b.Right; break;
            }
            major = Math.Max(0, major);
            gap = vertical ? Math.Max(0, Math.Max(b.Left - a.Right, a.Left - b.Right)) : Math.Max(0, Math.Max(b.Top - a.Bottom, a.Top - b.Bottom));
            center = vertical ? Math.Abs(bcx - acx) : Math.Abs(bcy - acy);
            return true;
        }

        // The control to go to: the nearest one that way, first in the scroll area
        // the pad is in (a page goes on below what is shown). Sideways only what is
        // level with it counts, except when leaving the area (menu <-> page).
        FrameworkElement PadFind(Window root, int dir)
        {
            var cur = PadRect(padFocus, root);
            if (cur.IsEmpty) return null;
            var scope = PadScope(padFocus);
            var all = new List<FrameworkElement>();
            CollectPadTargets(root, all);
            bool sideways = dir == PadLeft || dir == PadRight;
            int tiers = sideways ? 3 : 2;
            for (int tier = 0; tier < tiers; tier++)
            {
                FrameworkElement best = null;
                double bestScore = double.MaxValue;
                foreach (var c in all)
                {
                    if (c == padFocus) continue;
                    var r = PadRect(c, root);
                    if (r.IsEmpty) continue;
                    bool inScope = scope != null && scope.IsAncestorOf(c);
                    if (!inScope && !PadShown(c, r, root)) continue;
                    double major, gap, center;
                    if (!PadDirTo(cur, r, dir, out major, out gap, out center)) continue;
                    bool level = gap <= 0;
                    double score;
                    if (sideways)
                    {
                        if (tier == 0 && !(inScope && level)) continue;
                        if (tier == 1 && !level) continue;
                        if (tier == 2 && inScope) continue;
                        score = tier < 2 ? major * 4 + center * 0.5 : gap * 4 + major * 0.5;
                    }
                    else
                    {
                        if (tier == 0 && !inScope) continue;
                        score = major * 4 + gap + center * 0.05;
                    }
                    if (score < bestScore) { bestScore = score; best = c; }
                }
                if (best != null) return best;
            }
            return null;
        }

        static Panel ItemsHost(DependencyObject d)
        {
            int n = VisualTreeHelper.GetChildrenCount(d);
            for (int i = 0; i < n; i++)
            {
                var child = VisualTreeHelper.GetChild(d, i);
                var p = child as Panel;
                if (p != null && p.IsItemsHost) return p;
                var found = ItemsHost(child);
                if (found != null) return found;
            }
            return null;
        }

        // In a list the next entry is the next by index, also when it is not built
        // yet (long lists build only what is on screen)
        bool PadListStep(ListBoxItem item, int dir)
        {
            var list = ItemsControl.ItemsControlFromItemContainer(item) as ListBox;
            if (list == null) return false;
            var host = ItemsHost(list);
            bool horizontal;
            if (host is StackPanel) horizontal = ((StackPanel)host).Orientation == Orientation.Horizontal;
            else if (host is VirtualizingStackPanel) horizontal = ((VirtualizingStackPanel)host).Orientation == Orientation.Horizontal;
            else return false;
            int step;
            if (horizontal) step = dir == PadRight ? 1 : dir == PadLeft ? -1 : 0;
            else step = dir == PadDown ? 1 : dir == PadUp ? -1 : 0;
            if (step == 0) return false;
            int i = list.ItemContainerGenerator.IndexFromContainer(item) + step;
            for (; i >= 0 && i < list.Items.Count; i += step)
            {
                list.ScrollIntoView(list.Items[i]);
                list.UpdateLayout();
                var next = list.ItemContainerGenerator.ContainerFromIndex(i) as ListBoxItem;
                if (next != null && next.IsVisible && next.IsEnabled) { PadSetFocus(next); return true; }
            }
            return false;
        }

        void PadMove(Window root, int dir)
        {
            // the menu: up and down select (round its end), right goes into the page
            if (root == win && InMenu(padFocus))
            {
                if (dir == PadUp || dir == PadDown)
                {
                    var entry = NavStep(dir == PadDown ? 1 : -1);
                    if (entry != null) PadSetFocus(entry);
                }
                else if (dir == PadRight) PadPageStart();
                return;
            }
            var item = padFocus as ListBoxItem;
            if (item != null && PadListStep(item, dir)) return;
            var next = PadFind(root, dir);
            // back into the menu: on the page shown, not on the entry nearest
            if (next != null && root == win && InMenu(next)) next = (nav.SelectedItem ?? navBottom.SelectedItem) as ListBoxItem ?? next;
            if (next != null) PadSetFocus(next);
        }

        // The first control of the page: the top one, the left one of a row (also
        // when the page is scrolled down)
        void PadPageStart()
        {
            var all = new List<FrameworkElement>();
            // the switch beside the page title (Page.Switch) first: it is at the top
            CollectPadTargets(pageSwitch, all);
            CollectPadTargets(pageHost, all);
            FrameworkElement best = null;
            Rect bestRect = Rect.Empty;
            foreach (var c in all)
            {
                var r = PadRect(c, win);
                if (r.IsEmpty) continue;
                // a row: what overlaps the best up and down counts as the same row
                // (a slider is lower than the box after it, centred in the row)
                bool sameRow = best != null && r.Top < bestRect.Bottom && r.Bottom > bestRect.Top;
                if (best == null || (sameRow ? r.Left < bestRect.Left : r.Top < bestRect.Top))
                {
                    best = c;
                    bestRect = r;
                }
            }
            if (best != null) PadSetFocus(best);
        }

        // --- Acting ------------------------------------------------------------------

        void PadActivate()
        {
            var fe = padFocus;
            if (fe == null) return;
            Action area;
            if (padAreas.TryGetValue(fe, out area)) { area(); return; }
            var cb = fe as ComboBox;
            if (cb != null)
            {
                padCombo = cb;
                padComboStart = cb.SelectedIndex;
                cb.IsDropDownOpen = true;
                return;
            }
            var slider = fe as Slider;
            if (slider != null) { StartSliderEdit(slider); return; }
            var tb = fe as TextBox;
            if ((tb != null && !tb.IsReadOnly) || fe is PasswordBox) { OpenOsk(fe); return; }
            var item = fe as ListBoxItem;
            if (item != null)
            {
                var list = ItemsControl.ItemsControlFromItemContainer(item) as ListBox;
                if (list != null && list.SelectionMode != SelectionMode.Single) item.IsSelected = !item.IsSelected;
                else item.IsSelected = true;
                return;
            }
            var b = fe as ButtonBase;
            if (b != null) PadClick(b);
        }

        // As a click: switches, choices and buttons run their own handlers
        static void PadClick(ButtonBase b)
        {
            try { buttonOnClick.Invoke(b, null); }
            catch (TargetInvocationException e)
            {
                if (e.InnerException != null) ExceptionDispatchInfo.Capture(e.InnerException).Throw();
                throw;
            }
        }

        void PadBack(Window root)
        {
            // a dialog: as Esc
            if (root != win) { root.Close(); return; }
            var list = padFocus is ListBoxItem ? ItemsControl.ItemsControlFromItemContainer(padFocus) : null;
            if (list == nav || list == navBottom) { win.Close(); return; }
            var sel = (nav.SelectedItem ?? navBottom.SelectedItem) as ListBoxItem;
            if (sel != null) PadSetFocus(sel);
        }

        // LB / RB: the previous / next page of the menu (NavStep)
        void PadPage(int delta)
        {
            // a group rebuilds the menu: the pad goes to its new entry on the next read
            var next = NavStep(delta);
            if (next != null) PadSetFocus(next);
        }

        void PadComboInput(int fire)
        {
            var cb = padCombo;
            int step = (fire & PadDown) != 0 ? 1 : (fire & PadUp) != 0 ? -1 : (fire & PadRB) != 0 ? 10 : (fire & PadLB) != 0 ? -10 : 0;
            if (step != 0 && cb.Items.Count > 0)
            {
                int i = Math.Max(0, Math.Min(cb.Items.Count - 1, cb.SelectedIndex + step));
                if (cb.SelectedIndex < 0) i = 0;
                cb.SelectedIndex = i;
                var popup = cb.Template.FindName("PART_Popup", cb) as Popup;
                var host = popup != null && popup.Child != null ? ItemsHost(popup.Child) as VirtualizingStackPanel : null;
                if (host != null) host.BringIndexIntoViewPublic(i);
                else
                {
                    var c = cb.ItemContainerGenerator.ContainerFromIndex(i) as FrameworkElement;
                    if (c != null) c.BringIntoView();
                }
            }
            if ((fire & PadA) != 0) { cb.IsDropDownOpen = false; padCombo = null; }
            else if ((fire & PadB) != 0)
            {
                cb.SelectedIndex = padComboStart;
                cb.IsDropDownOpen = false;
                padCombo = null;
            }
        }

        // A slider is passed over like any control: A starts changing it (the ring
        // goes, its thumb turns accent), left / right change it, A keeps the value,
        // B puts back the one it had. So the number box next to it can be reached.
        void StartSliderEdit(Slider s)
        {
            padSlider = s;
            padSliderStart = s.Value;
            s.Tag = PadEditTag;
            HideRing();
        }

        void EndSliderEdit(bool keep)
        {
            var s = padSlider;
            if (s == null) return;
            padSlider = null;
            if (!keep && s.Value != padSliderStart) s.Value = padSliderStart;
            s.ClearValue(FrameworkElement.TagProperty);
            ShowRing();
        }

        void PadSliderInput(int fire)
        {
            // gone (page rebuilt): the value stays as it is
            if (!padSlider.IsVisible) { EndSliderEdit(true); return; }
            int d = FirstDir(fire);
            if (d == PadLeft || d == PadRight) (d == PadRight ? Slider.IncreaseSmall : Slider.DecreaseSmall).Execute(null, padSlider);
            else if ((fire & PadA) != 0) EndSliderEdit(true);
            else if ((fire & PadB) != 0) EndSliderEdit(false);
        }

        // Right stick: scrolls the area the pad is in (or the page)
        void PadScroll(Window root, int rx, int ry)
        {
            ScrollViewer v = null, h = null;
            for (DependencyObject p = padFocus; p != null; p = VisualTreeHelper.GetParent(p))
            {
                var sv = p as ScrollViewer;
                if (sv == null) continue;
                if (v == null && sv.ScrollableHeight > 0) v = sv;
                if (h == null && sv.ScrollableWidth > 0) h = sv;
            }
            if (v == null && root == win) v = FindScrollViewer(pageHost);
            if (v != null && ry != 0) v.ScrollToVerticalOffset(v.VerticalOffset - ry / 32767.0 * 24);
            if (h != null && rx != 0) h.ScrollToHorizontalOffset(h.HorizontalOffset + rx / 32767.0 * 24);
        }
    }
}
