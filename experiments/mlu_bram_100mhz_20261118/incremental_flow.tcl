# Reuse the independently audited 10 ns baseline implementation for unchanged
# logic. The candidate netlist, cycle boundaries and timing constraints remain
# those of the frozen source snapshot; only physical reuse is requested.
if {$argc != 4} {error "Expected SYNTH_DCP REFERENCE_DCP NEW_OUTPUT_ROOT BRAM_COUNT"}
set incr_scripts [file normalize [file dirname [info script]]]
set incr_input [file normalize [lindex $argv 0]]
set incr_reference [file normalize [lindex $argv 1]]
set incr_output [file normalize [lindex $argv 2]]
set incr_brams [lindex $argv 3]
if {$incr_brams ni {18 36}} {error "Unsupported BRAM count"}
if {[file exists $incr_output]} {error "Preserve previous incremental result"}
file mkdir $incr_output
cd $incr_output
set_param general.maxThreads 2
open_checkpoint $incr_input
if {[llength [get_clocks]] != 1 || abs([get_property PERIOD [get_clocks clk]] - 10.0) > 0.000001} {
    error "Expected original 10.000 ns clock"
}
if {[llength [get_cells -hier -filter {REF_NAME == RAMB36E1}]] != $incr_brams} {
    error "Unexpected candidate memory configuration"
}
opt_design
read_checkpoint -incremental $incr_reference
report_incremental_reuse -file reuse_loaded.rpt
place_design
write_checkpoint placed.dcp
report_timing_summary -max_paths 10 -file timing_placed.rpt
report_incremental_reuse -file reuse_placed.rpt
phys_opt_design -directive AggressiveExplore
write_checkpoint physopt.dcp
route_design
write_checkpoint routed.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 100 -input_pins -file critical_paths.rpt
report_utilization -file utilization_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc_routed.rpt
report_incremental_reuse -file reuse_routed.rpt
set incr_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set incr_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fd [open result.txt w]
puts $fd "setup_ns=$incr_setup hold_ns=$incr_hold"
puts $fd "candidate=$incr_input"
puts $fd "reference=$incr_reference"
close $fd
puts "INCREMENTAL_COMPLETE setup=$incr_setup hold=$incr_hold"
if {$incr_setup >= 0.0 && $incr_hold >= 0.0} {
    close_project
    set argv [list [file join $incr_output routed.dcp] [file join $incr_output final_audit] $incr_brams]
    set argc [llength $argv]
    source [file join $incr_scripts final_gate.tcl]
} else {
    set fd [open INCOMPLETE.txt w]
    puts $fd "100 MHz timing NOT closed. See completed-route reports."
    close $fd
}
