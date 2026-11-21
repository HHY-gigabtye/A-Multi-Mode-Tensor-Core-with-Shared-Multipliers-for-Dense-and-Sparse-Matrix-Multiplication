onerror {quit -f -code 1}
onbreak {}
set trial [file normalize $::env(OUTER_TRIAL)]
set repo [file normalize [file join $trial ../..]]
set case $::env(OUTER_CASE)
set out [file join $trial build $case]
file mkdir $out
cd $out
if {![file isdirectory work]} {vlib work}
vmap work work
vlog -sv [file join $repo tensor_core_sv/tensor_core_pkg.sv] [file join $trial outer_product_core.sv]
if {$case eq "unit"} {
    set tb tb_outer_core
    vlog -sv [file join $trial tb_outer_core.sv]
    vsim -onfinish stop -voptargs=+acc work.$tb +VECTORS=[file join $repo tensor_core_sv/c_vectors.txt]
} elseif {$case eq "top"} {
    set tb tb_sparse_tensor_core_top
    foreach f {du_tia_sv/rtl/du_tia_pkg.sv mlu_sv/mlu_pkg.sv fifo_sv/du_tc_bridge_pkg.sv
        msu_sv/rtl/msu_pkg.sv mlu_sv/mlu.sv du_tia_sv/rtl/du_tia.sv fifo_sv/du_tc_bridge.sv msu_sv/rtl/msu.sv} {
        vlog -sv [file join $repo $f]
    }
    vlog -sv [file join $trial sparse_tensor_core_top.sv] [file join $trial tb_outer_top.sv]
    vsim -onfinish stop -voptargs=+acc work.$tb
} elseif {$case eq "compare"} {
    set tb tb_compare
    vlog -sv [file join $repo tensor_core_sv/tensor_core.sv] [file join $trial tb_compare.sv]
    vsim -onfinish stop -voptargs=+acc work.$tb
} else {error "Expected unit, top or compare"}
run -all
if {[examine -radix unsigned /$tb/passed] != 1} {quit -f -code 1}
quit -f -code 0
