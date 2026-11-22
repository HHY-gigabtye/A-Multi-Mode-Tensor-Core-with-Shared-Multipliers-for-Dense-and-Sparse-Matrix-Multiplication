# Independently reopen both completed checkpoints; preserve all measured data.
if {$argc != 3} {error "Expected BASELINE_DCP CANDIDATE_DCP NEW_OUTPUT"}
set trial [file normalize [file dirname [info script]]]
set repo [file normalize [file join $trial ../..]]
set checkpoints [list [file normalize [lindex $argv 0]] [file normalize [lindex $argv 1]]]
set output [file normalize [lindex $argv 2]]
if {[file exists $output]} {error "Preserve previous audit: $output"}
file mkdir $output
source [file join $repo project_integration scripts check_bram_100mhz.tcl]
set points [open [file join $output periods.csv] w]
puts $points "variant,period_ns,mhz,setup_slack_ns,hold_slack_ns"
set results [open [file join $output audit_summary.txt] w]
foreach name {baseline candidate_v2} checkpoint $checkpoints {
    open_checkpoint $checkpoint
    set folder [file join $output $name]
    if {[catch {check_bram_100mhz $folder} message]} {
        set failure [open [file join $folder FAIL.txt] w]
        puts $failure $message
        close $failure
        puts $results "${name}: 100 MHz audit FAIL: $message"
    } else {
        puts $results "${name}: 100 MHz audit PASS"
    }
    set tc_cells [get_cells -hier -filter {NAME =~ u_tensor_core/* && IS_SEQUENTIAL}]
    report_timing -from $tc_cells -to $tc_cells -max_paths 10 -input_pins -file [file join $folder tc_internal_paths.rpt]
    set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set boundary [expr {ceil((10.0 - $wns) * 100.0) / 100.0}]
    foreach label {longer shorter} offset {0.0 -0.01} {
        set period [format %.3f [expr {$boundary + $offset}]]
        create_clock -name clk -period $period -waveform [list 0 [expr {$period / 2.0}]] [get_ports clk]
        set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
        set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
        puts $points "$name,$period,[format %.4f [expr {1000.0/$period}]],$setup,$hold"
        flush $points
        report_timing_summary -max_paths 3 -file [file join $output ${name}_${label}.rpt]
    }
    close_design
}
close $points
close $results
puts "PRE_ROUTE_INDEPENDENT_AUDIT_COMPLETE"
