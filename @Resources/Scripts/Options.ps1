# Raintile: finestra delle opzioni (impostazioni e categorie).
#
# Avviata dal pulsante con l'ingranaggio o dal menu del tasto destro.
#  - Impostazioni: tutte le voci di Settings.inc, raggruppate come nel file,
#    con la descrizione presa dai commenti. Salvando cambia solo il valore
#    nella riga: commenti e ordine restano com'erano.
#  - Categorie: crea, elimina (nel Cestino) e riordina le categorie; aggiunge,
#    elimina, riordina e modifica le tile. Le immagini scelte vengono copiate
#    in Images\<categoria>\background|logo\<NomeTile>.<ext>. I giochi importati
#    (sotto il segnaposto di Import.ps1) si vedono ma non si modificano.
# "Salva" scrive i file e aggiorna la skin.
#
# Con -NoGui carica solo le funzioni (per i test).

param(
    [Parameter(Mandatory = $true)][string]$Resources,
    [string]$Config = 'Raintile',
    [switch]$NoGui
)

$ErrorActionPreference = 'Stop'
$IMPORT_MARKER = '; ===== IMPORTATI AUTOMATICAMENTE ====='
$utf8 = New-Object System.Text.UTF8Encoding $false
$settingsFile = Join-Path $Resources 'Settings.inc'
$categoriesDir = Join-Path $Resources 'Categories'
$imagesRoot = Join-Path $Resources 'Images'

# Voci con una scelta fissa (menu a tendina)
$choices = @{
    'ScrollDir' = @('V', 'H')
    'MenuMode'  = @('IconText', 'Icon', 'Text')
    'BgStyle'   = @('Crop', 'Pan', 'Parallax', 'Zoom')
    'ShowZPos'  = @('1', '0', '-1', '-2')
}
# Interruttori 0/1 (casella di spunta)
$switches = 'ShowLabels', 'InfiniteScroll', 'KeyboardNav', 'CloseOnLaunch', 'StartHidden', 'LaunchAnimation',
'AnimOpen', 'AnimCategory', 'AnimHover', 'AnimScroll', 'AnimLogoZoom', 'LogoGreyscale', 'Thumbnails',
'TileHover', 'Gamepad', 'ImportOnStart', 'DebugLog'

# --- Settings.inc --------------------------------------------------------------

# Restituisce le voci: Section, Key, Value, Description, Line (indice di riga)
function Read-Settings([string]$path) {
    $lines = [IO.File]::ReadAllLines($path)
    $items = New-Object System.Collections.ArrayList
    $section = 'Generale'
    $comment = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim()
        if ($t -match '^;\s*---\s*(.+?)\s*-*$') {
            $section = $Matches[1]; $comment.Clear(); continue
        }
        if ($t.StartsWith(';')) { [void]$comment.Add($t.TrimStart(';').Trim()); continue }
        if ($t -eq '' -or $t.StartsWith('[')) { $comment.Clear(); continue }
        if ($t -match '^([^=]+?)\s*=(.*)$') {
            # i valori calcolati non si modificano
            if ($section -notmatch '^Calcolati') {
                [void]$items.Add([pscustomobject]@{
                        Section = $section; Key = $Matches[1].Trim(); Value = $Matches[2].Trim()
                        Description = ($comment -join ' '); Line = $i
                    })
            }
            $comment.Clear()
        }
    }
    return , $items
}

# Scrive i nuovi valori (hashtable Key -> Value) cambiando solo quelle righe
function Write-Settings([string]$path, [hashtable]$values) {
    $lines = [IO.File]::ReadAllLines($path)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(\s*)([^;=\[][^=]*?)(\s*=)(.*)$') {
            $key = $Matches[2].Trim()
            if ($values.ContainsKey($key)) { $lines[$i] = $Matches[1] + $Matches[2] + $Matches[3] + $values[$key] }
        }
    }
    [IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), $utf8)
}

function Get-ControlKind($item) {
    if ($choices.ContainsKey($item.Key)) { return 'choice' }
    if ($item.Value -match '^\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}(\s*,\s*\d{1,3})?$') { return 'color' }
    if ($switches -contains $item.Key) { return 'bool' }
    return 'text'
}

# --- File di categoria -------------------------------------------------------------

