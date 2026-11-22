param(
  [Parameter(Mandatory=$true)][ValidateSet('baseline','candidate_v2')][string]$Variant,
  [ValidateSet('rtl','timing','functional')][string]$Kind='rtl',
  [string]$RunName=''
)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$src=Join-Path $root "$Variant/src"
if (!$RunName) {$RunName=$Kind}
$build=Join-Path $root "$Variant/$RunName"
if (Test-Path -LiteralPath $build) {throw "Preserve existing run: $build"}
New-Item -ItemType Directory -Path $build | Out-Null
$bin='C:/Xilinx/Vivado/2022.2/bin'
Push-Location $build
try {
  $packages=@('du_tia_sv/rtl/du_tia_pkg.sv','mlu_sv/mlu_pkg.sv','tensor_core_sv/tensor_core_pkg.sv','fifo_sv/du_tc_bridge_pkg.sv','msu_sv/rtl/msu_pkg.sv')
  $rtl=@('mlu_sv/mlu.sv','du_tia_sv/rtl/du_tia.sv','fifo_sv/du_tc_bridge.sv','tensor_core_sv/outer_product_core.sv','msu_sv/rtl/msu.sv','integration_sv/rtl/sparse_tensor_core_top.sv')
  $files=@($packages | ForEach-Object {Join-Path $src $_})
  if ($Kind -eq 'rtl') {$files+=@($rtl | ForEach-Object {Join-Path $src $_})}
  $files+=Join-Path $root '../tb_power.sv'
  $defines=@()
  if ($Kind -ne 'rtl') {$defines=@('--define','POWER_NETLIST')}
  & "$bin/xvlog.bat" --sv @defines @files *> compile.log
  if ($LASTEXITCODE -ne 0) {throw 'SV compilation failed: compile.log'}
  $elab=@('--debug','typical','--mt','2','--snapshot','power_sim','work.tb_power')
  if ($Kind -ne 'rtl') {
    $netlist=if ($Kind -eq 'timing') {'routed.v'} else {'routed_functional.v'}
    & "$bin/xvlog.bat" (Join-Path $root "$Variant/routed/$netlist") 'C:/Xilinx/Vivado/2022.2/data/verilog/src/glbl.v' *> compile_netlist.log
    if ($LASTEXITCODE -ne 0) {throw 'Netlist compilation failed'}
    $elab+=@('work.glbl','-L','unisims_ver','-L','secureip')
    if ($Kind -eq 'timing') {
      $sdf=(Join-Path $root "$Variant/routed.sdf").Replace('\','/')
      $elab+=@('-L','simprims_ver','--sdfmax',('"/tb_power/dut={0}"' -f $sdf),'--transport_int_delays','--pulse_r','0','--pulse_int_r','0','--pulse_e','0','--pulse_int_e','0')
    }
  }
  & "$bin/xelab.bat" @elab *> elaborate.log
  if ($LASTEXITCODE -ne 0) {throw 'Elaboration failed: elaborate.log'}
  foreach ($mode in 0..2) {
    $name=@('dense','hybrid','dual')[$mode]
    $out=Join-Path $build $name
    New-Item -ItemType Directory -Path $out | Out-Null
    $env:POWER_RUN_OUT=$out
    $env:POWER_CAPTURE=if ($Kind -ne 'rtl') {'1'} else {'0'}
    $batch=(Join-Path $root '../simulate.tcl').Replace('\','/')
    $simlog=(Join-Path $out 'simulation.log').Replace('\','/')
    & "$bin/xsim.bat" power_sim --testplusarg $name.ToUpper() --tclbatch $batch --log $simlog *> (Join-Path $out 'console.log')
    if ($LASTEXITCODE -ne 0) {throw "$name simulation failed"}
    $log=Get-Content -Raw -LiteralPath (Join-Path $out 'simulation.log')
    if (!$log.Contains('POWER_SIMULATION_PASS') -or !$log.Contains('POWER WORKLOAD PASS') -or $log -match 'Fatal:|Error:|Timing Violation|Timing violation') {throw "$name simulation failed; inspect $out"}
    $line=@(Get-Content (Join-Path $out 'simulation.log') | Where-Object {$_ -match '^POWER WORKLOAD PASS|^POWER_SIMULATION_PASS'})
    $line | Set-Content (Join-Path $out 'PASS.txt')
    Copy-Item -LiteralPath (Join-Path $build "transactions_$mode.trace") -Destination (Join-Path $out 'transactions.trace')
    Write-Output "$Variant $Kind $name PASS"
  }
} finally {Pop-Location}
