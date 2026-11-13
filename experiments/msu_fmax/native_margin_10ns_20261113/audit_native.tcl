# Independently reopen a fresh native run and its routed checkpoint.
# Arguments: IMPLEMENTATION_RUN NEW_AUDIT_DIRECTORY
if {$argc != 2} {error "Expected IMPLEMENTATION_RUN NEW_AUDIT_DIRECTORY"}
set native_repo [file normalize [file join [file dirname [info script]] ../../..]]
set native_run_name [lindex $argv 0]
set native_output [file normalize [lindex $argv 1]]
if {[file exists $native_output]} {error "Use a new audit directory"}
file mkdir $native_output
set_param general.maxThreads 4
open_project [file join $native_repo project_integration project_integration.xpr]
set native_run [get_runs $native_run_name]
set native_fd [open [file join $native_output run_properties.txt] w]
puts $native_fd "Current synthesis: [current_run -synthesis]"
puts $native_fd "Current implementation: [current_run -implementation]"
foreach native_property [list_property $native_run] {
    puts $native_fd "$native_property: [get_property $native_property $native_run]"
}
close $native_fd
if {[get_property STATUS $native_run] ne "route_design Complete!"} {error "Native run is incomplete"}
if {[get_property NEEDS_REFRESH $native_run]} {error "Native run is stale"}
if {[current_run -implementation] ne $native_run_name} {error "Unexpected current implementation"}
foreach native_stat {STATS.WNS STATS.WHS STATS.TNS STATS.THS} {
    set native_value [get_property $native_stat $native_run]
    if {![string is double -strict $native_value] || $native_value < 0} {error "Failed native timing: $native_stat=$native_value"}
    puts "NATIVE_STAT_PASS $native_stat=$native_value"
}
set native_dcp [file join [get_property DIRECTORY $native_run] sparse_tensor_core_top_routed.dcp]
open_run $native_run_name
if {[llength [get_clocks]] != 1 || abs([get_property PERIOD [get_clocks clk]] - 10.000) > 0.000001} {error "Expected one 10.000 ns clock"}
report_timing_summary -max_paths 20 -file [file join $native_output open_run_timing.rpt]
close_project
set argv [list $native_dcp [file join $native_output checkpoint]]
set argc 2
source [file join $native_repo experiments msu_fmax target_10ns_20261110 audit.tcl]
set native_fd [open [file join $native_output result.txt] w]
puts $native_fd "PASS: native project run and routed checkpoint independently reopened."
puts $native_fd "Run: $native_run_name"
puts $native_fd "Checkpoint: $native_dcp"
close $native_fd
puts "NATIVE_10NS_INDEPENDENT_AUDIT_COMPLETE"
