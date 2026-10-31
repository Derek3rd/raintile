# Raintile: Options window (settings and categories).
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
#    Games of the old automatic import (below its marker) are listed but cannot be
#    edited.
# "Save and refresh" writes the files and refreshes the skin.
#
# With -NoGui only the functions and the schema are loaded (for tests).

param(
    [Parameter(Mandatory = $true)][string]$Resources,
    # folder with your data (Settings.inc, Categories\, Images\): see Data.ps1
    [string]$Data = '',
    [string]$Config = 'Raintile',
    # page to open on (e.g. -Page import: the list of games and apps found;
    # -Page tile: the tile in Generated\EditTile.txt, from the skin's menu).
    # Not $Page: variable names ignore case, and the menu code uses $page.
    [Alias('Page')][string]$OpenPage = '',
    [switch]$NoGui
)

$ErrorActionPreference = 'Stop'
$IMPORT_MARKER = '; ===== IMPORTED AUTOMATICALLY ====='
# Marker written by older Italian versions, still recognised
$OLD_IMPORT_MARKER = '; ===== IMPORTATI AUTOMATICAMENTE ====='
$utf8 = New-Object System.Text.UTF8Encoding $false
$Resources = [IO.Path]::GetFullPath($Resources).TrimEnd('\', '/')
# until the data folder is prepared, the skin's own files are used
$Data = if ($Data -and (Test-Path -LiteralPath (Join-Path $Data 'Settings.inc'))) { [IO.Path]::GetFullPath($Data).TrimEnd('\', '/') } else { $Resources }
$settingsFile = Join-Path $Data 'Settings.inc'
$categoriesDir = Join-Path $Data 'Categories'
$imagesRoot = Join-Path $Data 'Images'
$IMAGE_EXTS = '.png', '.jpg', '.jpeg', '.bmp', '.ico', '.gif'
# Functions of the search (names, existing tiles, SteamGridDB) and its files:
# $foundFile, $seenFile. Its parameters become variables here too ($Stores,
# $NoRun, ...: typed [string], so no other variable may use those names).
. (Join-Path $PSScriptRoot 'Scan.ps1') -Resources $Resources -Data $Data -NoRun
# Functions of the update check (Read-UpdateInfo, Invoke-UpdateCheck)
. (Join-Path $PSScriptRoot 'Update.ps1') -Resources $Resources -Data $Data -NoRun

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
            # one line: a value can not add keys or sections
            if ($values.ContainsKey($key)) { $lines[$i] = $Matches[1] + $Matches[2] + $Matches[3] + ("$($values[$key])" -replace '[\r\n]+', ' ') }
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
#   info (text only), action (button), secret (hidden text, saved encrypted).

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
$SOURCES = 'Steam', 'Epic', 'GOG', 'Ubisoft', 'Battlenet', 'EA', 'Xbox', 'Apps'
$STORE_LABELS = @{
    Steam = 'Steam'; Epic = 'Epic Games'; GOG = 'GOG'; Ubisoft = 'Ubisoft Connect'; Battlenet = 'Battle.net'
    'Battle.net' = 'Battle.net'; EA = 'EA app'; Xbox = 'Xbox / Store'; Apps = 'Start menu apps'
}

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
        Desc = 'Games and apps installed on this PC: pick the ones to add, they become normal tiles with their images. Nothing is added by itself.'
        Groups = @(
            @{ Found = $true; Items = @() }
            @{ Title = 'Search'; Items = @(
                    (S 'stores' 'ImportStores' 'Where to look'),
                    (S 'bool' 'ScanOnStart' 'Look for new ones on start' 'In the background, each time the skin loads: new games or apps light a dot on the gear.'),
                    (S 'category' 'ImportCategory' 'Category for games'),
                    (S 'category' 'AppsCategory' 'Category for apps'),
                    (S 'secret' 'SteamGridDBKey' 'SteamGridDB API key' 'Free, from steamgriddb.com > Preferences > API. When adding a game without local images, its background and logo are downloaded. Saved encrypted: only your Windows user on this PC can read it.')
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
            @{ Title = 'Updates'; Items = @(
                    (S 'bool' 'CheckUpdates' 'Check for updates' 'Once a day, on GitHub. A new version lights the dot on the gear and is shown in Info.')
                ) }
            @{ Title = 'Diagnostics'; Items = @(
                    (S 'bool' 'DebugLog' 'Debug log' 'Writes details to the Rainmeter log (Manage > Log).')
                ) }
            @{ Title = 'Other settings'; Other = $true; Items = @() }
        )
    }
    @{ Id = 'info'; Title = 'Info'; Icon = 0xE946
        Desc = 'About Raintile, and its files.'
        Groups = @()
    }
    @{ Id = 'categories'; Title = 'Categories'; Icon = 0xECA5
        Desc = 'One file per category in Categories\. Select a category to edit it; double-click it, or pick it in the menu, for its tiles.'
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
    ImportCategory = 'Games'; AppsCategory = 'Apps'; ImportStores = 'Steam|Epic|GOG|Ubisoft|Battlenet|EA|Xbox|Apps'
    ScanOnStart = '1'; SteamGridDBKey = ''
    CheckUpdates = '1'; DebugLog = '0'; ShowLabels = '1'; FontFace = 'Segoe UI'; MenuFontSize = '12'; LabelFontSize = '14'
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

# --- Secrets ----------------------------------------------------------------------
# The SteamGridDB key is kept encrypted in Settings.inc with Windows DPAPI
# (current user): "dpapi:<base64>". Only your Windows account on this PC can
# read it back. A value written by hand without the prefix is used as it is
# and encrypted the next time the Options window saves.

$SECRET_PREFIX = 'dpapi:'
$SECRET_ENTROPY = [Text.Encoding]::UTF8.GetBytes('Raintile SteamGridDB key')
try { Add-Type -AssemblyName System.Security } catch { }

function Protect-Secret([string]$plain) {
    if (-not $plain) { return '' }
    $bytes = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($plain), $SECRET_ENTROPY, 'CurrentUser')
    return $SECRET_PREFIX + [Convert]::ToBase64String($bytes)
}

# The plain text of a stored secret ('' if it cannot be decrypted, e.g. it
# was encrypted by another Windows user)
function Unprotect-Secret([string]$stored) {
    if (-not $stored) { return '' }
    if (-not $stored.StartsWith($SECRET_PREFIX)) { return $stored }
    try {
        $bytes = [Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($stored.Substring($SECRET_PREFIX.Length)), $SECRET_ENTROPY, 'CurrentUser')
        return [Text.Encoding]::UTF8.GetString($bytes)
    } catch { return '' }
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
    $value = $value -replace '[\r\n]+', ' '   # one line: no extra keys or sections
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
# True if 'path' is a file directly inside 'folder' (a name with ..\ or a
# full path can not lead anywhere else)
function Test-InFolder([string]$path, [string]$folder) {
    try {
        $parent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path))
        return $parent -ieq [IO.Path]::GetFullPath($folder).TrimEnd('\', '/')
    } catch { return $false }
}

function Copy-TileImage([string]$category, [string]$kind, [string]$tile, [string]$source) {
    $dir = Join-Path $imagesRoot "$category\$kind"
    $dest = Join-Path $dir ($tile + [IO.Path]::GetExtension($source).ToLowerInvariant())
    if (-not (Test-InFolder $dest $dir)) { throw "Not a valid tile name for an image file: $tile" }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    # remove any previous image with another extension
    Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.BaseName -ieq $tile } | Remove-Item -Force
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
            if (-not (Test-InFolder $dest $dir)) { continue }
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
$information = ''
try {
    $ini = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $Resources) 'Raintile.ini'))
    $m = [regex]::Match($ini, '(?m)^\s*Version\s*=\s*(.+?)\s*$')
    if ($m.Success) { $version = 'v' + $m.Groups[1].Value }
    $m = [regex]::Match($ini, '(?m)^\s*Information\s*=\s*(.+?)\s*$')
    if ($m.Success) { $information = $m.Groups[1].Value }
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
          <TextBlock Text="Raintile" FontSize="21" FontWeight="SemiBold"/>
          <TextBlock x:Name="Version" Foreground="{StaticResource DimBrush}" FontSize="12" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
          <Border Height="1" Background="{StaticResource LineBrush}" Margin="8,0,8,8"/>
          <ListBox x:Name="NavBottom"/>
        </StackPanel>
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
    <!-- Shown after "Save and refresh" while the skin reloads -->
    <Grid x:Name="Overlay" Grid.ColumnSpan="2" Background="#D915151B" Visibility="Collapsed">
      <Border Style="{StaticResource Card}" Width="400" Padding="28,24" HorizontalAlignment="Center" VerticalAlignment="Center">
        <StackPanel>
          <TextBlock Text="Saving and refreshing" FontSize="17" FontWeight="SemiBold"/>
          <TextBlock Text="The launcher opens in a moment." Foreground="{StaticResource DimBrush}" Margin="0,4,0,18"/>
          <DockPanel Margin="0,0,0,8">
            <TextBlock x:Name="ProgressPercent" DockPanel.Dock="Right" FontWeight="SemiBold" Foreground="{StaticResource AccentBrush}"/>
            <TextBlock x:Name="ProgressStage" Foreground="{StaticResource DimBrush}" FontSize="12.5"/>
          </DockPanel>
          <Border x:Name="ProgressTrack" Height="10" CornerRadius="5" Background="{StaticResource FieldBg}" ClipToBounds="True">
            <Border x:Name="ProgressBar" Width="0" HorizontalAlignment="Left" CornerRadius="5" Background="{StaticResource AccentBrush}"/>
          </Border>
        </StackPanel>
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
# a SteamGridDB key written in clear (by hand, or by an older version) is
# encrypted in Settings.inc right away
if ($values['SteamGridDBKey'] -and -not "$($values['SteamGridDBKey'])".StartsWith($SECRET_PREFIX)) {
    try {
        $encrypted = Protect-Secret $values['SteamGridDBKey']
        Write-Settings $settingsFile @{ SteamGridDBKey = $encrypted }
        $values['SteamGridDBKey'] = $encrypted
        $fileValues['SteamGridDBKey'] = $encrypted
    } catch { }
}
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
    $dirty = $changed.Count -gt 0 -or $changedFiles.Count -gt 0 -or $script:needsRefresh
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
            'secret' { $c.Box.Password = Unprotect-Secret $v }
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

# Hidden text (the SteamGridDB key): shown as dots, saved encrypted
function New-SecretControl([string]$key) {
    $pb = New-Object System.Windows.Controls.PasswordBox
    $pb.Width = 300
    $pb.Tag = $key
    $pb.Password = Unprotect-Secret "$($values[$key])"
    $pb.Add_PasswordChanged({ param($s, $e) Set-Value $s.Tag (Protect-Secret $s.Password) })
    $ctl[$key] = @{ Kind = 'secret'; Box = $pb }
    return $pb
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
    $wp.MaxWidth = 470
    $wp.HorizontalAlignment = 'Right'
    $current = @("$($values[$key])" -split '\|' | ForEach-Object { $_.Trim() -replace '\.', '' })
    foreach ($store in $SOURCES) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $STORE_LABELS[$store]
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
        'secret' { New-SecretControl $k }
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
        if ($group.Found) {
            # list of the games and apps found (its own card)
            [void](Add-To $sp (New-FoundCard))
            continue
        }
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

$script:currentFile = $null  # category whose tiles are shown (chosen in the menu)
# category selected in the list of the Categories page
function Get-ListFile { if ($cat.Cats -and $cat.Cats.SelectedItem) { return [string]$cat.Cats.SelectedItem.Tag.File } return $null }
function Get-ListBase { $f = Get-ListFile; if ($f) { return [IO.Path]::GetFileNameWithoutExtension($f) } return $null }
function Get-CurrentFile { return $script:currentFile }
function Get-CurrentBase { $f = Get-CurrentFile; if ($f) { return [IO.Path]::GetFileNameWithoutExtension($f) } return $null }
# Tile selected, if it can be edited (not imported)
function Get-CurrentTile {
    $sel = $cat.Tiles.SelectedItem
    if (-not $sel -or $sel.Tag.Imported) { return $null }
    return $sel.Tag.Section
}
# Tile selected, imported ones too (read from the imported block)
function Get-ShownTile {
    $sel = $cat.Tiles.SelectedItem
    if (-not $sel) { return $null }
    return $sel.Tag.Section
}

# An imported game as a section (Name, Keys), read from the imported block
function Get-ImportedSection($model, [string]$name) {
    $s = $null
    foreach ($line in ($model.Imported -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match '^\[(.+)\]$') {
            if ($s) { break }
            if ($Matches[1].Trim() -ieq $name) {
                $s = [pscustomobject]@{ Name = $Matches[1].Trim(); Comments = @(); Keys = (New-Object System.Collections.ArrayList) }
            }
            continue
        }
        if ($s -and $t -match '^([^;=][^=]*?)\s*=(.*)$') { [void]$s.Keys.Add(@($Matches[1].Trim(), $Matches[2].Trim())) }
    }
    return $s
}

function Remove-ImportedSection($model, [string]$name) {
    $out = New-Object System.Collections.ArrayList
    $skip = $false
    foreach ($line in ($model.Imported -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match '^\[(.+)\]$') {
            $skip = ($Matches[1].Trim() -ieq $name)
            if ($skip -and $out.Count -and "$($out[$out.Count - 1])".Trim() -eq '') { $out.RemoveAt($out.Count - 1) }
        }
        if (-not $skip) { [void]$out.Add($line) }
    }
    $model.Imported = ($out -join "`r`n")
}

# Imported game -> hand-written tile, at the end of the tiles: its images are
# copied to the default folders (the import does not touch it any more: a
# hand-written tile with its name or command is skipped)
function Convert-ImportedTile([string]$file, [string]$name) {
    $m = Get-Model $file
    $src = Get-ImportedSection $m $name
    if (-not $src) { return $null }
    $base = [IO.Path]::GetFileNameWithoutExtension($file)
    $s = [pscustomobject]@{ Name = $src.Name; Comments = @(); Keys = (New-Object System.Collections.ArrayList) }
    foreach ($kv in $src.Keys) {
        if ($kv[0] -in 'Background', 'Logo') {
            $path = Find-Image (Join-Path $imagesRoot "$base\$($kv[0].ToLowerInvariant())") $kv[1]
            if ($path) { [void](Copy-TileImage $base $kv[0].ToLowerInvariant() $src.Name $path); continue }
        }
        [void]$s.Keys.Add(@($kv[0], $kv[1]))
    }
    Remove-ImportedSection $m $name
    [void]$m.Sections.Add($s)
    Set-Changed $file
    return $s
}

# Moves a tile and its images to another category; both files are written at
# once (the images have already moved). Returns an error message, or $null.
function Move-TileToCategory([string]$from, $section, [string]$to) {
    $dst = Get-Model $to
    if (($dst.Sections | Where-Object { $_.Name -ieq $section.Name }) -or ((Get-ImportedNames $dst) -contains $section.Name)) {
        return "There is already a tile called '$($section.Name)' in that category."
    }
    $fromBase = [IO.Path]::GetFileNameWithoutExtension($from)
    $toBase = [IO.Path]::GetFileNameWithoutExtension($to)
    $fromRoot = Join-Path $imagesRoot $fromBase
    foreach ($kind in 'Background', 'Logo') {
        $path = Get-TileImage $fromBase $section $kind
        if (-not $path -or -not $path.StartsWith($fromRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $dest = Join-Path (Join-Path $imagesRoot $toBase) $path.Substring($fromRoot.Length + 1)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        if (-not (Test-Path -LiteralPath $dest)) { Move-Item -LiteralPath $path -Destination $dest }
        # a full path to the old place follows the image
        $explicit = (Get-Key $section $kind).Trim('"')
        if ($explicit -and [IO.Path]::IsPathRooted($explicit)) { Set-Key $section $kind $dest }
    }
    (Get-Model $from).Sections.Remove($section)
    [void]$dst.Sections.Add($section)
    foreach ($f in $from, $to) {
        Write-Category (Join-Path $categoriesDir $f) (Get-Model $f)
        $changedFiles.Remove($f)
    }
    Update-Dirty
    return $null
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
    if ($cat.Cats) {
        foreach ($it in $cat.Cats.Items) {
            if ($it.Tag.File -eq $file) {
                $it.Tag.Title.Text = $name
                Set-Thumb $it.Tag.Thumb (Get-CategoryIcon ([IO.Path]::GetFileNameWithoutExtension($file)) $c)
            }
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
            $item = New-ListEntry $n 'imported' @{ Section = (Get-ImportedSection $m $n); Imported = $true }
            $item.Opacity = 0.7
            [void]$cat.Tiles.Items.Add($item)
            if ($item.Tag.Section) { Update-TileEntry $item }
        }
    }
    if ($cat.Tiles.Items.Count) { $cat.Tiles.SelectedIndex = [Math]::Max(0, [Math]::Min($select, $cat.Tiles.Items.Count - 1)) }
    else { Show-Tile }
}

# Tiles of the category chosen in the menu
function Show-Category {
    if (-not $cat.Tiles) { return }
    Refresh-Tiles
}

# Settings of the category selected in the list of the Categories page
function Show-CategoryDetails {
    if (-not $cat.CatCard) { return }
    $script:loading = $true
    $file = Get-ListFile
    $cat.CatCard.IsEnabled = [bool]$file
    $c = if ($file) { Get-CategorySection (Get-Model $file) } else { $null }
    foreach ($k in 'Name', 'NX', 'NY', 'IconSize') { $cat["cat.$k"].Text = if ($c) { Get-Key $c $k } else { '' } }
    Set-Thumb $cat.CatIcon $(if ($c) { Get-CategoryIcon (Get-ListBase) $c } else { $null })
    $cat.CatIconHint.Text = if ($file) { "Default: Images\$(Get-ListBase)\icon.png" } else { '' }
    $cat.GridHint.Text = "Empty = default ($($values['NX']) " + [char]0xD7 + " $($values['NY']), from Layout)"
    $cat.SizeHint.Text = "Pixels or %. Empty = default ($($values['IconSize']))"
    $script:loading = $false
}

# --- Framing of the background (BgFocus, BgZoom) ----------------------------------
# The preview has the proportions of this category's tiles on the current
# screen (the skin writes its grid area to Generated\Area.txt) and shows the
# part of the image the launcher shows with BgStyle=Crop; the other styles
# start from it. Dragging the preview moves BgFocus, the wheel and the slider
# set BgZoom. The same maths as frameRect in Raintile.lua.

$bgFrame = @{ Path = $null; Bitmap = $null; FX = 0.5; FY = 0.5; Zoom = 1.0; TW = 16; TH = 9; Drag = $null; Moved = $false; Sync = $false }

# Size in pixels of a tile of category $file (only its proportions count)
function Get-TileSize([string]$file) {
    $area = $null
    try {
        $parts = [IO.File]::ReadAllText((Join-Path $Resources 'Generated\Area.txt')).Trim().Split(',')
        if ($parts.Count -eq 3) { $area = @([double]$parts[0], [double]$parts[1], [double]$parts[2]) }
    } catch { }
    if (-not $area) {
        # skin not loaded yet: the screen without menu and margins, roughly
        $px = Get-ScreenPixels
        $area = @(($px.W * 0.96), ($px.H * 0.88), 16)
    }
    $c = Get-CategorySection (Get-Model $file)
    $n = @{}
    foreach ($k in 'NX', 'NY') {
        $v = 0
        if (-not [int]::TryParse((Get-Key $c $k), [ref]$v) -or $v -lt 1) { [void][int]::TryParse("$($values[$k])", [ref]$v) }
        $n[$k] = [Math]::Max(1, $v)
    }
    return @{
        W = [Math]::Max(1, [Math]::Floor(($area[0] - ($n.NX - 1) * $area[2]) / $n.NX))
        H = [Math]::Max(1, [Math]::Floor(($area[1] - ($n.NY - 1) * $area[2]) / $n.NY))
    }
}

function Read-Framing($section) {
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $bgFrame.FX = 0.5; $bgFrame.FY = 0.5; $bgFrame.Zoom = 1.0
    if (-not $section) { return }
    $x = 0.0; $y = 0.0; $z = 0.0
    if ((Get-Key $section 'BgFocus') -match '^\s*([\d.]+)\s*,\s*([\d.]+)\s*$' -and
        [double]::TryParse($Matches[1], 'Float', $inv, [ref]$x) -and [double]::TryParse($Matches[2], 'Float', $inv, [ref]$y)) {
        $bgFrame.FX = [Math]::Min(100.0, $x) / 100; $bgFrame.FY = [Math]::Min(100.0, $y) / 100
    }
    if ([double]::TryParse((Get-Key $section 'BgZoom'), 'Float', $inv, [ref]$z)) { $bgFrame.Zoom = [Math]::Min(4.0, [Math]::Max(1.0, $z)) }
}

# Part of the image shown, in image pixels; S = preview pixels per image pixel.
# Doubles everywhere: with an integer first argument PowerShell picks the
# Int32 overload of [Math]::Min/Max and truncates the other one.
function Get-FrameWindow {
    $iw = [double]$bgFrame.Bitmap.PixelWidth; $ih = [double]$bgFrame.Bitmap.PixelHeight
    $pw = [double]$cat.Preview.Width; $ph = [double]$cat.Preview.Height
    $s = [Math]::Max($pw / $iw, $ph / $ih) * $bgFrame.Zoom
    $w = [Math]::Min($iw, $pw / $s); $h = [Math]::Min($ih, $ph / $s)
    return @{
        X = [Math]::Min($iw - $w, [Math]::Max(0.0, $bgFrame.FX * $iw - $w / 2))
        Y = [Math]::Min($ih - $h, [Math]::Max(0.0, $bgFrame.FY * $ih - $h / 2))
        W = $w; H = $h; S = $s; IW = $iw; IH = $ih
    }
}

# The focus goes back to the centre of what is shown: past an edge it would
# move nothing (and dragging back would first have to undo the excess)
function Limit-Focus {
    $v = Get-FrameWindow
    $bgFrame.FX = ($v.X + $v.W / 2) / $v.IW
    $bgFrame.FY = ($v.Y + $v.H / 2) / $v.IH
}

function Update-Framing {
    $p = $cat.Preview
    $k = [Math]::Min(384 / $bgFrame.TW, 260 / $bgFrame.TH)
    $p.Width = [Math]::Max(40.0, [Math]::Round($bgFrame.TW * $k))
    $p.Height = [Math]::Max(40.0, [Math]::Round($bgFrame.TH * $k))
    $img = $cat.PreviewBg
    $img.Source = $bgFrame.Bitmap
    $has = [bool]$bgFrame.Bitmap
    $cat.FrameRow.IsEnabled = $has
    $p.Cursor = if ($has) { [System.Windows.Input.Cursors]::SizeAll } else { $null }
    $bgFrame.Sync = $true
    $cat.ZoomSlider.Value = $bgFrame.Zoom
    $bgFrame.Sync = $false
    $cat.ZoomText.Text = $bgFrame.Zoom.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture) + [char]0xD7
    if (-not $has) { return }
    $v = Get-FrameWindow
    $img.Width = $v.IW * $v.S; $img.Height = $v.IH * $v.S
    [System.Windows.Controls.Canvas]::SetLeft($img, -$v.X * $v.S)
    [System.Windows.Controls.Canvas]::SetTop($img, -$v.Y * $v.S)
}

# Writes BgFocus/BgZoom; the centre at zoom 1 (the default) removes them
function Save-Framing {
    $t = Get-CurrentTile; if (-not $t) { return }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $fx = [Math]::Round($bgFrame.FX * 100, 1); $fy = [Math]::Round($bgFrame.FY * 100, 1)
    $z = [Math]::Round($bgFrame.Zoom, 2)
    $focus = if ($fx -eq 50 -and $fy -eq 50) { '' } else { $fx.ToString('0.#', $inv) + ',' + $fy.ToString('0.#', $inv) }
    $zoom = if ($z -le 1) { '' } else { $z.ToString('0.##', $inv) }
    if ((Get-Key $t 'BgFocus') -ceq $focus -and (Get-Key $t 'BgZoom') -ceq $zoom) { return }
    Set-Key $t 'BgFocus' $focus
    Set-Key $t 'BgZoom' $zoom
    Set-Changed (Get-CurrentFile)
}

# New zoom; $anchor (a point of the preview) keeps showing the same part of
# the image, as when zooming with the wheel under the mouse
function Set-FrameZoom([double]$zoom, $anchor = $null) {
    $zoom = [Math]::Round([Math]::Min(4.0, [Math]::Max(1.0, $zoom)), 2)
    if ($anchor) {
        $v = Get-FrameWindow
        $ix = $v.X + $anchor.X / $v.S; $iy = $v.Y + $anchor.Y / $v.S
        $bgFrame.Zoom = $zoom
        $v = Get-FrameWindow
        $bgFrame.FX = ($ix - $anchor.X / $v.S + $v.W / 2) / $v.IW
        $bgFrame.FY = ($iy - $anchor.Y / $v.S + $v.H / 2) / $v.IH
    } else {
        $bgFrame.Zoom = $zoom
    }
    Limit-Focus
    Update-Framing
    Save-Framing
}

# A new or removed background: the old framing no longer applies
function Reset-Framing($section) {
    Set-Key $section 'BgFocus' ''
    Set-Key $section 'BgZoom' ''
    $bgFrame.Path = $null
}

function Update-TilePreview {
    $s = Get-ShownTile
    $base = Get-CurrentBase
    $bg = if ($s) { Get-TileImage $base $s 'Background' } else { $null }
    $logo = if ($s) { Get-TileImage $base $s 'Logo' } else { $null }
    $p = $cat.Preview
    $p.Background = if ($s) { Get-TileBrush $base $s $bg $logo } else { Res 'FieldBg' }
    # decoded large enough to stay sharp when zoomed in
    if ($bgFrame.Path -ne $bg) { $bgFrame.Path = $bg; $bgFrame.Bitmap = Get-Bitmap $bg 1200 }
    if (-not $bg) { $bgFrame.Bitmap = $null }
    Read-Framing $s
    $size = if (Get-CurrentFile) { Get-TileSize (Get-CurrentFile) } else { @{ W = 16; H = 9 } }
    $bgFrame.TW = $size.W; $bgFrame.TH = $size.H
    Update-Framing
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
    if ($sel -and $sel.Tag.Section) { Update-TileEntry $sel }
}

function Show-Tile {
    $script:loading = $true
    $s = Get-ShownTile
    $sel = $cat.Tiles.SelectedItem
    $imported = $sel -and $sel.Tag.Imported
    $cat.TileCard.IsEnabled = [bool]$s -and -not $imported
    $cat.ImportedCard.Visibility = if ($imported) { 'Visible' } else { 'Collapsed' }
    foreach ($k in 'Command', 'Label', 'Color') { $cat["tile.$k"].Text = if ($s) { Get-Key $s $k } else { '' } }
    $cat['tile.Name'].Text = if ($s) { $s.Name } else { '' }
    $cat.Note.Text = if (-not $sel) { 'No tiles yet: add one with the + button.' } else { '' }
    $cat.Note.Visibility = if ($cat.Note.Text) { 'Visible' } else { 'Collapsed' }
    # other categories the tile can move to
    $cat.MoveTo.Items.Clear()
    foreach ($e in Get-CategoryEntries) {
        if ($e.File -eq (Get-CurrentFile)) { continue }
        $ci = New-Object System.Windows.Controls.ComboBoxItem
        $ci.Content = $e.Name
        $ci.Tag = $e.File
        [void]$cat.MoveTo.Items.Add($ci)
    }
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
    $grid = New-Grid @('440', '*')
    $grid.Margin = T 36 4 36 20
    $dp = New-Object System.Windows.Controls.DockPanel
    $dp.Margin = T 0 0 16 0
    [void]$grid.Children.Add($dp)
    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'
    Set-Col $sv 1
    [void]$grid.Children.Add($sv)
    $side = New-Panel
    $side.MaxWidth = 600
    $side.HorizontalAlignment = 'Left'
    $sv.Content = $side
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

    # Category card
    $card = New-Card 'Category' ''
    $cat.CatCard = $card
    [void](Add-To $side $card)
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


    $cat.Cats.Add_SelectionChanged({ Show-CategoryDetails })
    foreach ($k in 'Name', 'NX', 'NY', 'IconSize') {
        $cat["cat.$k"].Add_TextChanged({
                param($s, $e)
                if ($script:loading) { return }
                $file = Get-ListFile; if (-not $file) { return }
                Set-Key (Get-CategorySection (Get-Model $file)) $s.Tag $s.Text.Trim()
                Set-Changed $file
                if ($s.Tag -eq 'Name') { Update-NavCategory $file }
            })
    }
    $btnIcon.Add_Click({
            $file = Get-ListFile; if (-not $file) { return }
            $src = Select-File $imageFilter; if (-not $src) { return }
            $dir = Join-Path $imagesRoot (Get-ListBase)
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.BaseName -ieq 'icon' } | Remove-Item -Force
            Copy-Item -LiteralPath $src -Destination (Join-Path $dir ('icon' + [IO.Path]::GetExtension($src).ToLowerInvariant())) -Force
            Set-Key (Get-CategorySection (Get-Model $file)) 'Icon' ''   # the default icon just copied applies
            Set-Changed $file
            $icon = Get-CategoryIcon (Get-ListBase) (Get-CategorySection (Get-Model $file))
            Set-Thumb $cat.CatIcon $icon
            Update-NavCategory $file
        })
    $btnIconDel.Add_Click({
            $file = Get-ListFile; if (-not $file) { return }
            $c = Get-CategorySection (Get-Model $file)
            $icon = Get-CategoryIcon (Get-ListBase) $c
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
            [void](New-CategoryFile $file $r.Text)
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
    return $grid
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

    # Imported game: read-only, can become a normal tile
    $card = New-Card 'Imported game' ''
    $cat.ImportedCard = $card
    $card.Visibility = 'Collapsed'
    [void](Add-To $details $card)
    $txt = New-Text 'From the old automatic import (written below its marker line), so it cannot be edited here. Make it a normal tile to edit or move it: its images are copied to the category folders. Opening Import turns all of them into normal tiles.' 12.5 (Res 'DimBrush') -Wrap
    $txt.Margin = T 0 0 0 10
    [void](Add-To $card.Child $txt)
    $btnConvert = New-Button 'Make it a normal tile' 'AccentButton'
    $btnConvert.HorizontalAlignment = 'Left'
    $btnConvert.Margin = T 0 0 0 10
    [void](Add-To $card.Child $btnConvert)
    $btnConvert.Add_Click({
            $sel = $cat.Tiles.SelectedItem
            if (-not $sel -or -not $sel.Tag.Imported) { return }
            $file = Get-CurrentFile
            $s = Convert-ImportedTile $file $sel.Tag.Section.Name
            if ($s) { Refresh-Tiles ((Get-Tiles (Get-Model $file)).Count - 1) }
        })

    # Tile card
    $card = New-Card 'Tile' ''
    $cat.TileCard = $card
    [void](Add-To $details $card)
    $f = $card.Child
    $cat.Note = New-Text '' 12.5 (Res 'AccentBrush') -Wrap
    $cat.Note.Margin = T 0 0 0 8
    [void](Add-To $f $cat.Note)

    # preview, as the tile looks in the launcher (sized by Update-Framing); the
    # background sits on a canvas, positioned by the framing
    $p = New-Object System.Windows.Controls.Border
    $p.Width = 384; $p.Height = 216
    $p.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $p.HorizontalAlignment = 'Left'
    $p.Margin = T 0 4 0 10
    $p.ClipToBounds = $true
    $pg = New-Object System.Windows.Controls.Grid
    $p.Child = $pg
    $canvas = New-Object System.Windows.Controls.Canvas
    $cat.PreviewBg = New-Object System.Windows.Controls.Image
    $cat.PreviewBg.Stretch = 'Fill'
    [void]$canvas.Children.Add($cat.PreviewBg)
    $cat.PreviewLogo = New-Object System.Windows.Controls.Image
    $cat.PreviewLogo.Stretch = 'Uniform'
    $cat.PreviewLogo.MaxWidth = 140; $cat.PreviewLogo.MaxHeight = 90
    $cat.PreviewLabel = New-Text '' 14 (New-ColorBrush "$($values['TextColor'])")
    $cat.PreviewLabel.HorizontalAlignment = 'Left'; $cat.PreviewLabel.VerticalAlignment = 'Bottom'
    $cat.PreviewLabel.Margin = T 12 0 0 10
    $cat.PreviewLabel.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ BlurRadius = 6; ShadowDepth = 1; Opacity = 0.8 }
    # logo and label must not catch the drag
    $cat.PreviewLogo.IsHitTestVisible = $false; $cat.PreviewLabel.IsHitTestVisible = $false
    [void]$pg.Children.Add($canvas); [void]$pg.Children.Add($cat.PreviewLogo); [void]$pg.Children.Add($cat.PreviewLabel)
    $cat.Preview = $p
    [void](Add-To $f $p)

    # framing: drag the preview, wheel or slider to zoom
    $frameRow = New-Panel 'Horizontal'
    $cat.ZoomSlider = New-Object System.Windows.Controls.Slider
    $cat.ZoomSlider.Width = 180
    $cat.ZoomSlider.Minimum = 1; $cat.ZoomSlider.Maximum = 4
    $cat.ZoomSlider.SmallChange = 0.05; $cat.ZoomSlider.LargeChange = 0.25
    $cat.ZoomSlider.VerticalAlignment = 'Center'
    $cat.ZoomText = New-Text '' 12 (Res 'DimBrush')
    $cat.ZoomText.Width = 48
    $cat.ZoomText.Margin = T 10 0 0 0
    $cat.ZoomText.VerticalAlignment = 'Center'
    $btnFrameReset = New-Button 'Reset'
    $btnFrameReset.Margin = T 6 0 0 0
    [void](Add-To $frameRow $cat.ZoomSlider); [void](Add-To $frameRow $cat.ZoomText); [void](Add-To $frameRow $btnFrameReset)
    $cat.FrameRow = $frameRow
    [void](Add-To $f (New-FormRow 'Framing' $frameRow 'Drag the preview to choose the part of the background shown; zoom with the wheel or the slider. The preview has the size of this category''s tiles on this screen.'))

    $p.Add_MouseLeftButtonDown({
            param($s, $e)
            if (-not $bgFrame.Bitmap -or -not (Get-CurrentTile)) { return }
            Limit-Focus
            $bgFrame.Drag = @{ Point = $e.GetPosition($s); FX = $bgFrame.FX; FY = $bgFrame.FY }
            $bgFrame.Moved = $false
            [void]$s.CaptureMouse()
            $e.Handled = $true
        })
    $p.Add_MouseMove({
            param($s, $e)
            $d = $bgFrame.Drag; if (-not $d) { return }
            $pt = $e.GetPosition($s)
            $v = Get-FrameWindow
            $bgFrame.FX = $d.FX - ($pt.X - $d.Point.X) / ($v.S * $v.IW)
            $bgFrame.FY = $d.FY - ($pt.Y - $d.Point.Y) / ($v.S * $v.IH)
            Limit-Focus
            $bgFrame.Moved = $true
            Update-Framing
        })
    $p.Add_MouseLeftButtonUp({ param($s, $e) $s.ReleaseMouseCapture() })
    # end of the drag (also when the capture is lost): written once
    $p.Add_LostMouseCapture({
            if (-not $bgFrame.Drag) { return }
            $bgFrame.Drag = $null
            if ($bgFrame.Moved) { Save-Framing }
        })
    $p.Add_MouseWheel({
            param($s, $e)
            if (-not $bgFrame.Bitmap -or -not (Get-CurrentTile)) { return }
            $e.Handled = $true   # the page must not scroll
            Set-FrameZoom ($bgFrame.Zoom * [Math]::Pow(1.1, $e.Delta / 120)) $e.GetPosition($s)
        })
    $cat.ZoomSlider.Add_ValueChanged({
            param($s, $e)
            if ($bgFrame.Sync -or -not $bgFrame.Bitmap -or -not (Get-CurrentTile)) { return }
            Set-FrameZoom $s.Value
        })
    $btnFrameReset.Add_Click({
            if (-not $bgFrame.Bitmap -or -not (Get-CurrentTile)) { return }
            $bgFrame.FX = 0.5; $bgFrame.FY = 0.5; $bgFrame.Zoom = 1.0
            Update-Framing
            Save-Framing
        })

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
    $moveRow = New-Panel 'Horizontal'
    $cat.MoveTo = New-Object System.Windows.Controls.ComboBox
    $cat.MoveTo.Width = 200
    $btnMove = New-Button 'Move'
    $btnMove.Margin = T 8 0 0 0
    [void](Add-To $moveRow $cat.MoveTo); [void](Add-To $moveRow $btnMove)
    [void](Add-To $f (New-FormRow 'Move to' $moveRow 'Moves the tile and its images to another category. Both category files are saved at once.'))
    $btnMove.Add_Click({
            $t = Get-CurrentTile; if (-not $t) { return }
            $target = $cat.MoveTo.SelectedItem
            if (-not $target) { [void](Show-Dialog 'Raintile' 'Choose the category to move the tile to.'); return }
            $r = Show-Dialog 'Move tile' "Move '$($t.Name)' to $($target.Content)?" @('Move', 'Cancel')
            if ($r.Button -ne 'Move') { return }
            $err = Move-TileToCategory (Get-CurrentFile) $t $target.Tag
            if ($err) { [void](Show-Dialog 'Raintile' $err); return }
            Refresh-Tiles ([Math]::Max(0, $cat.Tiles.SelectedIndex - 1))
        })
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
                if ($s.Tag -eq 'Background') { Reset-Framing $t }
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
                if ($s.Tag -eq 'Background') { Reset-Framing $t }
                Set-Changed (Get-CurrentFile)
                Update-TilePreview
            })
    }

    # --- events
    $cat.Tiles.Add_SelectionChanged({ Show-Tile })

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
            $new = Get-TileName $s.Text
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
    # tiles: new, delete, reorder (hand-written ones only)
    $btnTileNew.Add_Click({
            $file = Get-CurrentFile; if (-not $file) { return }
            $m = Get-Model $file
            $r = Show-Dialog 'New tile' 'Name of the new tile (also the name of its images):' @('Create', 'Cancel') ''
            $name = Get-TileName "$($r.Text)"
            if ($r.Button -ne 'Create' -or -not $name) { return }
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

# --- Games and apps found (Import page) ---------------------------------------------
# Scan.ps1 writes Generated\Found.json; the list shows what is not in the
# launcher yet. The picked items become normal tiles: their images (local,
# SteamGridDB for games, the program icon for apps) are copied to the
# category folders and the category files are written at once.

$found = @{ Items = @(); Scanned = ''; Selected = @{}; Kind = 'all'; ShowAdded = $false; Covers = $true; Filter = '' }
$script:needsRefresh = $false   # tiles written by the list: the skin needs a refresh
$script:scanProcess = $null
$script:foundBuilding = $false

function Read-Found {
    $found.Items = @(); $found.Scanned = ''
    if (-not (Test-Path -LiteralPath $foundFile)) { return }
    try {
        $j = [IO.File]::ReadAllText($foundFile) | ConvertFrom-Json
        $found.Items = @($j.Items | Where-Object { $_ })
        $found.Scanned = "$($j.Scanned)"
    } catch { }
}

# Tiles of every category (as in the window, unsaved changes too):
# name key / command -> category name
function Get-PresentMap {
    $map = @{ Names = @{}; Commands = @{} }
    foreach ($e in Get-CategoryEntries) {
        $m = Get-Model $e.File
        foreach ($s in Get-Tiles $m) {
            $map.Names[(Get-NameKey $s.Name)] = $e.Name
            $cmd = Get-Key $s 'Command'
            if ($cmd) { $map.Commands[$cmd.ToLowerInvariant()] = $e.Name }
        }
        foreach ($n in Get-ImportedNames $m) { $map.Names[(Get-NameKey $n)] = $e.Name }
    }
    return $map
}
function Get-PresentIn($item, $map) {
    $c = $map.Commands["$($item.Command)".ToLowerInvariant()]
    if ($c) { return $c }
    return $map.Names[(Get-NameKey $item.Name)]
}

# Everything in the list has been seen: no dot on the gear until something
# else turns up
function Set-FoundSeen {
    $ids = New-Object 'System.Collections.Generic.HashSet[string]'
    if (Test-Path -LiteralPath $seenFile) { foreach ($l in [IO.File]::ReadAllLines($seenFile)) { if ($l) { [void]$ids.Add($l) } } }
    $before = $ids.Count
    foreach ($it in $found.Items) { [void]$ids.Add($it.Id) }
    if ($ids.Count -eq $before) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $seenFile) | Out-Null
    [IO.File]::WriteAllLines($seenFile, [string[]]@($ids), $utf8)
    Invoke-Rainmeter "!CommandMeasure MeasureScript `"OnFoundSeen()`" `"$Config`""
}

# A new category file (Categories\<base>.ini) and its image folders
function New-CategoryFile([string]$base, [string]$name) {
    $m = [pscustomobject]@{ Header = '; Format: see Games.ini'; Sections = (New-Object System.Collections.ArrayList); Imported = '' }
    $c = Get-CategorySection $m
    Set-Key $c 'Name' $name
    Set-Key $c 'Order' "$(@(Get-CategoryFiles).Count + 1)"
    Write-Category (Join-Path $categoriesDir "$base.ini") $m
    foreach ($kind in 'background', 'logo') { New-Item -ItemType Directory -Force -Path (Join-Path $imagesRoot "$base\$kind") | Out-Null }
    $models["$base.ini"] = $m
    return "$base.ini"
}

function Test-TileName($model, [string]$name) {
    return [bool](($model.Sections | Where-Object { $_.Name -ieq $name }) -or ((Get-ImportedNames $model) -contains $name))
}

# The old automatic import block becomes normal tiles (once)
function Convert-OldImports {
    $n = 0
    foreach ($f in Get-CategoryFiles) {
        $m = Get-Model $f.Name
        if (-not $m.Imported) { continue }
        foreach ($name in @(Get-ImportedNames $m)) { if (Convert-ImportedTile $f.Name $name) { $n++ } }
        $m.Imported = ''   # the marker and its comments go too
        Write-Category (Join-Path $categoriesDir $f.Name) $m
        $changedFiles.Remove($f.Name)
        $script:needsRefresh = $true
    }
    Update-Dirty
    return $n
}

function Update-FoundCount {
    $n = $found.Selected.Count
    $found.AddButton.Content = if ($n) { "Add $n selected" } else { 'Add selected' }
    $found.AddButton.IsEnabled = $n -gt 0
}

function Update-FoundStatus([string]$extra = '') {
    $games = @($found.Items | Where-Object { $_.Kind -eq 'game' }).Count
    $apps = @($found.Items | Where-Object { $_.Kind -eq 'app' }).Count
    $when = ''
    try { $when = ', searched ' + ([DateTime]::Parse($found.Scanned)).ToString('g') } catch { }
    $found.Status.Text = if ($found.Scanned) { "$games games and $apps apps found$when." } else { 'Not searched yet.' }
    if ($extra) { $found.Status.Text = $extra + ' ' + $found.Status.Text }
}

function New-FoundEntry($it, [string]$in) {
    $li = New-Object System.Windows.Controls.ListBoxItem
    $li.Tag = $it
    $li.Padding = T 8 6
    $g = New-Grid @('Auto', 'Auto', '*', 'Auto')
    $tick = New-Object System.Windows.Controls.CheckBox
    $tick.Style = Res 'Tick'
    $tick.IsHitTestVisible = $false
    $tick.VerticalAlignment = 'Center'
    $tick.Margin = T 2 0 12 0
    $binding = New-Object System.Windows.Data.Binding('IsSelected')
    $binding.RelativeSource = New-Object System.Windows.Data.RelativeSource([System.Windows.Data.RelativeSourceMode]::FindAncestor, [System.Windows.Controls.ListBoxItem], 1)
    [void]$tick.SetBinding([System.Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty, $binding)
    [void]$g.Children.Add($tick)
    if ($found.Covers) {
        $b = New-Object System.Windows.Controls.Border
        $b.Width = 96; $b.Height = 45
        $b.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $b.ClipToBounds = $true
        $b.Background = Res 'FieldBg'
        $b.Margin = T 0 0 12 0
        $img = New-Object System.Windows.Controls.Image
        if ($it.Hero -and (Test-Path -LiteralPath $it.Hero)) {
            $img.Stretch = 'UniformToFill'
            $img.Source = Get-Bitmap $it.Hero 192
        } else {
            $img.Stretch = 'Uniform'
            $img.Margin = T 8 5 8 5
            $img.Source = Get-Bitmap $(if ($it.Logo) { $it.Logo } else { $it.Icon }) 96
        }
        $b.Child = $img
        Set-Col $b 1
        [void]$g.Children.Add($b)
    }
    $texts = New-Panel
    $texts.VerticalAlignment = 'Center'
    $title = New-Panel 'Horizontal'
    $t = New-Text $it.Name 13.5
    $t.TextTrimming = 'CharacterEllipsis'
    [void](Add-To $title $t)
    if ($it.New) {
        $badge = New-Object System.Windows.Controls.Border
        $badge.Background = Res 'AccentSoftBrush'
        $badge.CornerRadius = New-Object System.Windows.CornerRadius(3)
        $badge.Padding = T 5 0 5 1
        $badge.Margin = T 8 0 0 0
        $badge.VerticalAlignment = 'Center'
        $badge.Child = New-Text 'NEW' 10 (Res 'AccentBrush') -Bold
        [void](Add-To $title $badge)
    }
    [void](Add-To $texts $title)
    $store = $STORE_LABELS["$($it.Store)"]
    if (-not $store) { $store = "$($it.Store)" }
    [void](Add-To $texts (New-Text "$store   $([char]0xB7)   $(if ($it.Kind -eq 'game') { 'game' } else { 'app' })" 11.5 (Res 'DimBrush')))
    Set-Col $texts 2
    [void]$g.Children.Add($texts)
    if ($in) {
        $note = New-Text "in $in" 12 (Res 'DimBrush')
        $note.VerticalAlignment = 'Center'
        $note.Margin = T 12 0 4 0
        Set-Col $note 3
        [void]$g.Children.Add($note)
        $li.IsEnabled = $false
        $li.Opacity = 0.55
    }
    $li.Content = $g
    return $li
}

function Refresh-FoundList {
    $list = $found.List
    if (-not $list) { return }
    $script:foundBuilding = $true
    try {
        $list.Items.Clear()
        $present = Get-PresentMap
        $words = @($found.Filter.ToLowerInvariant() -split '\s+' | Where-Object { $_ })
        foreach ($it in $found.Items) {
            if ($found.Kind -ne 'all' -and $it.Kind -ne $found.Kind) { continue }
            $in = Get-PresentIn $it $present
            if ($in) { $found.Selected.Remove($it.Id) }
            if ($in -and -not $found.ShowAdded) { continue }
            $hay = "$($it.Name) $($it.Store)".ToLowerInvariant()
            if (@($words | Where-Object { -not $hay.Contains($_) }).Count) { continue }
            $item = New-FoundEntry $it $in
            [void]$list.Items.Add($item)
            if (-not $in -and $found.Selected.ContainsKey($it.Id)) { $item.IsSelected = $true }
        }
        $found.Empty.Visibility = if ($list.Items.Count) { 'Collapsed' } else { 'Visible' }
        $found.Empty.Text = if ($script:scanProcess -and -not $script:scanProcess.HasExited) { 'Searching' + [char]0x2026 }
        elseif (-not $found.Items.Count) { 'Nothing found yet: press Search again.' }
        else { 'Nothing to show: everything is already in the launcher, or hidden by the filters.' }
    } finally { $script:foundBuilding = $false }
    Update-FoundCount
}

# Search in the background (a separate PowerShell): the window stays usable
$scanTimer = New-Object System.Windows.Threading.DispatcherTimer
$scanTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$scanTimer.Add_Tick({
        if (-not $script:scanProcess -or -not $script:scanProcess.HasExited) { return }
        $scanTimer.Stop()
        $found.ScanButton.IsEnabled = $true
        Read-Found
        Refresh-FoundList
        Update-FoundStatus
        Set-FoundSeen
    })

function Start-FoundScan {
    if ($script:scanProcess -and -not $script:scanProcess.HasExited) { return }
    $found.ScanButton.IsEnabled = $false
    $found.Status.Text = 'Searching the stores and the Start menu' + [char]0x2026
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f (Join-Path $PSScriptRoot 'Scan.ps1')),
        '-Resources', ('"{0}"' -f $Resources), '-Stores', ('"{0}"' -f $values['ImportStores']))
    $script:scanProcess = Start-Process -FilePath $exe -ArgumentList $argList -WindowStyle Hidden -PassThru
    Refresh-FoundList
    $scanTimer.Start()
}

# Category file for an added item; created if it does not exist yet
function Get-CategoryFileFor([string]$base) {
    if ($models.ContainsKey("$base.ini") -or (Test-Path -LiteralPath (Join-Path $categoriesDir "$base.ini"))) { return "$base.ini" }
    $file = New-CategoryFile $base $base
    Build-Nav $script:navCurrent
    return $file
}

function Add-SelectedFound {
    $sel = @($found.Items | Where-Object { $found.Selected.ContainsKey($_.Id) })
    if (-not $sel.Count) { return }
    $target = [string]$found.Target.SelectedItem.Tag
    $key = Unprotect-Secret "$($values['SteamGridDBKey'])"
    $present = Get-PresentMap
    $touched = @{}
    $added = 0
    $win.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        for ($i = 0; $i -lt $sel.Count; $i++) {
            $it = $sel[$i]
            $found.Status.Text = "Adding $($i + 1) of $($sel.Count): $($it.Name)" + [char]0x2026
            $win.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
            $found.Selected.Remove($it.Id)
            if (Get-PresentIn $it $present) { continue }
            $base = if ($target -ne 'auto') { [IO.Path]::GetFileNameWithoutExtension($target) }
            elseif ($it.Kind -eq 'game') { "$($values['ImportCategory'])" } else { "$($values['AppsCategory'])" }
            if (-not $base) { $base = if ($it.Kind -eq 'game') { 'Games' } else { 'Apps' } }
            $file = Get-CategoryFileFor $base
            $m = Get-Model $file
            $name = Get-TileName $it.Name
            if (-not $name) { continue }
            if (Test-TileName $m $name) { $name = "$name ($($it.Store))" }
            if (Test-TileName $m $name) { continue }
            $s = [pscustomobject]@{ Name = $name; Comments = @(); Keys = (New-Object System.Collections.ArrayList) }
            Set-Key $s 'Command' $it.Command
            Set-Key $s 'Source' $it.Id
            # images in the default folders, named after the tile
            if ($it.Hero -and (Test-Path -LiteralPath $it.Hero)) { [void](Copy-TileImage $base 'background' $name $it.Hero) }
            elseif ($it.Kind -eq 'game' -and $key) {
                try { [void](Get-SGDBImage $key 'heroes' $name $it.SteamAppId (Join-Path $imagesRoot "$base\background\$name")) } catch { }
            }
            if ($it.Logo -and (Test-Path -LiteralPath $it.Logo)) { [void](Copy-TileImage $base 'logo' $name $it.Logo) }
            elseif ($it.Kind -eq 'game' -and $key) {
                try { [void](Get-SGDBImage $key 'logos' $name $it.SteamAppId (Join-Path $imagesRoot "$base\logo\$name")) } catch { }
            }
            if (-not (Find-Image (Join-Path $imagesRoot "$base\logo") $name) -and $it.Icon -and (Test-Path -LiteralPath $it.Icon)) {
                [void](Copy-TileImage $base 'logo' $name $it.Icon)
            }
            [void]$m.Sections.Add($s)
            $present.Names[(Get-NameKey $name)] = $base
            $present.Commands["$($it.Command)".ToLowerInvariant()] = $base
            $touched[$file] = $true
            $added++
        }
    } finally { $win.Cursor = $null }
    foreach ($f in @($touched.Keys)) {
        Write-Category (Join-Path $categoriesDir $f) (Get-Model $f)
        $changedFiles.Remove($f)
    }
    if ($added) { $script:needsRefresh = $true }
    Update-Dirty
    Refresh-FoundList
    Update-FoundStatus $(if ($added) { "Added ${added}: save and refresh to see them in the launcher." } else { 'Nothing added: already in the launcher.' })
}

function New-FoundCard {
    $card = New-Card 'Found on this PC' ''
    $f = $card.Child

    $converted = Convert-OldImports
    if ($converted) {
        $note = New-Text "$converted games of the old automatic import are now normal tiles: you can edit and move them." 12.5 (Res 'AccentBrush') -Wrap
        $note.Margin = T 0 0 0 8
        [void](Add-To $f $note)
    }

    # search again + status
    $head = New-Grid @('Auto', '*')
    $head.Margin = T 0 2 0 10
    $found.ScanButton = New-Button 'Search again'
    [void]$head.Children.Add($found.ScanButton)
    $found.Status = New-Text '' 12 (Res 'DimBrush') -Wrap
    $found.Status.VerticalAlignment = 'Center'
    $found.Status.Margin = T 12 0 0 0
    Set-Col $found.Status 1
    [void]$head.Children.Add($found.Status)
    [void](Add-To $f $head)

    # filters: type, text, already added, covers
    $filters = New-Object System.Windows.Controls.WrapPanel
    $filters.Margin = T 0 0 0 10
    foreach ($k in @(@('all', 'All'), @('game', 'Games'), @('app', 'Apps'))) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = Res 'Segment'; $rb.Content = $k[1]; $rb.GroupName = 'found_kind'; $rb.Tag = $k[0]
        $rb.IsChecked = ($found.Kind -eq $k[0])
        $rb.Add_Click({ param($s, $e) $found.Kind = $s.Tag; Refresh-FoundList })
        [void]$filters.Children.Add($rb)
    }
    $search = New-Object System.Windows.Controls.TextBox
    $search.Width = 200
    $search.Margin = T 10 2 16 2
    $search.ToolTip = 'Filter by name or store'
    $search.Add_TextChanged({ param($s, $e) $found.Filter = $s.Text; Refresh-FoundList })
    [void]$filters.Children.Add($search)
    foreach ($o in @(@('ShowAdded', 'Show added'), @('Covers', 'Covers'))) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $o[1]; $cb.Tag = $o[0]; $cb.Margin = T 0 4 16 4
        $cb.IsChecked = [bool]$found[$o[0]]
        $cb.Add_Click({ param($s, $e) $found[$s.Tag] = [bool]$s.IsChecked; Refresh-FoundList })
        [void]$filters.Children.Add($cb)
    }
    [void](Add-To $f $filters)

    # the list
    $frame = New-Object System.Windows.Controls.Border
    $frame.BorderBrush = Res 'LineBrush'
    $frame.BorderThickness = T 1
    $frame.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $frame.Padding = T 4
    $frame.Height = 440
    $grid = New-Object System.Windows.Controls.Grid
    $frame.Child = $grid
    $found.List = New-Object System.Windows.Controls.ListBox
    $found.List.SelectionMode = 'Multiple'
    [void]$grid.Children.Add($found.List)
    $found.Empty = New-Text '' 13 (Res 'DimBrush') -Wrap
    $found.Empty.HorizontalAlignment = 'Center'
    $found.Empty.VerticalAlignment = 'Center'
    $found.Empty.IsHitTestVisible = $false
    [void]$grid.Children.Add($found.Empty)
    [void](Add-To $f $frame)
    $found.List.Add_SelectionChanged({
            param($s, $e)
            if ($script:foundBuilding) { return }
            foreach ($i in $e.AddedItems) { $found.Selected[$i.Tag.Id] = $true }
            foreach ($i in $e.RemovedItems) { $found.Selected.Remove($i.Tag.Id) }
            Update-FoundCount
        })

    # select all / none, where, add
    $bottom = New-Grid @('Auto', 'Auto', '*', 'Auto', 'Auto')
    $bottom.Margin = T 0 10 0 6
    $all = New-Button 'Select all' 'LinkButton'
    $none = New-Button 'Select none' 'LinkButton'
    Set-Col $none 1
    [void]$bottom.Children.Add($all); [void]$bottom.Children.Add($none)
    $all.Add_Click({ foreach ($i in $found.List.Items) { if ($i.IsEnabled) { $i.IsSelected = $true } } })
    $none.Add_Click({ $found.List.UnselectAll(); $found.Selected.Clear(); Update-FoundCount })
    $found.Target = New-Object System.Windows.Controls.ComboBox
    $found.Target.Width = 290
    $found.Target.Margin = T 0 0 10 0
    $ci = New-Object System.Windows.Controls.ComboBoxItem
    $ci.Content = "By type: games to $($values['ImportCategory']), apps to $($values['AppsCategory'])"
    $ci.Tag = 'auto'
    [void]$found.Target.Items.Add($ci)
    foreach ($e in Get-CategoryEntries) {
        $ci = New-Object System.Windows.Controls.ComboBoxItem
        $ci.Content = "All to $($e.Name)"
        $ci.Tag = $e.File
        [void]$found.Target.Items.Add($ci)
    }
    $found.Target.SelectedIndex = 0
    Set-Col $found.Target 3
    [void]$bottom.Children.Add($found.Target)
    $found.AddButton = New-Button 'Add selected' 'AccentButton'
    $found.AddButton.Add_Click({ Add-SelectedFound })
    Set-Col $found.AddButton 4
    [void]$bottom.Children.Add($found.AddButton)
    [void](Add-To $f $bottom)

    $found.ScanButton.Add_Click({ Start-FoundScan })
    Read-Found
    Update-FoundStatus
    Refresh-FoundList
    if ($found.Items.Count) { Set-FoundSeen } else { Start-FoundScan }
    return $card
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
    if (-not $NoRefresh) { $script:needsRefresh = $false }
    Update-Dirty
    $status.Text = 'Saved'
    if (-not $NoRefresh) { Invoke-Rainmeter "!Refresh `"$Config`"" }
}

# "Save and refresh": saves, shows a progress bar for 2.5 to 3.5 seconds, then
# closes the window and refreshes the skin, which shows the launcher once it
# has reloaded. The bar does not fill evenly: it goes through a few
# random steps, some quick, some slow, like a real loading.
$overlay = $win.FindName('Overlay')
$progressTrack = $win.FindName('ProgressTrack')
$progressBar = $win.FindName('ProgressBar')
$progressPercent = $win.FindName('ProgressPercent')
$progressStage = $win.FindName('ProgressStage')
$script:refreshing = $false
$script:refreshStart = [DateTime]::Now
$random = New-Object System.Random

# Steps of the bar: Times (ms from the start) and Values (0-1), both rising
function New-ProgressPlan {
    $total = 2500 + $random.Next(0, 1001)
    $steps = 5 + $random.Next(0, 3)
    $timeWeights = @(1..$steps | ForEach-Object { 0.4 + $random.NextDouble() })
    # some steps barely move: pauses
    $valueWeights = @(1..$steps | ForEach-Object { if ($random.NextDouble() -lt 0.3) { 0.02 } else { 0.2 + $random.NextDouble() } })
    $tSum = ($timeWeights | Measure-Object -Sum).Sum
    $vSum = ($valueWeights | Measure-Object -Sum).Sum
    $times = @(0.0); $vals = @(0.0); $t = 0.0; $v = 0.0
    for ($i = 0; $i -lt $steps; $i++) {
        $t += $timeWeights[$i] / $tSum * $total
        $v += $valueWeights[$i] / $vSum
        $times += $t; $vals += $v
    }
    $vals[$steps] = 1.0
    return @{ Total = $total; Times = $times; Values = $vals }
}

# Progress (0-1) after 'elapsed' ms: each step eases out
function Get-PlannedProgress($plan, [double]$elapsed) {
    if ($elapsed -ge $plan.Total) { return 1.0 }
    for ($i = 0; $i -lt $plan.Times.Count - 1; $i++) {
        if ($elapsed -lt $plan.Times[$i + 1]) {
            $f = ($elapsed - $plan.Times[$i]) / ($plan.Times[$i + 1] - $plan.Times[$i])
            $f = 1 - (1 - $f) * (1 - $f)
            return $plan.Values[$i] + ($plan.Values[$i + 1] - $plan.Values[$i]) * $f
        }
    }
    return 1.0
}

$refreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$refreshTimer.Interval = [TimeSpan]::FromMilliseconds(30)
$refreshTimer.Add_Tick({
        $p = Get-PlannedProgress $script:progressPlan ([DateTime]::Now - $script:refreshStart).TotalMilliseconds
        $progressBar.Width = $p * $progressTrack.ActualWidth
        $progressPercent.Text = "$([int][Math]::Floor($p * 100))%"
        $progressStage.Text = if ($p -lt 0.3) { 'Saving the settings' + [char]0x2026 }
        elseif ($p -lt 0.85) { 'Refreshing the skin' + [char]0x2026 }
        else { 'Opening the launcher' + [char]0x2026 }
        if ($p -ge 1) {
            $refreshTimer.Stop()
            $overlay.Visibility = 'Collapsed'
            $script:refreshing = $false
            # the launcher shows itself when it has reloaded (Generated\ShowOnLoad);
            # the window closes first, so the launcher does not open over it
            try { [IO.File]::WriteAllText((Join-Path $Resources 'Generated\ShowOnLoad'), '', $utf8) } catch { }
            $win.Close()
            Invoke-Rainmeter "!Refresh `"$Config`""
        }
    })

