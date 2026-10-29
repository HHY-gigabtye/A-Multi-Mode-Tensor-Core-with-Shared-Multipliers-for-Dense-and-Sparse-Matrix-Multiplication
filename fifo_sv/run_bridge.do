# ModelSim / Questa: run this script from the Transcript using do <path>.
# Unit test only: the DUT is du_tc_bridge; tensor_core_pkg supplies types.
cd [file dirname [file normalize [info script]]]
onerror {quit -f -code 1}
if {![file isdirectory bridge_work]} {vlib bridge_work}
vmap bridge_work bridge_work
vlog -sv -work bridge_work tensor_core_pkg.sv du_tc_bridge_pkg.sv du_tc_bridge.sv tb_bridge.sv
vsim -onfinish stop -voptargs=+acc bridge_work.tb_bridge
log -r /*
add wave sim:/tb_bridge/clk sim:/tb_bridge/rst_n
add wave sim:/tb_bridge/issue sim:/tb_bridge/can_issue
add wave sim:/tb_bridge/du_valid sim:/tb_bridge/head_valid sim:/tb_bridge/tc_accept
add wave sim:/tb_bridge/result_meta_valid sim:/tb_bridge/result_accept
add wave -radix unsigned sim:/tb_bridge/fifo_count sim:/tb_bridge/inflight_count sim:/tb_bridge/result_meta_count
add wave sim:/tb_bridge/status sim:/tb_bridge/dut/q
run -all
