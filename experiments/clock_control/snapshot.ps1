param([Parameter(Mandatory=$true)][string]$Trial)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$trialDir = Join-Path $PSScriptRoot $Trial
if (Test-Path (Join-Path $trialDir 'sources.csv')) { throw 'Snapshot already exists; use a new trial name.' }
New-Item -ItemType Directory -Force $trialDir | Out-Null
$sourceFiles = @(
    'tensor_core_sv/tensor_core_pkg.sv', 'fifo_sv/du_tc_bridge_pkg.sv',
    'fifo_sv/du_tc_bridge.sv', 'du_tia_sv/rtl/du_tia_pkg.sv',
    'du_tia_sv/rtl/du_tia.sv', 'mlu_sv/mlu_pkg.sv', 'mlu_sv/mlu.sv',
    'msu_sv/rtl/msu_pkg.sv', 'msu_sv/rtl/msu.sv',
    'tensor_core_sv/tensor_core.sv', 'integration_sv/rtl/sparse_tensor_core_top.sv'
)
$sourceFiles | ForEach-Object {
    $source = Join-Path $repoRoot $_
    $destination = Join-Path $trialDir "src/$_"
    New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
    [pscustomobject]@{Path=$_; SHA256=(Get-FileHash -LiteralPath $source).Hash}
} | Export-Csv (Join-Path $trialDir 'sources.csv') -NoTypeInformation
