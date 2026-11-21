# Read immutable original tests/vectors; substitute only snapshot RTL/packages.
set repo [file normalize $::env(MLU_BRAM_REPO)]
set source_root [file normalize $::env(MLU_BRAM_SOURCE)]
set output_root [file normalize $::env(MLU_BRAM_OUTPUT)]
set test_case $::env(MLU_BRAM_CASE)
set build [file join $output_root build $test_case]
file mkdir $build
cd $build
onerror {quit -f -code 1}
onbreak {}
proc resolve_source {relative} {
    global repo source_root
    if {[file exists [file join $source_root $relative]]} {return [file join $source_root $relative]}
    return [file join $repo $relative]
}
if {$test_case eq "top"} {
    vlib work
    vmap work work
    foreach src {
        du_tia_sv/rtl/du_tia_pkg.sv mlu_sv/mlu_pkg.sv
        tensor_core_sv/tensor_core_pkg.sv fifo_sv/du_tc_bridge_pkg.sv
        msu_sv/rtl/msu_pkg.sv mlu_sv/mlu.sv du_tia_sv/rtl/du_tia.sv
        fifo_sv/du_tc_bridge.sv tensor_core_sv/tensor_core.sv
        msu_sv/rtl/msu.sv integration_sv/rtl/sparse_tensor_core_top.sv
        integration_sv/tb/tb_sparse_tensor_core_top.sv
    } {vlog -sv -work work [resolve_source $src]}
    vsim -onfinish stop -voptargs=+acc work.tb_sparse_tensor_core_top
    run -all
    if {[examine -radix unsigned /tb_sparse_tensor_core_top/passed] != 1} {quit -f -code 1}
} else {
    set cases [list \
      [list mlu tb_mlu {mlu_sv/du_tia_pkg.sv mlu_sv/mlu_pkg.sv mlu_sv/mlu.sv mlu_sv/tb_mlu.sv} mlu_sv/mlu_vectors.txt] \
      [list du_tia tb_du_tia {du_tia_sv/rtl/du_tia_pkg.sv du_tia_sv/rtl/du_tia.sv du_tia_sv/tb/tb_du_tia.sv} {}] \
      [list bridge tb_bridge {fifo_sv/tensor_core_pkg.sv fifo_sv/du_tc_bridge_pkg.sv fifo_sv/du_tc_bridge.sv fifo_sv/tb_bridge.sv} fifo_sv/vectors/bridge_vectors.txt] \
      [list tc tb_tensor_core {tensor_core_sv/tensor_core_pkg.sv tensor_core_sv/tensor_core.sv tensor_core_sv/tb_tensor_core.sv} tensor_core_sv/c_vectors.txt] \
      [list msu tb_msu {msu_sv/rtl/msu_pkg.sv msu_sv/rtl/msu.sv msu_sv/tb/tb_msu.sv} msu_sv/vectors/msu_vectors.txt]]
    foreach spec $cases {
        lassign $spec name tb sources vectors
        if {$test_case eq "mlu" && $name ne "mlu"} {continue}
        set lib unit_${name}
        vlib $lib
        vmap $lib $lib
        foreach src $sources {vlog -sv -work $lib [resolve_source $src]}
        if {$vectors eq {}} {
            vsim -onfinish stop ${lib}.${tb}
        } else {
            vsim -onfinish stop ${lib}.${tb} +VECTORS=[file join $repo $vectors]
        }
        run -all
        quit -sim
    }
}
quit -f -code 0
