# Check the MAC mapping on the standalone compute core before full implementation.
set trial [file normalize [file dirname [info script]]]
set out [file join $trial core_probe]
if {[file exists $out]} {error "Choose a fresh probe directory"}
file mkdir $out
cd $out
set_param general.maxThreads 1
create_project -in_memory -part xc7z020clg484-1
set root [file join $trial candidate src tensor_core_sv]
read_verilog -sv [file join $root tensor_core_pkg.sv]
read_verilog -sv [file join $root outer_product_core.sv]
synth_design -mode out_of_context -top outer_product_core -part xc7z020clg484-1
report_utilization -file utilization.rpt
write_verilog -mode funcsim core_netlist.v
set dsps [get_cells -hier -filter {REF_NAME == DSP48E1}]
puts "DSP_COUNT=[llength $dsps]"
if {[llength $dsps] != 64} {error "Expected 64 MACs"}
foreach d $dsps {
    foreach {key val} {AREG 0 BREG 0 MREG 1 PREG 1 USE_MULT MULTIPLY} {
        if {[get_property $key $d] ne $val} {error "$d: expected $key=$val"}
    }
}
puts "ALL_64_MREG_PREG_MAC_REGISTERS_PRESENT"
