# Standalone synthesis and observable-cycle comparison against immutable RTL/C.
if {$argc != 2} {error "Expected SOURCE_SNAPSHOT NEW_OUTPUT_DIR"}
set bn_scripts [file normalize [file dirname [info script]]]
set bn_repo [file normalize [file join $bn_scripts ../..]]
set bn_source [file normalize [lindex $argv 0]]
set bn_output [file normalize [lindex $argv 1]]
if {[file exists $bn_output]} {error "Preserve earlier bridge proof"}
file mkdir $bn_output
cd $bn_output
set_param general.maxThreads 1
create_project -in_memory -part xc7z020clg484-1
foreach src {tensor_core_sv/tensor_core_pkg.sv fifo_sv/du_tc_bridge_pkg.sv fifo_sv/du_tc_bridge.sv} {
    read_verilog -sv [file join $bn_source $src]
}
read_verilog -sv [file join $bn_scripts bridge_flat.sv]
set fd [open clock.xdc w]
puts $fd {create_clock -period 10.000 -name clk [get_ports clk]}
close $fd
read_xdc clock.xdc
synth_design -top bridge_flat -part xc7z020clg484-1 -mode out_of_context
write_checkpoint synthesized.dcp
report_utilization -file utilization.rpt
report_timing_summary -max_paths 10 -file timing.rpt
write_verilog -mode funcsim -rename_top bridge_flat_netlist bridge_flat_netlist.v
close_project
set fd [open [file join $bn_repo experiments mlu_bram_20261118 baseline src fifo_sv du_tc_bridge.sv] r]
set bn_original [read $fd]
close $fd
if {[regsub {module du_tc_bridge \(} $bn_original {module du_tc_bridge_reference (} bn_reference] != 1} {
    error "Expected original Bridge module declaration"
}
set fd [open du_tc_bridge_reference.sv w]
puts -nonewline $fd $bn_reference
close $fd
create_project bridge_sim [file join $bn_output project] -part xc7z020clg484-1
set_property target_simulator XSim [current_project]
add_files -fileset sim_1 [list \
    [file join $bn_source tensor_core_sv tensor_core_pkg.sv] \
    [file join $bn_source fifo_sv du_tc_bridge_pkg.sv] \
    [file join $bn_output du_tc_bridge_reference.sv] \
    [file join $bn_output bridge_flat_netlist.v] \
    [file join $bn_scripts tb_bridge_netlist.sv]]
set_property top tb_bridge_netlist [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property -dict [list xsim.simulate.xsim.more_options \
    "-testplusarg VECTORS=[file join $bn_repo fifo_sv vectors bridge_vectors.txt]"] [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
close_sim
set transcript [file join $bn_output project bridge_sim.sim sim_1 behav xsim simulate.log]
set fd [open $transcript r]
set body [read $fd]
close $fd
if {[string first {BRIDGE NETLIST EQUIVALENCE PASS rows=19147} $body] < 0 ||
    [regexp -nocase {Fatal:|Error:|\$fatal} $body]} {error "Bridge netlist comparison failed"}
file copy $transcript [file join $bn_output result.log]
puts "BRIDGE_NETLIST_CHECK_COMPLETE"
