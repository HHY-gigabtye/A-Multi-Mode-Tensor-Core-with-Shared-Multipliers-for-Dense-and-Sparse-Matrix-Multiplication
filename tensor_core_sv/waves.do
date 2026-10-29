# Focus on control/stages. Expand dense_q/sparse_q in Objects when inspecting
# the arrays; logging every matrix every cycle can create a large WLF file.
add wave -divider {Input / output}
add wave sim:/tb_tensor_core/clk
add wave sim:/tb_tensor_core/rst_n
add wave sim:/tb_tensor_core/in_valid
add wave sim:/tb_tensor_core/input_ready
add wave sim:/tb_tensor_core/in_ready
add wave sim:/tb_tensor_core/in_packet
add wave sim:/tb_tensor_core/status
add wave sim:/tb_tensor_core/result_ready
add wave sim:/tb_tensor_core/result_valid
add wave sim:/tb_tensor_core/result
add wave sim:/tb_tensor_core/busy
add wave -divider {Tile control / FIFO}
add wave sim:/tb_tensor_core/dut/ctrl_q.busy
add wave sim:/tb_tensor_core/dut/ctrl_q.is_sparse
add wave sim:/tb_tensor_core/dut/ctrl_q.received
add wave sim:/tb_tensor_core/dut/ctrl_q.outstanding
add wave sim:/tb_tensor_core/dut/ctrl_q.result_count
add wave sim:/tb_tensor_core/dut/ctrl_q.finish_pending
add wave -divider {Events on last rising edge}
add wave sim:/tb_tensor_core/tick_info
configure wave -timelineunits ns
wave zoom full
