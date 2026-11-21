# Unit-level actual-netlist proof precedes full implementation.
if {$argc != 2} {error "Expected SOURCE_SNAPSHOT NEW_OUTPUT_ROOT"}
set rf_scripts [file normalize [file dirname [info script]]]
set rf_source [file normalize [lindex $argv 0]]
set rf_output [file normalize [lindex $argv 1]]
set rf_proof [file join [file dirname $rf_source] bridge_netlist]
if {[file exists $rf_proof] || [file exists $rf_output]} {error "Preserve previous trial outputs"}
set argv [list $rf_source $rf_proof]
set argc 2
source [file join $rf_scripts bridge_netlist_check.tcl]
close_project
set argv [list $rf_source $rf_output]
set argc 2
source [file join $rf_scripts prefetch_candidate_flow.tcl]