# Modello: Header (testo prima della prima sezione), Sections (Name, Comments,
# Keys = lista ordinata di [Key, Value]), Imported (testo dal segnaposto in poi)
function Read-Category([string]$path) {
    $text = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } else { '' }
    $imported = ''
    $i = $text.IndexOf($IMPORT_MARKER)
    if ($i -ge 0) { $imported = $text.Substring($i); $text = $text.Substring(0, $i) }

    $model = [pscustomobject]@{ Header = ''; Sections = (New-Object System.Collections.ArrayList); Imported = $imported }
    $header = New-Object System.Collections.ArrayList
    $pending = New-Object System.Collections.ArrayList
    $current = $null
    foreach ($line in ($text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match '^\[(.+)\]$') {
            $current = [pscustomobject]@{ Name = $Matches[1].Trim(); Comments = @($pending); Keys = (New-Object System.Collections.ArrayList) }
            [void]$model.Sections.Add($current)
            $pending.Clear()
        } elseif ($t.StartsWith(';') -or $t -eq '') {
            if ($current) { if ($t) { [void]$pending.Add($line) } } else { [void]$header.Add($line) }
        } elseif ($current -and $t -match '^([^=]+?)\s*=(.*)$') {
            [void]$current.Keys.Add(@($Matches[1].Trim(), $Matches[2].Trim()))
        }
    }
    $model.Header = (($header -join "`r`n").TrimEnd())
    return $model
}

function Get-Key($section, [string]$key) {
    foreach ($kv in $section.Keys) { if ($kv[0] -ieq $key) { return $kv[1] } }
    return ''
}

function Set-Key($section, [string]$key, [string]$value) {
    for ($i = 0; $i -lt $section.Keys.Count; $i++) {
        if ($section.Keys[$i][0] -ieq $key) {
            if ($value -eq '') { $section.Keys.RemoveAt($i) } else { $section.Keys[$i] = @($section.Keys[$i][0], $value) }
            return
        }
    }
    if ($value -ne '') { [void]$section.Keys.Add(@($key, $value)) }
}

function Write-Category([string]$path, $model) {
    $sb = New-Object System.Text.StringBuilder
    if ($model.Header) { [void]$sb.Append($model.Header + "`r`n") }
    foreach ($s in $model.Sections) {
        [void]$sb.Append("`r`n")
        foreach ($c in $s.Comments) { [void]$sb.Append($c + "`r`n") }
        [void]$sb.Append('[' + $s.Name + "]`r`n")
        foreach ($kv in $s.Keys) { [void]$sb.Append($kv[0] + '=' + $kv[1] + "`r`n") }
    }
    if ($model.Imported) { [void]$sb.Append("`r`n" + $model.Imported.TrimEnd() + "`r`n") }
    [IO.File]::WriteAllText($path, $sb.ToString(), $utf8)
}

function Get-CategorySection($model) {
    foreach ($s in $model.Sections) { if ($s.Name -ieq 'Category') { return $s } }
    $s = [pscustomobject]@{ Name = 'Category'; Comments = @(); Keys = (New-Object System.Collections.ArrayList) }
    $model.Sections.Insert(0, $s)
    return $s
}

function Get-Tiles($model) {
    return @($model.Sections | Where-Object { $_.Name -ine 'Category' })
}

# Nomi delle tile importate (sola lettura)
function Get-ImportedNames($model) {
    return @([regex]::Matches($model.Imported, '(?m)^\[(.+)\]\s*$') | ForEach-Object { $_.Groups[1].Value })
}

# Copia un'immagine scelta nella cartella di default della tile
function Copy-TileImage([string]$category, [string]$kind, [string]$tile, [string]$source) {
    $dir = Join-Path $imagesRoot "$category\$kind"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    # toglie eventuali immagini precedenti con altra estensione
    Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.BaseName -ieq $tile } | Remove-Item -Force
    $dest = Join-Path $dir ($tile + [IO.Path]::GetExtension($source).ToLowerInvariant())
    Copy-Item -LiteralPath $source -Destination $dest -Force
    return $dest
}

function Get-CategoryFiles {
    return @(Get-ChildItem -LiteralPath $categoriesDir -Filter '*.ini' -File | Sort-Object Name)
}

if ($NoGui) { return }

# ==============================================================================
#  Interfaccia
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic

# Un errore durante la costruzione della finestra non deve passare inosservato
# (lo script gira senza console): lo si mostra e lo si scrive in un log.
trap {
    $msg = "$($_.Exception.Message)`r`n`r`n$($_.InvocationInfo.PositionMessage)"
    try { [IO.File]::WriteAllText((Join-Path $Resources 'Generated\Options.log'), $msg, $utf8) } catch { }
    [void][System.Windows.Forms.MessageBox]::Show("Errore nella finestra delle opzioni:`r`n`r`n$msg", 'Raintile')
    exit 1
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# Avviato senza console (RunCommand, finestra nascosta): Windows potrebbe
# applicare il "nascosto" anche alla prima finestra mostrata, quindi la si
# rende visibile e in primo piano esplicitamente.
Add-Type -Namespace RaintileOptions -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
'@

function Pad([int]$left, [int]$top, [int]$right, [int]$bottom) {
    return New-Object System.Windows.Forms.Padding($left, $top, $right, $bottom)
}

$dirty = $false
function Set-Dirty { $script:dirty = $true; $form.Text = 'Raintile - Opzioni *' }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Raintile - Opzioni'
$form.Size = New-Object System.Drawing.Size(1100, 760)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.TopMost = $true

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)

