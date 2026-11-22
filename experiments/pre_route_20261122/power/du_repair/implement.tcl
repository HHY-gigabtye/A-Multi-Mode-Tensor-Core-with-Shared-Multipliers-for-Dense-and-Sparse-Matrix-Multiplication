# Identical integrated OOC flow for the baseline and the operand-route trial.
# vivado -mode batch -source implement.tcl -tclargs baseline|candidate NEW_OUTPUT
if {$argc != 2} {error "Expected VARIANT NEW_OUTPUT_DIRECTORY"}
set trial [file normalize [file dirname [info script]]]
set variant [lindex $argv 0]
if {$variant ni {baseline candidate candidate_v2}} {error "Unknown variant: $variant"}
set root [file join $trial $variant src]
set out [file normalize [lindex $argv 1]]
if {[file exists $out]} {error "Choose a new output directory: $out"}
file mkdir $out
cd $out
set_param general.maxThreads 1
create_project -in_memory -part xc7z020clg484-1
set_property target_language Verilog [current_project]
foreach source {
  tensor_core_sv/tensor_core_pkg.sv fifo_sv/du_tc_bridge_pkg.sv
  fifo_sv/du_tc_bridge.sv du_tia_sv/rtl/du_tia_pkg.sv du_tia_sv/rtl/du_tia.sv
  mlu_sv/mlu_pkg.sv mlu_sv/mlu.sv msu_sv/rtl/msu_pkg.sv msu_sv/rtl/msu.sv
  tensor_core_sv/outer_product_core.sv integration_sv/rtl/sparse_tensor_core_top.sv
} {read_verilog -sv [file join $root $source]}
set fd [open clock.xdc w]
puts $fd {create_clock -period 10.000 -name clk [get_ports clk]}
close $fd
read_xdc clock.xdc
synth_design -top sparse_tensor_core_top -part xc7z020clg484-1 -mode out_of_context
report_utilization -file utilization_synth.rpt
report_utilization -hierarchical -file hierarchy_synth.rpt
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
report_clocks -file clocks.rpt
report_timing_summary -report_unconstrained -max_paths 10 -file timing_summary.rpt
report_timing -delay_type max -max_paths 100 -input_pins -file critical_paths.rpt
report_high_fanout_nets -max_nets 30 -file high_fanout.rpt
foreach pair {{u_mlu mlu} {u_du_tia du_tia} {u_bridge bridge} {u_tensor_core tc} {u_msu msu}} {
  lassign $pair instance label
  report_timing -to [get_cells -hier -filter "NAME =~ $instance/* && IS_SEQUENTIAL"] -max_paths 5 -file ${label}_paths.rpt
}
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fd [open metrics.csv w]
puts $fd "variant,period_ns,setup_slack_ns,hold_slack_ns"
puts $fd "$variant,10.000,$setup,$hold"
close $fd
puts "PRE_ROUTE_IMPLEMENTATION_COMPLETE variant=$variant setup_ns=$setup hold_ns=$hold"
write_verilog -mode funcsim routed_functional.v
