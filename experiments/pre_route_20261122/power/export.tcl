if {$argc != 1} {error "Expected baseline or candidate_v2"}
set variant [lindex $argv 0]
if {$variant ni {baseline candidate_v2}} {error "Bad variant"}
set root [file normalize [file dirname [info script]]]
set out [file join $root $variant]
if {[file exists $out]} {error "Preserve existing export: $out"}
file mkdir $out
set_param general.maxThreads 2
open_checkpoint [file join $root .. $variant routed routed.dcp]
write_verilog -mode timesim -sdf_anno false [file join $out routed.v]
write_sdf -process_corner slow [file join $out routed.sdf]
report_clocks -file [file join $out clocks.rpt]
puts "POWER_EXPORT_PASS $variant"
