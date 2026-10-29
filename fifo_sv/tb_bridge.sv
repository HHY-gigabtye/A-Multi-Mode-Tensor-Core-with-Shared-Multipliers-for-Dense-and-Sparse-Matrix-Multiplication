`timescale 1ns/1ps

// Standalone C/RTL equivalence test. No DU/TIA or TC module required.
// Plain procedural checks only: no SVA, DPI, or external simulator library.
module tb_bridge;
  import tensor_core_pkg::*;
  import du_tc_bridge_pkg::*;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0;
  logic issue, can_issue, du_valid, head_valid, tc_accept;
  logic result_meta_valid, result_accept;
  io_mode_t issued_mode;
  bridge_k_t issued_k;
  io_meta_t issued_meta, result_meta;
  tc_input_packet_t du_packet;
  bridge_entry_t head_entry;
  fifo_count_t fifo_count;
  flight_count_t inflight_count;
  meta_count_t result_meta_count;
  io_status_t status;

  du_tc_bridge dut (.*);

  task automatic require(input logic good, input string message);
    if (good !== 1'b1) $fatal(1, "%s", message);
  endtask

  initial begin : run
    string path;
    integer fd, fields, row, rejects, resets;
    integer r_reset, r_issue, r_mode, r_k, r_du, r_tc, r_result, r_status;
    io_meta_t r_meta;
    tc_input_packet_t r_packet;
    bridge_state_t expected;
    logic expected_head_valid;

    issue = 0; issued_mode = IO_DENSE; issued_k = 0; issued_meta = '0;
    du_valid = 0; du_packet = '0; tc_accept = 0; result_accept = 0;
    path = "vectors/bridge_vectors.txt";
    if ($value$plusargs("VECTORS=%s", path)) begin end
    if ($test$plusargs("TRACE")) begin
      $dumpfile("bridge.vcd"); $dumpvars(0, tb_bridge);
    end
    fd = $fopen(path, "r");
    require(fd != 0, $sformatf("Cannot open %s; run from the package directory", path));
    require($bits(bridge_state_t) == 2941, "Unexpected state layout");
    row = 0; rejects = 0; resets = 0;
    while (!$feof(fd)) begin
      fields = $fscanf(fd, "%d %d %h %h %h %d %h %d %d %d %h\n",
          r_reset, r_issue, r_mode, r_k, r_meta, r_du, r_packet,
          r_tc, r_result, r_status, expected);
      if (fields != 11) begin
        if ($feof(fd) && fields <= 0) break;
        $fatal(1, "Malformed vector row %0d: %0d fields", row+1, fields);
      end
      @(negedge clk);
      rst_n = (r_reset == 0);
      issue = (r_issue != 0); issued_mode = io_mode_t'(r_mode);
      issued_k = bridge_k_t'(r_k); issued_meta = r_meta;
      du_valid = (r_du != 0); du_packet = r_packet;
      tc_accept = (r_tc != 0); result_accept = (r_result != 0);
      #1;
      require(status === io_status_t'(r_status),
              $sformatf("row %0d status=%0d expected=%0d", row+1, status, r_status));
      @(posedge clk); #1;
      require(dut.q === expected,
              $sformatf("row %0d full state mismatch: count=%0d/%0d inflight=%0d/%0d meta=%0d/%0d",
                        row+1, dut.q.count, expected.count, dut.q.inflight,
                        expected.inflight, dut.q.meta_count, expected.meta_count));
      require(can_issue === ((int'(expected.count) + int'(expected.inflight)) < IO_PACKET_FIFO),
              $sformatf("row %0d can_issue", row+1));
      expected_head_valid = expected.count != 0 &&
          !(expected.fifo[expected.head].k == 0 && expected.meta_count == meta_count_t'(RESULT_SLOTS));
      require(head_valid === expected_head_valid, $sformatf("row %0d head_valid", row+1));
      require(head_entry === ((expected.count != 0) ? expected.fifo[expected.head] : '0),
              $sformatf("row %0d head_entry", row+1));
      require(result_meta_valid === (expected.meta_count != 0), "result_meta_valid");
      require(result_meta === ((expected.meta_count != 0) ? expected.result_meta[expected.meta_head] : '0),
              "result_meta");
      require(fifo_count === expected.count && inflight_count === expected.inflight &&
              result_meta_count === expected.meta_count, "debug counts");
      row++;
      if (r_status != 0) rejects++;
      if (r_reset != 0) resets++;
    end
    $fclose(fd);
    require(row > 1000 && rejects > 0 && resets > 1,
            $sformatf("Incomplete vector file rows=%0d rejects=%0d resets=%0d", row, rejects, resets));
    $display("BRIDGE RTL PASS: C-equivalent rows=%0d rejected_edges=%0d resets=%0d", row, rejects, resets);
    $finish;
  end
  initial begin #2000000; $fatal(1, "Testbench timeout"); end
endmodule
