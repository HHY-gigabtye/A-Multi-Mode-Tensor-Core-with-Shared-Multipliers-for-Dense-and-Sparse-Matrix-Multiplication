`timescale 1ns/1ps
module bridge_flat (
  input wire clk, rst_n, issue,
  input wire [1:0] issued_mode_bits,
  input wire [7:0] issued_k,
  input wire [95:0] issued_meta_bits,
  output wire can_issue,
  input wire du_valid,
  input wire [$bits(tensor_core_pkg::tc_input_packet_t)-1:0] du_packet_bits,
  output wire head_valid,
  output wire [$bits(du_tc_bridge_pkg::bridge_entry_t)-1:0] head_entry_bits,
  input wire tc_accept,
  output wire result_meta_valid,
  output wire [95:0] result_meta_bits,
  input wire result_accept,
  output wire [3:0] fifo_count,
  output wire [2:0] inflight_count,
  output wire [1:0] result_meta_count,
  output wire [2:0] status_bits
);
  import du_tc_bridge_pkg::*;
  wire io_status_t status;
  wire bridge_entry_t head_entry;
  wire io_meta_t result_meta;
  assign head_entry_bits = head_entry;
  assign result_meta_bits = result_meta;
  assign status_bits = status;
  du_tc_bridge dut (
    .clk(clk), .rst_n(rst_n), .issue(issue),
    .issued_mode(io_mode_t'(issued_mode_bits)), .issued_k(issued_k),
    .issued_meta(issued_meta_bits), .can_issue(can_issue),
    .du_valid(du_valid), .du_packet(du_packet_bits),
    .head_valid(head_valid), .head_entry(head_entry), .tc_accept(tc_accept),
    .result_meta_valid(result_meta_valid), .result_meta(result_meta),
    .result_accept(result_accept), .fifo_count(fifo_count),
    .inflight_count(inflight_count), .result_meta_count(result_meta_count),
    .status(status)
  );
endmodule
