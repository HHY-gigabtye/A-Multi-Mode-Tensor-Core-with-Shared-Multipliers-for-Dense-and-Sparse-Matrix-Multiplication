# Adapt the physical-only replication selection to measured candidate nets.
# Usage: REFINED_ROUTE_DCP HIGH_FANOUT_REPORT NEW_OUTPUT_DIR
if {$argc != 3} {error "Expected REFINED_ROUTE_DCP HIGH_FANOUT_REPORT NEW_OUTPUT_DIR"}
set measured_repo [file normalize [file join [file dirname [info script]] ../..]]
set measured_input [file normalize [lindex $argv 0]]
set measured_report [file normalize [lindex $argv 1]]
set measured_output [file normalize [lindex $argv 2]]
if {[file exists $measured_output]} {error "Preserve previous measured trial"}
file mkdir $measured_output
cd $measured_output
set_param general.maxThreads 4
open_checkpoint $measured_input
if {[llength [get_clocks]] != 1 || abs([get_property PERIOD [get_clocks clk]] - 10.0) > 0.000001} {
    error "Expected original 10.000 ns clock"
}
set fd [open $measured_report r]
set measured_lines [split [read $fd] \n]
close $fd
set measured_drivers {}
set fd [open selection.tsv w]
puts $fd "net\tfanout\tworst_slack_ns\tdriver"
foreach line $measured_lines {
    set cols [split $line |]
    if {[llength $cols] < 7} {continue}
    set netname [string trim [lindex $cols 1]]
    set fanout [string trim [lindex $cols 2]]
    set type [string trim [lindex $cols 3]]
    set slack [string trim [lindex $cols 4]]
    if {![string is integer -strict $fanout] || ![string match LUT* $type] ||
        ![string is double -strict $slack] || $slack > -0.500 || $fanout < 128} {continue}
    set net [get_nets -hierarchical -filter [format {NAME == "%s"} $netname]]
    if {[llength $net] != 1} {error "Expected measured net: $netname"}
    set segments [get_nets -segments $net]
    set pins [get_pins -leaf -of_objects $segments -filter {DIRECTION == OUT}]
    set driver [get_cells -of_objects $pins -filter {REF_NAME =~ LUT*}]
    if {[llength $driver] != 1} {error "Expected one LUT driver for $netname: $driver"}
    set name [get_property NAME $driver]
    lappend measured_drivers $name
    puts $fd "$netname\t$fanout\t$slack\t$name"
}
# The final LUT on the measured worst CEP path has only ten sinks, but its
# routed segment contributes 1.415 ns. Include this inspected driver too.
set cep_name {u_bridge/g_arithmetic_row[1].g_arithmetic_column[6].product_q_reg_i_1}
set cep [get_cells -hierarchical -filter [format {NAME == "%s"} $cep_name]]
if {[llength $cep] != 1 || ![string match LUT* [get_property REF_NAME $cep]]} {
    error "Missing inspected CEP driver"
}
lappend measured_drivers $cep_name
puts $fd "inspected_worst_CEP_path\t10\t-1.422\t$cep_name"
close $fd
set measured_drivers [lsort -unique $measured_drivers]
if {[llength $measured_drivers] == 0} {error "No measured drivers selected"}
set measured_names [file join $measured_output measured_drivers.txt]
set fd [open $measured_names w]
puts $fd [join $measured_drivers \n]
close $fd
puts "MEASURED_SELECTION_COMPLETE drivers=[llength $measured_drivers]"
close_project
set argv [list $measured_input [file join $measured_output replicated] $measured_names]
set argc 3
source [file join $measured_repo experiments msu_fmax target_11ns_20261109 replicate_drivers.tcl]
close_project
set argv [list [file join $measured_output replicated routed.dcp] [file join $measured_output closure] 10.000]
set argc 3
source [file join $measured_repo experiments clock_control refine_route.tcl]
close_project
set argv [list [file join $measured_output closure routed.dcp] [file join $measured_output margin_9p75] 9.750]
set argc 3
source [file join $measured_repo experiments msu_fmax margin_10ns_20261113 guardband_refine.tcl]
close_project
set argv [list [file join $measured_output margin_9p75 timing_closed.dcp] [file join $measured_output final_10ns]]
set argc 2
source [file join $measured_repo experiments msu_fmax target_10ns_20261112 validate_10ns.tcl]
report_utilization -hierarchical -file hierarchy.rpt
puts "MLU_MEASURED_IMPLEMENTATION_COMPLETE setup=$task_setup hold=$task_hold"
