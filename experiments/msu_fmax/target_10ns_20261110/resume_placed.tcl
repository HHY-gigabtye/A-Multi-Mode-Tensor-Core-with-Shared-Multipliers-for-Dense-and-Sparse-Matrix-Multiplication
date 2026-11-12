# Resume an interrupted implementation without repeating synthesis/placement.
# Arguments: PLACED_DCP NEW_OUTPUT_DIR
if {$argc != 2} {error "Expected PLACED_DCP NEW_OUTPUT_DIR"}
set task_root [file normalize [file join [file dirname [info script]] ../../..]]
set task_input [file normalize [lindex $argv 0]]
set task_output [file normalize [lindex $argv 1]]
if {![file isfile $task_input]} {error "Missing placed checkpoint"}
if {[file exists $task_output]} {error "Use a new output directory"}
file mkdir [file join $task_output default]
cd [file join $task_output default]
set_param general.maxThreads 4
open_checkpoint $task_input
set task_period [get_property PERIOD [get_clocks clk]]
if {abs($task_period - 10.0) > 0.000001} {error "Expected preserved 10 ns clock"}
report_clocks -file clocks.rpt
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
set argv [list [file join $task_output default routed.dcp] [file join $task_output refined] $task_period]
source [file join $task_root experiments clock_control refine_route.tcl]
puts "RESUME_PLACED_COMPLETE input=$task_input output=$task_output"
