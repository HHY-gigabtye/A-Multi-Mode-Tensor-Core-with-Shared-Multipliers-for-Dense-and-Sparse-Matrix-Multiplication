# Read-only audit for either the original or the banked result implementation.
# Arguments: CHECKPOINT NEW_OUTPUT_DIR EXPECTED_PERIOD_NS
if {$argc != 3} {error "Expected CHECKPOINT NEW_OUTPUT_DIR EXPECTED_PERIOD_NS"}
set candidate_checkpoint [file normalize [lindex $argv 0]]
set candidate_output [file normalize [lindex $argv 1]]
set candidate_period [lindex $argv 2]
if {[file exists $candidate_output]} {error "Use a new output directory"}
file mkdir $candidate_output
cd $candidate_output
set_param general.maxThreads 4
open_checkpoint $candidate_checkpoint
set candidate_clock [get_clocks]
if {[llength $candidate_clock] != 1 ||
    [get_property NAME $candidate_clock] ne "clk" ||
    abs([get_property PERIOD $candidate_clock] - $candidate_period) > 0.000001} {
    error "Checkpoint clock does not match the requested audit period"
}
report_clocks -file clocks.rpt
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary.rpt
report_timing -delay_type max -max_paths 100 -nworst 1 -input_pins -file critical_paths.rpt
report_utilization -hierarchical -file utilization.rpt
report_route_status -file route_status.rpt
report_drc -file drc.rpt
report_high_fanout_nets -max_nets 40 -timing -load_types -file high_fanout.rpt
set candidate_fd [open audit.txt w]
puts $candidate_fd "Checkpoint: $candidate_checkpoint"
puts $candidate_fd "Original clocks and constraints preserved."
puts $candidate_fd "Clock period ns: [get_property PERIOD $candidate_clock]"
puts $candidate_fd "Setup slack ns: [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]"
puts $candidate_fd "Hold slack ns: [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]"
set candidate_dsps [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]
set candidate_histogram [dict create]
foreach candidate_dsp $candidate_dsps {
    set candidate_key {}
    foreach candidate_property {AREG BREG MREG PREG} {
        lappend candidate_key "$candidate_property=[get_property $candidate_property $candidate_dsp]"
    }
    dict incr candidate_histogram [join $candidate_key ,]
}
puts $candidate_fd "DSP48E1 count: [llength $candidate_dsps]"
dict for {candidate_configuration candidate_count} $candidate_histogram {
    puts $candidate_fd "DSP configuration $candidate_configuration count=$candidate_count"
}
close $candidate_fd
set candidate_fd [open groups.tsv w]
puts $candidate_fd "group\tendpoint_cells\tworst_slack_ns"
foreach {candidate_label candidate_pattern} {
    msu u_msu/*
    mlu u_mlu/*
    bridge u_bridge/*
    du_tia u_du_tia/*
    tc_all u_tensor_core/*
    tc_dense u_tensor_core/dense_q_reg*
    tc_sparse u_tensor_core/sparse*
    tc_results u_tensor_core/*result*
} {
    set candidate_cells [get_cells -hierarchical -filter "IS_SEQUENTIAL == 1 && NAME =~ $candidate_pattern"]
    if {[llength $candidate_cells] == 0} {error "No sequential endpoints for $candidate_label"}
    set candidate_paths [get_timing_paths -delay_type max -to $candidate_cells -max_paths 1]
    puts $candidate_fd "$candidate_label\t[llength $candidate_cells]\t[get_property SLACK $candidate_paths]"
    report_timing -delay_type max -to $candidate_cells -max_paths 10 -input_pins -file ${candidate_label}.rpt
}
close $candidate_fd
puts "RESULT_BANK_AUDIT_COMPLETE checkpoint=$candidate_checkpoint period=$candidate_period"
close_design
