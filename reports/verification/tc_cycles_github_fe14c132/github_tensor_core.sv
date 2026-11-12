`timescale 1ns/1ps

// Cycle-equivalent translation of the supplied tensor_core_model.c.
// Strict C API contract: in_valid while not ready, a mode violation, or a
// malformed sparse vector rejects the ENTIRE edge (including output consume).
// Producer must check in_ready BEFORE pulsing in_valid.
// Timing revision: factor sparse routing into two parallel 8-way selector
// banks. No new registers, ports, pipeline cycles, or packet formats.
module tensor_core (
  input  logic clk,
  input  logic rst_n,
  input  logic in_valid,
  input  wire tensor_core_pkg::tc_input_packet_t in_packet,
  output logic in_ready,
  output logic input_ready, // tc_input_ready(): independent of offered mode.
  input  logic result_ready,
  output logic result_valid,
  output tensor_core_pkg::tc_matrix_t result,
  output logic busy,
  output tensor_core_pkg::tc_status_t status,
  output tensor_core_pkg::tc_tick_info_t tick_info
);
  import tensor_core_pkg::*;

  tc_control_t ctrl_q, ctrl_d;
  tc_dense_state_t dense_q, dense_d;
  tc_sparse_state_t sparse_q, sparse_d;
  tc_tick_info_t info_q, info_d;

  // ROUTE is computed from OLD MUL registers. Epoch/busy/valid controls are
  // applied when committing the mapped result in next_state, rather than
  // zero-muxing every product/index before a long scatter-write network.
  wire [7:0][7:0] route_a_match, route_b_match;
  wire [7:0][7:0] route_a_select, route_b_select;
  wire [7:0] route_a_present, route_b_present;
  wire [7:0][7:0][15:0] route_column_data, route_delta;
  wire [7:0][7:0] route_enable;

  // Balanced reduction of eight one-hot-masked 16-bit data words.
  function automatic logic [15:0] route_or8(
      input logic [7:0][15:0] words);
    logic [3:0][15:0] level1;
    logic [1:0][15:0] level2;
    for (int n = 0; n < 4; n = n + 1)
      level1[n] = words[2*n] | words[2*n+1];
    for (int n = 0; n < 2; n = n + 1)
      level2[n] = level1[2*n] | level1[2*n+1];
    return level2[0] | level2[1];
  endfunction

  generate
    for (genvar coord = 0; coord < TC_DIM; coord = coord + 1) begin : g_route_decode
      for (genvar rank = 0; rank < TC_DIM; rank = rank + 1) begin : g_rank
        assign route_a_match[coord][rank] =
            (rank < int'(sparse_q.mul.a_count)) &&
            (sparse_q.mul.a_index[rank] == TC_INDEX_W'(coord));
        assign route_b_match[coord][rank] =
            (rank < int'(sparse_q.mul.b_count)) &&
            (sparse_q.mul.b_index[rank] == TC_INDEX_W'(coord));

        // Legal vectors already have unique indices. Keep the last matching
        // rank even for duplicate indices, preserving the old loop's exact
        // overwrite priority without a 64-entry data priority chain.
        if (rank == TC_DIM-1) begin : g_last
          assign route_a_select[coord][rank] = route_a_match[coord][rank];
          assign route_b_select[coord][rank] = route_b_match[coord][rank];
        end else begin : g_lower
          assign route_a_select[coord][rank] = route_a_match[coord][rank] &&
              !(|route_a_match[coord][TC_DIM-1:rank+1]);
          assign route_b_select[coord][rank] = route_b_match[coord][rank] &&
              !(|route_b_match[coord][TC_DIM-1:rank+1]);
        end
      end
      assign route_a_present[coord] = |route_a_match[coord];
      assign route_b_present[coord] = |route_b_match[coord];
    end

    // B routing: for each packed A rank p, select original B column j.
    for (genvar p = 0; p < TC_DIM; p = p + 1) begin : g_route_columns
      for (genvar j = 0; j < TC_DIM; j = j + 1) begin : g_column
        wire [7:0][15:0] terms;
        for (genvar r = 0; r < TC_DIM; r = r + 1) begin : g_term
          assign terms[r] = {16{route_b_select[j][r]}} &
                            sparse_q.mul.product[p][r];
        end
        assign route_column_data[p][j] = route_or8(terms);
      end
    end

    // A routing: select original row i for each already mapped column j.
    // Both banks are combinational inside the existing single ROUTE stage.
    for (genvar i = 0; i < TC_DIM; i = i + 1) begin : g_route_rows
      for (genvar j = 0; j < TC_DIM; j = j + 1) begin : g_column
        wire [7:0][15:0] terms;
        for (genvar p = 0; p < TC_DIM; p = p + 1) begin : g_term
          assign terms[p] = {16{route_a_select[i][p]}} &
                            route_column_data[p][j];
        end
        assign route_delta[i][j] = route_or8(terms);
        assign route_enable[i][j] = route_a_present[i] && route_b_present[j];
      end
    end
  endgenerate

  assign result_valid = ctrl_q.result_valid;
  assign result = ctrl_q.result;
  assign busy = ctrl_q.busy;
  assign tick_info = info_q;

  // Readiness only uses OLD registers: result_ready has no bypass path.
  always_comb begin : input_contract
    input_ready = 1'b0;
    if (!ctrl_q.busy)
      input_ready = 1'b1;
    else if (ctrl_q.is_sparse)
      input_ready = (ctrl_q.received != 0) || (int'(ctrl_q.outstanding) < TC_RESULT_SLOTS);
    else
      input_ready = !ctrl_q.result_valid && !ctrl_q.finish_pending &&
                    (int'(ctrl_q.received) < TC_K);
    in_ready = input_ready &&
               (!ctrl_q.busy || (ctrl_q.is_sparse == in_packet.is_sparse));
    status = TC_OK;
    if (in_valid) begin
      // Preserve tc_tick() error precedence.
      if (!input_ready)
        status = TC_NOT_READY;
      else if (ctrl_q.busy && (ctrl_q.is_sparse != in_packet.is_sparse))
        status = TC_MODE_CHANGE;
      else if (in_packet.is_sparse &&
               (!valid_vector(in_packet.payload.sparse.a.count, in_packet.payload.sparse.a.index) ||
                !valid_vector(in_packet.payload.sparse.b.count, in_packet.payload.sparse.b.index)))
        status = TC_BAD_SPARSE_VECTOR;
    end
  end

  always_comb begin : next_state
    tc_dense_state_t dense_base;
    tc_sparse_state_t sparse_base;
    tc_token_t [7:0] left, top;
    tc_token_t a, b;
    logic signed [15:0] product;
    logic old_result_valid, run_pipeline, first, last;

    ctrl_d = ctrl_q;
    dense_d = dense_q;
    sparse_d = sparse_q;
    dense_base = dense_q;
    sparse_base = sparse_q;
    info_d = '0;
    left = '0;
    top = '0;
    a = '0;
    b = '0;
    product = '0;
    first = 1'b0;
    last = 1'b0;
    old_result_valid = ctrl_q.result_valid;
    run_pipeline = 1'b0;

    if (status == TC_OK) begin
      // FIFO pop first. Newly published data cannot be consumed on this edge.
      if (old_result_valid && result_ready) begin
        if (ctrl_q.result_count == 2)
          ctrl_d.result = ctrl_q.result_next;
        ctrl_d.result_count = ctrl_d.result_count - 2'd1;
        ctrl_d.outstanding = ctrl_d.outstanding - 2'd1;
        ctrl_d.result_valid = (ctrl_d.result_count != 0);
        info_d.result_accepted = 1'b1;
        // Like C, invalid physical slots retain their last contents.
      end

      // Only OLD busy defines a new epoch. A same-edge consume/start must
      // never reset the new input after decrementing outstanding to zero.
      if (!ctrl_q.busy) begin
        if (in_valid) begin
          ctrl_d = '0;
          ctrl_d.busy = 1'b1;
          ctrl_d.is_sparse = in_packet.is_sparse;
          dense_base = '0;
          sparse_base = '0;
          dense_d = '0;
          sparse_d = '0;
          run_pipeline = 1'b1;
        end
      end else begin
        run_pipeline = 1'b1;
      end

      if (run_pipeline) begin
        if (!ctrl_d.is_sparse && old_result_valid) begin
          ctrl_d.busy = (ctrl_d.outstanding != 0);
          run_pipeline = 1'b0;
        end else if (ctrl_d.finish_pending) begin
          // Publish OLD accumulator before sparse ACC first can clear it.
          if (ctrl_d.result_count == 0) begin
            if (ctrl_d.is_sparse)
              ctrl_d.result = sparse_base.acc;
            else
              for (int i = 0; i < TC_DIM; i = i + 1)
                for (int j = 0; j < TC_DIM; j = j + 1)
                  ctrl_d.result[i][j] = dense_base.pe[i][j].acc;
          end else begin
            if (ctrl_d.is_sparse)
              ctrl_d.result_next = sparse_base.acc;
            else
              for (int i = 0; i < TC_DIM; i = i + 1)
                for (int j = 0; j < TC_DIM; j = j + 1)
                  ctrl_d.result_next[i][j] = dense_base.pe[i][j].acc;
          end
          ctrl_d.result_count = ctrl_d.result_count + 2'd1;
          ctrl_d.result_valid = 1'b1;
          ctrl_d.finish_pending = 1'b0;
          info_d.result_produced = 1'b1;
          if (!ctrl_d.is_sparse) run_pipeline = 1'b0;
        end
      end

      if (run_pipeline) begin
        if (in_valid) begin
          info_d.input_accepted = 1'b1;
          info_d.input_k = ctrl_d.received;
          first = (ctrl_d.received == 0);
          last = (ctrl_d.received == 7);
          info_d.input_first = first;
          info_d.input_last = last;
          if (first) ctrl_d.outstanding = ctrl_d.outstanding + 2'd1;
          if (ctrl_d.is_sparse && last) ctrl_d.received = '0;
          else ctrl_d.received = ctrl_d.received + 4'd1;
        end
        ctrl_d.finish_pending = 1'b0;

        if (ctrl_d.is_sparse) begin
          info_d.sparse_step = 1'b1;
          sparse_d.mul = '0;
          sparse_d.route = '0;

          // ACC reads ONLY the old ROUTE, not this edge's new routing.
          if (sparse_base.route.valid) begin
            info_d.acc = 1'b1;
            info_d.acc_first = sparse_base.route.first;
            info_d.acc_last = sparse_base.route.last;
            if (sparse_base.route.first) sparse_d.acc = '0;
            for (int i = 0; i < TC_DIM; i = i + 1)
              for (int j = 0; j < TC_DIM; j = j + 1)
                if (sparse_base.route.enable[i][j]) begin
                  sparse_d.acc[i][j] = $signed(sparse_d.acc[i][j]) +
                                      extend_product(sparse_base.route.delta[i][j]);
                  info_d.macs = info_d.macs + 7'd1;
                end
            ctrl_d.finish_pending = sparse_base.route.last;
          end

          // ROUTE: commit the parallel, factored mapping of OLD MUL data.
          // The original sparse_base.mul.valid guard suppresses stale data
          // on a new epoch and preserves bubbles, rejects, and mode changes.
          if (sparse_base.mul.valid) begin
            info_d.route = 1'b1;
            sparse_d.route.valid = 1'b1;
            sparse_d.route.first = sparse_base.mul.first;
            sparse_d.route.last = sparse_base.mul.last;
            sparse_d.route.enable = route_enable;
            sparse_d.route.delta = route_delta;
          end

          // MUL: signed 8x8 products; stored zero values remain valid work.
          if (in_valid) begin
            info_d.mul = 1'b1;
            sparse_d.mul.valid = 1'b1;
            sparse_d.mul.first = first;
            sparse_d.mul.last = last;
            sparse_d.mul.a_count = in_packet.payload.sparse.a.count;
            sparse_d.mul.b_count = in_packet.payload.sparse.b.count;
            sparse_d.mul.a_index = in_packet.payload.sparse.a.index;
            sparse_d.mul.b_index = in_packet.payload.sparse.b.index;
          end
        end else begin
          info_d.dense_step = 1'b1;
          // Lane i uses i skew registers. All lanes advance on bubbles too.
          for (int lane = 0; lane < TC_DIM; lane = lane + 1) begin
            a = '0;
            b = '0;
            if (in_valid) begin
              a.valid = 1'b1;
              b.valid = 1'b1;
              a.last = last;
              b.last = last;
              a.value = in_packet.payload.dense.dense_a[lane];
              b.value = in_packet.payload.dense.dense_b[lane];
            end
            if (lane == 0) begin
              left[lane] = a;
              top[lane] = b;
            end else begin
              left[lane] = dense_base.a_delay[lane][lane-1];
              top[lane] = dense_base.b_delay[lane][lane-1];
              for (int n = 1; n < TC_DIM-1; n = n + 1)
                if (n < lane) begin
                  dense_d.a_delay[lane][n] = dense_base.a_delay[lane][n-1];
                  dense_d.b_delay[lane][n] = dense_base.b_delay[lane][n-1];
                end
              dense_d.a_delay[lane][0] = a;
              dense_d.b_delay[lane][0] = b;
            end
          end
        end

        // One 8x8 multiplier bank is shared between the two modes. Dense
        // selects aligned PE operands; sparse selects packed-rank operands.
        for (int i = 0; i < TC_DIM; i = i + 1)
          for (int j = 0; j < TC_DIM; j = j + 1) begin
            a = '0;
            b = '0;
            if (ctrl_d.is_sparse) begin
              if (in_valid && (i < int'(in_packet.payload.sparse.a.count)) &&
                              (j < int'(in_packet.payload.sparse.b.count))) begin
                a.valid = 1'b1;
                b.valid = 1'b1;
                a.value = in_packet.payload.sparse.a.value[i];
                b.value = in_packet.payload.sparse.b.value[j];
              end
            end else begin
              if (j == 0) a = left[i];
              else a = dense_base.pe[i][j-1].a;
              if (i == 0) b = top[j];
              else b = dense_base.pe[i-1][j].b;
            end
            product = mul_int8(a.value, b.value);
            if (ctrl_d.is_sparse) begin
              if (a.valid && b.valid) sparse_d.mul.product[i][j] = product;
            end else begin
              dense_d.pe[i][j].a = a;
              dense_d.pe[i][j].b = b;
              if (a.valid && b.valid) begin
                dense_d.pe[i][j].acc = dense_base.pe[i][j].acc +
                                      extend_product(product);
                info_d.macs = info_d.macs + 7'd1;
                if ((i == TC_DIM-1) && (j == TC_DIM-1) && a.last)
                  ctrl_d.finish_pending = 1'b1;
              end
            end
          end
        ctrl_d.busy = (ctrl_d.outstanding != 0);
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_q <= '0;
      dense_q <= '0;
      sparse_q <= '0;
      info_q <= '0;
    end else begin
      ctrl_q <= ctrl_d;
      dense_q <= dense_d;
      sparse_q <= sparse_d;
      info_q <= info_d;
    end
  end
endmodule
