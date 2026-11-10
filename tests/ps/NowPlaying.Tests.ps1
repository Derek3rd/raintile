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
    $song = @{ Title = 'Song'; Artist = 'Someone'; App = 'Chrome'; Playing = $false; Position = 30; Duration = 120; Cover = ''; Note = '' }
    $bang = Format-PlayingBang $song 'CW5_' 'CW5' 'Raintile'
    Assert-True ($bang.Contains('[!SetOption "CW5_App" "Text" "Chrome" "Raintile"]')) 'the player'
    Assert-True ($bang.Contains('[!SetOption "CW5_Progress" "Formula" "25" "Raintile"]')) 'the progress'
    Assert-True ($bang.Contains('[!SetOption "CW5_PlayGlyph" "Text" "' + [char]0xE768 + '" "Raintile"]')) 'play while paused'
    $live = Format-PlayingBang @{ Title = 'Live'; Artist = ''; App = 'Chrome'; Playing = $true; Position = 0; Duration = 0; Cover = ''; Note = '' } 'CW5_' 'CW5' 'Raintile'
    Assert-True ($live.Contains('[!SetOption "CW5_Dur" "Text" "" "Raintile"]')) 'no times without a duration (a live stream)'
}
