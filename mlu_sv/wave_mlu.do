add wave -group Clock sim:/tb_mlu/clk sim:/tb_mlu/rst_n
add wave -group Input -radix hexadecimal sim:/tb_mlu/stimulus
add wave -group Command sim:/tb_mlu/command_ready
add wave -group Read sim:/tb_mlu/read_request_valid sim:/tb_mlu/read_data_ready
add wave -group Read -radix hexadecimal sim:/tb_mlu/read_addr
add wave -group Read -radix unsigned sim:/tb_mlu/read_beats
add wave -group Output sim:/tb_mlu/out_valid
add wave -group Output -radix unsigned sim:/tb_mlu/out_k
add wave -group Output -radix hexadecimal sim:/tb_mlu/out_meta sim:/tb_mlu/out_packet
add wave -group State -radix hexadecimal sim:/tb_mlu/dut/state_q
add wave -group Events sim:/tb_mlu/status sim:/tb_mlu/tick_info
configure wave -namecolwidth 240
configure wave -valuecolwidth 160
