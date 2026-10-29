`timescale 1ns/1ps

package du_tia_pkg;

  localparam int unsigned DATA_W         = 8;
  localparam int unsigned VECTOR_LANES   = 8;
  localparam int unsigned N_DIM          = 8;
  localparam int unsigned GROUP_SIZE     = 4;
  localparam int unsigned KEEP_PER_GROUP = 2;

  localparam int unsigned INDEX_W      = $clog2(VECTOR_LANES);
  localparam int unsigned COUNT_W      = $clog2(VECTOR_LANES + 1);
  localparam int unsigned HALF_COUNT_W = $clog2(GROUP_SIZE + 1);
  localparam int unsigned GROUP_POS_W  = $clog2(GROUP_SIZE);

  typedef logic [DATA_W-1:0] data_t;
  typedef logic [VECTOR_LANES-1:0] bitmap_t;
  typedef logic [VECTOR_LANES-1:0][DATA_W-1:0] lane_data_t;
  typedef logic [INDEX_W-1:0] index_t;
  typedef logic [VECTOR_LANES-1:0][INDEX_W-1:0] index_vec_t;
  typedef logic [COUNT_W-1:0] count_t;
  typedef logic [HALF_COUNT_W-1:0] half_count_t;
  typedef logic [GROUP_POS_W-1:0] group_position_t;
  typedef logic [N_DIM-1:0][GROUP_SIZE-1:0] mask2to4_vec_t;
  typedef logic [N_DIM-1:0][KEEP_PER_GROUP-1:0][DATA_W-1:0]
      packed2to4_vec_t;

  typedef enum logic [1:0] {
    MODE_DENSE_DENSE               = 2'd0,
    MODE_UNSTRUCTURED_2TO4         = 2'd1,
    MODE_UNSTRUCTURED_UNSTRUCTURED = 2'd2
  } compiler_mode_e;

  /*
   * The input is a tagged packed union. Only the member selected by mode is
   * physically carried, instead of carrying dense, hybrid, and dual-sparse
   * payloads in parallel. The reserved fields only equalize union widths;
   * they are ignored and are not registered as useful state.
   */
  localparam int unsigned DENSE_PAYLOAD_W =
      2 * VECTOR_LANES * DATA_W;
  localparam int unsigned HYBRID_PAYLOAD_W =
      VECTOR_LANES +
      VECTOR_LANES * DATA_W +
      N_DIM * GROUP_SIZE +
      N_DIM * KEEP_PER_GROUP * DATA_W;
  localparam int unsigned DUAL_PAYLOAD_W =
      2 * (VECTOR_LANES + VECTOR_LANES * DATA_W);
  localparam int unsigned INPUT_PAYLOAD_W = HYBRID_PAYLOAD_W;

  typedef struct packed {
    lane_data_t dense_a;
    lane_data_t dense_b;
    logic [INPUT_PAYLOAD_W-DENSE_PAYLOAD_W-1:0] reserved;
  } dense_input_payload_t;

  typedef struct packed {
    bitmap_t          a_bitmap;
    lane_data_t       a_packed;
    mask2to4_vec_t    b_2to4_mask;
    packed2to4_vec_t  b_2to4_packed;
  } hybrid_input_payload_t;

  typedef struct packed {
    bitmap_t       a_bitmap;
    lane_data_t    a_packed;
    bitmap_t       b_bitmap;
    lane_data_t    b_packed;
    logic [INPUT_PAYLOAD_W-DUAL_PAYLOAD_W-1:0] reserved;
  } dual_input_payload_t;

  typedef union packed {
    dense_input_payload_t   dense;
    hybrid_input_payload_t  hybrid;
    dual_input_payload_t    dual;
  } du_tia_input_payload_t;

  typedef struct packed {
    compiler_mode_e        mode;
    group_position_t       k_position;
    du_tia_input_payload_t payload;
  } du_tia_input_t;

  /* Packed values always occupy value[0 .. count-1]. */
  typedef struct packed {
    count_t      count;
    lane_data_t  value;
  } compact_vector_t;

  /* TIA's two four-entry sorters need their local lengths for S2 merging. */
  typedef struct packed {
    half_count_t count;
    logic [GROUP_SIZE-1:0][INDEX_W-1:0] index;
  } tia_half_map_t;

  typedef struct packed {
    compact_vector_t a;
    compact_vector_t b;
    tia_half_map_t    a_low;
    tia_half_map_t    a_high;
    tia_half_map_t    b_low;
    tia_half_map_t    b_high;
  } sparse_predecode_t;

  typedef struct packed {
    count_t      count;
    lane_data_t  value;
    index_vec_t  index;
  } sparse_vector_t;

  typedef struct packed {
    sparse_vector_t a;
    sparse_vector_t b;
  } sparse_output_payload_t;

  localparam int unsigned SPARSE_OUTPUT_W =
      2 * (COUNT_W + VECTOR_LANES * DATA_W + VECTOR_LANES * INDEX_W);
  localparam int unsigned OUTPUT_PAYLOAD_W = SPARSE_OUTPUT_W;

  typedef struct packed {
    lane_data_t dense_a;
    lane_data_t dense_b;
    logic [OUTPUT_PAYLOAD_W-DENSE_PAYLOAD_W-1:0] reserved;
  } dense_output_payload_t;

  typedef union packed {
    dense_output_payload_t   dense;
    sparse_output_payload_t  sparse;
  } du_tia_output_payload_t;

  /*
   * Ux2:4 and UxU have the same post-DU/TIA outer-product format, so the
   * output only needs one dense/sparse selector rather than the full mode.
   */
  typedef struct packed {
    logic                    is_sparse;
    du_tia_output_payload_t  payload;
  } du_tia_output_t;

  typedef struct packed {
    logic           valid;
    du_tia_input_t  packet;
  } s0_reg_t;

  localparam int unsigned COMPACT_VECTOR_W =
      COUNT_W + VECTOR_LANES * DATA_W;
  localparam int unsigned TIA_HALF_MAP_W =
      HALF_COUNT_W + GROUP_SIZE * INDEX_W;
  localparam int unsigned SPARSE_PREDECODE_W =
      2 * COMPACT_VECTOR_W + 4 * TIA_HALF_MAP_W;

  typedef struct packed {
    lane_data_t dense_a;
    lane_data_t dense_b;
    logic [SPARSE_PREDECODE_W-DENSE_PAYLOAD_W-1:0] reserved;
  } s1_dense_payload_t;

  typedef union packed {
    s1_dense_payload_t  dense;
    sparse_predecode_t  sparse;
  } s1_payload_t;

  typedef struct packed {
    logic         valid;
    logic         is_sparse;
    s1_payload_t  payload;
  } s1_reg_t;

  typedef struct packed {
    logic            valid;
    du_tia_output_t  packet;
  } s2_reg_t;

  typedef struct packed {
    logic            valid;
    du_tia_output_t  packet;
  } s3_reg_t;

  function automatic logic legal_mode(input compiler_mode_e mode);
    return (mode == MODE_DENSE_DENSE) ||
           (mode == MODE_UNSTRUCTURED_2TO4) ||
           (mode == MODE_UNSTRUCTURED_UNSTRUCTURED);
  endfunction

  function automatic count_t popcount8(input bitmap_t value);
    count_t result;
    result = '0;
    for (int unsigned bit_index = 0;
         bit_index < VECTOR_LANES; bit_index++) begin
      if (value[bit_index]) begin
        result = result + 1'b1;
      end
    end
    return result;
  endfunction

  function automatic logic [1:0] packed_rank_before(
      input logic [GROUP_SIZE-1:0] mask,
      input group_position_t position
  );
    logic [1:0] result;
    result = '0;
    for (int unsigned bit_index = 0;
         bit_index < GROUP_SIZE; bit_index++) begin
      if ((bit_index < position) && mask[bit_index]) begin
        result = result + 1'b1;
      end
    end
    return result;
  endfunction

  function automatic tia_half_map_t tia_decode_half(
      input bitmap_t bitmap,
      input logic high_half
  );
    tia_half_map_t result;
    index_t base;
    result = '0;
    base = high_half ? index_t'(GROUP_SIZE) : '0;

    /* Four-bit sorter/leading-one-detector truth table. */
    case (high_half ? bitmap[7:4] : bitmap[3:0])
      4'b0000: result.count = 0;
      4'b0001: begin
        result.count = 1; result.index[0] = base;
      end
      4'b0010: begin
        result.count = 1; result.index[0] = base + 1;
      end
      4'b0011: begin
        result.count = 2;
        result.index[0] = base; result.index[1] = base + 1;
      end
      4'b0100: begin
        result.count = 1; result.index[0] = base + 2;
      end
      4'b0101: begin
        result.count = 2;
        result.index[0] = base; result.index[1] = base + 2;
      end
      4'b0110: begin
        result.count = 2;
        result.index[0] = base + 1; result.index[1] = base + 2;
      end
      4'b0111: begin
        result.count = 3;
        result.index[0] = base; result.index[1] = base + 1;
        result.index[2] = base + 2;
      end
      4'b1000: begin
        result.count = 1; result.index[0] = base + 3;
      end
      4'b1001: begin
        result.count = 2;
        result.index[0] = base; result.index[1] = base + 3;
      end
      4'b1010: begin
        result.count = 2;
        result.index[0] = base + 1; result.index[1] = base + 3;
      end
      4'b1011: begin
        result.count = 3;
        result.index[0] = base; result.index[1] = base + 1;
        result.index[2] = base + 3;
      end
      4'b1100: begin
        result.count = 2;
        result.index[0] = base + 2; result.index[1] = base + 3;
      end
      4'b1101: begin
        result.count = 3;
        result.index[0] = base; result.index[1] = base + 2;
        result.index[2] = base + 3;
      end
      4'b1110: begin
        result.count = 3;
        result.index[0] = base + 1; result.index[1] = base + 2;
        result.index[2] = base + 3;
      end
      4'b1111: begin
        result.count = 4;
        result.index[0] = base; result.index[1] = base + 1;
        result.index[2] = base + 2; result.index[3] = base + 3;
      end
      default: result = 'x;
    endcase
    return result;
  endfunction

endpackage
