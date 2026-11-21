# The MSU predicate is the only change relative to the measured early-prefetch
# BRAM design. Reuse that physical reference where Vivado can match cells/nets.
if {$argc != 3} {error "Expected SOURCE_SNAPSHOT NEW_OUTPUT_ROOT REFERENCE_DCP"}
set mi_scripts [file normalize [file dirname [info script]]]
set mi_source [file normalize [lindex $argv 0]]
set mi_output [file normalize [lindex $argv 1]]
set mi_reference [file normalize [lindex $argv 2]]
set mi_trial [file dirname $mi_source]
if {[file exists $mi_output]} {error "Preserve earlier MSU implementation"}
foreach src {
    tensor_core_sv/tensor_core_pkg.sv tensor_core_sv/tensor_core.sv
    fifo_sv/du_tc_bridge_pkg.sv fifo_sv/du_tc_bridge.sv
    du_tia_sv/rtl/du_tia_pkg.sv du_tia_sv/rtl/du_tia.sv
    mlu_sv/mlu_pkg.sv mlu_sv/mlu.sv msu_sv/rtl/msu_pkg.sv
    integration_sv/rtl/sparse_tensor_core_top.sv
} {
    set fd [open [file join $mi_source $src] r]
    set candidate_text [read $fd]
    close $fd
    set fd [open [file join $mi_scripts early_prefetch src $src] r]
    set reference_text [read $fd]
    close $fd
    if {$candidate_text ne $reference_text} {error "Non-MSU source changed: $src"}
}
foreach {log markers} {
    units.log {{ALL PASS MLU unit C/SV:} {[PASS] DU/TIA compact RTL:} {BRIDGE RTL PASS:} {ALL PASS C/SV:} {MSU SV PASS:}}
    top.log {{TOP INTEGRATION PASS:}}
    ../early_prefetch/equiv_netlist/result.log {{MLU BRAM EQUIVALENCE PASS vectors=16708 steps=17171}}
} {
    set fd [open [file join $mi_trial $log] r]
    set body [read $fd]
    close $fd
    if {[regexp {\*\*\s+(Fatal|Error):|Fatal:|\$fatal} $body]} {error "Regression failure: $log"}
    foreach marker $markers {
        if {[string first $marker $body] < 0} {error "Missing regression PASS: $marker"}
    }
}
file mkdir $mi_output
set argv [list $mi_source [file join $mi_output synthesis]]
set argc 2
source [file join $mi_scripts synth_top_serial.tcl]
if {[llength [get_cells -hier -filter {REF_NAME == DSP48E1}]] != 128} {error "DSP count changed"}
report_drc -checks [get_drc_checks REQP-1839] -file bram_control_synth.rpt
set fd [open bram_control_synth.rpt r]
set bram_report [read $fd]
close $fd
if {![regexp {Violations found:\s*0\s} $bram_report]} {error "BRAM control DRC failed"}
close_project
set argv [list [file join $mi_output synthesis synthesized.dcp] $mi_reference [file join $mi_output incremental] 18]
set argc 4
source [file join $mi_scripts incremental_flow.tcl]
