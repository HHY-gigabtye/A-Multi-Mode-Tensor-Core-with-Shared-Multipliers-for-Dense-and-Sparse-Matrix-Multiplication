# In ModelSim/Questa: do C:/path/to/mlu_sv/run_mlu.do
# Standalone MLU unit test; sim.f contains no DU/TIA RTL.
set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
onerror {abort all}
if {![file isdirectory work]} {vlib work}
vmap work work
vlog -sv -f sim.f
vsim -voptargs=+acc work.tb_mlu +VECTORS=mlu_vectors.txt
onfinish stop
log -r /*
do wave_mlu.do
run -all
