onerror {quit -f -code 1}
set trial [file normalize [pwd]]
if {![file exists [file join $trial tb_pre_route_equiv.sv]]} {
  error "Run ModelSim from the pre_route_20261122 experiment directory"
}
set variant candidate_v2
if {[info exists ::env(PRE_ROUTE_VARIANT)]} {set variant $::env(PRE_ROUTE_VARIANT)}
if {$variant ni {candidate candidate_v2}} {error "Unknown candidate variant"}
set build [file join $trial $variant equivalence_build]
file mkdir $build
cd $build
onbreak {}
if {![file isdirectory work]} {vlib work}
vmap work work
# Rename only the module declaration in a generated compilation adapter.
# The baseline source snapshot remains byte-for-byte unchanged.
set fd [open [file join $trial baseline src tensor_core_sv outer_product_core.sv] r]
set reference [read $fd]
close $fd
set renamed [string map {{module outer_product_core (} {module outer_product_core_baseline (}} $reference]
if {$renamed eq $reference} {error "Baseline module declaration was not found"}
set fd [open outer_product_core_baseline.sv w]
puts -nonewline $fd $renamed
close $fd
vlog -sv -work work [file join $trial baseline src tensor_core_sv tensor_core_pkg.sv]
vlog -sv -work work outer_product_core_baseline.sv
vlog -sv -work work [file join $trial $variant src tensor_core_sv outer_product_core.sv]
vlog -sv -work work [file join $trial tb_pre_route_equiv.sv]
vsim -onfinish stop work.tb_pre_route_equiv
run -all
if {[examine -radix unsigned /tb_pre_route_equiv/passed] != 1} {quit -f -code 1}
quit -f -code 0
