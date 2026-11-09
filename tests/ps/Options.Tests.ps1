# The Options program (src/Options): its helpers that hold a rule of
# docs/OptionsUI.md, called on the built program. Windows only, with the
# program in @Resources\Bin when it is newer than its sources (dev-build.ps1),
# otherwise built here (needs the .NET SDK); without either the tests are
# skipped and say so.

function Get-OptionsProgram {
    if ($env:OS -ne 'Windows_NT') { return $null }
    $src = Join-Path $Root 'src\Options'
    $newest = (Get-ChildItem -LiteralPath $src -Recurse -File | Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } |
        Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
    $exe = Join-Path $Root '@Resources\Bin\RaintileOptions.exe'
    if ((Test-Path -LiteralPath $exe) -and (Get-Item -LiteralPath $exe).LastWriteTimeUtc -ge $newest) { return $exe }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { return $null }
    $out = Join-Path $Root 'build\options-tests'
    $log = & dotnet build (Join-Path $src 'RaintileOptions.csproj') -c Release -o $out -nologo -v q 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("the Options program does not build:`n" + ($log -join "`n")) }
    return (Join-Path $out 'RaintileOptions.exe')
}

$optionsExe = Get-OptionsProgram
if (-not $optionsExe) {
    Write-Output 'skip Options: no built program and no .NET SDK (or not Windows)'
    return
}
Add-Type -AssemblyName PresentationFramework
$optionsApp = [System.Reflection.Assembly]::LoadFrom($optionsExe).GetType('RaintileOptions.OptionsApp')
function Invoke-Options([string]$Name, [object[]]$Arguments) {
    # New-Object wraps what it makes in a PSObject: reflection wants the object
    # (assigned, not output: a list written to the pipeline becomes an array)
    $plain = New-Object object[] $Arguments.Count
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = $Arguments[$i]
        if ($null -ne $a) { $a = $a.psobject.BaseObject }
        $plain[$i] = $a
    }
    return $optionsApp.GetMethod($Name).Invoke($null, $plain)
}

Test 'Options: IsPartialNumber lets through only what can still be a number' {
    $all = '0123456789.-'
    foreach ($ok in '', '-', '7', '-70.5', '.5', '70.') { Assert-True (Invoke-Options 'IsPartialNumber' @($all, $ok)) "'$ok' refused" }
    foreach ($bad in '70-', '--7', '7.0.', '7a', ' 7', '7,5') { Assert-True (-not (Invoke-Options 'IsPartialNumber' @($all, $bad))) "'$bad' taken" }
    # a size: no minus sign; a count: no decimals either
    Assert-True (-not (Invoke-Options 'IsPartialNumber' @('0123456789.', '-7'))) 'minus taken by a box without it'
    Assert-True (-not (Invoke-Options 'IsPartialNumber' @('0123456789', '7.5'))) 'decimal point taken by a box without it'
}

Test 'Options: the carousel takes only odd numbers, the next one within the range' {
    Assert-Equal (Invoke-Options 'OddNumber' @([double]5, [double]1, [double]12, $false)) ([double]5) 'odd kept'
    Assert-Equal (Invoke-Options 'OddNumber' @([double]4, [double]1, [double]12, $false)) ([double]5) 'even: the next one'
    Assert-Equal (Invoke-Options 'OddNumber' @([double]4, [double]1, [double]12, $true)) ([double]3) 'even, slider moved down'
    Assert-Equal (Invoke-Options 'OddNumber' @([double]12, [double]1, [double]12, $false)) ([double]11) 'the maximum, even'
    Assert-Equal (Invoke-Options 'OddNumber' @([double]2, [double]1, [double]8, $true)) ([double]1) 'down to the minimum'
    Assert-Equal (Invoke-Options 'OddNumber' @([double]6.4, [double]1, [double]12, $false)) ([double]7) 'a slider between two steps'
    Assert-True (Invoke-Options 'IsEven' @([double]8)) '8 not even'
    Assert-True (-not (Invoke-Options 'IsEven' @([double]7))) '7 even'
}