$bottom = New-Object System.Windows.Forms.FlowLayoutPanel
$bottom.Dock = 'Bottom'; $bottom.Height = 44; $bottom.FlowDirection = 'RightToLeft'; $bottom.Padding = (Pad 8 6 8 6)
$form.Controls.Add($bottom)
$btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = 'Chiudi'; $btnClose.Width = 110
$btnSave = New-Object System.Windows.Forms.Button; $btnSave.Text = 'Salva e aggiorna'; $btnSave.Width = 140
$btnImport = New-Object System.Windows.Forms.Button; $btnImport.Text = 'Importa giochi'; $btnImport.Width = 130
$bottom.Controls.AddRange(@($btnClose, $btnSave, $btnImport))
$tip = New-Object System.Windows.Forms.ToolTip

# --- Scheda Impostazioni ---------------------------------------------------------

$settings = Read-Settings $settingsFile
$settingControls = @{}

$pageSettings = New-Object System.Windows.Forms.TabPage
$pageSettings.Text = 'Impostazioni'
$tabs.TabPages.Add($pageSettings)
$panel = New-Object System.Windows.Forms.TableLayoutPanel
$panel.Dock = 'Fill'; $panel.AutoScroll = $true; $panel.ColumnCount = 3; $panel.Padding = (Pad 12 8 24 8)
[void]$panel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 210)))
[void]$panel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 300)))
[void]$panel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
$pageSettings.Controls.Add($panel)

$lastSection = $null
foreach ($item in $settings) {
    if ($item.Section -ne $lastSection) {
        $h = New-Object System.Windows.Forms.Label
        $h.Text = $item.Section; $h.AutoSize = $true; $h.Margin = (Pad 0 14 0 4)
        $h.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
        $panel.Controls.Add($h); $panel.SetColumnSpan($h, 3)
        $lastSection = $item.Section
    }
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $item.Key; $label.AutoSize = $true; $label.Margin = (Pad 0 6 0 0)
    $panel.Controls.Add($label)

    switch (Get-ControlKind $item) {
        'bool' {
            $c = New-Object System.Windows.Forms.CheckBox
            $c.Checked = $item.Value -eq '1'
            $c.Add_CheckedChanged({ Set-Dirty })
        }
        'choice' {
            $c = New-Object System.Windows.Forms.ComboBox
            $c.DropDownStyle = 'DropDownList'; $c.Width = 280
            [void]$c.Items.AddRange([object[]]$choices[$item.Key])
            $sel = [array]::FindIndex([string[]]$choices[$item.Key], [Predicate[string]] { param($x) $x -ieq $item.Value })
            $c.SelectedIndex = [Math]::Max(0, $sel)
            $c.Add_SelectedIndexChanged({ Set-Dirty })
        }
        'color' {
            $c = New-Object System.Windows.Forms.Button
            $c.Width = 280; $c.Text = $item.Value; $c.Tag = $item.Value; $c.TextAlign = 'MiddleRight'
            $p = $item.Value -split '\s*,\s*' | ForEach-Object { [int]$_ }
            $c.BackColor = [System.Drawing.Color]::FromArgb(255, $p[0], $p[1], $p[2])
            $c.ForeColor = if (($p[0] + $p[1] + $p[2]) -gt 380) { [System.Drawing.Color]::Black } else { [System.Drawing.Color]::White }
            $c.Add_Click({
                    $btn = $this
                    $v = $btn.Tag -split '\s*,\s*' | ForEach-Object { [int]$_ }
                    $dlg = New-Object System.Windows.Forms.ColorDialog
                    $dlg.FullOpen = $true
                    $dlg.Color = [System.Drawing.Color]::FromArgb(255, $v[0], $v[1], $v[2])
                    if ($dlg.ShowDialog($form) -eq 'OK') {
                        $alpha = if ($v.Count -ge 4) { ",$($v[3])" } else { '' }
                        $btn.Tag = "$($dlg.Color.R),$($dlg.Color.G),$($dlg.Color.B)$alpha"
                        $btn.Text = $btn.Tag
                        $btn.BackColor = [System.Drawing.Color]::FromArgb(255, $dlg.Color.R, $dlg.Color.G, $dlg.Color.B)
                        $btn.ForeColor = if (($dlg.Color.R + $dlg.Color.G + $dlg.Color.B) -gt 380) { [System.Drawing.Color]::Black } else { [System.Drawing.Color]::White }
                        Set-Dirty
                    }
                })
        }
        default {
            $c = New-Object System.Windows.Forms.TextBox
            $c.Width = 280; $c.Text = $item.Value
            $c.Add_TextChanged({ Set-Dirty })
        }
    }
    $panel.Controls.Add($c)
    $settingControls[$item.Key] = $c

    $d = New-Object System.Windows.Forms.Label
    $d.Text = $item.Description; $d.AutoSize = $true; $d.MaximumSize = (New-Object System.Drawing.Size(520, 0)); $d.Margin = (Pad 8 6 0 6)
    $d.ForeColor = [System.Drawing.Color]::DimGray
    $panel.Controls.Add($d)
}

