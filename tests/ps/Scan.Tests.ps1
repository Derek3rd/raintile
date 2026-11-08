# Scan.ps1: tile names become file names (images, thumbnails) and INI
# section names, so they are cleaned (see "Security" in CLAUDE.md).

Import-ScriptFunction (Join-Path $Root '@Resources\Scripts\Scan.ps1') 'Get-TileName'

Test 'Get-TileName: names stay names' {
    Assert-Equal (Get-TileName 'Battle.net') 'Battle.net' 'a dot inside the name'
    Assert-Equal (Get-TileName 'Half-Life 2') 'Half-Life 2' 'a plain name'
    Assert-Equal (Get-TileName 'Portal: Revolution') 'Portal Revolution' 'a colon'
    Assert-Equal (Get-TileName "Game$([char]0x2122) Name$([char]0x00AE)") 'Game Name' 'trademark signs'
    Assert-Equal (Get-TileName '[Steam] Game') 'Steam Game' 'brackets (INI sections)'
    Assert-Equal (Get-TileName '; Game') 'Game' 'a leading ; (INI comment)'
    Assert-Equal (Get-TileName "A`tB`r`nC") 'A B C' 'control characters'
}

Test 'Get-TileName: a name never leaves its folder' {
    # (a folder of this machine: the test also runs outside Windows, in the checks)
    $base = Join-Path ([IO.Path]::GetTempPath()) 'Data'
    $base = Join-Path $base 'Images'
    $sep = [IO.Path]::DirectorySeparatorChar
    foreach ($name in '..', '...', '..\..\Windows\evil', '../../evil', 'a\..\..\b', ' . ', 'C:\evil', '\\server\share\x', 'a/b', '.hidden', 'name.') {
        $clean = Get-TileName $name
        Assert-True ($clean -notmatch '[\\/:*?"<>|]') "reserved characters left in <$clean> (from <$name>)"
        Assert-True (-not $clean.StartsWith('.') -and -not $clean.EndsWith('.')) "dot at an end of <$clean> (from <$name>)"
        if ($clean) {
            $full = [IO.Path]::GetFullPath((Join-Path $base "$clean.png"))
            Assert-True $full.StartsWith($base + $sep) "<$name> leads to $full"
        }
    }
}

$IMPORT_KINDS = @('game', 'app')
Import-ScriptFunction (Join-Path $Root '@Resources\Scripts\Scan.ps1') 'Split-FolderEntry'
Import-ScriptFunction (Join-Path $Root '@Resources\Scripts\Scan.ps1') 'Update-FirstFound'

Test 'Split-FolderEntry: an alias, or the folder name' {
    $e = Split-FolderEntry 'Emulators=X:\Emulators'
    Assert-Equal $e.Alias 'Emulators' 'alias'
    Assert-Equal $e.Path 'X:\Emulators' 'path with an alias'
    $e = Split-FolderEntry ' My games = "D:\Games\Portable" '
    Assert-Equal $e.Alias 'My games' 'alias with a space'
    Assert-Equal $e.Path 'D:\Games\Portable' 'quoted path'
    $e = Split-FolderEntry 'D:\Games\Portable\'
    Assert-Equal $e.Alias 'Portable' 'no alias: the folder name'
    Assert-Equal $e.Path 'D:\Games\Portable\' 'path without alias'
    # an = in the path is not an alias (the part before it has a \ or :)
    $e = Split-FolderEntry 'D:\a=b\Games'
    Assert-Equal $e.Path 'D:\a=b\Games' 'an = inside a path'
    # its kind and category
    $e = Split-FolderEntry 'Emulators=E:\Emu>App>Retro games'
    Assert-Equal $e.Path 'E:\Emu' 'path before the kind'
    Assert-Equal $e.Kind 'app' 'kind'
    Assert-Equal $e.Category 'Retro games' 'category'
    $e = Split-FolderEntry 'E:\Emu>Game'
    Assert-Equal $e.Kind 'game' 'kind without a category'
    Assert-Equal $e.Category '' 'no category'
    Assert-Equal (Split-FolderEntry 'E:\Emu').Kind '' 'no kind: the default one'
}

