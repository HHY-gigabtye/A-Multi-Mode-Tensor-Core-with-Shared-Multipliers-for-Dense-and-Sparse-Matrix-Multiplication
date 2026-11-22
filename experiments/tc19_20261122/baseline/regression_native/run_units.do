# Production units and the standalone comparison use separate libraries.
set root [pwd]
if {[info exists ::env(STC_ROOT)]} {set root $::env(STC_ROOT)}
set root [file normalize $root]
while {![file exists [file join $root mlu_sv mlu.sv]]} {
  set parent [file dirname $root]
  if {$parent eq $root} {error "Run from the repository or set STC_ROOT"}
  set root $parent
}
set build {C:/Users/Jason/Desktop/TC/experiments/tc19_20261122/baseline/regression_native/build/units}
file mkdir $build
cd $build
onerror {quit -f -code 1}
# $finish with onfinish=stop also invokes onbreak in ModelSim 2020.1.
# The PowerShell runner checks all five PASS markers and fatal/error text.
onbreak {}
set cases [list \
  [list mlu tb_mlu {mlu_sv/du_tia_pkg.sv mlu_sv/mlu_pkg.sv mlu_sv/mlu.sv mlu_sv/tb_mlu.sv} mlu_sv/mlu_vectors.txt] \
  [list du_tia tb_du_tia {du_tia_sv/rtl/du_tia_pkg.sv du_tia_sv/rtl/du_tia.sv du_tia_sv/tb/tb_du_tia.sv} {}] \
  [list bridge tb_bridge {fifo_sv/tensor_core_pkg.sv fifo_sv/du_tc_bridge_pkg.sv fifo_sv/du_tc_bridge.sv fifo_sv/tb_bridge.sv} fifo_sv/vectors/bridge_vectors.txt] \
  [list tc tb_outer_core {tensor_core_sv/tensor_core_pkg.sv tensor_core_sv/outer_product_core.sv tensor_core_sv/tb_outer_core.sv} tensor_core_sv/c_vectors.txt] \
  [list compare tb_compare {tensor_core_sv/tensor_core_pkg.sv tensor_core_sv/outer_product_core.sv tensor_core_sv/tensor_core.sv tensor_core_sv/tb_compare.sv} {}] \
  [list msu tb_msu {msu_sv/rtl/msu_pkg.sv msu_sv/rtl/msu.sv msu_sv/tb/tb_msu.sv} msu_sv/vectors/msu_vectors.txt]]
foreach spec $cases {
  lassign $spec name tb sources vectors
  set lib unit_${name}
  if {![file isdirectory $lib]} {vlib $lib}
  vmap $lib $lib
  foreach source $sources {vlog -sv -work $lib [file join $root $source]}
  if {$vectors eq {}} {
    vsim -onfinish stop ${lib}.${tb}
  } else {
    vsim -onfinish stop ${lib}.${tb} +VECTORS=[file join $root $vectors]
  }
  run -all
  if {$name in {tc compare} && [examine -radix unsigned /${tb}/passed] != 1} {quit -f -code 1}
  quit -sim
}
quit -f -code 0
