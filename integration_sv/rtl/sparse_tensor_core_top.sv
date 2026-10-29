`timescale 1ns/1ps

// Independent 8x8x8 tiles. Simplified, separate read/write memory channels;
// read_beats is a count (4 or 5), not AXI ARLEN. All blocks share reset.
module sparse_tensor_core_top (
  input  logic clk,
  input  logic rst_n,
  input  logic command_valid,
  input  wire mlu_pkg::io_command_t command,
  output logic command_ready,
  output logic read_request_valid,
  input  logic read_request_ready,
  output logic [63:0] read_addr,
  output logic [2:0] read_beats,
  input  logic read_data_valid,
  output logic read_data_ready,
  input  wire mlu_pkg::io_beat_t read_data,
  input  logic read_last,
  output logic write_valid,
  input  logic write_ready,
  output logic [63:0] write_addr,
  output msu_pkg::msu_beat_t write_data,
  output logic write_last,
  output msu_pkg::io_meta_t write_meta,
  output logic tile_done,
  output msu_pkg::io_meta_t completed,
  output mlu_pkg::io_status_t mlu_status,
  output du_tc_bridge_pkg::io_status_t bridge_status,
  output tensor_core_pkg::tc_status_t tc_status,
  output msu_pkg::io_status_t msu_status
);
  logic mlu_command_ready, mlu_read_request_valid, mlu_read_data_ready;
  logic mlu_out_valid, can_issue, issue, du_valid;
  du_tia_pkg::du_tia_input_t mlu_packet;
  mlu_pkg::io_meta_t mlu_meta;
  logic [2:0] mlu_k;
  du_tia_pkg::du_tia_output_t du_packet;
  tensor_core_pkg::tc_input_packet_t decoded_packet;
  du_tc_bridge_pkg::io_meta_t issued_meta;
  du_tc_bridge_pkg::bridge_entry_t head_entry;
  logic head_valid, tc_in_ready, tc_accept;
  logic result_meta_valid, tc_result_valid, tc_result_ready;
  logic msu_result_valid, msu_result_ready, result_accept;
  du_tc_bridge_pkg::io_meta_t result_meta;
  msu_pkg::io_meta_t msu_meta;
  tensor_core_pkg::tc_matrix_t tc_result;
  msu_pkg::msu_events_t msu_events;
  du_tc_bridge_pkg::fifo_count_t fifo_count;
  du_tc_bridge_pkg::flight_count_t inflight_count;
  du_tc_bridge_pkg::meta_count_t result_meta_count;

  // The standalone MLU does not gate its combinational outputs in reset.
  assign command_ready = rst_n && mlu_command_ready;
  assign read_request_valid = rst_n && mlu_read_request_valid;
  assign read_data_ready = rst_n && mlu_read_data_ready;
  assign issue = rst_n && mlu_out_valid && can_issue;

  mlu u_mlu (
    .clk(clk), .rst_n(rst_n),
    .command_valid(rst_n && command_valid), .command(command),
    .command_ready(mlu_command_ready),
    .read_request_valid(mlu_read_request_valid),
    .read_request_ready(rst_n && read_request_ready),
    .read_addr(read_addr), .read_beats(read_beats),
    .read_data_valid(rst_n && read_data_valid),
    .read_data_ready(mlu_read_data_ready), .read_data(read_data),
    .read_last(read_last), .out_valid(mlu_out_valid),
    .out_ready(rst_n && can_issue), .out_packet(mlu_packet),
    .out_meta(mlu_meta), .out_k(mlu_k), .status(mlu_status), .tick_info()
  );

  du_tia u_du_tia (
    .clk(clk), .rst_n(rst_n), .in_valid(issue), .in_packet(mlu_packet),
    .out_valid(du_valid), .out_packet(du_packet)
  );

  // Map fields explicitly across independently maintained packages.
  // No arithmetic or extra pipeline stage is introduced by these adapters.
  always_comb begin
    decoded_packet = '0;
    decoded_packet.is_sparse = du_packet.is_sparse;
    if (du_packet.is_sparse) begin
      decoded_packet.payload.sparse.a.count = du_packet.payload.sparse.a.count;
      decoded_packet.payload.sparse.a.value = du_packet.payload.sparse.a.value;
      decoded_packet.payload.sparse.a.index = du_packet.payload.sparse.a.index;
      decoded_packet.payload.sparse.b.count = du_packet.payload.sparse.b.count;
      decoded_packet.payload.sparse.b.value = du_packet.payload.sparse.b.value;
      decoded_packet.payload.sparse.b.index = du_packet.payload.sparse.b.index;
    end else begin
      decoded_packet.payload.dense.dense_a = du_packet.payload.dense.dense_a;
      decoded_packet.payload.dense.dense_b = du_packet.payload.dense.dense_b;
    end
    issued_meta.tile_id = mlu_meta.tile_id;
    issued_meta.dst_addr = mlu_meta.dst_addr;
    msu_meta.tile_id = result_meta.tile_id;
    msu_meta.dst_addr = result_meta.dst_addr;
  end

  // Bridge already contains the four-stage sideband and both FIFOs.
  du_tc_bridge u_bridge (
    .clk(clk), .rst_n(rst_n), .issue(issue),
    .issued_mode(du_tc_bridge_pkg::io_mode_t'(mlu_packet.mode)),
    .issued_k({5'd0, mlu_k}), .issued_meta(issued_meta),
    .can_issue(can_issue), .du_valid(du_valid), .du_packet(decoded_packet),
    .head_valid(head_valid), .head_entry(head_entry), .tc_accept(tc_accept),
    .result_meta_valid(result_meta_valid), .result_meta(result_meta),
    .result_accept(result_accept), .fifo_count(fifo_count),
    .inflight_count(inflight_count), .result_meta_count(result_meta_count),
    .status(bridge_status)
  );

  // Present the stored head even when blocked, then use MODE-AWARE readiness.
  // TC in_valid is an actual acceptance pulse, not a conventional held valid.
  assign tc_accept = rst_n && head_valid && tc_in_ready;
  assign msu_result_valid = rst_n && tc_result_valid && result_meta_valid;
  assign tc_result_ready = rst_n && result_meta_valid && msu_result_ready;
  assign result_accept = tc_result_valid && tc_result_ready;

  tensor_core u_tensor_core (
    .clk(clk), .rst_n(rst_n), .in_valid(tc_accept),
    .in_packet(head_entry.packet), .in_ready(tc_in_ready), .input_ready(),
    .result_ready(tc_result_ready), .result_valid(tc_result_valid),
    .result(tc_result), .busy(), .status(tc_status), .tick_info()
  );

  msu u_msu (
    .clk(clk), .rst_n(rst_n), .result_valid(msu_result_valid),
    .result_ready(msu_result_ready), .result_meta(msu_meta), .result(tc_result),
    .write_valid(write_valid), .write_ready(write_ready), .write_addr(write_addr),
    .write_data(write_data), .write_last(write_last), .write_meta(write_meta),
    .status(msu_status), .events(msu_events), .buffer_count(),
    .head_index(), .row_index()
  );
  assign tile_done = msu_events.tile_done;
  assign completed = msu_events.completed;
endmodule
