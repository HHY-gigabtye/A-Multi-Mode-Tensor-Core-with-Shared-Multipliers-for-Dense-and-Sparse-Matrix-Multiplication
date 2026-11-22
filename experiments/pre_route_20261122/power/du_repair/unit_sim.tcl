run all
if {[get_value -radix unsigned /tb_du_gate/passed] != 1} {error "DU unit failed"}
puts "DU_UNIT_SIMULATION_PASS"
quit
