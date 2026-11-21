# Implementation search target for the selected 10.25 ns operating point.
# post_route_10p25.tcl performs the measured refinement/replication recipe,
# then restores 10.25 ns and applies the unchanged final setup/hold gate.
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]
