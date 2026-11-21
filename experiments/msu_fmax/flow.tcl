# Fresh, paired implementation followed by the existing selected refinement.
# Arguments: IMMUTABLE_SOURCE_DIR NEW_OUTPUT_DIR PERIOD_NS
set task_root [file normalize [file join [file dirname [info script]] ../..]]
set task_source [file normalize [lindex $argv 0]]
set task_out [file normalize [lindex $argv 1]]
set task_period [lindex $argv 2]
if {[file exists $task_out]} { error "Output directory already exists: $task_out" }
set argv [list $task_source [file join $task_out default] $task_period Default]
source [file join $task_root experiments clock_control implement.tcl]
close_project
set argv [list [file join $task_out default routed.dcp] [file join $task_out refined] $task_period]
source [file join $task_root experiments clock_control refine_route.tcl]
puts "MSU_FMAX_FLOW_COMPLETE period=$task_period output=$task_out"
