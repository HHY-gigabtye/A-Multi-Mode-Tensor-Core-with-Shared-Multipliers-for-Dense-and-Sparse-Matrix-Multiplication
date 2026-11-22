set out [file normalize $::env(POWER_RUN_OUT)]
cd $out
run 2000 ns
set before [get_value -radix unsigned /tb_power/dones]
if {$::env(POWER_CAPTURE) eq "1"} {
  open_saif [file join $out activity.saif]
  # The exported netlist has these six design scopes. Log their nets and
  # ports, excluding vendor primitive internals that cannot map to DCP nets.
  foreach scope {/tb_power/dut /tb_power/dut/u_mlu /tb_power/dut/u_du_tia /tb_power/dut/u_bridge /tb_power/dut/u_tensor_core /tb_power/dut/u_msu} {
    set objects [get_objects $scope/*]
    if {[llength $objects] == 0} {error "Empty design scope: $scope"}
    log_saif $objects
    puts "POWER_SAIF_SCOPE $scope objects=[llength $objects]"
  }
}
run 20480 ns
if {$::env(POWER_CAPTURE) eq "1"} {close_saif}
set after [get_value -radix unsigned /tb_power/dones]
if {$after-$before != 256} {error "Expected 256 completed tiles in power window: $before -> $after"}
set fd [open window.txt w]
puts $fd "start_ns=2000 end_ns=22480 duration_ns=20480 frequency_mhz=100 tiles=[expr {$after-$before}]"
close $fd
run all
if {[get_value -radix unsigned /tb_power/passed] != 1} {error "Power workload did not pass"}
puts "POWER_SIMULATION_PASS captured_tiles=[expr {$after-$before}]"
quit
