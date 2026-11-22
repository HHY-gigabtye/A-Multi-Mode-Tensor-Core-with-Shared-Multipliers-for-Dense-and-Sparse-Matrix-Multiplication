if {$argc != 2} {error "Expected DU_RTL NEW_OUTPUT"}
set root [file normalize [file dirname [info script]]]
set rtl [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
if {[file exists $out]} {error "Preserve existing run"}
file mkdir $out
cd $out
set_param general.maxThreads 2
create_project -in_memory -part xc7z020clg484-1
read_verilog -sv [file join $root ../../baseline/src/du_tia_sv/rtl/du_tia_pkg.sv]
read_verilog -sv $rtl
read_verilog -sv [file join $root du_gate.sv]
synth_design -top du_gate -part xc7z020clg484-1 -mode out_of_context
create_clock -period 10 [get_ports clk]
write_checkpoint synthesized.dcp
write_verilog -mode funcsim unit_netlist.v
report_utilization -hierarchical -file utilization.rpt
puts "DU_UNIT_SYNTH_COMPLETE"
