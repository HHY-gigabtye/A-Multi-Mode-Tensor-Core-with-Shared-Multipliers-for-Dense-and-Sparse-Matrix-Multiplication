`timescale 1ns/1ps
// Compare complete logical state against the immutable baseline, independently
// of the candidate's physical product/shadow registers. No other modules.
module tb_product_rejections;
  import tensor_core_pkg::*;
  logic clk = 0, rst_n = 0, in_valid = 0, result_ready = 0;
  tc_input_packet_t in_packet;
  logic in_ready, input_ready, result_valid, busy;
  logic ref_in_ready, ref_input_ready, ref_result_valid, ref_busy;
  tc_matrix_t result, ref_result;
  tc_status_t status, ref_status;
  tc_tick_info_t tick_info, ref_tick_info;
  int edges = 0, rejected = 0, consumed = 0, longest_streak = 0, streak = 0;

  tensor_core dut (.*);
  tensor_core_baseline reference (
    .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_packet(in_packet),
    .result_ready(result_ready), .in_ready(ref_in_ready),
    .input_ready(ref_input_ready), .result_valid(ref_result_valid),
    .result(ref_result), .busy(ref_busy), .status(ref_status), .tick_info(ref_tick_info)
  );

  task automatic compare_state;
    if ({in_ready, input_ready, result_valid, busy, status, result, tick_info} !==
        {ref_in_ready, ref_input_ready, ref_result_valid, ref_busy,
         ref_status, ref_result, ref_tick_info})
      $fatal(1, "Public interface mismatch at edge %0d", edges);
    if (dut.ctrl_q !== reference.ctrl_q || dut.dense_q !== reference.dense_q ||
        dut.sparse_q !== reference.sparse_q || dut.info_q !== reference.info_q)
      $fatal(1, "Complete logical state mismatch at edge %0d", edges);
  endtask

  task automatic step;
    #2;
    compare_state();
    if (rst_n && ref_status != TC_OK) begin
      rejected++;
      streak++;
      if (streak > longest_streak) longest_streak = streak;
    end else streak = 0;
    if (rst_n && ref_status == TC_OK && ref_result_valid && result_ready) consumed++;
    #3 clk = 1;
    #1;
    edges++;
    compare_state();
    #4 clk = 0;
  endtask

  task automatic packet(input int tag, input int count_a, count_b);
    in_packet = '0;
    in_packet.is_sparse = 1;
    in_packet.payload.sparse.a.count = 4'(count_a);
    in_packet.payload.sparse.b.count = 4'(count_b);
    for (int lane = 0; lane < 8; lane++) begin
      in_packet.payload.sparse.a.index[lane] = 3'(lane);
      in_packet.payload.sparse.b.index[lane] = 3'(lane);
      // Include signed extremes, stored zero and varying invalid-edge data.
      case ((tag + lane) % 4)
        0: begin
          in_packet.payload.sparse.a.value[lane] = 8'h80;
          in_packet.payload.sparse.b.value[lane] = 8'h7f;
        end
        1: begin
          in_packet.payload.sparse.a.value[lane] = 0;
          in_packet.payload.sparse.b.value[lane] = 8'h80;
        end
        default: begin
          in_packet.payload.sparse.a.value[lane] = 8'(tag * 17 + lane);
          in_packet.payload.sparse.b.value[lane] = 8'(tag * 31 - lane);
        end
      endcase
    end
  endtask

  initial begin
    in_packet = '0;
    // Different malformed-input streak lengths and all legal count values.
    for (int trial = 0; trial < 72; trial++) begin
      rst_n = 0;
      in_valid = 0;
      result_ready = 0;
      step();
      rst_n = 1;
      for (int k = 0; k < 8; k++) begin
        packet(trial * 8 + k, trial % 9, (trial / 9) % 9);
        in_valid = 1;
        #1;
        if (!ref_in_ready || ref_status != TC_OK) $fatal(1, "Legal packet unexpectedly blocked");
        step();
        for (int bad = 0; bad < (trial % 24) + 1; bad++) begin
          packet(trial + bad + k, 8, 8);
          case (bad % 3)
            0: in_packet.payload.sparse.a.count = 9;
            1: in_packet.payload.sparse.b.index[2] = 0;
            2: in_packet.is_sparse = 0;
          endcase
          #1;
          if (ref_status == TC_OK) $fatal(1, "Malformed input was not rejected");
          step();
        end
        in_valid = 0;
        packet(trial - k, 8, 8);
        step();
      end
      // Hold a complete result while raw multiplier inputs continue to change.
      for (int idle = 0; idle < 24; idle++) begin
        packet(trial + idle, idle % 9, (idle + 1) % 9);
        step();
      end
      if (!ref_result_valid) $fatal(1, "Missing result under output stall");
      result_ready = 1;
      repeat (8) step();
      // Reset with a fresh accepted product still in the MUL stage.
      packet(trial, 8, 8);
      in_valid = 1;
      step();
      rst_n = 0;
      in_valid = 0;
      step();
    end
    if (consumed != 72 || longest_streak != 24 || rejected != 7200)
      $fatal(1, "Coverage mismatch consumed=%0d streak=%0d rejected=%0d", consumed, longest_streak, rejected);
    $display("PRODUCT REJECTION EQUIVALENCE PASS edges=%0d rejected=%0d longest_streak=%0d consumed=%0d", edges, rejected, longest_streak, consumed);
    $finish;
  end
endmodule
