# Resume the GUI post-route hook from a preserved checkpoint without changing runs.
# Arguments: ROUTED_DCP NEW_OUTPUT_DIR ?refined?
# Use 'refined' only after AggressiveExplore phys_opt and Explore route completed.
if {$argc < 2 || $argc > 3} {error "Usage: resume_post_route.tcl ROUTED_DCP NEW_OUTPUT_DIR ?refined?"}
set task_post_route_refined 0
if {$argc == 3} {
    if {[lindex $argv 2] ne "refined"} {error "Expected optional phase: refined"}
    set task_post_route_refined 1
}
set task_resume_root [file normalize [file join [file dirname [info script]] ..]]
set task_resume_input [file normalize [lindex $argv 0]]
set task_resume_output [file normalize [lindex $argv 1]]
set task_resume_hook [file join $task_resume_root project_integration scripts post_route_opt.tcl.txt]
if {![file isfile $task_resume_input]} {error "Missing checkpoint: $task_resume_input"}
if {[file exists $task_resume_output]} {error "Use a new output directory: $task_resume_output"}
file mkdir $task_resume_output
cd $task_resume_output
file copy $task_resume_hook post_route_opt.used.tcl.txt
file copy [file join [file dirname $task_resume_hook] replicate_11ns_controls.tcl] replicate_11ns_controls.tcl
set_param general.maxThreads 4
open_checkpoint $task_resume_input
# Match the GUI project's message policy outside the PRE/POST hook.
set_msg_config -id {[Route 35-39]} -new_severity WARNING
report_clocks -file clocks.rpt
report_timing_summary -max_paths 20 -report_unconstrained -file timing_before.rpt
set task_resume_status [catch {source post_route_opt.used.tcl.txt} task_resume_message]
report_timing -max_paths 20 -input_pins -file critical_paths.rpt
if {$task_resume_status} {
    puts stderr "POST_ROUTE_RECOVERY_FAILED: $task_resume_message"
    exit 1
}
puts "POST_ROUTE_RECOVERY_PASS input=$task_resume_input output=$task_resume_output"
exit 0
