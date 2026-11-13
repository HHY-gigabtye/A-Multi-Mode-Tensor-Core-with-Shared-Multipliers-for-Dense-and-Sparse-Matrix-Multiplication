# Validate an already routed 10 ns checkpoint, without changing its clock.
# Arguments: ROUTED_DCP NEW_OUTPUT_DIR
if {$argc != 2} {error "Expected ROUTED_DCP NEW_OUTPUT_DIR"}
set task_validate_root [file normalize [file join [file dirname [info script]] ../../..]]
set task_validate_input [file normalize [lindex $argv 0]]
set task_validate_output [file normalize [lindex $argv 1]]
if {[file exists $task_validate_output]} {error "Use a new output directory"}
file mkdir $task_validate_output
cd $task_validate_output
set_param general.maxThreads 4
open_checkpoint $task_validate_input
set task_validate_clocks [get_clocks]
if {[llength $task_validate_clocks] != 1 ||
    [get_property NAME $task_validate_clocks] ne "clk" ||
    abs([get_property PERIOD $task_validate_clocks] - 10.0) > 0.000001} {
    error "Expected exactly one original 10.000 ns clock"
}
report_clocks -file clocks.rpt
# Apply the existing final setup/hold gate unchanged; do not reroute.
set task_post_route_refined 1
source [file join $task_validate_root project_integration scripts post_route_opt.tcl.txt]
report_timing -max_paths 50 -input_pins -file critical_paths.rpt
puts "VALIDATE_10NS_COMPLETE period=10.000 setup=$task_setup hold=$task_hold"
