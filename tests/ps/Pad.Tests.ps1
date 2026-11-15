# Helper.ps1: the gamepad buttons (RaintilePad.Step), the launcher's window
# among the skins and the wait of the main loop, compiled from the helper's
# C# without running it.

$helperScript = Join-Path $Root '@Resources\Scripts\Helper.ps1'

if (-not ('RaintilePad' -as [type])) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($helperScript, [ref]$tokens, [ref]$errors)
    $assign = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left.Extent.Text -eq '$source' }, $true)
    if (-not $assign) { throw "no `$source in $helperScript" }
    Add-Type -AssemblyName System.Management, System.Web.Extensions
    $refs = @([System.Management.ManagementScope].Assembly.Location,
        [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location)
    Add-Type -TypeDefinition $assign.Right.Expression.Value -Language CSharp -ReferencedAssemblies $refs
}

# A pad with the default buttons and the given ones; Press runs one read and
# returns what the launcher gets, as "Function(args)" (Pad() left out)
function New-Pad([string]$Bindings = '') {
    $pad = New-Object RaintilePad('Raintile', 12000, 350, 110)
    $pad.SetBindings($Bindings)
    return @{ Pad = $pad; Now = [long]0 }
}

function Press($p, [string]$Buttons, [int]$Lx = 0, [int]$Ly = 0, [int]$Ms = 16) {
    $p.Now += $Ms
    $out = @($p.Pad.Step([RaintilePad]::ParseButtons($Buttons), $Lx, $Ly, $p.Now))
    return @($out | ForEach-Object {
        if ($_ -match "Pad\('(\w+)',?([^)]*)\)") { "$($Matches[1])($($Matches[2]))" }
        elseif ($_ -match '"(\w+)\(\)"') { "$($Matches[1])()" }
        else { $_ }
    }) -join ' '
}

Test 'Pad: one button acts when pressed, once' {
    $p = New-Pad
    Assert-Equal (Press $p 'A') 'Confirm()' 'A pressed'
    Assert-Equal (Press $p 'A') '' 'A held'
    Assert-Equal (Press $p '') '' 'A released'
    Assert-Equal (Press $p 'Y') 'PadSearch()' 'Y'
    Assert-Equal (Press $p 'LB') 'NextCategory(-1)' 'LB'
}

Test 'Pad: Back + Start opens and closes, Start alone is Done on release' {
    $p = New-Pad
    Assert-Equal (Press $p 'BACK') '' 'Back alone'
    Assert-Equal (Press $p 'BACK START') 'Toggle()' 'Back + Start'
    Assert-Equal (Press $p 'START') '' 'Back released'
    Assert-Equal (Press $p '') '' 'Start released after the combination'
    # Start first, then Back: still the combination, no Done
    Assert-Equal (Press $p 'START') '' 'Start pressed'
    Assert-Equal (Press $p 'START BACK') 'Toggle()' 'then Back'
    Assert-Equal (Press $p '') '' 'both released'
    Assert-Equal (Press $p 'START') '' 'Start alone pressed'
    Assert-Equal (Press $p '') 'PadStart()' 'Start alone released'
}

Test 'Pad: a combination of two buttons, its buttons alone on release' {
    $p = New-Pad 'Options=LB RB'
    Assert-Equal (Press $p 'LB') '' 'LB pressed (part of LB + RB)'
    Assert-Equal (Press $p 'LB RB') 'PadOptions()' 'LB + RB'
    Assert-Equal (Press $p '') '' 'released'
    Assert-Equal (Press $p 'RB') '' 'RB alone'
    Assert-Equal (Press $p '') 'NextCategory(1)' 'RB released'
    # held together again only after both were released
    Assert-Equal (Press $p 'LB RB') 'PadOptions()' 'LB + RB at once'
    Assert-Equal (Press $p 'LB') '' 'RB released'
    Assert-Equal (Press $p 'LB RB') '' 'RB again, LB still held'
}

Test 'Pad: directions repeat, the left stick moves whatever the buttons' {
    $p = New-Pad 'Up=Y'
    Assert-Equal (Press $p 'DOWN') 'Nav(0,1)' 'down'
    Assert-Equal (Press $p 'DOWN' -Ms 300) '' 'before the delay'
    Assert-Equal (Press $p 'DOWN' -Ms 60) 'Nav(0,1)' 'after the delay'
    Assert-Equal (Press $p 'DOWN' -Ms 50) '' 'before the interval'
    Assert-Equal (Press $p 'DOWN' -Ms 70) 'Nav(0,1)' 'after the interval'
    Assert-Equal (Press $p '') '' 'released'
    Assert-Equal (Press $p 'Y') 'Nav(0,-1)' 'Y is up'
    Assert-Equal (Press $p '') '' 'Y released'
    Assert-Equal (Press $p 'UP') '' 'the D-pad up has no action'
    Assert-Equal (Press $p '' -Ly 30000) 'Nav(0,-1)' 'the stick up'
    Assert-Equal (Press $p '' -Ly 30000) '' 'the stick held'
    Assert-Equal (Press $p 'DOWN' -Ly -30000) 'Nav(0,1)' 'the stick and the D-pad down: once'
}

