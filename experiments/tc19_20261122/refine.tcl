# One matched post-route refinement for both variants. Preserve original runs.
set trial [file normalize [file dirname [info script]]]
set_param general.maxThreads 2
foreach variant {baseline candidate} {
  set out [file join $trial $variant refined]
  if {[file exists $out]} {error "Preserve previous refinement: $out"}
  file mkdir $out
  cd $out
  open_checkpoint [file join $trial $variant routed routed.dcp]
  if {abs([get_property PERIOD [get_clocks clk]]-10.000)>0.000001} {error "Unexpected clock"}
  report_timing_summary -max_paths 10 -file timing_before.rpt
  phys_opt_design -directive AggressiveExplore
  route_design -directive Explore
  write_checkpoint routed.dcp
  report_utilization -file utilization_routed.rpt
  report_utilization -hierarchical -file hierarchy.rpt
  report_timing_summary -max_paths 20 -report_unconstrained -file timing_summary.rpt
  report_timing -delay_type max -max_paths 100 -input_pins -file critical_paths.rpt
  report_high_fanout_nets -max_nets 30 -file high_fanout.rpt
  report_route_status -file route_status.rpt
  report_drc -file drc.rpt
  set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
  set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
  set fd [open metrics.csv w]
  puts $fd "variant,period_ns,setup_slack_ns,hold_slack_ns"
  puts $fd "$variant,10.000,$setup,$hold"
  close $fd
  write_verilog -mode funcsim routed_functional.v
  puts "TC19_REFINEMENT_COMPLETE variant=$variant setup=$setup hold=$hold"
  close_design
}
