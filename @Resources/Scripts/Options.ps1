# Raintile: Options window (settings and categories). Work in progress.
#
# Opened from the gear button or the right-click menu.
#  - Settings: every Settings.inc entry, grouped as in the file, with the
#    description taken from the comments. Saving only changes the value on
#    its line: comments and order stay as they were.
#  - Categories: create, delete (to the Recycle Bin) and reorder categories;
#    add, delete, reorder and edit tiles. Picked images are copied to
#    Images\<category>\background|logo\<TileName>.<ext>. Imported games (below
#    the Import.ps1 marker) are listed but cannot be edited.
# "Save" writes the files and refreshes the skin.
#
# With -NoGui only the functions are loaded (for tests).

param(
    [Parameter(Mandatory = $true)][string]$Resources,
    [string]$Config = 'Raintile',
    [switch]$NoGui
)

$ErrorActionPreference = 'Stop'
$IMPORT_MARKER = '; ===== IMPORTED AUTOMATICALLY ====='
# Marker written by older Italian versions, still recognised
$OLD_IMPORT_MARKER = '; ===== IMPORTATI AUTOMATICAMENTE ====='
$utf8 = New-Object System.Text.UTF8Encoding $false
$settingsFile = Join-Path $Resources 'Settings.inc'
$categoriesDir = Join-Path $Resources 'Categories'
$imagesRoot = Join-Path $Resources 'Images'

# Entries with a fixed choice (drop-down)
$choices = @{
    'ScrollDir' = @('V', 'H')
    'MenuMode'  = @('IconText', 'Icon', 'Text')
    'BgStyle'   = @('Crop', 'Pan', 'Parallax', 'Zoom')
    'ShowZPos'  = @('1', '0', '-1', '-2')
}
# 0/1 switches (checkbox)
$switches = 'ShowLabels', 'InfiniteScroll', 'KeyboardNav', 'CloseOnLaunch', 'StartHidden', 'LaunchAnimation',
'AnimOpen', 'AnimCategory', 'AnimHover', 'AnimScroll', 'AnimLogoZoom', 'LogoGreyscale', 'Thumbnails',
'TileHover', 'Gamepad', 'ImportOnStart', 'DebugLog', 'AutoHide', 'AutoTileColor'

# --- Settings.inc --------------------------------------------------------------

