run 400 ns
foreach signal {mode cycle mlu_status bridge_status tc_status msu_status command read_data read_data_valid read_last} {
  puts "POWER_DIAGNOSTIC $signal=[get_value -radix hex /tb_power/$signal]"
}
foreach scope {/tb_power/dut /tb_power/dut/u_bridge /tb_power/dut/u_mlu /tb_power/dut/u_du_tia} {
  foreach object [get_objects $scope/*] {
    if {[regexp {status|valid|packet|sparse|count|head} $object]} {
      puts "POWER_DIAGNOSTIC $object=[get_value -radix hex $object]"
    }
  }
}
quit
