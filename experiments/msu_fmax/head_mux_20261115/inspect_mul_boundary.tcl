# Read-only inspection of the existing sparse MUL-to-ROUTE timing boundary.
# Arguments: BASELINE_ROUTED_DCP NEW_OUTPUT_DIR
if {$argc != 2} {error "Expected BASELINE_ROUTED_DCP NEW_OUTPUT_DIR"}
set mul_probe_input [file normalize [lindex $argv 0]]
set mul_probe_output [file normalize [lindex $argv 1]]
if {[file exists $mul_probe_output]} {error "Use a new output directory"}
file mkdir $mul_probe_output
cd $mul_probe_output
set_param general.maxThreads 2
open_checkpoint $mul_probe_input
report_clocks -file clocks.rpt
set mul_probe_dsps [get_cells -hierarchical -filter {REF_NAME == DSP48E1 && NAME =~ u_tensor_core/g_arithmetic*product_q_reg*}]
set mul_probe_destinations {}
foreach mul_probe_cell [get_cells -hierarchical -filter {IS_SEQUENTIAL == 1 && NAME =~ u_tensor_core/sparse_storage_q_reg*}] {
    if {[string first {[route][delta]} [get_property NAME $mul_probe_cell]] >= 0} {
        lappend mul_probe_destinations $mul_probe_cell
    }
}
if {[llength $mul_probe_dsps] != 64 || [llength $mul_probe_destinations] == 0} {
    error "Unexpected sparse DSP or ROUTE data endpoint selection"
}
set mul_probe_paths [get_timing_paths -from $mul_probe_dsps -to $mul_probe_destinations -max_paths 20 -nworst 1]
if {[llength $mul_probe_paths] == 0} {error "No registered MUL-to-ROUTE data paths found"}
report_timing -from $mul_probe_dsps -to $mul_probe_destinations -max_paths 20 -input_pins -file mul_to_route.rpt
set mul_probe_fd [open inspection.txt w]
puts $mul_probe_fd "Checkpoint: $mul_probe_input"
puts $mul_probe_fd "Unchanged clock period ns: [get_property PERIOD [get_clocks clk]]"
puts $mul_probe_fd "Sparse product DSP cells: [llength $mul_probe_dsps]"
puts $mul_probe_fd "ROUTE delta endpoint cells: [llength $mul_probe_destinations]"
puts $mul_probe_fd "Worst MUL-to-ROUTE slack ns: [get_property SLACK [lindex $mul_probe_paths 0]]"
puts $mul_probe_fd "Read-only inspection; no implementation or constraint changes."
close $mul_probe_fd
puts "MUL_BOUNDARY_INSPECTION_COMPLETE"
close_design
