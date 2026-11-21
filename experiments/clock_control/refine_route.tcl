# Preserve a completed route and optimize its remaining critical paths.
# Arguments: ROUTED_DCP NEW_OUTPUT_DIR PERIOD_NS
set input_dcp [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
set period [lindex $argv 2]
if {[file exists [file join $output_dir routed.dcp]]} {error "Use a new output directory"}
file mkdir $output_dir
cd $output_dir
set_param general.maxThreads 4
open_checkpoint $input_dcp
set clock_file [open clock.xdc w]
puts $clock_file "create_clock -period $period -name clk \[get_ports clk\]"
close $clock_file
read_xdc clock.xdc
report_timing_summary -max_paths 20 -file timing_before.rpt
report_utilization -file utilization_placed.rpt
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
write_checkpoint routed.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 50 -input_pins -file critical_paths.rpt
report_high_fanout_nets -max_nets 30 -timing -load_types -file high_fanout.rpt
report_utilization -file utilization_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc_routed.rpt
puts "CLOCK_REFINE_COMPLETE input=$input_dcp period=$period"
