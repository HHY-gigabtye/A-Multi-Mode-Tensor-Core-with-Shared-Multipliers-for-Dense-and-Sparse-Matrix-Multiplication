# Convenience launcher only; all stimulus, models and checking are SV.
param([switch]$TopOnly, [string]$Vsim = 'vsim')
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$resultDir = Join-Path $repoRoot 'integration_sv/results'
New-Item -ItemType Directory -Force $resultDir | Out-Null
function Invoke-SvRegression([string]$Name, [string[]]$Markers) {
    $logPath = Join-Path $resultDir "$Name.log"
    & $Vsim -c -l $logPath -do "integration_sv/sim/run_$Name.do"
    if ($LASTEXITCODE -ne 0) { throw "ModelSim $Name failed (exit $LASTEXITCODE)" }
    $logText = Get-Content -Raw -LiteralPath $logPath
    if ($logText -match '\*\*\s+(Fatal|Error):') { throw "ModelSim reported an error in $logPath" }
    foreach ($marker in $Markers) {
        if (!$logText.Contains($marker)) { throw "Missing PASS marker '$marker' in $logPath" }
    }
}
Push-Location $repoRoot
try {
    if (!$TopOnly) {
        Invoke-SvRegression 'units' @('ALL PASS MLU unit C/SV:', '[PASS] DU/TIA compact RTL:',
            'BRIDGE RTL PASS:', 'ALL PASS C/SV:', 'MSU SV PASS:')
    }
    Invoke-SvRegression 'top' @('TOP INTEGRATION PASS:')
    Write-Host 'ModelSim SV regression PASS'
} finally {
    Pop-Location
}
