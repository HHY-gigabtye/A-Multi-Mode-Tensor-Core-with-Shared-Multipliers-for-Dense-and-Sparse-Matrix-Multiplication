param([Parameter(Mandatory=$true)][ValidateSet('baseline','candidate_v2')][string]$Variant)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$build=Join-Path $root "$Variant/functional"
$capture=Join-Path $root "$Variant/functional_net_saif"
if (Test-Path -LiteralPath $capture) {throw 'Preserve existing capture'}
New-Item -ItemType Directory -Path $capture | Out-Null
Push-Location $build
try {
  foreach ($mode in 0..2) {
    $name=@('dense','hybrid','dual')[$mode]
    $out=Join-Path $capture $name
    New-Item -ItemType Directory -Path $out | Out-Null
    $env:POWER_RUN_OUT=$out; $env:POWER_CAPTURE='1'
    $batch=(Join-Path $root 'simulate.tcl').Replace('\','/')
    $simlog=(Join-Path $out 'simulation.log').Replace('\','/')
    & 'C:/Xilinx/Vivado/2022.2/bin/xsim.bat' power_sim --testplusarg $name.ToUpper() --tclbatch $batch --log $simlog *> (Join-Path $out 'console.log')
    if ($LASTEXITCODE -ne 0) {throw "$name simulation exit $LASTEXITCODE"}
    $log=Get-Content -Raw -LiteralPath (Join-Path $out 'simulation.log')
    if (!$log.Contains('POWER_SIMULATION_PASS') -or !$log.Contains('POWER WORKLOAD PASS') -or $log -match 'Fatal:|Error:|Timing Violation|Timing violation') {throw "Failed $name"}
    Get-Content (Join-Path $out 'simulation.log') | Where-Object {$_ -match '^POWER WORKLOAD PASS|^POWER_SIMULATION_PASS'} | Set-Content (Join-Path $out 'PASS.txt')
    Copy-Item -LiteralPath (Join-Path $build "transactions_$mode.trace") -Destination (Join-Path $out 'transactions.trace')
    Write-Output "$Variant functional_net_saif $name PASS"
  }
} finally {Pop-Location}