function Start-SaveAndRefresh {
    if ($script:refreshing) { return }
    $script:needsRefresh = $false
    Save-All -NoRefresh   # the refresh comes at the end of the bar
    $script:refreshing = $true
    $script:progressPlan = New-ProgressPlan
    $progressBar.Width = 0
    $progressPercent.Text = '0%'
    $progressStage.Text = 'Saving the settings' + [char]0x2026
    $overlay.Visibility = 'Visible'
    $script:refreshStart = [DateTime]::Now
    $refreshTimer.Start()
}

function Invoke-Action([string]$action) {
    switch ($action) {
        'OpenSettings' { Start-Process notepad.exe -ArgumentList "`"$settingsFile`"" }
        'OpenFolder' { Start-Process explorer.exe -ArgumentList "`"$Data`"" }
        'OpenSkinFolder' { Start-Process explorer.exe -ArgumentList "`"$(Split-Path -Parent $Resources)`"" }
        'OpenRainmeter' { Invoke-Rainmeter '!Manage' }
        'OpenGuide' { Start-Process 'https://github.com/Derek3rd/raintile/blob/main/docs/Guide.md' }
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

# --- Updates (Info page) -----------------------------------------------------------
# Update.ps1 keeps the last check in Update.json (data folder). "Download and
# install" downloads the release's .rmskin and opens it: the Rainmeter
# installer takes over (your data is not in the skin folder, so it stays).

$upd = @{}

function Show-UpdateInfo {
    $info = Read-UpdateInfo
    $installed = Get-InstalledVersion
    $upd.Installed.Text = $installed
    if (-not $info) {
        $upd.Latest.Text = 'Not checked yet'
    } elseif ($info.Error) {
        $upd.Latest.Text = "Check failed: $($info.Error)"
    } else {
        $when = ''
        try { $when = '   ' + [char]0xB7 + '   checked ' + ([DateTime]::Parse($info.Checked)).ToString('g') } catch { }
        $upd.Latest.Text = $(if ($info.Latest) { $info.Latest } else { 'unknown' }) + $when
    }
    $newer = $info -and $info.Newer -and $info.Current -eq $installed
    $upd.Status.Text = if ($newer) { "Raintile $($info.Latest) is available." } elseif ($info -and -not $info.Error) { 'Raintile is up to date.' } else { '' }
    $upd.Status.Foreground = if ($newer) { Res 'AccentBrush' } else { Res 'DimBrush' }
    $upd.Notes.Text = if ($newer -and $info.Notes) { $info.Notes } else { '' }
    $upd.NotesBox.Visibility = if ($upd.Notes.Text) { 'Visible' } else { 'Collapsed' }
    $upd.Install.Visibility = if ($newer) { 'Visible' } else { 'Collapsed' }
    $upd.Install.Content = if ($newer -and $info.Asset) { 'Download and install' } else { 'Open the release page' }
    $upd.Page.Visibility = if ($info -and $info.Page) { 'Visible' } else { 'Collapsed' }
}

function Invoke-CheckNow {
    $upd.Status.Text = 'Checking' + [char]0x2026
    $win.Cursor = [System.Windows.Input.Cursors]::Wait
    $win.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
    try { $info = Invoke-UpdateCheck } finally { $win.Cursor = $null }
    Show-UpdateInfo
    # no dot on the gear without an update
    if (-not $info.Error -and -not $info.Newer) { Invoke-Rainmeter "!CommandMeasure MeasureScript `"OnUpdateSeen()`" `"$Config`"" }
}

# Opens the release page (only a GitHub page of this repository)
function Open-ReleasePage($info) {
    $page = if ($info -and (Test-ReleaseUrl $info.Page)) { $info.Page } else { "https://github.com/$Repository/releases" }
    Start-Process $page
}

function Install-Update {
    $info = Read-UpdateInfo
    if (-not $info) { return }
    if (-not (Test-ReleaseUrl $info.Asset)) { Open-ReleasePage $info; return }
    $r = Show-Dialog 'Update Raintile' ("Download Raintile $($info.Latest) and open the Rainmeter installer?`r`n`r`n" +
        "Your settings, categories and images stay: they are in $Data, which the installer does not touch. " +
        "In the installer keep the default options and press Install.`r`n`r`n" +
        "This is still experimental: keep a copy of your data folder first.") @('Download and install', 'Cancel')
    if ($r.Button -ne 'Download and install') { return }
    # a new folder of its own, and a name made here: nothing else can be
    # put in its place before it is opened
    $version = Get-SafeVersion $info.Latest
    $folder = Join-Path $env:TEMP ('Raintile-update-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $dest = Join-Path $folder $(if ($version) { "Raintile_$version.rmskin" } else { 'Raintile_update.rmskin' })
    $upd.Status.Text = 'Downloading' + [char]0x2026
    $win.Cursor = [System.Windows.Input.Cursors]::Wait
    $win.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $info.Asset -OutFile $dest -UseBasicParsing -TimeoutSec 180
    } catch {
        $win.Cursor = $null
        $upd.Status.Text = "Download failed: $($_.Exception.Message)"
        return
    }
    $win.Cursor = $null
    if (-not (Test-RmskinPackage $dest)) {
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
        $upd.Status.Text = 'The downloaded file is not a Rainmeter package: nothing was installed.'
        return
    }
    # .rmskin files open with the Rainmeter skin installer; this window closes
    # so that nothing of the skin folder is in use
    Start-Process -FilePath $dest
    $win.Close()
}

function New-UpdateCard {
    $card = New-Card 'Updates' ''
    $f = $card.Child
    $beta = New-Text ('Experimental: installing updates from here is still being tested and could cause problems. ' +
        'Before installing, keep a copy of your data folder; if something goes wrong, the release page has the package to install by hand.') 12.5 (Res 'AccentBrush') -Wrap
    $beta.Margin = T 0 0 0 6
    [void](Add-To $f $beta)
    foreach ($row in @(@('Installed', 'Installed'), @('Latest', 'Latest version'))) {
        $v = New-Text '' 13 -Wrap
        $v.MaxWidth = 460
        $v.TextAlignment = 'Right'
        $upd[$row[0]] = $v
        [void]$f.Children.Add((New-Row $row[1] '' $v $null))
    }
    $upd.Status = New-Text '' 13.5 -Wrap
    $upd.Status.Margin = T 0 12 0 6
    [void](Add-To $f $upd.Status)
    $notesBox = New-Object System.Windows.Controls.Border
    $notesBox.Background = Res 'FieldBg'
    $notesBox.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $notesBox.Padding = T 14 10
    $notesBox.Margin = T 0 0 0 10
    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.MaxHeight = 220
    $sv.VerticalScrollBarVisibility = 'Auto'
    $upd.Notes = New-Text '' 12.5 (Res 'DimBrush') -Wrap
    $sv.Content = $upd.Notes
    $notesBox.Child = $sv
    $upd.NotesBox = $notesBox
    [void](Add-To $f $notesBox)
    $bar = New-Panel 'Horizontal'
    $bar.Margin = T 0 4 0 10
    $upd.Install = New-Button 'Download and install' 'AccentButton'
    $upd.Install.Margin = T 0 0 8 0
    $check = New-Button 'Check now'
    $check.Margin = T 0 0 8 0
    $upd.Page = New-Button 'Release page' 'LinkButton'
    $upd.Page.VerticalAlignment = 'Center'
    foreach ($b in $upd.Install, $check, $upd.Page) { [void](Add-To $bar $b) }
    [void](Add-To $f $bar)
    $upd.Install.Add_Click({ Install-Update })
    $check.Add_Click({ Invoke-CheckNow })
    $upd.Page.Add_Click({ Open-ReleasePage (Read-UpdateInfo) })
    Show-UpdateInfo
    return $card
}

# Info page: what Raintile is, version, where it is, and its files
function New-InfoPage {
    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'
    $sp = New-Panel
    $sp.Margin = T 36 4 36 24
    $sp.MaxWidth = 920
    $sp.HorizontalAlignment = 'Left'
    $sv.Content = $sp

    $card = New-Card '' ''
    $card.Padding = T 24 20 24 20
    $head = New-Panel 'Horizontal'
    [void](Add-To $head (New-Text 'Raintile' 26 -Bold))
    if ($version) {
        $badge = New-Object System.Windows.Controls.Border
        $badge.Background = Res 'AccentSoftBrush'
        $badge.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $badge.Padding = T 8 2 8 2
        $badge.Margin = T 12 4 0 0
        $badge.VerticalAlignment = 'Center'
        $badge.Child = New-Text $version 12 (Res 'AccentBrush') -Bold
        [void](Add-To $head $badge)
    }
    [void](Add-To $card.Child $head)
    $about = New-Text $(if ($information) { $information } else { 'Full-screen tile launcher for Rainmeter.' }) 13.5 (Res 'DimBrush') -Wrap
    $about.Margin = T 0 8 0 0
    [void](Add-To $card.Child $about)
    $more = New-Text 'Categories in a menu at the top, tiles with background art and logo, mouse, keyboard and gamepad, search, games and apps found on this PC. Every setting is described in the Guide, on GitHub.' 12.5 (Res 'DimBrush') -Wrap
    $more.Margin = T 0 6 0 0
    [void](Add-To $card.Child $more)
    [void](Add-To $sp $card)

    $entries = Get-CategoryEntries
    $tiles = ($entries | Measure-Object -Property Tiles -Sum).Sum
    $imported = ($entries | Measure-Object -Property Imported -Sum).Sum
    $card = New-Card 'Details' ''
    foreach ($row in @(
            @('Version', $(if ($version) { $version.Substring(1) } else { 'unknown' })),
            @('Rainmeter skin', $Config),
            @('Your data', $Data),
            @('Skin folder', (Split-Path -Parent $Resources)),
            @('Categories', "$(@($entries).Count)"),
            @('Tiles', "$([int]$tiles) written by hand, $([int]$imported) imported")
        )) {
        $v = New-Text $row[1] 13 -Wrap
        $v.MaxWidth = 460
        $v.TextAlignment = 'Right'
        [void]$card.Child.Children.Add((New-Row $row[0] '' $v $null))
    }
    [void](Add-To $sp $card)

    [void](Add-To $sp (New-UpdateCard))

    $card = New-Card 'Files' ''
    [void]$card.Child.Children.Add((New-Row 'Settings' 'Settings.inc, in Notepad.' (New-ActionControl 'OpenSettings' 'Open Settings.inc') $null))
    [void]$card.Child.Children.Add((New-Row 'Your data' 'Settings, categories and images: updates never touch this folder.' (New-ActionControl 'OpenFolder' 'Open the folder') $null))
    [void]$card.Child.Children.Add((New-Row 'Skin folder' 'Scripts and the default files of this version.' (New-ActionControl 'OpenSkinFolder' 'Open the folder') $null))
    [void]$card.Child.Children.Add((New-Row 'Rainmeter' 'The Manage window: skins, Rainmeter settings and log.' (New-ActionControl 'OpenRainmeter' 'Open Rainmeter') $null))
    [void]$card.Child.Children.Add((New-Row 'Guide' 'Every setting, the controls and troubleshooting, on GitHub.' (New-ActionControl 'OpenGuide' 'Open the Guide') $null))
    [void](Add-To $sp $card)
    return $sv
}

function Show-Page($page) {
    if ($page.Id -eq 'info') { $pages.Remove('info') }   # the counts may have changed
    if (-not $pages.ContainsKey($page.Id)) {
        $script:updating = $true
        try {
            $pages[$page.Id] = if ($page.Id -eq 'categories') { New-CategoryListPage }
            elseif ($page.Id -eq 'info') { New-InfoPage }
            else { New-SettingsPage $page }
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
    $pageDesc.Text = "Categories\${file}: its tiles. Name, icon and grid of the category are on the Categories page."
}

function Show-NavTarget($tag) {
    switch ($tag.Type) {
        'page' { Show-Page $tag.Page }
        'category' { Show-CategoryPage $tag.File }
        'group' { return }
    }
    $script:navCurrent = $tag.Id
}

# Info, at the bottom of the menu: a list of its own, only one of the two
# lists has a selection
$navBottom = $win.FindName('NavBottom')
[void]$navBottom.Items.Add((New-NavItem 'page:info' 'Info' $schemaById['info'].Icon 0 @{ Type = 'page'; Page = $schemaById['info'] }))
$navBottom.Add_SelectionChanged({
        if ($script:navBuilding -or -not $navBottom.SelectedItem) { return }
        $script:navBuilding = $true
        $nav.SelectedItem = $null
        $script:navBuilding = $false
        Show-NavTarget $navBottom.SelectedItem.Tag
    })

$nav.Add_SelectionChanged({
        if ($script:navBuilding) { return }
        $sel = $nav.SelectedItem
        if (-not $sel) { return }
        $script:navBuilding = $true
        $navBottom.SelectedItem = $null
        $script:navBuilding = $false
        $tag = $sel.Tag
        if ($tag.Type -eq 'group') {
            # reached with the keyboard: open the group on its first entry
            $navOpen[$tag.Group] = $true
            Open-Nav $tag.First
            return
        }
        Show-NavTarget $tag
    })

$btnSave.Add_Click({ Start-SaveAndRefresh })
$win.FindName('BtnClose').Add_Click({ $win.Close() })
$win.Add_PreviewKeyDown({
        param($s, $e)
        if ($script:refreshing) { $e.Handled = $true; return }   # waiting for the skin
        if ($e.Key -eq 'S' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control' -and -not $script:capturing) {
            $e.Handled = $true
            Start-SaveAndRefresh
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

# Tile to open on (-Page tile): "file|name" left by the skin, used once. The
# file must be one of the categories; a tile no longer there leaves the
# first one selected.
function Read-EditTile {
    $path = Join-Path $Resources 'Generated\EditTile.txt'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $parts = [IO.File]::ReadAllText($path).Split('|', 2)
        Remove-Item -LiteralPath $path -Force
    } catch { return $null }
    if ($parts.Count -ne 2) { return $null }
    $file = $parts[0].Trim()
    $match = Get-CategoryFiles | Where-Object { $_.Name -ieq $file } | Select-Object -First 1
    if (-not $match) { return $null }
    return @{ File = $match.Name; Name = $parts[1].Trim() }
}

$script:updating = $false
$editTile = if ($OpenPage -eq 'tile') { Read-EditTile } else { $null }
if ($OpenPage -eq 'info') {
    # Info is in the list at the bottom: selecting it shows it
    Build-Nav ''
    $navBottom.SelectedIndex = 0
} elseif ($editTile) {
    $navOpen['categories'] = $true
    Build-Nav "cat:$($editTile.File)"
    if ($nav.SelectedItem) { Show-NavTarget $nav.SelectedItem.Tag }
    for ($i = 0; $cat.Tiles -and $i -lt $cat.Tiles.Items.Count; $i++) {
        $sec = $cat.Tiles.Items[$i].Tag.Section
        if ($sec -and $sec.Name -ieq $editTile.Name) {
            $cat.Tiles.SelectedIndex = $i
            $cat.Tiles.ScrollIntoView($cat.Tiles.Items[$i])
            break
        }
    }
} else {
    Build-Nav $(if ($OpenPage -eq 'import') { 'page:import' } else { 'page:general' })
    Show-NavTarget $nav.SelectedItem.Tag
}
Update-Dirty
[void]$win.ShowDialog()
$app.Shutdown()
