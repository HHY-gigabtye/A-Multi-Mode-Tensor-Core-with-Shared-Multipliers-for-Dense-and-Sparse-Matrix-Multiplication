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

  // Keep control resettable; image storage is a synchronous block RAM per beat.
  // The public package/vector format stays unchanged.
  typedef struct packed {
    mlu_phase_t phase;
    io_command_t command;
    logic [2:0] beats_received;
  } buffer_control_t;
  typedef struct packed {
    buffer_control_t [1:0] buffer;
    logic head;
    logic [1:0] count;
    logic [2:0] next_k;
  } control_t;
  control_t ctrl_q, ctrl_d;
  mlu_tick_info_t info_q, info_d;
  io_frame_t frame;
  logic reading_valid, pending_valid;
  logic reading_slot, pending_slot;
  mlu_buffer_t head_buffer;
  io_image_t head_image;
  logic [1:0] hybrid_stored_good;
  logic image_write;
  // A single shared input register moves every BRAM write control behind
  // synchronous storage. Reset discards the logical images immediately;
  // any old pending write drains before a new image can become READY.
  logic image_pending_valid, image_pending_slot;
  logic [2:0] image_pending_beat;
  io_beat_t image_pending_data;
  io_image_t [1:0] image_read_q;

  assign image_write = rst_n && (status == IO_OK) &&
                       read_data_ready && read_data_valid;
  always_ff @(posedge clk) begin
    image_pending_valid <= image_write;
    if (image_write) begin
      image_pending_slot <= reading_slot;
      image_pending_beat <= ctrl_q.buffer[reading_slot].beats_received;
      image_pending_data <= read_data;
    end
  end
  assign head_image = image_read_q[ctrl_q.head];
  generate
    for (genvar beat = 0; beat < 5; beat = beat + 1) begin : g_image
      (* ram_style = "block" *) logic [255:0] memory [0:1];
      for (genvar slot = 0; slot < 2; slot = slot + 1) begin : g_port
        logic [255:0] read_q;
        wire write_enable = image_pending_valid &&
            (image_pending_slot == 1'(slot)) &&
            (image_pending_beat == 3'(beat));
        // One fixed address per true-dual-port RAM port. WRITE_FIRST makes
        // the penultimate accepted beat available on the final load edge.
        // Neither address nor write enable has asynchronous reset fan-in.
        always_ff @(posedge clk) begin
          if (write_enable) begin
            memory[slot] <= image_pending_data;
            read_q <= image_pending_data;
          end else begin
            read_q <= memory[slot];
          end
        end
        assign image_read_q[slot][32*beat +: 32] = read_q;
      end
    end
  endgenerate

  // The incoming final beat is pending for one edge, but k=0 uses only
  // earlier beats in every mode. WRITE_FIRST covers hybrid group 0, whose
  // penultimate beat is committed to RAM on the final acceptance edge.
  // Simulation-only logical view reads the actual RAM cells, not a golden
  // shadow. Unwritten beats are logically zero after reset/new command;
  // retired slots retain their bytes. Original full-state assertions apply.
  // synthesis translate_off
  mlu_state_t state_q;
  io_image_t [1:0] image_observed;
  generate
    for (genvar obs_beat = 0; obs_beat < 5; obs_beat = obs_beat + 1) begin : g_observe
      for (genvar obs_slot = 0; obs_slot < 2; obs_slot = obs_slot + 1) begin : g_slot
        assign image_observed[obs_slot][32*obs_beat +: 32] =
          (ctrl_q.buffer[obs_slot].beats_received > 3'(obs_beat)) ?
          ((image_pending_valid && (image_pending_slot == 1'(obs_slot)) &&
            (image_pending_beat == 3'(obs_beat))) ? image_pending_data :
           g_image[obs_beat].memory[obs_slot]) : 256'b0;
      end
    end
  endgenerate
  always_comb begin : logical_state_view
    state_q = '0;
    state_q.head = ctrl_q.head;
    state_q.count = ctrl_q.count;
    state_q.next_k = ctrl_q.next_k;
    for (int s = 0; s < 2; s = s + 1) begin
      state_q.buffer[s].phase = ctrl_q.buffer[s].phase;
      state_q.buffer[s].command = ctrl_q.buffer[s].command;
      state_q.buffer[s].beats_received = ctrl_q.buffer[s].beats_received;
      state_q.buffer[s].image = image_observed[s];
    end
  end
  // synthesis translate_on

  // Hybrid masks occupy bytes 72+3*j (beat 2) and 96+3*j (beat 3).
  // The image is validated only on its final accepted beat, which is beat 3
  // for hybrid mode. Validate each OLD slot and the incoming last beat in
  // parallel. Store group-0 validity when its beat is accepted, but report
  // errors only at the original final-beat edge and with original priority.
  function automatic logic legal_hybrid_mask(input logic [7:0] mask);
    case (mask)
      8'h03, 8'h05, 8'h06, 8'h09, 8'h0a, 8'h0c: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction
  wire [7:0] hybrid_group0_good;
  wire [7:0] hybrid_incoming_masks_good;
  generate
    for (genvar j = 0; j < 8; j = j + 1) begin : g_hybrid_incoming
      assign hybrid_group0_good[j] = legal_hybrid_mask(read_data[8+3*j]);
      assign hybrid_incoming_masks_good[j] = legal_hybrid_mask(read_data[3*j]);
    end
  endgenerate

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
      slot = ctrl_q.head ^ (n != 0);
      if (n < int'(ctrl_q.count)) begin
        if (!reading_valid && ctrl_q.buffer[slot].phase == MLU_READING) begin
          reading_valid = 1'b1;
          reading_slot = slot;
        end
        if (!pending_valid && ctrl_q.buffer[slot].phase == MLU_PENDING) begin
          pending_valid = 1'b1;
          pending_slot = slot;
        end
      end
    end
    command_ready = (ctrl_q.count < 2);
    read_data_ready = reading_valid;
    read_request_valid = !reading_valid && pending_valid;
    read_addr = '0;
    read_beats = '0;
    if (read_request_valid) begin
      read_addr = ctrl_q.buffer[pending_slot].command.src_addr;
      read_beats = io_image_beats(ctrl_q.buffer[pending_slot].command.mode);
    end
    out_valid = (ctrl_q.count != 0) &&
                (ctrl_q.buffer[ctrl_q.head].phase == MLU_READY);
    head_buffer = '0;
    head_buffer.phase = ctrl_q.buffer[ctrl_q.head].phase;
    head_buffer.command = ctrl_q.buffer[ctrl_q.head].command;
    head_buffer.beats_received = ctrl_q.buffer[ctrl_q.head].beats_received;
    head_buffer.image = head_image;
    frame = '0;
    if (out_valid)
      frame = make_frame(head_buffer, ctrl_q.next_k);
  end

  always_comb begin : next_state
    logic tail, last;
    int beat_index;
    ctrl_d = ctrl_q;
    info_d = '0;
    status = IO_OK;
    tail = ctrl_q.head ^ ctrl_q.count[0];
    last = 1'b0;
    beat_index = 0;

    // Preserve the C error-check priority: command, read_last, hybrid image.
    if (command_valid && command_ready) begin
      if (!valid_command(command)) begin
        status = IO_BAD_FORMAT;
      end else begin
        ctrl_d.buffer[tail] = '0;
        ctrl_d.buffer[tail].phase = MLU_PENDING;
        ctrl_d.buffer[tail].command = command;
        ctrl_d.count = ctrl_d.count + 1'b1;
        info_d.command_accepted = 1'b1;
      end
    end

    if (status == IO_OK && read_request_valid && read_request_ready) begin
      ctrl_d.buffer[pending_slot].phase = MLU_READING;
      info_d.read_request_accepted = 1'b1;
    end

    if (status == IO_OK && read_data_ready && read_data_valid) begin
      beat_index = int'(ctrl_q.buffer[reading_slot].beats_received);
      last = (beat_index + 1 ==
              int'(io_image_beats(ctrl_q.buffer[reading_slot].command.mode)));
      if (read_last != last) begin
        status = IO_PROTOCOL_ERROR;
      end else begin
        ctrl_d.buffer[reading_slot].beats_received =
            ctrl_q.buffer[reading_slot].beats_received + 1'b1;
        if (last) begin
          // Group 0 is in the OLD image; group 1 is in this final beat.
          if ((ctrl_q.buffer[reading_slot].command.mode == IO_HYBRID) &&
              (!hybrid_stored_good[reading_slot] ||
               !(&hybrid_incoming_masks_good)))
            status = IO_BAD_FORMAT;
          else
            ctrl_d.buffer[reading_slot].phase = MLU_READY;
        end
        info_d.read_data_accepted = 1'b1;
      end
    end

    if (status == IO_OK && out_valid && out_ready) begin
      info_d.packet_issued = 1'b1;
      info_d.tile_id = frame.meta.tile_id;
      info_d.k = ctrl_q.next_k;
      if (ctrl_q.next_k == 3'd7) begin
        // Keep retired image/command bytes, just like the C model.
        ctrl_d.buffer[ctrl_q.head].phase = MLU_EMPTY;
        ctrl_d.head = ~ctrl_q.head;
        ctrl_d.count = ctrl_d.count - 1'b1;
        ctrl_d.next_k = '0;
        info_d.tile_issued = 1'b1;
      end else begin
        ctrl_d.next_k = ctrl_q.next_k + 1'b1;
      end
    end

    if (status != IO_OK) begin
      ctrl_d = ctrl_q;
      info_d = '0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_q <= '0;
      info_q <= '0;
      hybrid_stored_good <= '0;
    end else begin
      ctrl_q <= ctrl_d;
      info_q <= info_d;
      if (status == IO_OK) begin
        if (command_valid && command_ready)
          hybrid_stored_good[ctrl_q.head ^ ctrl_q.count[0]] <= 1'b0;
        if (image_write && (ctrl_q.buffer[reading_slot].beats_received == 3'd2))
          hybrid_stored_good[reading_slot] <= &hybrid_group0_good;
      end
    end
  end
endmodule
