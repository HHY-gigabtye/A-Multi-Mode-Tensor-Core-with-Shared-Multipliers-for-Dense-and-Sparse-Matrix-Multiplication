# Reproduce the selected 11 ns physical step from the measured accumulator trial.
# Operates only on the current in-memory design; the caller preserves checkpoints.
# No retiming, DSP registers, clock changes, or RTL pipeline stages are added.
set task_rep_clock [get_clocks clk]
if {[llength $task_rep_clock] != 1 || abs([get_property PERIOD $task_rep_clock] - 11.0) > 0.000001} {
    error "Control replication requires the measured 11.000 ns clk"
}
set task_rep_nets {}
set task_rep_resolved {}
foreach task_rep_name {
    u_bridge/dense_q[a_delay][3][2][value][7]_i_1
    u_bridge/sparse_q[route][delta][5][5][15]_i_1
} {
    set task_rep_driver [get_cells -hierarchical -filter [format {NAME == "%s"} $task_rep_name]]
    if {[llength $task_rep_driver] != 1} {error "Expected exactly one measured driver: $task_rep_name"}
    set task_rep_type [get_property REF_NAME $task_rep_driver]
    if {![string match LUT* $task_rep_type]} {error "Expected a LUT control driver: $task_rep_name"}
    set task_rep_pin [get_pins -of_objects $task_rep_driver -filter {DIRECTION == OUT && REF_PIN_NAME == O}]
    if {[llength $task_rep_pin] != 1} {error "Expected one LUT output: $task_rep_name"}
    set task_rep_net [get_nets -of_objects $task_rep_pin]
    if {[llength $task_rep_net] != 1} {error "Expected one output net: $task_rep_name"}
    lappend task_rep_nets [lindex $task_rep_net 0]
    lappend task_rep_resolved "$task_rep_name\t$task_rep_type\t[get_property NAME $task_rep_net]"
}
set task_rep_fd [open timing_replicated_drivers.txt w]
puts $task_rep_fd [join $task_rep_resolved \n]
close $task_rep_fd
# Vivado 2022.2 requires post-place mode for forced replication.
if {[string first {-unroute} [help route_design]] < 0} {error "Vivado lacks route_design -unroute"}
route_design -unroute
phys_opt_design -force_replication_on_nets $task_rep_nets
route_design -directive Explore
puts "MAIN_11NS_CONTROL_REPLICATION_COMPLETE"