function Get-SettingValues {
    $values = @{}
    foreach ($item in $settings) {
        $c = $settingControls[$item.Key]
        $v = switch ($c.GetType().Name) {
            'CheckBox' { if ($c.Checked) { '1' } else { '0' } }
            'ComboBox' { [string]$c.SelectedItem }
            'Button' { [string]$c.Tag }
            default { $c.Text.Trim() }
        }
        if ($v -ne $item.Value) { $values[$item.Key] = $v }
    }
    return $values
}

# --- Scheda Categorie --------------------------------------------------------------

$models = @{}       # file -> modello (caricato quando serve)
$changedFiles = @{} # file modificati
function Get-Model([string]$file) {
    if (-not $models.ContainsKey($file)) { $models[$file] = Read-Category (Join-Path $categoriesDir $file) }
    return $models[$file]
}
function Set-Changed([string]$file) { $changedFiles[$file] = $true; Set-Dirty }

$pageCats = New-Object System.Windows.Forms.TabPage
$pageCats.Text = 'Categorie'
$tabs.TabPages.Add($pageCats)

$split = New-Object System.Windows.Forms.TableLayoutPanel
$split.Dock = 'Fill'; $split.ColumnCount = 3; $split.Padding = (Pad 8 8 8 8)
[void]$split.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 240)))
[void]$split.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 280)))
[void]$split.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
$pageCats.Controls.Add($split)

function New-Column([string]$title) {
    $col = New-Object System.Windows.Forms.TableLayoutPanel
    $col.Dock = 'Fill'; $col.RowCount = 3
    [void]$col.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    [void]$col.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
    [void]$col.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $title; $l.AutoSize = $true; $l.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $col.Controls.Add($l, 0, 0)
    return $col
}
function New-Button([string]$text, [int]$width = 70) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Width = $width
    return $b
}

# Colonna 1: categorie
$colCats = New-Column 'Categorie'
$listCats = New-Object System.Windows.Forms.ListBox
$listCats.Dock = 'Fill'; $listCats.IntegralHeight = $false; $listCats.DisplayMember = 'Text'
$colCats.Controls.Add($listCats, 0, 1)
$barCats = New-Object System.Windows.Forms.FlowLayoutPanel; $barCats.AutoSize = $true
$btnCatNew = New-Button 'Nuova'; $btnCatDel = New-Button 'Elimina'; $btnCatUp = New-Button 'Su' 45; $btnCatDown = New-Button 'Giu' 45
$barCats.Controls.AddRange(@($btnCatNew, $btnCatDel, $btnCatUp, $btnCatDown))
$colCats.Controls.Add($barCats, 0, 2)
$split.Controls.Add($colCats, 0, 0)

# Colonna 2: tile della categoria
$colTiles = New-Column 'Tile'
$listTiles = New-Object System.Windows.Forms.ListBox
$listTiles.Dock = 'Fill'; $listTiles.IntegralHeight = $false; $listTiles.DisplayMember = 'Text'
$colTiles.Controls.Add($listTiles, 0, 1)
$barTiles = New-Object System.Windows.Forms.FlowLayoutPanel; $barTiles.AutoSize = $true
$btnTileNew = New-Button 'Nuova'; $btnTileDel = New-Button 'Elimina'; $btnTileUp = New-Button 'Su' 45; $btnTileDown = New-Button 'Giu' 45
$barTiles.Controls.AddRange(@($btnTileNew, $btnTileDel, $btnTileUp, $btnTileDown))
$colTiles.Controls.Add($barTiles, 0, 2)
$split.Controls.Add($colTiles, 1, 0)