Test 'Options: a tile takes its own Size or the TileSize of All tiles, as the launcher' {
    $asm = $optionsApp.Assembly
    $core = $asm.GetType('RaintileOptions.Core')
    $section = $asm.GetType('RaintileOptions.IniSection')
    function New-Section([hashtable]$Keys) {
        $s = [Activator]::CreateInstance($section)
        foreach ($k in $Keys.Keys) { $s.Keys.Add([System.Collections.Generic.KeyValuePair[string, string]]::new($k, $Keys[$k])) }
        return $s
    }
    $span = { param($c, $t) ($core.GetMethod('GetSpan').Invoke($null, [object[]]@($c, $t))) -join 'x' }
    $cat = New-Section @{ TileSize = '3x1' }
    Assert-Equal (& $span $cat (New-Section @{})) '3x1' 'tile without a size'
    Assert-Equal (& $span $cat (New-Section @{ Size = '1x2' })) '1x2' 'tile with its own'
    Assert-Equal (& $span $cat $null) '3x1' 'All tiles'
    Assert-Equal (& $span (New-Section @{}) (New-Section @{})) '1x1' 'nothing set'
    # a Size= that is not WxH is not replaced by the category's (Raintile.lua: one cell)
    Assert-Equal (& $span $cat (New-Section @{ Size = 'big' })) '1x1' 'a size that is not WxH'
}

Test 'Options: NumericOnly records the characters a box takes' {
    $tb = New-Object System.Windows.Controls.TextBox
    Invoke-Options 'NumericOnly' @($tb, $false, $true) | Out-Null
    Assert-Equal (Invoke-Options 'NumericChars' @($tb)) '0123456789.' 'characters of a size box'
    Assert-Equal (Invoke-Options 'NumericChars' @((New-Object System.Windows.Controls.TextBox))) $null 'characters of a text box'
}

Test 'Options: a choice box selects by value, the first when the value is not there' {
    $choices = [System.Collections.Generic.List[string[]]]::new()
    $choices.Add([string[]]@('V', 'Vertical')); $choices.Add([string[]]@('H', 'Horizontal'))
    $cb = Invoke-Options 'NewChoiceBox' @($choices, 'h', $null)
    Assert-Equal (Invoke-Options 'ChoiceValue' @($cb)) 'H' 'value selected (case-insensitive)'
    Assert-True (-not (Invoke-Options 'SelectChoice' @($cb, 'X'))) 'a value not in the list selected'
    Assert-Equal (Invoke-Options 'ChoiceValue' @($cb)) 'H' 'selection after a value not in the list'
    $cb = Invoke-Options 'NewChoiceBox' @($choices, 'X', $null)
    Assert-Equal (Invoke-Options 'ChoiceValue' @($cb)) 'V' 'first choice for a value not in the list'
}

Test 'Options: the pad keeps being read while what it pressed shows a dialog' {
    # The pad's work opens a modal dialog (a nested loop) on its second call: a
    # DispatcherTimer does not tick while its own Tick is inside one, so the
    # work must still be called while the dialog is open.
    $s = @{ Calls = 0; Inner = 0; Nested = $false }
    $outer = New-Object System.Windows.Threading.DispatcherFrame
    $work = {
        $s.Calls++
        if ($s.Nested) { $s.Inner++; return }
        if ($s.Calls -ne 2) { return }
        $s.Nested = $true
        $inner = New-Object System.Windows.Threading.DispatcherFrame
        $close = New-Object System.Windows.Threading.DispatcherTimer
        $close.Interval = [TimeSpan]::FromMilliseconds(400)
        $close.add_Tick({ $close.Stop(); $inner.Continue = $false }.GetNewClosure())
        $close.Start()
        [System.Windows.Threading.Dispatcher]::PushFrame($inner)
        $s.Nested = $false
        $outer.Continue = $false
    }.GetNewClosure()
    $timer = Invoke-Options 'NewLoopTimer' @([TimeSpan]::FromMilliseconds(16), [System.Windows.Threading.DispatcherPriority]::Input, [Action]$work)
    # (in case the work is never called twice)
    $guard = New-Object System.Windows.Threading.DispatcherTimer
    $guard.Interval = [TimeSpan]::FromSeconds(5)
    $guard.add_Tick({ $guard.Stop(); $outer.Continue = $false }.GetNewClosure())
    $guard.Start()
    $timer.Start()
    [System.Windows.Threading.Dispatcher]::PushFrame($outer)
    $timer.Stop(); $guard.Stop()
    Assert-True ($s.Calls -ge 2) 'the work was not called'
    Assert-True ($s.Inner -gt 0) 'the work stopped while the dialog was open'
}

