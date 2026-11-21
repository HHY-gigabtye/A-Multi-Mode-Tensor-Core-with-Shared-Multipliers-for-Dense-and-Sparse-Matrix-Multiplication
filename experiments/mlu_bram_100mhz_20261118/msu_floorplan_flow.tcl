# Physical-only experiment motivated by the early_prefetch congestion report:
# central north window = TC 66%, MSU 29%; clock region X1Y2 is lightly used.
# Preserve the frozen synthesized netlist and the single original 10 ns clock.
if {$argc != 2} {error "Expected SYNTH_CHECKPOINT NEW_OUTPUT_ROOT"}
set fp_scripts [file normalize [file dirname [info script]]]
set fp_input [file normalize [lindex $argv 0]]
set fp_output [file normalize [lindex $argv 1]]
if {[file exists $fp_output]} {error "Preserve prior floorplan results"}
file mkdir $fp_output
cd $fp_output
set_param general.maxThreads 2
open_checkpoint $fp_input
if {[llength [get_clocks]] != 1 || abs([get_property PERIOD [get_clocks clk]] - 10.0) > 0.000001} {
    error "Expected original single 10.000 ns clock"
}
if {[llength [get_cells -hier -filter {REF_NAME == RAMB36E1}]] != 18} {
    error "Expected the 18-BRAM candidate"
}
opt_design
foreach site {SLICE_X50Y100 SLICE_X113Y149} {
    if {[llength [get_sites -quiet $site]] != 1} {error "Unexpected device geometry: $site"}
}
set msu_cell [get_cells -quiet u_msu]
if {[llength $msu_cell] != 1} {error "Expected original MSU hierarchy"}
create_pblock pblock_msu_top
add_cells_to_pblock [get_pblocks pblock_msu_top] $msu_cell
resize_pblock [get_pblocks pblock_msu_top] -add {SLICE_X50Y100:SLICE_X113Y149}
set_property IS_SOFT false [get_pblocks pblock_msu_top]
report_property [get_pblocks pblock_msu_top] -file pblock.rpt
place_design
write_checkpoint placed.dcp
report_timing_summary -max_paths 10 -file timing_placed.rpt
report_design_analysis -congestion -file congestion.rpt
phys_opt_design -directive Default
write_checkpoint physopt.dcp
route_design
write_checkpoint routed.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 100 -input_pins -file critical_paths.rpt
report_utilization -file utilization_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc_routed.rpt
set fp_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set fp_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "MSU_FLOORPLAN_ROUTE_COMPLETE setup=$fp_setup hold=$fp_hold"
if {$fp_setup >= 0.0 && $fp_hold >= 0.0} {
    close_project
    set argv [list [file join $fp_output routed.dcp] [file join $fp_output final_audit] 18]
    set argc 3
    source [file join $fp_scripts final_gate.tcl]
} else {
    set fd [open INCOMPLETE.txt w]
    puts $fd "100 MHz timing NOT closed. setup_ns=$fp_setup hold_ns=$fp_hold"
    close $fd
}
