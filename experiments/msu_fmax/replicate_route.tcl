# Target measured control nets in a completed route. No retiming, clock change,
# DSP register optimization, or new pipeline stage is requested.
# Arguments: ROUTED_DCP NEW_OUTPUT_DIR NET_NAMES_FILE
if {$argc != 3} {error "Expected ROUTED_DCP NEW_OUTPUT_DIR NET_NAMES_FILE"}
set routed_input [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
set names_file [file normalize [lindex $argv 2]]
if {[file exists $output_dir]} {error "Use a new output directory"}
set names_handle [open $names_file r]
set names_text [read $names_handle]
close $names_handle
file mkdir $output_dir
cd $output_dir
set_param general.maxThreads 4
open_checkpoint $routed_input
report_timing_summary -max_paths 10 -file timing_before.rpt
report_utilization -file utilization_placed.rpt
report_high_fanout_nets -max_nets 40 -timing -load_types -file high_fanout_before.rpt
set selected_nets {}
foreach line [split $names_text \n] {
    set name [string trim $line]
    if {$name eq "" || [string index $name 0] eq "#"} {continue}
    set matches [get_nets -hierarchical -filter [format {NAME == "%s"} $name]]
    if {[llength $matches] != 1} {error "Expected exactly one net: $name"}
    set driver [get_cells -of_objects [get_pins -of_objects $matches -filter {DIRECTION == OUT}]]
    set driver_type [get_property REF_NAME $driver]
    if {![string match LUT* $driver_type] && ![string match FD* $driver_type]} {
        error "Expected a LUT or flip-flop control driver for $name, got $driver_type"
    }
    lappend selected_nets [lindex $matches 0]
}
if {[llength $selected_nets] == 0} {error "No measured nets selected"}
phys_opt_design -force_replication_on_nets $selected_nets
route_design -directive Explore
write_checkpoint routed.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 50 -input_pins -file critical_paths.rpt
report_high_fanout_nets -max_nets 40 -timing -load_types -file high_fanout.rpt
report_utilization -file utilization_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc_routed.rpt
puts "TARGETED_REPLICATION_COMPLETE input=$routed_input nets=$selected_nets"
