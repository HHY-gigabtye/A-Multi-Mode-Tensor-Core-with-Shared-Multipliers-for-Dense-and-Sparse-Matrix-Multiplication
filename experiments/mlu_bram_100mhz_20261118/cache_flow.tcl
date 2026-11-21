# Bounded, reproducible flow for the frozen 18-BRAM cache candidate.
# A failed equivalence check stops before implementation. Physical trials
# remain separate; only final_gate.tcl can emit a 100 MHz PASS.
if {$argc != 3} {error "Expected SOURCE_SNAPSHOT MLU_NETLIST NEW_OUTPUT_ROOT"}
set cache_scripts [file normalize [file dirname [info script]]]
set cache_repo [file normalize [file join $cache_scripts ../..]]
set cache_source [file normalize [lindex $argv 0]]
set cache_netlist [file normalize [lindex $argv 1]]
set cache_output [file normalize [lindex $argv 2]]
set cache_trial [file dirname $cache_source]
if {[file exists $cache_output]} {error "Preserve previous flow"}
foreach {log markers} {
    units.log {{ALL PASS MLU unit C/SV:} {[PASS] DU/TIA compact RTL:} {BRIDGE RTL PASS:} {ALL PASS C/SV:} {MSU SV PASS:}}
    top.log {{TOP INTEGRATION PASS:}}
} {
    set fd [open [file join $cache_trial $log] r]
    set body [read $fd]
    close $fd
    if {[regexp {\*\*\s+(Fatal|Error):} $body]} {error "Regression error in $log"}
    foreach marker $markers {
        if {[string first $marker $body] < 0} {error "Missing regression PASS: $marker"}
    }
}
file mkdir $cache_output
set cache_records {}
proc cache_run {script arguments} {
    set ::argv $arguments
    set ::argc [llength $arguments]
    uplevel #0 [list source $script]
}
proc cache_record {label checkpoint} {
    set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    lappend ::cache_records [list $label $setup $hold $checkpoint]
    set fd [open [file join $::cache_output timing_trials.csv] w]
    puts $fd "trial,wns_ns,whs_ns,checkpoint"
    foreach row $::cache_records {puts $fd [join $row ,]}
    close $fd
    puts "CACHE_PHYSICAL_RESULT label=$label setup=$setup hold=$hold"
    return [expr {$setup >= 0.0 && $hold >= 0.0}]
}
proc cache_best {} {
    set best [lindex $::cache_records 0]
    foreach row $::cache_records {
        if {[lindex $row 1] > [lindex $best 1]} {set best $row}
    }
    return [lindex $best 3]
}
proc cache_finish {checkpoint} {
    close_project
    cache_run [file join $::cache_scripts final_gate.tcl] \
        [list $checkpoint [file join $::cache_output final_audit] 18]
    puts "CACHE_FLOW_100MHZ_PASS checkpoint=$checkpoint"
}

cache_run [file join $cache_scripts .. mlu_bram_20261118 equiv.tcl] \
    [list $cache_source $cache_netlist [file join $cache_output equiv_netlist]]
close_project
cache_run [file join $cache_scripts synth_top.tcl] \
    [list $cache_source [file join $cache_output synthesis]]
report_drc -checks [get_drc_checks REQP-1839] -file bram_control_synth.rpt
set fd [open bram_control_synth.rpt r]
set cache_control_drc [read $fd]
close $fd
if {![regexp {Violations found:\s*0\s} $cache_control_drc]} {
    error "BRAM control DRC failed before implementation"
}
close_project
cache_run [file join $cache_scripts reimplement.tcl] \
    [list [file join $cache_output synthesis synthesized.dcp] \
          [file join $cache_output initial] WLDrivenBlockPlacement]
set cache_initial [file join $cache_output initial routed.dcp]
if {[cache_record initial $cache_initial]} {
    cache_finish $cache_initial
} else {
    close_project
    if {[catch {
        cache_run [file join $cache_scripts replicate_measured.tcl] \
            [list $cache_initial [file join $cache_output targeted]]
    } cache_replication_error]} {
        set fd [open [file join $cache_output targeted_error.txt] w]
        puts $fd $cache_replication_error
        close $fd
        puts "CACHE_REPLICATION_NOT_COMPLETED $cache_replication_error"
        catch {close_project}
        open_checkpoint $cache_initial
        set cache_target_closed 0
    } else {
        set cache_target [file join $cache_output targeted replicated routed.dcp]
        set cache_target_closed [cache_record targeted $cache_target]
    }
    if {$cache_target_closed} {
        cache_finish $cache_target
    } else {
        set cache_refine_input [cache_best]
        close_project
        cache_run [file join $cache_repo experiments clock_control refine_route.tcl] \
            [list $cache_refine_input [file join $cache_output refined] 10.000]
        set cache_refined [file join $cache_output refined routed.dcp]
        if {[cache_record refined $cache_refined]} {
            cache_finish $cache_refined
        } else {
            set fd [open [file join $cache_output INCOMPLETE.txt] w]
            puts $fd "100 MHz timing NOT closed. Best completed checkpoint: [cache_best]"
            close $fd
            puts "CACHE_FLOW_INCOMPLETE best=[cache_best]"
        }
    }
}
