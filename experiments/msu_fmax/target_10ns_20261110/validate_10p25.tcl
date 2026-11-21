# Validate a slower operating clock on the preserved best 10 ns physical route.
# This changes only the clock constraint, not RTL, placement, or routing.
# Arguments: ROUTED_10NS_DCP NEW_OUTPUT_DIR
if {$argc != 2} {error "Expected ROUTED_10NS_DCP NEW_OUTPUT_DIR"}
set task_validate_root [file normalize [file join [file dirname [info script]] ../../..]]
set task_validate_input [file normalize [lindex $argv 0]]
set task_validate_output [file normalize [lindex $argv 1]]
if {[file exists $task_validate_output]} {error "Use a new output directory"}
file mkdir $task_validate_output
cd $task_validate_output
set_param general.maxThreads 4
open_checkpoint $task_validate_input
set task_original_period [get_property PERIOD [get_clocks clk]]
if {abs($task_original_period - 10.0) > 0.000001} {error "Expected the original 10 ns clock"}
report_clocks -file clocks_original_10ns.rpt
report_timing_summary -max_paths 20 -report_unconstrained -file timing_original_10ns.rpt
create_clock -period 10.250 -name clk -waveform {0.000 5.125} [get_ports clk]
report_clocks -file clocks.rpt
# This DCP already completed the paired refinement and measured replication.
# Skip further physical changes and apply the same strict final setup/hold gate.
set task_post_route_refined 1
source [file join $task_validate_root project_integration scripts post_route_opt.tcl.txt]
report_timing -max_paths 50 -input_pins -file critical_paths.rpt
puts "VALIDATE_10P25_COMPLETE original_period=$task_original_period operating_period=10.250"
