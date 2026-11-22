run all
if {[get_value -radix unsigned /tb_power/passed] != 1} {error {Workload did not pass}}
puts {TC19_WORKLOAD_PASS}
quit
