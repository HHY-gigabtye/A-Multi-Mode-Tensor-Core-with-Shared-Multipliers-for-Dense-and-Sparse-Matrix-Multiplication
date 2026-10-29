`timescale 1ns/1ps

// ModelSim-compatible procedural checks; no SVA, classes, UVM, or DPI.
module tb_tensor_core;
  import tensor_core_pkg::*;
  logic clk, rst_n, in_valid, in_ready, input_ready;
  logic result_ready, result_valid, busy;
  tc_input_packet_t in_packet;
  tc_matrix_t result;
  tc_status_t status;
  tc_tick_info_t tick_info;

  tensor_core dut (.*);

  function automatic logic [31:0] mix(input logic [31:0] h, v);
    return (h ^ v) * 32'd16777619;
  endfunction
  function automatic logic [31:0] hash_token(input logic [31:0] h,
                                             input tc_token_t t);
    logic [31:0] x;
    x = mix(h, {31'd0, t.valid});
    x = mix(x, {31'd0, t.last});
    return mix(x, {24'd0, t.value});
  endfunction
  function automatic logic [31:0] state_hash();
    logic [31:0] h;
    h = 32'd2166136261;
    h = mix(h, {31'd0, dut.ctrl_q.busy});
    h = mix(h, {31'd0, dut.ctrl_q.is_sparse});
    h = mix(h, {31'd0, dut.ctrl_q.finish_pending});
    h = mix(h, {31'd0, dut.ctrl_q.result_valid});
    h = mix(h, {28'd0, dut.ctrl_q.received});
    h = mix(h, {30'd0, dut.ctrl_q.outstanding});
    h = mix(h, {30'd0, dut.ctrl_q.result_count});
    for (int i = 0; i < 8; i = i + 1)
      for (int j = 0; j < 8; j = j + 1) h = mix(h, dut.ctrl_q.result[i][j]);
    for (int i = 0; i < 8; i = i + 1)
      for (int j = 0; j < 8; j = j + 1) h = mix(h, dut.ctrl_q.result_next[i][j]);
    if (dut.ctrl_q.is_sparse) begin
      h = mix(h, {31'd0, dut.sparse_q.mul.valid});
      h = mix(h, {31'd0, dut.sparse_q.mul.first});
      h = mix(h, {31'd0, dut.sparse_q.mul.last});
      h = mix(h, {28'd0, dut.sparse_q.mul.a_count});
      h = mix(h, {28'd0, dut.sparse_q.mul.b_count});
      for (int p = 0; p < 8; p = p + 1) h = mix(h, {29'd0, dut.sparse_q.mul.a_index[p]});
      for (int p = 0; p < 8; p = p + 1) h = mix(h, {29'd0, dut.sparse_q.mul.b_index[p]});
      for (int i = 0; i < 8; i = i + 1)
        for (int j = 0; j < 8; j = j + 1) h = mix(h, {16'd0, dut.sparse_q.mul.product[i][j]});
      h = mix(h, {31'd0, dut.sparse_q.route.valid});
      h = mix(h, {31'd0, dut.sparse_q.route.first});
      h = mix(h, {31'd0, dut.sparse_q.route.last});
      for (int i = 0; i < 8; i = i + 1)
        for (int j = 0; j < 8; j = j + 1) begin
          h = mix(h, {31'd0, dut.sparse_q.route.enable[i][j]});
          h = mix(h, {16'd0, dut.sparse_q.route.delta[i][j]});
        end
      for (int i = 0; i < 8; i = i + 1)
        for (int j = 0; j < 8; j = j + 1) h = mix(h, dut.sparse_q.acc[i][j]);
    end else begin
      for (int i = 0; i < 8; i = i + 1)
        for (int n = 0; n < 7; n = n + 1) begin
          h = hash_token(h, dut.dense_q.a_delay[i][n]);
          h = hash_token(h, dut.dense_q.b_delay[i][n]);
        end
      for (int i = 0; i < 8; i = i + 1)
        for (int j = 0; j < 8; j = j + 1) begin
          h = hash_token(h, dut.dense_q.pe[i][j].a);
          h = hash_token(h, dut.dense_q.pe[i][j].b);
          h = mix(h, dut.dense_q.pe[i][j].acc);
        end
    end
    return h;
  endfunction

  integer fd, rc, n, resets, produced, consumed, errors;
  integer overlap_starts, pop_push, consume_start, full_fifo;
  integer reset_word, valid_word, ready_word, exp_base, exp_ready, exp_status;
  integer exp_result_valid, exp_busy;
  logic [31:0] exp_hash, actual_hash;
  tc_input_packet_t packet_word;
  tc_tick_info_t exp_info;
  tc_matrix_t exp_result, exp_next;
  logic old_busy;
  string vector_path;

  task automatic fail(input string message);
    $display("FAIL record=%0d time=%0t: %s", n + 1, $time, message);
    $display("  busy=%0b sparse=%0b received=%0d outstanding=%0d queued=%0d pending=%0b",
             dut.ctrl_q.busy, dut.ctrl_q.is_sparse, dut.ctrl_q.received,
             dut.ctrl_q.outstanding, dut.ctrl_q.result_count, dut.ctrl_q.finish_pending);
    $fatal(1, "C/SV comparison failed");
  endtask

  initial begin
    clk = 0; rst_n = 0; in_valid = 0; in_packet = '0; result_ready = 0;
    n = 0; resets = 0; produced = 0; consumed = 0; errors = 0;
    overlap_starts = 0; pop_push = 0; consume_start = 0; full_fifo = 0;
    vector_path = "c_vectors.txt";
    if ($value$plusargs("VECTORS=%s", vector_path)) begin end
    fd = $fopen(vector_path, "r");
    if (fd == 0) $fatal(1, "Cannot open %s. Run from the extracted project folder.", vector_path);

    while (!$feof(fd)) begin
      rc = $fscanf(fd, "%d %d %d %h %d %d %d %h %d %d %h %h %h\n",
                   reset_word, valid_word, ready_word, packet_word, exp_base, exp_ready,
                   exp_status, exp_info, exp_result_valid, exp_busy, exp_hash,
                   exp_result, exp_next);
      if (rc == 13) begin
        clk = 0;
        rst_n = (reset_word == 0);
        in_valid = (valid_word != 0);
        result_ready = (ready_word != 0);
        in_packet = packet_word;
        #5;
        old_busy = busy;
        if (rst_n) begin
          if (input_ready !== (exp_base != 0)) fail("tc_input_ready mismatch");
          if (in_ready !== (exp_ready != 0)) fail("tc_input_ready_for mismatch");
          if (status !== tc_status_t'(exp_status)) fail("rejection status mismatch");
        end
        clk = 1;
        #5;
        if (tick_info !== exp_info)
          fail($sformatf("tick_info got=%h expected=%h", tick_info, exp_info));
        if (result_valid !== (exp_result_valid != 0)) fail("result_valid mismatch");
        if (busy !== (exp_busy != 0)) fail("busy mismatch");
        if (result !== exp_result) begin
          for (int i = 0; i < 8; i = i + 1)
            for (int j = 0; j < 8; j = j + 1)
              if (result[i][j] !== exp_result[i][j])
                $display("  C[%0d][%0d] got=%0d expected=%0d", i, j,
                         $signed(result[i][j]), $signed(exp_result[i][j]));
          fail("result FIFO head mismatch");
        end
        if (dut.ctrl_q.result_next !== exp_next) fail("result FIFO second slot mismatch");
        actual_hash = state_hash();
        if (actual_hash !== exp_hash)
          fail($sformatf("internal state hash got=%h expected=%h", actual_hash, exp_hash));
        if (reset_word != 0) resets = resets + 1;
        if (exp_status != 0) errors = errors + 1;
        if (tick_info.result_produced) produced = produced + 1;
        if (tick_info.result_accepted) consumed = consumed + 1;
        if (tick_info.input_first && old_busy) overlap_starts = overlap_starts + 1;
        if (tick_info.result_accepted && tick_info.result_produced) pop_push = pop_push + 1;
        if (tick_info.result_accepted && tick_info.input_first) consume_start = consume_start + 1;
        if (dut.ctrl_q.result_count == 2) full_fifo = full_fifo + 1;
        n = n + 1;
      end else if (rc != -1) begin
        fail($sformatf("malformed vector file: got %0d fields", rc));
      end
    end
    $fclose(fd);
    if (n == 0) $fatal(1, "Empty vector file");
    $display("ALL PASS C/SV: %0d records, %0d resets, %0d RTL rejection cases", n, resets, errors);
    $display("  published=%0d consumed=%0d overlap_starts=%0d", produced, consumed, overlap_starts);
    $display("  pop_and_push=%0d consume_and_start=%0d full_fifo_cycles=%0d", pop_push, consume_start, full_fifo);
    $finish;
  end
endmodule
