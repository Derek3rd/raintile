# widgets/ClaudeCode: the sessions of Claude Code as rows (who waits for you
# first), the limits kept by its status line and shown in the meters, and
# StatusLine.ps1 itself, given what Claude Code gives a status line.

$claudeScript = Join-Path $Root 'widgets\ClaudeCode\ClaudeCode.ps1'
$lineScript = Join-Path $Root 'widgets\ClaudeCode\StatusLine.ps1'
foreach ($fn in 'Get-ClaudeFolder', 'Get-FieldText', 'Get-AgeText', 'Get-SessionView', 'Format-SessionList', 'Read-KeyValues', 'Get-LimitView', 'Format-UsageBang', 'Get-StatusLineHelp', 'ConvertFrom-ClaudeCommand') {
    Import-ScriptFunction $claudeScript $fn
}
foreach ($fn in 'Get-LimitValue', 'Format-Limits', 'Test-LimitsChanged', 'Format-StatusLine') {
    Import-ScriptFunction $lineScript $fn
}

Test 'claude code: its folder' {
    Assert-Equal (Get-ClaudeFolder ' D:\Claude\ ' 'E:\cfg' 'C:\Users\x') 'D:\Claude' 'the setting, without its backslash'
    Assert-Equal (Get-ClaudeFolder '' 'E:\cfg' 'C:\Users\x') 'E:\cfg' 'CLAUDE_CONFIG_DIR'
    Assert-Equal (Get-ClaudeFolder '' '' 'C:\Users\x') 'C:\Users\x\.claude' 'the user folder'
}

Test 'claude code: how long ago' {
    Assert-Equal (Get-AgeText 20000) 'now' 'seconds'
    Assert-Equal (Get-AgeText (5 * 60000 + 5000)) '5 min' 'minutes'
    Assert-Equal (Get-AgeText (3 * 3600000)) '3 h' 'hours'
    Assert-Equal (Get-AgeText (2 * 86400000)) '2 d' 'days'
    Assert-Equal (Get-AgeText -5000) 'now' 'a clock a little ahead'
}

Test 'claude code: the sessions, the ones that wait for you first' {
    $now = 1800000000000.0
    $views = @(
        (Get-SessionView @{ name = 'web'; status = 'busy'; statusUpdatedAt = $now - 60000 } $now 'X:\w'),
        (Get-SessionView @{ name = 'api'; status = 'idle'; statusUpdatedAt = $now - 600000 } $now 'X:\w'),
        (Get-SessionView @{ name = 'docs'; status = 'idle'; statusUpdatedAt = $now - 120000 } $now 'X:\w'),
        (Get-SessionView @{ name = 'tool|s'; status = 'waiting'; waitingFor = "dialog`nopen"; statusUpdatedAt = $now - 1000 } $now 'X:\w'),
        (Get-SessionView @{ cwd = 'C:\Code\site'; status = 'busy'; spare = $true } $now 'X:\w'),
        (Get-SessionView @{ cwd = 'C:\Code\site'; startedAt = $now - 7200000 } $now 'X:\w')
    )
    $rows = @(Format-SessionList $views)
    Assert-Equal $rows.Count 5 'a spare process is not a session'
    Assert-Equal $rows[0] 'tool s|Needs you: dialog open, now|X:\w\needs.png|' 'what it asks first, on one line'
    Assert-True ($rows[1].StartsWith('docs|Your turn, 2 min|')) 'then the ones done, the newest first'
    Assert-True ($rows[2].StartsWith('api|Your turn, 10 min|')) 'the older one done'
    Assert-True ($rows[3].StartsWith('web|Working, 1 min|')) 'then the working ones'
    Assert-Equal $rows[4] 'site|Open, 2 h||' 'no status (an older Claude Code): its folder, open'
    # a click: its window to the front, through the command file
    $row = @(Format-SessionList @(Get-SessionView @{ name = 'web'; status = 'idle'; pid = 4242 } $now 'X:\w' 'X:\w\cmd_CW3_Server.ini'))[0]
    Assert-True ($row.EndsWith('|[!WriteKeyValue Cmd Do "focus 4242" "X:\w\cmd_CW3_Server.ini"]')) "the row's command: $row"
    Assert-Equal (ConvertFrom-ClaudeCommand ' focus 4242 ').Pid 4242 'the session asked for'
    Assert-Equal (ConvertFrom-ClaudeCommand 'quit').Verb 'quit' 'quit'
    foreach ($bad in '', 'focus', 'focus -1', 'focus 12 13', 'focus x', 'run calc') {
        Assert-True ($null -eq (ConvertFrom-ClaudeCommand $bad)) "not a command: '$bad'"
    }
}

