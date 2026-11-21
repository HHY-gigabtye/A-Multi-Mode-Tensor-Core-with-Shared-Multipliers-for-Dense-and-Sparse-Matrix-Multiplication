# Physical-only refinement of explicitly inspected LUT drivers. Vivado 2022.2
# requires unroute before forced replication. Keep every original checkpoint.
if {$argc != 3} {error "Expected ROUTED_DCP NEW_OUTPUT_DIR DRIVER_NAMES_FILE"}
set sel_scripts [file normalize [file dirname [info script]]]
set sel_input [file normalize [lindex $argv 0]]
set sel_output [file normalize [lindex $argv 1]]
set sel_names [file normalize [lindex $argv 2]]
if {[file exists $sel_output]} {error "Preserve previous replication trial"}
file mkdir $sel_output
cd $sel_output
set_param general.maxThreads 2
open_checkpoint $sel_input
if {[llength [get_clocks]] != 1 || abs([get_property PERIOD [get_clocks clk]] - 10.0) > 0.000001} {
    error "Expected original single 10.000 ns clock"
}
set fd [open $sel_names r]
set sel_text [read $fd]
close $fd
set sel_nets {}
set fd [open selected_drivers.tsv w]
puts $fd "driver\ttype\tnet"
foreach line [split $sel_text \n] {
    set name [string trim $line]
    if {$name eq "" || [string index $name 0] eq "#"} {continue}
    set driver [get_cells -hierarchical -filter [format {NAME == "%s"} $name]]
    if {[llength $driver] != 1 || ![string match LUT* [get_property REF_NAME $driver]]} {
        error "Expected one inspected LUT driver: $name"
    }
    set pin [get_pins -of_objects $driver -filter {DIRECTION == OUT && REF_PIN_NAME == O}]
    set net [get_nets -of_objects $pin]
    if {[llength $pin] != 1 || [llength $net] != 1} {error "Ambiguous driver output: $name"}
    puts $fd "$name\t[get_property REF_NAME $driver]\t[get_property NAME $net]"
    lappend sel_nets [lindex $net 0]
}
close $fd
if {[llength $sel_nets] != 4} {error "Expected the four measured drivers"}
report_timing_summary -max_paths 10 -file timing_before.rpt
route_design -unroute
phys_opt_design -force_replication_on_nets $sel_nets
write_checkpoint replicated_placed.dcp
route_design -directive Explore
write_checkpoint routed.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 100 -input_pins -file critical_paths.rpt
report_utilization -file utilization_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc_routed.rpt
set sel_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set sel_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "SELECTED_REPLICATION_COMPLETE setup=$sel_setup hold=$sel_hold"
if {$sel_setup >= 0.0 && $sel_hold >= 0.0} {
    close_project
    set argv [list [file join $sel_output routed.dcp] [file join $sel_output final_audit] 18]
    set argc 3
    source [file join $sel_scripts final_gate.tcl]
} else {
    set fd [open INCOMPLETE.txt w]
    puts $fd "100 MHz timing NOT closed. setup_ns=$sel_setup hold_ns=$sel_hold"
    close $fd
}
