# Run from the extracted package root: do sim/run_msu.do
# A dedicated work library avoids changing the user's existing work library.
set msu_root [file normalize "C:/Users/Jason/Desktop/TC/msu_sv"]
cd $msu_root

puts "Current directory: [pwd]"
puts "Package exists: [file exists rtl/msu_pkg.sv]"
puts "Module exists: [file exists rtl/msu.sv]"
puts "Testbench exists: [file exists tb/tb_msu.sv]"
onerror {quit -code 1 -force}
if {![file isdirectory build]} {file mkdir build}
if {![file isdirectory results]} {file mkdir results}
transcript file results/modelsim.log
if {![file isdirectory build/msu_work]} {vlib build/msu_work}
vmap msu_work build/msu_work
vlog -sv -work msu_work rtl/msu_pkg.sv rtl/msu.sv tb/tb_msu.sv
vsim -voptargs=+acc msu_work.tb_msu +VECTORS=vectors/msu_vectors.txt
onfinish stop
log -r /tb_msu/dut/*
if {![batch_mode]} {
    add wave -divider {Clock / reset}
    add wave /tb_msu/clk /tb_msu/rst_n
    add wave -divider {TC to MSU}
    add wave /tb_msu/result_valid /tb_msu/result_ready /tb_msu/result_meta
    add wave -divider {MSU to memory}
    add wave /tb_msu/write_valid /tb_msu/write_ready /tb_msu/write_last
    add wave -radix hexadecimal /tb_msu/write_addr /tb_msu/write_data /tb_msu/write_meta
    add wave -divider {State and events}
    add wave /tb_msu/buffer_count /tb_msu/head_index /tb_msu/row_index
    add wave /tb_msu/events /tb_msu/status /tb_msu/phase
}
run -all
if {![batch_mode]} {wave zoom full}