# Profiles (General > Profiles): their files and what loading one changes
$optionsTypes = $optionsApp.Assembly
function New-StringMap([hashtable]$Values = @{}) {
    $d = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $Values.Keys) { $d[$k] = $Values[$k] }
    return ,$d
}
function New-ProfileData {
    return [Activator]::CreateInstance($optionsTypes.GetType('RaintileOptions.ProfileData'))
}

Test 'Options: a profile name is cleaned and kept inside its folder' {
    Assert-Equal (Invoke-Options 'CleanProfileName' @(' Couch: night ')) 'Couch night' 'name with a colon'
    foreach ($bad in 'CON', 'nul.txt', 'Com1', '...', '', ' ') { Assert-Equal (Invoke-Options 'CleanProfileName' @($bad)) '' "name '$bad'" }
    Assert-Equal (Invoke-Options 'CleanProfileName' @('a' * 50)).Length 40 'length of a long name'
    $d = New-TestFolder
    Assert-Equal (Invoke-Options 'GetProfilePath' @($d, '..\..\x')) (Join-Path $d 'x.ini') 'path of a name going up'
    Assert-Equal (Invoke-Options 'GetProfilePath' @($d, 'CON')) $null 'path of a name Windows keeps'
}

Test 'Options: a profile is written and read back whole' {
    $d = New-TestFolder
    $path = Join-Path $d 'Profiles\Desk.ini'
    $p = New-ProfileData
    $p.Settings['AccentColor'] = '0,210,180,255'
    $p.Settings['OpenHotKey'] = ''
    $p.Settings['DateFormat'] = '%A = %#d'
    $p.Settings['ClockFormat'] = "a`r`nb"
    $p.Categories['Games'] = New-StringMap @{ NX = '5'; TileColor = '' }
    $p.Widgets['BigClock'] = New-StringMap @{ Format = '%H' }
    Invoke-Options 'WriteProfile' @($path, $p) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($path)
    Assert-True (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) 'BOM written'
    Assert-Equal @(Get-ChildItem -LiteralPath (Split-Path $path) -Filter '*.tmp').Count 0 'files .tmp left'
    $r = Invoke-Options 'ReadProfile' @($path)
    Assert-Equal $r.Settings['AccentColor'] '0,210,180,255' 'a colour'
    Assert-True ($r.Settings.ContainsKey('OpenHotKey')) 'an empty value lost'
    Assert-Equal $r.Settings['OpenHotKey'] '' 'an empty value'
    Assert-Equal $r.Settings['DateFormat'] '%A = %#d' 'a value with ='
    Assert-Equal $r.Settings['ClockFormat'] 'a b' 'a value on two lines'
    Assert-Equal $r.Categories['games']['NX'] '5' 'the look of a category'
    Assert-True ($r.Categories['Games'].ContainsKey('TileColor')) 'an empty look key lost'
    Assert-Equal $r.Widgets['BigClock']['Format'] '%H' 'a widget setting'
}

