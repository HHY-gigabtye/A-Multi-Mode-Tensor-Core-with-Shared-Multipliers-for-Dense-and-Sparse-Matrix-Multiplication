# Independent verification of the native run and its final routed checkpoint.
# Arguments: NEW_AUDIT_DIRECTORY
if {$argc != 1} {error "Expected NEW_AUDIT_DIRECTORY"}
set task_audit_repo [file normalize [file join [file dirname [info script]] ../../..]]
set task_audit_output [file normalize [lindex $argv 0]]
if {[file exists $task_audit_output]} {error "Use a new audit directory"}
file mkdir $task_audit_output
set_param general.maxThreads 4
open_project [file join $task_audit_repo project_integration project_integration.xpr]
set task_audit_run [get_runs impl_10ns]
set task_audit_fd [open [file join $task_audit_output run_properties.txt] w]
foreach task_audit_property [list_property $task_audit_run] {
    puts $task_audit_fd "$task_audit_property: [get_property $task_audit_property $task_audit_run]"
}
close $task_audit_fd
if {[get_property STATUS $task_audit_run] ne "route_design Complete!"} {error "Native implementation is not complete"}
foreach task_audit_stat {STATS.WNS STATS.WHS STATS.TNS STATS.THS} {
    if {[lsearch -exact [list_property $task_audit_run] $task_audit_stat] < 0} {error "Missing GUI statistic: $task_audit_stat"}
    set task_audit_value [get_property $task_audit_stat $task_audit_run]
    if {![string is double -strict $task_audit_value] || $task_audit_value < 0} {error "GUI run timing failed: $task_audit_stat=$task_audit_value"}
    puts "GUI_STAT_PASS $task_audit_stat=$task_audit_value"
}
open_run impl_10ns
if {abs([get_property PERIOD [get_clocks clk]] - 10.000) > 0.000001} {error "Wrong clock in reopened implementation"}
report_timing_summary -max_paths 20 -file [file join $task_audit_output open_run_timing.rpt]
close_project
set argv [list [file join $task_audit_repo project_integration project_integration.runs impl_10ns sparse_tensor_core_top_routed.dcp] [file join $task_audit_output checkpoint]]
set argc 2
source [file join $task_audit_repo experiments msu_fmax target_10ns_20261110 audit.tcl]
puts "GUI_10NS_INDEPENDENT_AUDIT_COMPLETE"
