# Native 100 MHz recipe after a fresh 10 ns default route. Every checkpoint
# belongs to this run; no archived implementation is imported.
set task_gui_repo [file normalize [file join [file dirname [info script]] ../..]]
set task_gui_run_dir [pwd]
set task_gui_recipe [file join $task_gui_run_dir recipe_10ns_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
if {[file exists $task_gui_recipe]} {error "Recipe output already exists: $task_gui_recipe"}
set task_gui_clock [get_clocks clk]
if {[llength $task_gui_clock] != 1 || abs([get_property PERIOD $task_gui_clock] - 10.0) > 0.000001} {
    error "The 100 MHz recipe requires a 10.000 ns implementation"
}
set_param general.maxThreads 4
file mkdir $task_gui_recipe
write_checkpoint [file join $task_gui_recipe default_10ns.dcp]
report_timing_summary -max_paths 20 -file [file join $task_gui_recipe default_10ns.rpt]

close_design
set argv [list [file join $task_gui_recipe default_10ns.dcp] [file join $task_gui_recipe refined] 10.000]
set argc 3
source [file join $task_gui_repo experiments clock_control refine_route.tcl]
close_design
set argv [list [file join $task_gui_recipe refined routed.dcp] \
               [file join $task_gui_recipe replicated] \
               [file join $task_gui_repo experiments msu_fmax target_10ns_20261110 dsp_route replicate_controls_cep.txt]]
set argc 3
source [file join $task_gui_repo experiments msu_fmax target_11ns_20261109 replicate_drivers.tcl]
close_design
# An additional post-route pass closes the remaining metadata/result-enable
# and head-select/DSP-input paths without changing RTL or pipeline boundaries.
set argv [list [file join $task_gui_recipe replicated routed.dcp] [file join $task_gui_recipe closure] 10.000]
set argc 3
source [file join $task_gui_repo experiments clock_control refine_route.tcl]
close_design
set argv [list [file join $task_gui_recipe closure routed.dcp] [file join $task_gui_recipe final_10ns]]
set argc 2
source [file join $task_gui_repo experiments msu_fmax target_10ns_20261112 validate_10ns.tcl]

# Keep the validated design open for normal native checkpoint/stat generation.
cd $task_gui_run_dir
foreach task_gui_file {
    timing_closed.dcp timing_closed.rpt timing_closed_route_status.rpt
    timing_closed_utilization.rpt timing_closed_drc.rpt clocks.rpt critical_paths.rpt
} {
    file copy -force [file join $task_gui_recipe final_10ns $task_gui_file] [file join $task_gui_run_dir $task_gui_file]
}
if {abs([get_property PERIOD [get_clocks clk]] - 10.0) > 0.000001} {error "Final clock changed unexpectedly"}
puts "GUI_10NS_RECIPE_PASS recipe=$task_gui_recipe"
