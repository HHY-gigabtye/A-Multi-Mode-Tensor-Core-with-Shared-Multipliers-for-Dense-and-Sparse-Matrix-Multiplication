# Re-place an immutable synthesized candidate using a measured-problem
# directive. The original 10.000 ns clock and all interfaces remain intact.
if {$argc != 3} {error "Expected SYNTH_DCP NEW_OUTPUT_DIR PLACER_DIRECTIVE"}
set task_input [file normalize [lindex $argv 0]]
set task_output [file normalize [lindex $argv 1]]
set task_place [lindex $argv 2]
if {$task_place ni {ExtraNetDelay_high AltSpreadLogic_high WLDrivenBlockPlacement}} {
    error "Unexpected placer directive"
}
if {[file exists $task_output]} {error "Preserve previous implementation"}
file mkdir $task_output
cd $task_output
set_param general.maxThreads 4
open_checkpoint $task_input
if {[llength [get_clocks]] != 1 || abs([get_property PERIOD [get_clocks clk]] - 10.0) > 0.000001} {
    error "Expected single original 10.000 ns clock"
}
opt_design
place_design -directive $task_place
write_checkpoint placed.dcp
report_timing_summary -max_paths 10 -file timing_placed.rpt
report_design_analysis -congestion -file congestion.rpt
phys_opt_design -directive AggressiveExplore
write_checkpoint physopt.dcp
route_design -directive Explore
write_checkpoint routed.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 100 -input_pins -file critical_paths.rpt
report_high_fanout_nets -max_nets 100 -timing -load_types -file high_fanout.rpt
report_utilization -file utilization_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc_routed.rpt
puts "BRAM_REIMPLEMENT_COMPLETE placement=$task_place clock=10.000"
