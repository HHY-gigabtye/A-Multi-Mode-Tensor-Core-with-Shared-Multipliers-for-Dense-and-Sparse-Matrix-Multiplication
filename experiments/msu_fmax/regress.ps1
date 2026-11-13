param([Parameter(Mandatory=$true)][string]$Trial)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$trialDir = Join-Path $PSScriptRoot $Trial
New-Item -ItemType Directory -Force -Path $trialDir | Out-Null
Set-Location $repo
$sim = 'C:/intelFPGA/20.1/modelsim_ase/win32aloem/vsim.exe'
& $sim -c -l (Join-Path $trialDir 'units.log') -do integration_sv/sim/run_units.do
if ($LASTEXITCODE -ne 0) { throw "Unit simulation exited $LASTEXITCODE" }
& (Join-Path $PSScriptRoot 'check_regression.ps1') -Trial $Trial -UnitsOnly
& $sim -c -l (Join-Path $trialDir 'top.log') -do integration_sv/sim/run_top.do
if ($LASTEXITCODE -ne 0) { throw "Integration simulation exited $LASTEXITCODE" }
& (Join-Path $PSScriptRoot 'check_regression.ps1') -Trial $Trial
