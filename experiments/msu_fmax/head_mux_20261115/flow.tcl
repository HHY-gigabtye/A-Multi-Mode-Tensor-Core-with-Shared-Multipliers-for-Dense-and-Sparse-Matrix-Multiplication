# Fresh OOC implementation with the same default/refinement phases as ../flow.tcl.
# Check the intended head-to-DSP mapping before placement and routing.
# Arguments: IMMUTABLE_SOURCE_DIR NEW_OUTPUT_DIR PERIOD_NS ?SYNTH_GUARD_TCL?
if {$argc != 3 && $argc != 4} {error "Expected IMMUTABLE_SOURCE_DIR NEW_OUTPUT_DIR PERIOD_NS ?SYNTH_GUARD_TCL?"}
set head_flow_root [file normalize [file join [file dirname [info script]] ../../..]]
set head_flow_source [file normalize [lindex $argv 0]]
set head_flow_output [file normalize [lindex $argv 1]]
set head_flow_period [lindex $argv 2]
set head_flow_guard {}
if {$argc == 4} {set head_flow_guard [file normalize [lindex $argv 3]]}
if {[file exists $head_flow_output]} {error "Use a new output directory"}
file mkdir [file join $head_flow_output default]
cd [file join $head_flow_output default]
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
} {read_verilog -sv [file join $head_flow_source $src]}
set head_flow_fd [open clock.xdc w]
puts $head_flow_fd "create_clock -period $head_flow_period -name clk \[get_ports clk\]"
close $head_flow_fd
read_xdc clock.xdc
synth_design -top sparse_tensor_core_top -part xc7z020clg484-1 -mode out_of_context
write_checkpoint synthesized.dcp
report_utilization -file utilization_synth.rpt
report_timing_summary -max_paths 10 -file timing_synth.rpt
set head_flow_starts [get_cells -hierarchical -filter {IS_SEQUENTIAL == 1 && NAME =~ u_bridge/head_select_q_reg*}]
set head_flow_dsps [get_cells -hierarchical -filter {REF_NAME == DSP48E1 && NAME =~ u_tensor_core/g_arithmetic*product_q_reg*}]
set head_flow_inputs [get_pins -of_objects $head_flow_dsps -filter {DIRECTION == IN && (REF_PIN_NAME =~ A* || REF_PIN_NAME =~ B*)}]
if {[llength $head_flow_starts] == 0 || [llength $head_flow_inputs] == 0} {
    error "Missing head selector or sparse DSP input endpoints"
}
report_timing -from $head_flow_starts -to $head_flow_inputs -max_paths 40 -input_pins -file head_to_dsp_synth.rpt
set head_flow_paths [get_timing_paths -from $head_flow_starts -to $head_flow_inputs -max_paths 40 -nworst 1]
if {[llength $head_flow_paths] == 0} {error "No head-to-DSP timing paths found"}
set head_flow_fd [open mapping.txt w]
set head_flow_max_levels 0
foreach head_flow_path $head_flow_paths {
    if {[lsearch -exact [list_property $head_flow_path] LOGIC_LEVELS] < 0} {
        error "Cannot inspect head-path logic levels; inspect head_to_dsp_synth.rpt"
    }
    set head_flow_levels [get_property LOGIC_LEVELS $head_flow_path]
    puts $head_flow_fd "levels=$head_flow_levels endpoint=[get_property ENDPOINT_PIN $head_flow_path]"
    if {$head_flow_levels > $head_flow_max_levels} {set head_flow_max_levels $head_flow_levels}
}
puts $head_flow_fd "Maximum logic levels across [llength $head_flow_paths] reported paths: $head_flow_max_levels"
close $head_flow_fd
if {$head_flow_max_levels > 2} {error "Paired head mux did not achieve the intended two-level mapping"}
puts "HEAD_MUX_MAPPING_PASS max_levels=$head_flow_max_levels"
if {$head_flow_guard ne ""} {source $head_flow_guard}
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
set argv [list [file join $head_flow_output default routed.dcp] [file join $head_flow_output refined] $head_flow_period]
set argc 3
source [file join $head_flow_root experiments clock_control refine_route.tcl]
puts "HEAD_MUX_FLOW_COMPLETE period=$head_flow_period output=$head_flow_output"
