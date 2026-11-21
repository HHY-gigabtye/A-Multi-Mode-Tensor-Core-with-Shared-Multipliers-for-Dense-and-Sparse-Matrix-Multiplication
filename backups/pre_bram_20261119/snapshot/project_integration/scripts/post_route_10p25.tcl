# GUI equivalent of tools/build_10p25ns.tcl after the first 10 ns route.
# All input checkpoints belong to this fresh run; no archived route is imported.
set task_gui_repo [file normalize [file join [file dirname [info script]] ../..]]
set task_gui_run_dir [pwd]
set task_gui_recipe [file join $task_gui_run_dir recipe_10p25_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
if {[file exists $task_gui_recipe]} {error "Recipe output already exists: $task_gui_recipe"}
set task_gui_clock [get_clocks clk]
if {[llength $task_gui_clock] != 1 || abs([get_property PERIOD $task_gui_clock] - 10.0) > 0.000001} {
    error "The 10.25 ns GUI recipe must start from a fresh 10 ns implementation"
}
set_param general.maxThreads 4
file mkdir $task_gui_recipe
write_checkpoint [file join $task_gui_recipe default_10ns.dcp]
report_timing_summary -max_paths 20 -file [file join $task_gui_recipe default_10ns.rpt]

# Preserve the same checkpoint boundaries as the canonical standalone flow.
# close_design keeps the route step's message database usable (verified locally).
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
set argv [list [file join $task_gui_recipe replicated routed.dcp] [file join $task_gui_recipe final_10p25ns]]
set argc 2
source [file join $task_gui_repo experiments msu_fmax target_10ns_20261110 validate_10p25.tcl]

# Keep the final 10.25 ns design open for Vivado's normal routed DCP, timing
# database and run-status generation. Publish convenient reports at run root.
cd $task_gui_run_dir
foreach task_gui_file {
    timing_closed.dcp timing_closed.rpt timing_closed_route_status.rpt
    timing_closed_utilization.rpt timing_closed_drc.rpt clocks.rpt critical_paths.rpt
} {
    file copy -force [file join $task_gui_recipe final_10p25ns $task_gui_file] [file join $task_gui_run_dir $task_gui_file]
}
if {abs([get_property PERIOD [get_clocks clk]] - 10.25) > 0.000001} {error "Final operating clock changed unexpectedly"}
puts "GUI_10P25_RECIPE_PASS recipe=$task_gui_recipe"
