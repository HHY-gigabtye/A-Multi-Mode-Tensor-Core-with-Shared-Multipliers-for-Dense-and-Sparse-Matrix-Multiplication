# Reproduce 100 MHz from current RTL with the verified physical recipe.
# Optional argument: a new output directory. Preserve all earlier results.
if {$argc > 1} {error "Usage: build_10ns.tcl ?NEW_OUTPUT_DIR?"}
set task_main_root [file normalize [file join [file dirname [info script]] ..]]
if {$argc == 1} {
    set task_main_output [file normalize [lindex $argv 0]]
} else {
    set task_main_output [file join $task_main_root build main_10ns]
}
if {[file exists $task_main_output]} {error "Use a new output directory: $task_main_output"}
set argv [list $task_main_root [file join $task_main_output target_10ns] 10.000]
set argc 3
source [file join $task_main_root experiments msu_fmax flow.tcl]
close_project
set argv [list [file join $task_main_output target_10ns refined routed.dcp] \
               [file join $task_main_output replicated] \
               [file join $task_main_root experiments msu_fmax target_10ns_20261110 dsp_route replicate_controls_cep.txt]]
set argc 3
source [file join $task_main_root experiments msu_fmax target_11ns_20261109 replicate_drivers.tcl]
close_project
set argv [list [file join $task_main_output replicated routed.dcp] [file join $task_main_output closure] 10.000]
set argc 3
source [file join $task_main_root experiments clock_control refine_route.tcl]
close_project
set argv [list [file join $task_main_output closure routed.dcp] [file join $task_main_output final_10ns]]
set argc 2
source [file join $task_main_root experiments msu_fmax target_10ns_20261112 validate_10ns.tcl]
puts "MAIN_10NS_BUILD_COMPLETE output=$task_main_output"
