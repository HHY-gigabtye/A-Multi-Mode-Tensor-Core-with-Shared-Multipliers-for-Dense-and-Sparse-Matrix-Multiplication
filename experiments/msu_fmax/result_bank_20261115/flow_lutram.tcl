# Same synthesis/default implementation/refinement as ../flow.tcl, with a
# post-synthesis LUTRAM mapping check before spending time on implementation.
# Arguments: IMMUTABLE_SOURCE_DIR NEW_OUTPUT_DIR PERIOD_NS
if {$argc != 3} {error "Expected IMMUTABLE_SOURCE_DIR NEW_OUTPUT_DIR PERIOD_NS"}
set ram_flow_root [file normalize [file join [file dirname [info script]] ../../..]]
set ram_flow_source [file normalize [lindex $argv 0]]
set ram_flow_output [file normalize [lindex $argv 1]]
set ram_flow_period [lindex $argv 2]
if {[file exists $ram_flow_output]} {error "Use a new output directory"}
file mkdir [file join $ram_flow_output default]
cd [file join $ram_flow_output default]
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
} {read_verilog -sv [file join $ram_flow_source $src]}
set ram_flow_fd [open clock.xdc w]
puts $ram_flow_fd "create_clock -period $ram_flow_period -name clk \[get_ports clk\]"
close $ram_flow_fd
read_xdc clock.xdc
synth_design -top sparse_tensor_core_top -part xc7z020clg484-1 -mode out_of_context
write_checkpoint synthesized.dcp
report_utilization -file utilization_synth.rpt
report_timing_summary -max_paths 10 -file timing_synth.rpt
set ram_flow_cells [get_cells -hierarchical -filter {NAME =~ u_tensor_core/* && (REF_NAME =~ RAM32* || REF_NAME =~ RAM64*)}]
set ram_flow_fd [open memory_mapping.txt w]
puts $ram_flow_fd "TC distributed-memory cells: [llength $ram_flow_cells]"
foreach ram_flow_cell $ram_flow_cells {
    puts $ram_flow_fd "[get_property NAME $ram_flow_cell]\t[get_property REF_NAME $ram_flow_cell]"
}
close $ram_flow_fd
if {[llength $ram_flow_cells] == 0} {error "TC result storage was not mapped to LUTRAM"}
puts "RESULT_LUTRAM_MAPPING_PASS count=[llength $ram_flow_cells]"
opt_design
place_design
write_checkpoint placed.dcp
report_utilization -file utilization_placed.rpt
phys_opt_design -directive Default
route_design
write_checkpoint routed.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 50 -input_pins -file critical_paths.rpt
report_high_fanout_nets -max_nets 30 -timing -load_types -file high_fanout.rpt
report_utilization -file utilization_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc_routed.rpt
close_project
set argv [list [file join $ram_flow_output default routed.dcp] [file join $ram_flow_output refined] $ram_flow_period]
set argc 3
source [file join $ram_flow_root experiments clock_control refine_route.tcl]
puts "RESULT_LUTRAM_FLOW_COMPLETE period=$ram_flow_period output=$ram_flow_output"
