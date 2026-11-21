# Independently reopen a completed checkpoint, preserving every audit report.
# This script exits with an error unless the 10 ns internal STA target passes.
if {$argc < 2 || $argc > 3} {error "Expected ROUTED_DCP NEW_OUTPUT_DIR ?BRAM_COUNT?"}
set gate_dir [file normalize [file dirname [info script]]]
set gate_input [file normalize [lindex $argv 0]]
set gate_output [file normalize [lindex $argv 1]]
set gate_bram_count 36
if {$argc == 3} {set gate_bram_count [lindex $argv 2]}
if {$gate_bram_count ni {18 36}} {error "Unexpected BRAM count"}
set argv [list $gate_input $gate_output $gate_bram_count]
set argc 3
source [file join $gate_dir .. mlu_bram_20261118 audit.tcl]
foreach ram $brams {
    set configuration {
        RAM_MODE TDP READ_WIDTH_A 36 READ_WIDTH_B 36
        WRITE_WIDTH_A 36 WRITE_WIDTH_B 36 DOA_REG 0 DOB_REG 0
        WRITE_MODE_A WRITE_FIRST WRITE_MODE_B WRITE_FIRST
    }
    if {$gate_bram_count == 18} {
        set configuration {
            RAM_MODE SDP READ_WIDTH_A 72 READ_WIDTH_B 0
            WRITE_WIDTH_A 0 WRITE_WIDTH_B 72 DOA_REG 0 DOB_REG 0
            WRITE_MODE_A READ_FIRST WRITE_MODE_B READ_FIRST
        }
    }
    foreach {property expected} $configuration {
        if {[get_property $property $ram] ne $expected} {
            error "Primitive configuration changed: $ram / $property"
        }
    }
}
if {[llength $dsps] != 128} {error "Expected original 128 DSP48E1"}
set preg_counts [dict create 0 0 1 0]
foreach dsp $dsps {
    foreach property {AREG BREG MREG} {
        if {[get_property $property $dsp] != 0} {error "DSP stage changed: $dsp / $property"}
    }
    dict incr preg_counts [get_property PREG $dsp]
}
if {[dict get $preg_counts 0] != 64 || [dict get $preg_counts 1] != 64} {
    error "DSP output pipeline configuration changed"
}
set full_drc_errors [get_drc_violations -filter {SEVERITY == Error}]
if {[llength $full_drc_errors] != 0} {error "DRC errors present: $full_drc_errors"}
report_exceptions -file exceptions.rpt
report_drc -checks [get_drc_checks REQP-1839] -file bram_control_drc.rpt
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
if {$setup < 0 || $hold < 0} {error "Timing target failed: setup=$setup hold=$hold"}
set fd [open route_status.rpt r]
set route_report [read $fd]
close $fd
foreach {pattern variable} {
    {# of routable nets\.+\s*:\s*(\d+)} routable
    {# of fully routed nets\.+\s*:\s*(\d+)} routed
    {# of nets with routing errors\.+\s*:\s*(\d+)} route_errors
} {
    if {![regexp $pattern $route_report all $variable]} {error "Missing route status: $pattern"}
}
if {$routed != $routable || $route_errors != 0} {error "Incomplete or erroneous routing"}
set fd [open bram_control_drc.rpt r]
set bram_report [read $fd]
close $fd
if {![regexp {Violations found:\s*0\s} $bram_report]} {error "BRAM control DRC did not pass"}
set fd [open PASS.txt w]
puts $fd "PASS internal FPGA OOC post-route STA, 10.000 ns"
puts $fd "setup_slack_ns=$setup hold_slack_ns=$hold routed_nets=$routed"
puts $fd "$gate_bram_count RAMB36E1; REQP-1839 violations=0; routing errors=0"
close $fd
puts "BRAM_100MHZ_FINAL_GATE_PASS setup=$setup hold=$hold routed=$routed"
