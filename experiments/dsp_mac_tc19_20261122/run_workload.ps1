param(
  [Parameter(Mandatory=$true)][ValidateSet('baseline','candidate')][string]$Variant,
  [ValidateSet('rtl','functional')][string]$Kind='functional',
  [ValidateSet('routed','refined')][string]$Implementation='routed',
  [switch]$Bounds,
  [string]$RunName=''
)
$ErrorActionPreference='Stop'
$trial=$PSScriptRoot
$src=Join-Path $trial "$Variant/src"
if(!$RunName){$RunName=$Kind+$(if($Bounds){'_bounds'}else{'_workload'});if($Implementation -eq 'refined'){$RunName='refined_'+$RunName}}
$build=Join-Path $trial "$Variant/$RunName"
if(Test-Path -LiteralPath $build){throw "Preserve previous workload: $build"}
New-Item -ItemType Directory -Path $build | Out-Null
$bin='C:/Xilinx/Vivado/2022.2/bin'
$tb=if($Bounds){'tb_tc19_system'}else{'tb_power'}
Push-Location $build
try {
  $packages=@('du_tia_sv/rtl/du_tia_pkg.sv','mlu_sv/mlu_pkg.sv','tensor_core_sv/tensor_core_pkg.sv','fifo_sv/du_tc_bridge_pkg.sv','msu_sv/rtl/msu_pkg.sv')
  $rtl=@('mlu_sv/mlu.sv','du_tia_sv/rtl/du_tia.sv','fifo_sv/du_tc_bridge.sv','tensor_core_sv/outer_product_core.sv','msu_sv/rtl/msu.sv','integration_sv/rtl/sparse_tensor_core_top.sv')
  $files=@($packages | ForEach-Object {Join-Path $src $_})
  if($Kind -eq 'rtl'){$files+=@($rtl | ForEach-Object {Join-Path $src $_})}
  $files+=Join-Path $trial "$tb.sv"
  $defines=@()
  if($Kind -eq 'functional'){$defines=@('--define','POWER_NETLIST')}
  & "$bin/xvlog.bat" --sv @defines @files *> compile.log
  if($LASTEXITCODE -ne 0){throw 'SV compilation failed'}
  $elab=@('--debug','typical','--mt','2','--snapshot','workload_sim',"work.$tb")
  if($Kind -eq 'functional'){
    & "$bin/xvlog.bat" (Join-Path $trial "$Variant/$Implementation/routed_functional.v") 'C:/Xilinx/Vivado/2022.2/data/verilog/src/glbl.v' *> compile_netlist.log
    if($LASTEXITCODE -ne 0){throw 'Netlist compilation failed'}
    $elab+=@('work.glbl','-L','unisims_ver','-L','secureip')
  }
  & "$bin/xelab.bat" @elab *> elaborate.log
  if($LASTEXITCODE -ne 0){throw 'Elaboration failed'}
  foreach($mode in 0..2){
    $name=@('dense','hybrid','dual')[$mode]
    $out=Join-Path $build $name
    New-Item -ItemType Directory -Path $out | Out-Null
    $batch=Join-Path $out 'run.tcl'
    $commands="run all`nif {[get_value -radix unsigned /$tb/passed] != 1} {error {Workload did not pass}}`nputs {TC19_WORKLOAD_PASS}`nquit`n"
    [IO.File]::WriteAllText($batch,$commands,[Text.UTF8Encoding]::new($false))
    $simargs=@('workload_sim','--testplusarg',$name.ToUpper(),'--tclbatch',$batch.Replace('\','/'),'--log',(Join-Path $out 'simulation.log'))
    if($Bounds){$simargs+=@('--testplusarg','BOUNDS')}
    & "$bin/xsim.bat" @simargs *> (Join-Path $out 'console.log')
    if($LASTEXITCODE -ne 0){throw "$name simulation failed"}
    $log=Get-Content -Raw (Join-Path $out 'simulation.log')
    if(!$log.Contains('TC19_WORKLOAD_PASS') -or !$log.Contains('POWER WORKLOAD PASS') -or $log -match 'Fatal:|Error:|Timing Violation|Timing violation'){throw "$name failed"}
    Get-Content (Join-Path $out 'simulation.log') | Where-Object {$_ -match '^POWER WORKLOAD PASS|^TC19_WORKLOAD_PASS'} | Set-Content (Join-Path $out 'PASS.txt')
    Copy-Item -LiteralPath (Join-Path $build "transactions_$mode.trace") -Destination (Join-Path $out 'transactions.trace')
    Write-Output "$Variant $Kind bounds=$Bounds $name PASS"
  }
} finally {Pop-Location}
