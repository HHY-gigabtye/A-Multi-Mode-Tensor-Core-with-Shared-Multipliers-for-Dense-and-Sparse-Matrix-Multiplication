# Standalone synthesis first, before committing time to integrated placement.
# Usage: SOURCE_SNAPSHOT NEW_OUTPUT_DIR
if {$argc != 2} {error "Expected SOURCE_SNAPSHOT NEW_OUTPUT_DIR"}
set probe_source [file normalize [lindex $argv 0]]
set probe_output [file normalize [lindex $argv 1]]
if {[file exists $probe_output]} {error "Preserve previous output: $probe_output"}
file mkdir $probe_output
cd $probe_output
set_param general.maxThreads 4
create_project -in_memory -part xc7z020clg484-1
foreach src {du_tia_sv/rtl/du_tia_pkg.sv mlu_sv/mlu_pkg.sv mlu_sv/mlu.sv} {
    read_verilog -sv [file join $probe_source $src]
}
set fd [open clock.xdc w]
puts $fd {create_clock -period 10.000 -name clk [get_ports clk]}
close $fd
read_xdc clock.xdc
synth_design -top mlu -part xc7z020clg484-1 -mode out_of_context
write_checkpoint synthesized.dcp
report_utilization -file utilization.rpt
report_utilization -hierarchical -file hierarchy.rpt
report_timing_summary -max_paths 20 -file timing.rpt
write_verilog -mode funcsim -rename_top mlu_netlist mlu_netlist.v
set fd [open memory_cells.txt w]
foreach cell [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}] {
    puts $fd "$cell [get_property REF_NAME $cell]"
    report_property $cell -file [string map {/ _} ${cell}_properties.txt]
}
close $fd
puts "MLU_PROBE_COMPLETE brams=[llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}]]"
