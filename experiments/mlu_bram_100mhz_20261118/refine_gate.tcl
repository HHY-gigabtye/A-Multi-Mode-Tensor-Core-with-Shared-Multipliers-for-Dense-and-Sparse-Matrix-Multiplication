# Refine a completed route at the unchanged 10 ns constraint. Preserve the
# post-physopt checkpoint, and avoid disturbing it if it already fully passes.
if {$argc != 3} {error "Expected ROUTED_DCP NEW_OUTPUT_DIR BRAM_COUNT"}
set refine_scripts [file normalize [file dirname [info script]]]
set refine_input [file normalize [lindex $argv 0]]
set refine_output [file normalize [lindex $argv 1]]
set refine_brams [lindex $argv 2]
if {$refine_brams ni {18 36}} {error "Unsupported BRAM count"}
if {[file exists $refine_output]} {error "Preserve previous refinement"}
file mkdir $refine_output
cd $refine_output
set_param general.maxThreads 2
open_checkpoint $refine_input
if {[llength [get_clocks]] != 1 || abs([get_property PERIOD [get_clocks clk]] - 10.0) > 0.000001} {
    error "Expected original single 10.000 ns clock"
}
phys_opt_design -directive AggressiveExplore
write_checkpoint physopt.dcp
report_timing_summary -max_paths 10 -file timing_physopt.rpt
report_route_status -file route_status_physopt.rpt
set refine_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set refine_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fd [open route_status_physopt.rpt r]
set refine_status [read $fd]
close $fd
set refine_complete 0
if {[regexp {# of routable nets\.+\s*:\s*(\d+)} $refine_status all total] &&
    [regexp {# of fully routed nets\.+\s*:\s*(\d+)} $refine_status all routed] &&
    [regexp {# of nets with routing errors\.+\s*:\s*(\d+)} $refine_status all errors]} {
    set refine_complete [expr {$total == $routed && $errors == 0}]
}
set fd [open physical_stage.txt w]
puts $fd "setup_ns=$refine_setup hold_ns=$refine_hold fully_routed=$refine_complete"
close $fd
if {!($refine_complete && $refine_setup >= 0.0 && $refine_hold >= 0.0)} {
    route_design -directive Explore
}
write_checkpoint routed.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 100 -input_pins -file critical_paths.rpt
report_high_fanout_nets -max_nets 100 -timing -load_types -file high_fanout.rpt
report_utilization -file utilization_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc_routed.rpt
set refine_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set refine_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "REFINEMENT_COMPLETE setup=$refine_setup hold=$refine_hold"
if {$refine_setup >= 0.0 && $refine_hold >= 0.0} {
    close_project
    set argv [list [file join $refine_output routed.dcp] [file join $refine_output final_audit] $refine_brams]
    set argc 3
    source [file join $refine_scripts final_gate.tcl]
} else {
    set fd [open INCOMPLETE.txt w]
    puts $fd "100 MHz timing NOT closed. setup_ns=$refine_setup hold_ns=$refine_hold"
    close $fd
}
