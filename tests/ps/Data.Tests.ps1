# Data.ps1: prepares the user data folder. It must be idempotent and never
# lose a value of the user (see CLAUDE.md).

$dataScript = Join-Path $Root '@Resources\Scripts\Data.ps1'

# A skin folder with the default files, and an empty data folder
function New-Install {
    $base = New-TestFolder
    $res = Join-Path $base 'Skins\Raintile\@Resources'
    New-Item -ItemType Directory -Path $res | Out-Null
    foreach ($item in 'Settings.inc', 'State.inc', 'Categories', 'Images') {
        Copy-Item -LiteralPath (Join-Path $Root "@Resources\$item") -Destination $res -Recurse
    }
    return @{ Base = $base; Skins = (Join-Path $base 'Skins'); Resources = $res; Data = (Join-Path $base 'Settings\Raintile') }
}

function Invoke-Data($i, [switch]$WithSkins) {
    if ($WithSkins) { $out = & $dataScript -Resources $i.Resources -Data $i.Data -Skins $i.Skins -Config 'Raintile' }
    else { $out = & $dataScript -Resources $i.Resources -Data $i.Data }
    $out = @($out)
    Assert-Equal $out[-1] 'RESULT:OK' "last line of Data.ps1 ($($out -join ' / '))"
    return $out
}

function Get-Setting([string]$path, [string]$key) {
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        if ($line -match ('^' + [regex]::Escape($key) + '=(.*)$')) { return $Matches[1] }
    }
    return $null
}

function Set-Setting([string]$path, [string]$key, [string]$value) {
    $lines = [IO.File]::ReadAllLines($path)
    $found = $false
    for ($k = 0; $k -lt $lines.Count; $k++) {
        if ($lines[$k] -match ('^' + [regex]::Escape($key) + '=')) { $lines[$k] = "$key=$value"; $found = $true }
    }
    if (-not $found) { throw "no setting $key" }
    [IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"))
}

Test 'Data.ps1: first run fills the data folder' {
    $i = New-Install
    Invoke-Data $i | Out-Null
    foreach ($item in 'Settings.inc', 'State.inc', 'Categories', 'Images', 'Dashboard.added') {
        Assert-True (Test-Path -LiteralPath (Join-Path $i.Data $item)) "$item in the data folder"
    }
    $games = Join-Path $i.Data 'Categories\Games.ini'
    Assert-True (Test-Path -LiteralPath $games) 'the default categories'
    # the settings are the defaults, written without BOM
    $bytes = [IO.File]::ReadAllBytes((Join-Path $i.Data 'Settings.inc'))
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF)) 'Settings.inc without BOM'
    $defaults = [IO.File]::ReadAllLines((Join-Path $i.Resources 'Settings.inc'))
    $written = [IO.File]::ReadAllLines((Join-Path $i.Data 'Settings.inc'))
    Assert-Equal $written.Count $defaults.Count 'lines of Settings.inc'
}

Test 'Data.ps1: a second run changes nothing' {
    $i = New-Install
    Invoke-Data $i | Out-Null
    $settings = Join-Path $i.Data 'Settings.inc'
    $before = [IO.File]::ReadAllBytes($settings)
    $stamp = (Get-Item -LiteralPath $settings).LastWriteTimeUtc
    $out = Invoke-Data $i
    Assert-True (-not ($out -match '^Settings updated')) 'Settings.inc written again'
    $after = [IO.File]::ReadAllBytes($settings)
    Assert-Equal ([Convert]::ToBase64String($after)) ([Convert]::ToBase64String($before)) 'Settings.inc'
    Assert-Equal (Get-Item -LiteralPath $settings).LastWriteTimeUtc $stamp 'time of Settings.inc'
}

