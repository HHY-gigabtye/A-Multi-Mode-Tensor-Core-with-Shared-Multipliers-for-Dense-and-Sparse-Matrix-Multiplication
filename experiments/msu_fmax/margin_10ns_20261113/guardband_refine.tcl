# Physical-only margin search. Operating clock remains 10.000 ns.
# Arguments: ORIGINAL_10NS_DCP NEW_OUTPUT_DIR SEARCH_PERIOD_NS
if {$argc != 3} {error "Expected ORIGINAL_10NS_DCP NEW_OUTPUT_DIR SEARCH_PERIOD_NS"}
set margin_repo [file normalize [file join [file dirname [info script]] ../../..]]
set margin_input [file normalize [lindex $argv 0]]
set margin_output [file normalize [lindex $argv 1]]
set margin_search_period [lindex $argv 2]
if {![string is double -strict $margin_search_period] ||
    $margin_search_period <= 0 || $margin_search_period >= 10.0} {
    error "Search period must be positive and strictly below the 10 ns operating period"
}
if {[file exists $margin_output]} {error "Use a new output directory"}
file mkdir $margin_output
cd $margin_output
set_param general.maxThreads 4
open_checkpoint $margin_input
set margin_clocks [get_clocks]
if {[llength $margin_clocks] != 1 ||
    [get_property NAME $margin_clocks] ne "clk" ||
    abs([get_property PERIOD $margin_clocks] - 10.0) > 0.000001} {
    error "Input checkpoint must have exactly one original 10.000 ns clock"
}
report_clocks -file clocks_original_10ns.rpt
report_timing_summary -max_paths 20 -file timing_original_10ns.rpt
create_clock -period $margin_search_period -name clk \
    -waveform [list 0 [expr {$margin_search_period / 2.0}]] [get_ports clk]
report_clocks -file clocks_search.rpt
report_timing_summary -max_paths 20 -file timing_search_before.rpt
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
write_checkpoint routed_search.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_search_after.rpt
report_route_status -file route_status.rpt

# Restore the original operating requirement. This is not a claim that the
# tighter search target closed; retain both reports and apply the 10 ns gate.
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]
report_clocks -file clocks.rpt
set task_post_route_refined 1
source [file join $margin_repo project_integration scripts post_route_opt.tcl.txt]
report_timing -max_paths 100 -nworst 1 -input_pins -file critical_paths.rpt
report_high_fanout_nets -max_nets 40 -timing -load_types -file high_fanout.rpt
set margin_fd [open result.txt w]
puts $margin_fd "Input checkpoint: $margin_input"
puts $margin_fd "Search period ns: $margin_search_period"
puts $margin_fd "Operating period ns: [get_property PERIOD [get_clocks clk]]"
puts $margin_fd "Setup slack ns: $task_setup"
puts $margin_fd "Hold slack ns: $task_hold"
close $margin_fd
puts "MARGIN_SEARCH_COMPLETE search=$margin_search_period operating=10.000 setup=$task_setup hold=$task_hold"
close_design
