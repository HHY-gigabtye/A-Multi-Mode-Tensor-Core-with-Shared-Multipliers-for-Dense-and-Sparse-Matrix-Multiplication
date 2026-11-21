# Fresh native GUI-compatible runs from main RTL; preserve earlier runs.
# Usage: NEW_REPORT_DIR ?UNUSED_RUN_SUFFIX?
if {$argc < 1 || $argc > 2} {error "Expected NEW_REPORT_DIR ?UNUSED_RUN_SUFFIX?"}
set bram_repo [file normalize [file join [file dirname [info script]] ..]]
set bram_reports [file normalize [lindex $argv 0]]
set bram_suffix outer_100mhz
if {$argc == 2} {set bram_suffix [lindex $argv 1]}
if {![regexp {^[A-Za-z0-9_]+$} $bram_suffix]} {error "Invalid run suffix"}
if {[file exists $bram_reports]} {error "Use a new report directory"}
file mkdir $bram_reports
set bram_synth synth_$bram_suffix
set bram_impl impl_$bram_suffix
set bram_scripts [file join $bram_repo project_integration scripts]
open_project [file join $bram_repo project_integration project_integration.xpr]
if {[get_property PART [current_project]] ne "xc7z020clg484-1"} {error "Unexpected project device"}
if {[get_property TOP [get_filesets sources_1]] ne "sparse_tensor_core_top"} {error "Unexpected top"}
if {$argc == 1} {
    for {set n 1} {[llength [get_runs -quiet $bram_synth]] || [llength [get_runs -quiet $bram_impl]]} {incr n} {
        set bram_synth synth_${bram_suffix}_$n
        set bram_impl impl_${bram_suffix}_$n
    }
}
foreach run [list $bram_synth $bram_impl] {
    if {[llength [get_runs -quiet $run]]} {error "Run exists; choose another suffix: $run"}
}
set bram_expected_sources {}
foreach relative {
    tensor_core_sv/tensor_core_pkg.sv fifo_sv/du_tc_bridge_pkg.sv fifo_sv/du_tc_bridge.sv
    du_tia_sv/rtl/du_tia_pkg.sv du_tia_sv/rtl/du_tia.sv mlu_sv/mlu_pkg.sv mlu_sv/mlu.sv
    msu_sv/rtl/msu_pkg.sv msu_sv/rtl/msu.sv tensor_core_sv/outer_product_core.sv
    integration_sv/rtl/sparse_tensor_core_top.sv
} {lappend bram_expected_sources [file normalize [file join $bram_repo $relative]]}
set bram_actual_sources {}
foreach src [get_files -of_objects [get_filesets sources_1]] {
    lappend bram_actual_sources [file normalize $src]
}
if {[lsort $bram_expected_sources] ne [lsort $bram_actual_sources]} {error "Project must use exactly the 11 main RTL/package sources"}
set bram_constrs constrs_bram_100mhz
set bram_xdc [file join $bram_repo project_integration project_integration.srcs constrs_1 new constraint.xdc]
if {![llength [get_filesets -quiet $bram_constrs]]} {
    create_fileset -constrset $bram_constrs
    add_files -fileset $bram_constrs -norecurse $bram_xdc
}
if {[llength [get_files -of_objects [get_filesets $bram_constrs]]] != 1} {error "Unexpected constraints"}
foreach hook {bram_100mhz_synth_pre.tcl bram_100mhz_impl_pre.tcl bram_100mhz_route_post.tcl check_bram_100mhz.tcl} {
    set path [file join $bram_scripts $hook]
    if {![llength [get_files -quiet $path]]} {add_files -fileset utils_1 -norecurse $path}
}
create_run $bram_synth -part xc7z020clg484-1 -flow {Vivado Synthesis 2022} -strategy {Vivado Synthesis Defaults} -constrset $bram_constrs
create_run $bram_impl -part xc7z020clg484-1 -flow {Vivado Implementation 2022} -strategy {Vivado Implementation Defaults} -constrset $bram_constrs -parent_run $bram_synth
foreach {run property value} [list \
    $bram_synth AUTO_INCREMENTAL_CHECKPOINT 0 \
    $bram_synth INCREMENTAL_CHECKPOINT {} \
    $bram_synth {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} {-mode out_of_context} \
    $bram_synth STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE Default \
    $bram_synth STEPS.SYNTH_DESIGN.TCL.PRE [file join $bram_scripts bram_100mhz_synth_pre.tcl] \
    $bram_impl AUTO_INCREMENTAL_CHECKPOINT 0 \
    $bram_impl INCREMENTAL_CHECKPOINT {} \
    $bram_impl STEPS.INIT_DESIGN.TCL.PRE [file join $bram_scripts bram_100mhz_impl_pre.tcl] \
    $bram_impl STEPS.PHYS_OPT_DESIGN.IS_ENABLED 1 \
    $bram_impl STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Default \
    $bram_impl STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Default \
    $bram_impl STEPS.ROUTE_DESIGN.TCL.POST [file join $bram_scripts bram_100mhz_route_post.tcl] \
    $bram_impl STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED 0] {
    set_property -dict [list $property $value] [get_runs $run]
}
current_run -synthesis [get_runs $bram_synth]
current_run -implementation [get_runs $bram_impl]
close_project
open_project [file join $bram_repo project_integration project_integration.xpr]
set fd [open [file join $bram_reports project_settings.txt] w]
puts $fd "Main RTL sources: $bram_actual_sources"
foreach run [list $bram_synth $bram_impl] {
    foreach property [list_property [get_runs $run]] {
        if {[regexp {CONSTRSET|SRCSET|PARENT|MORE OPTIONS|TCL\.(PRE|POST)$|IS_ENABLED$|ARGS.DIRECTIVE$|STATUS$} $property]} {
            puts $fd "$run $property: [get_property $property [get_runs $run]]"
        }
    }
}
close $fd
update_compile_order -fileset sources_1
launch_runs $bram_synth -jobs 1
wait_on_run $bram_synth
if {[get_property STATUS [get_runs $bram_synth]] ne "synth_design Complete!"} {error "Synthesis failed"}
launch_runs $bram_impl -to_step route_design -jobs 1
wait_on_run $bram_impl
if {[get_property STATUS [get_runs $bram_impl]] ne "route_design Complete!"} {error "Implementation failed"}
open_run $bram_impl
source [file join $bram_scripts check_bram_100mhz.tcl]
check_bram_100mhz [file join $bram_reports reopened_run]
write_checkpoint [file join $bram_reports main_bram_routed.dcp]
close_project
# Audit the saved native checkpoint independently as well.
open_checkpoint [file join $bram_reports main_bram_routed.dcp]
check_bram_100mhz [file join $bram_reports independent_checkpoint]
close_project
puts "GUI_BRAM_100MHZ_BUILD_PASS implementation=$bram_impl"
