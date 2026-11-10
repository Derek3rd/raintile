# Helper.ps1: the gamepad buttons (RaintilePad.Step), compiled from the
# helper's C# without running it.

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
