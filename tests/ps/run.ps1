# Runs the PowerShell tests (tests/ps/*.Tests.ps1), on temporary folders.
# Windows PowerShell 5.1, as the skin; run by tools/check.py.
#
# Each test file calls Test 'name' { ... }: a test passes if its block does
# not throw. Output: "ok   <name>" or "FAIL <name>: <reason>"; the exit code
# is the number of failures.
#
# No .ini file in tests/: the repository can be the skin folder itself, and
# Rainmeter would list it as a skin.

param([string]$Filter = '')

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:Failed = 0
$script:Folders = New-Object System.Collections.ArrayList

function Assert-Equal($Actual, $Expected, [string]$What = 'value') {
    if (-not ($Actual -ceq $Expected)) { throw "$What`: expected <$Expected>, got <$Actual>" }
}

function Assert-True($Condition, [string]$What = 'condition') {
    if (-not $Condition) { throw "$What" }
}

# An empty folder, removed after the tests
function New-TestFolder {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('raintile-test-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    New-Item -ItemType Directory -Path $path | Out-Null
    [void]$script:Folders.Add($path)
    return $path
}

# Defines a function of a script without running the script (found with the
# parser): its helpers can be tested on their own.
function Import-ScriptFunction([string]$Path, [string]$Name) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true)
    if (-not $fn) { throw "no function $Name in $Path" }
    Invoke-Expression ($fn.Extent.Text -replace '^function\s+', 'function global:')
}

function Test([string]$Name, [scriptblock]$Body) {
    if ($Filter -and $Name -notlike "*$Filter*") { return }
    try {
        & $Body
        Write-Output "ok   $Name"
    } catch {
        $script:Failed++
        $where = $_.InvocationInfo.ScriptName
        $line = $_.InvocationInfo.ScriptLineNumber
        Write-Output ("FAIL {0}: {1} ({2}:{3})" -f $Name, $_.Exception.Message, (Split-Path -Leaf $where), $line)
    }
}

try {
    foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' | Sort-Object Name) {
        . $file.FullName
    }
} finally {
    foreach ($f in $script:Folders) { Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue }
}
exit $script:Failed
