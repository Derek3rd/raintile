# Raintile: Options window (settings and categories). Work in progress.
#
# Opened from the gear button or the right-click menu. A WPF window (look in
# Options.xaml) with a menu on the left ($navTree: sections, some with
# sub-entries):
#  - settings pages: every Settings.inc entry with a fitting control (switch,
#    slider, choices, colour, key capture, ...), described by $schema below.
#    Saving only changes the value on its line: comments and order stay as
#    they were. Entries not in $schema are listed under Advanced.
#  - Categories: create, delete (to the Recycle Bin) and reorder categories.
#    One sub-entry per category: its settings, and its tiles to add, delete,
#    reorder and edit, with a preview. Picked
#    images are copied to Images\<category>\background|logo\<TileName>.<ext>.
#    Imported games (below the Import.ps1 marker) are listed but cannot be
#    edited.
# "Save and refresh" writes the files and refreshes the skin.
#
# With -NoGui only the functions and the schema are loaded (for tests).

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
$Resources = [IO.Path]::GetFullPath($Resources).TrimEnd('\', '/')
$settingsFile = Join-Path $Resources 'Settings.inc'
$categoriesDir = Join-Path $Resources 'Categories'
$imagesRoot = Join-Path $Resources 'Images'
$IMAGE_EXTS = '.png', '.jpg', '.jpeg', '.bmp', '.ico', '.gif'

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

# A colour picked as R,G,B written in the format of the old value (hex or
# R,G,B), keeping its opacity.
function Format-PickedColor([string]$old, [int]$r, [int]$g, [int]$b) {
    $old = $old.Trim()
    $v = ConvertFrom-ColorText $old
    if ($old -and $old -notmatch ',') {
        $prefix = if ($old -match '^#') { '#' } elseif ($old -match '^0[xX]') { '0x' } else { '#' }
        $alpha = if ($v -and $v.Count -ge 4) { '{0:X2}' -f $v[3] } else { '' }
        return $prefix + ('{0:X2}{1:X2}{2:X2}' -f $r, $g, $b) + $alpha
    }
    $alpha = if ($v -and $v.Count -ge 4) { ",$($v[3])" } elseif (-not $old) { ',255' } else { '' }
    return "$r,$g,$b$alpha"
}

# --- Keys (HotKey plugin names) ---------------------------------------------------

# Windows virtual-key code -> HotKey plugin name
$VK_NAMES = @{
    0x08 = 'BACKSPACE'; 0x09 = 'TAB'; 0x0D = 'ENTER'; 0x13 = 'PAUSE'; 0x14 = 'CAPSLOCK'; 0x1B = 'ESCAPE'
    0x20 = 'SPACE'; 0x21 = 'PAGEUP'; 0x22 = 'PAGEDOWN'; 0x23 = 'END'; 0x24 = 'HOME'
    0x25 = 'LEFT'; 0x26 = 'UP'; 0x27 = 'RIGHT'; 0x28 = 'DOWN'; 0x2C = 'PRINTSCREEN'; 0x2D = 'INSERT'; 0x2E = 'DELETE'
    0x5B = 'LWIN'; 0x5C = 'RWIN'; 0x5D = 'MENU'
    0x6A = 'MULT'; 0x6B = 'ADD'; 0x6D = 'SUBTRACT'; 0x6E = 'DECIMAL'; 0x6F = 'DIVIDE'
    0x90 = 'NUMLOCK'; 0x91 = 'SCROLLLOCK'
    0x10 = 'SHIFT'; 0x11 = 'CTRL'; 0x12 = 'ALT'
    0xA0 = 'LSHIFT'; 0xA1 = 'RSHIFT'; 0xA2 = 'LCTRL'; 0xA3 = 'RCTRL'; 0xA4 = 'LALT'; 0xA5 = 'RALT'
    0xBA = 'COLON'; 0xBB = 'PLUS'; 0xBC = 'COMMA'; 0xBD = 'MINUS'; 0xBE = 'PERIOD'; 0xBF = 'FORWARDSLASH'
    0xC0 = 'BACKTICK'; 0xDB = 'LBRACKET'; 0xDC = 'BACKSLASH'; 0xDD = 'RBRACKET'; 0xDE = 'QUOTE'
}
foreach ($c in @(0x30..0x39) + @(0x41..0x5A)) { $VK_NAMES[$c] = [string][char]$c }
foreach ($n in 0..9) { $VK_NAMES[0x60 + $n] = "NUM$n" }
foreach ($n in 1..24) { $VK_NAMES[0x6F + $n] = "F$n" }
$MODIFIER_VKS = 0x10, 0x11, 0x12, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C

# Value written to Settings.inc for a key press: just the key, or (combo) the
# held modifiers too, e.g. "CTRL ALT G". $null for keys without a name and,
# in combos, for modifiers alone.
function ConvertTo-HotKey([int]$vk, [bool]$ctrl = $false, [bool]$alt = $false, [bool]$shift = $false,
    [bool]$win = $false, [switch]$Combo) {
    $name = $VK_NAMES[$vk]
    if (-not $name) { return $null }
    if (-not $Combo) { return $name }
    if ($MODIFIER_VKS -contains $vk) { return $null }
    $parts = @()
    if ($ctrl) { $parts += 'CTRL' }
    if ($alt) { $parts += 'ALT' }
    if ($shift) { $parts += 'SHIFT' }
    if ($win) { $parts += 'LWIN' }
    return (($parts + $name) -join ' ')
}

# Readable form of a HotKey value: "CTRL ALT G" -> "Ctrl + Alt + G"
$KEY_LABELS = @{
    CTRL = 'Ctrl'; LCTRL = 'Left Ctrl'; RCTRL = 'Right Ctrl'; ALT = 'Alt'; LALT = 'Left Alt'; RALT = 'Right Alt'
    SHIFT = 'Shift'; LSHIFT = 'Left Shift'; RSHIFT = 'Right Shift'; LWIN = 'Win'; RWIN = 'Right Win'; WIN = 'Win'
    ESCAPE = 'Esc'; ENTER = 'Enter'; SPACE = 'Space'; TAB = 'Tab'; BACKSPACE = 'Backspace'
    UP = [string][char]0x2191; DOWN = [string][char]0x2193; LEFT = [string][char]0x2190; RIGHT = [string][char]0x2192
    PAGEUP = 'Page Up'; PAGEDOWN = 'Page Down'; PRINTSCREEN = 'Print Screen'; CAPSLOCK = 'Caps Lock'
    NUMLOCK = 'Num Lock'; SCROLLLOCK = 'Scroll Lock'; MULT = 'Num *'; ADD = 'Num +'; SUBTRACT = 'Num -'
    DECIMAL = 'Num .'; DIVIDE = 'Num /'; COLON = ';'; PLUS = '='; COMMA = ','; MINUS = '-'; PERIOD = '.'
    FORWARDSLASH = '/'; BACKTICK = '`'; LBRACKET = '['; BACKSLASH = '\'; RBRACKET = ']'; QUOTE = "'"
}
function Format-HotKey([string]$value) {
    $tokens = @($value.Trim() -split '\s+' | Where-Object { $_ })
    if ($tokens.Count -eq 0) { return 'None' }
    $labels = foreach ($t in $tokens) {
        $u = $t.ToUpperInvariant()
        if ($KEY_LABELS.ContainsKey($u)) { $KEY_LABELS[$u] }
        elseif ($u -match '^NUM(\d)$') { "Num $($Matches[1])" }
        elseif ($u -match '^(F\d{1,2}|.)$') { $u }
        else { $u.Substring(0, 1) + $u.Substring(1).ToLowerInvariant() }
    }
    return ($labels -join ' + ')
}

# --- Settings schema ------------------------------------------------------------------
# Pages of the window: groups of items. Kinds:
#   bool, choice (Choices = value, label), int / float (slider: Min, Max, Step,
#   Unit), size (pixels or % of the screen width/height: Axis W/H), color,
#   text, font, category, stores, pad (gamepad buttons), key, combo (key with
#   modifiers), keys (two keys for one action: Pair), screen (ScreenX/Y/W/H),
#   info (text only), action (button).

function S([string]$kind, [string]$key, [string]$label, [string]$help = '', [hashtable]$more = @{}) {
    $item = @{ Kind = $kind; Key = $key; Label = $label; Help = $help }
    foreach ($k in $more.Keys) { $item[$k] = $more[$k] }
    return $item
}
function Num([string]$key, [string]$label, [double]$min, [double]$max, [double]$step, [string]$unit = '', [string]$help = '') {
    $kind = if ($step -lt 1) { 'float' } else { 'int' }
    return (S $kind $key $label $help @{ Min = $min; Max = $max; Step = $step; Unit = $unit })
}
function Size([string]$key, [string]$label, [string]$axis, [string]$help = '') {
    return (S 'size' $key $label $help @{ Axis = $axis })
}

$GAMEPAD_BUTTONS = 'A', 'B', 'X', 'Y', 'LB', 'RB', 'BACK', 'START', 'LS', 'RS', 'UP', 'DOWN', 'LEFT', 'RIGHT'
$STORES = 'Steam', 'Epic', 'GOG', 'Ubisoft'

