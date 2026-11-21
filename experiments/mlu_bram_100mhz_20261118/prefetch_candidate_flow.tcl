# Baseline-comparable Default placement/physical optimization/routing.
# Requires completed original regressions and the unchanged early_prefetch MLU.
# Reuse its primitive comparison only after exact source-text equality.
if {$argc != 2} {error "Expected SOURCE_SNAPSHOT NEW_OUTPUT_ROOT"}
set cand_scripts [file normalize [file dirname [info script]]]
set cand_source [file normalize [lindex $argv 0]]
set cand_output [file normalize [lindex $argv 1]]
set cand_trial [file dirname $cand_source]
if {[file exists $cand_output]} {error "Preserve earlier candidate implementation"}
set fd [open [file join $cand_source mlu_sv mlu.sv] r]
set candidate_mlu [read $fd]
close $fd
set fd [open [file join $cand_scripts early_prefetch src mlu_sv mlu.sv] r]
set tested_mlu [read $fd]
close $fd
if {$candidate_mlu ne $tested_mlu} {error "MLU source differs from primitive-tested early_prefetch"}
foreach {log markers} {
    units.log {{ALL PASS MLU unit C/SV:} {[PASS] DU/TIA compact RTL:} {BRIDGE RTL PASS:} {ALL PASS C/SV:} {MSU SV PASS:}}
    top.log {{TOP INTEGRATION PASS:}}
    ../early_prefetch/equiv_netlist/result.log {{MLU BRAM EQUIVALENCE PASS vectors=16708 steps=17171}}
} {
    set fd [open [file join $cand_trial $log] r]
    set body [read $fd]
    close $fd
    if {[regexp {\*\*\s+(Fatal|Error):|Fatal:|\$fatal} $body]} {error "Regression error: $log"}
    foreach marker $markers {
        if {[string first $marker $body] < 0} {error "Missing regression PASS: $marker"}
    }
}
file mkdir $cand_output
set argv [list $cand_source [file join $cand_output synthesis]]
set argc 2
source [file join $cand_scripts synth_top_serial.tcl]
if {[llength [get_cells -hier -filter {REF_NAME == DSP48E1}]] != 128} {
    error "DSP count changed; inspect arithmetic sharing before implementation"
}
set_param general.maxThreads 2
report_drc -checks [get_drc_checks REQP-1839] -file bram_control_synth.rpt
set fd [open bram_control_synth.rpt r]
set control_report [read $fd]
close $fd
if {![regexp {Violations found:\s*0\s} $control_report]} {error "BRAM control DRC failed"}
file mkdir [file join $cand_output initial]
cd [file join $cand_output initial]
opt_design
place_design
write_checkpoint placed.dcp
report_timing_summary -max_paths 10 -file timing_placed.rpt
report_design_analysis -congestion -file congestion.rpt
phys_opt_design -directive Default
write_checkpoint physopt.dcp
route_design
write_checkpoint routed.dcp
report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary_routed.rpt
report_timing -max_paths 100 -input_pins -file critical_paths.rpt
report_high_fanout_nets -max_nets 100 -timing -load_types -file high_fanout.rpt
report_utilization -file utilization_routed.rpt
report_route_status -file route_status.rpt
report_drc -file drc_routed.rpt
set cand_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set cand_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fd [open [file join $cand_output timing_trials.csv] w]
puts $fd "trial,wns_ns,whs_ns,checkpoint"
puts $fd "initial,$cand_setup,$cand_hold,[file join $cand_output initial routed.dcp]"
close $fd
puts "DEFAULT_CANDIDATE_ROUTE_COMPLETE setup=$cand_setup hold=$cand_hold"
if {$cand_setup >= 0.0 && $cand_hold >= 0.0} {
    close_project
    set argv [list [file join $cand_output initial routed.dcp] [file join $cand_output final_audit] 18]
    set argc 3
    source [file join $cand_scripts final_gate.tcl]
} else {
    set fd [open [file join $cand_output INCOMPLETE.txt] w]
    puts $fd "100 MHz timing NOT closed. Inspect completed-route paths before another optimization."
    close $fd
}


