# Reopen each routed netlist in memory and probe adjacent 10 ps clock periods.
# This is a timing check of fixed placements/routes; there is no reimplementation.
if {$argc != 3} {error "Expected BASELINE_DCP CANDIDATE_DCP NEW_REPORT_DIRECTORY"}
set checkpoints [list [file normalize [lindex $argv 0]] [file normalize [lindex $argv 1]]]
set output [file normalize [lindex $argv 2]]
if {[file exists $output]} {error "Select a fresh report directory"}
file mkdir $output
set report [open [file join $output periods.csv] w]
puts $report "design,period_ns,mhz,setup_slack_ns,hold_slack_ns"
foreach name {baseline candidate} checkpoint $checkpoints {
    open_checkpoint $checkpoint
    set clock [get_clocks clk]
    if {[llength [get_clocks]] != 1 || [get_property PERIOD $clock] != 10} {
        error "Expected the 10 ns single-clock implementation"
    }
    set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set boundary [expr {ceil((10.0 - $wns) * 100.0) / 100.0}]
    foreach label {longer shorter} offset {0.0 -0.01} {
        set period [format %.3f [expr {$boundary + $offset}]]
        create_clock -name clk -period $period -waveform [list 0 [expr {$period / 2.0}]] [get_ports clk]
        set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
        set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
        puts $report "$name,$period,[format %.4f [expr {1000.0/$period}]],$setup,$hold"
        flush $report
        report_timing_summary -max_paths 1 -file [file join $output ${name}_${label}.rpt]
    }
    close_design
}
close $report
