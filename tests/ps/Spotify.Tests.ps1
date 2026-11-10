# widgets/Spotify/Spotify.ps1: its commands, the messages it sends to
# Spotify, the bangs to the widget's meters, and its WebSocket server
# (compiled from the script and talked to with .NET's own client).

$spotifyScript = Join-Path $Root 'widgets\Spotify\Spotify.ps1'
foreach ($fn in 'Get-SafeText', 'ConvertTo-Seconds', 'Get-CoverId', 'ConvertFrom-SpotifyCommand', 'Get-SpotifyMessage', 'Format-SpotifyBang', 'Format-Time') {
    Import-ScriptFunction $spotifyScript $fn
}

Test 'spotify: times and covers' {
    Assert-Equal (ConvertTo-Seconds '3:13') 193 'm:ss'
    Assert-Equal (ConvertTo-Seconds '1:02:03') 3723 'h:mm:ss'
    Assert-Equal (ConvertTo-Seconds 'abc') 0 'not a time'
    Assert-Equal (Format-Time 193) '3:13' 'back'
    Assert-Equal (Format-Time 3723) '1:02:03' 'an hour'
    Assert-Equal (Get-CoverId 'https://i.scdn.co/image/ab67616d0000b273abcdef') 'ab67616d0000b273abcdef' 'Spotify image'
    foreach ($bad in 'http://i.scdn.co/image/ab67616d0000b273', 'https://evil.example/image/ab67616d0000b273', 'https://i.scdn.co/image/../x', '') {
        Assert-Equal (Get-CoverId $bad) '' "not a cover: '$bad'"
    }
}

Test 'spotify: commands and what Spotify gets' {
    Assert-Equal (Get-SpotifyMessage (ConvertFrom-SpotifyCommand 'playpause') 0 0) 'TOGGLE_PLAYING' 'play / pause'
    Assert-Equal (Get-SpotifyMessage (ConvertFrom-SpotifyCommand 'like') 0 0) 'TOGGLE_THUMBS_UP' 'heart'
    Assert-Equal (Get-SpotifyMessage (ConvertFrom-SpotifyCommand 'seek 50') 10 200) 'SET_POSITION 100:0.5' 'half way'
    Assert-Equal (Get-SpotifyMessage (ConvertFrom-SpotifyCommand 'step 10') 90 200) 'SET_POSITION 100:0.5' '10 s on'
    Assert-Equal (Get-SpotifyMessage (ConvertFrom-SpotifyCommand 'step -10') 5 200) 'SET_POSITION 0:0' 'not before the start'
    Assert-True ($null -eq (Get-SpotifyMessage (ConvertFrom-SpotifyCommand 'seek 50') 0 0)) 'no seek without a song'
    foreach ($bad in '', 'seek', 'seek x', 'format c:') {
        Assert-True ($null -eq (ConvertFrom-SpotifyCommand $bad)) "not a command: '$bad'"
    }
}

Test 'spotify: the song in the meters' {
    $song = @{ Title = 'A "song" [live]'; Artist = 'Someone'; State = 'PLAYING'; Position = 50; Duration = 200; Liked = $true; Cover = ''; Note = '' }
    $bang = Format-SpotifyBang $song 'CW3_' 'CW3' 'Raintile' @{ Text = 'T'; Accent = 'A' }
    Assert-True ($bang.Contains('[!SetOption "CW3_Title" "Text" "A ''song'' (live)" "Raintile"]')) 'the title, safe in a bang'
    Assert-True ($bang.Contains('[!SetOption "CW3_Progress" "Formula" "25" "Raintile"]')) 'the progress'
    Assert-True ($bang.Contains('[!SetOption "CW3_LikeGlyph" "FontColor" "A" "Raintile"]')) 'a liked song in the accent colour'
    Assert-True ($bang.Contains('[!SetOption "CW3_PlayGlyph" "Text" "' + [char]0xE769 + '" "Raintile"]')) 'pause while playing'
    Assert-True ($bang.Contains('[!SetOption "CW3_NoCover" "Hidden" "0" "Raintile"]')) 'the note without a cover'
    Assert-True ($bang.Contains('[!SetOption "CW3_Status" "Hidden" "1" "Raintile"]')) 'no status with a song'
}

Test 'spotify: the WebSocket server' {
    if (-not ('RaintileSpotify.Link' -as [type])) {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($spotifyScript, [ref]$tokens, [ref]$errors)
        $assign = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$source' }, $true)
        if (-not $assign) { throw "no `$source in $spotifyScript" }
        Add-Type -TypeDefinition $assign.Right.Expression.Value -Language CSharp
    }
    $port = 18974 + (Get-Random -Maximum 500)
    $link = New-Object RaintileSpotify.Link $port
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    try {
        $ws.ConnectAsync([Uri]"ws://127.0.0.1:$port", [Threading.CancellationToken]::None).Wait(5000) | Out-Null
        Assert-Equal ([string]$ws.State) 'Open' 'the handshake'
        # the server says its protocol first
        $buf = New-Object byte[] 256
        $seg = New-Object 'System.ArraySegment[byte]' (, $buf)
        $r = $ws.ReceiveAsync($seg, [Threading.CancellationToken]::None)
        [void]$r.Wait(5000)
        Assert-Equal ([Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count)) 'ADAPTER_VERSION 1.0.0;WNPRLIB_REVISION 1' 'its first message'
        foreach ($m in ('TITLE Caf' + [char]0xE9), 'POSITION 1:02') {
            $bytes = [Text.Encoding]::UTF8.GetBytes($m)
            $ws.SendAsync((New-Object 'System.ArraySegment[byte]' (, $bytes)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait(5000) | Out-Null
        }
        for ($i = 0; $i -lt 50 -and -not $link.Snapshot().ContainsKey('POSITION'); $i++) { Start-Sleep -Milliseconds 20 }
        $d = $link.Snapshot()
        Assert-Equal $d['TITLE'] ('Caf' + [char]0xE9) 'a title, UTF-8'
        Assert-Equal $d['POSITION'] '1:02' 'the position'
        Assert-True $link.Connected 'connected'
        # a command reaches the client
        $link.Send('NEXT')
        $r = $ws.ReceiveAsync($seg, [Threading.CancellationToken]::None)
        [void]$r.Wait(5000)
        Assert-Equal ([Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count)) 'NEXT' 'a command'
    } finally {
        $ws.Dispose()
        $link.Stop()
    }
}
