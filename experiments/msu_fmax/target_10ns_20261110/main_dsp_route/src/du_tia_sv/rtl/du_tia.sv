`timescale 1ns/1ps

/* Compact DU/TIA RTL with no SystemVerilog assertions. */
module du_tia (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       in_valid,
  input  wire du_tia_pkg::du_tia_input_t  in_packet,
  output logic                       out_valid,
  output du_tia_pkg::du_tia_output_t out_packet
);
  import du_tia_pkg::*;

  s0_reg_t s0_q;
  s1_reg_t s1_q;
  s2_reg_t s2_q;
  s3_reg_t s3_q;

  s0_reg_t s0_d;
  s1_reg_t s1_d;
  s2_reg_t s2_d;
  s3_reg_t s3_d;

  /* S0: register only the tagged, mode-selected input payload. */
  always_comb begin : s0_comb
    s0_d       = '0;
    s0_d.valid = in_valid;
    if (in_valid) begin
      s0_d.packet = in_packet;
    end
  end

  /* S1: DU forward/decode and TIA four-bit predecode. */
  always_comb begin : s1_comb
    int unsigned lane_index;
    int unsigned column_index;
    bitmap_t a_bitmap;
    bitmap_t b_bitmap;
    count_t a_count;
    count_t b_count;

    s1_d       = '0;
    s1_d.valid = s0_q.valid;
    a_bitmap   = '0;
    b_bitmap   = '0;
    a_count    = '0;
    b_count    = '0;

    if (s0_q.valid) begin
      case (s0_q.packet.mode)
        MODE_DENSE_DENSE: begin
          s1_d.is_sparse             = 1'b0;
          s1_d.payload.dense.dense_a =
              s0_q.packet.payload.dense.dense_a;
          s1_d.payload.dense.dense_b =
              s0_q.packet.payload.dense.dense_b;
        end

        MODE_UNSTRUCTURED_2TO4: begin
          s1_d.is_sparse = 1'b1;

          /* A is already packed; only its valid prefix is forwarded. */
          a_bitmap = s0_q.packet.payload.hybrid.a_bitmap;
          a_count  = popcount8(a_bitmap);
          s1_d.payload.sparse.a.count = a_count;
          for (lane_index = 0; lane_index < VECTOR_LANES;
               lane_index++) begin
            if (lane_index < a_count) begin
              s1_d.payload.sparse.a.value[lane_index] =
                  s0_q.packet.payload.hybrid.a_packed[lane_index];
            end
          end

          /*
           * Select the B value at k_position from each column's 2:4 group,
           * then condense the hits. The source rank is consumed here and is
           * deliberately not stored in any pipeline register.
           */
          for (column_index = 0; column_index < N_DIM; column_index++) begin
            if (s0_q.packet.payload.hybrid.b_2to4_mask[column_index]
                                                 [s0_q.packet.k_position]) begin
              b_bitmap[column_index] = 1'b1;
              s1_d.payload.sparse.b.value[b_count] =
                  s0_q.packet.payload.hybrid.b_2to4_packed[column_index]
                      [packed_rank_before(
                          s0_q.packet.payload.hybrid
                              .b_2to4_mask[column_index],
                          s0_q.packet.k_position)];
              b_count = b_count + 1'b1;
            end
          end
          s1_d.payload.sparse.b.count = b_count;
        end

        MODE_UNSTRUCTURED_UNSTRUCTURED: begin
          s1_d.is_sparse = 1'b1;

          a_bitmap = s0_q.packet.payload.dual.a_bitmap;
          b_bitmap = s0_q.packet.payload.dual.b_bitmap;
          a_count  = popcount8(a_bitmap);
          b_count  = popcount8(b_bitmap);
          s1_d.payload.sparse.a.count = a_count;
          s1_d.payload.sparse.b.count = b_count;

          for (lane_index = 0; lane_index < VECTOR_LANES;
               lane_index++) begin
            if (lane_index < a_count) begin
              s1_d.payload.sparse.a.value[lane_index] =
                  s0_q.packet.payload.dual.a_packed[lane_index];
            end
            if (lane_index < b_count) begin
              s1_d.payload.sparse.b.value[lane_index] =
                  s0_q.packet.payload.dual.b_packed[lane_index];
            end
          end
        end

        default: begin
          /* The simulation-only input contract below reports this case. */
          s1_d.is_sparse = 1'b0;
        end
      endcase

      if (s1_d.is_sparse) begin
        s1_d.payload.sparse.a_low  = tia_decode_half(a_bitmap, 1'b0);
        s1_d.payload.sparse.a_high = tia_decode_half(a_bitmap, 1'b1);
        s1_d.payload.sparse.b_low  = tia_decode_half(b_bitmap, 1'b0);
        s1_d.payload.sparse.b_high = tia_decode_half(b_bitmap, 1'b1);
      end
    end
  end

  /* S2: merge the two TIA halves into compact value/index vectors. */
  always_comb begin : s2_comb
    int unsigned lane_index;
    count_t merge_position_a;
    count_t merge_position_b;

    s2_d             = '0;
    s2_d.valid       = s1_q.valid;
    merge_position_a = '0;
    merge_position_b = '0;

    if (s1_q.valid) begin
      s2_d.packet.is_sparse = s1_q.is_sparse;
      if (!s1_q.is_sparse) begin
        s2_d.packet.payload.dense.dense_a =
            s1_q.payload.dense.dense_a;
        s2_d.packet.payload.dense.dense_b =
            s1_q.payload.dense.dense_b;
      end
      else begin
        s2_d.packet.payload.sparse.a.count =
            s1_q.payload.sparse.a.count;
        s2_d.packet.payload.sparse.a.value =
            s1_q.payload.sparse.a.value;
        s2_d.packet.payload.sparse.b.count =
            s1_q.payload.sparse.b.count;
        s2_d.packet.payload.sparse.b.value =
            s1_q.payload.sparse.b.value;

        for (lane_index = 0; lane_index < GROUP_SIZE; lane_index++) begin
          if (lane_index < s1_q.payload.sparse.a_low.count) begin
            s2_d.packet.payload.sparse.a.index[merge_position_a] =
                s1_q.payload.sparse.a_low.index[lane_index];
            merge_position_a = merge_position_a + 1'b1;
          end
        end
        for (lane_index = 0; lane_index < GROUP_SIZE; lane_index++) begin
          if (lane_index < s1_q.payload.sparse.a_high.count) begin
            s2_d.packet.payload.sparse.a.index[merge_position_a] =
                s1_q.payload.sparse.a_high.index[lane_index];
            merge_position_a = merge_position_a + 1'b1;
          end
        end

        for (lane_index = 0; lane_index < GROUP_SIZE; lane_index++) begin
          if (lane_index < s1_q.payload.sparse.b_low.count) begin
            s2_d.packet.payload.sparse.b.index[merge_position_b] =
                s1_q.payload.sparse.b_low.index[lane_index];
            merge_position_b = merge_position_b + 1'b1;
          end
        end
        for (lane_index = 0; lane_index < GROUP_SIZE; lane_index++) begin
          if (lane_index < s1_q.payload.sparse.b_high.count) begin
            s2_d.packet.payload.sparse.b.index[merge_position_b] =
                s1_q.payload.sparse.b_high.index[lane_index];
            merge_position_b = merge_position_b + 1'b1;
          end
        end
      end
    end
  end

  /* S3: final timing register; the S2 packet is already in TC-ready form. */
  always_comb begin : s3_comb
    s3_d       = '0;
    s3_d.valid = s2_q.valid;
    if (s2_q.valid) begin
      s3_d.packet = s2_q.packet;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s0_q <= '0;
      s1_q <= '0;
      s2_q <= '0;
      s3_q <= '0;
    end
    else begin
      s0_q <= s0_d;
      s1_q <= s1_d;
      s2_q <= s2_d;
      s3_q <= s3_d;
    end
  end

  always_comb begin
    out_valid  = s3_q.valid;
    out_packet = s3_q.packet;
  end

endmodule
