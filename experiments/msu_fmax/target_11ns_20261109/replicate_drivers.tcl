# Target measured control nets in a completed route. No retiming, clock change,
# DSP register optimization, or new pipeline stage is requested.
# Resolve reported driver cells to their output nets. This avoids selecting a
# hierarchy-boundary net segment that has no directly queryable driver.
# Arguments: ROUTED_DCP NEW_OUTPUT_DIR LUT_DRIVER_NAMES_FILE
if {$argc != 3} {error "Expected ROUTED_DCP NEW_OUTPUT_DIR LUT_DRIVER_NAMES_FILE"}
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
set resolved_handle [open selected_drivers.txt w]
foreach line [split $names_text \n] {
    set name [string trim $line]
    if {$name eq "" || [string index $name 0] eq "#"} {continue}
    set driver [get_cells -hierarchical -filter [format {NAME == "%s"} $name]]
    if {[llength $driver] != 1} {error "Expected exactly one measured driver: $name"}
    set driver_type [get_property REF_NAME $driver]
    if {![string match LUT* $driver_type]} {
        error "Expected a LUT control driver for $name, got $driver_type"
    }
    set driver_pin [get_pins -of_objects $driver -filter {DIRECTION == OUT && REF_PIN_NAME == O}]
    if {[llength $driver_pin] != 1} {error "Expected one LUT output for $name"}
    set matches [get_nets -of_objects $driver_pin]
    if {[llength $matches] != 1} {error "Expected one output net for $name"}
    puts $resolved_handle "$name\t$driver_type\t[get_property NAME $matches]"
    lappend selected_nets [lindex $matches 0]
}
close $resolved_handle
if {[llength $selected_nets] == 0} {error "No measured nets selected"}
# Vivado 2022.2 only supports forced replication before routing.
set route_help [help route_design]
if {[string first {-unroute} $route_help] < 0} {error {This Vivado has no route_design -unroute}}
route_design -unroute
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

