`timescale 1ns/1ps

// Standalone post-DU/TIA interface. Fixed M=N=K=8, signed INT8 -> INT32.
package tensor_core_pkg;
  localparam int TC_DIM = 8;
  localparam int TC_K = 8;
  localparam int TC_RESULT_SLOTS = 2;
  localparam int TC_DATA_W = 8;
  localparam int TC_INDEX_W = 3;
  localparam int TC_COUNT_W = 4;
  localparam int TC_PAYLOAD_W = 184;

  typedef logic [TC_DIM-1:0][TC_DATA_W-1:0] tc_lane_data_t;
  typedef logic [TC_DIM-1:0][TC_INDEX_W-1:0] tc_index_vec_t;
  typedef logic [7:0][7:0][31:0] tc_matrix_t;

  typedef struct packed {
    logic [TC_COUNT_W-1:0] count;
    tc_lane_data_t value;
    tc_index_vec_t index;
  } tc_sparse_vector_t;
  typedef struct packed {
    tc_sparse_vector_t a;
    tc_sparse_vector_t b;
  } tc_sparse_payload_t;
  typedef struct packed {
    tc_lane_data_t dense_a; // A[:,k]
    tc_lane_data_t dense_b; // B[k,:]
    logic [TC_PAYLOAD_W-2*TC_DIM*TC_DATA_W-1:0] reserved; // Equal-width union.
  } tc_dense_payload_t;
  typedef union packed {
    tc_dense_payload_t dense;
    tc_sparse_payload_t sparse;
  } tc_payload_t;
  typedef struct packed {
    logic is_sparse;
    tc_payload_t payload;
  } tc_input_packet_t;

  typedef struct packed {
    logic valid;
    logic last;
    logic signed [7:0] value;
  } tc_token_t;
  typedef struct packed {
    tc_token_t a;
    tc_token_t b;
    logic signed [31:0] acc;
  } tc_pe_t;
  typedef struct packed {
    tc_token_t [7:0][6:0] a_delay;
    tc_token_t [7:0][6:0] b_delay;
    tc_pe_t [7:0][7:0] pe;
  } tc_dense_state_t;
  typedef struct packed {
    logic valid;
    logic first;
    logic last;
    logic [3:0] a_count;
    logic [3:0] b_count;
    tc_index_vec_t a_index;
    tc_index_vec_t b_index;
    logic [7:0][7:0][15:0] product;
  } tc_mul_reg_t;
  typedef struct packed {
    logic valid;
    logic first;
    logic last;
    logic [7:0][7:0] enable;
    logic [7:0][7:0][15:0] delta;
  } tc_route_reg_t;
  typedef struct packed {
    tc_mul_reg_t mul;
    tc_route_reg_t route;
    tc_matrix_t acc;
  } tc_sparse_state_t;
  typedef struct packed {
    logic busy;
    logic is_sparse;
    logic finish_pending;
    logic result_valid;
    logic [3:0] received;
    logic [1:0] outstanding;
    logic [1:0] result_count;
    tc_matrix_t result;
    tc_matrix_t result_next;
  } tc_control_t;

  // Debug observation of the most recent edge, matching TcTickInfo.
  typedef struct packed {
    logic input_accepted;
    logic dense_step;
    logic sparse_step;
    logic result_accepted;
    logic input_first;
    logic input_last;
    logic result_produced;
    logic mul;
    logic route;
    logic acc;
    logic acc_first;
    logic acc_last;
    logic [3:0] input_k;
    logic [6:0] macs;
  } tc_tick_info_t;

  typedef enum logic [2:0] {
    TC_OK = 3'd0,
    TC_BAD_ARGUMENT = 3'd1, // C pointers only; never emitted by RTL.
    TC_BAD_SPARSE_VECTOR = 3'd2,
    TC_MODE_CHANGE = 3'd3,
    TC_NOT_READY = 3'd4
  } tc_status_t;

  function automatic logic valid_vector(input logic [TC_COUNT_W-1:0] count,
                                        input tc_index_vec_t index);
    logic good;
    good = (int'(count) <= TC_DIM);
    // A 3-bit index is always 0..7. Padding lanes are ignored.
    for (int p = 1; p < TC_DIM; p = p + 1)
      if ((p < int'(count)) && (index[p] <= index[p-1]))
        good = 1'b0;
    return good;
  endfunction

  function automatic logic signed [15:0] mul_int8(
      input logic [7:0] a, input logic [7:0] b);
    return $signed(a) * $signed(b);
  endfunction

  function automatic logic signed [31:0] extend_product(
      input logic [15:0] p);
    return {{16{p[15]}}, p};
  endfunction
endpackage
