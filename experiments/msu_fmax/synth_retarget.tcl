# Fresh synthesis at the baseline period, then new physical implementation at
# the requested target. Comparable with retargeting the baseline synth DCP.
# Arguments: SOURCE_DIR NEW_SYNTH_DIR NEW_IMPL_DIR SYNTH_PERIOD IMPL_PERIOD
if {$argc != 5} {error "Expected SOURCE_DIR NEW_SYNTH_DIR NEW_IMPL_DIR SYNTH_PERIOD IMPL_PERIOD"}
set run_root [file normalize [file join [file dirname [info script]] ../..]]
set run_source [file normalize [lindex $argv 0]]
set run_synth [file normalize [lindex $argv 1]]
set run_impl [file normalize [lindex $argv 2]]
set run_synth_period [lindex $argv 3]
set run_impl_period [lindex $argv 4]
if {[file exists $run_synth] || [file exists $run_impl]} {error "Use new output directories"}
file mkdir $run_synth
cd $run_synth
set_param general.maxThreads 4
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
} {read_verilog -sv [file join $run_source $src]}
set clock_file [open clock.xdc w]
puts $clock_file "create_clock -period $run_synth_period -name clk \[get_ports clk\]"
close $clock_file
read_xdc clock.xdc
synth_design -top sparse_tensor_core_top -part xc7z020clg484-1 -mode out_of_context
write_checkpoint synthesized.dcp
report_utilization -file utilization_synth.rpt
report_timing_summary -max_paths 10 -file timing_synth.rpt
close_project
set argv [list [file join $run_synth synthesized.dcp] $run_impl $run_impl_period]
source [file join $run_root experiments msu_fmax retarget.tcl]
puts "MSU_FMAX_SYNTH_RETARGET_COMPLETE source=$run_source synth=$run_synth_period implementation=$run_impl_period"
