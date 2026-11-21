# Re-open the selected route, independently check STA, and audit the bottleneck.
# Arguments: ROUTED_DCP NEW_OUTPUT_DIR PERIOD_NS
set repo_root [file normalize [file join [file dirname [info script]] ../..]]
source [file join $repo_root experiments fmax check_clock.tcl]
report_timing -max_paths 50 -input_pins -file critical_paths.rpt
report_utilization -hierarchical -file utilization_hierarchical.rpt
report_high_fanout_nets -max_nets 30 -timing -load_types -file high_fanout.rpt
set fifo_sources [get_cells -hierarchical -filter {NAME =~ *u_bridge/q_reg*count*}]
set result_destinations [get_cells -hierarchical -filter {NAME =~ *u_tensor_core/ctrl_q_reg*result*}]
if {[llength $fifo_sources] == 0 || [llength $result_destinations] == 0} {
    error "Bridge/result path endpoints not found"
}
report_timing -from $fifo_sources -to $result_destinations -max_paths 5 -input_pins -file bridge_to_result.rpt
puts "CLOCK_CONTROL_INSPECTION_COMPLETE"