# Returns the entries: Section, Key, Value, Description, Line (line index)
function Read-Settings([string]$path) {
    $lines = [IO.File]::ReadAllLines($path)
    $items = New-Object System.Collections.ArrayList
    $section = 'General'
    $comment = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim()
        if ($t -match '^;\s*---\s*(.+?)\s*-*$') {
            $section = $Matches[1]; $comment.Clear(); continue
        }
        if ($t.StartsWith(';')) { [void]$comment.Add($t.TrimStart(';').Trim()); continue }
        if ($t -eq '' -or $t.StartsWith('[')) { $comment.Clear(); continue }
        if ($t -match '^([^=]+?)\s*=(.*)$') {
            # computed values are not editable
            if ($section -notmatch '^Computed') {
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

# Writes the new values (hashtable Key -> Value) changing only those lines
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

# Colour components (R, G, B[, A]) from "R,G,B[,A]" or hex RRGGBB[AA] (with or
# without # or 0x); $null if the text is not a colour.
function ConvertFrom-ColorText([string]$text) {
    $t = $text.Trim()
    if ($t -match '^\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}(\s*,\s*\d{1,3})?$') {
        return , ($t -split '\s*,\s*' | ForEach-Object { [int]$_ })
    }
    $hex = $t -replace '^#', '' -replace '^0[xX]', ''
    if ($hex -match '^[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$') {
        return , (0..($hex.Length / 2 - 1) | ForEach-Object { [Convert]::ToInt32($hex.Substring($_ * 2, 2), 16) })
    }
    return $null
}

function Get-ControlKind($item) {
    if ($choices.ContainsKey($item.Key)) { return 'choice' }
    if ($item.Key -match 'Color$' -and (ConvertFrom-ColorText $item.Value)) { return 'color' }
    if ($switches -contains $item.Key) { return 'bool' }
    return 'text'
}

# --- Category files ---------------------------------------------------------------

# Model: Header (text before the first section), Sections (Name, Comments,
# Keys = ordered list of [Key, Value]), Imported (text from the marker on)
function Read-Category([string]$path) {
    $text = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } else { '' }
    $imported = ''
    $i = $text.IndexOf($IMPORT_MARKER)
    if ($i -lt 0) { $i = $text.IndexOf($OLD_IMPORT_MARKER) }
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

# Names of the imported tiles (read-only)
function Get-ImportedNames($model) {
    return @([regex]::Matches($model.Imported, '(?m)^\[(.+)\]\s*$') | ForEach-Object { $_.Groups[1].Value })
}

# Copies a picked image to the tile's default folder
function Copy-TileImage([string]$category, [string]$kind, [string]$tile, [string]$source) {
    $dir = Join-Path $imagesRoot "$category\$kind"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    # remove any previous image with another extension
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
#  User interface
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic

# An error while building the window must not go unnoticed (the script runs
# without a console): show it and write it to a log.
trap {
    $msg = "$($_.Exception.Message)`r`n`r`n$($_.InvocationInfo.PositionMessage)"
    try { [IO.File]::WriteAllText((Join-Path $Resources 'Generated\Options.log'), $msg, $utf8) } catch { }
    [void][System.Windows.Forms.MessageBox]::Show("Error in the Options window:`r`n`r`n$msg", 'Raintile')
    exit 1
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# Started without a console (hidden window): Windows might apply "hidden" to
# the first window shown too, so it is made visible and brought to the
# foreground explicitly.
Add-Type -Namespace RaintileOptions -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
'@

function Pad([int]$left, [int]$top, [int]$right, [int]$bottom) {
    return New-Object System.Windows.Forms.Padding($left, $top, $right, $bottom)
}

$dirty = $false
function Set-Dirty { $script:dirty = $true; $form.Text = 'Raintile - Options (WIP) *' }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Raintile - Options (WIP)'
$form.Size = New-Object System.Drawing.Size(1100, 760)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.TopMost = $true

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)

# Banner: the window is still being developed
$wip = New-Object System.Windows.Forms.Label
$wip.Text = 'WIP - Work in progress: this window is still being developed. Settings and category files can always be edited by hand too.'
$wip.Dock = 'Top'; $wip.Height = 30; $wip.TextAlign = 'MiddleCenter'
$wip.BackColor = [System.Drawing.Color]::FromArgb(255, 255, 196, 0)
$wip.ForeColor = [System.Drawing.Color]::Black
$wip.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
$form.Controls.Add($wip)

$bottom = New-Object System.Windows.Forms.FlowLayoutPanel
$bottom.Dock = 'Bottom'; $bottom.Height = 44; $bottom.FlowDirection = 'RightToLeft'; $bottom.Padding = (Pad 8 6 8 6)
$form.Controls.Add($bottom)
$btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = 'Close'; $btnClose.Width = 110
$btnSave = New-Object System.Windows.Forms.Button; $btnSave.Text = 'Save and refresh'; $btnSave.Width = 140
$btnImport = New-Object System.Windows.Forms.Button; $btnImport.Text = 'Import games'; $btnImport.Width = 130
$bottom.Controls.AddRange(@($btnClose, $btnSave, $btnImport))
$tip = New-Object System.Windows.Forms.ToolTip

# --- Settings tab -----------------------------------------------------------------

$settings = Read-Settings $settingsFile
$settingControls = @{}

$pageSettings = New-Object System.Windows.Forms.TabPage
$pageSettings.Text = 'Settings'
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
            $p = ConvertFrom-ColorText $item.Value
            $c.BackColor = [System.Drawing.Color]::FromArgb(255, $p[0], $p[1], $p[2])
            $c.ForeColor = if (($p[0] + $p[1] + $p[2]) -gt 380) { [System.Drawing.Color]::Black } else { [System.Drawing.Color]::White }
            $c.Add_Click({
                    $btn = $this
                    $v = ConvertFrom-ColorText $btn.Tag
                    $dlg = New-Object System.Windows.Forms.ColorDialog
                    $dlg.FullOpen = $true
                    $dlg.Color = [System.Drawing.Color]::FromArgb(255, $v[0], $v[1], $v[2])
                    if ($dlg.ShowDialog($form) -eq 'OK') {
                        # the value keeps its format (hex or R,G,B) and its opacity
                        $old = ([string]$btn.Tag).Trim()
                        if ($old -notmatch ',') {
                            $prefix = if ($old -match '^#') { '#' } elseif ($old -match '^0[xX]') { '0x' } else { '' }
                            $alpha = if ($v.Count -ge 4) { '{0:X2}' -f $v[3] } else { '' }
                            $btn.Tag = $prefix + ('{0:X2}{1:X2}{2:X2}' -f $dlg.Color.R, $dlg.Color.G, $dlg.Color.B) + $alpha
                        } else {
                            $alpha = if ($v.Count -ge 4) { ",$($v[3])" } else { '' }
                            $btn.Tag = "$($dlg.Color.R),$($dlg.Color.G),$($dlg.Color.B)$alpha"
                        }
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

# --- Categories tab ---------------------------------------------------------------

$models = @{}       # file -> model (loaded when needed)
$changedFiles = @{} # modified files
function Get-Model([string]$file) {
    if (-not $models.ContainsKey($file)) { $models[$file] = Read-Category (Join-Path $categoriesDir $file) }
    return $models[$file]
}
function Set-Changed([string]$file) { $changedFiles[$file] = $true; Set-Dirty }

$pageCats = New-Object System.Windows.Forms.TabPage
$pageCats.Text = 'Categories'
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

# Column 1: categories
$colCats = New-Column 'Categories'
$listCats = New-Object System.Windows.Forms.ListBox
$listCats.Dock = 'Fill'; $listCats.IntegralHeight = $false; $listCats.DisplayMember = 'Text'
$colCats.Controls.Add($listCats, 0, 1)
$barCats = New-Object System.Windows.Forms.FlowLayoutPanel; $barCats.AutoSize = $true
$btnCatNew = New-Button 'New'; $btnCatDel = New-Button 'Delete'; $btnCatUp = New-Button 'Up' 45; $btnCatDown = New-Button 'Down' 50
$barCats.Controls.AddRange(@($btnCatNew, $btnCatDel, $btnCatUp, $btnCatDown))
$colCats.Controls.Add($barCats, 0, 2)
$split.Controls.Add($colCats, 0, 0)

# Column 2: tiles of the category
$colTiles = New-Column 'Tiles'
$listTiles = New-Object System.Windows.Forms.ListBox
$listTiles.Dock = 'Fill'; $listTiles.IntegralHeight = $false; $listTiles.DisplayMember = 'Text'
$colTiles.Controls.Add($listTiles, 0, 1)
$barTiles = New-Object System.Windows.Forms.FlowLayoutPanel; $barTiles.AutoSize = $true
$btnTileNew = New-Button 'New'; $btnTileDel = New-Button 'Delete'; $btnTileUp = New-Button 'Up' 45; $btnTileDown = New-Button 'Down' 50
$barTiles.Controls.AddRange(@($btnTileNew, $btnTileDel, $btnTileUp, $btnTileDown))
$colTiles.Controls.Add($barTiles, 0, 2)
$split.Controls.Add($colTiles, 1, 0)

# Column 3: details (category at the top, tile below)
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

Add-Header 'Category'
Add-Field 'cat.Name' 'Name' 'Text shown in the menu'
Add-Field 'cat.Icon' 'Icon' 'Menu icon (default: Images\<category>\icon.png)' 'Browse...'
Add-Field 'cat.NX' 'Columns (NX)' 'Tiles visible per row (empty = Settings.inc)'
Add-Field 'cat.NY' 'Rows (NY)' 'Tiles visible per column (empty = Settings.inc)'
Add-Field 'cat.IconSize' 'Logo size' 'Logo size in the tiles, pixels or % (empty = Settings.inc)'
Add-Header 'Tile'
Add-Field 'tile.Name' 'Name' 'Tile name: also the default name of its images'
Add-Field 'tile.Command' 'Command' 'Program, .lnk/.url shortcut, URL, folder or Rainmeter bang' 'Browse...'
Add-Field 'tile.Label' 'Label' 'Text at the bottom left (empty = none)'
Add-Field 'tile.Color' 'Colour' 'Background colour when there is no background image (R,G,B,A or #RRGGBBAA; empty = automatic from the logo)' 'Pick...'
Add-Field 'tile.Background' 'Background' 'Empty = Images\<category>\background\<Name>.*' 'Browse...'
Add-Field 'tile.Logo' 'Logo' 'Empty = Images\<category>\logo\<Name>.*' 'Browse...'
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
        $e = [pscustomobject]@{ Section = $null; Imported = $true; Text = "$n   (imported)" }
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
        'Imported game: it is rewritten on every import and cannot be edited here. To customise it, add a tile with the same name: the import will not duplicate it.'
    } else { '' }
    $script:loading = $false
}

$listCats.Add_SelectedIndexChanged({ Show-Category })
$listTiles.Add_SelectedIndexChanged({ Show-Tile })

# Editing the category fields
foreach ($k in 'Name', 'Icon', 'NX', 'NY', 'IconSize') {
    $fields["cat.$k"].Tag = $k
    $fields["cat.$k"].Add_TextChanged({
            if ($loading) { return }
            $file = Get-CurrentFile; if (-not $file) { return }
            Set-Key (Get-CategorySection (Get-Model $file)) $this.Tag $this.Text.Trim()
            Set-Changed $file
        })
}
# Editing the tile fields
foreach ($k in 'Command', 'Label', 'Color', 'Background', 'Logo') {
    $fields["tile.$k"].Tag = $k
    $fields["tile.$k"].Add_TextChanged({
            if ($loading) { return }
            $s = Get-CurrentTile; if (-not $s) { return }
            Set-Key $s $this.Tag $this.Text.Trim()
            Set-Changed (Get-CurrentFile)
        })
}
# Renaming the tile (when editing ends, to check for duplicates)
$fields['tile.Name'].Add_Leave({
        $s = Get-CurrentTile; if (-not $s) { return }
        $new = ($this.Text -replace '[\[\]]', '').Trim()
        if (-not $new -or $new -eq $s.Name) { $this.Text = $s.Name; return }
        $m = Get-Model (Get-CurrentFile)
        if ($m.Sections | Where-Object { $_ -ne $s -and $_.Name -ieq $new }) {
            [void][System.Windows.Forms.MessageBox]::Show($form, "There is already a tile called '$new'.", 'Raintile')
            $this.Text = $s.Name; return
        }
        $s.Name = $new
        Set-Changed (Get-CurrentFile)
        Refresh-Tiles $listTiles.SelectedIndex
    })

# Browse...
function Select-File([string]$filter) {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = $filter
    if ($dlg.ShowDialog($form) -eq 'OK') { return $dlg.FileName }
    return $null
}
$imageFilter = 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.ico|All files|*.*'
$fields['cat.Icon.button'].Add_Click({
        $file = Get-CurrentFile; if (-not $file) { return }
        $src = Select-File $imageFilter; if (-not $src) { return }
        $base = [IO.Path]::GetFileNameWithoutExtension($file)
        $dir = Join-Path $imagesRoot $base
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.BaseName -ieq 'icon' } | Remove-Item -Force
        Copy-Item -LiteralPath $src -Destination (Join-Path $dir ('icon' + [IO.Path]::GetExtension($src).ToLowerInvariant())) -Force
        $fields['cat.Icon'].Text = ''   # the default icon just copied applies
        Set-Changed $file
    })
$fields['tile.Command.button'].Add_Click({
        $src = Select-File 'Programs and shortcuts|*.exe;*.lnk;*.url;*.bat;*.cmd|All files|*.*'
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
            $fields["tile.$($this.Tag)"].Text = ''   # the default image just copied applies
            Set-Changed (Get-CurrentFile)
        })
}

# Categories: new, delete, reorder
function Save-CategoryOrder {
    for ($i = 0; $i -lt $listCats.Items.Count; $i++) {
        $file = $listCats.Items[$i].File
        $c = Get-CategorySection (Get-Model $file)
        if ((Get-Key $c 'Order') -ne "$($i + 1)") { Set-Key $c 'Order' "$($i + 1)"; Set-Changed $file }
    }
}
$btnCatNew.Add_Click({
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('Category name (e.g. Emulators):', 'New category', '')
        $file = ($name -replace '[^A-Za-z0-9_-]', '')
        if (-not $file) { return }
        if (Test-Path -LiteralPath (Join-Path $categoriesDir "$file.ini")) {
            [void][System.Windows.Forms.MessageBox]::Show($form, "The category '$file' already exists.", 'Raintile'); return
        }
        $m = [pscustomobject]@{ Header = '; Format: see Games.ini'; Sections = (New-Object System.Collections.ArrayList); Imported = '' }
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
        $r = [System.Windows.Forms.MessageBox]::Show($form, "Move the category $file to the Recycle Bin? Its images stay in Images.", 'Raintile', 'YesNo', 'Warning')
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

# Tiles: new, delete, reorder (hand-written ones only)
$btnTileNew.Add_Click({
        $file = Get-CurrentFile; if (-not $file) { return }
        $m = Get-Model $file
        $name = ([Microsoft.VisualBasic.Interaction]::InputBox('Tile name (also the name of its images):', 'New tile', '') -replace '[\[\]]', '').Trim()
        if (-not $name) { return }
        if (($m.Sections | Where-Object { $_.Name -ieq $name }) -or ((Get-ImportedNames $m) -contains $name)) {
            [void][System.Windows.Forms.MessageBox]::Show($form, "There is already a tile called '$name'.", 'Raintile'); return
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
        $r = [System.Windows.Forms.MessageBox]::Show($form, "Delete the tile '$($s.Name)'?", 'Raintile', 'YesNo', 'Question')
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

# --- Save, import, close --------------------------------------------------------------

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
    $form.Text = 'Raintile - Options (WIP)'
    # refresh everything: the skin, and the key mini-skins if active
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
        [void][System.Windows.Forms.MessageBox]::Show($form, (($out | Where-Object { "$_" -notmatch '^RESULT:' }) -join "`r`n"), 'Import games')
        Invoke-Rainmeter "!Refresh `"$Config`""
    })
$form.Add_FormClosing({
        param($sender, $e)
        if (-not $dirty) { return }
        $r = [System.Windows.Forms.MessageBox]::Show($form, 'Save the changes?', 'Raintile', 'YesNoCancel', 'Question')
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
$form.Text = 'Raintile - Options (WIP)'
[void][System.Windows.Forms.Application]::Run($form)