$schema = @(
    @{ Id = 'general'; Title = 'General'; Icon = 0xE713
        Desc = 'Where the launcher appears and how it opens and closes.'
        Groups = @(
            @{ Title = 'Screen'; Items = @(
                    (S 'screen' 'ScreenX' 'Area covered' 'The launcher covers the whole area. The work area leaves the taskbar free.')
                ) }
            @{ Title = 'Opening and closing'; Items = @(
                    (S 'bool' 'StartHidden' 'Start hidden' 'Stay hidden when Rainmeter starts, until you open it with the shortcut or the gamepad.'),
                    (S 'bool' 'AutoHide' 'Hide when it loses focus' 'A click outside the launcher (e.g. on another monitor) or another program coming to the foreground hides it.'),
                    (S 'bool' 'CloseOnLaunch' 'Hide after launching a tile'),
                    (S 'choice' 'CloseAction' 'Close button (X)' 'Unloading frees memory, but the next opening is slower.' @{ Choices = @(
                                @('[!CommandMeasure MeasureScript "Hide()"]', 'Hide'), @('[!DeactivateConfig]', 'Unload the skin')) }),
                    (S 'choice' 'ShowZPos' 'Window level when shown' 'On the desktop, hiding on focus loss does not work.' @{ Choices = @(
                                @('1', 'On top'), @('2', 'Always on top'), @('0', 'Normal'), @('-2', 'On the desktop'), @('', 'Unchanged')) }),
                    (Num 'FadeDuration' 'Fade when opening and closing' 0 1000 10 'ms' 'Applies from the next time Rainmeter loads the skin.')
                ) }
        )
    }
    @{ Id = 'layout'; Title = 'Layout'; Icon = 0xE8A9
        Desc = 'The default grid of tiles and the spaces around it. Each category can have its own grid (Categories).'
        Groups = @(
            @{ Title = 'Grid'; Items = @(
                    (Num 'NX' 'Columns' 1 12 1),
                    (Num 'NY' 'Rows' 1 8 1),
                    (S 'choice' 'ScrollDir' 'Scroll direction' '' @{ Choices = @(@('V', 'Vertical'), @('H', 'Horizontal')) }),
                    (Num 'ScrollStep' 'Rows per mouse wheel notch' 1 5 1),
                    (S 'bool' 'InfiniteScroll' 'Infinite scroll' 'After the last row the first one comes back (only when the tiles do not all fit).')
                ) }
            @{ Title = 'Spacing'; Help = 'In pixels, or as a percentage of the screen.'; Items = @(
                    (Size 'Gap' 'Space between tiles' 'H'),
                    (Size 'PadX' 'Side margins' 'W' 'Also holds the vertical scrollbar.'),
                    (Size 'PadY' 'Top and bottom margins' 'H' 'Also holds the horizontal scrollbar.'),
                    (Size 'IconSize' 'Logo size' 'H' 'Box the tile logo fits in.'),
                    (Size 'LabelPad' 'Label margin' 'H'),
                    (Size 'ScrollBarSize' 'Scrollbar thickness' 'H')
                ) }
        )
    }
    @{ Id = 'menu'; Title = 'Menu'; Icon = 0xE700
        Desc = 'The category menu at the top.'
        Groups = @(
            @{ Title = 'Category menu'; Items = @(
                    (S 'choice' 'MenuMode' 'Show' 'A category without an icon always shows its name.' @{ Choices = @(
                                @('IconText', 'Icon and text'), @('Icon', 'Icon only'), @('Text', 'Text only')) }),
                    (Size 'MenuH' 'Height' 'H'),
                    (Size 'MenuIconSize' 'Icon size' 'H'),
                    (Size 'MenuIconGap' 'Space between icon and text' 'W'),
                    (Size 'MenuItemPad' 'Entry padding' 'W'),
                    (Size 'MenuGap' 'Space between entries' 'W'),
                    (Size 'MenuRadius' 'Corner radius' 'H'),
                    (Num 'MenuIconDimAlpha' 'Opacity of inactive icons' 0 255 5)
                ) }
            @{ Title = 'Buttons'; Items = @(
                    (Num 'CloseSize' 'Size of the X and gear buttons' 8 40 1)
                ) }
        )
    }
    @{ Id = 'appearance'; Title = 'Appearance'; Icon = 0xE790
        Desc = 'Fonts and colours. Colours can be written as R,G,B,A or #RRGGBBAA: click the swatch to pick one.'
        Groups = @(
            @{ Title = 'Text'; Items = @(
                    (S 'font' 'FontFace' 'Font'),
                    (Num 'MenuFontSize' 'Menu font size' 6 40 1 'pt'),
                    (Num 'LabelFontSize' 'Label font size' 6 40 1 'pt'),
                    (S 'bool' 'ShowLabels' 'Show tile labels')
                ) }
            @{ Title = 'Tiles'; Items = @(
                    (S 'color' 'TileColor' 'Default tile colour'),
                    (S 'bool' 'AutoTileColor' 'Colour from the logo' 'Tiles with a logo but no background image and no colour of their own get a dark colour taken from the logo.'),
                    (S 'bool' 'LogoGreyscale' 'Greyscale logos' 'They turn to colour under the mouse.')
                ) }
            @{ Title = 'Colours'; Items = @(
                    (S 'color' 'BgColor' 'Launcher background'),
                    (S 'color' 'AccentColor' 'Accent' 'Highlight border, scrollbar, buttons under the mouse.'),
                    (S 'color' 'HoverColor' 'Highlight fill'),
                    (S 'color' 'ActiveCategoryColor' 'Active category'),
                    (S 'color' 'HoverCategoryColor' 'Category under the mouse'),
                    (S 'color' 'TextColor' 'Text'),
                    (S 'color' 'TextDimColor' 'Dimmed text'),
                    (S 'color' 'ScrollTrackColor' 'Scrollbar track'),
                    (S 'color' 'ScrollThumbColor' 'Scrollbar thumb')
                ) }
        )
    }
    @{ Id = 'animations'; Title = 'Animations'; Icon = 0xE945
        Desc = 'They only run while something moves: at rest the launcher uses no CPU. Lengths are in steps of 16 ms.'
        Groups = @(
            @{ Title = 'Effects'; Items = @(
                    (S 'bool' 'AnimOpen' 'Tiles appear when opening'),
                    (S 'bool' 'AnimCategory' 'Tiles appear on category change' 'The menu pill slides too.'),
                    (S 'bool' 'AnimHover' 'Sliding highlight'),
                    (S 'bool' 'AnimScroll' 'Smooth scrolling'),
                    (S 'bool' 'AnimLogoZoom' 'Logo zoom under the mouse'),
                    (Num 'HoverLogoScale' 'Logo zoom' 1 2 0.05 ([string][char]0xD7))
                ) }
            @{ Title = 'Appearing tiles'; Items = @(
                    (Num 'AnimAppearFrames' 'Length' 1 60 1 'steps'),
                    (Num 'AnimStagger' 'Delay between one tile and the next' 0 10 1 'steps'),
                    (Num 'AnimSlide' 'Upward slide' 0 200 1 'px')
                ) }
            @{ Title = 'Smoothing'; Help = 'Lower is smoother and slower, 1 is instant.'; Items = @(
                    (Num 'AnimSmooth' 'Base' 0.05 1 0.01),
                    (Num 'AnimScrollSmooth' 'Scrolling' 0.05 1 0.01),
                    (Num 'AnimHoverSmooth' 'Highlight' 0.05 1 0.01),
                    (Num 'AnimPillSmooth' 'Menu pill' 0.05 1 0.01),
                    (Num 'AnimLogoSmooth' 'Logo zoom and colour' 0.05 1 0.01)
                ) }
            @{ Title = 'Tile launch'; Items = @(
                    (S 'bool' 'LaunchAnimation' 'Full-screen expansion' 'The tile expands to full screen before the launcher hides.'),
                    (Num 'LaunchAnimFrames' 'Expansion length' 1 60 1 'steps'),
                    (Num 'LaunchHold' 'Time at full screen' 0 5000 100 'ms'),
                    (Size 'LaunchLogoSize' 'Logo size at full screen' 'H'),
                    (Num 'LaunchFontSize' 'Text size for tiles without a logo' 8 120 1 'pt')
                ) }
        )
    }
    @{ Id = 'backgrounds'; Title = 'Backgrounds'; Icon = 0xE91B
        Desc = 'How the background images of the tiles move.'
        Groups = @(
            @{ Title = 'Tile backgrounds'; Items = @(
                    (S 'choice' 'BgStyle' 'Style' 'Crop: fixed. Pan: under the mouse the image slowly slides. Parallax: it moves slower than the tile while scrolling. Zoom: it grows slightly under the mouse.' @{ Choices = @(
                                @('Crop', 'Crop'), @('Pan', 'Pan'), @('Parallax', 'Parallax'), @('Zoom', 'Zoom')) }),
                    (Num 'BgOverscan' 'Overscan' 1 1.5 0.01 ([string][char]0xD7) 'How much larger than the tile the image is: room to move.'),
                    (Num 'BgPanFrames' 'Pan length' 30 600 10 'steps'),
                    (Num 'BgHoverZoom' 'Zoom amount' 1 1.3 0.01 ([string][char]0xD7))
                ) }
        )
    }
    @{ Id = 'keys'; Title = 'Keyboard'; Icon = 0xE765
        Desc = 'Click a key and press the new one. Navigation keys only work while the launcher is visible.'
        Groups = @(
            @{ Title = 'Open and close'; Items = @(
                    (S 'combo' 'OpenHotKey' 'Open / close the launcher' 'Works everywhere, also while the launcher is hidden. Hold the modifiers, then press the key.'),
                    (S 'key' 'CloseHotKey' 'Close' 'Closes the search first, if it is open.')
                ) }
            @{ Title = 'Navigation'; Items = @(
                    (S 'bool' 'KeyboardNav' 'Keyboard navigation'),
                    (S 'keys' 'NavUp' 'Move up' '' @{ Pair = @('NavUp', 'NavUp2') }),
                    (S 'keys' 'NavDown' 'Move down' '' @{ Pair = @('NavDown', 'NavDown2') }),
                    (S 'keys' 'NavLeft' 'Move left' '' @{ Pair = @('NavLeft', 'NavLeft2') }),
                    (S 'keys' 'NavRight' 'Move right' '' @{ Pair = @('NavRight', 'NavRight2') }),
                    (S 'keys' 'NavConfirm' 'Launch the highlighted tile' 'Acts when the key is released.' @{ Pair = @('NavConfirm', 'NavConfirm2') }),
                    (S 'key' 'NavPrevCategory' 'Previous category'),
                    (S 'key' 'NavNextCategory' 'Next category'),
                    (S 'key' 'NavSearch' 'Search')
                ) }
        )
    }
    @{ Id = 'gamepad'; Title = 'Gamepad'; Icon = 0xE7FC
        Desc = 'Xbox and compatible (XInput) controllers, read by a small background helper.'
        Groups = @(
            @{ Title = 'Controller'; Items = @(
                    (S 'bool' 'Gamepad' 'Gamepad support'),
                    (S 'pad' 'GamepadToggle' 'Open / close' 'Buttons to hold together.'),
                    (Num 'GamepadDeadZone' 'Stick dead zone' 0 32767 500),
                    (Num 'GamepadRepeatDelay' 'Repeat delay' 50 1000 10 'ms' 'Holding a direction: wait before it repeats.'),
                    (Num 'GamepadRepeatRate' 'Repeat interval' 30 500 10 'ms')
                ) }
            @{ Title = 'Buttons'; Items = @(
                    (S 'info' '' 'D-pad / left stick' 'Move the highlight'),
                    (S 'info' '' 'A' 'Launch the highlighted tile'),
                    (S 'info' '' 'B' 'Close the search, or the launcher'),
                    (S 'info' '' 'LB / RB' 'Previous / next category')
                ) }
        )
    }
    @{ Id = 'search'; Title = 'Search'; Icon = 0xE721
        Desc = 'The search bar at the top left searches the tiles of every category.'
        Groups = @(
            @{ Title = 'Search bar'; Items = @(
                    (Size 'SearchW' 'Width' 'W'),
                    (S 'text' 'SearchPlaceholder' 'Text in the empty bar')
                ) }
        )
    }
    @{ Id = 'import'; Title = 'Import'; Icon = 0xE896
        Desc = 'Games installed from the stores are added at the end of a category, in a block rewritten on every import. Tiles you wrote yourself are never touched.'
        Groups = @(
            @{ Title = 'Store import'; Items = @(
                    (S 'category' 'ImportCategory' 'Category' 'Where imported games go.'),
                    (S 'stores' 'ImportStores' 'Stores'),
                    (S 'bool' 'ImportOnStart' 'Import on every load' 'In the background, each time the skin loads.'),
                    (S 'text' 'SteamGridDBKey' 'SteamGridDB API key' 'Free, from steamgriddb.com > Preferences > API. Downloads images for games without local ones.')
                ) }
            @{ Title = 'Import now'; Items = @(
                    (S 'action' 'Import' 'Import games' 'Saves the changes, imports and refreshes the skin.')
                ) }
        )
    }
    @{ Id = 'advanced'; Title = 'Advanced'; Icon = 0xE90F
        Desc = 'Performance, diagnostics and the entries that have no page of their own.'
        Groups = @(
            @{ Title = 'Performance'; Items = @(
                    (S 'bool' 'Thumbnails' 'Thumbnails' 'Uses copies of the images at the exact displayed size, made in the background.'),
                    (S 'bool' 'TileHover' 'Highlight the tile under the mouse')
                ) }
            @{ Title = 'Diagnostics'; Items = @(
                    (S 'bool' 'DebugLog' 'Debug log' 'Writes details to the Rainmeter log (Manage > Log).')
                ) }
            @{ Title = 'Other settings'; Other = $true; Items = @() }
            @{ Title = 'Files'; Items = @(
                    (S 'action' 'OpenSettings' 'Settings file' 'Settings.inc, in Notepad.'),
                    (S 'action' 'OpenFolder' 'Skin resources' 'Categories, images and scripts.')
                ) }
        )
    }
    @{ Id = 'categories'; Title = 'Categories'; Icon = 0xECA5
        Desc = 'One file per category in Categories\. Double-click a category, or pick it on the left, to edit it and its tiles.'
        Groups = @()
    }
)

# Menu on the left: pages, and groups with sub-entries (Categories lists one
# entry per category file)
$navTree = @(
    @{ Page = 'general' }, @{ Page = 'layout' }, @{ Page = 'menu' }, @{ Page = 'appearance' },
    @{ Page = 'animations' }, @{ Page = 'backgrounds' },
    @{ Id = 'keybindings'; Title = 'Keybindings'; Icon = 0xE765; Children = @('keys', 'gamepad') },
    @{ Page = 'search' }, @{ Page = 'import' }, @{ Page = 'advanced' },
    @{ Page = 'categories'; Categories = $true }
)

# Default values (as shipped), for "Restore default"
$defaults = @{
    ScreenX = '#SCREENAREAX#'; ScreenY = '#SCREENAREAY#'; ScreenW = '#SCREENAREAWIDTH#'; ScreenH = '#SCREENAREAHEIGHT#'
    NX = '4'; NY = '2'; ScrollDir = 'V'; ScrollStep = '1'; InfiniteScroll = '1'
    Gap = '18'; PadX = '40'; PadY = '24'; IconSize = '96'; LabelPad = '14'; ScrollBarSize = '4'
    MenuMode = 'IconText'; MenuH = '44'; MenuIconSize = '24'; MenuIconGap = '8'; MenuItemPad = '16'; MenuGap = '6'
    MenuRadius = '22'; MenuIconDimAlpha = '150'
    OpenHotKey = 'CTRL ALT G'; CloseAction = '[!CommandMeasure MeasureScript "Hide()"]'; CloseSize = '14'
    CloseHotKey = 'ESCAPE'; KeyboardNav = '1'
    NavUp = 'W'; NavUp2 = 'UP'; NavDown = 'S'; NavDown2 = 'DOWN'; NavLeft = 'A'; NavLeft2 = 'LEFT'
    NavRight = 'D'; NavRight2 = 'RIGHT'; NavConfirm = 'SPACE'; NavConfirm2 = 'ENTER'
    NavPrevCategory = 'Q'; NavNextCategory = 'E'; NavSearch = 'F'
    CloseOnLaunch = '1'; AutoHide = '1'; StartHidden = '0'; ShowZPos = '1'
    LaunchAnimation = '1'; LaunchAnimFrames = '15'; LaunchHold = '1500'; LaunchLogoSize = '33%'; LaunchFontSize = '48'
    AnimOpen = '1'; AnimCategory = '1'; AnimHover = '1'; AnimScroll = '1'; AnimLogoZoom = '1'
    HoverLogoScale = '1.25'; LogoGreyscale = '1'; AnimAppearFrames = '12'; AnimStagger = '2'; AnimSlide = '30'
    AnimSmooth = '0.3'; AnimScrollSmooth = '0.15'; AnimHoverSmooth = '0.3'; AnimPillSmooth = '0.25'; AnimLogoSmooth = '0.2'
    BgStyle = 'Parallax'; BgOverscan = '1.15'; BgPanFrames = '180'; BgHoverZoom = '1.08'
    Thumbnails = '1'; TileHover = '1'; FadeDuration = '0'
    Gamepad = '1'; GamepadToggle = 'BACK START'; GamepadDeadZone = '12000'; GamepadRepeatDelay = '350'; GamepadRepeatRate = '110'
    SearchW = '320'; SearchPlaceholder = 'Search'
    ImportCategory = 'Games'; ImportStores = 'Steam|Epic|GOG|Ubisoft'; ImportOnStart = '0'; SteamGridDBKey = ''
    DebugLog = '0'; ShowLabels = '1'; FontFace = 'Segoe UI'; MenuFontSize = '12'; LabelFontSize = '14'
    BgColor = '8,8,12,200'; TileColor = '36,36,44,255'; AutoTileColor = '1'; HoverColor = '255,255,255,25'
    AccentColor = '0,210,180,255'; ActiveCategoryColor = '0,210,180,70'; HoverCategoryColor = '255,255,255,20'
    TextColor = '240,240,245,255'; TextDimColor = '150,150,160,255'
    ScrollTrackColor = '255,255,255,25'; ScrollThumbColor = '0,210,180,200'
}

# Settings.inc keys the schema shows on a page
function Get-SchemaKeys {
    $keys = New-Object System.Collections.ArrayList
    foreach ($page in $schema) {
        foreach ($group in $page.Groups) {
            foreach ($item in $group.Items) {
                if ($item.Kind -eq 'screen') { [void]$keys.AddRange(@('ScreenX', 'ScreenY', 'ScreenW', 'ScreenH')) }
                elseif ($item.Kind -eq 'keys') { [void]$keys.AddRange([string[]]$item.Pair) }
                elseif ($item.Kind -notin 'info', 'action') { [void]$keys.Add($item.Key) }
            }
        }
    }
    return , $keys
}

