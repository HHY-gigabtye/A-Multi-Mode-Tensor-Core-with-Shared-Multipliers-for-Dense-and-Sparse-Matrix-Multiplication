if {$argc != 1} {error "Expected variant"}
set variant [lindex $argv 0]
if {$variant ni {baseline candidate_v2}} {error "Bad variant"}
set root [file normalize [file dirname [info script]]]
set out [file join $root $variant routed_functional.v]
if {[file exists $out]} {error "Preserve existing netlist"}
set_param general.maxThreads 2
open_checkpoint [file join $root .. $variant routed routed.dcp]
write_verilog -mode funcsim $out
puts "POWER_FUNCTIONAL_EXPORT_PASS $variant"
