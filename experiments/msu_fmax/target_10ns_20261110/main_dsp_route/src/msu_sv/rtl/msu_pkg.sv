`timescale 1ns/1ps

// Standalone MSU interface; no dependency on the MLU/DU/TIA packages.
package msu_pkg;
  localparam int MSU_DIM          = 8;
  localparam int MSU_BEAT_BYTES   = 32;
  localparam int MSU_RESULT_BYTES = 256; // NOT IO_TILE_BYTES=160 (MLU image).
  localparam int MSU_TILE_BUFFERS = 2;

  // Same packed shape as tensor_core_pkg::tc_matrix_t.
  // Each lane is an INT32 bit pattern. MSU performs no arithmetic on it.
  typedef logic [7:0][7:0][31:0] msu_matrix_t;
  typedef logic [MSU_BEAT_BYTES*8-1:0] msu_beat_t;

  typedef struct packed {
    logic [31:0] tile_id;
    logic [63:0] dst_addr;
  } io_meta_t;

  typedef enum logic [2:0] {
    IO_OK             = 3'd0,
    IO_BAD_ARGUMENT   = 3'd1, // C pointer error; never emitted by RTL.
    IO_BAD_FORMAT     = 3'd2,
    IO_PROTOCOL_ERROR = 3'd3,
    IO_NO_CREDIT      = 3'd4
  } io_status_t;

  // Registered observation of the MOST RECENT rising edge, like MsuEvents.
  // completed is zero on every edge that does not complete a tile.
  typedef struct packed {
    logic result_accepted;
    logic beat_written;
    logic tile_done;
    io_meta_t completed;
  } msu_events_t;
endpackage
