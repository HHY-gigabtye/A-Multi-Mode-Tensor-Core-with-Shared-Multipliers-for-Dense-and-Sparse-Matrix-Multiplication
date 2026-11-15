# Standalone supplemental equivalence check; original regressions are unchanged.
onerror {quit -f -code 1}
onbreak {}
set reject_root [file normalize [pwd]]
set reject_experiment [file join $reject_root experiments msu_fmax head_mux_20261115]
set reject_build [file join $reject_experiment product_shadow rejection_equiv]
if {[file exists $reject_build]} {error "Use a new output directory"}
file mkdir $reject_build
set reject_fd [open [file join $reject_experiment baseline src tensor_core_sv tensor_core.sv] r]
set reject_source [read $reject_fd]
close $reject_fd
# Only rename the immutable baseline module to instantiate both versions.
set reject_count [regsub {module tensor_core \(} $reject_source {module tensor_core_baseline (} reject_renamed]
if {$reject_count != 1} {error "Unexpected baseline module declaration"}
set reject_fd [open [file join $reject_build tensor_core_baseline.sv] w]
puts -nonewline $reject_fd $reject_renamed
close $reject_fd
cd $reject_build
vlib work
vmap work work
vlog -sv [file join $reject_experiment product_shadow src tensor_core_sv tensor_core_pkg.sv]
vlog -sv [file join $reject_experiment product_shadow src tensor_core_sv tensor_core.sv]
vlog -sv tensor_core_baseline.sv
vlog -sv [file join $reject_experiment tb_product_rejections.sv]
vsim -onfinish stop work.tb_product_rejections
run -all
quit -f -code 0
