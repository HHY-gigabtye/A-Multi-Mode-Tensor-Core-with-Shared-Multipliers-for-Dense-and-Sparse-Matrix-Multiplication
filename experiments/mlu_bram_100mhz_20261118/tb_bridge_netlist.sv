`timescale 1ns/1ps
// Additional synthesized-interface proof. Original full-state unit tests
// remain mandatory and unchanged; no implementation shadow feeds outputs.
module tb_bridge_netlist;
  import tensor_core_pkg::*;
  import du_tc_bridge_pkg::*;
  logic clk=0, rst_n=0, issue=0, du_valid=0, tc_accept=0, result_accept=0;
  io_mode_t issued_mode;
  bridge_k_t issued_k;
  io_meta_t issued_meta;
  tc_input_packet_t du_packet;
  wire ref_can, ref_head_valid, ref_meta_valid;
  wire net_can, net_head_valid, net_meta_valid;
  wire bridge_entry_t ref_head, net_head;
  wire io_meta_t ref_meta, net_meta;
  wire fifo_count_t ref_count, net_count;
  wire flight_count_t ref_flight, net_flight;
  wire meta_count_t ref_meta_count, net_meta_count;
  wire io_status_t ref_status;
  wire [2:0] net_status;
  du_tc_bridge_reference reference_dut (
    .clk(clk), .rst_n(rst_n), .issue(issue), .issued_mode(issued_mode),
    .issued_k(issued_k), .issued_meta(issued_meta), .can_issue(ref_can),
    .du_valid(du_valid), .du_packet(du_packet), .head_valid(ref_head_valid),
    .head_entry(ref_head), .tc_accept(tc_accept),
    .result_meta_valid(ref_meta_valid), .result_meta(ref_meta),
    .result_accept(result_accept), .fifo_count(ref_count),
    .inflight_count(ref_flight), .result_meta_count(ref_meta_count), .status(ref_status)
  );
  bridge_flat_netlist candidate_dut (
    .clk(clk), .rst_n(rst_n), .issue(issue), .issued_mode_bits(issued_mode),
    .issued_k(issued_k), .issued_meta_bits(issued_meta), .can_issue(net_can),
    .du_valid(du_valid), .du_packet_bits(du_packet), .head_valid(net_head_valid),
    .head_entry_bits(net_head), .tc_accept(tc_accept),
    .result_meta_valid(net_meta_valid), .result_meta_bits(net_meta),
    .result_accept(result_accept), .fifo_count(net_count),
    .inflight_count(net_flight), .result_meta_count(net_meta_count), .status_bits(net_status)
  );
  task automatic compare_outputs(input int row, input string phase_name);
    if ({net_can,net_head_valid,net_head,net_meta_valid,net_meta,net_count,
         net_flight,net_meta_count,net_status} !==
        {ref_can,ref_head_valid,ref_head,ref_meta_valid,ref_meta,ref_count,
         ref_flight,ref_meta_count,ref_status})
      $fatal(1,"Bridge netlist interface mismatch row=%0d phase=%s",row,phase_name);
  endtask
  initial begin : replay
    string path;
    integer fd, fields, row, rejects, resets;
    integer r_reset,r_issue,r_mode,r_k,r_du,r_tc,r_result,r_status;
    io_meta_t r_meta;
    tc_input_packet_t r_packet;
    bridge_state_t expected;
    issued_mode=IO_DENSE; issued_k='0; issued_meta='0; du_packet='0;
    if (!$value$plusargs("VECTORS=%s",path)) $fatal(1,"Missing original vectors");
    fd=$fopen(path,"r");
    if (!fd) $fatal(1,"Cannot open original vectors");
    row=0; rejects=0; resets=0;
    // Allow the simulator's FPGA global startup reset to finish.
    #5; clk=1; #5; clk=0; #190;
    while (!$feof(fd)) begin
      fields=$fscanf(fd,"%d %d %h %h %h %d %h %d %d %d %h\n",
        r_reset,r_issue,r_mode,r_k,r_meta,r_du,r_packet,r_tc,r_result,r_status,expected);
      if (fields != 11) begin
        if ($feof(fd) && fields <= 0) break;
        $fatal(1,"Malformed original vector row %0d",row+1);
      end
      rst_n=(r_reset==0); issue=(r_issue!=0); issued_mode=io_mode_t'(r_mode);
      issued_k=bridge_k_t'(r_k); issued_meta=r_meta; du_valid=(r_du!=0);
      du_packet=r_packet; tc_accept=(r_tc!=0); result_accept=(r_result!=0);
      #2;
      if (ref_status !== io_status_t'(r_status)) $fatal(1,"Reference status row %0d",row+1);
      compare_outputs(row+1,"pre-edge");
      #3; clk=1; #2;
      if (reference_dut.q !== expected) $fatal(1,"Reference full state row %0d",row+1);
      compare_outputs(row+1,"post-edge");
      #3; clk=0;
      row++;
      if (r_status!=0) rejects++;
      if (r_reset!=0) resets++;
    end
    $fclose(fd);
    if (row!=19147 || rejects!=7156 || resets!=13) $fatal(1,"Incomplete vector replay");
    $display("BRIDGE NETLIST EQUIVALENCE PASS rows=%0d rejected=%0d resets=%0d comparisons=%0d",
             row,rejects,resets,2*row);
    $finish;
  end
  initial begin #2000000; $fatal(1,"Netlist simulation timeout"); end
endmodule