# Colonna 3: dettagli (categoria in alto, tile sotto)
$details = New-Object System.Windows.Forms.TableLayoutPanel
$details.Dock = 'Fill'; $details.ColumnCount = 3; $details.AutoScroll = $true; $details.Padding = (Pad 8 0 8 0)
[void]$details.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 110)))
[void]$details.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
[void]$details.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 90)))
$split.Controls.Add($details, 2, 0)

$fields = @{}
function Add-Header([string]$text) {
    $h = New-Object System.Windows.Forms.Label
    $h.Text = $text; $h.AutoSize = $true; $h.Margin = (Pad 0 10 0 4)
    $h.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $details.Controls.Add($h); $details.SetColumnSpan($h, 3)
}
function Add-Field([string]$id, [string]$label, [string]$help, [string]$button = '') {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $label; $l.AutoSize = $true; $l.Margin = (Pad 0 6 0 0)
    $details.Controls.Add($l)
    $t = New-Object System.Windows.Forms.TextBox
    $t.Dock = 'Fill'
    $details.Controls.Add($t)
    if ($help) { $tip.SetToolTip($t, $help); $tip.SetToolTip($l, $help) }
    if ($button) {
        $b = New-Button $button 85
        $details.Controls.Add($b)
        $fields["$id.button"] = $b
    } else {
        $details.Controls.Add((New-Object System.Windows.Forms.Label))
    }
    $fields[$id] = $t
}

Add-Header 'Categoria'
Add-Field 'cat.Name' 'Nome' 'Testo mostrato nel menu'
Add-Field 'cat.Icon' 'Icona' 'Icona nel menu (default: Images\<categoria>\icon.png)' 'Sfoglia...'
Add-Field 'cat.NX' 'Colonne (NX)' 'Tile visibili per riga (vuoto = Settings.inc)'
Add-Field 'cat.NY' 'Righe (NY)' 'Tile visibili per colonna (vuoto = Settings.inc)'
Add-Field 'cat.IconSize' 'Dim. logo' 'Lato del logo nelle tile (vuoto = Settings.inc)'
Add-Header 'Tile'
Add-Field 'tile.Name' 'Nome' 'Nome della tile: e'' anche il nome di default delle sue immagini'
Add-Field 'tile.Command' 'Comando' 'Programma, collegamento .lnk/.url, URL, cartella o bang di Rainmeter' 'Sfoglia...'
Add-Field 'tile.Label' 'Etichetta' 'Testo in basso a sinistra (vuoto = nessuno)'
Add-Field 'tile.Color' 'Colore' 'Colore di fondo senza sfondo (R,G,B,A)' 'Scegli...'
Add-Field 'tile.Background' 'Sfondo' 'Vuoto = Images\<categoria>\background\<Nome>.*' 'Sfoglia...'
Add-Field 'tile.Logo' 'Logo' 'Vuoto = Images\<categoria>\logo\<Nome>.*' 'Sfoglia...'
$note = New-Object System.Windows.Forms.Label
$note.AutoSize = $true; $note.MaximumSize = (New-Object System.Drawing.Size(520, 0)); $note.ForeColor = [System.Drawing.Color]::DimGray; $note.Margin = (Pad 0 10 0 0)
$details.Controls.Add($note); $details.SetColumnSpan($note, 3)

$loading = $false
function Get-CurrentFile { if ($listCats.SelectedIndex -ge 0) { return [string]$listCats.SelectedItem.File } return $null }
function Get-CurrentTile {
    $file = Get-CurrentFile
    if (-not $file -or $listTiles.SelectedIndex -lt 0) { return $null }
    $entry = $listTiles.SelectedItem
    if ($entry.Imported) { return $null }
    return $entry.Section
}

function Refresh-Cats([int]$select = 0) {
    $listCats.Items.Clear()
    $entries = foreach ($f in Get-CategoryFiles) {
        $m = Get-Model $f.Name
        $c = Get-CategorySection $m
        $order = 0; [void][int]::TryParse((Get-Key $c 'Order'), [ref]$order)
        if (-not $order) { $order = 9999 }
        $name = Get-Key $c 'Name'; if (-not $name) { $name = $f.BaseName }
        [pscustomobject]@{ File = $f.Name; Order = $order; Text = "$name   ($($f.Name))" }
    }
    foreach ($e in ($entries | Sort-Object Order, File)) {
        $e | Add-Member ScriptMethod ToString { $this.Text } -Force
        [void]$listCats.Items.Add($e)
    }
    if ($listCats.Items.Count) { $listCats.SelectedIndex = [Math]::Min($select, $listCats.Items.Count - 1) }
}

