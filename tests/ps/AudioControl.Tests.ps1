# widgets/AudioControl/AudioControl.ps1: its commands, the bangs it sends to
# the widget's meters, and its C# (Core Audio) compiled without running it.

$audioScript = Join-Path $Root 'widgets\AudioControl\AudioControl.ps1'
foreach ($fn in 'Get-SafeText', 'Get-AudioMode', 'ConvertFrom-AudioCommand', 'Get-SteppedVolume', 'Format-AudioBang', 'Read-CommandFile', 'Resolve-SoftMute', 'Get-UnmuteLevel', 'Read-SavedLevels') {
    Import-ScriptFunction $audioScript $fn
}

Test 'audio: commands of the widget' {
    $c = ConvertFrom-AudioCommand 'set 3 57.5'
    Assert-Equal $c.Verb 'set' 'verb'
    Assert-Equal $c.Row 3 'row'
    Assert-Equal $c.Value 57.5 'value'
    Assert-Equal (ConvertFrom-AudioCommand 'set 1 140').Value 100.0 'a volume over 100'
    Assert-Equal (ConvertFrom-AudioCommand ' pick 2 ').Row 2 'pick'
    Assert-Equal (ConvertFrom-AudioCommand 'quit').Verb 'quit' 'quit'
    Assert-Equal (Get-AudioMode ' mixer ') 'Mixer' 'the tile setting, any case'
    Assert-True ($null -eq (Get-AudioMode '')) 'no tile setting: the default'
    foreach ($bad in '', 'set 2', 'pick 0', 'pick x', 'mode mixer', 'format c:', 'up') {
        Assert-True ($null -eq (ConvertFrom-AudioCommand $bad)) "not a command: '$bad'"
    }
}

Test 'audio: volume steps land on the step' {
    Assert-Equal (Get-SteppedVolume 52 5 1) 55 '52 up'
    Assert-Equal (Get-SteppedVolume 55 5 1) 60 '55 up'
    Assert-Equal (Get-SteppedVolume 52 5 -1) 50 '52 down'
    Assert-Equal (Get-SteppedVolume 98 5 1) 100 'not over 100'
    Assert-Equal (Get-SteppedVolume 2 5 -1) 0 'not under 0'
}

Test 'audio: names safe in a bang' {
    Assert-Equal (Get-SafeText 'Speakers "Realtek" [HD] #1') "Speakers 'Realtek' (HD) 1" 'quotes, brackets, #'
    Assert-Equal (Get-SafeText "a`r`nb") 'a  b' 'one line'
}

Test 'audio: the rows sent to the meters' {
    $items = @(
        @{ Name = 'Speakers'; Volume = 40; Mute = $false; Active = $true; Icon = '' },
        @{ Name = 'Headphones'; Volume = 75; Mute = $true; Active = $false; Icon = '' },
        @{ Name = 'Third'; Volume = 10; Mute = $false; Active = $false; Icon = '' })
    $colors = @{ Text = 'T'; Dim = 'D'; Accent = 'A' }
    $bang = Format-AudioBang $items 'Devices' 'CW4_' 'CW4' 'Raintile' 2 $colors
    Assert-True ($bang.Contains('[!SetOption "CW4_Name1" "Text" "Speakers" "Raintile"]')) 'the first name'
    Assert-True ($bang.Contains('[!SetOption "CW4_Name1" "FontColor" "A" "Raintile"]')) 'the default device lit'
    Assert-True ($bang.Contains('[!SetOption "CW4_Pct2" "Text" "Muted" "Raintile"]')) 'a muted device'
    Assert-True ($bang.Contains('[!SetOption "CW4_Vol2" "Formula" "75" "Raintile"]')) 'the volume'
    Assert-True ($bang.Contains('[!SetOption "CW4_Count" "Formula" "2" "Raintile"]')) 'as many rows as the meters'
    Assert-True (-not $bang.Contains('CW4_Name3')) 'no third row'
    Assert-True ($bang.Contains('[!SetOption "CW4_Title" "Text" "Sound devices" "Raintile"]')) 'the title after the mode'
    $mixer = Format-AudioBang @() 'Mixer' 'CW4_' 'CW4' 'Raintile' 8 $colors 'My "mix"' 'Sound not readable'
    Assert-True ($mixer.Contains('[!SetOption "CW4_Title" "Text" "My ' + "'mix'" + '" "Raintile"]')) 'the Title setting'
    Assert-True ($mixer.Contains('[!SetOption "CW4_Empty" "Text" "Sound not readable" "Raintile"]')) 'the note without rows'
    Assert-True ($mixer.Contains('[!SetOption "CW4_IconOn" "Formula" "1" "Raintile"]')) 'icons in the mixer'
    Assert-True ($bang.EndsWith('[!Redraw "Raintile"]')) 'redrawn at the end'
}

Test 'audio: the command file' {
    $dir = New-TestFolder
    $path = Join-Path $dir 'cmd_CW4_Server.ini'
    Assert-Equal (Read-CommandFile $path).Do '' 'no file'
    [IO.File]::WriteAllText($path, "[Other]`r`nDo=x`r`n[Cmd]`r`nOwner=12`r`nDo=set 1 50`r`n")
    $r = Read-CommandFile $path
    Assert-Equal $r.Owner '12' 'owner'
    Assert-Equal $r.Do 'set 1 50' 'command'
}

Test 'audio: programs without a mute of their own' {
    $saved = @{ 'c:\chrome.exe' = 60; 'c:\steam.exe' = 40 }
    $items = @(
        [pscustomobject]@{ Key = 'c:\chrome.exe'; Volume = 0; Mute = $false; CanMute = $false },
        [pscustomobject]@{ Key = 'c:\steam.exe'; Volume = 25; Mute = $false; CanMute = $false },
        [pscustomobject]@{ Key = 'c:\game.exe'; Volume = 0; Mute = $false; CanMute = $false })
    Assert-True (Resolve-SoftMute $items $saved) 'a program back above 0 changes the saved levels'
    Assert-True $items[0].Mute 'muted by the widget: at 0 and saved'
    Assert-True (-not $saved.ContainsKey('c:\steam.exe')) 'raised elsewhere: no longer muted'
    Assert-True (-not $items[2].Mute) 'at 0 without the widget muting it: not muted'
    Assert-True (-not (Resolve-SoftMute $items $saved)) 'nothing changed the second time'
    Assert-Equal (Get-UnmuteLevel $saved 'c:\chrome.exe' 5) 60 'back to the level before'
    Assert-Equal (Get-UnmuteLevel @{ 'x' = 0 } 'x' 5) 5 'never back to 0'
    $dir = New-TestFolder
    $path = Join-Path $dir 'muted.txt'
    [IO.File]::WriteAllText($path, "c:\a b\x.exe|35`r`nbroken`r`n")
    $read = Read-SavedLevels $path
    Assert-Equal $read['c:\a b\x.exe'] 35 'a saved level'
    Assert-Equal $read.Count 1 'a broken line left out'
    Assert-Equal (Read-SavedLevels (Join-Path $dir 'none.txt')).Count 0 'no file'
}

Test 'audio: its C# compiles' {
    if (-not ('RaintileAudio.Audio' -as [type])) {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($audioScript, [ref]$tokens, [ref]$errors)
        $assign = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$source' }, $true)
        if (-not $assign) { throw "no `$source in $audioScript" }
        Add-Type -TypeDefinition $assign.Right.Expression.Value -Language CSharp
    }
    Assert-True ('RaintileAudio.Audio' -as [type]) 'no RaintileAudio.Audio'
}
