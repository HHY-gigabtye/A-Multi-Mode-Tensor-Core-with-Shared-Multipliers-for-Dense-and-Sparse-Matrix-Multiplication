$ErrorActionPreference = 'Stop'
$repoRoot = (Get-Location).Path
$runDir = Join-Path $repoRoot ('build/tc19_extra_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff'))
$logPath = Join-Path $runDir 'extra.log'
$previousRoot = $env:STC_ROOT
$previousOutput = $env:TC19_MAIN_OUTPUT
New-Item -ItemType Directory -Path $runDir | Out-Null
try {
    $env:STC_ROOT = $repoRoot
    $env:TC19_MAIN_OUTPUT = $runDir
    & vsim -c -l $logPath -do reports/verification/tc19_main_20261122/extra.do
    if ($LASTEXITCODE -ne 0) { throw 'ModelSim supplemental tests failed' }
    $logText = Get-Content -Raw -LiteralPath $logPath
    if ($logText -match '\*\*\s+(Fatal|Error):') { throw 'Simulator error; inspect extra.log' }
    foreach ($marker in 'PRE_ROUTE EQUIVALENCE PASS', 'TC19 BOUNDS PASS') {
        if (!$logText.Contains($marker)) { throw "Missing PASS marker: $marker" }
    }
    Get-Content -LiteralPath $logPath | Select-String '^# (PRE_ROUTE EQUIVALENCE PASS|TC19 BOUNDS PASS)'
} finally {
    $env:STC_ROOT = $previousRoot
    $env:TC19_MAIN_OUTPUT = $previousOutput
}

