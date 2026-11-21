`timescale 1ns/1ps

// Replay original C expectations where every offered valid packet belongs to
// the C outer-product mode. Start each independent window at a recorded reset.
module tb_outer_core;
  import tensor_core_pkg::*;
  logic clk=0, rst_n=1, in_valid, result_ready, in_ready, result_valid, busy;
  tc_sparse_payload_t in_packet;
  tc_matrix_t result, exp_result, exp_tail;
  tc_status_t status;
  tc_tick_info_t tick_info, exp_info;
  outer_product_core dut (.*);

  integer fd, rc, reset_word, valid_word, pop_word, exp_ready, exp_mode_ready;
  integer exp_status, exp_valid, exp_busy, total=0, checked=0, published=0, invalid=0;
  tc_input_packet_t original;
  logic [31:0] old_state_hash;
  bit window, passed=0;
  string path;
  task automatic step;
    #1; clk=1; #1; clk=0;
  endtask
  initial begin
    if (!$value$plusargs("VECTORS=%s",path)) $fatal(1,"missing C vector file");
    fd = $fopen(path,"r");
    if (fd == 0) $fatal(1,"could not open C vectors");
    while (!$feof(fd)) begin
      rc=$fscanf(fd,"%d %d %d %h %d %d %d %h %d %d %h %h %h\n",
          reset_word, valid_word, pop_word, original, exp_ready, exp_mode_ready,
          exp_status, exp_info, exp_valid, exp_busy, old_state_hash, exp_result, exp_tail);
      if (rc != 13 && !$feof(fd)) $fatal(1,"bad vector record");
      if (rc == 13) begin
        total++;
        if (reset_word) window=1;
        if (valid_word && !original.is_sparse) window=0;
        if (window) begin
          rst_n=!reset_word; in_valid=valid_word; result_ready=pop_word;
          in_packet=original.payload.sparse;
          #1;
          if (rst_n && (in_ready !== 1'(exp_ready) || status !== tc_status_t'(exp_status)))
            $fatal(1,"C input contract mismatch at record %0d",total);
          step();
          if (tick_info !== exp_info || result_valid !== 1'(exp_valid) ||
              busy !== 1'(exp_busy) || result !== exp_result || dut.tail !== exp_tail)
            $fatal(1,"C output mismatch at record %0d",total);
          checked++; published+=tick_info.result_produced;
          if (exp_status == TC_BAD_SPARSE_VECTOR) invalid++;
        end
      end
    end
    $fclose(fd);
    if (checked != 21032 || published != 1366 || invalid != 6)
      $fatal(1,"incomplete C trace replay");
    // Two back-to-back tiles reserve both credits. A forbidden third start
    // with result_ready=1 must reject the entire edge, even an otherwise legal pop.
    rst_n=0; in_valid=0; result_ready=0; step(); rst_n=1; in_valid=1; in_packet='0;
    repeat (16) step();
    result_ready=1; #1;
    if (status !== TC_NOT_READY || !result_valid) $fatal(1,"missing full rejection");
    step();
    if (dut.outstanding !== 2 || !result_valid || tick_info !== '0)
      $fatal(1,"rejected edge lost a result or advanced the pipe");
    in_valid=0; repeat (8) step();
    if (busy || result_valid) $fatal(1,"failed to drain");
    $display("OUTER UNIT PASS C_records=%0d publications=%0d malformed=%0d full_reject=1",checked,published,invalid);
    passed=1; $finish;
  end
endmodule
