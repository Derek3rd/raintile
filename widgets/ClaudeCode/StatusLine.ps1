# Claude Code widget for Raintile: Claude Code's status line.
#
# Claude Code runs its status line command after its answers, with what the
# line may show on standard input (JSON), the use of the plan's limits
# among it: rate_limits.five_hour and rate_limits.seven_day, each with
# used_percentage and resets_at (Unix seconds). Nothing else on the PC has
# them, so this script, set as the status line (StatusLine.txt, written by
# ClaudeCode.ps1, says how), keeps them for the widget in limits.txt of its
# folder, written only when they change, and prints a short line for Claude
# Code: the model and the two limits.
#
# It never fails in Claude Code's face: anything wrong, it prints what it
# can (a line without the limits).

param([string]$Out = '')

$ErrorActionPreference = 'Stop'

# A limit of the input: @{ Used; Resets }, or $null (no such limit: an API
# key, or none reported yet)
function Get-LimitValue($Limit) {
    if ($null -eq $Limit) { return $null }
    $used = 0.0
    $resets = [long]0
    if (-not [double]::TryParse([string]$Limit.used_percentage, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$used)) { return $null }
    [void][long]::TryParse([string]$Limit.resets_at, [ref]$resets)
    return @{ Used = [Math]::Max(0.0, [Math]::Min(100.0, $used)); Resets = [Math]::Max([long]0, $resets) }
}

# limits.txt: FiveHour=<%>, FiveHourResets=<s>, Week=<%>, WeekResets=<s>
# (a limit not reported: left out; none: Reported=0)
function Format-Limits($Five, $Week) {
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $lines = @()
    if ($Five) { $lines += 'FiveHour=' + $Five.Used.ToString('0.#', $inv); $lines += 'FiveHourResets=' + $Five.Resets }
    if ($Week) { $lines += 'Week=' + $Week.Used.ToString('0.#', $inv); $lines += 'WeekResets=' + $Week.Resets }
    if ($lines.Count -eq 0) { $lines += 'Reported=0' }
    return ($lines -join "`r`n")
}

# The line Claude Code shows: "Opus | 5h 42% | week 18%" (ASCII, one line)
function Format-StatusLine([string]$Model, $Five, $Week) {
    $parts = @()
    $m = ($Model -replace '[^\x20-\x7E]', '').Trim()
    if ($m) { $parts += $m }
    if ($Five) { $parts += ('5h {0:0}%' -f $Five.Used) }
    if ($Week) { $parts += ('week {0:0}%' -f $Week.Used) }
    if (-not $Five -and -not $Week) { $parts += 'no limits reported' }
    return ($parts -join ' | ')
}

$model = ''
$five = $null
$week = $null
try {
    $in = [Console]::In.ReadToEnd()
    $data = $in | ConvertFrom-Json
    if ($data.model) { $model = [string]$data.model.display_name }
    if ($data.rate_limits) {
        $five = Get-LimitValue $data.rate_limits.five_hour
        $week = Get-LimitValue $data.rate_limits.seven_day
    }
    # (Claude Code's input without limits: written only while there is no
    # file, so the tile says "none reported" instead of "not set up", and
    # limits kept earlier are not lost to a session that has none yet)
    if (-not $Out) { $Out = Join-Path $PSScriptRoot 'limits.txt' }
    $has = Test-Path -LiteralPath $Out
    if ($five -or $week -or ($data -and -not $has)) {
        $text = Format-Limits $five $week
        $old = $null
        if ($has) { $old = [IO.File]::ReadAllText($Out) }
        if ($text -ne $old) {
            $tmp = "$Out.tmp"
            [IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding $false))
            Move-Item -LiteralPath $tmp -Destination $Out -Force
        }
    }
} catch { }
Write-Output (Format-StatusLine $model $five $week)