# Screen area: "#SCREENAREAX#", "#WORKAREAWIDTH@2#", ... -> @{ Area; Monitor }
# ($null if the four values are not of that form)
function ConvertFrom-ScreenArea([hashtable]$v) {
    $area = $null; $mon = $null
    foreach ($p in @(@('ScreenX', 'X'), @('ScreenY', 'Y'), @('ScreenW', 'WIDTH'), @('ScreenH', 'HEIGHT'))) {
        if ("$($v[$p[0]])" -notmatch "^#(SCREENAREA|WORKAREA)$($p[1])(@\d+)?#$") { return $null }
        $a = $Matches[1]; $m = if ($Matches[2]) { $Matches[2].Substring(1) } else { '' }
        if ($null -ne $area -and ($a -ne $area -or $m -ne $mon)) { return $null }
        $area = $a; $mon = $m
    }
    return @{ Area = $area; Monitor = $mon }
}
function ConvertTo-ScreenArea([string]$area, [string]$monitor) {
    $at = if ($monitor) { "@$monitor" } else { '' }
    return @{
        ScreenX = "#${area}X$at#"; ScreenY = "#${area}Y$at#"
        ScreenW = "#${area}WIDTH$at#"; ScreenH = "#${area}HEIGHT$at#"
    }
}

# Number written back with the precision of the slider step
function Format-Number([double]$value, [double]$step) {
    $r = [Math]::Round($value / $step) * $step
    if ($step -ge 1) { return ([long][Math]::Round($r)).ToString() }
    return $r.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
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

# Image 'name' in 'dir' (or an absolute path), with or without extension, as
# the skin looks for it; $null if not found.
function Find-Image([string]$dir, [string]$name) {
    $p = $name.Trim().Trim('"')
    if (-not $p) { return $null }
    if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $dir $p }
    if ($p -match '\.\w+$') {
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
        return $null
    }
    foreach ($e in $IMAGE_EXTS) { if (Test-Path -LiteralPath ($p + $e) -PathType Leaf) { return $p + $e } }
    return $null
}

# Background or logo of a tile: its Background=/Logo= key, otherwise the image
# named after Image= or the tile.
function Get-TileImage([string]$categoryBase, $section, [string]$kind) {
    $dir = Join-Path $imagesRoot "$categoryBase\$($kind.ToLowerInvariant())"
    $explicit = Get-Key $section $kind
    if ($explicit) { return (Find-Image $dir $explicit) }
    $image = Get-Key $section 'Image'
    if (-not $image) { $image = $section.Name }
    return (Find-Image $dir $image)
}

function Get-CategoryIcon([string]$categoryBase, $catSection) {
    $icon = Get-Key $catSection 'Icon'
    if (-not $icon) { $icon = 'icon' }
    return (Find-Image (Join-Path $imagesRoot $categoryBase) $icon)
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

# Renaming a tile: its default images follow it
function Rename-TileImages([string]$category, [string]$old, [string]$new) {
    foreach ($kind in 'background', 'logo') {
        $dir = Join-Path $imagesRoot "$category\$kind"
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.BaseName -ieq $old })) {
            $dest = Join-Path $dir ($new + $f.Extension)
            if (-not (Test-Path -LiteralPath $dest)) { Move-Item -LiteralPath $f.FullName -Destination $dest }
        }
    }
}

function Get-CategoryFiles {
    return @(Get-ChildItem -LiteralPath $categoriesDir -Filter '*.ini' -File | Sort-Object Name)
}

# Tile colours computed from the logos by Thumbs.ps1 (Generated\Colors.txt):
# full logo path (lower case) -> colour
function Read-LogoColors {
    $map = @{}
    $file = Join-Path $Resources 'Generated\Colors.txt'
    if (-not (Test-Path -LiteralPath $file)) { return $map }
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        $parts = $line.Split('|', 3)
        if ($parts.Count -eq 3 -and $parts[1]) {
            try { $map[[IO.Path]::GetFullPath($parts[2]).ToLowerInvariant()] = $parts[1] } catch { }
        }
    }
    return $map
}

if ($NoGui) { return }

# ==============================================================================
#  User interface (WPF)
# ==============================================================================

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing, Microsoft.VisualBasic

function Write-ErrorLog([string]$msg) {
    try { [IO.File]::WriteAllText((Join-Path $Resources 'Generated\Options.log'), $msg, $utf8) } catch { }
}

# An error while building the window must not go unnoticed (the script runs
# without a console): show it and write it to a log.
trap {
    $msg = "$($_.Exception.Message)`r`n`r`n$($_.InvocationInfo.PositionMessage)"
    Write-ErrorLog $msg
    [void][System.Windows.MessageBox]::Show("Error in the Options window:`r`n`r`n$msg", 'Raintile')
    exit 1
}

Add-Type -Namespace RaintileOptions -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
[DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
[DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hdc);
[DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int index);
'@

# Dark title bar (Windows 10 2004+ / 11)
function Set-DarkTitle($window) {
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
        $on = 1
        foreach ($attr in 20, 19) { if ([RaintileOptions.Win32]::DwmSetWindowAttribute($h, $attr, [ref]$on, 4) -eq 0) { break } }
    } catch { }
}

# Resolution of the main screen in real pixels (for px <-> % conversion)
function Get-ScreenPixels {
    $dc = [RaintileOptions.Win32]::GetDC([IntPtr]::Zero)
    try { return @{ W = [RaintileOptions.Win32]::GetDeviceCaps($dc, 118); H = [RaintileOptions.Win32]::GetDeviceCaps($dc, 117) } }
    finally { [void][RaintileOptions.Win32]::ReleaseDC([IntPtr]::Zero, $dc) }
}

$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
$app.Resources = [System.Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Options.xaml')))
# An error in an event handler: shown and logged, the window stays open
$app.Add_DispatcherUnhandledException({
        param($s, $e)
        $e.Handled = $true
        $msg = $e.Exception.ToString()
        Write-ErrorLog $msg
        [void][System.Windows.MessageBox]::Show("Something went wrong:`r`n`r`n$($e.Exception.Message)`r`n`r`nDetails in Generated\Options.log", 'Raintile')
    })

function Res([string]$name) { return $app.Resources[$name] }

# --- Small helpers to build elements ----------------------------------------------

function T([double]$a, [double]$b = -1, [double]$c = -1, [double]$d = -1) {
    if ($b -lt 0) { return (New-Object System.Windows.Thickness($a)) }
    if ($c -lt 0) { return (New-Object System.Windows.Thickness($a, $b, $a, $b)) }
    return (New-Object System.Windows.Thickness($a, $b, $c, $d))
}

function New-Text([string]$text, [double]$size = 13, $brush = $null, [switch]$Bold, [switch]$Wrap) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $text
    $t.FontSize = $size
    if ($brush) { $t.Foreground = $brush }
    if ($Bold) { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
    if ($Wrap) { $t.TextWrapping = 'Wrap' }
    return $t
}

function New-Glyph([int]$code, [double]$size = 14) {
    $t = New-Text ([string][char]$code) $size
    $t.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe MDL2 Assets')
    $t.VerticalAlignment = 'Center'
    return $t
}

function New-Button([string]$text, [string]$style = '', [string]$tip = '') {
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $text
    if ($style) { $b.Style = Res $style }
    if ($tip) { $b.ToolTip = $tip }
    return $b
}

function New-IconButton([int]$glyph, [string]$tip) {
    $b = New-Button ([string][char]$glyph) 'IconButton' $tip
    return $b
}

function New-Panel([string]$orientation = 'Vertical') {
    $p = New-Object System.Windows.Controls.StackPanel
    $p.Orientation = $orientation
    return $p
}

function Add-To($panel, $child) { [void]$panel.Children.Add($child); return $child }

function New-Grid([string[]]$columns) {
    $g = New-Object System.Windows.Controls.Grid
    foreach ($w in $columns) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = if ($w -eq '*') { New-Object System.Windows.GridLength(1, 'Star') }
        elseif ($w -eq 'Auto') { [System.Windows.GridLength]::Auto }
        else { New-Object System.Windows.GridLength([double]$w) }
        [void]$g.ColumnDefinitions.Add($cd)
    }
    return $g
}

function Set-Col($element, [int]$col) { [System.Windows.Controls.Grid]::SetColumn($element, $col) }

function New-ColorBrush([string]$text, [switch]$Opaque) {
    $v = ConvertFrom-ColorText $text
    if (-not $v) { return $null }
    $a = if ($Opaque -or $v.Count -lt 4) { 255 } else { $v[3] }
    $brush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb($a, $v[0], $v[1], $v[2]))
    $brush.Freeze()
    return $brush
}

# Image without locking the file; decoded small for thumbnails
function Get-Bitmap([string]$path, [int]$width = 0) {
    if (-not $path) { return $null }
    try {
        $b = New-Object System.Windows.Media.Imaging.BitmapImage
        $b.BeginInit()
        $b.CacheOption = 'OnLoad'
        $b.CreateOptions = 'IgnoreImageCache'
        $b.UriSource = New-Object System.Uri($path)
        if ($width -gt 0) { $b.DecodePixelWidth = $width }
        $b.EndInit()
        $b.Freeze()
        return $b
    } catch { return $null }
}

function Select-File([string]$filter) {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = $filter
    if ($dlg.ShowDialog($win)) { return $dlg.FileName }
    return $null
}
$imageFilter = 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.ico|All files|*.*'

# Windows colour picker; returns the colour in the format of 'old', or $null
function Select-Color([string]$old) {
    $dlg = New-Object System.Windows.Forms.ColorDialog
    $dlg.FullOpen = $true
    $v = ConvertFrom-ColorText $old
    if ($v) { $dlg.Color = [System.Drawing.Color]::FromArgb(255, $v[0], $v[1], $v[2]) }
    if ($dlg.ShowDialog() -ne 'OK') { return $null }
    return (Format-PickedColor $old $dlg.Color.R $dlg.Color.G $dlg.Color.B)
}

# Dialog in the window's style: message, optional text field, buttons (the
# first is the default). Returns @{ Button = <text or $null>; Text = <field> }
function Show-Dialog([string]$title, [string]$message, [string[]]$buttons = @('OK'), $inputText = $null) {
    $d = New-Object System.Windows.Window
    $d.Title = $title
    $d.Owner = $win
    $d.WindowStartupLocation = 'CenterOwner'
    $d.SizeToContent = 'WidthAndHeight'
    $d.ResizeMode = 'NoResize'
    $d.ShowInTaskbar = $false
    $d.Background = Res 'CardBg'
    $d.Foreground = Res 'TextBrush'
    $d.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
    $d.FontSize = 13
    $d.Tag = @{ Result = $null }
    $d.Add_SourceInitialized({ param($s, $e) Set-DarkTitle $s })

    $sp = New-Panel
    $sp.Margin = T 24 20 24 18
    $sp.MinWidth = 380
    $sp.MaxWidth = 520
    $d.Content = $sp
    [void](Add-To $sp (New-Text $message 13.5 -Wrap))
    $tb = $null
    if ($null -ne $inputText) {
        $tb = New-Object System.Windows.Controls.TextBox
        $tb.Text = $inputText
        $tb.Margin = T 0 14 0 0
        [void](Add-To $sp $tb)
    }
    $bar = New-Panel 'Horizontal'
    $bar.HorizontalAlignment = 'Right'
    $bar.Margin = T 0 20 0 0
    [void](Add-To $sp $bar)
    for ($i = 0; $i -lt $buttons.Count; $i++) {
        $b = New-Button $buttons[$i] $(if ($i -eq 0) { 'AccentButton' } else { '' })
        $b.Margin = T 8 0 0 0
        $b.MinWidth = 90
        $b.Tag = $buttons[$i]
        if ($i -eq 0) { $b.IsDefault = $true }
        $b.Add_Click({
                param($s, $e)
                $w = [System.Windows.Window]::GetWindow($s)
                $w.Tag.Result = $s.Tag
                $w.Close()
            })
        [void](Add-To $bar $b)
    }
    $d.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $s.Close() } })
    if ($tb) { $d.Add_ContentRendered({ param($s, $e) $s.Content.Children[1].Focus(); $s.Content.Children[1].SelectAll() }) }
    [void]$d.ShowDialog()
    return @{ Button = $d.Tag.Result; Text = $(if ($tb) { $tb.Text.Trim() } else { $null }) }
}

# --- Window ------------------------------------------------------------------

$version = ''
try {
    $m = [regex]::Match([IO.File]::ReadAllText((Join-Path (Split-Path -Parent $Resources) 'Raintile.ini')), '(?m)^\s*Version\s*=\s*(.+?)\s*$')
    if ($m.Success) { $version = 'v' + $m.Groups[1].Value }
} catch { }

$win = [System.Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Raintile - Options" Width="1180" Height="800" MinWidth="960" MinHeight="580"
        WindowStartupLocation="CenterScreen" Background="{StaticResource Bg}" Foreground="{StaticResource TextBrush}"
        FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="236"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>
    <Border Background="{StaticResource SideBg}" BorderBrush="{StaticResource LineBrush}" BorderThickness="0,0,1,0">
      <DockPanel Margin="12,20,12,14">
        <StackPanel DockPanel.Dock="Top" Margin="10,0,0,20">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="Raintile" FontSize="21" FontWeight="SemiBold"/>
            <Border Background="{StaticResource AccentSoftBrush}" CornerRadius="4" Padding="6,1" Margin="10,3,0,0"
                    VerticalAlignment="Center" ToolTip="Work in progress: this window is still being developed.">
              <TextBlock Text="WIP" Foreground="{StaticResource AccentBrush}" FontSize="10.5" FontWeight="SemiBold"/>
            </Border>
          </StackPanel>
          <TextBlock x:Name="Version" Foreground="{StaticResource DimBrush}" FontSize="12" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel x:Name="Links" DockPanel.Dock="Bottom" Margin="0,10,0,0"/>
        <ListBox x:Name="Nav"/>
      </DockPanel>
    </Border>
    <Grid Grid.Column="1">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel Margin="36,24,36,14">
        <TextBlock x:Name="PageTitle" FontSize="24" FontWeight="SemiBold"/>
        <TextBlock x:Name="PageDesc" Foreground="{StaticResource DimBrush}" Margin="0,5,0,0" TextWrapping="Wrap" MaxWidth="820" HorizontalAlignment="Left"/>
      </StackPanel>
      <Grid x:Name="PageHost" Grid.Row="1"/>
      <Border Grid.Row="2" BorderBrush="{StaticResource LineBrush}" BorderThickness="0,1,0,0" Padding="28,12">
        <DockPanel>
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
            <Button x:Name="BtnClose" Content="Close" MinWidth="90"/>
            <Button x:Name="BtnSave" Content="Save and refresh" Style="{StaticResource AccentButton}" Margin="10,0,0,0"
                    ToolTip="Ctrl+S"/>
          </StackPanel>
          <TextBlock x:Name="Status" VerticalAlignment="Center" Foreground="{StaticResource DimBrush}"/>
        </DockPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@)
