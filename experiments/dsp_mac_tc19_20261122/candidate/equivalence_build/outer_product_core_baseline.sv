`timescale 1ns/1ps

// Isolated signed 19-bit accumulation with exact INT32 external results.
// External timing and strict error/credit handling match the production core.
// One packet describes one k slice; reserve a result slot on its first slice.
module outer_product_core_baseline (
  input logic clk, rst_n, in_valid, result_ready,
  input tensor_core_pkg::tc_sparse_payload_t in_packet,
  output logic in_ready, result_valid, busy,
  output tensor_core_pkg::tc_matrix_t result,
  output tensor_core_pkg::tc_status_t status,
  output tensor_core_pkg::tc_tick_info_t tick_info
);
  import tensor_core_pkg::*;
  logic [2:0] next_k;
  logic [1:0] outstanding, result_count;
  logic publish_q;
  // Eight signed INT8 products fit in [-130048, 131072], including every
  // partial sum. This requires 19 signed bits (18 cannot hold +131072).
  // No cross-K-tile accumulation is supported by the unchanged contract.
  localparam int ACC_W = 19;
  typedef logic [7:0][7:0][ACC_W-1:0] acc_matrix_t;
  acc_matrix_t acc_q, result_q, tail_q;
  // Preserve the existing full-width observation names without extra storage.
  tc_matrix_t tail, acc;
  function automatic logic signed [ACC_W-1:0] product_to_acc(
      input logic [15:0] value);
    return {{(ACC_W-16){value[15]}}, value};
  endfunction
  typedef struct packed {
    logic valid, first, last;
    tc_lane_data_t a_value, b_value;
    logic [7:0] a_present, b_present;
  } operand_reg_t;
  typedef struct packed {
    logic valid, first, last;
    logic [7:0] a_present, b_present;
  } product_meta_t;
  operand_reg_t operand_q;
  product_meta_t product_meta_q;
  wire [7:0][7:0][15:0] product_q;
  wire [7:0][7:0][ACC_W-1:0] acc_sum;
  wire [7:0][7:0] a_select, b_select, acc_enable;
  wire [7:0] a_present, b_present;
  tc_lane_data_t routed_a, routed_b;

  assign busy = outstanding != 0;
  assign result_valid = result_count != 0;
  assign in_ready = (next_k != 0) || (outstanding < 2'd2);
  always_comb begin
    status = TC_OK;
    if (in_valid && !in_ready) status = TC_NOT_READY;
    else if (in_valid && (!valid_vector(in_packet.a.count, in_packet.a.index) ||
                          !valid_vector(in_packet.b.count, in_packet.b.index)))
      status = TC_BAD_SPARSE_VECTOR;
  end

  wire first = in_valid && next_k == 0;
  wire last = in_valid && next_k == 7;
  wire pop = result_valid && result_ready;
  wire empty_after_pop = result_count == {1'b0, pop};
  // A rejected input freezes every stage, including a pending multiply.
  wire capture_product = rst_n && operand_q.valid && status == TC_OK;
  for (genvar i=0; i<TC_DIM; i++) begin : g_row
    for (genvar j=0; j<TC_DIM; j++) begin : g_col
      assign result[i][j] = {{(32-ACC_W){result_q[i][j][ACC_W-1]}}, result_q[i][j]};
      assign tail[i][j] = {{(32-ACC_W){tail_q[i][j][ACC_W-1]}}, tail_q[i][j]};
      assign acc[i][j] = {{(32-ACC_W){acc_q[i][j][ACC_W-1]}}, acc_q[i][j]};
      (* use_dsp = "yes" *) wire signed [15:0] product =
          mul_int8(operand_q.a_value[i], operand_q.b_value[j]);
      logic signed [15:0] p;
      always_ff @(posedge clk)
        if (capture_product) p <= product;
      assign product_q[i][j] = p;
      assign acc_enable[i][j] = product_meta_q.a_present[i] &&
                                product_meta_q.b_present[j];
      // Keep accumulation in fabric at the authorized narrower width. Otherwise synthesis can
      // duplicate the multiplier into an additional DSP multiply-add cone.
      (* use_dsp = "no" *) wire signed [ACC_W-1:0] fabric_sum =
          $signed(acc_q[i][j]) + product_to_acc(product_q[i][j]);
      assign acc_sum[i][j] = fabric_sum;
    end
  end

  // Each operand is independently scattered into original coordinates.
  // Legal sorted indices make each destination select zero or one source.
  function automatic logic [7:0] route_or8(
      input logic [7:0][7:0] words);
    logic [3:0][7:0] level1;
    logic [1:0][7:0] level2;
    for (int n = 0; n < 4; n = n + 1)
      level1[n] = words[2*n] | words[2*n+1];
    for (int n = 0; n < 2; n = n + 1)
      level2[n] = level1[2*n] | level1[2*n+1];
    return level2[0] | level2[1];
  endfunction

  generate
    for (genvar coord = 0; coord < TC_DIM; coord = coord + 1) begin : g_route_decode
      for (genvar rank = 0; rank < TC_DIM; rank = rank + 1) begin : g_rank
        assign a_select[coord][rank] =
            (rank < int'(in_packet.a.count)) &&
            (in_packet.a.index[rank] == TC_INDEX_W'(coord));
        assign b_select[coord][rank] =
            (rank < int'(in_packet.b.count)) &&
            (in_packet.b.index[rank] == TC_INDEX_W'(coord));
      end
      wire [7:0][7:0] a_terms, b_terms;
      for (genvar rank = 0; rank < TC_DIM; rank = rank + 1) begin : g_data
        assign a_terms[rank] = {8{a_select[coord][rank]}} & in_packet.a.value[rank];
        assign b_terms[rank] = {8{b_select[coord][rank]}} & in_packet.b.value[rank];
      end
      assign a_present[coord] = |a_select[coord];
      assign b_present[coord] = |b_select[coord];
      assign routed_a[coord] = route_or8(a_terms);
      assign routed_b[coord] = route_or8(b_terms);
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      next_k <= '0;
      outstanding <= '0;
      result_count <= '0;
      operand_q <= '0;
      product_meta_q <= '0;
      publish_q <= 1'b0;
      result_q <= '0;
      tail_q <= '0;
      acc_q <= '0;
    end else if (status == TC_OK) begin
      if (in_valid) next_k <= next_k + 3'd1;
      outstanding <= outstanding + {1'b0, first} - {1'b0, pop};
      result_count <= result_count + {1'b0, publish_q} - {1'b0, pop};
      if (!busy && first) begin
        result_q <= '0;
        tail_q <= '0;
      end else begin
        if (publish_q && empty_after_pop) result_q <= acc_q;
        else if (pop && result_count == 2) result_q <= tail_q;
        if (publish_q && !empty_after_pop) tail_q <= acc_q;
      end
      operand_q.valid <= in_valid;
      operand_q.first <= first;
      operand_q.last <= last;
      if (in_valid) begin
        operand_q.a_value <= routed_a;
        operand_q.b_value <= routed_b;
        operand_q.a_present <= a_present;
        operand_q.b_present <= b_present;
      end
      product_meta_q.valid <= operand_q.valid;
      product_meta_q.first <= operand_q.first;
      product_meta_q.last <= operand_q.last;
      if (operand_q.valid) begin
        product_meta_q.a_present <= operand_q.a_present;
        product_meta_q.b_present <= operand_q.b_present;
      end
      publish_q <= product_meta_q.valid && product_meta_q.last;
      if (product_meta_q.valid) begin
        for (int i=0; i<TC_DIM; i++)
          for (int j=0; j<TC_DIM; j++) begin
            if (product_meta_q.first)
              acc_q[i][j] <= acc_enable[i][j] ? product_to_acc(product_q[i][j]) : '0;
            else if (acc_enable[i][j])
              acc_q[i][j] <= acc_sum[i][j];
          end
      end
    end
  end

  // Preserve the existing observation ABI exactly: mul denotes the first
  // pipeline phase (now operand routing), route denotes the second phase
  // (now multiplication). These legacy labels do not name physical work here.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) tick_info <= '0;
    else begin
      tick_info <= '0;
      if (status == TC_OK) begin
        tick_info.sparse_step <= busy || in_valid;
        tick_info.input_accepted <= in_valid;
        tick_info.input_first <= first;
        tick_info.input_last <= last;
        tick_info.input_k <= in_valid ? {1'b0,next_k} : '0;
        tick_info.mul <= in_valid;
        tick_info.route <= operand_q.valid;
        tick_info.acc <= product_meta_q.valid;
        tick_info.acc_first <= product_meta_q.valid && product_meta_q.first;
        tick_info.acc_last <= product_meta_q.valid && product_meta_q.last;
        tick_info.macs <= product_meta_q.valid ? 7'($countones(acc_enable)) : '0;
        tick_info.result_produced <= publish_q;
        tick_info.result_accepted <= pop;
      end
    end
  end
endmodule