Test 'Pad: no button, and the same buttons on two actions' {
    $p = New-Pad 'Search=;Options=A'
    Assert-Equal (Press $p 'Y') '' 'Search without a button'
    Assert-Equal (Press $p '') '' 'released'
    Assert-Equal (Press $p 'A') 'Confirm()' 'A: Launch, not Options'
    Assert-Equal (Press $p '') '' 'released'
    Assert-Equal (Press $p 'RS') '' 'RS no longer Options'
}

Test 'Pad: the pad shortcuts of the tiles, after the actions' {
    $p = New-Pad
    # (Generated\PadKeys.txt: one combination per line; the second is Back's)
    $p.Pad.SetTiles(@('A LB', 'B', 'x+y'))
    Assert-Equal (Press $p 'LB') '' 'LB, part of a shortcut: waits'
    Assert-Equal (Press $p 'LB A') 'PadTile(1)' 'LB + A: the first tile'
    Assert-Equal (Press $p '') '' 'released: no category'
    Assert-Equal (Press $p 'LB') '' 'LB alone pressed'
    Assert-Equal (Press $p '') 'NextCategory(-1)' 'LB alone released'
    Assert-Equal (Press $p 'B') 'Escape()' 'B stays Back'
    Assert-Equal (Press $p '') '' 'released'
    Assert-Equal (Press $p 'Y X') 'PadTile(3)' 'X + Y, written another way'
}

Test 'Pad: the Rainside has no button by default; its own open it, also hidden' {
    $p = New-Pad
    foreach ($b in @('LS', 'RS', 'BACK', 'START')) {
        Assert-True ((Press $p $b) -notmatch 'RainsideToggle') "$b opened the Rainside by default"
        [void](Press $p '')
    }
    $p = New-Pad 'Rainside=LS'
    Assert-Equal (Press $p 'LS') 'RainsideToggle()' 'LS'
    Assert-Equal (Press $p '') '' 'released'
}

# --- Keyboard (RaintileKeys) ---------------------------------------------------

function Combo([string]$Text) { $k = [RaintileKeys]::ParseCombo($Text); if ($null -eq $k) { return 'null' }; return ($k | ForEach-Object { '{0:X2}' -f $_ }) -join ' ' }

Test 'Keys: the HotKey plugin names, as Settings.inc and the Options window write them' {
    Assert-Equal (Combo 'CTRL ALT G') '11 12 47' 'CTRL ALT G'
    Assert-Equal (Combo 'ctrl alt g') '11 12 47' 'lower case'
    Assert-Equal (Combo 'LWIN SPACE') '20 5B' 'LWIN SPACE'
    Assert-Equal (Combo 'ESCAPE') '1B' 'ESCAPE'
    Assert-Equal (Combo 'NUM7') '67' 'NUM7'
    Assert-Equal (Combo 'F12') '7B' 'F12'
    Assert-Equal (Combo 'F24') '87' 'F24'
    Assert-Equal (Combo '7') '37' 'a digit'
    Assert-Equal (Combo '0x41') '41' 'hex'
    Assert-Equal (Combo '65') '41' 'decimal'
    Assert-Equal (Combo 'SHIFT LSHIFT A') '10 41' 'SHIFT covers LSHIFT'
    Assert-Equal (Combo 'LCTRL RALT 1') '31 A2 A5' 'left and right kept'
    Assert-Equal (Combo 'CTRL NOPE') 'null' 'an unknown name'
    Assert-Equal (Combo '') 'null' 'empty'
    # every name the Options window writes (Schema.VkNames) and the defaults
    $names = 'BACKSPACE TAB ENTER PAUSE CAPSLOCK ESCAPE SPACE PAGEUP PAGEDOWN END HOME LEFT UP RIGHT DOWN PRINTSCREEN INSERT DELETE ' +
        'LWIN RWIN MENU MULT ADD SUBTRACT DECIMAL DIVIDE NUMLOCK SCROLLLOCK SHIFT CTRL ALT LSHIFT RSHIFT LCTRL RCTRL LALT RALT ' +
        'COLON PLUS COMMA MINUS PERIOD FORWARDSLASH BACKTICK LBRACKET BACKSLASH RBRACKET QUOTE NUM0 NUM9 F1 A Z 0 9 W S D Q E F'
    foreach ($n in $names.Split(' ')) { Assert-True ((Combo $n) -ne 'null') "$n not read" }
}