function Refresh-Tiles([int]$select = 0) {
    $listTiles.Items.Clear()
    $file = Get-CurrentFile
    if (-not $file) { return }
    $m = Get-Model $file
    foreach ($s in Get-Tiles $m) {
        $e = [pscustomobject]@{ Section = $s; Imported = $false; Text = $s.Name }
        $e | Add-Member ScriptMethod ToString { $this.Text } -Force
        [void]$listTiles.Items.Add($e)
    }
    foreach ($n in Get-ImportedNames $m) {
        $e = [pscustomobject]@{ Section = $null; Imported = $true; Text = "$n   (importato)" }
        $e | Add-Member ScriptMethod ToString { $this.Text } -Force
        [void]$listTiles.Items.Add($e)
    }
    if ($listTiles.Items.Count) { $listTiles.SelectedIndex = [Math]::Min($select, $listTiles.Items.Count - 1) }
    else { Show-Tile }
}

function Show-Category {
    $script:loading = $true
    $file = Get-CurrentFile
    foreach ($k in 'Name', 'Icon', 'NX', 'NY', 'IconSize') {
        $fields["cat.$k"].Enabled = [bool]$file
        $fields["cat.$k"].Text = if ($file) { Get-Key (Get-CategorySection (Get-Model $file)) $k } else { '' }
    }
    $script:loading = $false
    Refresh-Tiles
}

function Show-Tile {
    $script:loading = $true
    $s = Get-CurrentTile
    foreach ($k in 'Name', 'Command', 'Label', 'Color', 'Background', 'Logo') {
        $fields["tile.$k"].Enabled = [bool]$s
        if ($fields.ContainsKey("tile.$k.button")) { $fields["tile.$k.button"].Enabled = [bool]$s }
        $fields["tile.$k"].Text = if (-not $s) { '' } elseif ($k -eq 'Name') { $s.Name } else { Get-Key $s $k }
    }
    $entry = $listTiles.SelectedItem
    $note.Text = if ($entry -and $entry.Imported) {
        'Gioco importato: viene riscritto a ogni import e non si modifica da qui. Per personalizzarlo, aggiungi una tile con lo stesso nome: l''import non lo duplichera''.'
    } else { '' }
    $script:loading = $false
}

$listCats.Add_SelectedIndexChanged({ Show-Category })
$listTiles.Add_SelectedIndexChanged({ Show-Tile })

# Modifica dei campi della categoria
foreach ($k in 'Name', 'Icon', 'NX', 'NY', 'IconSize') {
    $fields["cat.$k"].Tag = $k
    $fields["cat.$k"].Add_TextChanged({
            if ($loading) { return }
            $file = Get-CurrentFile; if (-not $file) { return }
            Set-Key (Get-CategorySection (Get-Model $file)) $this.Tag $this.Text.Trim()
            Set-Changed $file
        })
}
# Modifica dei campi della tile
foreach ($k in 'Command', 'Label', 'Color', 'Background', 'Logo') {
    $fields["tile.$k"].Tag = $k
    $fields["tile.$k"].Add_TextChanged({
            if ($loading) { return }
            $s = Get-CurrentTile; if (-not $s) { return }
            Set-Key $s $this.Tag $this.Text.Trim()
            Set-Changed (Get-CurrentFile)
        })
}
# Rinomina della tile (alla fine della modifica, per controllare i doppioni)
$fields['tile.Name'].Add_Leave({
        $s = Get-CurrentTile; if (-not $s) { return }
        $new = ($this.Text -replace '[\[\]]', '').Trim()
        if (-not $new -or $new -eq $s.Name) { $this.Text = $s.Name; return }
        $m = Get-Model (Get-CurrentFile)
        if ($m.Sections | Where-Object { $_ -ne $s -and $_.Name -ieq $new }) {
            [void][System.Windows.Forms.MessageBox]::Show($form, "Esiste gia' una tile chiamata '$new'.", 'Raintile')
            $this.Text = $s.Name; return
        }
        $s.Name = $new
        Set-Changed (Get-CurrentFile)
        Refresh-Tiles $listTiles.SelectedIndex
    })

# Sfoglia...
function Select-File([string]$filter) {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = $filter
    if ($dlg.ShowDialog($form) -eq 'OK') { return $dlg.FileName }
    return $null
}
$imageFilter = 'Immagini|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.ico|Tutti i file|*.*'
$fields['cat.Icon.button'].Add_Click({
        $file = Get-CurrentFile; if (-not $file) { return }
        $src = Select-File $imageFilter; if (-not $src) { return }
        $base = [IO.Path]::GetFileNameWithoutExtension($file)
        $dir = Join-Path $imagesRoot $base
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.BaseName -ieq 'icon' } | Remove-Item -Force
        Copy-Item -LiteralPath $src -Destination (Join-Path $dir ('icon' + [IO.Path]::GetExtension($src).ToLowerInvariant())) -Force
        $fields['cat.Icon'].Text = ''   # vale l'icona di default appena copiata
        Set-Changed $file
    })
