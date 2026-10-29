`timescale 1ns/1ps

// Cycle-accurate translation of the supplied mlu_model.c.
// All handshakes use OLD state; no same-edge pop credit or first-beat bypass.
// status describes the upcoming edge. Non-OK rejects all local state changes,
// as in C. Invalid traffic is a SYSTEM ERROR, not a recoverable bus transaction:
// peers can already observe valid/ready on that edge. Reset all participants
// together after a protocol/format error; do not retry on a live system.
module mlu (
  input  logic clk,
  input  logic rst_n,

  input  logic command_valid,
  input  mlu_pkg::io_command_t command,
  output logic command_ready,

  output logic read_request_valid,
  input  logic read_request_ready,
  output logic [63:0] read_addr,
  output logic [2:0] read_beats, // actual beat count, 4 or 5; NOT AXI ARLEN

  input  logic read_data_valid,
  output logic read_data_ready,
  input  mlu_pkg::io_beat_t read_data,
  input  logic read_last,

  output logic out_valid,
  input  logic out_ready, // bridge credit, not raw TC input_ready
  output du_tia_pkg::du_tia_input_t out_packet,
  output mlu_pkg::io_meta_t out_meta,
  output logic [2:0] out_k,

  output mlu_pkg::io_status_t status,
  output mlu_pkg::mlu_tick_info_t tick_info
);
  import mlu_pkg::*;

  mlu_state_t state_q, state_d;
  mlu_tick_info_t info_q, info_d;
  io_frame_t frame;
  logic reading_valid, pending_valid;
  logic reading_slot, pending_slot;

  assign tick_info = info_q;
  assign out_packet = frame.packet;
  assign out_meta = frame.meta;
  assign out_k = frame.k;

  always_comb begin : peek
    logic slot;
    slot = 1'b0;
    reading_valid = 1'b0;
    pending_valid = 1'b0;
    reading_slot = 1'b0;
    pending_slot = 1'b0;
    // Scan in FIFO age order, including after head wraps to slot 1.
    for (int n = 0; n < IO_TILE_BUFFERS; n = n + 1) begin
      slot = state_q.head ^ (n != 0);
      if (n < int'(state_q.count)) begin
        if (!reading_valid && state_q.buffer[slot].phase == MLU_READING) begin
          reading_valid = 1'b1;
          reading_slot = slot;
        end
        if (!pending_valid && state_q.buffer[slot].phase == MLU_PENDING) begin
          pending_valid = 1'b1;
          pending_slot = slot;
        end
      end
    end
    command_ready = (state_q.count < 2);
    read_data_ready = reading_valid;
    read_request_valid = !reading_valid && pending_valid;
    read_addr = '0;
    read_beats = '0;
    if (read_request_valid) begin
      read_addr = state_q.buffer[pending_slot].command.src_addr;
      read_beats = io_image_beats(state_q.buffer[pending_slot].command.mode);
    end
    out_valid = (state_q.count != 0) &&
                (state_q.buffer[state_q.head].phase == MLU_READY);
    frame = '0;
    if (out_valid)
      frame = make_frame(state_q.buffer[state_q.head], state_q.next_k);
  end

  always_comb begin : next_state
    logic tail, last;
    int beat_index;
    state_d = state_q;
    info_d = '0;
    status = IO_OK;
    tail = state_q.head ^ state_q.count[0];
    last = 1'b0;
    beat_index = 0;

    // Preserve the C error-check priority: command, read_last, hybrid image.
    if (command_valid && command_ready) begin
      if (!valid_command(command)) begin
        status = IO_BAD_FORMAT;
      end else begin
        state_d.buffer[tail] = '0;
        state_d.buffer[tail].phase = MLU_PENDING;
        state_d.buffer[tail].command = command;
        state_d.count = state_d.count + 1'b1;
        info_d.command_accepted = 1'b1;
      end
    end

    if (status == IO_OK && read_request_valid && read_request_ready) begin
      state_d.buffer[pending_slot].phase = MLU_READING;
      info_d.read_request_accepted = 1'b1;
    end

    if (status == IO_OK && read_data_ready && read_data_valid) begin
      beat_index = int'(state_q.buffer[reading_slot].beats_received);
      last = (beat_index + 1 ==
              int'(io_image_beats(state_q.buffer[reading_slot].command.mode)));
      if (read_last != last) begin
        status = IO_PROTOCOL_ERROR;
      end else begin
        for (int i = 0; i < IO_BEAT_BYTES; i = i + 1)
          state_d.buffer[reading_slot].image[32*beat_index + i] = read_data[i];
        state_d.buffer[reading_slot].beats_received =
            state_q.buffer[reading_slot].beats_received + 1'b1;
        if (last) begin
          // Include the just-arrived final beat in validation (not OLD image).
          if (!valid_image(state_d.buffer[reading_slot]))
            status = IO_BAD_FORMAT;
          else
            state_d.buffer[reading_slot].phase = MLU_READY;
        end
        info_d.read_data_accepted = 1'b1;
      end
    end

    if (status == IO_OK && out_valid && out_ready) begin
      info_d.packet_issued = 1'b1;
      info_d.tile_id = frame.meta.tile_id;
      info_d.k = state_q.next_k;
      if (state_q.next_k == 3'd7) begin
        // Keep retired image/command bytes, just like the C model.
        state_d.buffer[state_q.head].phase = MLU_EMPTY;
        state_d.head = ~state_q.head;
        state_d.count = state_d.count - 1'b1;
        state_d.next_k = '0;
        info_d.tile_issued = 1'b1;
      end else begin
        state_d.next_k = state_q.next_k + 1'b1;
      end
    end

    if (status != IO_OK) begin
      state_d = state_q;
      info_d = '0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= '0;
      info_q <= '0;
    end else begin
      state_q <= state_d;
      info_q <= info_d;
    end
  end
endmodule
