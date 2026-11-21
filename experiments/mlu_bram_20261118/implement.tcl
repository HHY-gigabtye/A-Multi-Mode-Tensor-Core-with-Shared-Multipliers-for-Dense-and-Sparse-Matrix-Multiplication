# Same selected production sequence for both immutable source snapshots.
# Usage: SOURCE_SNAPSHOT NEW_OUTPUT_DIR
if {$argc != 2} {error "Expected SOURCE_SNAPSHOT NEW_OUTPUT_DIR"}
set bram_repo [file normalize [file join [file dirname [info script]] ../..]]
set bram_src [file normalize [lindex $argv 0]]
set bram_out [file normalize [lindex $argv 1]]
if {[file exists $bram_out]} {error "Preserve previous output: $bram_out"}
set argv [list $bram_src [file join $bram_out fresh] 10.000]
set argc 3
source [file join $bram_repo experiments msu_fmax flow.tcl]
close_project
set argv [list [file join $bram_out fresh refined routed.dcp] \
    [file join $bram_out replicated] \
    [file join $bram_repo experiments msu_fmax target_10ns_20261110 dsp_route replicate_controls_cep.txt]]
set argc 3
source [file join $bram_repo experiments msu_fmax target_11ns_20261109 replicate_drivers.tcl]
close_project
set argv [list [file join $bram_out replicated routed.dcp] [file join $bram_out closure] 10.000]
set argc 3
source [file join $bram_repo experiments clock_control refine_route.tcl]
close_project
set argv [list [file join $bram_out closure routed.dcp] [file join $bram_out margin_9p75] 9.750]
set argc 3
source [file join $bram_repo experiments msu_fmax margin_10ns_20261113 guardband_refine.tcl]
close_project
set argv [list [file join $bram_out margin_9p75 timing_closed.dcp] [file join $bram_out final_10ns]]
set argc 2
source [file join $bram_repo experiments msu_fmax target_10ns_20261112 validate_10ns.tcl]
report_utilization -hierarchical -file hierarchy.rpt
puts "MLU_BRAM_IMPLEMENTATION_COMPLETE source=$bram_src setup=$task_setup hold=$task_hold"