$fields['tile.Command.button'].Add_Click({
        $src = Select-File 'Programmi e collegamenti|*.exe;*.lnk;*.url;*.bat;*.cmd|Tutti i file|*.*'
        if ($src) { $fields['tile.Command'].Text = '"' + $src + '"' }
    })
$fields['tile.Color.button'].Add_Click({
        $dlg = New-Object System.Windows.Forms.ColorDialog
        $dlg.FullOpen = $true
        if ($dlg.ShowDialog($form) -eq 'OK') { $fields['tile.Color'].Text = "$($dlg.Color.R),$($dlg.Color.G),$($dlg.Color.B),255" }
    })
foreach ($kind in 'Background', 'Logo') {
    $fields["tile.$kind.button"].Tag = $kind
    $fields["tile.$kind.button"].Add_Click({
            $s = Get-CurrentTile; if (-not $s) { return }
            $src = Select-File $imageFilter; if (-not $src) { return }
            $base = [IO.Path]::GetFileNameWithoutExtension((Get-CurrentFile))
            [void](Copy-TileImage $base $this.Tag.ToLowerInvariant() $s.Name $src)
            $fields["tile.$($this.Tag)"].Text = ''   # vale l'immagine di default appena copiata
            Set-Changed (Get-CurrentFile)
        })
}

# Categorie: nuova, elimina, riordina
function Save-CategoryOrder {
    for ($i = 0; $i -lt $listCats.Items.Count; $i++) {
        $file = $listCats.Items[$i].File
        $c = Get-CategorySection (Get-Model $file)
        if ((Get-Key $c 'Order') -ne "$($i + 1)") { Set-Key $c 'Order' "$($i + 1)"; Set-Changed $file }
    }
}
$btnCatNew.Add_Click({
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('Nome della categoria (es. Emulatori):', 'Nuova categoria', '')
        $file = ($name -replace '[^A-Za-z0-9_-]', '')
        if (-not $file) { return }
        if (Test-Path -LiteralPath (Join-Path $categoriesDir "$file.ini")) {
            [void][System.Windows.Forms.MessageBox]::Show($form, "La categoria '$file' esiste gia'.", 'Raintile'); return
        }
        $m = [pscustomobject]@{ Header = '; Formato: vedi Games.ini'; Sections = (New-Object System.Collections.ArrayList); Imported = '' }
        $c = Get-CategorySection $m
        Set-Key $c 'Name' $name.Trim()
        Set-Key $c 'Order' "$($listCats.Items.Count + 1)"
        Write-Category (Join-Path $categoriesDir "$file.ini") $m
        foreach ($kind in 'background', 'logo') { New-Item -ItemType Directory -Force -Path (Join-Path $imagesRoot "$file\$kind") | Out-Null }
        $models["$file.ini"] = $m
        Set-Dirty
        Refresh-Cats $listCats.Items.Count
    })
