// Raintile Options: the preview of the tile editor with the gamepad. A on the
// preview starts placing: what the mouse does by dragging and with the wheel.
// The part being moved is outlined in the preview and named in a line under it.
//
//   left stick     moves it (the further, the faster)    D-pad  one pixel
//   LB / RB        background, logo, play time line
//   LT / RT        smaller / larger: background zoom, logo size
//   A (or Start)   keeps it                               B      puts back
//
// The keys are written once, when it is kept, as at the end of a mouse drag; a
// click or a key ends it and keeps it too.

using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

namespace RaintileOptions
{
    public partial class OptionsApp
    {
        // the parts of the preview, in the order LB / RB go through them
        const int PlaceBg = 0, PlaceLogo = 1, PlaceInfo = 2;
        static readonly string[] PlaceNames = { "Background", "Logo", "Play time" };

        int placePart = -1;                       // the part being moved, -1: not placing
        readonly bool[] placeMoved = new bool[3];
        double[] placeStart;                      // to put back: framing, logo, play time
        double placeZoom, placeScale;             // zoom and logo size, not rounded (slow triggers add up)
        Rectangle placeMark;
        TextBlock placeHint;

        // Elements the pad stops on and presses with A, besides the controls
        static readonly Dictionary<FrameworkElement, Action> padAreas = new Dictionary<FrameworkElement, Action>();

        void AddPadArea(FrameworkElement fe, Action action)
        {
            fe.Focusable = true;
            fe.FocusVisualStyle = null;
            KeyboardNavigation.SetIsTabStop(fe, false);   // Tab goes on as before
            padAreas[fe] = action;
        }

        Rectangle NewPlaceMark()
        {
            placeMark = new Rectangle
            {
                Stroke = ResBrush("AccentBrush"), StrokeThickness = 2, StrokeDashArray = new DoubleCollection { 3, 2 },
                IsHitTestVisible = false, Visibility = Visibility.Collapsed,
            };
            return placeMark;
        }

        TextBlock NewPlaceHint()
        {
            placeHint = NewHelp("", ResBrush("AccentBrush"));
            placeHint.Margin = T(0, Gap.Control, 0, 0);
            placeHint.Visibility = Visibility.Collapsed;
            return placeHint;
        }

        bool PlaceHas(int part)
        {
            if (part == PlaceBg) return bgFrame.Bitmap != null && !placeBack;   // (the backdrop is not framed)
            if (part == PlaceLogo) return previewLogo.Source != null && previewLogo.Visibility == Visibility.Visible;
            return previewInfo.Visibility == Visibility.Visible;
        }

        // A on the preview: the first part the tile has
        void StartPlace()
        {
            if (GetPlaceTarget() == null) return;
            int part = -1;
            for (int p = 0; p < 3 && part < 0; p++) if (PlaceHas(p)) part = p;
            if (part < 0) return;
            if (bgFrame.Bitmap != null) LimitFocus();
            LimitLogoPos();
            placeStart = new[] { bgFrame.FX, bgFrame.FY, bgFrame.Zoom, logoPlace.X, logoPlace.Y, logoPlace.Scale, infoPlace.X, infoPlace.Y };
            for (int p = 0; p < 3; p++) placeMoved[p] = false;
            placeZoom = bgFrame.Zoom;
            placeScale = logoPlace.Scale;
            placePart = part;
            HideRing();
            ShowPlacePart();
        }

        // Leaves placing: keep writes what moved, otherwise everything is put back
        void EndPlace(bool keep)
        {
            if (placePart < 0) return;
            placePart = -1;
            placeMark.Visibility = Visibility.Collapsed;
            placeHint.Visibility = Visibility.Collapsed;
            if (keep)
            {
                if (placeMoved[PlaceBg]) SaveFraming();
                if (placeMoved[PlaceLogo]) SaveLogoPlace();
                if (placeMoved[PlaceInfo]) SaveInfoPlace();
                return;
            }
            var s = placeStart;
            bgFrame.FX = s[0]; bgFrame.FY = s[1]; bgFrame.Zoom = s[2];
            logoPlace.X = s[3]; logoPlace.Y = s[4]; logoPlace.Scale = s[5];
            infoPlace.X = s[6]; infoPlace.Y = s[7];
            UpdateFraming();
            UpdateLogoPlace();
            UpdateInfoPlace();
        }

