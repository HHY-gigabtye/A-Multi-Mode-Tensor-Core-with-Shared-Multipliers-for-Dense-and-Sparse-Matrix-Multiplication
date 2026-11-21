# Use with: vivado -mode gui -source tools/open_bram_100mhz_gui.tcl
# Open the saved native run and display its current reports without rebuilding.
set gui_bram_repo [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $gui_bram_repo project_integration project_integration.xpr]
set gui_bram_run [current_run -implementation]
if {[get_property STATUS [get_runs $gui_bram_run]] ne "route_design Complete!" ||
    [get_property NEEDS_REFRESH [get_runs $gui_bram_run]]} {
    error "BRAM implementation is incomplete or out of date; rebuild before inspection"
}
open_run $gui_bram_run
if {[get_property PERIOD [get_clocks clk]] != 10.0 ||
    [llength [get_cells -hier -filter {REF_NAME == RAMB36E1}]] != 18 ||
    [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]] != 64} {
    error "Expected the 10 ns unified core with 18 BRAM36s and 64 DSP48s"
}
set gui_bram_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set gui_bram_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
if {$gui_bram_setup < 0 || $gui_bram_hold < 0} {error "Reopened implementation fails timing"}
report_utilization -name bram_100mhz_utilization
report_timing_summary -name bram_100mhz_timing -max_paths 10 -report_unconstrained
puts "GUI_BRAM_OPENED run=$gui_bram_run period_ns=10.000 setup=$gui_bram_setup hold=$gui_bram_hold bram36=18"
