# The Options program (src/Options): its helpers that hold a rule of
# docs/OptionsUI.md, called on the built program. Windows only, with the
# program in @Resources\Bin when it is newer than its sources (dev-build.ps1),
# otherwise built here (needs the .NET SDK); without either the tests are
# skipped and say so.

function Get-OptionsProgram {
    if ($env:OS -ne 'Windows_NT') { return $null }
    $src = Join-Path $Root 'src\Options'
    $newest = (Get-ChildItem -LiteralPath $src -Recurse -File | Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } |
        Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum
    $exe = Join-Path $Root '@Resources\Bin\RaintileOptions.exe'
    if ((Test-Path -LiteralPath $exe) -and (Get-Item -LiteralPath $exe).LastWriteTimeUtc -ge $newest) { return $exe }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { return $null }
    $out = Join-Path $Root 'build\options-tests'
    $log = & dotnet build (Join-Path $src 'RaintileOptions.csproj') -c Release -o $out -nologo -v q 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("the Options program does not build:`n" + ($log -join "`n")) }
    return (Join-Path $out 'RaintileOptions.exe')
}

$optionsExe = Get-OptionsProgram
if (-not $optionsExe) {
    Write-Output 'skip Options: no built program and no .NET SDK (or not Windows)'
    return
}
Add-Type -AssemblyName PresentationFramework
$optionsApp = [System.Reflection.Assembly]::LoadFrom($optionsExe).GetType('RaintileOptions.OptionsApp')
function Invoke-Options([string]$Name, [object[]]$Arguments) {
    # New-Object wraps what it makes in a PSObject: reflection wants the object
    # (assigned, not output: a list written to the pipeline becomes an array)
    $plain = New-Object object[] $Arguments.Count
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = $Arguments[$i]
        if ($null -ne $a) { $a = $a.psobject.BaseObject }
        $plain[$i] = $a
    }
    return $optionsApp.GetMethod($Name).Invoke($null, $plain)
}

Test 'Options: IsPartialNumber lets through only what can still be a number' {
    $all = '0123456789.-'
    foreach ($ok in '', '-', '7', '-70.5', '.5', '70.') { Assert-True (Invoke-Options 'IsPartialNumber' @($all, $ok)) "'$ok' refused" }
    foreach ($bad in '70-', '--7', '7.0.', '7a', ' 7', '7,5') { Assert-True (-not (Invoke-Options 'IsPartialNumber' @($all, $bad))) "'$bad' taken" }
    # a size: no minus sign; a count: no decimals either
    Assert-True (-not (Invoke-Options 'IsPartialNumber' @('0123456789.', '-7'))) 'minus taken by a box without it'
    Assert-True (-not (Invoke-Options 'IsPartialNumber' @('0123456789', '7.5'))) 'decimal point taken by a box without it'
}

Test 'Options: NumericOnly records the characters a box takes' {
    $tb = New-Object System.Windows.Controls.TextBox
    Invoke-Options 'NumericOnly' @($tb, $false, $true) | Out-Null
    Assert-Equal (Invoke-Options 'NumericChars' @($tb)) '0123456789.' 'characters of a size box'
    Assert-Equal (Invoke-Options 'NumericChars' @((New-Object System.Windows.Controls.TextBox))) $null 'characters of a text box'
}

Test 'Options: a choice box selects by value, the first when the value is not there' {
    $choices = [System.Collections.Generic.List[string[]]]::new()
    $choices.Add([string[]]@('V', 'Vertical')); $choices.Add([string[]]@('H', 'Horizontal'))
    $cb = Invoke-Options 'NewChoiceBox' @($choices, 'h', $null)
    Assert-Equal (Invoke-Options 'ChoiceValue' @($cb)) 'H' 'value selected (case-insensitive)'
    Assert-True (-not (Invoke-Options 'SelectChoice' @($cb, 'X'))) 'a value not in the list selected'
    Assert-Equal (Invoke-Options 'ChoiceValue' @($cb)) 'H' 'selection after a value not in the list'
    $cb = Invoke-Options 'NewChoiceBox' @($choices, 'X', $null)
    Assert-Equal (Invoke-Options 'ChoiceValue' @($cb)) 'V' 'first choice for a value not in the list'
}
