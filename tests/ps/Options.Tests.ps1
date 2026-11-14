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

Test 'Options: a reset pressed with the pad hides itself, the pad goes to the first control of its row' {
    # a row as NewRow builds it: the label, two fields with their clear buttons,
    # the reset in the action column, which hides itself once used
    $row = [Activator]::CreateInstance($optionsApp.Assembly.GetType('RaintileOptions.CardRow'), @([System.Windows.Media.Brushes]::Gray))
    $grid = New-Object System.Windows.Controls.Grid
    foreach ($w in 300, 400, 40) { $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = New-Object System.Windows.GridLength $w; $grid.ColumnDefinitions.Add($c) }
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = 'Open these options'
    $fields = New-Object System.Windows.Controls.StackPanel
    $fields.Orientation = 'Horizontal'
    [System.Windows.Controls.Grid]::SetColumn($fields, 1)
    $buttons = @{}
    foreach ($name in 'Field1', 'Clear1', 'Field2', 'Clear2') {
        $b = New-Object System.Windows.Controls.Button
        $b.Width = if ($name -like 'Field*') { 132 } else { 28 }
        $b.Height = 28
        [void]$fields.Children.Add($b)
        $buttons[$name] = $b
    }
    $reset = New-Object System.Windows.Controls.Button
    $reset.Width = 28; $reset.Height = 28
    [System.Windows.Controls.Grid]::SetColumn($reset, 2)
    foreach ($e in $label, $fields, $reset) { [void]$grid.Children.Add($e) }
    $row.Child = $grid
    $row.Measure((New-Object System.Windows.Size 740, 60))
    $row.Arrange((New-Object System.Windows.Rect 0, 0, 740, 60))
    $reset.Visibility = 'Hidden'
    $found = Invoke-Options 'PadRowOf' @($reset)
    Assert-True ([object]::ReferenceEquals($found, $row)) 'the row of the reset'
    $list = New-Object 'System.Collections.Generic.List[System.Windows.FrameworkElement]'
    foreach ($name in 'Clear2', 'Field2', 'Clear1', 'Field1') { $list.Add($buttons[$name]) }
    $first = Invoke-Options 'PadFirst' @($list, $row)
    Assert-True ([object]::ReferenceEquals($first, $buttons['Field1'])) 'not the first field of the row'
    Assert-True ($null -eq (Invoke-Options 'PadRowOf' @($grid.Parent.Parent))) 'a row outside a card'
}

