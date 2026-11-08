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
