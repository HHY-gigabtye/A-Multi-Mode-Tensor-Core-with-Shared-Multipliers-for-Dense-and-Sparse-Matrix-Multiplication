# Reopen saved implementations without modifying the measured constraints.
if {$argc != 3} {error "Expected BASELINE_DCP CANDIDATE_DCP NEW_OUTPUT"}
set trial [file normalize [file dirname [info script]]]
set repo [file normalize [file join $trial ../..]]
set output [file normalize [lindex $argv 2]]
if {[file exists $output]} {error "Preserve previous audit"}
file mkdir $output
source [file join $repo project_integration scripts check_bram_100mhz.tcl]
set summary [open [file join $output summary.txt] w]
set failed 0
foreach name {baseline candidate} path [lrange $argv 0 1] {
  open_checkpoint [file normalize $path]
  set folder [file join $output $name]
  if {[catch {check_bram_100mhz $folder} message]} {
    set failed 1
    set fd [open [file join $folder FAIL.txt] w]
    puts $fd $message
    close $fd
    puts $summary "$name FAIL: $message"
  } else {puts $summary "$name PASS: internal FPGA OOC 100 MHz"}
  report_utilization -hierarchical -file [file join $folder hierarchy.rpt]
  set cells [get_cells -hier -filter {NAME =~ u_tensor_core/* && IS_SEQUENTIAL}]
  report_timing -from $cells -to $cells -max_paths 10 -input_pins -file [file join $folder tc_internal_paths.rpt]
  close_design
}
close $summary
if {$failed} {error "At least one 100 MHz audit failed"}
puts "TC19_AUDIT_PASS"
