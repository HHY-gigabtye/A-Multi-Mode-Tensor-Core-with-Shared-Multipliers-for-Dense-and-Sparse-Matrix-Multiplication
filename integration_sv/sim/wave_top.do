set tb /tb_sparse_tensor_core_top
add wave -divider {Clock and command}
add wave $tb/clk $tb/rst_n $tb/command_valid $tb/command_ready $tb/command
add wave -divider {Memory read}
add wave $tb/read_request_valid $tb/read_request_ready $tb/read_addr $tb/read_beats
add wave $tb/read_data_valid $tb/read_data_ready $tb/read_data $tb/read_last
add wave -divider {DU pipeline and bridge credits}
add wave $tb/dut/issue $tb/dut/du_valid $tb/dut/can_issue
add wave -radix unsigned $tb/dut/fifo_count $tb/dut/inflight_count $tb/dut/result_meta_count
add wave -divider {TC input and result}
add wave $tb/dut/head_valid $tb/dut/head_entry $tb/dut/tc_in_ready $tb/dut/tc_accept
add wave $tb/dut/tc_result_valid $tb/dut/tc_result_ready $tb/dut/result_accept
add wave $tb/dut/result_meta $tb/dut/tc_result
add wave -divider {Memory write and completion}
add wave $tb/write_valid $tb/write_ready $tb/write_addr $tb/write_data $tb/write_last
add wave $tb/write_meta $tb/tile_done $tb/completed
add wave -divider {Status and test progress}
add wave $tb/mlu_status $tb/bridge_status $tb/tc_status $tb/msu_status
add wave -radix unsigned $tb/epoch $tb/cycle $tb/dones
