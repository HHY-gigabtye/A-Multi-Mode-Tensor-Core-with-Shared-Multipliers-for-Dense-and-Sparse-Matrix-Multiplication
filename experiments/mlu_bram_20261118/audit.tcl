# Read-only independent audit of a completed routed checkpoint, pass or fail.
# Usage: CHECKPOINT NEW_OUTPUT_DIR EXPECTED_BRAM36_COUNT
if {$argc != 3} {error "Expected CHECKPOINT NEW_OUTPUT_DIR EXPECTED_BRAM36_COUNT"}
set audit_input [file normalize [lindex $argv 0]]
set audit_output [file normalize [lindex $argv 1]]
set audit_expected_bram [lindex $argv 2]
if {[file exists $audit_output]} {error "Preserve previous audit"}
file mkdir $audit_output
cd $audit_output
set_param general.maxThreads 4
open_checkpoint $audit_input
if {[llength [get_clocks]] != 1 || [get_property NAME [get_clocks]] ne "clk" ||
    abs([get_property PERIOD [get_clocks clk]] - 10.0) > 0.000001} {
    error "Expected original single 10.000 ns clock"
}
report_clocks -file clocks.rpt
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary.rpt
report_timing -delay_type max -max_paths 100 -nworst 1 -input_pins -file critical_paths.rpt
report_utilization -file utilization.rpt
report_utilization -hierarchical -file hierarchy.rpt
report_route_status -file route_status.rpt
report_drc -file drc.rpt
report_high_fanout_nets -max_nets 40 -timing -load_types -file high_fanout.rpt
set fd [open audit.txt w]
puts $fd "Checkpoint: $audit_input"
puts $fd "Phase: FPGA OOC post-route STA; clocks and constraints unchanged"
puts $fd "Period ns: [get_property PERIOD [get_clocks clk]]"
puts $fd "Setup slack ns: [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]"
puts $fd "Hold slack ns: [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]"
set brams [get_cells -hierarchical -filter {REF_NAME == RAMB36E1}]
puts $fd "RAMB36E1 count: [llength $brams]"
foreach cell $brams {
    puts $fd "$cell mode=[get_property RAM_MODE $cell] read=[get_property READ_WIDTH_A $cell]/[get_property READ_WIDTH_B $cell] write=[get_property WRITE_WIDTH_A $cell]/[get_property WRITE_WIDTH_B $cell] output_reg=[get_property DOA_REG $cell]/[get_property DOB_REG $cell] write_mode=[get_property WRITE_MODE_A $cell]/[get_property WRITE_MODE_B $cell]"
}
if {[llength $brams] != $audit_expected_bram} {error "Unexpected BRAM mapping"}
set histogram [dict create]
set dsps [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]
foreach dsp $dsps {
    set key {}
    foreach property {AREG BREG MREG PREG} {lappend key "$property=[get_property $property $dsp]"}
    dict incr histogram [join $key ,]
}
puts $fd "DSP48E1 count: [llength $dsps]"
dict for {configuration count} $histogram {puts $fd "DSP $configuration count=$count"}
close $fd
foreach {label pattern} {mlu u_mlu/* bridge u_bridge/* du_tia u_du_tia/* tc u_tensor_core/* msu u_msu/*} {
    set cells [get_cells -hierarchical -filter "IS_SEQUENTIAL == 1 && NAME =~ $pattern"]
    report_timing -delay_type max -to $cells -max_paths 10 -input_pins -file ${label}.rpt
}
puts "MLU_BRAM_AUDIT_COMPLETE"
