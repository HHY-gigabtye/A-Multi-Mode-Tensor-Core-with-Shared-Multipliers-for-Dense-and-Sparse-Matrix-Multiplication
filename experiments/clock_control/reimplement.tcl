# Retarget placement/routing of an unchanged synthesized netlist.
# vivado -mode batch -source reimplement.tcl -tclargs SYNTH_DCP OUTPUT_DIR PERIOD
set synth_dcp [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
set period [lindex $argv 2]
set directive [lindex $argv 3]
if {$directive eq ""} {set directive Default}
if {[file exists [file join $output_dir routed.dcp]]} {error "Use a new output directory"}
file mkdir $output_dir
cd $output_dir
set_param general.maxThreads 4
open_checkpoint $synth_dcp
set clock_file [open clock.xdc w]
puts $clock_file "create_clock -period $period -name clk \[get_ports clk\]"
close $clock_file
read_xdc clock.xdc
opt_design
place_design
report_utilization -file utilization_placed.rpt
phys_opt_design -directive $directive
route_design
write_checkpoint -force routed.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 20 -input_pins -file critical_paths.rpt
report_high_fanout_nets -max_nets 30 -timing -load_types -file high_fanout.rpt
report_utilization -file utilization_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc_routed.rpt
puts "FMAX_REIMPLEMENT_COMPLETE checkpoint=$synth_dcp period=$period"
