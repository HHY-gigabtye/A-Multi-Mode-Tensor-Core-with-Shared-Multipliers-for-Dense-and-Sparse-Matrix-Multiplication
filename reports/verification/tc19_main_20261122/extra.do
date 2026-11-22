onerror {quit -f -code 1}
onbreak {}
set root [file normalize $env(STC_ROOT)]
set trial [file join $root experiments tc19_20261122]
set build [file join $env(TC19_MAIN_OUTPUT) build extra]
file mkdir $build
cd $build
if {![file isdirectory work]} {vlib work}
vmap work work
# Rename only the preserved 32-bit module in a generated build adapter.
set fd [open [file join $trial baseline src tensor_core_sv outer_product_core.sv] r]
set reference [read $fd]
close $fd
set renamed [string map {{module outer_product_core (} {module outer_product_core_baseline (}} $reference]
if {$renamed eq $reference} {error "Missing baseline module declaration"}
set fd [open outer_product_core_baseline.sv w]
puts -nonewline $fd $renamed
close $fd
vlog -sv -work work [file join $root tensor_core_sv tensor_core_pkg.sv]
vlog -sv -work work outer_product_core_baseline.sv
vlog -sv -work work [file join $root tensor_core_sv outer_product_core.sv]
foreach tb {tb_pre_route_equiv tb_tc19_bounds} {
  vlog -sv -work work [file join $trial ${tb}.sv]
  vsim -onfinish stop work.$tb
  run -all
  if {[examine -radix unsigned /${tb}/passed] != 1} {quit -f -code 1}
  quit -sim
}
quit -f -code 0
