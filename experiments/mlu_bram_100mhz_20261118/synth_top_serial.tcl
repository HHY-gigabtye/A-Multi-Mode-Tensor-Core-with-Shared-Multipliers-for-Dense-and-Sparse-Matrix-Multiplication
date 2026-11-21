# Synthesize a frozen candidate independently of subsequent physical recipes.
# Limit synthesis threads to reduce simultaneous memory demand. Device,
# source order, optimization defaults and the 10 ns clock are unchanged.
if {$argc != 2} {error "Expected SOURCE_SNAPSHOT NEW_OUTPUT_DIR"}
set task_source [file normalize [lindex $argv 0]]
set task_output [file normalize [lindex $argv 1]]
if {[file exists $task_output]} {error "Preserve previous synthesis"}
file mkdir $task_output
cd $task_output
set_param general.maxThreads 1
create_project -in_memory -part xc7z020clg484-1
set_property target_language Verilog [current_project]
foreach src {
    tensor_core_sv/tensor_core_pkg.sv
    fifo_sv/du_tc_bridge_pkg.sv
    fifo_sv/du_tc_bridge.sv
    du_tia_sv/rtl/du_tia_pkg.sv
    du_tia_sv/rtl/du_tia.sv
    mlu_sv/mlu_pkg.sv
    mlu_sv/mlu.sv
    msu_sv/rtl/msu_pkg.sv
    msu_sv/rtl/msu.sv
    tensor_core_sv/tensor_core.sv
    integration_sv/rtl/sparse_tensor_core_top.sv
} {read_verilog -sv [file join $task_source $src]}
set fd [open clock.xdc w]
puts $fd {create_clock -period 10.000 -name clk [get_ports clk]}
close $fd
read_xdc clock.xdc
synth_design -top sparse_tensor_core_top -part xc7z020clg484-1 -mode out_of_context
write_checkpoint synthesized.dcp
report_utilization -file utilization_synth.rpt
report_timing_summary -max_paths 20 -file timing_synth.rpt
puts "BRAM_TOP_SYNTH_COMPLETE source=$task_source clock=10.000"

