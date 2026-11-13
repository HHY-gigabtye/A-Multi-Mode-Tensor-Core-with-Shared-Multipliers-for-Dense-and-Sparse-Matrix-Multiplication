param([Parameter(Mandatory=$true)][string]$Trial)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$trialDir = Join-Path $PSScriptRoot $Trial
$srcDir = Join-Path $trialDir 'src'
if (Test-Path -LiteralPath $srcDir) { throw "Snapshot already exists: $srcDir" }
$rows = foreach ($entry in (Import-Csv (Join-Path $repo 'experiments/clock_control/result_local/sources.csv'))) {
    $source = Join-Path $repo $entry.Path
    $destination = Join-Path $srcDir $entry.Path
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
    [pscustomobject]@{Path=$entry.Path; SHA256=(Get-FileHash -LiteralPath $destination).Hash}
}
$rows | Export-Csv -NoTypeInformation (Join-Path $trialDir 'sources.csv')
git -C $repo rev-parse HEAD | Set-Content (Join-Path $trialDir 'base_commit.txt')
git -C $repo diff -- msu_sv/rtl/msu.sv tensor_core_sv/tensor_core.sv fifo_sv/du_tc_bridge.sv | Set-Content -Encoding utf8 (Join-Path $trialDir 'rtl.patch')