Test 'claude code: the limits' {
    $utc = [TimeZoneInfo]::Utc
    $now = [long]1800000000   # 2027-01-15 08:00 UTC, a Friday
    $v = Read-KeyValues "FiveHour=42.5`r`nFiveHourResets=$($now + 3600)`r`nWeek=91`r`nWeekResets=$($now + 4 * 86400)`r`n"
    $five = Get-LimitView $v 'FiveHour' $now $utc
    Assert-Equal $five.Pct 42.5 'the use'
    Assert-Equal $five.Text '43%, resets 09:00' 'today: the time (rounded)'
    Assert-Equal (Get-LimitView $v 'Week' $now $utc).Text '91%, resets Tue 08:00' 'another day: the day too'
    Assert-Equal (Get-LimitView (Read-KeyValues "FiveHour=80`r`nFiveHourResets=$($now - 5)") 'FiveHour' $now $utc).Text '0%' 'reset since it was written'
    Assert-True ($null -eq (Get-LimitView (Read-KeyValues '') 'Week' $now $utc)) 'none'
    Assert-True ($null -eq (Get-LimitView (Read-KeyValues 'Week=lots') 'Week' $now $utc)) 'not a number'
    Assert-Equal (Get-LimitView (Read-KeyValues 'Week=140') 'Week' $now $utc).Pct 100.0 'at most 100'
}

Test 'claude code: the limits in the meters' {
    $colors = @{ Accent = 'A'; Warn = 'W' }
    $bang = Format-UsageBang @{ Pct = 42.5; Text = '42%, resets 09:00' } @{ Pct = 95.0; Text = '95%' } '' '' 'CW3_' 'CW3' 'Raintile' $colors
    Assert-True ($bang.Contains('[!SetOption "CW3_FiveValue" "Text" "42%, resets 09:00" "Raintile"]')) 'the 5 hours'
    Assert-True ($bang.Contains('[!SetOption "CW3_FivePct" "Formula" "42.5" "Raintile"]')) 'its bar'
    Assert-True ($bang.Contains('[!SetOption "CW3_WeekBar" "BarColor" "W" "Raintile"]')) 'nearly used up: the warning colour'
    Assert-True ($bang.EndsWith('[!Redraw "Raintile"]')) 'redrawn'
    Assert-True ($bang.Contains('"CW3_FiveLabel" "Text" "5 hours"')) 'just given: no age'
    $old = Format-UsageBang @{ Pct = 42.5; Text = '42%' } $null '' '40 min' 'CW3_' 'CW3' 'Raintile' $colors
    Assert-True ($old.Contains('"CW3_FiveLabel" "Text" "5 hours, 40 min ago"')) 'given a while ago: how long'
    $none = Format-UsageBang $null $null 'not set up' '40 min' 'CW3_' 'CW3' 'Raintile' $colors
    Assert-True ($none.Contains('"CW3_FiveValue" "Text" "not set up"')) 'why there are none'
    Assert-True ($none.Contains('"CW3_WeekValue" "Text" "-"')) 'the week: empty'
    Assert-True ($none.Contains('"CW3_FiveLabel" "Text" "5 hours"')) 'no age without limits'
}

Test 'claude code: how to set the status line' {
    $help = Get-StatusLineHelp 'C:\Data\Widgets\ClaudeCode\StatusLine.ps1' 'C:\Users\x\.claude'
    Assert-True ($help.Contains('C:\Users\x\.claude\settings.json')) 'where'
    Assert-True ($help.Contains('"command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Data\\Widgets\\ClaudeCode\\StatusLine.ps1\""')) 'the entry, as JSON'
    $entry = @($help -split "`r`n" | Where-Object { $_ -match '^\s{4,}("|\})' }) -join ''
    $json = '{' + $entry + '}'
    Assert-Equal (($json | ConvertFrom-Json).statusLine.command) 'powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Data\Widgets\ClaudeCode\StatusLine.ps1"' 'JSON that reads back'
}

