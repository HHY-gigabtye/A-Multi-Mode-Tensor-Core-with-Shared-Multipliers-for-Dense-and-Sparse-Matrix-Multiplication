# Select physical replication targets from this checkpoint's own measured
# high-fanout report. No retiming, functional RTL change, or timing exception.
if {$argc != 2} {error "Expected ROUTED_DCP NEW_OUTPUT_DIR"}
set task_script_dir [file normalize [file dirname [info script]]]
set task_repo [file normalize [file join $task_script_dir ../..]]
set task_input [file normalize [lindex $argv 0]]
set task_output [file normalize [lindex $argv 1]]
if {[file exists $task_output]} {error "Preserve previous physical trial"}
file mkdir $task_output
cd $task_output
set_param general.maxThreads 4
open_checkpoint $task_input
if {[llength [get_clocks]] != 1 || abs([get_property PERIOD [get_clocks clk]] - 10.0) > 0.000001} {
    error "Expected original 10.000 ns clock"
}
report_high_fanout_nets -max_nets 100 -timing -load_types -file measured_fanout.rpt
set fd [open measured_fanout.rpt r]
set lines [split [read $fd] \n]
close $fd
set drivers {}
set fd [open selection.tsv w]
puts $fd "net\tfanout\tslack_ns\tdriver"
foreach line $lines {
    set cols [split $line |]
    if {[llength $cols] < 7} {continue}
    set netname [string trim [lindex $cols 1]]
    set fanout [string trim [lindex $cols 2]]
    set type [string trim [lindex $cols 3]]
    set slack [string trim [lindex $cols 4]]
    if {![string is integer -strict $fanout] || ![string match LUT* $type] ||
        ![string is double -strict $slack] || $slack >= 0.0 || $fanout < 128} {continue}
    set net [get_nets -hierarchical -filter [format {NAME == "%s"} $netname]]
    if {[llength $net] != 1} {error "Missing measured net: $netname"}
    set pins [get_pins -leaf -of_objects [get_nets -segments $net] -filter {DIRECTION == OUT}]
    set driver [get_cells -of_objects $pins -filter {REF_NAME =~ LUT*}]
    if {[llength $driver] != 1} {error "Expected one LUT driver: $netname"}
    set name [get_property NAME $driver]
    lappend drivers $name
    puts $fd "$netname\t$fanout\t$slack\t$name"
}
# Also inspect long routed segments on the worst paths. A 10..50 sink
# control net can be slow despite being absent from the high-fanout list.
report_timing -delay_type max -max_paths 100 -input_pins -file measured_paths.rpt
set pf [open measured_paths.rpt r]
set path_lines [split [read $pf] \n]
close $pf
set path_driver ""
set path_slack 0.0
foreach line $path_lines {
    if {[regexp {^Slack \([^)]*\)\s*:\s*(-?[0-9.]+)ns} $line all path_slack]} {
        set path_driver ""
    }
    if {[regexp {LUT[1-6]\s+\(Prop_.*\s([^\s]+)/O\s*$} $line all name]} {
        set path_driver $name
        continue
    }
    if {[regexp {net \(fo=([0-9]+), routed\)\s+([0-9.]+)\s} $line all fanout delay]} {
        if {$path_slack < 0 && $path_driver ne "" && $fanout >= 8 && $delay >= 0.800} {
            set cell [get_cells -hierarchical -filter [format {NAME == "%s"} $path_driver]]
            if {[llength $cell] != 1 || ![string match LUT* [get_property REF_NAME $cell]]} {
                error "Missing measured path driver: $path_driver"
            }
            lappend drivers $path_driver
            puts $fd "critical_path_segment_${delay}ns\t$fanout\t$path_slack\t$path_driver"
        }
        set path_driver ""
    }
}
close $fd
set drivers [lsort -unique $drivers]
if {[llength $drivers] == 0} {error "No failing high-fanout LUT drivers found"}
set names_file [file join $task_output drivers.txt]
set fd [open $names_file w]
puts $fd [join $drivers \n]
close $fd
puts "MEASURED_SELECTION_COMPLETE drivers=[llength $drivers]"
close_project
set argv [list $task_input [file join $task_output replicated] $names_file]
set argc 3
source [file join $task_repo experiments msu_fmax target_11ns_20261109 replicate_drivers.tcl]
