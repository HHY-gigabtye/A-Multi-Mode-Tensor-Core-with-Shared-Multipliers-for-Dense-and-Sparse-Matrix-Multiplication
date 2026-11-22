if {$argc < 1 || $argc > 3} {error "Expected variant, optional capture directory and workload"}
set variant [lindex $argv 0]
if {$variant ni {baseline candidate_v2}} {error "Bad variant"}
set capture functional
if {$argc >= 2} {set capture [lindex $argv 1]}
if {$capture ni {functional}} {error "Bad capture directory"}
set root [file normalize [file dirname [info script]]]
set_param general.maxThreads 2
set modes {dense hybrid dual}
if {$argc == 3} {
  set modes [lindex $argv 2]
  if {$modes ni {dense hybrid dual}} {error "Bad workload"}
}
foreach mode $modes {
  set run [file join $root $variant $capture $mode]
  if {![file exists [file join $run PASS.txt]]} {error "Missing validated functional simulation: $run"}
  set out [file join $root $variant reports ${capture}_filtered $mode]
  if {[file exists $out]} {error "Preserve existing power reports: $out"}
  file mkdir $out
  open_checkpoint [file join $root $variant routed routed.dcp]
  if {[get_property PERIOD [get_clocks clk]] != 10.0} {error "Clock must be 100 MHz"}
  # Identical explicitly fixed conditions; these are comparison assumptions,
  # not measurements of the user's board or ambient environment.
  set_operating_conditions -process typical -junction_temp 50 -ambient_temp 25 \
    -voltage {Vccint 1.0 Vccaux 1.8 Vccbram 1.0}
  read_saif -strip_path tb_power/dut -out_file [file join $out saif_import.rpt] [file join $run activity_import.saif]
  report_operating_conditions -file [file join $out operating_conditions.rpt]
  report_clocks -file [file join $out clocks.rpt]
  report_power -hier all -hierarchical_depth 3 -advisory -l 20 -file [file join $out power.rpt]
  report_power -hier all -hierarchical_depth 3 -format xml -file [file join $out power.xml]
  report_switching_activity -signal_rate -static_probability -file [file join $out input_activity.rpt] [get_ports -filter {DIRECTION == IN}]
  puts "POWER_ANALYSIS_COMPLETE variant=$variant mode=$mode"
  close_design
}
