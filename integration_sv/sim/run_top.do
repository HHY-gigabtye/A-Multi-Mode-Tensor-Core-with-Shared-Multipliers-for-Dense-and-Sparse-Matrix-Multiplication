# From repository root: vsim -c -do integration_sv/sim/run_top.do
# GUI: cd C:/Users/Jason/Desktop/TC; do integration_sv/sim/run_top.do
# Or set env(STC_ROOT) to the repository path before invoking this script.
set root [pwd]
if {[info exists ::env(STC_ROOT)]} {set root $::env(STC_ROOT)}
set root [file normalize $root]
while {![file exists [file join $root mlu_sv mlu.sv]]} {
  set parent [file dirname $root]
  if {$parent eq $root} {error "Run from the repository or set STC_ROOT"}
  set root $parent
}
set build [file join $root integration_sv build top]
file mkdir $build
cd $build
onerror {quit -f -code 1}
onbreak {}
if {![file isdirectory work]} {vlib work}
vmap work work
# Exactly one copy of each package; the unit-local copies are identical today.
foreach src {
  du_tia_sv/rtl/du_tia_pkg.sv
  mlu_sv/mlu_pkg.sv
  tensor_core_sv/tensor_core_pkg.sv
  fifo_sv/du_tc_bridge_pkg.sv
  msu_sv/rtl/msu_pkg.sv
  mlu_sv/mlu.sv
  du_tia_sv/rtl/du_tia.sv
  fifo_sv/du_tc_bridge.sv
  tensor_core_sv/tensor_core.sv
  msu_sv/rtl/msu.sv
  integration_sv/rtl/sparse_tensor_core_top.sv
  integration_sv/tb/tb_sparse_tensor_core_top.sv
} {vlog -sv -work work [file join $root $src]}
vsim -onfinish stop -voptargs=+acc work.tb_sparse_tensor_core_top
log -r /tb_sparse_tensor_core_top/dut/*
if {![batch_mode]} {do [file join $root integration_sv sim wave_top.do]}
run -all
if {[examine -radix unsigned /tb_sparse_tensor_core_top/passed] != 1} {
  if {[batch_mode]} {quit -f -code 1}
  error "Integration test did not reach PASS; inspect Transcript"
}
if {[batch_mode]} {quit -f -code 0} else {wave zoom full}