$win.FindName('Version').Text = $version
$nav = $win.FindName('Nav')
$pageHost = $win.FindName('PageHost')
$pageTitle = $win.FindName('PageTitle')
$pageDesc = $win.FindName('PageDesc')
$status = $win.FindName('Status')
$btnSave = $win.FindName('BtnSave')

# --- Values ---------------------------------------------------------------------

$settings = Read-Settings $settingsFile
$fileValues = @{}   # as in Settings.inc
$values = @{}       # as in the window
foreach ($item in $settings) { $fileValues[$item.Key] = $item.Value; $values[$item.Key] = $item.Value }
$ctl = @{}          # key -> controls of that setting
$resets = New-Object System.Collections.ArrayList # @{ KeyList; Button }
$keyButtons = @{}   # key -> key capture button (for conflicts)
$script:updating = $true
$script:capturing = $null
$script:dirtySettings = $false
$screenPx = Get-ScreenPixels

$models = @{}       # category file -> model (loaded when needed)
$changedFiles = @{} # modified category files
$logoColors = Read-LogoColors

function Update-Dirty {
    $changed = @($values.Keys | Where-Object { $values[$_] -ne $fileValues[$_] })
    $dirty = $changed.Count -gt 0 -or $changedFiles.Count -gt 0
    $script:dirtySettings = $dirty
    $status.Text = if ($dirty) { 'Unsaved changes' } else { '' }
    $status.Foreground = if ($dirty) { Res 'AccentBrush' } else { Res 'DimBrush' }
    $win.Title = if ($dirty) { 'Raintile - Options *' } else { 'Raintile - Options' }
}

function Update-Resets {
    foreach ($r in $resets) {
        $differs = $false
        foreach ($k in $r.KeyList) { if ($defaults.ContainsKey($k) -and $values[$k] -ne $defaults[$k]) { $differs = $true } }
        $r.Button.Visibility = if ($differs) { 'Visible' } else { 'Hidden' }
    }
}

# The same key used by two actions: both are marked
function Update-KeyConflicts {
    $byKey = @{}
    foreach ($k in $keyButtons.Keys) {
        if ($k -eq 'OpenHotKey') { continue }
        $v = "$($values[$k])".Trim().ToUpperInvariant()
        if (-not $v) { continue }
        if (-not $byKey.ContainsKey($v)) { $byKey[$v] = @() }
        $byKey[$v] += $k
    }
    foreach ($k in $keyButtons.Keys) {
        $b = $keyButtons[$k]
        $v = "$($values[$k])".Trim().ToUpperInvariant()
        $others = if ($v -and $byKey.ContainsKey($v)) { @($byKey[$v] | Where-Object { $_ -ne $k }) } else { @() }
        if ($others.Count) {
            $b.BorderBrush = Res 'DangerBrush'
            $b.ToolTip = "Also used by: $($others -join ', ')"
        } else {
            $b.ClearValue([System.Windows.Controls.Control]::BorderBrushProperty)
            $b.ToolTip = 'Click, then press a key'
        }
    }
}

function Set-Value([string]$key, [string]$value) {
    if ($script:updating) { return }
    $values[$key] = $value
    Update-Dirty
    Update-Resets
    if ($keyButtons.ContainsKey($key)) { Update-KeyConflicts }
}

# Shows the current value of 'key' in its controls (after a reset)
function Update-Control([string]$key) {
    $c = $ctl[$key]
    if (-not $c) { return }
    $v = "$($values[$key])"
    $script:updating = $true
    try {
        switch ($c.Kind) {
            'bool' { $c.Box.IsChecked = ($v -eq '1') }
            'choice' { foreach ($rb in $c.Panel.Children) { $rb.IsChecked = ($rb.Tag[1] -ieq $v) } }
            { $_ -in 'int', 'float' } {
                $c.Text.Text = $v
                $n = 0.0
                if ([double]::TryParse($v, 'Float', [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
                    $c.Slider.Value = [Math]::Min($c.Slider.Maximum, [Math]::Max($c.Slider.Minimum, $n))
                }
            }
            'size' {
                $pct = $v.Trim().EndsWith('%')
                $c.Text.Text = $v.Trim().TrimEnd('%').Trim()
                $c.Pct.IsChecked = $pct
                $c.Px.IsChecked = -not $pct
            }
            'color' { $c.Text.Text = $v; $c.Swatch.Background = New-ColorBrush $v -Opaque }
            { $_ -in 'text', 'font' } { $c.Box.Text = $v }
            'category' { $c.Box.SelectedItem = $v }
            'stores' { foreach ($cb in $c.Panel.Children) { $cb.IsChecked = (@($v -split '\|') -contains $cb.Tag[1]) } }
            'pad' { foreach ($tb in $c.Panel.Children) { $tb.IsChecked = (@($v -split '\s+') -contains $tb.Tag[1]) } }
            { $_ -in 'key', 'combo' } { $c.Button.Content = Format-HotKey $v }
            'screen' {
                $sa = ConvertFrom-ScreenArea $values
                if ($sa) {
                    foreach ($rb in $c.Area.Children) { $rb.IsChecked = ($rb.Tag[1] -eq $sa.Area) }
                    foreach ($rb in @($c.Monitor.Children | Where-Object { $_ -is [System.Windows.Controls.RadioButton] })) { $rb.IsChecked = ($rb.Tag[1] -eq $sa.Monitor) }
                }
            }
        }
    } finally { $script:updating = $false }
}

# --- Controls for each kind of setting --------------------------------------------

function New-BoolControl([string]$key) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Tag = $key
    $cb.IsChecked = ($values[$key] -eq '1')
    $cb.Add_Click({ param($s, $e) Set-Value $s.Tag $(if ($s.IsChecked) { '1' } else { '0' }) })
    $ctl[$key] = @{ Kind = 'bool'; Box = $cb }
    return $cb
}

function New-ChoiceControl([string]$key, $choices) {
    $wp = New-Object System.Windows.Controls.WrapPanel
    $wp.MaxWidth = 460
    $wp.HorizontalAlignment = 'Right'
    foreach ($c in $choices) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = Res 'Segment'
        $rb.Content = $c[1]
        $rb.GroupName = "choice_$key"
        $rb.Tag = @($key, $c[0])
        $rb.IsChecked = ("$($values[$key])" -ieq $c[0])
        $rb.Add_Click({ param($s, $e) Set-Value $s.Tag[0] $s.Tag[1] })
        [void]$wp.Children.Add($rb)
    }
    $ctl[$key] = @{ Kind = 'choice'; Panel = $wp }
    return $wp
}

