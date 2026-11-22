param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$RunName,[switch]$Gate)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$build=Join-Path $root $RunName
if(Test-Path -LiteralPath $build){throw 'Preserve existing unit run'}
New-Item -ItemType Directory -Path $build | Out-Null
$file=(Resolve-Path -LiteralPath $Source).Path
Push-Location $build
try {
  $bin='C:/Xilinx/Vivado/2022.2/bin'
  $files=@((Join-Path $root '../../baseline/src/du_tia_sv/rtl/du_tia_pkg.sv'))
  if(!$Gate){$files+=@($file,(Join-Path $root 'du_gate.sv'))}
  $files+=Join-Path $root 'tb_du_gate.sv'
  & "$bin/xvlog.bat" --sv @files *> compile.log
  if($LASTEXITCODE -ne 0){throw 'Compile failed'}
  $args=@('--debug','typical','--mt','2','--snapshot','du_sim','work.tb_du_gate')
  if($Gate){
    & "$bin/xvlog.bat" $file 'C:/Xilinx/Vivado/2022.2/data/verilog/src/glbl.v' *> compile_gate.log
    if($LASTEXITCODE -ne 0){throw 'Netlist compile failed'}
    $args+=@('work.glbl','-L','unisims_ver','-L','secureip')
  }
  & "$bin/xelab.bat" @args *> elaborate.log
  if($LASTEXITCODE -ne 0){throw 'Elaboration failed'}
  & "$bin/xsim.bat" du_sim --tclbatch (Join-Path $root 'unit_sim.tcl').Replace('\','/') --log simulation.log *> console.log
  $log=Get-Content -Raw simulation.log
  if($LASTEXITCODE -ne 0 -or !$log.Contains('DU_UNIT_SIMULATION_PASS') -or $log -match 'Fatal:|Error:'){throw 'Unit simulation failed: inspect simulation.log'}
  Get-Content simulation.log | Where-Object {$_ -match '^DU GATE PASS|^DU_UNIT_SIMULATION_PASS'} | Set-Content PASS.txt
  Get-Content PASS.txt
} finally {Pop-Location}
