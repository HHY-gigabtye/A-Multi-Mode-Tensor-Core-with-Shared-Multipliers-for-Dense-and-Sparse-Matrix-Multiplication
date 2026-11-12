# Project-level message policy; Vivado 2022.2 advises against set_msg_config
# inside PRE/POST hooks. No run is reset or launched by this script.
set task_root [file normalize [file join [file dirname [info script]] ..]]
set task_project [file join $task_root project_integration project_integration.xpr]
set task_hook [file join $task_root project_integration scripts post_route_opt.tcl.txt]
open_project $task_project
if {[file normalize [get_property STEPS.ROUTE_DESIGN.TCL.POST [get_runs impl_1]]] ne $task_hook} {
    error "Expected the project's final timing-check hook"
}
set task_fd [open $task_hook r]
set task_hook_text [read $task_fd]
close $task_fd
if {[string first {send_msg_id {TC 1-1} ERROR} $task_hook_text] < 0} {
    error "Refusing message policy without the explicit final timing ERROR gate"
}
# Exact ID, not a prefix match; retain the router message instead of suppressing it.
set_msg_config -id {[Route 35-39]} -new_severity WARNING
close_project
open_project $task_project
get_msg_config -rules
close_project
puts "TIMING_MESSAGE_POLICY_SAVED"
exit 0