        // The outline and the line under the preview for the part being moved
        void ShowPlacePart()
        {
            string size = placePart == PlaceBg ? "   LT / RT zoom" : placePart == PlaceLogo ? "   LT / RT size" : "";
            placeHint.Text = PlaceNames[placePart] + ":   left stick or D-pad move" + size + "   LB / RB next part   A keep   B put back";
            placeHint.Visibility = Visibility.Visible;
            UpdatePlaceMark();
        }

        void UpdatePlaceMark()
        {
            Rect r;
            if (placePart == PlaceBg) r = new Rect(1, 1, Math.Max(0.0, preview.Width - 2), Math.Max(0.0, preview.Height - 2));
            else if (placePart == PlaceLogo)
            {
                var l = GetLogoRect();
                r = new Rect(l.CX - l.VW / 2, l.CY - l.VH / 2, l.VW, l.VH);
            }
            else r = GetInfoRect();
            placeMark.Width = r.Width;
            placeMark.Height = r.Height;
            Canvas.SetLeft(placeMark, r.X);
            Canvas.SetTop(placeMark, r.Y);
            placeMark.Visibility = Visibility.Visible;
        }

        // Moves the part by dx, dy preview pixels, from where it is now (as a drag:
        // the background follows the stick, so its focus goes the other way)
        void PlaceNudge(double dx, double dy)
        {
            if (placePart == PlaceBg)
            {
                var v = GetFrameWindow();
                bgFrame.FX -= dx / (v.S * v.IW);
                bgFrame.FY -= dy / (v.S * v.IH);
                LimitFocus();
                UpdateFraming();
            }
            else if (placePart == PlaceLogo)
            {
                logoPlace.X += dx / preview.Width;
                logoPlace.Y += dy / preview.Height;
                LimitLogoPos();
                UpdateLogoPlace();
            }
            else
            {
                var r = GetInfoRect();
                MoveInfo(r.X + dx, r.Y + dy, false);
                UpdateInfoPlace();
            }
            placeMoved[placePart] = true;
            UpdatePlaceMark();
        }

        // Zoom of the background or size of the logo, times 'factor'
        void PlaceResize(double factor)
        {
            if (placePart == PlaceBg)
            {
                placeZoom = Math.Min(4.0, Math.Max(1.0, placeZoom * factor));
                SetFrameZoom(placeZoom, null, false);
            }
            else if (placePart == PlaceLogo)
            {
                placeScale = Math.Min(3.0, Math.Max(0.25, placeScale * factor));
                SetLogoScale(placeScale, false);
            }
            else return;
            placeMoved[placePart] = true;
            UpdatePlaceMark();
        }

        // One read of the pad while placing; dt: seconds since the last read
        void PadPlaceInput(int fire, bool start, double dt)
        {
            // the tile lost the part (another image, the page changed): done
            if (!PlaceHas(placePart) || !preview.IsVisible) { EndPlace(true); return; }
            if ((fire & PadA) != 0 || start) { EndPlace(true); return; }
            if ((fire & PadB) != 0) { EndPlace(false); return; }
            if ((fire & (PadLB | PadRB)) != 0)
            {
                int step = (fire & PadRB) != 0 ? 1 : 2;
                int p = placePart;
                do p = (p + step) % 3; while (!PlaceHas(p));
                placePart = p;
                // the other part's zoom or size may have changed meanwhile
                placeZoom = bgFrame.Zoom;
                placeScale = logoPlace.Scale;
                ShowPlacePart();
                return;
            }
            if (padLX != 0 || padLY != 0)
            {
                // full tilt: across the preview in about a second and a half
                double speed = preview.Width / 1.5 * dt;
                PlaceNudge(padLX * speed, -padLY * speed);
            }
            else
            {
                int d = FirstDir(fire);
                if (d != 0) PlaceNudge(d == PadLeft ? -1 : d == PadRight ? 1 : 0, d == PadUp ? -1 : d == PadDown ? 1 : 0);
            }
            // triggers: twice / half as large per second, at full press
            double grow = padRT - padLT;
            if (grow != 0) PlaceResize(Math.Pow(2, grow * dt));
        }
    }
}
