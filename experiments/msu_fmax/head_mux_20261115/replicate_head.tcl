# Physical-only replication of measured registered head selectors.
# Arguments: ROUTED_DCP NEW_OUTPUT_DIR HEAD_FDCE_NAMES_FILE
if {$argc != 3} {error "Expected ROUTED_DCP NEW_OUTPUT_DIR HEAD_FDCE_NAMES_FILE"}
set local_head_input [file normalize [lindex $argv 0]]
set local_head_output [file normalize [lindex $argv 1]]
set local_head_names [file normalize [lindex $argv 2]]
if {[file exists $local_head_output]} {error "Use a new output directory"}
set local_head_fd [open $local_head_names r]
set local_head_text [read $local_head_fd]
close $local_head_fd
file mkdir $local_head_output
cd $local_head_output
set_param general.maxThreads 4
open_checkpoint $local_head_input
set local_head_clocks [get_clocks]
if {[llength $local_head_clocks] != 1 || [get_property NAME $local_head_clocks] ne "clk" ||
    abs([get_property PERIOD $local_head_clocks] - 10.0) > 0.000001} {
    error "Expected the measured 10.000 ns checkpoint"
}
report_timing_summary -max_paths 10 -file timing_before.rpt
set local_head_nets {}
set local_head_fd [open selected_drivers.txt w]
foreach local_head_line [split $local_head_text \n] {
    set local_head_name [string trim $local_head_line]
    if {$local_head_name eq "" || [string index $local_head_name 0] eq "#"} {continue}
    if {![string match {u_bridge/head_select_q_reg*} $local_head_name]} {
        error "Unexpected driver scope: $local_head_name"
    }
    set local_head_cell [get_cells -hierarchical -filter [format {NAME == "%s"} $local_head_name]]
    if {[llength $local_head_cell] != 1 || [get_property REF_NAME $local_head_cell] ne "FDCE"} {
        error "Expected exactly one measured FDCE: $local_head_name"
    }
    set local_head_pin [get_pins -of_objects $local_head_cell -filter {REF_PIN_NAME == Q && DIRECTION == OUT}]
    set local_head_net [get_nets -of_objects $local_head_pin]
    if {[llength $local_head_net] != 1} {error "Expected one Q net for $local_head_name"}
    puts $local_head_fd "$local_head_name\tFDCE\t[get_property NAME $local_head_net]"
    lappend local_head_nets [lindex $local_head_net 0]
}
close $local_head_fd
if {[llength $local_head_nets] == 0} {error "No measured head nets selected"}
# Forced replication is a pre-route operation in this Vivado version.
# The input checkpoint remains intact; only this in-memory copy is unrouted.
route_design -unroute
phys_opt_design -force_replication_on_nets $local_head_nets
route_design -directive Explore
write_checkpoint routed.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 100 -nworst 1 -input_pins -file critical_paths.rpt
report_utilization -file utilization_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc_routed.rpt
report_high_fanout_nets -max_nets 40 -timing -load_types -file high_fanout.rpt
puts "HEAD_REPLICATION_COMPLETE input=$local_head_input selected=[llength $local_head_nets]"
