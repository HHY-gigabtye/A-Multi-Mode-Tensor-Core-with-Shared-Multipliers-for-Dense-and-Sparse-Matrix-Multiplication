# Comparable OOC runs: source snapshot, output directory, period, phys directive.
set source_root [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
set period [lindex $argv 2]
set directive [lindex $argv 3]
if {$directive eq ""} {set directive Default}
if {[file exists [file join $output_dir routed.dcp]]} {error "Use a new output directory"}
file mkdir $output_dir
cd $output_dir
set_param general.maxThreads 4
create_project -in_memory -part xc7z020clg484-1
set_property target_language Verilog [current_project]
foreach src {
  tensor_core_sv/tensor_core_pkg.sv
  fifo_sv/du_tc_bridge_pkg.sv
  fifo_sv/du_tc_bridge.sv
  du_tia_sv/rtl/du_tia_pkg.sv
  du_tia_sv/rtl/du_tia.sv
  mlu_sv/mlu_pkg.sv
  mlu_sv/mlu.sv
  msu_sv/rtl/msu_pkg.sv
  msu_sv/rtl/msu.sv
  tensor_core_sv/tensor_core.sv
  integration_sv/rtl/sparse_tensor_core_top.sv
} {read_verilog -sv [file join $source_root $src]}
set clock_file [open clock.xdc w]
puts $clock_file "create_clock -period $period -name clk \[get_ports clk\]"
close $clock_file
read_xdc clock.xdc
synth_design -top sparse_tensor_core_top -part xc7z020clg484-1 -mode out_of_context
write_checkpoint synthesized.dcp
report_utilization -file utilization_synth.rpt
report_timing_summary -max_paths 10 -file timing_synth.rpt
opt_design
place_design
write_checkpoint placed.dcp
report_utilization -file utilization_placed.rpt
phys_opt_design -directive $directive
route_design
write_checkpoint routed.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 50 -input_pins -file critical_paths.rpt
report_high_fanout_nets -max_nets 30 -timing -load_types -file high_fanout.rpt
report_utilization -file utilization_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc_routed.rpt
puts "CLOCK_FLOW_COMPLETE source=$source_root period=$period phys=$directive"