function New-NumberControl($item) {
    $key = $item.Key
    $sp = New-Panel 'Horizontal'
    $sl = New-Object System.Windows.Controls.Slider
    $sl.Width = 220
    $sl.Minimum = $item.Min
    $sl.Maximum = $item.Max
    $sl.TickFrequency = $item.Step
    $sl.SmallChange = $item.Step
    $sl.LargeChange = $item.Step
    $sl.Tag = $key
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Width = 72
    $tb.Margin = T 12 0 0 0
    $tb.TextAlignment = 'Right'
    $tb.Tag = $key
    $tb.Text = "$($values[$key])"
    $n = 0.0
    if ([double]::TryParse("$($values[$key])", 'Float', [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
        $sl.Value = [Math]::Min($item.Max, [Math]::Max($item.Min, $n))
    }
    $unit = New-Text $item.Unit 12 (Res 'DimBrush')
    $unit.Width = 40
    $unit.Margin = T 8 0 0 0
    $unit.VerticalAlignment = 'Center'
    [void](Add-To $sp $sl); [void](Add-To $sp $tb); [void](Add-To $sp $unit)
    $ctl[$key] = @{ Kind = $item.Kind; Slider = $sl; Text = $tb; Step = $item.Step }

    $sl.Add_ValueChanged({
            param($s, $e)
            if ($script:updating) { return }
            $c = $ctl[$s.Tag]
            $txt = Format-Number $s.Value $c.Step
            $script:updating = $true
            $c.Text.Text = $txt
            $script:updating = $false
            Set-Value $s.Tag $txt
        })
    $tb.Add_TextChanged({
            param($s, $e)
            if ($script:updating) { return }
            $c = $ctl[$s.Tag]
            $t = $s.Text.Trim()
            $n = 0.0
            if ($t -ne '' -and -not [double]::TryParse($t, 'Float', [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return }
            if ($t -ne '') {
                $script:updating = $true
                $c.Slider.Value = [Math]::Min($c.Slider.Maximum, [Math]::Max($c.Slider.Minimum, $n))
                $script:updating = $false
            }
            Set-Value $s.Tag $t
        })
    return $sp
}

function New-SizeControl($item) {
    $key = $item.Key
    $v = "$($values[$key])".Trim()
    $sp = New-Panel 'Horizontal'
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Width = 80
    $tb.TextAlignment = 'Right'
    $tb.Margin = T 0 0 10 0
    $tb.Tag = $key
    $tb.Text = $v.TrimEnd('%').Trim()
    $px = New-Object System.Windows.Controls.RadioButton
    $pct = New-Object System.Windows.Controls.RadioButton
    foreach ($p in @(@($px, 'px'), @($pct, '%'))) {
        $p[0].Style = Res 'Segment'
        $p[0].Content = $p[1]
        $p[0].GroupName = "size_$key"
        $p[0].Tag = $key
        $p[0].MinWidth = 42
    }
    $isPct = $v.EndsWith('%')
    $pct.IsChecked = $isPct
    $px.IsChecked = -not $isPct
    [void](Add-To $sp $tb); [void](Add-To $sp $px); [void](Add-To $sp $pct)
    $ctl[$key] = @{ Kind = 'size'; Text = $tb; Px = $px; Pct = $pct; Axis = $item.Axis }

    $tb.Add_TextChanged({
            param($s, $e)
            if ($script:updating) { return }
            $c = $ctl[$s.Tag]
            Set-Value $s.Tag ($s.Text.Trim() + $(if ($c.Pct.IsChecked) { '%' } else { '' }))
        })
    # switching unit converts the number (on the main screen)
    foreach ($rb in $px, $pct) {
        $rb.Add_Click({
                param($s, $e)
                $c = $ctl[$s.Tag]
                $toPct = [bool]$c.Pct.IsChecked
                $full = if ($c.Axis -eq 'W') { $screenPx.W } else { $screenPx.H }
                $n = 0.0
                $t = $c.Text.Text.Trim()
                if ($full -gt 0 -and [double]::TryParse($t, 'Float', [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
                    $t = if ($toPct) { Format-Number ($n * 100 / $full) 0.01 } else { Format-Number ($n * $full / 100) 1 }
                }
                $script:updating = $true
                $c.Text.Text = $t
                $script:updating = $false
                Set-Value $s.Tag ($t + $(if ($toPct) { '%' } else { '' }))
            })
    }
    return $sp
}

function New-ColorControl([string]$key) {
    $sp = New-Panel 'Horizontal'
    $sw = New-Button '' 'Swatch' 'Pick a colour'
    $sw.Background = New-ColorBrush "$($values[$key])" -Opaque
    $sw.Tag = $key
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Width = 170
    $tb.Margin = T 10 0 0 0
    $tb.Tag = $key
    $tb.Text = "$($values[$key])"
    [void](Add-To $sp $sw); [void](Add-To $sp $tb)
    $ctl[$key] = @{ Kind = 'color'; Swatch = $sw; Text = $tb }
    $sw.Add_Click({
            param($s, $e)
            $c = $ctl[$s.Tag]
            $new = Select-Color $c.Text.Text
            if ($new) { $c.Text.Text = $new }
        })
    $tb.Add_TextChanged({
            param($s, $e)
            if ($script:updating) { return }
            $c = $ctl[$s.Tag]
            $brush = New-ColorBrush $s.Text -Opaque
            if ($brush) {
                $c.Swatch.Background = $brush
                $s.ClearValue([System.Windows.Controls.Control]::BorderBrushProperty)
                Set-Value $s.Tag $s.Text.Trim()
            } else {
                $s.BorderBrush = Res 'DangerBrush'
            }
        })
    return $sp
}

function New-TextControl([string]$key, [double]$width = 300) {
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Width = $width
    $tb.Tag = $key
    $tb.Text = "$($values[$key])"
    $tb.Add_TextChanged({ param($s, $e) Set-Value $s.Tag $s.Text.Trim() })
    $ctl[$key] = @{ Kind = 'text'; Box = $tb }
    return $tb
}

function New-FontControl([string]$key) {
    $cb = New-Object System.Windows.Controls.ComboBox
    $cb.Width = 300
    $cb.IsEditable = $true
    $cb.Tag = $key
    foreach ($f in ([System.Windows.Media.Fonts]::SystemFontFamilies | ForEach-Object { $_.Source } | Sort-Object -Unique)) {
        [void]$cb.Items.Add($f)
    }
    $cb.Text = "$($values[$key])"
    $cb.AddHandler([System.Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,
        [System.Windows.Controls.TextChangedEventHandler] { param($s, $e) Set-Value $s.Tag $s.Text.Trim() })
    $ctl[$key] = @{ Kind = 'font'; Box = $cb }
    return $cb
}

function New-CategoryControl([string]$key) {
    $cb = New-Object System.Windows.Controls.ComboBox
    $cb.Width = 220
    $cb.Tag = $key
    $names = @(Get-CategoryFiles | ForEach-Object { $_.BaseName })
    if ($values[$key] -and $names -notcontains $values[$key]) { $names += $values[$key] }
    foreach ($n in $names) { [void]$cb.Items.Add($n) }
    $cb.SelectedItem = "$($values[$key])"
    $cb.Add_SelectionChanged({ param($s, $e) if ($s.SelectedItem) { Set-Value $s.Tag ([string]$s.SelectedItem) } })
    $ctl[$key] = @{ Kind = 'category'; Box = $cb }
    return $cb
}

function New-StoresControl([string]$key) {
    $wp = New-Object System.Windows.Controls.WrapPanel
    $current = @("$($values[$key])" -split '\|' | ForEach-Object { $_.Trim() })
    foreach ($store in $STORES) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $store
        $cb.Margin = T 18 4 0 4
        $cb.Tag = @($key, $store)
        $cb.IsChecked = ($current -contains $store)
        $cb.Add_Click({
                param($s, $e)
                $c = $ctl[$s.Tag[0]]
                $on = @($c.Panel.Children | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag[1] })
                Set-Value $s.Tag[0] ($on -join '|')
            })
        [void]$wp.Children.Add($cb)
    }
    $ctl[$key] = @{ Kind = 'stores'; Panel = $wp }
    return $wp
}

function New-PadControl([string]$key) {
    $wp = New-Object System.Windows.Controls.WrapPanel
    $wp.MaxWidth = 470
    $wp.HorizontalAlignment = 'Right'
    $current = @("$($values[$key])".ToUpperInvariant() -split '\s+')
    foreach ($b in $GAMEPAD_BUTTONS) {
        $tb = New-Object System.Windows.Controls.Primitives.ToggleButton
        $tb.Style = Res 'Segment'
        $tb.Content = $b
        $tb.Tag = @($key, $b)
        $tb.IsChecked = ($current -contains $b)
        $tb.Add_Click({
                param($s, $e)
                $c = $ctl[$s.Tag[0]]
                $on = @($c.Panel.Children | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag[1] })
                Set-Value $s.Tag[0] ($on -join ' ')
            })
        [void]$wp.Children.Add($tb)
    }
    $ctl[$key] = @{ Kind = 'pad'; Panel = $wp }
    return $wp
}

# Key binding: click, then press the key (with the modifiers for 'combo')
function New-KeyControl([string]$key, [bool]$combo = $false) {
    $sp = New-Panel 'Horizontal'
    $b = New-Button (Format-HotKey "$($values[$key])") 'KeyButton' 'Click, then press a key'
    $b.Tag = @{ Key = $key; Combo = $combo }
    $clear = New-IconButton 0xE711 'No key'
    $clear.Tag = $key
    [void](Add-To $sp $b); [void](Add-To $sp $clear)
    $ctl[$key] = @{ Kind = $(if ($combo) { 'combo' } else { 'key' }); Button = $b }
    $keyButtons[$key] = $b

    $b.Add_Click({
            param($s, $e)
            $script:capturing = $s
            $s.Content = 'Press a key' + [char]0x2026
            [void]$s.Focus()
        })
    $b.Add_LostKeyboardFocus({
            param($s, $e)
            if ($script:capturing -eq $s) {
                $script:capturing = $null
                $s.Content = Format-HotKey "$($values[$s.Tag.Key])"
            }
        })
    $b.Add_PreviewKeyDown({
            param($s, $e)
            if ($script:capturing -ne $s) { return }
            $e.Handled = $true
            $k = if ($e.Key -eq 'System') { $e.SystemKey } else { $e.Key }
            $vk = [System.Windows.Input.KeyInterop]::VirtualKeyFromKey($k)
            $mods = [System.Windows.Input.Keyboard]::Modifiers
            $ctrl = ($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
            $alt = ($mods -band [System.Windows.Input.ModifierKeys]::Alt) -ne 0
            $shift = ($mods -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0
            $winKey = ($mods -band [System.Windows.Input.ModifierKeys]::Windows) -ne 0
            if ($s.Tag.Combo) {
                $value = ConvertTo-HotKey $vk $ctrl $alt $shift $winKey -Combo
                if (-not $value) {
                    # modifiers only so far: show them and wait for the key
                    $held = @()
                    if ($ctrl) { $held += 'CTRL' }; if ($alt) { $held += 'ALT' }; if ($shift) { $held += 'SHIFT' }; if ($winKey) { $held += 'LWIN' }
                    if ($held.Count) { $s.Content = (Format-HotKey ($held -join ' ')) + ' + ' + [char]0x2026 }
                    return
                }
            } else {
                $value = ConvertTo-HotKey $vk
                if (-not $value) { return }
            }
            $script:capturing = $null
            $s.Content = Format-HotKey $value
            Set-Value $s.Tag.Key $value
        })
    $clear.Add_Click({
            param($s, $e)
            Set-Value $s.Tag ''
            Update-Control $s.Tag
        })
    return $sp
}

function New-ScreenControl {
    $sa = ConvertFrom-ScreenArea $values
    $sp = New-Panel
    $sp.HorizontalAlignment = 'Right'
    $area = New-Object System.Windows.Controls.WrapPanel
    $area.HorizontalAlignment = 'Right'
    $mon = New-Object System.Windows.Controls.WrapPanel
    $mon.HorizontalAlignment = 'Right'
    $mon.Margin = T 0 6 0 0
    foreach ($a in @(@('SCREENAREA', 'Whole screen'), @('WORKAREA', 'Work area'))) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = Res 'Segment'; $rb.Content = $a[1]; $rb.GroupName = 'screen_area'; $rb.Tag = @('area', $a[0])
        $rb.IsChecked = ($sa.Area -eq $a[0])
        [void]$area.Children.Add($rb)
    }
    $monLabel = New-Text 'Monitor' 12 (Res 'DimBrush')
    $monLabel.Margin = T 0 0 10 0
    $monLabel.VerticalAlignment = 'Center'
    [void](Add-To $mon $monLabel)
    foreach ($m in @(@('', 'Main'), @('1', '1'), @('2', '2'), @('3', '3'), @('4', '4'))) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = Res 'Segment'; $rb.Content = $m[1]; $rb.GroupName = 'screen_monitor'; $rb.Tag = @('monitor', $m[0])
        $rb.MinWidth = 38
        $rb.IsChecked = ($sa.Monitor -eq $m[0])
        [void]$mon.Children.Add($rb)
    }
    [void](Add-To $sp $area); [void](Add-To $sp $mon)
    $ctl['ScreenX'] = @{ Kind = 'screen'; Area = $area; Monitor = $mon }
    foreach ($rb in @($area.Children) + @($mon.Children | Where-Object { $_ -is [System.Windows.Controls.RadioButton] })) {
        $rb.Add_Click({
                param($s, $e)
                $c = $ctl['ScreenX']
                $a = ($c.Area.Children | Where-Object { $_.IsChecked } | Select-Object -First 1).Tag[1]
                $m = ($c.Monitor.Children | Where-Object { $_ -is [System.Windows.Controls.RadioButton] -and $_.IsChecked } | Select-Object -First 1).Tag[1]
                $new = ConvertTo-ScreenArea $a $m
                foreach ($k in $new.Keys) { $values[$k] = $new[$k] }
                Set-Value 'ScreenX' $new['ScreenX']
            })
    }
    $ctl['ScreenY'] = $ctl['ScreenX']; $ctl['ScreenW'] = $ctl['ScreenX']; $ctl['ScreenH'] = $ctl['ScreenX']
    return $sp
}

function New-ActionControl([string]$action, [string]$label) {
    $b = New-Button $label $(if ($action -eq 'Import') { 'AccentButton' } else { '' })
    $b.Tag = $action
    $b.Add_Click({ param($s, $e) Invoke-Action $s.Tag })
    return $b
}

# --- Rows, cards, pages -----------------------------------------------------------

function New-ResetButton([string[]]$keys) {
    $b = New-IconButton 0xE7A7 'Restore default'
    $b.Margin = T 6 0 0 0
    $b.VerticalAlignment = 'Center'
    $b.Tag = $keys
    $b.Visibility = 'Hidden'
    $b.Add_Click({
            param($s, $e)
            foreach ($k in $s.Tag) { if ($defaults.ContainsKey($k)) { $values[$k] = $defaults[$k] } }
            foreach ($k in $s.Tag) { Update-Control $k }
            Update-Dirty
            Update-Resets
            Update-KeyConflicts
        })
    [void]$resets.Add(@{ KeyList = $keys; Button = $b })
    return $b
}

function New-Row([string]$label, [string]$help, $control, $reset) {
    $g = New-Grid @('*', 'Auto', '34')
    $g.Margin = T 0 11
    $left = New-Panel
    $left.VerticalAlignment = 'Center'
    $left.Margin = T 0 0 24 0
    [void](Add-To $left (New-Text $label 13.5))
    if ($help) {
        $h = New-Text $help 12 (Res 'DimBrush') -Wrap
        $h.Margin = T 0 3 0 0
        [void](Add-To $left $h)
    }
    [void]$g.Children.Add($left)
    if ($control) {
        $control.VerticalAlignment = 'Center'
        Set-Col $control 1
        [void]$g.Children.Add($control)
    }
    if ($reset) { Set-Col $reset 2; [void]$g.Children.Add($reset) }
    $b = New-Object System.Windows.Controls.Border
    $b.BorderBrush = Res 'LineBrush'
    $b.BorderThickness = T 0 1 0 0
    $b.Child = $g
    return $b
}

function New-Card([string]$title, [string]$help) {
    $b = New-Object System.Windows.Controls.Border
    $b.Style = Res 'Card'
    $sp = New-Panel
    $b.Child = $sp
    if ($title) {
        $h = New-Text $title.ToUpperInvariant() 11.5 (Res 'DimBrush') -Bold
        $h.Margin = T 0 12 0 4
        [void](Add-To $sp $h)
    }
    if ($help) {
        $x = New-Text $help 12 (Res 'DimBrush') -Wrap
        $x.Margin = T 0 0 0 8
        [void](Add-To $sp $x)
    }
    return $b
}

# Row of one schema item ($null if its settings are not in Settings.inc)
function New-ItemRow($item) {
    $k = $item.Key
    switch ($item.Kind) {
        'info' { return (New-Row $item.Label $item.Help $null $null) }
        'action' {
            $label = if ($item.Key -eq 'Import') { 'Import games' } else { 'Open' }
            return (New-Row $item.Label $item.Help (New-ActionControl $item.Key $label) $null)
        }
        'screen' {
            if (-not ($values.ContainsKey('ScreenX') -and $values.ContainsKey('ScreenY') -and $values.ContainsKey('ScreenW') -and $values.ContainsKey('ScreenH'))) { return $null }
            if (-not (ConvertFrom-ScreenArea $values)) {
                # custom values (formulas, coordinates): plain fields
                $sp = New-Panel
                foreach ($sk in 'ScreenX', 'ScreenY', 'ScreenW', 'ScreenH') {
                    $row = New-Panel 'Horizontal'
                    $row.Margin = T 0 2
                    $l = New-Text $sk 12 (Res 'DimBrush'); $l.Width = 64; $l.VerticalAlignment = 'Center'
                    [void](Add-To $row $l); [void](Add-To $row (New-TextControl $sk 230))
                    [void](Add-To $sp $row)
                }
                return (New-Row $item.Label 'Custom values: written as they are.' $sp (New-ResetButton @('ScreenX', 'ScreenY', 'ScreenW', 'ScreenH')))
            }
            return (New-Row $item.Label $item.Help (New-ScreenControl) (New-ResetButton @('ScreenX', 'ScreenY', 'ScreenW', 'ScreenH')))
        }
        'keys' {
            $present = @($item.Pair | Where-Object { $values.ContainsKey($_) })
            if (-not $present.Count) { return $null }
            $sp = New-Panel 'Horizontal'
            foreach ($kk in $present) {
                $kc = New-KeyControl $kk
                $kc.Margin = T 6 0 0 0
                [void](Add-To $sp $kc)
            }
            return (New-Row $item.Label $item.Help $sp (New-ResetButton $present))
        }
    }
    if (-not $values.ContainsKey($k)) { return $null }
    $control = switch ($item.Kind) {
        'bool' { New-BoolControl $k }
        'choice' {
            if (@($item.Choices | ForEach-Object { $_[0] }) -contains "$($values[$k])") { New-ChoiceControl $k $item.Choices }
            else { New-TextControl $k }   # a value of its own: plain field
        }
        { $_ -in 'int', 'float' } { New-NumberControl $item }
        'size' {
            if ("$($values[$k])" -match '^\s*-?[\d.]+\s*%?\s*$') { New-SizeControl $item } else { New-TextControl $k }
        }
        'color' { New-ColorControl $k }
        'text' { New-TextControl $k }
        'font' { New-FontControl $k }
        'category' { New-CategoryControl $k }
        'stores' { New-StoresControl $k }
        'pad' { New-PadControl $k }
        'key' { New-KeyControl $k }
        'combo' { New-KeyControl $k $true }
    }
    return (New-Row $item.Label $item.Help $control (New-ResetButton @($k)))
}

function New-SettingsPage($page) {
    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'
    $sp = New-Panel
    $sp.Margin = T 36 4 36 24
    $sp.MaxWidth = 920
    $sp.HorizontalAlignment = 'Left'
    $sv.Content = $sp
    $schemaKeys = Get-SchemaKeys
    foreach ($group in $page.Groups) {
        $card = New-Card $group.Title $group.Help
        $rows = 0
        if ($group.Other) {
            # Settings.inc entries without a page of their own
            foreach ($item in $settings) {
                if ($schemaKeys -contains $item.Key) { continue }
                [void]$card.Child.Children.Add((New-Row $item.Key $item.Description (New-TextControl $item.Key) $null))
                $rows++
            }
        } else {
            foreach ($item in $group.Items) {
                $row = New-ItemRow $item
                if ($row) { [void]$card.Child.Children.Add($row); $rows++ }
            }
        }
        if ($rows) { [void](Add-To $sp $card) }
    }
    if ($page.Id -eq 'import') {
        $script:importResult = New-Text '' 12.5 (Res 'DimBrush') -Wrap
        $script:importResult.Margin = T 4 0 4 0
        [void](Add-To $sp $script:importResult)
    }
    return $sv
}

# --- Categories pages --------------------------------------------------------------

function Get-Model([string]$file) {
    if (-not $models.ContainsKey($file)) { $models[$file] = Read-Category (Join-Path $categoriesDir $file) }
    return $models[$file]
}
function Set-Changed([string]$file) { $changedFiles[$file] = $true; Update-Dirty }

$cat = @{}   # controls of the page
$script:loading = $false

# Square thumbnail: image (or colour) in a rounded box
function New-Thumb([double]$size) {
    $b = New-Object System.Windows.Controls.Border
    $b.Width = $size; $b.Height = $size
    $b.CornerRadius = New-Object System.Windows.CornerRadius(5)
    $b.Background = Res 'FieldBg'
    $img = New-Object System.Windows.Controls.Image
    $img.Stretch = 'Uniform'
    $img.Margin = T ([Math]::Round($size / 8))
    $b.Child = $img
    return $b
}
function Set-Thumb($thumb, [string]$path, $brush = $null) {
    $thumb.Child.Source = Get-Bitmap $path 96
    $thumb.Background = if ($brush) { $brush } else { Res 'FieldBg' }
}

function New-ListEntry([string]$title, [string]$sub, $tag, [double]$thumbSize = 30) {
    $item = New-Object System.Windows.Controls.ListBoxItem
    $sp = New-Panel 'Horizontal'
    $thumb = New-Thumb $thumbSize
    $thumb.Margin = T 0 0 10 0
    [void](Add-To $sp $thumb)
    $texts = New-Panel
    $texts.VerticalAlignment = 'Center'
    $t = New-Text $title 13
    $t.TextTrimming = 'CharacterEllipsis'
    [void](Add-To $texts $t)
    if ($sub) { [void](Add-To $texts (New-Text $sub 11 (Res 'DimBrush'))) }
    [void](Add-To $sp $texts)
    $item.Content = $sp
    $tag.Thumb = $thumb
    $tag.Title = $t
    $item.Tag = $tag
    return $item
}

$script:currentFile = $null  # category shown (chosen in the menu)
function Get-CurrentFile { return $script:currentFile }
function Get-CurrentBase { $f = Get-CurrentFile; if ($f) { return [IO.Path]::GetFileNameWithoutExtension($f) } return $null }
function Get-CurrentTile {
    $sel = $cat.Tiles.SelectedItem
    if (-not $sel -or $sel.Tag.Imported) { return $null }
    return $sel.Tag.Section
}

# Colour of a tile as the skin shows it
function Get-TileBrush([string]$base, $section, [string]$bg, [string]$logo) {
    $brush = New-ColorBrush (Get-Key $section 'Color')
    if ($brush) { return $brush }
    if ($values['AutoTileColor'] -eq '1' -and $logo -and -not $bg) {
        $c = $logoColors[[IO.Path]::GetFullPath($logo).ToLowerInvariant()]
        if ($c) { return (New-ColorBrush $c) }
    }
    $brush = New-ColorBrush "$($values['TileColor'])"
    if ($brush) { return $brush }
    return (Res 'FieldBg')
}

# Categories in menu order: File, Base, Name, Icon, Tiles, Imported
function Get-CategoryEntries {
    $entries = foreach ($f in Get-CategoryFiles) {
        $m = Get-Model $f.Name
        $c = Get-CategorySection $m
        $order = 0; [void][int]::TryParse((Get-Key $c 'Order'), [ref]$order)
        if (-not $order) { $order = 9999 }
        $name = Get-Key $c 'Name'; if (-not $name) { $name = $f.BaseName }
        [pscustomobject]@{
            File = $f.Name; Base = $f.BaseName; Order = $order; Name = $name; Icon = (Get-CategoryIcon $f.BaseName $c)
            Tiles = (Get-Tiles $m).Count; Imported = (Get-ImportedNames $m).Count
        }
    }
    return @($entries | Sort-Object Order, File)
}

# List of the Categories page
function Refresh-Cats([string]$selectFile = '') {
    if (-not $cat.Cats) { return }
    $cat.Cats.Items.Clear()
    $index = 0; $i = 0
    foreach ($e in Get-CategoryEntries) {
        $count = "$($e.Tiles) tile$(if ($e.Tiles -ne 1) { 's' })"
        if ($e.Imported) { $count += " + $($e.Imported) imported" }
        $item = New-ListEntry $e.Name "$($e.File)   $([char]0xB7)   $count" @{ File = $e.File } 36
        Set-Thumb $item.Tag.Thumb $e.Icon
        $item.Padding = T 12 9
        [void]$cat.Cats.Items.Add($item)
        if ($e.File -eq $selectFile) { $index = $i }
        $i++
    }
    if ($cat.Cats.Items.Count) { $cat.Cats.SelectedIndex = $index }
}

# Name and icon of a category in the menu and in the page title
function Update-NavCategory([string]$file) {
    $c = Get-CategorySection (Get-Model $file)
    $name = Get-Key $c 'Name'
    if (-not $name) { $name = [IO.Path]::GetFileNameWithoutExtension($file) }
    foreach ($it in $nav.Items) {
        if ($it.Tag.Id -eq "cat:$file") {
            $it.Tag.Title.Text = $name
            $it.Tag.Icon.Source = Get-Bitmap (Get-CategoryIcon ([IO.Path]::GetFileNameWithoutExtension($file)) $c) 40
        }
    }
    if ($script:currentFile -eq $file -and $script:navCurrent -eq "cat:$file") { $pageTitle.Text = $name }
}

function Update-TileEntry($item) {
    $base = Get-CurrentBase
    $s = $item.Tag.Section
    $bg = Get-TileImage $base $s 'Background'
    $logo = Get-TileImage $base $s 'Logo'
    $item.Tag.Title.Text = $s.Name
    Set-Thumb $item.Tag.Thumb $(if ($logo) { $logo } else { $bg }) (Get-TileBrush $base $s $bg $logo)
}

function Refresh-Tiles([int]$select = 0) {
    $cat.Tiles.Items.Clear()
    $file = Get-CurrentFile
    if ($file) {
        $m = Get-Model $file
        foreach ($s in Get-Tiles $m) {
            $item = New-ListEntry $s.Name '' @{ Section = $s; Imported = $false }
            [void]$cat.Tiles.Items.Add($item)
            Update-TileEntry $item
        }
        foreach ($n in Get-ImportedNames $m) {
            $item = New-ListEntry $n 'imported' @{ Section = $null; Imported = $true }
            $item.Opacity = 0.6
            [void]$cat.Tiles.Items.Add($item)
        }
    }
    if ($cat.Tiles.Items.Count) { $cat.Tiles.SelectedIndex = [Math]::Max(0, [Math]::Min($select, $cat.Tiles.Items.Count - 1)) }
    else { Show-Tile }
}

function Show-Category {
    if (-not $cat.Tiles) { return }
    $script:loading = $true
    $file = Get-CurrentFile
    $cat.CatCard.IsEnabled = [bool]$file
    $c = if ($file) { Get-CategorySection (Get-Model $file) } else { $null }
    foreach ($k in 'Name', 'NX', 'NY', 'IconSize') { $cat["cat.$k"].Text = if ($c) { Get-Key $c $k } else { '' } }
    Set-Thumb $cat.CatIcon $(if ($c) { Get-CategoryIcon (Get-CurrentBase) $c } else { $null })
    $cat.CatIconHint.Text = if ($file) { "Default: Images\$(Get-CurrentBase)\icon.png" } else { '' }
    $cat.GridHint.Text = "Empty = default ($($values['NX']) " + [char]0xD7 + " $($values['NY']), from Layout)"
    $cat.SizeHint.Text = "Pixels or %. Empty = default ($($values['IconSize']))"
    $script:loading = $false
    Refresh-Tiles
}

function Update-TilePreview {
    $s = Get-CurrentTile
    $base = Get-CurrentBase
    $bg = if ($s) { Get-TileImage $base $s 'Background' } else { $null }
    $logo = if ($s) { Get-TileImage $base $s 'Logo' } else { $null }
    $p = $cat.Preview
    $p.Background = if ($s) { Get-TileBrush $base $s $bg $logo } else { Res 'FieldBg' }
    $cat.PreviewBg.Source = Get-Bitmap $bg 480
    $cat.PreviewLogo.Source = Get-Bitmap $logo 256
    $label = if ($s) { Get-Key $s 'Label' } else { '' }
    if (-not $label -and $s -and -not $bg -and -not $logo) { $label = $s.Name }
    $cat.PreviewLabel.Text = $label
    $cat.PreviewLabel.Visibility = if ($label -and $values['ShowLabels'] -ne '0') { 'Visible' } else { 'Collapsed' }
    Set-Thumb $cat.BgThumb $bg
    Set-Thumb $cat.LogoThumb $logo
    $cat.BgPath.Text = if ($bg) { $bg } elseif ($s) { "None. Default: Images\$base\background\$($s.Name).jpg" } else { '' }
    $cat.LogoPath.Text = if ($logo) { $logo } elseif ($s) { "None. Default: Images\$base\logo\$($s.Name).png" } else { '' }
    $sw = New-ColorBrush $(if ($s) { Get-Key $s 'Color' } else { '' }) -Opaque
    $cat.ColorSwatch.Background = if ($sw) { $sw } else { Res 'FieldBg' }
    $sel = $cat.Tiles.SelectedItem
    if ($sel -and -not $sel.Tag.Imported) { Update-TileEntry $sel }
}

function Show-Tile {
    $script:loading = $true
    $s = Get-CurrentTile
    $sel = $cat.Tiles.SelectedItem
    $cat.TileCard.IsEnabled = [bool]$s
    foreach ($k in 'Command', 'Label', 'Color') { $cat["tile.$k"].Text = if ($s) { Get-Key $s $k } else { '' } }
    $cat['tile.Name'].Text = if ($s) { $s.Name } else { '' }
    $cat.Note.Text = if ($sel -and $sel.Tag.Imported) {
        'Imported game: it is rewritten on every import and cannot be edited here. To customise it, add a tile with the same name: the import will not duplicate it.'
    } elseif (-not $sel) { 'No tiles yet: add one with the + button.' } else { '' }
    $cat.Note.Visibility = if ($cat.Note.Text) { 'Visible' } else { 'Collapsed' }
    $script:loading = $false
    Update-TilePreview
}

function New-FormRow([string]$label, $control, [string]$hint = '', $hintBlock = $null) {
    $g = New-Grid @('118', '*')
    $g.Margin = T 0 7
    $l = New-Text $label 13 (Res 'DimBrush')
    $l.VerticalAlignment = 'Top'
    $l.Margin = T 0 6 0 0
    [void]$g.Children.Add($l)
    $sp = New-Panel
    [void](Add-To $sp $control)
    if (-not $hintBlock -and $hint) { $hintBlock = New-Text $hint 11.5 (Res 'DimBrush') -Wrap }
    if ($hintBlock) { $hintBlock.Margin = T 0 4 0 0; [void](Add-To $sp $hintBlock) }
    Set-Col $sp 1
    [void]$g.Children.Add($sp)
    return $g
}

function New-ListColumn([string]$title, $list, [object[]]$buttons) {
    $b = New-Object System.Windows.Controls.Border
    $b.Style = Res 'Card'
    $b.Padding = T 8 4 8 8
    $b.Margin = T 0 0 14 0
    $dp = New-Object System.Windows.Controls.DockPanel
    $b.Child = $dp
    $head = New-Grid @('*', 'Auto')
    $head.Margin = T 6 8 0 6
    [System.Windows.Controls.DockPanel]::SetDock($head, 'Top')
    $h = New-Text $title.ToUpperInvariant() 11.5 (Res 'DimBrush') -Bold
    $h.VerticalAlignment = 'Center'
    [void]$head.Children.Add($h)
    $bar = New-Panel 'Horizontal'
    foreach ($btn in $buttons) { [void](Add-To $bar $btn) }
    Set-Col $bar 1
    [void]$head.Children.Add($bar)
    [void]$dp.Children.Add($head)
    [void]$dp.Children.Add($list)
    return $b
}

# Categories page: the list of categories, to create, reorder and delete them
function New-CategoryListPage {
    $dp = New-Object System.Windows.Controls.DockPanel
    $dp.Margin = T 36 4 36 20
    $dp.MaxWidth = 760
    $dp.HorizontalAlignment = 'Left'
    $bar = New-Panel 'Horizontal'
    $bar.Margin = T 0 0 0 12
    [System.Windows.Controls.DockPanel]::SetDock($bar, 'Top')
    [void]$dp.Children.Add($bar)
    $btnCatNew = New-Button 'New category' 'AccentButton'
    $btnCatOpen = New-Button 'Open'
    $btnCatUp = New-Button 'Move up'
    $btnCatDown = New-Button 'Move down'
    $btnCatDel = New-Button 'Delete'
    $btnCatDel.Foreground = Res 'DangerBrush'
    foreach ($b in $btnCatNew, $btnCatOpen, $btnCatUp, $btnCatDown, $btnCatDel) { $b.Margin = T 0 0 8 0; [void](Add-To $bar $b) }
    $card = New-Object System.Windows.Controls.Border
    $card.Style = Res 'Card'
    $card.Padding = T 8
    $card.Margin = T 0
    $cat.Cats = New-Object System.Windows.Controls.ListBox
    $card.Child = $cat.Cats
    [void]$dp.Children.Add($card)

    $cat.Cats.Add_MouseDoubleClick({ if ($cat.Cats.SelectedItem) { Open-Category $cat.Cats.SelectedItem.Tag.File } })
    $cat.Cats.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return' -and $cat.Cats.SelectedItem) { Open-Category $cat.Cats.SelectedItem.Tag.File } })
    $btnCatOpen.Add_Click({ if ($cat.Cats.SelectedItem) { Open-Category $cat.Cats.SelectedItem.Tag.File } })

    $btnCatNew.Add_Click({
            $r = Show-Dialog 'New category' 'Name of the new category (e.g. Emulators):' @('Create', 'Cancel') ''
            if ($r.Button -ne 'Create' -or -not $r.Text) { return }
            $file = ($r.Text -replace '[^A-Za-z0-9_-]', '')
            if (-not $file) { [void](Show-Dialog 'Raintile' 'Use at least one letter or digit.'); return }
            if (Test-Path -LiteralPath (Join-Path $categoriesDir "$file.ini")) {
                [void](Show-Dialog 'Raintile' "The category '$file' already exists."); return
            }
            $m = [pscustomobject]@{ Header = '; Format: see Games.ini'; Sections = (New-Object System.Collections.ArrayList); Imported = '' }
            $c = Get-CategorySection $m
            Set-Key $c 'Name' $r.Text
            Set-Key $c 'Order' "$($cat.Cats.Items.Count + 1)"
            Write-Category (Join-Path $categoriesDir "$file.ini") $m
            foreach ($kind in 'background', 'logo') { New-Item -ItemType Directory -Force -Path (Join-Path $imagesRoot "$file\$kind") | Out-Null }
            $models["$file.ini"] = $m
            Refresh-Cats "$file.ini"
            Build-Nav $script:navCurrent
        })
    $btnCatDel.Add_Click({
            if (-not $cat.Cats.SelectedItem) { return }
            $file = $cat.Cats.SelectedItem.Tag.File
            $r = Show-Dialog 'Delete category' "Move the category $file to the Recycle Bin? Its images stay in Images." @('Delete', 'Cancel')
            if ($r.Button -ne 'Delete') { return }
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile((Join-Path $categoriesDir $file), 'OnlyErrorDialogs', 'SendToRecycleBin')
            $models.Remove($file); $changedFiles.Remove($file)
            if ($script:currentFile -eq $file) { $script:currentFile = $null }
            Update-Dirty
            Refresh-Cats
            Build-Nav $script:navCurrent
        })
    foreach ($pair in @(@($btnCatUp, -1), @($btnCatDown, 1))) {
        $pair[0].Tag = $pair[1]
        $pair[0].Add_Click({
                param($s, $e)
                $i = $cat.Cats.SelectedIndex; $j = $i + $s.Tag
                if ($i -lt 0 -or $j -lt 0 -or $j -ge $cat.Cats.Items.Count) { return }
                $files = @($cat.Cats.Items | ForEach-Object { $_.Tag.File })
                $tmp = $files[$i]; $files[$i] = $files[$j]; $files[$j] = $tmp
                for ($n = 0; $n -lt $files.Count; $n++) {
                    $c = Get-CategorySection (Get-Model $files[$n])
                    if ((Get-Key $c 'Order') -ne "$($n + 1)") { Set-Key $c 'Order' "$($n + 1)"; Set-Changed $files[$n] }
                }
                Refresh-Cats $files[$j]
                Build-Nav $script:navCurrent
            })
    }
    return $dp
}

# Page of one category (the same page for all: Show-Category fills it)
function New-CategoryPage {
    $grid = New-Grid @('300', '*')
    $grid.Margin = T 36 4 36 20

    # Column 1: tiles of the category
    $cat.Tiles = New-Object System.Windows.Controls.ListBox
    $btnTileNew = New-IconButton 0xE710 'New tile'
    $btnTileDel = New-IconButton 0xE74D 'Delete tile'
    $btnTileUp = New-IconButton 0xE70E 'Move up'
    $btnTileDown = New-IconButton 0xE70D 'Move down'
    $col = New-ListColumn 'Tiles' $cat.Tiles @($btnTileNew, $btnTileUp, $btnTileDown, $btnTileDel)
    [void]$grid.Children.Add($col)

    # Column 2: details
    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'
    Set-Col $sv 1
    [void]$grid.Children.Add($sv)
    $details = New-Panel
    $details.MaxWidth = 640
    $details.HorizontalAlignment = 'Left'
    $sv.Content = $details

    # Category card
    $card = New-Card 'Category' ''
    $cat.CatCard = $card
    [void](Add-To $details $card)
    $f = $card.Child
    foreach ($k in 'Name', 'NX', 'NY', 'IconSize') {
        $tb = New-Object System.Windows.Controls.TextBox
        $tb.Tag = $k
        $cat["cat.$k"] = $tb
    }
    $cat['cat.NX'].Width = 64; $cat['cat.NY'].Width = 64; $cat['cat.IconSize'].Width = 100
    [void](Add-To $f (New-FormRow 'Name' $cat['cat.Name'] 'Text shown in the menu.'))
    $iconRow = New-Panel 'Horizontal'
    $cat.CatIcon = New-Thumb 36
    $btnIcon = New-Button 'Choose...'
    $btnIcon.Margin = T 10 0 0 0
    $btnIconDel = New-Button 'Remove'
    $btnIconDel.Margin = T 6 0 0 0
    [void](Add-To $iconRow $cat.CatIcon); [void](Add-To $iconRow $btnIcon); [void](Add-To $iconRow $btnIconDel)
    $cat.CatIconHint = New-Text '' 11.5 (Res 'DimBrush') -Wrap
    [void](Add-To $f (New-FormRow 'Icon' $iconRow '' $cat.CatIconHint))
    $gridRow = New-Panel 'Horizontal'
    [void](Add-To $gridRow $cat['cat.NX'])
    $x = New-Text ([string][char]0xD7) 13 (Res 'DimBrush'); $x.Margin = T 8 0 8 0; $x.VerticalAlignment = 'Center'
    [void](Add-To $gridRow $x)
    [void](Add-To $gridRow $cat['cat.NY'])
    $cat.GridHint = New-Text '' 11.5 (Res 'DimBrush') -Wrap
    [void](Add-To $f (New-FormRow 'Grid' $gridRow '' $cat.GridHint))
    $cat.SizeHint = New-Text '' 11.5 (Res 'DimBrush') -Wrap
    [void](Add-To $f (New-FormRow 'Logo size' $cat['cat.IconSize'] '' $cat.SizeHint))

    # Tile card
    $card = New-Card 'Tile' ''
    $cat.TileCard = $card
    [void](Add-To $details $card)
    $f = $card.Child
    $cat.Note = New-Text '' 12.5 (Res 'AccentBrush') -Wrap
    $cat.Note.Margin = T 0 0 0 8
    [void](Add-To $f $cat.Note)

    # preview, as the tile looks in the launcher
    $p = New-Object System.Windows.Controls.Border
    $p.Width = 384; $p.Height = 216
    $p.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $p.HorizontalAlignment = 'Left'
    $p.Margin = T 0 4 0 10
    $p.ClipToBounds = $true
    $pg = New-Object System.Windows.Controls.Grid
    $p.Child = $pg
    $cat.PreviewBg = New-Object System.Windows.Controls.Image
    $cat.PreviewBg.Stretch = 'UniformToFill'
    $cat.PreviewLogo = New-Object System.Windows.Controls.Image
    $cat.PreviewLogo.Stretch = 'Uniform'
    $cat.PreviewLogo.MaxWidth = 140; $cat.PreviewLogo.MaxHeight = 90
    $cat.PreviewLabel = New-Text '' 14 (New-ColorBrush "$($values['TextColor'])")
    $cat.PreviewLabel.HorizontalAlignment = 'Left'; $cat.PreviewLabel.VerticalAlignment = 'Bottom'
    $cat.PreviewLabel.Margin = T 12 0 0 10
    $cat.PreviewLabel.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ BlurRadius = 6; ShadowDepth = 1; Opacity = 0.8 }
    [void]$pg.Children.Add($cat.PreviewBg); [void]$pg.Children.Add($cat.PreviewLogo); [void]$pg.Children.Add($cat.PreviewLabel)
    $cat.Preview = $p
    [void](Add-To $f $p)

    foreach ($k in 'Name', 'Command', 'Label', 'Color') {
        $tb = New-Object System.Windows.Controls.TextBox
        $tb.Tag = $k
        $cat["tile.$k"] = $tb
    }
    [void](Add-To $f (New-FormRow 'Name' $cat['tile.Name'] 'Also the name of its images and what search looks at.'))
    $cmdRow = New-Grid @('*', 'Auto')
    [void]$cmdRow.Children.Add($cat['tile.Command'])
    $btnCmd = New-Button 'Browse...'
    $btnCmd.Margin = T 8 0 0 0
    Set-Col $btnCmd 1
    [void]$cmdRow.Children.Add($btnCmd)
    [void](Add-To $f (New-FormRow 'Command' $cmdRow 'A program, a .lnk/.url shortcut, a URL (also steam://...), a folder or a Rainmeter bang.'))
    [void](Add-To $f (New-FormRow 'Label' $cat['tile.Label'] 'Text at the bottom left. Empty = none (tiles without images show their name).'))
    $colorRow = New-Panel 'Horizontal'
    $cat.ColorSwatch = New-Button '' 'Swatch' 'Pick a colour'
    $cat['tile.Color'].Width = 170
    $cat['tile.Color'].Margin = T 10 0 0 0
    [void](Add-To $colorRow $cat.ColorSwatch); [void](Add-To $colorRow $cat['tile.Color'])
    [void](Add-To $f (New-FormRow 'Colour' $colorRow 'Used when there is no background image. Empty = from the logo, or the default tile colour.'))
    foreach ($kind in 'Background', 'Logo') {
        $row = New-Panel 'Horizontal'
        $thumb = New-Thumb 44
        $choose = New-Button 'Choose...'
        $choose.Margin = T 10 0 0 0
        $choose.Tag = $kind
        $remove = New-Button 'Remove'
        $remove.Margin = T 6 0 0 0
        $remove.Tag = $kind
        [void](Add-To $row $thumb); [void](Add-To $row $choose); [void](Add-To $row $remove)
        $pathText = New-Text '' 11.5 (Res 'DimBrush') -Wrap
        [void](Add-To $f (New-FormRow $kind $row '' $pathText))
        $cat["${kind}Thumb".Replace('Background', 'Bg')] = $thumb
        $cat["${kind}Path".Replace('Background', 'Bg')] = $pathText
        $choose.Add_Click({
                param($s, $e)
                $t = Get-CurrentTile; if (-not $t) { return }
                $src = Select-File $imageFilter; if (-not $src) { return }
                [void](Copy-TileImage (Get-CurrentBase) $s.Tag.ToLowerInvariant() $t.Name $src)
                Set-Key $t $s.Tag ''   # the default image just copied applies
                Set-Changed (Get-CurrentFile)
                Update-TilePreview
            })
        $remove.Add_Click({
                param($s, $e)
                $t = Get-CurrentTile; if (-not $t) { return }
                $path = Get-TileImage (Get-CurrentBase) $t $s.Tag
                if ($path -and $path.StartsWith($imagesRoot, [StringComparison]::OrdinalIgnoreCase)) {
                    $r = Show-Dialog 'Raintile' "Move $([IO.Path]::GetFileName($path)) to the Recycle Bin?" @('Remove', 'Cancel')
                    if ($r.Button -ne 'Remove') { return }
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
                }
                Set-Key $t $s.Tag ''
                Set-Changed (Get-CurrentFile)
                Update-TilePreview
            })
    }

    # --- events
    $cat.Tiles.Add_SelectionChanged({ Show-Tile })

    foreach ($k in 'Name', 'NX', 'NY', 'IconSize') {
        $cat["cat.$k"].Add_TextChanged({
                param($s, $e)
                if ($script:loading) { return }
                $file = Get-CurrentFile; if (-not $file) { return }
                Set-Key (Get-CategorySection (Get-Model $file)) $s.Tag $s.Text.Trim()
                Set-Changed $file
                if ($s.Tag -eq 'Name') { Update-NavCategory $file }
            })
    }
    foreach ($k in 'Command', 'Label', 'Color') {
        $cat["tile.$k"].Add_TextChanged({
                param($s, $e)
                if ($script:loading) { return }
                $t = Get-CurrentTile; if (-not $t) { return }
                Set-Key $t $s.Tag $s.Text.Trim()
                Set-Changed (Get-CurrentFile)
                Update-TilePreview
            })
    }
    # renaming: checked when editing ends (duplicates); the images follow
    $cat['tile.Name'].Add_LostKeyboardFocus({
            param($s, $e)
            $t = Get-CurrentTile; if (-not $t) { return }
            $new = ($s.Text -replace '[\[\]]', '').Trim()
            if (-not $new -or $new -ceq $t.Name) { $s.Text = $t.Name; return }
            $m = Get-Model (Get-CurrentFile)
            if (($m.Sections | Where-Object { $_ -ne $t -and $_.Name -ieq $new }) -or ((Get-ImportedNames $m) -contains $new)) {
                [void](Show-Dialog 'Raintile' "There is already a tile called '$new'.")
                $s.Text = $t.Name; return
            }
            if (-not (Get-Key $t 'Image') -and $new -ine $t.Name) { Rename-TileImages (Get-CurrentBase) $t.Name $new }
            $t.Name = $new
            Set-Changed (Get-CurrentFile)
            Update-TilePreview
        })
    $cat['tile.Name'].Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { [void]$cat.Tiles.Focus() } })

    $btnCmd.Add_Click({
            $src = Select-File 'Programs and shortcuts|*.exe;*.lnk;*.url;*.bat;*.cmd|All files|*.*'
            if ($src) { $cat['tile.Command'].Text = '"' + $src + '"' }
        })
    $cat.ColorSwatch.Add_Click({
            if (-not (Get-CurrentTile)) { return }
            $new = Select-Color $cat['tile.Color'].Text
            if ($new) { $cat['tile.Color'].Text = $new }
        })
    $btnIcon.Add_Click({
            $file = Get-CurrentFile; if (-not $file) { return }
            $src = Select-File $imageFilter; if (-not $src) { return }
            $dir = Join-Path $imagesRoot (Get-CurrentBase)
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.BaseName -ieq 'icon' } | Remove-Item -Force
            Copy-Item -LiteralPath $src -Destination (Join-Path $dir ('icon' + [IO.Path]::GetExtension($src).ToLowerInvariant())) -Force
            Set-Key (Get-CategorySection (Get-Model $file)) 'Icon' ''   # the default icon just copied applies
            Set-Changed $file
            $icon = Get-CategoryIcon (Get-CurrentBase) (Get-CategorySection (Get-Model $file))
            Set-Thumb $cat.CatIcon $icon
            Update-NavCategory $file
        })
    $btnIconDel.Add_Click({
            $file = Get-CurrentFile; if (-not $file) { return }
            $c = Get-CategorySection (Get-Model $file)
            $icon = Get-CategoryIcon (Get-CurrentBase) $c
            if ($icon -and $icon.StartsWith($imagesRoot, [StringComparison]::OrdinalIgnoreCase)) {
                $r = Show-Dialog 'Raintile' "Move $([IO.Path]::GetFileName($icon)) to the Recycle Bin?" @('Remove', 'Cancel')
                if ($r.Button -ne 'Remove') { return }
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($icon, 'OnlyErrorDialogs', 'SendToRecycleBin')
            }
            Set-Key $c 'Icon' ''
            Set-Changed $file
            Set-Thumb $cat.CatIcon $null
            Update-NavCategory $file
        })

    # tiles: new, delete, reorder (hand-written ones only)
    $btnTileNew.Add_Click({
            $file = Get-CurrentFile; if (-not $file) { return }
            $m = Get-Model $file
            $r = Show-Dialog 'New tile' 'Name of the new tile (also the name of its images):' @('Create', 'Cancel') ''
            $name = "$($r.Text)" -replace '[\[\]]', ''
            if ($r.Button -ne 'Create' -or -not $name.Trim()) { return }
            $name = $name.Trim()
            if (($m.Sections | Where-Object { $_.Name -ieq $name }) -or ((Get-ImportedNames $m) -contains $name)) {
                [void](Show-Dialog 'Raintile' "There is already a tile called '$name'."); return
            }
            $s = [pscustomobject]@{ Name = $name; Comments = @(); Keys = (New-Object System.Collections.ArrayList) }
            [void]$m.Sections.Add($s)
            Set-Changed $file
            Refresh-Tiles ((Get-Tiles $m).Count - 1)
            [void]$cat['tile.Command'].Focus()
        })
    $btnTileDel.Add_Click({
            $t = Get-CurrentTile; if (-not $t) { return }
            $r = Show-Dialog 'Delete tile' "Delete the tile '$($t.Name)'? Its images stay in Images." @('Delete', 'Cancel')
            if ($r.Button -ne 'Delete') { return }
            $file = Get-CurrentFile
            (Get-Model $file).Sections.Remove($t)
            Set-Changed $file
            Refresh-Tiles ([Math]::Max(0, $cat.Tiles.SelectedIndex - 1))
        })
    foreach ($pair in @(@($btnTileUp, -1), @($btnTileDown, 1))) {
        $pair[0].Tag = $pair[1]
        $pair[0].Add_Click({
                param($s, $e)
                $t = Get-CurrentTile; if (-not $t) { return }
                $file = Get-CurrentFile
                $m = Get-Model $file
                $tiles = Get-Tiles $m
                $i = [array]::IndexOf($tiles, $t); $j = $i + $s.Tag
                if ($j -lt 0 -or $j -ge $tiles.Count) { return }
                $a = $m.Sections.IndexOf($t); $b = $m.Sections.IndexOf($tiles[$j])
                $m.Sections[$a] = $tiles[$j]; $m.Sections[$b] = $t
                Set-Changed $file
                Refresh-Tiles $j
            })
    }
    return $grid
}

