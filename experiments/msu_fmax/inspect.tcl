# Read-only STA of an existing routed checkpoint. No synthesis, implementation,
# clock replacement, project save, or checkpoint write is performed.
# Arguments: ROUTED_DCP NEW_OUTPUT_DIR
if {$argc != 2} { error "Usage: inspect.tcl ROUTED_DCP NEW_OUTPUT_DIR" }
set checkpoint [file normalize [lindex $argv 0]]
set outdir [file normalize [lindex $argv 1]]
if {[file exists $outdir]} { error "Output directory already exists: $outdir" }
file mkdir $outdir
set_param general.maxThreads 4
open_checkpoint $checkpoint
cd $outdir
report_clocks -file clocks.rpt
report_timing_summary -max_paths 10 -report_unconstrained -file timing_summary.rpt
report_timing -delay_type max -max_paths 100 -nworst 1 -input_pins -file critical_100.rpt
report_route_status -file route_status.rpt
report_high_fanout_nets -max_nets 40 -timing -load_types -file high_fanout.rpt
report_utilization -hierarchical -file utilization.rpt
set summary [open groups.tsv w]
puts $summary "group\tendpoint_cells\tworst_slack_ns"
foreach {label pattern} {
    msu u_msu/*
    tc_dense u_tensor_core/dense_q_reg*
    tc_sparse u_tensor_core/sparse_q_reg*
    tc_results u_tensor_core/ctrl_q_reg*result*
    tc_control u_tensor_core/ctrl_q_reg*
    bridge u_bridge/*
    mlu u_mlu/*
    du_tia u_du_tia/*
} {
    set cells [get_cells -hierarchical -filter "IS_SEQUENTIAL == 1 && NAME =~ $pattern"]
    if {[llength $cells] == 0} { error "No sequential endpoints for $label" }
    report_timing -delay_type max -to $cells -max_paths 10 -nworst 1 -input_pins -file ${label}.rpt
    set worst [get_timing_paths -delay_type max -to $cells -max_paths 1]
    puts $summary "$label\t[llength $cells]\t[get_property SLACK $worst]"
}
close $summary
set dense_cells [get_cells -hierarchical -filter {IS_SEQUENTIAL == 1 && NAME =~ u_tensor_core/dense_q_reg*acc*}]
set dense_data [get_pins -of_objects $dense_cells -filter {REF_PIN_NAME == D}]
report_timing -delay_type max -to $dense_data -max_paths 10 -input_pins -file dense_acc_data.rpt
set dsps [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]
set dsp_outputs [get_pins -of_objects $dsps -filter {DIRECTION == OUT && REF_PIN_NAME =~ P*}]
report_timing -delay_type max -through $dsp_outputs -max_paths 10 -input_pins -file through_dsp.rpt
set audit [open audit.txt w]
puts $audit "Checkpoint: $checkpoint"
puts $audit "Reopened existing route; original constraints preserved."
puts $audit "Setup slack ns: [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]"
puts $audit "Hold slack ns: [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]"
puts $audit "DSP48E1 count: [llength $dsps]"
foreach prop {AREG BREG MREG PREG} {
    puts $audit "$prop values: [lsort -unique [get_property $prop $dsps]]"
}
close $audit
set msu_results [get_cells -hierarchical -filter {IS_SEQUENTIAL == 1 && NAME =~ u_msu/*result_q_reg*}]
if {[llength $msu_results] == 0} { error "MSU result registers not found" }
set msu_enable_pins [get_pins -of_objects $msu_results -filter {REF_PIN_NAME == CE}]
set msu_enables [get_nets -of_objects $msu_enable_pins]
set fanout_file [open msu_enable_fanout.csv w]
puts $fanout_file "Net,TotalSinkPins"
foreach net $msu_enables {
    set sinks [get_pins -of_objects $net -filter {DIRECTION == IN}]
    puts $fanout_file "[get_property NAME $net],[llength $sinks]"
}
close $fanout_file
set tc_result_cells {}
foreach cell [get_cells -hierarchical -filter {IS_SEQUENTIAL == 1 && NAME =~ u_tensor_core/ctrl_q_reg*result*}] {
    if {[regexp {ctrl_q_reg\[result(_next)?\]\[} [get_property NAME $cell]]} {
        lappend tc_result_cells $cell
    }
}
if {[llength $tc_result_cells] == 0} {error "TC result matrix registers not found"}
set tc_enable_pins [get_pins -of_objects $tc_result_cells -filter {REF_PIN_NAME == CE}]
set tc_enables [get_nets -of_objects $tc_enable_pins]
set fanout_file [open tc_enable_fanout.csv w]
puts $fanout_file "Net,TotalSinkPins"
foreach net $tc_enables {
    puts $fanout_file "[get_property NAME $net],[llength [get_pins -of_objects $net -filter {DIRECTION == IN}]]"
}
close $fanout_file
puts "FMAX_DIAGNOSTIC_COMPLETE"
close_design
