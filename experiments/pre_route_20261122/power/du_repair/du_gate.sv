`timescale 1ns/1ps
// Flat unit boundary prevents exported struct-port adapters from hiding errors.
module du_gate(input logic clk, rst_n, in_valid,
  input logic [$bits(du_tia_pkg::du_tia_input_t)-1:0] input_bits,
  output logic out_valid,
  output logic [$bits(du_tia_pkg::du_tia_output_t)-1:0] output_bits);
  du_tia_pkg::du_tia_input_t packet_in;
  du_tia_pkg::du_tia_output_t packet_out;
  assign packet_in = input_bits;
  assign output_bits = packet_out;
  du_tia u_du (.clk(clk), .rst_n(rst_n), .in_valid(in_valid),
    .in_packet(packet_in), .out_valid(out_valid), .out_packet(packet_out));
endmodule
