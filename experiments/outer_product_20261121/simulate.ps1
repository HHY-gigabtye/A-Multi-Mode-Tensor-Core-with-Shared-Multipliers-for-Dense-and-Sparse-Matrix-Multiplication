param([Parameter(Mandatory)][ValidateSet('unit','top','compare')][string]$Case)
$ErrorActionPreference = 'Stop'
$env:OUTER_TRIAL = $PSScriptRoot
$env:OUTER_CASE = $Case
& vsim -c -l (Join-Path $PSScriptRoot "$Case.log") -do (Join-Path $PSScriptRoot 'simulate.do')
if ($LASTEXITCODE -ne 0) { throw "ModelSim failed: $Case" }
