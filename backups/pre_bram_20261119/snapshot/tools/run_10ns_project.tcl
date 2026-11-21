# Configure and verify fresh native Vivado project runs; preserve old runs.
# Arguments: NEW_REPORT_DIR ?UNUSED_RUN_SUFFIX?
if {$argc < 1 || $argc > 2} {error "Expected NEW_REPORT_DIR ?UNUSED_RUN_SUFFIX?"}
set task_gui_root [file normalize [file join [file dirname [info script]] ..]]
set task_gui_reports [file normalize [lindex $argv 0]]
set task_gui_suffix 10ns
if {$argc == 2} {set task_gui_suffix [lindex $argv 1]}
if {![regexp {^[A-Za-z0-9_]+$} $task_gui_suffix]} {error "Invalid run suffix"}
if {[file exists $task_gui_reports]} {error "Use a new report directory"}
file mkdir $task_gui_reports
set task_gui_synth synth_$task_gui_suffix
set task_gui_impl impl_$task_gui_suffix
set task_gui_scripts [file join $task_gui_root project_integration scripts]
set_param general.maxThreads 4
open_project [file join $task_gui_root project_integration project_integration.xpr]
if {[get_property PART [current_project]] ne "xc7z020clg484-1"} {error "Unexpected part"}
if {[get_property TOP [get_filesets sources_1]] ne "sparse_tensor_core_top"} {error "Unexpected top"}
foreach task_run [list $task_gui_synth $task_gui_impl] {
    if {[llength [get_runs -quiet $task_run]]} {error "Run already exists; choose another suffix: $task_run"}
}
set task_gui_constrs constrs_10ns_impl
set task_gui_xdc [file join $task_gui_root project_integration project_integration.srcs constrs_1 new constraint.xdc]
if {![llength [get_filesets -quiet $task_gui_constrs]]} {create_fileset -constrset $task_gui_constrs}
if {![llength [get_files -quiet -of_objects [get_filesets $task_gui_constrs] $task_gui_xdc]]} {
    add_files -fileset $task_gui_constrs -norecurse $task_gui_xdc
}
set task_gui_constraint_files [get_files -of_objects [get_filesets $task_gui_constrs]]
if {[llength $task_gui_constraint_files] != 1} {error "Unexpected implementation constraint files"}
foreach task_hook {init_12ns.tcl post_route_10ns.tcl} {
    set task_hook_path [file join $task_gui_scripts $task_hook]
    if {![llength [get_files -quiet $task_hook_path]]} {add_files -fileset utils_1 -norecurse $task_hook_path}
}
create_run $task_gui_synth -part xc7z020clg484-1 -flow {Vivado Synthesis 2022} -strategy {Vivado Synthesis Defaults} -constrset $task_gui_constrs
create_run $task_gui_impl -part xc7z020clg484-1 -flow {Vivado Implementation 2022} -strategy {Vivado Implementation Defaults} -constrset $task_gui_constrs -parent_run $task_gui_synth
foreach {task_run task_property task_value} [list \
    $task_gui_synth AUTO_INCREMENTAL_CHECKPOINT 0 \
    $task_gui_synth INCREMENTAL_CHECKPOINT {} \
    $task_gui_synth {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} {-mode out_of_context} \
    $task_gui_synth STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE Default \
    $task_gui_synth STEPS.SYNTH_DESIGN.TCL.PRE [file join $task_gui_scripts init_12ns.tcl] \
    $task_gui_impl AUTO_INCREMENTAL_CHECKPOINT 0 \
    $task_gui_impl INCREMENTAL_CHECKPOINT {} \
    $task_gui_impl STEPS.INIT_DESIGN.TCL.PRE [file join $task_gui_scripts init_12ns.tcl] \
    $task_gui_impl STEPS.PHYS_OPT_DESIGN.IS_ENABLED 1 \
    $task_gui_impl STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Default \
    $task_gui_impl STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Default \
    $task_gui_impl STEPS.ROUTE_DESIGN.TCL.POST [file join $task_gui_scripts post_route_10ns.tcl] \
    $task_gui_impl STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED 0] {
    if {[lsearch -exact [list_property [get_runs $task_run]] $task_property] < 0} {error "Missing run property $task_property"}
    set_property -dict [list $task_property $task_value] [get_runs $task_run]
}
current_run -synthesis [get_runs $task_gui_synth]
current_run -implementation [get_runs $task_gui_impl]
close_project
open_project [file join $task_gui_root project_integration project_integration.xpr]
set task_gui_fd [open [file join $task_gui_reports project_settings.txt] w]
foreach task_run [list $task_gui_synth $task_gui_impl] {
    foreach task_property [list_property [get_runs $task_run]] {
        if {[regexp {CONSTRSET|SRCSET|PARENT|MORE OPTIONS|TCL\.(PRE|POST)$|IS_ENABLED$|ARGS.DIRECTIVE$|STATUS$} $task_property]} {
            puts $task_gui_fd "$task_run $task_property: [get_property $task_property [get_runs $task_run]]"
        }
    }
}
close $task_gui_fd
launch_runs $task_gui_synth -jobs 1
wait_on_run $task_gui_synth
if {[get_property STATUS [get_runs $task_gui_synth]] ne "synth_design Complete!"} {error "Synthesis failed: [get_property STATUS [get_runs $task_gui_synth]]"}
launch_runs $task_gui_impl -to_step route_design -jobs 1
wait_on_run $task_gui_impl
if {[get_property STATUS [get_runs $task_gui_impl]] ne "route_design Complete!"} {error "Implementation failed: [get_property STATUS [get_runs $task_gui_impl]]"}
open_run $task_gui_impl
if {abs([get_property PERIOD [get_clocks clk]] - 10.000) > 0.000001} {error "Open Implemented Design did not preserve 10.000 ns"}
report_clocks -file [file join $task_gui_reports clocks.rpt]
report_timing_summary -max_paths 20 -report_unconstrained -file [file join $task_gui_reports timing_summary.rpt]
report_route_status -file [file join $task_gui_reports route_status.rpt]
set task_gui_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set task_gui_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
if {$task_gui_setup eq "" || $task_gui_hold eq "" || $task_gui_setup < 0 || $task_gui_hold < 0} {error "Reopened GUI run fails timing"}
set task_gui_fd [open [file join $task_gui_reports result.txt] w]
puts $task_gui_fd "Run: $task_gui_impl"
puts $task_gui_fd "Status: [get_property STATUS [get_runs $task_gui_impl]]"
puts $task_gui_fd "Period ns: [get_property PERIOD [get_clocks clk]]"
puts $task_gui_fd "Setup ns: $task_gui_setup"
puts $task_gui_fd "Hold ns: $task_gui_hold"
puts $task_gui_fd "Fresh project synthesis/implementation; no historical checkpoint imported."
close $task_gui_fd
close_project
puts "GUI_10NS_PROJECT_PASS implementation=$task_gui_impl setup=$task_gui_setup hold=$task_gui_hold"
