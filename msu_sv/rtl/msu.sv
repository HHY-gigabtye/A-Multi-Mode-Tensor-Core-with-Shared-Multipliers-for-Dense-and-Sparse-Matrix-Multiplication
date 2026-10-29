`timescale 1ns/1ps

// MSU: two whole 8x8 INT32 results -> eight 256-bit row writes per tile.
// Legal-traffic timing follows msu_peek()/msu_tick() exactly.
// No look-ahead ready, no empty bypass, and no additional output register.
// An invalid destination rejects the whole edge, as in the C model. Unlike
// C's pre-tick peek, the RTL also deasserts ready/valid on that fault cycle
// so a live memory endpoint cannot commit a write that C would cancel.
// IO_BAD_FORMAT is an interface fault: fix the producer or reset the system.
module msu (
  input  logic clk,
  input  logic rst_n,

  input  logic result_valid,
  output logic result_ready,
  input  msu_pkg::io_meta_t result_meta,
  input  msu_pkg::msu_matrix_t result,

  output logic write_valid,
  input  logic write_ready,
  output logic [63:0] write_addr,
  output msu_pkg::msu_beat_t write_data,
  output logic write_last,
  output msu_pkg::io_meta_t write_meta,

  output msu_pkg::io_status_t status,
  output msu_pkg::msu_events_t events,
  output logic [1:0] buffer_count,
  output logic head_index,
  output logic [2:0] row_index
);
  import msu_pkg::*;

  // Packed arrays allow exactly the same lane ordering as tc_matrix_t.
  msu_matrix_t [1:0] result_q;
  msu_matrix_t head_result;
  // Store packed metadata as bits for simulators with limited support for
  // variable indexing into packed arrays of structs. Layout is io_meta_t.
  logic [1:0][95:0] meta_q;
  logic head_q;
  logic [1:0] count_q;
  logic [2:0] row_q;
  msu_events_t events_q;
  logic capacity_ready, addr_bad;
  logic push, write_fire, pop_tile, tail;

  assign buffer_count = count_q;
  assign head_index = head_q;
  assign row_index = row_q;
  assign events = events_q;

  assign capacity_ready = (count_q < 2'd2);
  // 32-byte alignment and a complete 256-byte address span.
  assign addr_bad = (result_meta.dst_addr[4:0] != 5'd0) ||
                   (result_meta.dst_addr > 64'hffff_ffff_ffff_ff00);
  // Like C, metadata is checked only when the input has capacity to accept.
  always_comb begin : check_format
    status = IO_OK;
    if (rst_n && result_valid && capacity_ready && addr_bad)
      status = IO_BAD_FORMAT;
  end
  assign result_ready = rst_n && capacity_ready && (status == IO_OK);
  assign write_valid = rst_n && (count_q != 0) && (status == IO_OK);
  assign push = result_valid && result_ready;
  assign write_fire = write_valid && write_ready;
  assign pop_tile = write_fire && (row_q == 3'd7);
  // (head + count) % 2. With one buffered tile, fill the other slot.
  assign tail = head_q ^ count_q[0];
  assign head_result = head_q ? result_q[1] : result_q[0];

  always_comb begin : observe_head
    write_addr = '0;
    write_data = '0;
    write_last = 1'b0;
    write_meta = '0;
    if (rst_n && (count_q != 0)) begin
      write_meta = meta_q[head_q];
      write_addr = write_meta.dst_addr + {56'd0, row_q, 5'b0};
      write_last = (row_q == 3'd7);
      // Whole packed row: write_data[32*j +: 32] = C[row][j].
      // byte b: write_data[8*(4*j+b) +: 8] = C[row][j][8*b +: 8].
      // Little endian: lowest byte lane maps to the lowest byte address.
      write_data = head_result[row_q];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : update_state
    if (!rst_n) begin
      head_q <= 1'b0;
      count_q <= 2'd0;
      row_q <= 3'd0;
      result_q <= '0;
      meta_q <= '0;
      events_q <= '0;
    end else begin
      events_q <= '0;
      if (status == IO_OK) begin
        if (push) begin
          meta_q[tail] <= result_meta;
          result_q[tail] <= result;
          events_q.result_accepted <= 1'b1;
        end
        if (write_fire) begin
          events_q.beat_written <= 1'b1;
          if (pop_tile) begin
            head_q <= ~head_q;
            row_q <= 3'd0;
            events_q.tile_done <= 1'b1;
            events_q.completed <= meta_q[head_q];
          end else begin
            row_q <= row_q + 3'd1;
          end
        end
        // Both decisions use OLD state. Simultaneous push/pop keeps count.
        case ({push, pop_tile})
          2'b10: count_q <= count_q + 2'd1;
          2'b01: count_q <= count_q - 2'd1;
          default: ;
        endcase
      end
    end
  end
endmodule
