# Raintile: creates background and logo thumbnails (started in the background
# by the skin).
#
# Each line of the job file: source|destination|width|height|mode[|x,y,w,h]
#   cover       = fills exactly w x h, cropping at the centre (backgrounds)
#   contain     = fits inside w x h keeping the proportions (logos, transparent PNG)
#   overscanNNN = covers w x h and exceeds it by NNN% (sliding backgrounds)
#   color       = tile colour taken from a logo (AutoTileColor): the
#                 destination is the size of the logo file, the result goes
#                 to Generated\Colors.txt
# x,y,w,h (optional): part of the source to use instead of the whole image
# (framed backgrounds, BgFocus/BgZoom); the modes treat it as the image.
# Thumbnails that already exist are skipped; those no longer listed are
# deleted.

param([Parameter(Mandatory = $true)][string]$JobFile)

$ErrorActionPreference = 'Stop'
(Get-Process -Id $PID).PriorityClass = 'BelowNormal'
Add-Type -AssemblyName System.Drawing

$thumbRoot = Join-Path (Split-Path -Parent $JobFile) 'Thumbs'
$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq 'image/jpeg' }
$jpegParams = New-Object System.Drawing.Imaging.EncoderParameters 1
$jpegParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter (
    [System.Drawing.Imaging.Encoder]::Quality, [long]90)

$wanted = @{}

