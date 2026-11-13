# In the ModelSim Transcript window:
#   do C:/your/path/tensor_core_sv/run_modelsim.do
# All relative paths are resolved against this script, not the GUI directory.
set tc_script_dir [file dirname [file normalize [info script]]]
cd $tc_script_dir
onerror {abort}
if {![file isdirectory work]} {vlib work}
vmap work work
vlog -sv tensor_core_pkg.sv tensor_core.sv tb_tensor_core.sv
vsim -onfinish stop -voptargs=+acc work.tb_tensor_core +VECTORS=c_vectors.txt
do waves.do
run -all
