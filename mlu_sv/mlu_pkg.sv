`timescale 1ns/1ps

package mlu_pkg;
  // Fixed dimensions of the supplied C model and existing DU/TIA package.
  localparam int IO_BEAT_BYTES   = 32;
  localparam int IO_TILE_BYTES   = 160;
  localparam int IO_TILE_BUFFERS = 2;

  typedef du_tia_pkg::compiler_mode_e io_mode_t;
  localparam io_mode_t IO_DENSE  = du_tia_pkg::MODE_DENSE_DENSE;
  localparam io_mode_t IO_HYBRID = du_tia_pkg::MODE_UNSTRUCTURED_2TO4;
  localparam io_mode_t IO_DUAL   = du_tia_pkg::MODE_UNSTRUCTURED_UNSTRUCTURED;

  typedef enum logic [2:0] {
    IO_OK = 3'd0, IO_BAD_ARGUMENT = 3'd1, IO_BAD_FORMAT = 3'd2,
    IO_PROTOCOL_ERROR = 3'd3, IO_NO_CREDIT = 3'd4
  } io_status_t;

  typedef struct packed {
    logic [31:0] tile_id;
    logic [63:0] dst_addr;
  } io_meta_t;

  typedef struct packed {
    io_mode_t mode;
    logic [63:0] src_addr;
    io_meta_t meta;
  } io_command_t;

  // Byte 0 occupies bits [7:0], byte 31 occupies bits [255:248].
  typedef logic [IO_BEAT_BYTES-1:0][7:0] io_beat_t;
  typedef logic [IO_TILE_BYTES-1:0][7:0] io_image_t;

  typedef struct packed {
    io_meta_t meta;
    logic [2:0] k;
    du_tia_pkg::du_tia_input_t packet;
  } io_frame_t;

  typedef enum logic [1:0] {
    MLU_EMPTY = 2'd0, MLU_PENDING = 2'd1,
    MLU_READING = 2'd2, MLU_READY = 2'd3
  } mlu_phase_t;

  typedef struct packed {
    mlu_phase_t phase;
    io_command_t command;
    io_image_t image;
    logic [2:0] beats_received;
  } mlu_buffer_t;

  typedef struct packed {
    mlu_buffer_t [1:0] buffer;
    logic head;
    logic [1:0] count;
    logic [2:0] next_k;
  } mlu_state_t;

  // Registered observation of the most recent edge, equivalent to MluEvents.
  typedef struct packed {
    logic command_accepted;
    logic read_request_accepted;
    logic read_data_accepted;
    logic packet_issued;
    logic tile_issued;
    logic [31:0] tile_id;
    logic [2:0] k;
  } mlu_tick_info_t;

  // Test-vector records, also useful to group the split RTL ports.
  typedef struct packed {
    logic command_valid;
    io_command_t command;
    logic read_request_ready;
    logic read_data_valid;
    io_beat_t read_data;
    logic read_last;
    logic out_ready;
  } mlu_inputs_t;

  typedef struct packed {
    logic command_ready;
    logic read_request_valid;
    logic [63:0] read_addr;
    logic [2:0] read_beats;
    logic read_data_ready;
    logic out_valid;
    io_frame_t out_frame;
  } mlu_outputs_t;

  function automatic logic [2:0] io_image_beats(input io_mode_t mode);
    case (mode)
      IO_DENSE, IO_HYBRID: return 3'd4;
      IO_DUAL: return 3'd5;
      default: return 3'd0;
    endcase
  endfunction

  function automatic logic valid_command(input io_command_t cmd);
    logic [63:0] last_offset;
    // Check the full padded read burst and the eventual 256-byte C tile.
    last_offset = (cmd.mode == IO_DUAL) ? 64'd159 : 64'd127;
    return ((cmd.mode == IO_DENSE) || (cmd.mode == IO_HYBRID) ||
            (cmd.mode == IO_DUAL)) &&
           (cmd.src_addr[4:0] == 5'd0) &&
           (cmd.meta.dst_addr[4:0] == 5'd0) &&
           (cmd.src_addr <= (64'hffffffffffffffff - last_offset)) &&
           (cmd.meta.dst_addr <= (64'hffffffffffffffff - 64'd255));
  endfunction

  function automatic logic valid_image(input mlu_buffer_t slot);
    logic ok;
    logic [7:0] mask;
    ok = 1'b1;
    mask = '0;
    if (slot.command.mode == IO_HYBRID) begin
      for (int g = 0; g < 2; g = g + 1) begin
        for (int j = 0; j < 8; j = j + 1) begin
          mask = slot.image[72 + 24*g + 3*j];
          // Validate all 8 stored bits BEFORE reducing the mask to 4 bits.
          case (mask)
            8'h03, 8'h05, 8'h06, 8'h09, 8'h0a, 8'h0c: begin end
            default: ok = 1'b0;
          endcase
        end
      end
    end
    return ok;
  endfunction

  function automatic io_frame_t make_frame(
      input mlu_buffer_t slot, input logic [2:0] k);
    io_frame_t f;
    int ki, b;
    f = '0;
    f.meta = slot.command.meta;
    f.k = k;
    f.packet.mode = slot.command.mode;
    f.packet.k_position = k[1:0];
    ki = int'(k);
    b = 0;
    for (int i = 0; i < 8; i = i + 1) begin
      case (slot.command.mode)
        IO_DENSE: begin
          f.packet.payload.dense.dense_a[i] = slot.image[16*ki + i];
          f.packet.payload.dense.dense_b[i] = slot.image[16*ki + 8 + i];
        end
        IO_HYBRID: begin
          b = 72 + (ki / 4)*24 + i*3;
          f.packet.payload.hybrid.a_packed[i] = slot.image[9*ki + 1 + i];
          f.packet.payload.hybrid.b_2to4_mask[i] = slot.image[b][3:0];
          f.packet.payload.hybrid.b_2to4_packed[i][0] = slot.image[b + 1];
          f.packet.payload.hybrid.b_2to4_packed[i][1] = slot.image[b + 2];
        end
        IO_DUAL: begin
          f.packet.payload.dual.a_packed[i] = slot.image[18*ki + 1 + i];
          f.packet.payload.dual.b_packed[i] = slot.image[18*ki + 10 + i];
        end
        default: begin end
      endcase
    end
    if (slot.command.mode == IO_HYBRID)
      f.packet.payload.hybrid.a_bitmap = slot.image[9*ki];
    if (slot.command.mode == IO_DUAL) begin
      f.packet.payload.dual.a_bitmap = slot.image[18*ki];
      f.packet.payload.dual.b_bitmap = slot.image[18*ki + 9];
    end
    return f;
  endfunction
endpackage