# --- Saving, actions ----------------------------------------------------------------

function Invoke-Rainmeter([string]$bang) {
    $exe = (Get-Process Rainmeter -ErrorAction SilentlyContinue | Select-Object -First 1).Path
    if (-not $exe) { $exe = Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe' }
    if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe -ArgumentList $bang }
}

function Save-All([switch]$NoRefresh) {
    $changed = @{}
    foreach ($k in $values.Keys) { if ($values[$k] -ne $fileValues[$k]) { $changed[$k] = $values[$k] } }
    if ($changed.Count) {
        Write-Settings $settingsFile $changed
        foreach ($k in $changed.Keys) { $fileValues[$k] = $changed[$k] }
    }
    foreach ($file in @($changedFiles.Keys)) {
        $path = Join-Path $categoriesDir $file
        if (Test-Path -LiteralPath $path) { Write-Category $path $models[$file] }
    }
    $changedFiles.Clear()
    Update-Dirty
    $status.Text = 'Saved'
    if (-not $NoRefresh) { Invoke-Rainmeter "!Refresh `"$Config`"" }
}

function Invoke-Action([string]$action) {
    switch ($action) {
        'Import' {
            Save-All -NoRefresh
            $win.Cursor = [System.Windows.Input.Cursors]::Wait
            $script:importResult.Text = 'Importing' + [char]0x2026
            # let the window draw the message before the import blocks it
            $win.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
            try {
                $out = & (Join-Path $Resources 'Scripts\Import.ps1') -Resources $Resources -Category $values['ImportCategory'] `
                    -Stores $values['ImportStores'] -SteamGridDBKey $values['SteamGridDBKey'] 2>&1
                $script:importResult.Text = (($out | Where-Object { "$_" -notmatch '^RESULT:' } | ForEach-Object { "$_" -replace '^Raintile: (import: )?', '' }) -join "`r`n")
            } finally { $win.Cursor = $null }
            $models.Clear()
            $changedFiles.Clear()
            Build-Nav $script:navCurrent
            Refresh-Cats
            if ($script:currentFile) { Show-Category }
            Invoke-Rainmeter "!Refresh `"$Config`""
        }
        'OpenSettings' { Start-Process notepad.exe -ArgumentList "`"$settingsFile`"" }
        'OpenFolder' { Start-Process explorer.exe -ArgumentList "`"$Resources`"" }
    }
}

# --- Navigation ------------------------------------------------------------------
# The menu is rebuilt (Build-Nav) when a group opens or closes and when the
# categories change. Entry ids: page:<id>, group:<id>, categories, cat:<file>.

$pages = @{}
$schemaById = @{}
foreach ($page in $schema) { $schemaById[$page.Id] = $page }
$navOpen = @{ keybindings = $true; categories = $true }
$script:navBuilding = $false
$script:navCurrent = $null
$script:navPending = $null

# Entry of the menu: level 0 with a glyph (and an arrow for groups), level 1
# indented, with the category icon if any
function New-NavItem([string]$id, [string]$title, [int]$glyph, [int]$level, [hashtable]$tag, [string]$icon = '', $open = $null) {
    $item = New-Object System.Windows.Controls.ListBoxItem
    $g = New-Grid @('Auto', '*', 'Auto')
    if ($level -eq 0) {
        $gl = New-Glyph $glyph 15
        $gl.Width = 22
        $gl.Margin = T 0 0 10 0
        [void]$g.Children.Add($gl)
        $item.Padding = T 12 9
    } else {
        $img = New-Object System.Windows.Controls.Image
        $img.Width = 16; $img.Height = 16
        $img.Margin = T 0 0 10 0
        $img.Source = Get-Bitmap $icon 40
        [void]$g.Children.Add($img)
        $tag.Icon = $img
        $item.Padding = T 44 7 12 7
    }
    $t = New-Text $title $(if ($level -eq 0) { 13.5 } else { 13 })
    $t.VerticalAlignment = 'Center'
    $t.TextTrimming = 'CharacterEllipsis'
    Set-Col $t 1
    [void]$g.Children.Add($t)
    if ($null -ne $open) {
        $ch = New-Glyph $(if ($open) { 0xE70D } else { 0xE76C }) 9
        $ch.Foreground = Res 'DimBrush'
        $ch.Margin = T 8 0 0 0
        Set-Col $ch 2
        [void]$g.Children.Add($ch)
        $item.Add_PreviewMouseLeftButtonDown({ param($s, $e) Switch-NavGroup $s $e })
    }
    $item.Content = $g
    $tag.Id = $id
    $tag.Title = $t
    $item.Tag = $tag
    return $item
}

function Build-Nav([string]$selectId) {
    $script:navBuilding = $true
    try {
        $nav.Items.Clear()
        foreach ($node in $navTree) {
            if ($node.Children) {
                $open = [bool]$navOpen[$node.Id]
                [void]$nav.Items.Add((New-NavItem "group:$($node.Id)" $node.Title $node.Icon 0 @{ Type = 'group'; Group = $node.Id; First = "page:$($node.Children[0])" } '' $open))
                if ($open) {
                    foreach ($c in $node.Children) {
                        [void]$nav.Items.Add((New-NavItem "page:$c" $schemaById[$c].Title 0 1 @{ Type = 'page'; Page = $schemaById[$c] }))
                    }
                }
            } elseif ($node.Categories) {
                $page = $schemaById[$node.Page]
                $open = [bool]$navOpen['categories']
                [void]$nav.Items.Add((New-NavItem 'categories' $page.Title $page.Icon 0 @{ Type = 'page'; Group = 'categories'; Page = $page } '' $open))
                if ($open) {
                    foreach ($e in Get-CategoryEntries) {
                        [void]$nav.Items.Add((New-NavItem "cat:$($e.File)" $e.Name 0 1 @{ Type = 'category'; File = $e.File } $e.Icon))
                    }
                }
            } else {
                $page = $schemaById[$node.Page]
                [void]$nav.Items.Add((New-NavItem "page:$($node.Page)" $page.Title $page.Icon 0 @{ Type = 'page'; Page = $page }))
            }
        }
        foreach ($it in $nav.Items) { if ($it.Tag.Id -eq $selectId) { $nav.SelectedItem = $it } }
    } finally { $script:navBuilding = $false }
}

# Goes to a menu entry (after the current event: the menu may be rebuilt)
function Open-Nav([string]$id) {
    $script:navPending = $id
    [void]$win.Dispatcher.BeginInvoke([action] {
            Build-Nav $script:navPending
            if ($nav.SelectedItem) { Show-NavTarget $nav.SelectedItem.Tag }
        })
}

function Open-Category([string]$file) {
    $navOpen['categories'] = $true
    Open-Nav "cat:$file"
}

# Click on a group: opens or closes it. Keybindings has no page of its own and
# goes to its first entry; Categories opens on the first click and only
# closes when its page is already shown.
function Switch-NavGroup($item, $e) {
    $tag = $item.Tag
    if ($tag.Type -eq 'group') {
        $e.Handled = $true
        $navOpen[$tag.Group] = -not $navOpen[$tag.Group]
        Open-Nav $(if ($navOpen[$tag.Group]) { $tag.First } else { $script:navCurrent })
    } elseif ($script:navCurrent -eq $tag.Id) {
        $e.Handled = $true
        $navOpen[$tag.Group] = -not $navOpen[$tag.Group]
        Open-Nav $script:navCurrent
    } elseif (-not $navOpen[$tag.Group]) {
        $e.Handled = $true
        $navOpen[$tag.Group] = $true
        Open-Nav $tag.Id
    }
}

function Show-Page($page) {
    if (-not $pages.ContainsKey($page.Id)) {
        $script:updating = $true
        try {
            $pages[$page.Id] = if ($page.Id -eq 'categories') { New-CategoryListPage } else { New-SettingsPage $page }
        } finally { $script:updating = $false }
        Update-Resets
        Update-KeyConflicts
    }
    if ($page.Id -eq 'categories') { Refresh-Cats $script:currentFile }
    $pageHost.Children.Clear()
    [void]$pageHost.Children.Add($pages[$page.Id])
    $pageTitle.Text = $page.Title
    $pageDesc.Text = $page.Desc
}

function Show-CategoryPage([string]$file) {
    if (-not $pages.ContainsKey('category')) { $pages['category'] = New-CategoryPage }
    $script:currentFile = $file
    Show-Category
    $pageHost.Children.Clear()
    [void]$pageHost.Children.Add($pages['category'])
    $c = Get-CategorySection (Get-Model $file)
    $name = Get-Key $c 'Name'
    $pageTitle.Text = if ($name) { $name } else { [IO.Path]::GetFileNameWithoutExtension($file) }
    $pageDesc.Text = "Categories\${file}: the category and its tiles."
}

function Show-NavTarget($tag) {
    switch ($tag.Type) {
        'page' { Show-Page $tag.Page }
        'category' { Show-CategoryPage $tag.File }
        'group' { return }
    }
    $script:navCurrent = $tag.Id
}

$links = $win.FindName('Links')
foreach ($l in @(@('OpenSettings', 'Open Settings.inc'), @('OpenFolder', 'Open the skin folder'))) {
    $b = New-Button $l[1] 'LinkButton'
    $b.Tag = $l[0]
    $b.Add_Click({ param($s, $e) Invoke-Action $s.Tag })
    [void](Add-To $links $b)
}

$nav.Add_SelectionChanged({
        if ($script:navBuilding) { return }
        $sel = $nav.SelectedItem
        if (-not $sel) { return }
        $tag = $sel.Tag
        if ($tag.Type -eq 'group') {
            # reached with the keyboard: open the group on its first entry
            $navOpen[$tag.Group] = $true
            Open-Nav $tag.First
            return
        }
        Show-NavTarget $tag
    })

$btnSave.Add_Click({ Save-All })
$win.FindName('BtnClose').Add_Click({ $win.Close() })
$win.Add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq 'S' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control' -and -not $script:capturing) {
            $e.Handled = $true
            Save-All
        }
    })
$win.Add_Closing({
        param($s, $e)
        if (-not $script:dirtySettings) { return }
        $r = Show-Dialog 'Raintile' 'Save the changes before closing?' @('Save', "Don't save", 'Cancel')
        if ($r.Button -eq 'Save') { Save-All }
        elseif ($r.Button -ne "Don't save") { $e.Cancel = $true }
    })
$win.Add_SourceInitialized({ Set-DarkTitle $win })
# Started without a console: bring the window to the foreground explicitly
$win.Add_ContentRendered({
        $win.Topmost = $true
        [void]$win.Activate()
        $win.Topmost = $false
        [void][RaintileOptions.Win32]::SetForegroundWindow((New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle)
    })

$script:updating = $false
Build-Nav 'page:general'
Show-NavTarget $nav.SelectedItem.Tag
Update-Dirty
[void]$win.ShowDialog()
$app.Shutdown()