Test 'Options: a damaged profile gives what it can, a missing one nothing' {
    $d = New-TestFolder
    $path = Join-Path $d 'Bad.ini'
    $text = "Loose=1`r`njunk`r`n[Settings]`r`nNX=6`r`nbad key=1`r`n=x`r`n[Other]`r`nNY=9`r`n[Widget ..\x]`r`nA=1`r`n[Category My Games]`r`nNX=3`r`n"
    [IO.File]::WriteAllText($path, $text)
    $r = Invoke-Options 'ReadProfile' @($path)
    Assert-Equal $r.Settings.Count 1 'settings read'
    Assert-Equal $r.Settings['NX'] '6' 'the valid setting'
    Assert-Equal $r.Widgets.Count 0 'widgets with an id that is not one'
    Assert-Equal $r.Categories['My Games']['NX'] '3' 'a category with a space'
    Assert-Equal (Invoke-Options 'ReadProfile' @((Join-Path $d 'None.ini'))) $null 'a missing profile'
}

Test 'Options: the profiles of a folder and the one in use' {
    $d = New-TestFolder
    Assert-Equal @(Invoke-Options 'GetProfileNames' @((Join-Path $d 'Profiles'))).Count 0 'profiles of a missing folder'
    foreach ($f in 'a.ini', 'B.ini', 'Current.txt', 'x.tmp', 'c.inix') { [IO.File]::WriteAllText((Join-Path $d $f), '') }
    Assert-Equal (@(Invoke-Options 'GetProfileNames' @($d)) -join ',') 'a,B' 'profiles'
    Invoke-Options 'WriteCurrentProfile' @($d, 'b') | Out-Null
    Assert-Equal (Invoke-Options 'ReadCurrentProfile' @($d)) 'B' 'the one in use, as its file is spelt'
    Invoke-Options 'WriteCurrentProfile' @($d, '') | Out-Null
    Assert-Equal (Invoke-Options 'ReadCurrentProfile' @($d)) '' 'the default settings in use'
    Invoke-Options 'WriteCurrentProfile' @($d, 'gone') | Out-Null
    Assert-Equal (Invoke-Options 'ReadCurrentProfile' @($d)) $null 'a profile in use that is not there'
    Invoke-Options 'WriteCurrentProfile' @($d, $null) | Out-Null
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $d 'Current.txt'))) 'Current.txt left for no profile'
    Assert-Equal (Invoke-Options 'ReadCurrentProfile' @($d)) $null 'no profile in use'
}

Test 'Options: a profile is renamed, and the one in use with it' {
    $d = New-TestFolder
    foreach ($f in 'Desk.ini', 'Couch.ini') { [IO.File]::WriteAllText((Join-Path $d $f), "[Settings]`r`nNX=5`r`n") }
    Assert-Equal (Invoke-Options 'TestProfileName' @($d, 'couch', 'Desk')) "The profile 'couch' already exists." "another profile's name"
    Assert-Equal (Invoke-Options 'TestProfileName' @($d, 'default SETTINGS', $null)) "The profile 'default SETTINGS' already exists." 'the default settings'
    Assert-True ($null -ne (Invoke-Options 'TestProfileName' @($d, 'CON', $null))) 'a name Windows keeps taken'
    Assert-Equal (Invoke-Options 'TestProfileName' @($d, 'desk', 'Desk')) $null 'the case of its own name'
    Assert-Equal (Invoke-Options 'TestProfileName' @($d, 'Work: late', 'Desk')) $null 'a new name'
    Invoke-Options 'WriteCurrentProfile' @($d, 'Desk') | Out-Null
    Invoke-Options 'RenameProfile' @($d, 'Desk', 'Work: late') | Out-Null
    Assert-Equal (@(Invoke-Options 'GetProfileNames' @($d)) -join ',') 'Couch,Work late' 'profiles after the rename'
    Assert-Equal (Invoke-Options 'ReadCurrentProfile' @($d)) 'Work late' 'the one in use after its rename'
    Assert-Equal ((Invoke-Options 'ReadProfile' @((Join-Path $d 'Work late.ini'))).Settings['NX']) '5' 'the settings of the renamed profile'
    Invoke-Options 'RenameProfile' @($d, 'Couch', 'couch') | Out-Null
    Assert-Equal (@(Invoke-Options 'GetProfileNames' @($d)) -join ',') 'couch,Work late' 'only the case changed'
    Assert-Equal (Invoke-Options 'ReadCurrentProfile' @($d)) 'Work late' 'the one in use after renaming another'
}

