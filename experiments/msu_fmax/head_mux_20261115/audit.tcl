# Reopen a saved checkpoint without changing its clock, placement or routing.
# Arguments: ROUTED_DCP NEW_OUTPUT_DIR EXPECTED_PERIOD_NS ?product_shadow?
# Exit 0 indicates report completion, not timing closure.
if {$argc != 3 && $argc != 4} {error "Expected ROUTED_DCP NEW_OUTPUT_DIR EXPECTED_PERIOD_NS ?product_shadow?"}
set head_audit_shadow 0
if {$argc == 4} {
    if {[lindex $argv 3] ne "product_shadow"} {error "Unknown audit variant"}
    set head_audit_shadow 1
}
set head_audit_shadow_guard [file normalize [file join [file dirname [info script]] check_product_shadow.tcl]]
set head_audit_input [file normalize [lindex $argv 0]]
set head_audit_output [file normalize [lindex $argv 1]]
set head_audit_period [lindex $argv 2]
if {[file exists $head_audit_output]} {error "Use a new output directory"}
file mkdir $head_audit_output
cd $head_audit_output
set_param general.maxThreads 4
open_checkpoint $head_audit_input
set head_audit_clock [get_clocks]
if {[llength $head_audit_clock] != 1 || [get_property NAME $head_audit_clock] ne "clk" ||
    abs([get_property PERIOD $head_audit_clock] - $head_audit_period) > 0.000001} {
    error "Saved checkpoint clock does not match the expected period"
}
report_clocks -file clocks.rpt
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary.rpt
report_timing -delay_type max -max_paths 100 -nworst 1 -input_pins -file critical_paths.rpt
report_utilization -hierarchical -file utilization.rpt
report_route_status -file route_status.rpt
report_drc -file drc.rpt
report_high_fanout_nets -max_nets 40 -timing -load_types -file high_fanout.rpt
set head_audit_fd [open audit.txt w]
puts $head_audit_fd "Checkpoint: $head_audit_input"
puts $head_audit_fd "Clock period ns: [get_property PERIOD $head_audit_clock]"
puts $head_audit_fd "Setup slack ns: [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]"
puts $head_audit_fd "Hold slack ns: [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]"
puts $head_audit_fd "Constraints, placement and routing unchanged."
set head_audit_dsps [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]
set head_audit_histogram [dict create]
foreach head_audit_dsp $head_audit_dsps {
    set head_audit_key {}
    foreach head_audit_property {AREG BREG MREG PREG} {
        lappend head_audit_key "$head_audit_property=[get_property $head_audit_property $head_audit_dsp]"
    }
    dict incr head_audit_histogram [join $head_audit_key ,]
}
puts $head_audit_fd "DSP48E1 count: [llength $head_audit_dsps]"
dict for {head_audit_config head_audit_count} $head_audit_histogram {
    puts $head_audit_fd "DSP configuration $head_audit_config count=$head_audit_count"
}
set head_audit_starts [get_cells -hierarchical -filter {IS_SEQUENTIAL == 1 && NAME =~ u_bridge/*head_select*_q_reg*}]
set head_audit_products [get_cells -hierarchical -filter {REF_NAME == DSP48E1 && NAME =~ u_tensor_core/g_arithmetic*product_q_reg*}]
if {[llength $head_audit_starts] == 0 || [llength $head_audit_products] != 64} {
    error "Unexpected head selector or sparse DSP selection"
}
if {$head_audit_shadow} {source $head_audit_shadow_guard}
foreach {head_audit_label head_audit_filter} {
    head_to_dsp_data {DIRECTION == IN && (REF_PIN_NAME =~ A* || REF_PIN_NAME =~ B*)}
    head_to_dsp_enable {DIRECTION == IN && REF_PIN_NAME =~ CE*}
} {
    set head_audit_pins [get_pins -of_objects $head_audit_products -filter $head_audit_filter]
    set head_audit_paths [get_timing_paths -from $head_audit_starts -to $head_audit_pins -max_paths 1]
    if {[llength $head_audit_paths] == 0} {
        if {$head_audit_shadow && $head_audit_label eq "head_to_dsp_enable"} {
            puts $head_audit_fd "${head_audit_label}: no paths; product CEP is constant high as required."
            continue
        }
        error "No paths for $head_audit_label"
    }
    puts $head_audit_fd "$head_audit_label slack ns: [get_property SLACK $head_audit_paths]"
    report_timing -from $head_audit_starts -to $head_audit_pins -max_paths 20 -input_pins -file ${head_audit_label}.rpt
}
close $head_audit_fd
puts "HEAD_MUX_AUDIT_COMPLETE checkpoint=$head_audit_input period=$head_audit_period"
close_design
