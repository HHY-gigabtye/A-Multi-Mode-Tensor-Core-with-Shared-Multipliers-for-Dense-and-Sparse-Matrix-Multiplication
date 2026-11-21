# Additional physical-only trial, separate from the paired fresh flow.
# Usage: CANDIDATE_SYNTH_DCP VERIFIED_REFERENCE_ROUTE_DCP NEW_OUTPUT_DIR
# AMD UG904 2022.2: opt_design, read_checkpoint -incremental, place, route.
if {$argc != 3} {error "Expected SYNTH_DCP REFERENCE_ROUTE_DCP NEW_OUTPUT_DIR"}
set inc_repo [file normalize [file join [file dirname [info script]] ../..]]
set inc_synth [file normalize [lindex $argv 0]]
set inc_reference [file normalize [lindex $argv 1]]
set inc_output [file normalize [lindex $argv 2]]
if {[file exists $inc_output]} {error "Preserve previous incremental trial"}
file mkdir [file join $inc_output default]
cd [file join $inc_output default]
set_param general.maxThreads 4
open_checkpoint $inc_synth
if {[llength [get_clocks]] != 1 || abs([get_property PERIOD [get_clocks clk]] - 10.0) > 0.000001} {
    error "Candidate synthesis must retain the 10.000 ns clock"
}
opt_design
# The first trial matched 76.59% of cells and reverted to a normal flow at
# the default 80% threshold. Preserve its log separately and explicitly
# request reuse of the matching cells for this physical-only experiment.
read_checkpoint -incremental $inc_reference -force_incr
report_incremental_reuse -file reuse_import.rpt
place_design
write_checkpoint placed.dcp
report_utilization -file utilization_placed.rpt
phys_opt_design -directive Default
route_design
write_checkpoint routed.dcp
report_incremental_reuse -file reuse_routed.rpt
report_clocks -file clocks.rpt
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 50 -input_pins -file critical_paths.rpt
report_utilization -file utilization_routed.rpt
report_utilization -hierarchical -file hierarchy.rpt
report_route_status -file route_status.rpt
report_drc -file drc.rpt
report_high_fanout_nets -max_nets 40 -timing -load_types -file high_fanout.rpt
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "INCREMENTAL_DEFAULT_COMPLETE setup=$setup hold=$hold"
close_project
if {$setup < 0 || $hold < 0} {
    set argv [list [file join $inc_output default routed.dcp] [file join $inc_output refined] 10.000]
    set argc 3
    source [file join $inc_repo experiments clock_control refine_route.tcl]
}
puts "MLU_INCREMENTAL_TRIAL_COMPLETE"
