`timescale 1ns/1ps

// Standalone common-stimulus comparison against the unchanged production core.
// The additional matrix oracle uses original coordinates, independently of
// either RTL routing network. Existing tests, seeds and vectors are untouched.
module tb_pre_route_equiv;
  import tensor_core_pkg::*;
  logic clk = 0, rst_n = 1, in_valid = 0, result_ready = 0;
  tc_sparse_payload_t in_packet;
  logic ref_ready, dut_ready, ref_valid, dut_valid, ref_busy, dut_busy;
  tc_matrix_t ref_result, dut_result;
  tc_status_t ref_status, dut_status;
  tc_tick_info_t ref_info, dut_info;
  bit passed = 0;
  outer_product_core_baseline reference_core (
    .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .result_ready(result_ready),
    .in_packet(in_packet), .in_ready(ref_ready), .result_valid(ref_valid),
    .busy(ref_busy), .result(ref_result), .status(ref_status), .tick_info(ref_info)
  );
  outer_product_core candidate_core (
    .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .result_ready(result_ready),
    .in_packet(in_packet), .in_ready(dut_ready), .result_valid(dut_valid),
    .busy(dut_busy), .result(dut_result), .status(dut_status), .tick_info(dut_info)
  );

  tc_matrix_t expected_results[$];
  int publication_due[$];
  tc_matrix_t expected_acc, consumed;
  int input_k = 0, advancing = 0;
  int edges = 0, accepted = 0, completed = 0, publications = 0;
  int rejected = 0, malformed = 0, full_rejects = 0, resets = 0;
  int simultaneous = 0, stored_zero = 0, bitmap_pairs = 0;
  logic [31:0] random_state = 32'h7a913b65;

  function automatic logic [31:0] next_random();
    random_state = random_state ^ (random_state << 13);
    random_state = random_state ^ (random_state >> 17);
    random_state = random_state ^ (random_state << 5);
    return random_state;
  endfunction

  function automatic tc_sparse_vector_t make_vector(input logic [7:0] mask, input int salt);
    tc_sparse_vector_t vector_data;
    int rank;
    vector_data = '0;
    rank = 0;
    // Padding deliberately carries arbitrary nonzero data and indices.
    for (int n = 0; n < 8; n++) begin
      vector_data.value[n] = 8'(salt + 41*n + 1);
      vector_data.index[n] = 3'(7-n);
    end
    for (int coord = 0; coord < 8; coord++) begin
      if (mask[coord]) begin
        vector_data.index[rank] = 3'(coord);
        case ((salt + coord) % 6)
          0: vector_data.value[rank] = 8'h80;
          1: vector_data.value[rank] = 8'h7f;
          2: vector_data.value[rank] = 8'h00;
          3: vector_data.value[rank] = 8'hff;
          4: vector_data.value[rank] = 8'h01;
          default: vector_data.value[rank] = 8'(salt ^ (coord*29));
        endcase
        rank++;
      end
    end
    vector_data.count = 4'(rank);
    return vector_data;
  endfunction

  task automatic compare_state;
    if ({dut_ready,dut_valid,dut_busy,dut_status} !==
        {ref_ready,ref_valid,ref_busy,ref_status})
      $fatal(1, "Interface mismatch at edge %0d", edges);
    if (dut_result !== ref_result || dut_info !== ref_info ||
        candidate_core.tail !== reference_core.tail ||
        candidate_core.acc !== reference_core.acc ||
        candidate_core.next_k !== reference_core.next_k ||
        candidate_core.outstanding !== reference_core.outstanding ||
        candidate_core.result_count !== reference_core.result_count)
      $fatal(1, "State/payload/event mismatch at edge %0d", edges);
  endtask

  task automatic step;
    bit expect_publish;
    int i, j, product;
    #1;
    compare_state();
    expect_publish = 0;
    if (!rst_n) begin
      expected_results.delete();
      publication_due.delete();
      expected_acc = '0;
      input_k = 0;
      advancing = 0;
      resets++;
    end else if (ref_status == TC_OK) begin
      if (publication_due.size() != 0 && publication_due[0] == advancing) begin
        expect_publish = 1;
        void'(publication_due.pop_front());
      end
      if (ref_valid && result_ready) begin
        if (expected_results.size() == 0) $fatal(1, "Unexpected result");
        consumed = expected_results.pop_front();
        if (ref_result !== consumed || dut_result !== consumed)
          $fatal(1, "Independent GEMM mismatch at edge %0d", edges);
        completed++;
        if (in_valid) simultaneous++;
      end
      if (in_valid) begin
        if (input_k == 0) expected_acc = '0;
        for (int p = 0; p < int'(in_packet.a.count); p++) begin
          if (in_packet.a.value[p] == 0) stored_zero++;
          for (int r = 0; r < int'(in_packet.b.count); r++) begin
            i = int'(in_packet.a.index[p]);
            j = int'(in_packet.b.index[r]);
            product = int'($signed(in_packet.a.value[p])) * int'($signed(in_packet.b.value[r]));
            expected_acc[i][j] = 32'($signed(expected_acc[i][j]) + product);
          end
        end
        if (input_k == 7) begin
          expected_results.push_back(expected_acc);
          publication_due.push_back(advancing + 3);
        end
        input_k = (input_k + 1) % 8;
        accepted++;
      end
      advancing++;
    end else begin
      rejected++;
      if (ref_status == TC_BAD_SPARSE_VECTOR) malformed++;
      if (ref_status == TC_NOT_READY) full_rejects++;
    end
    clk = 1; #1;
    compare_state();
    if (dut_info.result_produced !== expect_publish)
      $fatal(1, "Publication latency mismatch at edge %0d", edges);
    if (expect_publish) publications++;
    clk = 0; #1;
    edges++;
  endtask

  task automatic reset_core;
    rst_n = 0; in_valid = 0; result_ready = 0; step(); rst_n = 1;
  endtask

  task automatic drain;
    in_valid = 0; result_ready = 1;
    repeat (20) step();
    if (expected_results.size() != 0 || publication_due.size() != 0 || ref_busy)
      $fatal(1, "Drain incomplete");
  endtask

  initial begin
    logic [31:0] random_bits;
    in_packet = '0;
    reset_core();
    // Exhaust every pair of legal A/B coordinate subsets (including empty
    // and full vectors). Padding values are not allowed to affect results.
    for (int a_mask = 0; a_mask < 256; a_mask++) begin
      for (int b_mask = 0; b_mask < 256; b_mask++) begin
        result_ready = 1; in_valid = 0; #1;
        while (!ref_ready) step();
        in_packet.a = make_vector(8'(a_mask), a_mask + b_mask);
        in_packet.b = make_vector(8'(b_mask), a_mask + 2*b_mask + 1);
        in_valid = 1; step(); bitmap_pairs++;
      end
    end
    drain();
    // Random bubbles, full-result offers, malformed metadata and resets in
    // flight. The strict contract rejects an entire edge, including a pop.
    for (int cycle = 0; cycle < 24000; cycle++) begin
      random_bits = next_random();
      rst_n = (cycle % 137 != 0);
      in_valid = (random_bits[3:0] != 0);
      result_ready = random_bits[7:4] < 4'd7;
      in_packet.a = make_vector(random_bits[15:8], cycle);
      in_packet.b = make_vector(random_bits[23:16], cycle + 11);
      case (random_bits[27:24])
        0: in_packet.a.count = 4'd9;
        1: begin in_packet.b.count = 4'd2; in_packet.b.index[0] = 3'd4; in_packet.b.index[1] = 3'd4; end
        2: begin in_packet.a.count = 4'd2; in_packet.a.index[0] = 3'd7; in_packet.a.index[1] = 3'd1; end
        default: ;
      endcase
      step();
    end
    reset_core();
    // Explicit full-credit rejection on a simultaneous requested result pop.
    in_packet.a = make_vector(8'hff, 0);
    in_packet.b = make_vector(8'hff, 1);
    in_valid = 1; result_ready = 0;
    repeat (16) step();
    result_ready = 1; step();
    drain();
    if (bitmap_pairs != 65536 || completed < 8194 || malformed == 0 ||
        full_rejects == 0 || simultaneous == 0 || stored_zero == 0)
      $fatal(1, "Insufficient test coverage");
    $display("PRE_ROUTE EQUIVALENCE PASS edges=%0d bitmap_pairs=%0d accepted=%0d completed=%0d publications=%0d malformed=%0d full_rejects=%0d resets=%0d simultaneous=%0d stored_zero=%0d seed=7a913b65",
      edges, bitmap_pairs, accepted, completed, publications, malformed,
      full_rejects, resets, simultaneous, stored_zero);
    passed = 1; $finish;
  end
endmodule
