# Raintile: crea le miniature di sfondi e loghi (lanciato in background dalla skin).
#
# Ogni riga del file di lavoro: sorgente|destinazione|larghezza|altezza|modo
#   cover   = riempie esattamente w x h ritagliando al centro (sfondi)
#   contain = sta dentro w x h mantenendo le proporzioni (loghi, PNG trasparenti)
#   overscanNNN = copre w x h e lo supera del NNN% (sfondi che scivolano)
# Le miniature gia' esistenti vengono saltate; quelle non piu' elencate vengono
# cancellate.

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

foreach ($line in Get-Content -LiteralPath $JobFile -Encoding UTF8) {
    if (-not $line.Trim()) { continue }
    $src, $dst, $w, $h, $mode = $line.Split('|')
    $w = [int]$w; $h = [int]$h
    $wanted[$dst.ToLowerInvariant()] = $true
    if ((Test-Path -LiteralPath $dst) -or $w -le 0 -or $h -le 0) { continue }

    $img = $null; $bmp = $null; $g = $null
    try {
        $img = [System.Drawing.Image]::FromFile($src)
        $iw = $img.Width; $ih = $img.Height

        if ($mode -eq 'cover') {
            $scale = [Math]::Max($w / $iw, $h / $ih)
            $sw = $w / $scale; $sh = $h / $scale
            $srcRect = New-Object System.Drawing.RectangleF ((($iw - $sw) / 2), (($ih - $sh) / 2), $sw, $sh)
            $tw = $w; $th = $h
        } elseif ($mode -like 'overscan*') {
            # copre w x h e lo supera della percentuale indicata (es. overscan115)
            $scale = [Math]::Max($w / $iw, $h / $ih) * ([int]$mode.Substring(8) / 100.0)
            $srcRect = New-Object System.Drawing.RectangleF (0, 0, $iw, $ih)
            $tw = [Math]::Max(1, [int][Math]::Round($iw * $scale))
            $th = [Math]::Max(1, [int][Math]::Round($ih * $scale))
        } else {
            $scale = [Math]::Min($w / $iw, $h / $ih)
            $srcRect = New-Object System.Drawing.RectangleF (0, 0, $iw, $ih)
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
        # Scrive su un file temporaneo e rinomina: la skin non vede mai file a meta'
        $tmp = "$dst.tmp"
        if ($dst.ToLowerInvariant().EndsWith('.png')) {
            $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        } else {
            $bmp.Save($tmp, $jpegCodec, $jpegParams)
        }
        Move-Item -LiteralPath $tmp -Destination $dst -Force
    } catch {
        Write-Output "Raintile: miniatura non creata per ${src}: $($_.Exception.Message)"
    } finally {
        if ($g) { $g.Dispose() }
        if ($bmp) { $bmp.Dispose() }
        if ($img) { $img.Dispose() }
    }
}

# Rimuove le miniature non piu' usate (immagini cambiate, tile tolte, nuova risoluzione)
if (Test-Path -LiteralPath $thumbRoot) {
    Get-ChildItem -LiteralPath $thumbRoot -Recurse -File |
        Where-Object { -not $wanted.ContainsKey($_.FullName.ToLowerInvariant()) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