Test 'Options: the controllers are read at every frame only with one connected or the ring shown' {
    $idle = Invoke-Options 'PadTickMs' @($false, $false)
    Assert-True ($idle -ge 250) "no controller, no ring: read every $idle ms"
    # a controller plugged in is looked for every 2 s: the slow read must not be slower
    Assert-True ($idle -le 1000) "no controller: read only every $idle ms"
    Assert-Equal (Invoke-Options 'PadTickMs' @($true, $false)) 16 'a controller connected'
    Assert-Equal (Invoke-Options 'PadTickMs' @($false, $true)) 16 'the ring shown, the controller unplugged'
    Assert-Equal (Invoke-Options 'PadTickMs' @($true, $true)) 16 'a controller in use'
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

Test 'Options: a gallery widget needs the Raintile of its minVersion' {
    Assert-True (Invoke-Options 'VersionFits' @('1.4.1', '1.4.1')) 'the same release'
    Assert-True (Invoke-Options 'VersionFits' @('1.5.0', '1.4.1')) 'a newer release'
    Assert-True (-not (Invoke-Options 'VersionFits' @('1.4.0', '1.4.1'))) 'an older release'
    Assert-True (-not (Invoke-Options 'VersionFits' @('1.3.9', '1.10.0'))) 'numbers, not text'
    Assert-True (Invoke-Options 'VersionFits' @('1.4.1.3', '1.4.2')) 'a nightly build: the next release'
    Assert-True (Invoke-Options 'VersionFits' @('1.4.1', '')) 'no minVersion'
    Assert-True (Invoke-Options 'VersionFits' @('0', '1.4.0')) 'an unknown version of Raintile'
}

# --- Images (GetBitmap) -----------------------------------------------------

# A picture of W x H pixels in a file
function New-TestImage([string]$Path, [int]$W, [int]$H) {
    $pixels = New-Object byte[] ($W * $H * 4)
    $bmp = [System.Windows.Media.Imaging.BitmapSource]::Create($W, $H, 96, 96, [System.Windows.Media.PixelFormats]::Bgra32, $null, $pixels, $W * 4)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $file = [IO.File]::Create($Path)
    try { $enc.Save($file) } finally { $file.Dispose() }
}

Test 'Options: an image is decoded once for a file and a width, and again when the file changes' {
    $file = Join-Path (New-TestFolder) 'a.png'
    New-TestImage $file 40 20
    $first = Invoke-Options 'GetBitmap' @($file, 0)
    Assert-Equal $first.PixelWidth 40 'width of the picture'
    Assert-True ([object]::ReferenceEquals($first, (Invoke-Options 'GetBitmap' @($file, 0)))) 'the same file decoded again'
    $small = Invoke-Options 'GetBitmap' @($file, 20)
    Assert-Equal $small.PixelWidth 20 'width asked for'
    Assert-True ([object]::ReferenceEquals($small, (Invoke-Options 'GetBitmap' @($file, 20)))) 'the same width decoded again'
    Assert-True ([object]::ReferenceEquals($first, (Invoke-Options 'GetBitmap' @($file, 0)))) 'the full picture lost to the small one'
    # another picture in its place (an image chosen again in the tile editor)
    New-TestImage $file 60 30
    (Get-Item -LiteralPath $file).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(1)
    $next = Invoke-Options 'GetBitmap' @($file, 0)
    Assert-Equal $next.PixelWidth 60 'the picture written again'
    Assert-Equal (Invoke-Options 'GetBitmap' @($file, 20)).PixelHeight 10 'the small copy of the picture written again'
    Remove-Item -LiteralPath $file
    Assert-True ($null -eq (Invoke-Options 'GetBitmap' @($file, 0))) 'a picture whose file is gone'
    Assert-True ($null -eq (Invoke-Options 'GetBitmap' @('', 0))) 'no path'
}

Test 'Options: the images kept stay under their limit, the last used first' {
    $limit = $optionsApp.GetField('bitmapCacheMax', [System.Reflection.BindingFlags]'NonPublic, Static')
    $was = $limit.GetValue($null)
    $folder = New-TestFolder
    try {
        # room for four pictures of 50 x 50 (10000 bytes of pixels each)
        $limit.SetValue($null, [long]40000)
        $files = 1..6 | ForEach-Object { $f = Join-Path $folder "$_.png"; New-TestImage $f 50 50; $f }
        $shown = $files | ForEach-Object { Invoke-Options 'GetBitmap' @($_, 0) }
        Assert-True ([object]::ReferenceEquals($shown[5], (Invoke-Options 'GetBitmap' @($files[5], 0)))) 'the last picture not kept'
        Assert-True ([object]::ReferenceEquals($shown[2], (Invoke-Options 'GetBitmap' @($files[2], 0)))) 'a picture within the limit not kept'
        Assert-True (-not [object]::ReferenceEquals($shown[0], (Invoke-Options 'GetBitmap' @($files[0], 0)))) 'the oldest picture kept over the limit'
        # (kept now, the last used first: 1, 3, 6, 5.) The one used again stays
        # when another comes in, the one not used since goes
        [void](Invoke-Options 'GetBitmap' @($files[4], 0))
        [void](Invoke-Options 'GetBitmap' @($files[0], 20))
        Assert-True ([object]::ReferenceEquals($shown[4], (Invoke-Options 'GetBitmap' @($files[4], 0)))) 'a picture just used dropped'
        Assert-True (-not [object]::ReferenceEquals($shown[5], (Invoke-Options 'GetBitmap' @($files[5], 0)))) 'the picture not used since kept over the limit'
    } finally { $limit.SetValue($null, $was) }
}

Test 'Options: the size of an image is read from its file, again when the file changes' {
    $file = Join-Path (New-TestFolder) 'a.png'
    New-TestImage $file 40 20
    Assert-Equal ((Invoke-Options 'ImagePixelSize' @($file)) -join 'x') '40x20' 'size of the picture'
    New-TestImage $file 60 30
    (Get-Item -LiteralPath $file).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(1)
    Assert-Equal ((Invoke-Options 'ImagePixelSize' @($file)) -join 'x') '60x30' 'the picture written again'
    [IO.File]::WriteAllText($file, 'not an image')
    (Get-Item -LiteralPath $file).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(2)
    Assert-True ($null -eq (Invoke-Options 'ImagePixelSize' @($file))) 'a file that is not an image'
    Assert-True ($null -eq (Invoke-Options 'ImagePixelSize' @(''))) 'no path'
}

Test 'Options: a background enlarged more than LowResLimit gets the low-resolution note' {
    $note = { param($w, $h, $sw, $sh, $zoom) Invoke-Options 'LowResNote' @([int[]]@($w, $h), [double]$sw, [double]$sh, [double]$zoom, 'on the launch screen') }
    # a Steam hero on a 1440p screen: cut to 16:9, its 620 rows become 1440
    $text = & $note 1920 620 2560 1440 1
    Assert-True ($text -match '2\.3') "enlargement not in the note: $text"
    Assert-True ($text -match '2560.1440\.$') "size to use not in the note: $text"
    Assert-Equal (& $note 1920 1080 2560 1440 1) '' '1920x1080 on 1440p (1.33x) is sharp enough'
    Assert-Equal (& $note 3840 2160 2560 1440 1) '' 'a 4K image on 1440p'
    # the zoom of the tile counts: 1.33 x 1.2 = 1.6
    Assert-True ((& $note 1920 1080 2560 1440 1.2) -ne '') 'zoom of the tile not counted'
    Assert-Equal (Invoke-Options 'LowResNote' @($null, [double]2560, [double]1440, [double]1, 'x')) '' 'no image size'
}

# The games found (Generated\Found.json) added by themselves to the category
# files (AutoAddGames, -Action autoadd without the bang to the skin): the new
# games only, each once, never the apps
Test 'Options: the games found are added by themselves once, the apps never' {
    $d = New-TestFolder
    $res = Join-Path $d 'Res'; $data = Join-Path $d 'Data'
    New-Item -ItemType Directory -Force -Path (Join-Path $res 'Generated'), (Join-Path $data 'Categories') | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $settings = Join-Path $data 'Settings.inc'
    $games = Join-Path $data 'Categories\Games.ini'
    [IO.File]::WriteAllText($settings, "[Variables]`r`nAutoAddGames=1`r`nImportCategory=Games`r`n", $utf8)
    [IO.File]::WriteAllText($games, "[Category]`r`nName=Games`r`n`r`n[Old Game]`r`nCommand=steam://rungameid/1`r`n", $utf8)
    function Write-Found([object[]]$Items) {
        $json = ConvertTo-Json -InputObject @{ Scanned = '2026-11-13T10:00:00'; Items = $Items } -Depth 4
        [IO.File]::WriteAllText((Join-Path $res 'Generated\Found.json'), $json, $utf8)
    }
    Write-Found @(
        @{ Id = 'Steam:1'; Kind = 'game'; Store = 'Steam'; Name = 'Old Game'; Command = 'steam://rungameid/1' },
        @{ Id = 'Epic:x'; Kind = 'game'; Store = 'Epic'; Name = 'New Game'; Command = 'com.epicgames.launcher://apps/x' },
        @{ Id = 'Folders:c:\emu\a.exe'; Kind = 'game'; Store = 'Folders'; Source = 'Emu'; Category = 'Emulators'; Name = 'Emu Game'; Command = '"C:\Emu\a.exe"' },
        @{ Id = 'Apps:calc'; Kind = 'app'; Store = 'Apps'; Name = 'Calculator'; Command = 'calc.exe' })
    $optionsApp.Assembly.GetType('RaintileOptions.Core').GetMethod('Init').Invoke($null, [object[]]@([string]$res, [string]$data, 'Test')) | Out-Null
    $add = { @($optionsApp.GetMethod('AutoAddToFiles').Invoke($null, $null)) -join '|' }

    Assert-Equal (& $add) 'New Game|Emu Game' 'games added'
    $text = [IO.File]::ReadAllText($games)
    Assert-True ($text -match '(?m)^\[New Game\]\r?\nCommand=com\.epicgames\.launcher://apps/x\r?\nSource=Epic:x') "the new game in Games.ini:`n$text"
    Assert-True ([IO.File]::ReadAllText((Join-Path $data 'Categories\Emulators.ini')) -match '\[Emu Game\]') 'the game of a folder not in its own category'
    Assert-True ((Get-ChildItem -LiteralPath (Join-Path $data 'Categories') -Recurse | Select-String -SimpleMatch 'Calculator') -eq $null) 'an app added'
    $handled = @([IO.File]::ReadAllLines((Join-Path $data 'AutoAdded.txt')))
    Assert-Equal ($handled -join '|') 'Epic:x|Folders:c:\emu\a.exe|Steam:1' 'games handled'
    # new until shown in their category: the dots of the gear, the menu, the strip
    $newTiles = Join-Path $res 'Generated\NewTiles.txt'
    Assert-Equal (@([IO.File]::ReadAllLines($newTiles)) -join ',') 'Games.ini|New Game,Emulators.ini|Emu Game' 'new tiles'

    # a tile removed by hand does not come back
    [IO.File]::WriteAllText($games, "[Category]`r`nName=Games`r`n`r`n[Old Game]`r`nCommand=steam://rungameid/1`r`n", $utf8)
    Assert-Equal (& $add) '' 'a removed game added again'
    Assert-True (-not ([IO.File]::ReadAllText($games) -match 'New Game')) 'the removed game is back in Games.ini'
    # the setting turned off and on again in the window: every missing game back
    $optionsApp.GetMethod('ForgetAutoAdded').Invoke($null, $null) | Out-Null
    Assert-Equal (& $add) 'New Game' 'the removed game after the setting was turned on again'

    # a game found later is added; nothing with the setting off
    Write-Found @(@{ Id = 'GOG:7'; Kind = 'game'; Store = 'GOG'; Name = 'Later Game'; Command = '"C:\GOG\later.exe"' })
    [IO.File]::WriteAllText($settings, "[Variables]`r`nAutoAddGames=0`r`nImportCategory=Games`r`n", $utf8)
    Assert-Equal (& $add) '' 'a game added with AutoAddGames=0'
    [IO.File]::WriteAllText($settings, "[Variables]`r`nAutoAddGames=1`r`nImportCategory=Games`r`n", $utf8)
    Assert-Equal (& $add) 'Later Game' 'a game found later'
    Assert-Equal (@([IO.File]::ReadAllLines($newTiles)) -join ',') 'Games.ini|New Game,Emulators.ini|Emu Game,Games.ini|Later Game' 'new tiles after a later game'
}

Test 'Options: the search finds settings by the words people use for them' {
    $schema = $optionsApp.Assembly.GetType('RaintileOptions.Schema')
    $search = { param($q) @($schema.GetMethod('Search').Invoke($null, [object[]]@([string]$q))) }
    $first = { param($q) $h = & $search $q; if ($h.Count -eq 0) { '(nothing)' } elseif ($h[0].Item) { $h[0].Item.Key } elseif ($h[0].Group) { 'card ' + $h[0].Group.Title } else { 'page ' + $h[0].Page.Id } }

    Assert-Equal (& $first 'transparency') 'BgColor' 'transparency (a keyword)'
    Assert-Equal (& $first 'TRANSP') 'BgColor' 'the start of a word, any case'
    Assert-Equal (& $first 'bgcolor') 'BgColor' 'the key'
    Assert-Equal (& $first 'wheel turn') 'WheelStepTime' 'two words'
    Assert-Equal (& $first 'delete game') 'page categories' 'removing a game'
    Assert-Equal (& $first 'steamgriddb') 'SteamGridDBKey' 'the SteamGridDB key'
    Assert-Equal (& $first 'profiles') 'card Profiles' 'a card'
    # a page's name lists the page, not every setting on it
    $anim = & $search 'animations'
    Assert-Equal (& $first 'animations') 'page animations' 'a page'
    Assert-True (-not ($anim | Where-Object { $_.Item -and $_.Page.Id -eq 'animations' })) 'the settings of Animations found by the page name'
    # every colour is found as one
    Assert-True ((& $search 'colour' | Where-Object { $_.Item -and $_.Item.Key -eq 'ScrollThumbColor' }).Count -eq 1) 'a colour whose label does not say it'
    Assert-Equal (& $search '').Count 0 'empty query'
    Assert-Equal (& $search 'zzqx').Count 0 'nothing to find'
    Assert-True ((& $search 'e').Count -le $schema.GetField('SearchMax').GetValue($null)) 'more results than the most shown'
    # where it is: the page (with its menu entry) and the card
    $h = (& $search 'recent tiles')[0]
    Assert-Equal $h.Path 'Top row > Quick categories > Recent' 'the place of Recent > Tiles'
}