Test 'claude code: the status line keeps the limits' {
    $five = Get-LimitValue ('{"used_percentage": 42.5, "resets_at": 1800003600}' | ConvertFrom-Json)
    Assert-Equal $five.Used 42.5 'the use'
    Assert-Equal $five.Resets ([long]1800003600) 'the reset'
    Assert-True ($null -eq (Get-LimitValue $null)) 'no limit (an API key)'
    Assert-Equal (Format-Limits $five $null 1800000000) "FiveHour=42.5`r`nFiveHourResets=1800003600`r`nUpdated=1800000000" 'the file, without the week'
    # (written again when the limits change, or a minute later: how old they are)
    $a = Format-Limits $five $null 1800000000
    Assert-True (-not (Test-LimitsChanged (Format-Limits $five $null 1800000030) $a 1800000030)) 'the same limits half a minute later'
    Assert-True (Test-LimitsChanged (Format-Limits $five $null 1800000060) $a 1800000060) 'the same limits a minute later'
    Assert-True (Test-LimitsChanged (Format-Limits @{ Used = 50.0; Resets = 1800003600 } $null 1800000010) $a 1800000010) 'other limits'
    Assert-True (Test-LimitsChanged $a $null 1800000000) 'no file yet'
    Assert-Equal (Format-StatusLine 'Opus' $five @{ Used = 7.6; Resets = 0 }) 'Opus | 5h 43% | week 8%' 'the line'
    Assert-Equal (Format-StatusLine 'Opus' $null $null) 'Opus | no limits reported' 'without limits: said'
    Assert-Equal (Format-Limits $null $null 5) "Reported=0`r`nUpdated=5" 'the file without limits'
    # (the script itself, given Claude Code's input on standard input)
    $dir = New-TestFolder
    $out = Join-Path $dir 'limits.txt'
    $inFile = Join-Path $dir 'input.json'
    [IO.File]::WriteAllText($inFile, '{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1800003600},"seven_day":{"used_percentage":30,"resets_at":1800300000}}}')
    $shell = (Get-Process -Id $PID).Path
    $p = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$lineScript`"", '-Out', "`"$out`"") `
        -RedirectStandardInput $inFile -RedirectStandardOutput (Join-Path $dir 'line.txt') -NoNewWindow -Wait -PassThru
    Assert-Equal $p.ExitCode 0 'the exit code'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $dir 'line.txt')).Trim()) 'Opus | 5h 12% | week 30%' 'what Claude Code shows'
    $limits = Read-KeyValues ([IO.File]::ReadAllText($out))
    Assert-Equal $limits['Week'] '30' 'the week kept'
    Assert-Equal $limits['FiveHourResets'] '1800003600' 'the reset kept'
    # an input without limits (a new session, an API key): the limits kept
    # stay; with no file yet, one that says none came
    $run = {
        param($json)
        [IO.File]::WriteAllText($inFile, $json)
        $q = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$lineScript`"", '-Out', "`"$out`"") `
            -RedirectStandardInput $inFile -RedirectStandardOutput (Join-Path $dir 'line.txt') -NoNewWindow -Wait -PassThru
        Assert-Equal $q.ExitCode 0 'the exit code'
    }
    & $run '{"model":{"display_name":"Opus"}}'
    Assert-Equal (Read-KeyValues ([IO.File]::ReadAllText($out)))['Week'] '30' 'limits lost to an input without them'
    Remove-Item -LiteralPath $out
    & $run '{"model":{"display_name":"Opus"}}'
    Assert-True ([IO.File]::ReadAllText($out).StartsWith("Reported=0`r`nUpdated=")) 'nothing says Claude Code gives no limits'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $dir 'line.txt')).Trim()) 'Opus | no limits reported' 'the line without limits'
}