Test 'Keys: the plugin rule, the key of the combination with the others held' {
    $held = New-Object 'System.Collections.Generic.HashSet[int]'
    $isHeld = [Func[int, bool]] { param($k) $held.Contains($k) }
    $combo = [RaintileKeys]::ParseCombo('CTRL ALT G')
    Assert-True (-not [RaintileKeys]::Fires($combo, 0x47, $isHeld)) 'G alone'
    [void]$held.Add(0x11); [void]$held.Add(0x12)
    Assert-True ([RaintileKeys]::Fires($combo, 0x47, $isHeld)) 'G with CTRL ALT held'
    [void]$held.Add(0x10)
    Assert-True ([RaintileKeys]::Fires($combo, 0x47, $isHeld)) 'SHIFT held too: still (as the plugin)'
    Assert-True (-not [RaintileKeys]::Fires($combo, 0x48, $isHeld)) 'another key'
    $held.Clear()
    $w = [RaintileKeys]::ParseCombo('W')
    Assert-True ([RaintileKeys]::Fires($w, 0x57, $isHeld)) 'one key'
}

Test 'Keys: the list of the skin (Generated\HotKeys.txt)' {
    $log = $false
    $list = [RaintileKeys]::ParseList(@('CTRL ALT G|down|Raintile|Toggle()', 'ENTER|up|Raintile|Confirm()',
        "SPACE|down|Raintile|TypeKey(' ')", 'log', 'end'), [ref]$log)
    Assert-Equal $list.Count 3 'bindings'
    Assert-True $log 'log'
    Assert-True ($list[1].Up) 'ENTER on release'
    Assert-Equal $list[2].Function "TypeKey(' ')" 'the function'
    Assert-Equal ([RaintileKeys]::ParseList(@('CTRL ALT G|down|Raintile|Toggle()'), [ref]$log)) $null 'no end: being written'
    $list = [RaintileKeys]::ParseList(@('NOPE|down|Raintile|Toggle()', 'A|sideways|Raintile|Toggle()', 'A|down||Toggle()',
        'A|down|Raintile|Toggle', 'A|down|Raintile|X("y")', 'A|down|Raintile|X()][!Quit]', 'A|down', 'end'), [ref]$log)
    Assert-Equal $list.Count 0 'lines not valid are left out'
    Assert-True (-not $log) 'no log line'
}

# The launcher's window among Rainmeter's skins ("w, h, visible 1/0" each)
function Pick([object[]]$Skins, [int]$W, [int]$H) {
    $list = New-Object 'System.Collections.Generic.List[int[]]'
    foreach ($s in $Skins) { $list.Add([int[]]$s) }
    return [RaintilePad]::PickLauncher($list.ToArray(), $W, $H)
}

Test 'Helper: the launcher hidden is never another skin' {
    # (a bigger skin on the desktop: its focus was followed in the launcher's place)
    Assert-Equal (Pick @(@(2560, 1440, 1), @(1792, 974, 0), @(300, 200, 1)) 1792 974) 1 'hidden, among visible skins'
    Assert-Equal (Pick @(@(2560, 1440, 1), @(1792, 974, 1)) 1792 974) 1 'shown, next to a bigger skin'
    Assert-Equal (Pick @(@(1792, 974, 0), @(1793, 973, 1)) 1792 974) 1 'the visible one of its size first (a pixel off)'
    Assert-Equal (Pick @(@(300, 200, 1), @(2560, 1440, 1), @(900, 900, 0)) 1792 974) 1 'no window of its size: the largest visible'
    Assert-Equal (Pick @(@(300, 200, 1), @(2560, 1440, 1), @(4000, 4000, 0)) 0 0) 1 'no size: the largest visible'
    Assert-Equal (Pick @(, @(300, 200, 0)) 0 0) -1 'nothing visible, no size'
    Assert-Equal (Pick @() 1792 974) -1 'no skin'
}

Test 'Helper: the loop waits longer at rest, not with a controller' {
    $pad = New-Object RaintilePad('Raintile', 12000, 350, 110)
    Assert-Equal ($pad.Wait($false, 0)) ([RaintilePad]::IDLE_WAIT) 'at rest'
    Assert-Equal ($pad.Wait($true, 0)) ([RaintilePad]::ACTIVE_WAIT) 'a controller connected'
    Assert-True ([RaintilePad]::IDLE_WAIT -ge 50 -and [RaintilePad]::ACTIVE_WAIT -le 16) 'the two waits'
}
