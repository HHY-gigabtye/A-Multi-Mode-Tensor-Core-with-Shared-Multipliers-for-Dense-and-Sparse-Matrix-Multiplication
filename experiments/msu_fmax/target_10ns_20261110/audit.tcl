# Read-only checkpoint audit; does not replace clocks or save the design.
# Arguments: CHECKPOINT NEW_OUTPUT_DIR
if {$argc != 2} {error "Expected CHECKPOINT NEW_OUTPUT_DIR"}
set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
if {[file exists $output_dir]} {error "Use a new output directory"}
file mkdir $output_dir
set_param general.maxThreads 4
open_checkpoint $checkpoint
cd $output_dir
report_clocks -file clocks.rpt
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary.rpt
report_timing -delay_type max -max_paths 100 -nworst 1 -input_pins -file critical_paths.rpt
report_utilization -hierarchical -file utilization.rpt
report_route_status -file route_status.rpt
report_drc -file drc.rpt
report_high_fanout_nets -max_nets 40 -timing -load_types -file high_fanout.rpt
set fd [open audit.txt w]
puts $fd "Checkpoint: $checkpoint"
puts $fd "Original clocks and constraints preserved."
puts $fd "Setup slack ns: [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]"
puts $fd "Hold slack ns: [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]"
set histogram [dict create]
set dsps [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]
foreach dsp $dsps {
    set key {}
    foreach property {AREG BREG MREG PREG} {
        lappend key "$property=[get_property $property $dsp]"
    }
    dict incr histogram [join $key ,]
}
puts $fd "DSP48E1 count: [llength $dsps]"
dict for {configuration count} $histogram {
    puts $fd "DSP configuration $configuration count=$count"
}
close $fd
set fd [open groups.tsv w]
puts $fd "group\tendpoint_cells\tworst_slack_ns"
foreach {label pattern} {
    msu u_msu/*
    mlu u_mlu/*
    bridge u_bridge/*
    du_tia u_du_tia/*
    tc_all u_tensor_core/*
    tc_dense u_tensor_core/dense_q_reg*
    tc_sparse u_tensor_core/sparse*
    tc_results u_tensor_core/ctrl_q_reg*result*
} {
    set cells [get_cells -hierarchical -filter "IS_SEQUENTIAL == 1 && NAME =~ $pattern"]
    if {[llength $cells] == 0} {error "No sequential endpoints for $label"}
    set paths [get_timing_paths -delay_type max -to $cells -max_paths 1]
    puts $fd "$label\t[llength $cells]\t[get_property SLACK $paths]"
    report_timing -delay_type max -to $cells -max_paths 10 -input_pins -file ${label}.rpt
}
close $fd
set pins [get_pins -of_objects $dsps -filter {DIRECTION == OUT && REF_PIN_NAME =~ P*}]
report_timing -delay_type max -through $pins -max_paths 10 -input_pins -file through_dsp.rpt
puts "TARGET_10NS_AUDIT_COMPLETE"
close_design
