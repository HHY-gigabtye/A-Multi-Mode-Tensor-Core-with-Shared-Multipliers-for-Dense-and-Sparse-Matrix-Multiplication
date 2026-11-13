# Re-place/re-route an immutable synthesized checkpoint at a tighter period.
# Arguments: SYNTHESIZED_DCP NEW_OUTPUT_DIR PERIOD_NS
set task_root [file normalize [file join [file dirname [info script]] ../..]]
set task_synth [file normalize [lindex $argv 0]]
set task_out [file normalize [lindex $argv 1]]
set task_period [lindex $argv 2]
if {[file exists $task_out]} { error "Output directory already exists: $task_out" }
set argv [list $task_synth [file join $task_out default] $task_period]
source [file join $task_root experiments fmax reimplement.tcl]
report_utilization -file utilization_routed.rpt
report_high_fanout_nets -max_nets 30 -timing -load_types -file high_fanout.rpt
close_project
set argv [list [file join $task_out default routed.dcp] [file join $task_out refined] $task_period]
source [file join $task_root experiments clock_control refine_route.tcl]
puts "MSU_FMAX_RETARGET_COMPLETE period=$task_period input=$task_synth"
