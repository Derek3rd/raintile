# widgets/AudioControl/AudioControl.ps1: its commands, the bangs it sends to
# the widget's meters, and its C# (Core Audio) compiled without running it.

$audioScript = Join-Path $Root 'widgets\AudioControl\AudioControl.ps1'
foreach ($fn in 'Get-SafeText', 'Get-AudioMode', 'ConvertFrom-AudioCommand', 'Get-SteppedVolume', 'Format-AudioBang', 'Read-CommandFile') {
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
