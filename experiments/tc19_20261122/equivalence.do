onerror {quit -f -code 1}
onbreak {}
set trial [file normalize [pwd]]
set build [file join $trial candidate equivalence_build]
file mkdir $build
cd $build
if {![file isdirectory work]} {vlib work}
vmap work work
set fd [open [file join $trial baseline src tensor_core_sv outer_product_core.sv] r]
set reference [read $fd]
close $fd
set renamed [string map {{module outer_product_core (} {module outer_product_core_baseline (}} $reference]
if {$renamed eq $reference} {error "Missing baseline module declaration"}
set fd [open outer_product_core_baseline.sv w]
puts -nonewline $fd $renamed
close $fd
vlog -sv -work work [file join $trial baseline src tensor_core_sv tensor_core_pkg.sv]
vlog -sv -work work outer_product_core_baseline.sv
vlog -sv -work work [file join $trial candidate src tensor_core_sv outer_product_core.sv]
foreach tb {tb_pre_route_equiv tb_tc19_bounds} {
  vlog -sv -work work [file join $trial ${tb}.sv]
  vsim -onfinish stop work.$tb
  run -all
  if {[examine -radix unsigned /${tb}/passed] != 1} {quit -f -code 1}
  quit -sim
}
quit -f -code 0
