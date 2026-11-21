# Integrated FPGA OOC comparison with the rotating FIFO production baseline.
# Run from the trial directory. An optional argument selects a fresh report directory.
set trial [file normalize [file dirname [info script]]]
set repo [file normalize [file join $trial ../..]]
set out [file normalize [expr {$argc == 1 ? [lindex $argv 0] : [file join $trial routed]}]]
if {[file exists $out]} {error "Select a fresh output directory: $out"}
file mkdir $out
cd $out
set_param general.maxThreads 1
create_project -in_memory -part xc7z020clg484-1
set_property target_language Verilog [current_project]
foreach f {tensor_core_sv/tensor_core_pkg.sv fifo_sv/du_tc_bridge_pkg.sv
           fifo_sv/du_tc_bridge.sv du_tia_sv/rtl/du_tia_pkg.sv du_tia_sv/rtl/du_tia.sv
           mlu_sv/mlu_pkg.sv mlu_sv/mlu.sv msu_sv/rtl/msu_pkg.sv msu_sv/rtl/msu.sv} {
    read_verilog -sv [file join $repo $f]
}
read_verilog -sv [file join $trial outer_product_core.sv]
read_verilog -sv [file join $trial sparse_tensor_core_top.sv]
set fd [open clock.xdc w]
puts $fd {create_clock -period 10.000 -name clk [get_ports clk]}
close $fd
read_xdc clock.xdc
synth_design -top sparse_tensor_core_top -part xc7z020clg484-1 -mode out_of_context
report_utilization -file utilization_synth.rpt
write_checkpoint synthesized.dcp
set_param general.maxThreads 2
opt_design
place_design
phys_opt_design -directive Default
route_design
write_checkpoint routed.dcp
report_utilization -file utilization_routed.rpt
report_utilization -hierarchical -file hierarchy.rpt
report_route_status -file route_status.rpt
report_drc -file drc.rpt
report_timing_summary -report_unconstrained -max_paths 10 -file timing_summary.rpt
report_timing -delay_type max -max_paths 10 -input_pins -file critical_paths.rpt
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "OUTER_ROUTE_COMPLETE period_ns=10.000 setup_ns=$setup hold_ns=$hold"
