# Vivado/XSim functional simulation of RTL or inferred RAM primitives.
# Usage: SOURCE_SNAPSHOT NETLIST_OR_RTL NEW_OUTPUT_DIR
if {$argc != 3} {error "Expected SOURCE_SNAPSHOT NETLIST_OR_RTL NEW_OUTPUT_DIR"}
set eq_dir [file normalize [file dirname [info script]]]
set eq_repo [file normalize [file join $eq_dir ../..]]
set eq_source [file normalize [lindex $argv 0]]
set eq_design [lindex $argv 1]
if {$eq_design ne "RTL"} {set eq_design [file normalize $eq_design]}
set eq_output [file normalize [lindex $argv 2]]
if {[file exists $eq_output]} {error "Preserve earlier simulation output"}
file mkdir $eq_output
cd $eq_output
set f [open [file join $eq_dir baseline src mlu_sv mlu.sv] r]
set original [read $f]
close $f
if {[regsub {module mlu \(} $original {module mlu_reference (} reference] != 1} {
    error "Expected exactly one baseline module declaration"
}
set f [open mlu_reference.sv w]
puts -nonewline $f $reference
close $f
create_project sim_project [file join $eq_output project] -part xc7z020clg484-1
set_property target_simulator XSim [current_project]
add_files -fileset sim_1 [list \
    [file join $eq_source du_tia_sv rtl du_tia_pkg.sv] \
    [file join $eq_source mlu_sv mlu_pkg.sv] \
    [file join $eq_output mlu_reference.sv] \
    [file join $eq_dir tb_mlu_bram_equiv.sv]]
if {$eq_design eq "RTL"} {
    add_files -fileset sim_1 [file join $eq_source mlu_sv mlu.sv]
} else {
    add_files -fileset sim_1 $eq_design
    set_property verilog_define NETLIST [get_filesets sim_1]
    # Vivado flattens struct and packed-array ports into escaped field names.
    # Reconnect every field explicitly; never rewrite the generated netlist.
    set header_start [string first {module mlu (} $original]
    set header_end [string first "\n);" $original $header_start]
    if {$header_start < 0 || $header_end < 0} {error "Missing baseline port declaration"}
    set header [string range $original $header_start [expr {$header_end+2}]]
    set wrapper [string map {{module mlu (} {module mlu_netlist_wrapper (}} $header]
    append wrapper "\n" {  wire [2:0] net_status;
  wire [1:0] net_mode;
  assign status = mlu_pkg::io_status_t'(net_status);
  assign out_packet.mode = du_tia_pkg::compiler_mode_e'(net_mode);
  mlu_netlist u_netlist (
}
    set connections {}
    foreach port {clk rst_n command_valid command_ready read_request_valid read_request_ready read_addr read_beats read_data_valid read_data_ready read_last out_valid out_ready out_k status} {
        set expression $port
        if {$port eq "status"} {set expression net_status}
        append connections [format {    .%s(%s),} $port $expression] "\n"
    }
    foreach {port expression} {
        {command[mode]} command.mode
        {command[src_addr]} command.src_addr
        {command[meta][tile_id]} command.meta.tile_id
        {command[meta][dst_addr]} command.meta.dst_addr
        {out_packet[mode]} net_mode
        {out_packet[k_position]} out_packet.k_position
        {out_packet[payload]} out_packet.payload
        {out_meta[tile_id]} out_meta.tile_id
        {out_meta[dst_addr]} out_meta.dst_addr
        {tick_info[command_accepted]} tick_info.command_accepted
        {tick_info[read_request_accepted]} tick_info.read_request_accepted
        {tick_info[read_data_accepted]} tick_info.read_data_accepted
        {tick_info[packet_issued]} tick_info.packet_issued
        {tick_info[tile_issued]} tick_info.tile_issued
        {tick_info[tile_id]} tick_info.tile_id
        {tick_info[k]} tick_info.k
    } {append connections [format {    .\%s (%s),} $port $expression] "\n"}
    for {set byte 0} {$byte < 32} {incr byte} {
        append connections [format {    .\read_data[%d] (read_data[%d]),} $byte $byte] "\n"
    }
    append wrapper [string trimright $connections ",\n"] "\n  );\nendmodule\n"
    set f [open mlu_netlist_wrapper.sv w]
    puts -nonewline $f $wrapper
    close $f
    add_files -fileset sim_1 [file join $eq_output mlu_netlist_wrapper.sv]
}
set_property top tb_mlu_bram_equiv [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property -dict [list xsim.simulate.xsim.more_options \
    "-testplusarg VECTORS=[file join $eq_repo mlu_sv mlu_vectors.txt]"] [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
close_sim
set transcript [file join $eq_output project sim_project.sim sim_1 behav xsim simulate.log]
set f [open $transcript r]
set body [read $f]
close $f
if {[string first {MLU BRAM EQUIVALENCE PASS} $body] < 0 ||
    [regexp -nocase {Fatal:|Error:|\$fatal} $body]} {error "Equivalence simulation failed; inspect $transcript"}
file copy $transcript [file join $eq_output result.log]
puts "MLU_BRAM_EQUIV_COMPLETE mode=$eq_design"
