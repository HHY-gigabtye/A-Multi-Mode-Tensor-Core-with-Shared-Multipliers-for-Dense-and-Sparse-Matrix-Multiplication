# Refine an already routed design without disturbing its routes in a new
# route_design pass. Preserve each complete result and stop on no improvement.
if {$argc != 2} {error "Expected ROUTED_DCP NEW_OUTPUT_DIR"}
set ro_scripts [file normalize [file dirname [info script]]]
set ro_input [file normalize [lindex $argv 0]]
set ro_output [file normalize [lindex $argv 1]]
if {[file exists $ro_output]} {error "Preserve previous refinement"}
file mkdir $ro_output
set_param general.maxThreads 2
open_checkpoint $ro_input
if {[llength [get_clocks]] != 1 || abs([get_property PERIOD [get_clocks clk]] - 10.0) > 0.000001} {
    error "Expected original single 10.000 ns clock"
}
set ro_previous [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set fd [open [file join $ro_output stages.csv] w]
puts $fd "stage,setup_ns,hold_ns,complete"
close $fd
foreach ro_stage {1 2 3} {
    set ro_stage_dir [file join $ro_output stage$ro_stage]
    file mkdir $ro_stage_dir
    cd $ro_stage_dir
    phys_opt_design -directive AggressiveExplore
    write_checkpoint routed.dcp
    report_route_status -file route_status.rpt
    report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
    report_timing -max_paths 100 -input_pins -file critical_paths.rpt
    report_utilization -file utilization_routed.rpt
    report_drc -file drc_routed.rpt
    set ro_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set ro_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    set fd [open route_status.rpt r]
    set ro_status [read $fd]
    close $fd
    set ro_complete 0
    if {[regexp {# of routable nets\.+\s*:\s*(\d+)} $ro_status all total] &&
        [regexp {# of fully routed nets\.+\s*:\s*(\d+)} $ro_status all routed] &&
        [regexp {# of nets with routing errors\.+\s*:\s*(\d+)} $ro_status all errors]} {
        set ro_complete [expr {$total == $routed && $errors == 0}]
    }
    set fd [open [file join $ro_output stages.csv] a]
    puts $fd "$ro_stage,$ro_setup,$ro_hold,$ro_complete"
    close $fd
    puts "ROUTED_REFINEMENT stage=$ro_stage setup=$ro_setup hold=$ro_hold complete=$ro_complete"
    if {!$ro_complete} {error "Physical optimization left incomplete routing; do not accept this stage"}
    if {$ro_setup >= 0.0 && $ro_hold >= 0.0} {
        close_project
        set argv [list [file join $ro_stage_dir routed.dcp] [file join $ro_stage_dir final_audit] 18]
        set argc 3
        source [file join $ro_scripts final_gate.tcl]
        break
    }
    if {$ro_setup <= $ro_previous + 0.001} {
        puts "STOP_NO_SETUP_IMPROVEMENT previous=$ro_previous current=$ro_setup"
        break
    }
    set ro_previous $ro_setup
}
