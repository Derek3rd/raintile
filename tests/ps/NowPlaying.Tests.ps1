# widgets/NowPlaying/NowPlaying.ps1: its commands, the names of the players,
# the position between two writes of the player, and the bangs to the
# widget's meters. Windows' media controls themselves are not reached here.

$playingScript = Join-Path $Root 'widgets\NowPlaying\NowPlaying.ps1'
foreach ($fn in 'Get-SafeText', 'Get-AppName', 'ConvertFrom-PlayingCommand', 'Get-SeekTarget', 'Get-LivePosition', 'Format-Time', 'Format-PlayingBang') {
    Import-ScriptFunction $playingScript $fn
}

Test 'now playing: the players by name' {
    Assert-Equal (Get-AppName 'Spotify.exe') 'Spotify' 'a program'
    Assert-Equal (Get-AppName 'Chrome') 'Chrome' 'a browser'
    Assert-Equal (Get-AppName 'Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic') 'ZuneMusic' 'an app of the Store'
    Assert-Equal (Get-AppName 'vlc.exe') 'Vlc' 'lower case'
    Assert-Equal (Get-AppName '') '' 'none'
}

Test 'now playing: commands and seeking' {
    Assert-Equal (ConvertFrom-PlayingCommand 'next').Verb 'next' 'next'
    Assert-Equal (Get-SeekTarget (ConvertFrom-PlayingCommand 'seek 25') 10 200) 50.0 'a quarter'
    Assert-Equal (Get-SeekTarget (ConvertFrom-PlayingCommand 'step 10') 195 200) 200.0 'not past the end'
    Assert-Equal (Get-SeekTarget (ConvertFrom-PlayingCommand 'step -10') 5 200) 0.0 'not before the start'
    Assert-Equal (Get-SeekTarget (ConvertFrom-PlayingCommand 'seek 25') 0 0) -1 'no song'
    foreach ($bad in '', 'like', 'seek', 'step x') {
        Assert-True ($null -eq (ConvertFrom-PlayingCommand $bad)) "not a command: '$bad'"
    }
}

Test 'now playing: the position goes on between the writes of the player' {
    Assert-Equal (Get-LivePosition 60 200 2.5 $true) 62.5 'playing'
    Assert-Equal (Get-LivePosition 60 200 2.5 $false) 60.0 'paused'
    Assert-Equal (Get-LivePosition 199 200 5 $true) 200.0 'not past the end'
}

Test 'now playing: the song in the meters' {
    $colors = @{ Text = 'T'; Dim = 'D'; Accent = 'A' }
    $song = @{ Title = 'Song'; Artist = 'Someone'; App = 'Chrome'; Playing = $false; Position = 30; Duration = 120; Shuffle = $false; Repeat = 'ALL'; Cover = ''; Note = '' }
    $bang = Format-PlayingBang $song 'CW5_' 'CW5' 'Raintile' $colors
    Assert-True ($bang.Contains('[!SetOption "CW5_Cover" "ToolTipText" "Song - Someone (Chrome)" "Raintile"]')) 'the song and the player'
    Assert-True ($bang.Contains('[!SetOption "CW5_ShuffleGlyph" "FontColor" "T" "Raintile"]')) 'shuffle off'
    Assert-True ($bang.Contains('[!SetOption "CW5_RepeatGlyph" "FontColor" "A" "Raintile"]')) 'repeat on'
    Assert-True ($bang.Contains('[!SetOption "CW5_Shuffle" "Hidden" "0" "Raintile"]')) 'without what the player takes: every control'
    # a player without shuffle, repeat or next (YouTube in a browser)
    $song.Can = @{ Play = $true; Previous = $true; Next = $false; Shuffle = $false; Repeat = $false; Seek = $true }
    $tube = Format-PlayingBang $song 'CW5_' 'CW5' 'Raintile' $colors
    Assert-True ($tube.Contains('[!SetOption "CW5_Shuffle" "Hidden" "1" "Raintile"]')) 'shuffle not a part'
    Assert-True ($tube.Contains('[!SetOption "CW5_RepeatGlyph" "FontColor" "D" "Raintile"]')) 'repeat dimmed, though on'
    Assert-True ($tube.Contains('[!SetOption "CW5_NextGlyph" "FontColor" "D" "Raintile"]')) 'next dimmed'
    Assert-True ($tube.Contains('[!SetOption "CW5_Play" "Hidden" "0" "Raintile"]')) 'play stays'
    Assert-True ($bang.Contains('[!SetOption "CW5_Progress" "Formula" "25" "Raintile"]')) 'the progress'
    Assert-True ($bang.Contains('[!SetOption "CW5_PlayGlyph" "Text" "' + [char]0xE768 + '" "Raintile"]')) 'play while paused'
    $live = Format-PlayingBang @{ Title = 'Live'; Artist = ''; App = 'Chrome'; Playing = $true; Position = 0; Duration = 0; Shuffle = $false; Repeat = 'NONE'; Cover = ''; Note = '' } 'CW5_' 'CW5' 'Raintile' $colors
    Assert-True ($live.Contains('[!SetOption "CW5_Dur" "Text" "" "Raintile"]')) 'no times without a duration (a live stream)'
}
