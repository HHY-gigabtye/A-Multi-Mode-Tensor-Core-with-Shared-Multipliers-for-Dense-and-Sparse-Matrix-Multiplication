# Physical-only follow-up to a completed, measured 36-BRAM checkpoint.
if {$argc != 2} {error "Expected ROUTED_DCP NEW_OUTPUT_ROOT"}
set target_scripts [file normalize [file dirname [info script]]]
set target_repo [file normalize [file join $target_scripts ../..]]
set target_input [file normalize [lindex $argv 0]]
set target_output [file normalize [lindex $argv 1]]
if {[file exists $target_output]} {error "Preserve previous targeted flow"}
file mkdir $target_output
set_param general.maxThreads 4
open_checkpoint $target_input
set target_best_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set target_best $target_input
close_project
set argv [list $target_input [file join $target_output measured]]
set argc 2
source [file join $target_scripts replicate_measured.tcl]
set target_candidate [file join $target_output measured replicated routed.dcp]
set target_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set target_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fd [open [file join $target_output timing_trials.csv] w]
puts $fd "trial,wns_ns,whs_ns,checkpoint"
puts $fd "targeted,$target_setup,$target_hold,$target_candidate"
close $fd
if {$target_setup > $target_best_setup} {set target_best $target_candidate}
if {$target_setup < 0 || $target_hold < 0} {
    close_project
    set argv [list $target_best [file join $target_output refined] 10.000]
    set argc 3
    source [file join $target_repo experiments clock_control refine_route.tcl]
    set target_candidate [file join $target_output refined routed.dcp]
    set target_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set target_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    set fd [open [file join $target_output timing_trials.csv] a]
    puts $fd "refined,$target_setup,$target_hold,$target_candidate"
    close $fd
}
if {$target_setup >= 0 && $target_hold >= 0} {
    close_project
    set argv [list $target_candidate [file join $target_output final_audit] 36]
    set argc 3
    source [file join $target_scripts final_gate.tcl]
    puts "TARGETED_FLOW_100MHZ_PASS checkpoint=$target_candidate"
} else {
    set fd [open [file join $target_output INCOMPLETE.txt] w]
    puts $fd "100 MHz NOT closed: WNS=$target_setup WHS=$target_hold"
    close $fd
    puts "TARGETED_FLOW_INCOMPLETE setup=$target_setup hold=$target_hold"
}
