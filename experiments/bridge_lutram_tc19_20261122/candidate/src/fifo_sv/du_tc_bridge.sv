`timescale 1ns/1ps

// Cycle-equivalent bridge_tick(), with no payload bypass or credit lookahead.
// issue / tc_accept / result_accept are ACTUAL transfers, not requests.
// Non-OK status rejects this entire edge and leaves ALL bridge state unchanged.
module du_tc_bridge (
  input  logic clk,
  input  logic rst_n,

  input  logic issue,
  input  du_tc_bridge_pkg::io_mode_t issued_mode,
  input  du_tc_bridge_pkg::bridge_k_t issued_k,
  input  du_tc_bridge_pkg::io_meta_t issued_meta,
  output logic can_issue,

  input  logic du_valid,
  input  tensor_core_pkg::tc_input_packet_t du_packet,

  output logic head_valid,
  output du_tc_bridge_pkg::bridge_entry_t head_entry,
  input  logic tc_accept,

  output logic result_meta_valid,
  output du_tc_bridge_pkg::io_meta_t result_meta,
  input  logic result_accept,

  output du_tc_bridge_pkg::fifo_count_t fifo_count,
  output du_tc_bridge_pkg::flight_count_t inflight_count,
  output du_tc_bridge_pkg::meta_count_t result_meta_count,
  output du_tc_bridge_pkg::io_status_t status
);
  import du_tc_bridge_pkg::*;

  bridge_state_t q, d, state_q;
  (* ram_style = "distributed" *) bridge_entry_t fifo_mem [0:IO_PACKET_FIFO-1];
  bridge_entry_t arriving_word, head_word;
  fifo_ptr_t write_ptr_q;
  logic fifo_write;
  meta_ptr_t meta_tail;
  logic [FIFO_COUNT_W:0] used_credits;
  (* max_fanout = 128 *) logic head_present_q;

  // RAM contents survive reset. Count gates all functional reads. For the
  // C-state observation, unwritten words read as zero in each reset epoch.
  // synthesis translate_off
  logic [IO_PACKET_FIFO-1:0] written_q;
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) written_q <= '0;
    else if (fifo_write) written_q[write_ptr_q] <= 1'b1;
  // synthesis translate_on
  always_comb begin : logical_state_view
    q = state_q;
    // synthesis translate_off
    for (int slot = 0; slot < IO_PACKET_FIFO; slot = slot + 1)
      q.fifo[slot] = written_q[slot] ? fifo_mem[slot] : '0;
    // synthesis translate_on
  end

  // Widen BEFORE adding so a carry cannot disappear.
  assign used_credits = {1'b0, q.count} +
                        {{(FIFO_COUNT_W+1-FLIGHT_COUNT_W){1'b0}}, q.inflight};
  assign can_issue = (used_credits < (FIFO_COUNT_W+1)'(IO_PACKET_FIFO));
  assign fifo_count = q.count;
  assign inflight_count = q.inflight;
  assign result_meta_count = q.meta_count;

  // Even when metadata blocks k=0, the stored head stays visible for mode
  // selection. It may be consumed ONLY when head_valid is high.
  assign head_word = fifo_mem[state_q.head];
  assign head_entry = head_present_q ? head_word : '0;
  assign head_valid = head_present_q &&
      !((head_entry.k == 0) && (q.meta_count == meta_count_t'(RESULT_SLOTS)));
  assign result_meta_valid = (q.meta_count != 0);
  assign result_meta = result_meta_valid ? q.result_meta[q.meta_head] : '0;

  // The tail advances only on a committed arrival. A simultaneous pop
  // advances the independent head, so both ports use the old pointers.
  assign meta_tail = meta_ptr_t'(q.meta_head + q.meta_count);
  assign arriving_word.packet = du_packet;
  assign arriving_word.meta = q.side[IO_DU_STAGES-1].meta;
  assign arriving_word.k = q.side[IO_DU_STAGES-1].k;
  assign fifo_write = rst_n && du_valid && status == IO_OK;
  always_ff @(posedge clk)
    if (fifo_write) fifo_mem[write_ptr_q] <= arriving_word;

  always_comb begin : check_contract
    status = IO_OK;
    // Keep the exact error priority of bridge_tick().
    if (issue && !can_issue)
      status = IO_NO_CREDIT;
    else if (issue && ((issued_k >= 8) || !io_legal_mode(issued_mode)))
      status = IO_BAD_FORMAT;
    else if (du_valid != q.side[IO_DU_STAGES-1].valid)
      status = IO_PROTOCOL_ERROR;
    else if (du_valid && ((q.inflight == 0) ||
             (q.count >= fifo_count_t'(IO_PACKET_FIFO)) ||
             (du_packet.is_sparse != q.side[IO_DU_STAGES-1].is_sparse)))
      status = IO_PROTOCOL_ERROR;
    else if (tc_accept && !head_valid)
      status = IO_PROTOCOL_ERROR;
    else if (result_accept && !result_meta_valid)
      status = IO_PROTOCOL_ERROR;
  end

  always_comb begin : next_state
    d = q;
    if (result_accept) begin
      d.meta_head = q.meta_head + 1'b1;
      d.meta_count = d.meta_count - 1'b1;
    end
    if (tc_accept) begin
      if (head_word.k == 0) begin
        d.result_meta[meta_tail] = head_word.meta;
        d.meta_count = d.meta_count + 1'b1;
      end
      d.head = q.head + 1'b1;
      d.count = d.count - 1'b1;
    end
    if (du_valid) begin
      d.count = d.count + 1'b1;
      d.inflight = d.inflight - 1'b1;
    end
    for (int s = IO_DU_STAGES-1; s > 0; s = s - 1)
      d.side[s] = q.side[s-1];
    d.side[0] = '0;
    if (issue) begin
      d.side[0].valid = 1'b1;
      d.side[0].is_sparse = (issued_mode != IO_DENSE);
      d.side[0].meta = issued_meta;
      d.side[0].k = issued_k;
      d.inflight = d.inflight + 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= '0;
      write_ptr_q <= '0;
      head_present_q <= 1'b0;
    end else if (status == IO_OK) begin
      state_q <= d;
      // Packet storage is exclusively in fifo_mem.
      state_q.fifo <= '0;
      if (du_valid) write_ptr_q <= write_ptr_q + 1'b1;
      head_present_q <= (d.count != 0);
    end
  end
endmodule
