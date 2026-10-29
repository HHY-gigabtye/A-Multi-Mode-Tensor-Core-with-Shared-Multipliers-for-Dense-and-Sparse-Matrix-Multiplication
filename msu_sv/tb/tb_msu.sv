`timescale 1ns/1ps

// Procedural checks only: no SVA, DPI, classes or UVM.
// Every cycle is compared with vectors from the original C implementation.
module tb_msu;
  import msu_pkg::*;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic result_valid = 1'b0;
  logic result_ready;
  io_meta_t result_meta = '0;
  msu_matrix_t result = '0;
  logic write_valid;
  logic write_ready = 1'b0;
  logic [63:0] write_addr;
  msu_beat_t write_data;
  logic write_last;
  io_meta_t write_meta;
  io_status_t status;
  msu_events_t events;
  logic [1:0] buffer_count;
  logic head_index;
  logic [2:0] row_index;

  msu dut (.*);
  always #5 clk = ~clk;

  int fd, fields, vector_cycle, phase, old_phase, checked;
  string vector_file, vcd_file;
  logic drive_reset, drive_valid, drive_ready;
  io_meta_t drive_meta;
  msu_matrix_t drive_result;
  logic [2:0] exp_status;
  logic raw_ready, raw_valid, exp_last;
  logic [63:0] exp_addr;
  msu_beat_t exp_data;
  io_meta_t exp_meta;
  msu_events_t exp_events;
  logic exp_head;
  logic [1:0] exp_count;
  logic [2:0] exp_row;
  logic effective_ready, effective_valid;
  logic held;
  msu_beat_t saved_data;
  logic [63:0] saved_addr;
  logic saved_last;
  io_meta_t saved_meta;
  int accepted, beats, done_tiles, simultaneous, faults, resets;
  int stalls, full_last, wraps, max_count;
  logic old_head;
  logic [1:0] old_count;
  // Scan scalar temporaries for portability across older SV simulators.
  logic [31:0] scan_input_id, scan_write_id, scan_completed_id;
  logic [63:0] scan_input_addr, scan_write_addr, scan_completed_addr;
  logic scan_accepted, scan_written, scan_done;

  task automatic check(input logic good, input string what);
    if (good !== 1'b1)
      $fatal(1, "MSU FAIL cycle=%0d phase=%0d: %s", vector_cycle, phase, what);
  endtask

  initial begin : replay
    checked = 0;
    old_phase = -1;
    held = 0;
    accepted = 0; beats = 0; done_tiles = 0; simultaneous = 0;
    faults = 0; resets = 0; stalls = 0; full_last = 0; wraps = 0; max_count = 0;
    vector_file = "vectors/msu_vectors.txt";
    if ($value$plusargs("VECTORS=%s", vector_file)) begin end
    if ($value$plusargs("VCD=%s", vcd_file)) begin
      $dumpfile(vcd_file);
      $dumpvars(0, tb_msu);
    end
    fd = $fopen(vector_file, "r");
    if (fd == 0) $fatal(1, "Cannot open %s; run from the package root.", vector_file);
    while (!$feof(fd)) begin
      fields = $fscanf(fd,
        "%d %d %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",
        vector_cycle, phase, drive_reset, drive_valid, scan_input_id,
        scan_input_addr, drive_result, drive_ready, exp_status, raw_ready,
        raw_valid, exp_addr, exp_data, exp_last, scan_write_id, scan_write_addr,
        scan_accepted, scan_written, scan_done,
        scan_completed_id, scan_completed_addr,
        exp_head, exp_count, exp_row);
      if (fields != 24) $fatal(1, "Malformed vector: fields=%0d line=%0d", fields, checked+1);
      drive_meta.tile_id = scan_input_id;
      drive_meta.dst_addr = scan_input_addr;
      exp_meta.tile_id = scan_write_id;
      exp_meta.dst_addr = scan_write_addr;
      exp_events.result_accepted = scan_accepted;
      exp_events.beat_written = scan_written;
      exp_events.tile_done = scan_done;
      exp_events.completed.tile_id = scan_completed_id;
      exp_events.completed.dst_addr = scan_completed_addr;
      check(vector_cycle == checked, "vector sequence");
      if (phase != old_phase) begin
        $display("MSU phase %0d starts at cycle %0d", phase, vector_cycle);
        old_phase = phase;
      end
      @(negedge clk);
      rst_n = drive_reset;
      result_valid = drive_valid;
      result_meta = drive_meta;
      result = drive_result;
      write_ready = drive_ready;
      #1;
      // C has no reset pin and a failing tick cancels the whole operation.
      // RTL must suppress actual external handshakes during reset/fault.
      effective_ready = drive_reset && (exp_status == 0) && raw_ready;
      effective_valid = drive_reset && (exp_status == 0) && raw_valid;
      check(status === exp_status, "status");
      check(result_ready === effective_ready, "result_ready");
      check(write_valid === effective_valid, "write_valid");
      check(write_addr === exp_addr, $sformatf("write_addr got=%h want=%h", write_addr, exp_addr));
      check(write_data === exp_data, "write_data / INT32 / byte order");
      check(write_last === exp_last, "write_last");
      check(write_meta === exp_meta, "write_meta (tile_id + dst_addr)");
      if (held && drive_reset && exp_status == 0) begin
        check(write_valid, "stalled write_valid dropped");
        check(write_data === saved_data && write_addr === saved_addr &&
              write_last === saved_last && write_meta === saved_meta,
              "stalled output changed");
      end
      held = write_valid && !write_ready;
      saved_data = write_data; saved_addr = write_addr;
      saved_last = write_last; saved_meta = write_meta;
      old_count = buffer_count;
      old_head = head_index;
      @(posedge clk);
      #1;
      check(events === exp_events, "registered events / completed metadata");
      check(buffer_count === exp_count, "buffer_count");
      check(head_index === exp_head, "head_index");
      check(row_index === exp_row, "row_index");
      check(buffer_count <= 2 && (buffer_count != 0 || row_index == 0), "state invariant");
      check(events.result_accepted === (drive_valid && effective_ready), "input handshake event");
      check(events.beat_written === (drive_ready && effective_valid), "output handshake event");
      check(events.tile_done === (drive_ready && effective_valid && exp_last), "tile_done timing");
      accepted += int'(events.result_accepted);
      beats += int'(events.beat_written);
      done_tiles += int'(events.tile_done);
      simultaneous += int'(events.tile_done && events.result_accepted);
      stalls += int'(held);
      faults += int'(drive_reset && exp_status != 0);
      resets += int'(!drive_reset);
      full_last += int'(old_count == 2 && events.tile_done);
      wraps += int'(old_head && events.tile_done && !head_index);
      if (int'(buffer_count) > max_count) max_count = int'(buffer_count);
      checked++;
    end
    $fclose(fd);
    $display("MSU coverage: simultaneous=%0d faults=%0d resets=%0d", simultaneous, faults, resets);
    check(checked > 5000 && accepted > 600 && beats > 5000, "traffic coverage");
    check(simultaneous >= 33 && faults >= 40 && resets >= 8, "directed coverage");
    check(full_last > 0 && wraps > 100 && max_count == 2 && buffer_count == 0, "queue coverage");
    $display("MSU SV PASS: cycles=%0d accepted=%0d beats=%0d done=%0d simultaneous=%0d faults=%0d resets=%0d stalls=%0d full_last=%0d wraps=%0d max_count=%0d",
             checked, accepted, beats, done_tiles, simultaneous, faults, resets,
             stalls, full_last, wraps, max_count);
    $finish;
  end

  initial begin : watchdog
    #3000000;
    $fatal(1, "MSU test timed out");
  end
endmodule
