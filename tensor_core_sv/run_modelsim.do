# From the repository root: vsim -c -do tensor_core_sv/run_modelsim.do
# In the GUI, run from the repository or set env(STC_ROOT) to the checkout.
if {[batch_mode]} {onerror {quit -f -code 1}} else {onerror {abort}}
onbreak {}
set tc_source_dir [pwd]
if {[info exists ::env(STC_ROOT)]} {set tc_source_dir $::env(STC_ROOT)}
if {[file exists [file join $tc_source_dir tensor_core_sv outer_product_core.sv]]} {
    set tc_source_dir [file join $tc_source_dir tensor_core_sv]
} elseif {![file exists [file join $tc_source_dir outer_product_core.sv]]} {
    set tc_source_dir [file dirname [file normalize [info script]]]
}
if {![file exists [file join $tc_source_dir outer_product_core.sv]]} {
    error "Run from the repository root or set STC_ROOT"
}
set tc_source_dir [file normalize $tc_source_dir]
file mkdir [file join $tc_source_dir build modelsim]
cd [file join $tc_source_dir build modelsim]
if {![file isdirectory work]} {vlib work}
vmap work work
foreach src {tensor_core_pkg.sv outer_product_core.sv tb_outer_core.sv} {
    vlog -sv [file join $tc_source_dir $src]
}
vsim -onfinish stop -voptargs=+acc work.tb_outer_core +VECTORS=[file join $tc_source_dir c_vectors.txt]
if {![batch_mode]} {
    foreach signal {clk rst_n in_valid in_ready in_packet result_ready result_valid result status tick_info} {
        add wave /tb_outer_core/$signal
    }
}
run -all
if {[examine -radix unsigned /tb_outer_core/passed] != 1} {error "Outer-product unit did not reach PASS"}
if {[batch_mode]} {quit -f -code 0}
