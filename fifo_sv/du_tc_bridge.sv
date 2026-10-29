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

  bridge_state_t q, d;
  fifo_ptr_t fifo_tail;
  meta_ptr_t meta_tail;
  logic [FIFO_COUNT_W:0] used_credits;

  // Widen BEFORE adding so a carry cannot disappear.
  assign used_credits = {1'b0, q.count} +
                        {{(FIFO_COUNT_W+1-FLIGHT_COUNT_W){1'b0}}, q.inflight};
  assign can_issue = (used_credits < (FIFO_COUNT_W+1)'(IO_PACKET_FIFO));
  assign fifo_count = q.count;
  assign inflight_count = q.inflight;
  assign result_meta_count = q.meta_count;

  // Even when metadata blocks k=0, the stored head stays visible for mode
  // selection. It may be consumed ONLY when head_valid is high.
  assign head_entry = (q.count != 0) ? q.fifo[q.head] : '0;
  assign head_valid = (q.count != 0) &&
      !((head_entry.k == 0) && (q.meta_count == meta_count_t'(RESULT_SLOTS)));
  assign result_meta_valid = (q.meta_count != 0);
  assign result_meta = result_meta_valid ? q.result_meta[q.meta_head] : '0;

  // These fixed depths are powers of two: truncation implements C's modulo.
  assign fifo_tail = fifo_ptr_t'(q.head + q.count);
  assign meta_tail = meta_ptr_t'(q.meta_head + q.meta_count);

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
      if (q.fifo[q.head].k == 0) begin
        d.result_meta[meta_tail] = q.fifo[q.head].meta;
        d.meta_count = d.meta_count + 1'b1;
      end
      d.head = q.head + 1'b1;
      d.count = d.count - 1'b1;
    end
    if (du_valid) begin
      d.fifo[fifo_tail].packet = du_packet;
      d.fifo[fifo_tail].meta = q.side[IO_DU_STAGES-1].meta;
      d.fifo[fifo_tail].k = q.side[IO_DU_STAGES-1].k;
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
    if (!rst_n)
      q <= '0;
    else if (status == IO_OK)
      q <= d;
  end
endmodule