$btnCatDel.Add_Click({
        $file = Get-CurrentFile; if (-not $file) { return }
        $r = [System.Windows.Forms.MessageBox]::Show($form, "Spostare la categoria $file nel Cestino? Le sue immagini restano in Images.", 'Raintile', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { return }
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile((Join-Path $categoriesDir $file), 'OnlyErrorDialogs', 'SendToRecycleBin')
        $models.Remove($file); $changedFiles.Remove($file)
        Set-Dirty
        Refresh-Cats ([Math]::Max(0, $listCats.SelectedIndex - 1))
    })
foreach ($pair in @(@($btnCatUp, -1), @($btnCatDown, 1))) {
    $pair[0].Tag = $pair[1]
    $pair[0].Add_Click({
            $i = $listCats.SelectedIndex; $j = $i + $this.Tag
            if ($i -lt 0 -or $j -lt 0 -or $j -ge $listCats.Items.Count) { return }
            $item = $listCats.Items[$i]; $listCats.Items.RemoveAt($i); $listCats.Items.Insert($j, $item)
            Save-CategoryOrder
            $listCats.SelectedIndex = $j
        })
}

# Tile: nuova, elimina, riordina (solo quelle scritte a mano)
$btnTileNew.Add_Click({
        $file = Get-CurrentFile; if (-not $file) { return }
        $m = Get-Model $file
        $name = ([Microsoft.VisualBasic.Interaction]::InputBox('Nome della tile (e'' anche il nome delle sue immagini):', 'Nuova tile', '') -replace '[\[\]]', '').Trim()
        if (-not $name) { return }
        if (($m.Sections | Where-Object { $_.Name -ieq $name }) -or ((Get-ImportedNames $m) -contains $name)) {
            [void][System.Windows.Forms.MessageBox]::Show($form, "Esiste gia' una tile chiamata '$name'.", 'Raintile'); return
        }
        $s = [pscustomobject]@{ Name = $name; Comments = @(); Keys = (New-Object System.Collections.ArrayList) }
        Set-Key $s 'Command' ''
        [void]$m.Sections.Add($s)
        Set-Changed $file
        Refresh-Tiles ((Get-Tiles $m).Count - 1)
        $fields['tile.Command'].Focus()
    })
$btnTileDel.Add_Click({
        $s = Get-CurrentTile; if (-not $s) { return }
        $r = [System.Windows.Forms.MessageBox]::Show($form, "Eliminare la tile '$($s.Name)'?", 'Raintile', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
        $file = Get-CurrentFile
        (Get-Model $file).Sections.Remove($s)
        Set-Changed $file
        Refresh-Tiles ([Math]::Max(0, $listTiles.SelectedIndex - 1))
    })
foreach ($pair in @(@($btnTileUp, -1), @($btnTileDown, 1))) {
    $pair[0].Tag = $pair[1]
    $pair[0].Add_Click({
            $s = Get-CurrentTile; if (-not $s) { return }
            $file = Get-CurrentFile
            $m = Get-Model $file
            $tiles = Get-Tiles $m
            $i = [array]::IndexOf($tiles, $s); $j = $i + $this.Tag
            if ($j -lt 0 -or $j -ge $tiles.Count) { return }
            $a = $m.Sections.IndexOf($s); $b = $m.Sections.IndexOf($tiles[$j])
            $m.Sections[$a] = $tiles[$j]; $m.Sections[$b] = $s
            Set-Changed $file
            Refresh-Tiles $j
        })
}

# --- Salva, importa, chiudi ----------------------------------------------------------

function Invoke-Rainmeter([string]$bang) {
    $exe = (Get-Process Rainmeter -ErrorAction SilentlyContinue | Select-Object -First 1).Path
    if (-not $exe) { $exe = Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe' }
    if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe -ArgumentList $bang }
}

function Save-All {
    $values = Get-SettingValues
    if ($values.Count) {
        Write-Settings $settingsFile $values
        foreach ($item in $settings) { if ($values.ContainsKey($item.Key)) { $item.Value = $values[$item.Key] } }
    }
    foreach ($file in @($changedFiles.Keys)) {
        $path = Join-Path $categoriesDir $file
        if (Test-Path -LiteralPath $path) { Write-Category $path $models[$file] }
    }
    $changedFiles.Clear()
    $script:dirty = $false
    $form.Text = 'Raintile - Opzioni'
    # aggiorna tutto: la skin, e le mini-skin dei tasti se sono attive
    Invoke-Rainmeter "!Refresh `"$Config`""
}

$btnSave.Add_Click({ Save-All })
$btnClose.Add_Click({ $form.Close() })
$btnImport.Add_Click({
        if ($dirty) { Save-All }
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $values = @{}; foreach ($item in $settings) { $values[$item.Key] = $item.Value }
        $out = & (Join-Path $Resources 'Scripts\Import.ps1') -Resources $Resources -Category $values['ImportCategory'] `
            -Stores $values['ImportStores'] -SteamGridDBKey $values['SteamGridDBKey'] 2>&1
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $models.Clear()
        Refresh-Cats $listCats.SelectedIndex
        [void][System.Windows.Forms.MessageBox]::Show($form, (($out | Where-Object { "$_" -notmatch '^RESULT:' }) -join "`r`n"), 'Importa giochi')
        Invoke-Rainmeter "!Refresh `"$Config`""
    })
$form.Add_FormClosing({
        param($sender, $e)
        if (-not $dirty) { return }
        $r = [System.Windows.Forms.MessageBox]::Show($form, 'Salvare le modifiche?', 'Raintile', 'YesNoCancel', 'Question')
        if ($r -eq 'Cancel') { $e.Cancel = $true }
        elseif ($r -eq 'Yes') { Save-All }
    })
$form.Add_Shown({
        [void][RaintileOptions.Win32]::ShowWindow($form.Handle, 1) # SW_SHOWNORMAL
        [void][RaintileOptions.Win32]::SetForegroundWindow($form.Handle)
        $form.Activate()
        $form.TopMost = $false
    })

Refresh-Cats
$tabs.SelectedIndex = 0
$script:dirty = $false
$form.Text = 'Raintile - Opzioni'
[void][System.Windows.Forms.Application]::Run($form)
