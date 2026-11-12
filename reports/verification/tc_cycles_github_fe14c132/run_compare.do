# Compare the pinned GitHub RTL and current RTL against the unchanged unit TB.
onerror {quit -f -code 1}
onbreak {}
# ModelSim's do macro does not provide the source path through info script.
set root [file normalize [pwd]]
while {![file exists [file join $root tensor_core_sv tensor_core.sv]]} {
    set parent [file dirname $root]
    if {$parent eq $root} {error "Run from the repository"}
    set root $parent
}
set comparison [file join $root reports verification tc_cycles_github_fe14c132]
set build [file join $comparison build]
file mkdir $build
cd $build
foreach spec {{github github_tensor_core.sv} {current current_tensor_core.sv}} {
    lassign $spec variant rtl
    set lib cycle_$variant
    if {[file isdirectory $lib]} {error "Use a fresh comparison directory"}
    vlib $lib
    vmap $lib $lib
    vlog -sv -work $lib [file join $root tensor_core_sv tensor_core_pkg.sv] \
        [file join $comparison $rtl] [file join $root tensor_core_sv tb_tensor_core.sv]
    puts "CYCLE_COMPARE_BEGIN variant=$variant"
    vsim -onfinish stop ${lib}.tb_tensor_core +VECTORS=[file join $root tensor_core_sv c_vectors.txt]
    run -all
    quit -sim
    puts "CYCLE_COMPARE_END variant=$variant"
}
quit -f -code 0
