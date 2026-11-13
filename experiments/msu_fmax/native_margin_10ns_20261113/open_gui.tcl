# Open the independently validated native implementation for interactive review.
set display_repo [file normalize [file join [file dirname [info script]] ../../..]]
set display_output [file dirname [info script]]
open_project [file join $display_repo project_integration project_integration.xpr]
if {[current_run -implementation] ne "impl_10ns_margin_20261113"} {error "Unexpected active implementation"}
open_run impl_10ns_margin_20261113
if {abs([get_property PERIOD [get_clocks clk]] - 10.000) > 0.000001} {error "Expected 10.000 ns clock"}
report_timing_summary -name timing_10ns_margin -max_paths 10 -report_unconstrained
set display_fd [open [file join $display_output gui_loaded.txt] w]
puts $display_fd "Project: [get_property NAME [current_project]]"
puts $display_fd "Implementation: [current_run -implementation]"
puts $display_fd "Period ns: [get_property PERIOD [get_clocks clk]]"
puts $display_fd "Setup ns: [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]"
puts $display_fd "Hold ns: [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]"
close $display_fd
puts "GUI_LOADED_NEW_NATIVE_10NS_IMPLEMENTATION"