Test 'Update-FirstFound: the first date stays, gone items leave' {
    $dir = New-TestFolder
    $file = Join-Path $dir 'FirstFound.txt'
    $a = [pscustomobject]@{ Id = 'Steam:1'; Found = '' }
    $b = [pscustomobject]@{ Id = 'Folders:x'; Found = '' }
    Update-FirstFound @($a, $b) $file '2026-01-01T10:00:00'
    Assert-Equal $a.Found '2026-01-01T10:00:00' 'first date of a'
    $a2 = [pscustomobject]@{ Id = 'Steam:1'; Found = '' }
    $c = [pscustomobject]@{ Id = 'Epic:2'; Found = '' }
    Update-FirstFound @($a2, $c) $file '2026-02-02T10:00:00'
    Assert-Equal $a2.Found '2026-01-01T10:00:00' 'a keeps its first date'
    Assert-Equal $c.Found '2026-02-02T10:00:00' 'c found now'
    $text = [IO.File]::ReadAllText($file)
    Assert-True ($text -notmatch 'Folders:x') 'an item no longer found is still in the file'
    Assert-True (-not (Test-Path -LiteralPath "$file.tmp")) 'the .tmp is left'
}

foreach ($fn in 'Read-GooglePlay', 'Add-Installed', 'Add-Item', 'Get-NameKey', 'Test-CommandMissing') {
    Import-ScriptFunction (Join-Path $Root '@Resources\Scripts\Scan.ps1') $fn
}
$GPG_LINK = '(?i)googleplaygames://launch/?\?(?:[^"\s]*?&)?id=([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)'

Test 'Read-GooglePlay: the shortcuts of its games' {
    $menu = New-TestFolder
    New-Item -ItemType Directory -Path (Join-Path $menu 'Google Play Games') | Out-Null
    [IO.File]::WriteAllText((Join-Path $menu 'Google Play Games\Clash of Clans.url'),
        "[InternetShortcut]`r`nURL=googleplaygames://launch/?id=com.supercell.clashofclans&lid=1&pid=1`r`nIconFile=C:\nothing\icon.ico`r`n")
    # the package after other parameters, and a shortcut of something else
    [IO.File]::WriteAllText((Join-Path $menu 'Other Game.url'), "[InternetShortcut]`r`nURL=googleplaygames://launch/?pid=2&id=com.example.othergame`r`n")
    [IO.File]::WriteAllText((Join-Path $menu 'A website.url'), "[InternetShortcut]`r`nURL=https://example.com/?id=com.not.agame`r`n")
    # the shortcut it makes on the desktop: a .lnk holding the link and the icon
    # as UTF-16 strings, with no program as its target
    $u = [Text.Encoding]::Unicode
    $lnk = [byte[]](0x4C, 0, 0, 0) + $u.GetBytes('googleplaygames://launch/?id=com.example.miner&lid=2&pid=1') + [byte[]](0, 0, 0x26, 0) +
        $u.GetBytes('Idle Miner - Google Play Games') + [byte[]](0, 0) + $u.GetBytes('D:\Play Games\data\image_cache\com.example.miner.appicon.ico') + [byte[]](0, 0)
    [IO.File]::WriteAllBytes((Join-Path $menu 'Idle Miner - Google Play Games.lnk'), $lnk)
    $script:items = New-Object System.Collections.ArrayList
    $script:installed = @{}
    $script:gameNames = @{}
    $StartMenu = $menu
    $out = Read-GooglePlay
    Assert-Equal $out '3 found' 'result'
    $miner = $script:items | Where-Object { $_.Command -eq 'googleplaygames://launch/?id=com.example.miner' }
    Assert-True $miner 'the .lnk of the desktop is not read'
    Assert-Equal $miner.Name 'Idle Miner' 'the name without - Google Play Games'
    $coc = $script:items | Where-Object { $_.Name -eq 'Clash of Clans' }
    Assert-True $coc 'Clash of Clans is not found'
    Assert-Equal $coc.Store 'GooglePlay' 'store'
    Assert-Equal $coc.Kind 'game' 'kind'
    Assert-Equal $coc.Command 'googleplaygames://launch/?id=com.supercell.clashofclans' 'command'
    Assert-Equal $coc.Id 'GooglePlay:com.supercell.clashofclans' 'id'
    Assert-True ($script:items | Where-Object { $_.Command -like '*id=com.example.othergame' }) 'the package after pid= is not found'
    Assert-True (-not ($script:items | Where-Object { $_.Command -like '*com.not.agame*' })) 'a website was taken for a game'
    # a tile of a game no longer there is told missing
    Assert-Equal (Test-CommandMissing 'googleplaygames://launch/?id=com.supercell.clashofclans') 'present' 'an installed game'
    Assert-Equal (Test-CommandMissing 'googleplaygames://launch/?id=com.gone.game') 'missing' 'a game no longer installed'
}