# --- Tile colour from a logo ---------------------------------------------------
# The logo is reduced to 32x32 and its opaque, coloured pixels are grouped by
# hue (white, grey and black ones do not count: many logos are white). The
# strongest hue becomes a dark, not too saturated colour that the logo and the
# label stay readable on. No coloured pixels: empty result (default colour).
function Get-LogoColor([string]$path) {
    $img = $null; $bmp = $null; $g = $null
    try {
        $img = [System.Drawing.Image]::FromFile($path)
        $bmp = New-Object System.Drawing.Bitmap (32, 32, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
        $g.DrawImage($img, 0, 0, 32, 32)
        $weight = New-Object double[] 12
        $sumR = New-Object double[] 12; $sumG = New-Object double[] 12; $sumB = New-Object double[] 12
        for ($y = 0; $y -lt 32; $y++) {
            for ($x = 0; $x -lt 32; $x++) {
                $c = $bmp.GetPixel($x, $y)
                if ($c.A -lt 128) { continue }
                $sat = $c.GetSaturation(); $bri = $c.GetBrightness()
                if ($sat -lt 0.2 -or $bri -lt 0.1 -or $bri -gt 0.95) { continue }
                $bucket = [int][Math]::Floor($c.GetHue() / 30) % 12
                $wt = $sat * ($c.A / 255.0)
                $weight[$bucket] += $wt
                $sumR[$bucket] += $c.R * $wt; $sumG[$bucket] += $c.G * $wt; $sumB[$bucket] += $c.B * $wt
            }
        }
        $best = 0
        for ($i = 1; $i -lt 12; $i++) { if ($weight[$i] -gt $weight[$best]) { $best = $i } }
        # fewer than ~3% of the pixels coloured: not enough to go by
        if ($weight[$best] -lt 15) { return '' }
        $avg = [System.Drawing.Color]::FromArgb(255,
            [int]($sumR[$best] / $weight[$best]), [int]($sumG[$best] / $weight[$best]),
            [int]($sumB[$best] / $weight[$best]))
        # back from HSL with a fixed darkness
        $hue = $avg.GetHue() / 360.0
        $sat = [Math]::Min(0.6, $avg.GetSaturation())
        $lum = 0.28
        $q = $lum * (1 + $sat); $p = 2 * $lum - $q
        $rgb = foreach ($t in @(($hue + 1 / 3), $hue, ($hue - 1 / 3))) {
            if ($t -lt 0) { $t += 1 }; if ($t -gt 1) { $t -= 1 }
            if ($t -lt 1 / 6) { $v = $p + ($q - $p) * 6 * $t }
            elseif ($t -lt 1 / 2) { $v = $q }
            elseif ($t -lt 2 / 3) { $v = $p + ($q - $p) * (2 / 3 - $t) * 6 }
            else { $v = $p }
            [int][Math]::Round($v * 255)
        }
        return "$($rgb[0]),$($rgb[1]),$($rgb[2]),255"
    } catch {
        # not Write-Output: it would become part of the returned value
        [Console]::Out.WriteLine("Raintile: tile colour not computed for ${path}: $($_.Exception.Message)")
        return ''
    } finally {
        if ($g) { $g.Dispose() }
        if ($bmp) { $bmp.Dispose() }
        if ($img) { $img.Dispose() }
    }
}

# Colours already computed: "size|R,G,B,A|path" -> kept if still wanted
$colorFile = Join-Path (Split-Path -Parent $JobFile) 'Colors.txt'
$oldColors = @{}
if (Test-Path -LiteralPath $colorFile) {
    foreach ($line in Get-Content -LiteralPath $colorFile -Encoding UTF8) {
        $parts = $line.Split('|', 3)
        if ($parts.Count -eq 3) { $oldColors[($parts[0] + '|' + $parts[2]).ToLowerInvariant()] = $parts[1] }
    }
}
$colors = New-Object System.Collections.Generic.List[string]

foreach ($line in Get-Content -LiteralPath $JobFile -Encoding UTF8) {
    if (-not $line.Trim()) { continue }
    $src, $dst, $w, $h, $mode, $rect = $line.Split('|')
    if ($mode -eq 'color') {
        $key = "$dst|$src".ToLowerInvariant()
        $color = if ($oldColors.ContainsKey($key)) { $oldColors[$key] } else { Get-LogoColor $src }
        $oldColors[$key] = $color # the same logo in two tiles: computed once
        $colors.Add("$dst|$color|$src")
        continue
    }
    $w = [int]$w; $h = [int]$h
    $wanted[$dst.ToLowerInvariant()] = $true
    if ((Test-Path -LiteralPath $dst) -or $w -le 0 -or $h -le 0) { continue }

    $img = $null; $bmp = $null; $g = $null
    try {
        $img = [System.Drawing.Image]::FromFile($src)
        $ix = 0; $iy = 0; $iw = $img.Width; $ih = $img.Height
        # framed part of the image, kept inside it
        if ($rect -match '^(\d+),(\d+),(\d+),(\d+)$') {
            $rx = [Math]::Min([int]$Matches[1], $iw - 1); $ry = [Math]::Min([int]$Matches[2], $ih - 1)
            $ix = $rx; $iy = $ry
            $iw = [Math]::Max(1, [Math]::Min([int]$Matches[3], $iw - $rx))
            $ih = [Math]::Max(1, [Math]::Min([int]$Matches[4], $ih - $ry))
        }

        if ($mode -eq 'cover') {
            $scale = [Math]::Max($w / $iw, $h / $ih)
            $sw = $w / $scale; $sh = $h / $scale
            $srcRect = New-Object System.Drawing.RectangleF (($ix + ($iw - $sw) / 2), ($iy + ($ih - $sh) / 2), $sw, $sh)
            $tw = $w; $th = $h
        } elseif ($mode -like 'overscan*') {
            # covers w x h and exceeds it by the given percentage (e.g. overscan115)
            $scale = [Math]::Max($w / $iw, $h / $ih) * ([int]$mode.Substring(8) / 100.0)
            $srcRect = New-Object System.Drawing.RectangleF ($ix, $iy, $iw, $ih)
            $tw = [Math]::Max(1, [int][Math]::Round($iw * $scale))
            $th = [Math]::Max(1, [int][Math]::Round($ih * $scale))
        } else {
            $scale = [Math]::Min($w / $iw, $h / $ih)
            $srcRect = New-Object System.Drawing.RectangleF ($ix, $iy, $iw, $ih)
            $tw = [Math]::Max(1, [int][Math]::Round($iw * $scale))
            $th = [Math]::Max(1, [int][Math]::Round($ih * $scale))
        }

        $bmp = New-Object System.Drawing.Bitmap ($tw, $th, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $destRect = New-Object System.Drawing.RectangleF (0, 0, $tw, $th)
        $g.DrawImage($img, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)

        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
        # Write to a temporary file and rename: the skin never sees half-written files
        $tmp = "$dst.tmp"
        if ($dst.ToLowerInvariant().EndsWith('.png')) {
            $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        } else {
            $bmp.Save($tmp, $jpegCodec, $jpegParams)
        }
        Move-Item -LiteralPath $tmp -Destination $dst -Force
    } catch {
        Write-Output "Raintile: thumbnail not created for ${src}: $($_.Exception.Message)"
    } finally {
        if ($g) { $g.Dispose() }
        if ($bmp) { $bmp.Dispose() }
        if ($img) { $img.Dispose() }
    }
}

# Only the colours of logos still in use are kept
if ($colors.Count -gt 0 -or (Test-Path -LiteralPath $colorFile)) {
    $tmp = "$colorFile.tmp"
    [System.IO.File]::WriteAllLines($tmp, [string[]]@($colors | Select-Object -Unique))
    Move-Item -LiteralPath $tmp -Destination $colorFile -Force
}

# Remove thumbnails no longer used (changed images, removed tiles, new resolution)
if (Test-Path -LiteralPath $thumbRoot) {
    Get-ChildItem -LiteralPath $thumbRoot -Recurse -File |
        Where-Object { -not $wanted.ContainsKey($_.FullName.ToLowerInvariant()) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
