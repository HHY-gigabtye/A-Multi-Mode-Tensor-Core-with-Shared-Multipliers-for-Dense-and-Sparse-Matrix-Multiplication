`timescale 1ns/1ps

// Fixed configuration from io_types.h and tensor_core_model.h.
// Compile tensor_core_pkg.sv before this package.
package du_tc_bridge_pkg;
  localparam int IO_DU_STAGES = 4;
  localparam int IO_PACKET_FIFO = 8;
  localparam int RESULT_SLOTS = tensor_core_pkg::TC_RESULT_SLOTS;
  localparam int FIFO_PTR_W = $clog2(IO_PACKET_FIFO);
  localparam int FIFO_COUNT_W = $clog2(IO_PACKET_FIFO + 1);
  localparam int FLIGHT_COUNT_W = $clog2(IO_DU_STAGES + 1);
  localparam int META_PTR_W = $clog2(RESULT_SLOTS);
  localparam int META_COUNT_W = $clog2(RESULT_SLOTS + 1);

  typedef enum logic [1:0] {
    IO_DENSE = 2'd0, IO_HYBRID = 2'd1, IO_DUAL = 2'd2
  } io_mode_t;
  typedef enum logic [2:0] {
    IO_OK = 3'd0,
    IO_BAD_ARGUMENT = 3'd1, // C null pointers only; not emitted by RTL.
    IO_BAD_FORMAT = 3'd2,
    IO_PROTOCOL_ERROR = 3'd3,
    IO_NO_CREDIT = 3'd4
  } io_status_t;

  typedef struct packed {
    logic [31:0] tile_id;
    logic [63:0] dst_addr;
  } io_meta_t;
  typedef logic [7:0] bridge_k_t; // Retain C's k>=8 format guard.
  typedef logic [FIFO_PTR_W-1:0] fifo_ptr_t;
  typedef logic [FIFO_COUNT_W-1:0] fifo_count_t;
  typedef logic [FLIGHT_COUNT_W-1:0] flight_count_t;
  typedef logic [META_PTR_W-1:0] meta_ptr_t;
  typedef logic [META_COUNT_W-1:0] meta_count_t;

  typedef struct packed {
    logic valid;
    logic is_sparse;
    io_meta_t meta;
    bridge_k_t k;
  } bridge_tag_t;
  typedef struct packed {
    tensor_core_pkg::tc_input_packet_t packet;
    io_meta_t meta;
    bridge_k_t k;
  } bridge_entry_t;

  // Packed arrays make all state visible as dut.q in the waveform and TB.
  // side[] carries ONLY tags; payload is computed by the external DU/TIA.
  typedef struct packed {
    bridge_tag_t [IO_DU_STAGES-1:0] side;
    bridge_entry_t [IO_PACKET_FIFO-1:0] fifo;
    fifo_ptr_t head;
    fifo_count_t count;
    flight_count_t inflight;
    io_meta_t [RESULT_SLOTS-1:0] result_meta;
    meta_ptr_t meta_head;
    meta_count_t meta_count;
  } bridge_state_t;

  function automatic logic io_legal_mode(input io_mode_t mode);
    return (mode == IO_DENSE) || (mode == IO_HYBRID) || (mode == IO_DUAL);
  endfunction
endpackage