Test 'Data.ps1: your values survive, new settings come, removed ones go' {
    $i = New-Install
    Invoke-Data $i | Out-Null
    $settings = Join-Path $i.Data 'Settings.inc'
    Set-Setting $settings 'NX' '7'
    Set-Setting $settings 'DockSize' '25%'
    Set-Setting $settings 'BgColor' '#10141CC8'
    Set-Setting $settings 'CloseAction' '[!CommandMeasure MeasureScript "Hide()"][!Log "a=b"]'
    # an older version: one setting missing, one that no longer exists
    $lines = [Collections.Generic.List[string]]([IO.File]::ReadAllLines($settings))
    $gone = $lines.FindIndex([Predicate[string]]{ param($l) $l -match '^ShowClock=' })
    $lines.RemoveAt($gone)
    $lines.Add('OldSetting=1')
    [IO.File]::WriteAllText($settings, (($lines -join "`r`n") + "`r`n"))

    $out = Invoke-Data $i
    Assert-True ($out -match '^Settings updated') 'Settings.inc rewritten'
    Assert-Equal (Get-Setting $settings 'NX') '7' 'NX'
    Assert-Equal (Get-Setting $settings 'DockSize') '25%' 'DockSize'
    Assert-Equal (Get-Setting $settings 'BgColor') '#10141CC8' 'BgColor'
    Assert-Equal (Get-Setting $settings 'CloseAction') '[!CommandMeasure MeasureScript "Hide()"][!Log "a=b"]' 'a value with = in it'
    Assert-Equal (Get-Setting $settings 'ShowClock') (Get-Setting (Join-Path $i.Resources 'Settings.inc') 'ShowClock') 'the new setting, with its default'
    Assert-Equal (Get-Setting $settings 'OldSetting') $null 'the removed setting'
}

Test 'Data.ps1: your categories are never overwritten' {
    $i = New-Install
    Invoke-Data $i | Out-Null
    $games = Join-Path $i.Data 'Categories\Games.ini'
    [IO.File]::WriteAllText($games, "[Category]`r`nName=Mine`r`n")
    Invoke-Data $i | Out-Null
    Assert-Equal ([IO.File]::ReadAllText($games)) "[Category]`r`nName=Mine`r`n" 'Games.ini'
}

Test 'Data.ps1: a deleted Dashboard does not come back' {
    $i = New-Install
    Invoke-Data $i | Out-Null
    $dash = Join-Path $i.Data 'Categories\Dashboard.ini'
    Assert-True (Test-Path -LiteralPath $dash) 'Dashboard.ini added the first time'
    Remove-Item -LiteralPath $dash
    Invoke-Data $i | Out-Null
    Assert-True (-not (Test-Path -LiteralPath $dash)) 'Dashboard.ini added again'
}

Test 'Data.ps1: after an update, the data comes from the backup' {
    $i = New-Install
    # what the installer leaves: the previous skin in Skins\@Backup
    $backup = Join-Path $i.Skins '@Backup\Raintile\@Resources'
    New-Item -ItemType Directory -Path (Join-Path $backup 'Categories') | Out-Null
    [IO.File]::WriteAllText((Join-Path $backup 'Categories\Old.ini'), "[Category]`r`nName=Old`r`n")
    Copy-Item -LiteralPath (Join-Path $i.Resources 'Settings.inc') -Destination $backup
    Set-Setting (Join-Path $backup 'Settings.inc') 'NY' '5'
    Invoke-Data $i -WithSkins | Out-Null
    Assert-True (Test-Path -LiteralPath (Join-Path $i.Data 'Categories\Old.ini')) 'categories of the backup'
    Assert-Equal (Get-Setting (Join-Path $i.Data 'Settings.inc') 'NY') '5' 'settings of the backup'
}

Test 'Data.ps1: the kind of your folders moves onto each folder' {
    $i = New-Install
    Invoke-Data $i | Out-Null
    $settings = Join-Path $i.Data 'Settings.inc'
    # an older version: one kind for every folder
    Set-Setting $settings 'ImportFolders' 'D:\Emu|Retro=E:\Old>Game'
    [IO.File]::AppendAllText($settings, "ImportFoldersKind=App`r`n")
    Invoke-Data $i | Out-Null
    Assert-Equal (Get-Setting $settings 'ImportFolders') 'D:\Emu>App|Retro=E:\Old>Game' 'the old kind on the folders without one'
    Assert-Equal (Get-Setting $settings 'ImportFoldersKind') $null 'the old setting'
    # and again: nothing changes
    $out = Invoke-Data $i
    Assert-True (-not ($out -match '^Settings updated')) 'a second run rewrote Settings.inc'
}
