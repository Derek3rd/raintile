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