Test 'Options: a profile holds the settings, not the excluded ones nor the secrets' {
    foreach ($k in 'SteamGridDBKey', 'steamgriddbkey', 'ImportStores', 'ImportFolders', 'ScanOnStart', 'ImportCategory', 'AppsCategory',
        'CheckUpdates', 'UpdateChannel', 'DebugLog', 'SensorPort', 'TrackPlaytime', 'NoSuchKey', '') {
        Assert-True (-not (Invoke-Options 'TestProfileKey' @($k))) "$k held"
    }
    foreach ($k in 'ScreenX', 'LauncherMode', 'OpenHotKey', 'NavUp2', 'GamepadToggle', 'FrameRate', 'FadeDuration', 'AccentColor', 'DashInterval') {
        Assert-True (Invoke-Options 'TestProfileKey' @($k)) "$k not held"
    }
}

Test 'Options: loading a profile changes only what it names' {
    $values = New-StringMap @{ AccentColor = '1'; NX = '4'; SteamGridDBKey = 'dpapi:x' }
    $wanted = New-StringMap @{ AccentColor = '2'; NX = '4'; SteamGridDBKey = ''; NoSuchKey = 'z' }
    Assert-Equal (@(Invoke-Options 'MergeProfileSettings' @($values, $wanted)) -join ',') 'AccentColor' 'settings changed'
    Assert-Equal $values['AccentColor'] '2' 'a setting of the profile'
    Assert-Equal $values['SteamGridDBKey'] 'dpapi:x' 'the secret'
    Assert-True (-not $values.ContainsKey('NoSuchKey')) 'a key that is not a setting added'

    $cat = [Activator]::CreateInstance($optionsTypes.GetType('RaintileOptions.IniSection'))
    $cat.Name = 'Category'
    foreach ($kv in @(@('Name', 'Games'), @('NX', '6'), @('TileColor', '1,2,3'))) {
        $cat.Keys.Add((New-Object 'System.Collections.Generic.KeyValuePair[string,string]' $kv[0], $kv[1]))
    }
    $look = New-StringMap @{ NX = ''; IconSize = '80'; TileColor = '1,2,3'; Name = 'Other' }
    Assert-Equal ((@(Invoke-Options 'MergeCategoryLook' @($cat, $look)) | Sort-Object) -join ',') 'IconSize,NX' 'look keys changed'
    $keys = @{}
    foreach ($kv in $cat.Keys) { $keys[$kv.Key] = $kv.Value }
    Assert-True (-not $keys.ContainsKey('NX')) 'an empty look key kept in the file'
    Assert-Equal $keys['IconSize'] '80' 'a look key of the profile'
    Assert-Equal $keys['Name'] 'Games' 'the name of the category'

    $widget = New-StringMap @{ Format = '%I'; Key = 'dpapi:y' }
    $defaults = New-StringMap @{ Format = '%H'; Size = '10' }
    $wp = New-StringMap @{ Format = '%H'; Size = '12'; Key = ''; Other = '1' }
    Assert-Equal ((@(Invoke-Options 'MergeWidgetValues' @($widget, $defaults, $wp)) | Sort-Object) -join ',') 'Format,Size' 'widget settings changed'
    Assert-True (-not $widget.ContainsKey('Format')) 'a value equal to the default kept in settings.inc'
    Assert-Equal $widget['Size'] '12' 'a widget setting of the profile'
    Assert-Equal $widget['Key'] 'dpapi:y' 'the secret of a widget'
    Assert-True (-not $widget.ContainsKey('Other')) 'an option the widget does not declare added'
}
