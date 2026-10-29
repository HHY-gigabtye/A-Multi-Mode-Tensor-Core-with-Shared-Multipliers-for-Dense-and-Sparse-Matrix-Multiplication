`timescale 1ns/1ps

// Standalone MLU unit test: the only instantiated DUT is mlu.
// C vectors drive command/read responses and downstream out_ready stalls.
// du_tia_pkg supplies packet types only; no DU/TIA or bridge RTL is needed.
// Procedural self-checks only: no SVA, UVM, classes or DPI.
module tb_mlu;
  import mlu_pkg::*;
  logic clk, rst_n;
  mlu_inputs_t stimulus;
  mlu_outputs_t observed, expected_outputs;
  io_status_t status;
  mlu_tick_info_t tick_info, expected_info;
  mlu_state_t expected_state;
  logic command_ready, read_request_valid, read_data_ready, out_valid;
  logic [63:0] read_addr;
  logic [2:0] read_beats, out_k;
  io_meta_t out_meta;
  du_tia_pkg::du_tia_input_t out_packet;

  mlu dut (
    .clk(clk), .rst_n(rst_n),
    .command_valid(stimulus.command_valid), .command(stimulus.command),
    .command_ready(command_ready),
    .read_request_valid(read_request_valid),
    .read_request_ready(stimulus.read_request_ready),
    .read_addr(read_addr), .read_beats(read_beats),
    .read_data_valid(stimulus.read_data_valid), .read_data_ready(read_data_ready),
    .read_data(stimulus.read_data), .read_last(stimulus.read_last),
    .out_valid(out_valid), .out_ready(stimulus.out_ready),
    .out_packet(out_packet), .out_meta(out_meta), .out_k(out_k),
    .status(status), .tick_info(tick_info)
  );

  always_comb begin
    observed = '0;
    observed.command_ready = command_ready;
    observed.read_request_valid = read_request_valid;
    observed.read_addr = read_addr;
    observed.read_beats = read_beats;
    observed.read_data_ready = read_data_ready;
    observed.out_valid = out_valid;
    observed.out_frame.meta = out_meta;
    observed.out_frame.k = out_k;
    observed.out_frame.packet = out_packet;
  end

  integer fd, rc, record_count, reset_word, status_word;
  integer resets, rejected, commands, packets, tiles;
  integer simultaneous_command_pop, simultaneous_data_out, full_cycles, both_ready;
  string vector_path;
  logic output_held, request_held;
  io_frame_t held_frame;
  logic [63:0] held_addr;
  logic [2:0] held_beats;

  task automatic fail(input string reason);
    $display("FAIL record=%0d time=%0t: %s", record_count+1, $time, reason);
    $display("  head=%0d count=%0d next_k=%0d phase[0]=%0d phase[1]=%0d",
       dut.state_q.head, dut.state_q.count, dut.state_q.next_k,
       dut.state_q.buffer[0].phase, dut.state_q.buffer[1].phase);
    $fatal(1, "MLU C/SV comparison failed");
  endtask

  initial begin
    clk = 0; rst_n = 0; stimulus = '0;
    record_count = 0; resets = 0; rejected = 0; commands = 0;
    packets = 0; tiles = 0;
    simultaneous_command_pop = 0; simultaneous_data_out = 0;
    full_cycles = 0; both_ready = 0;
    output_held = 0; request_held = 0; held_frame = '0;
    held_addr = '0; held_beats = '0;
    if ($bits(mlu_inputs_t) != 423 || $bits(mlu_outputs_t) != 406 ||
        $bits(mlu_state_t) != 2900 || $bits(mlu_tick_info_t) != 40 ||
        $bits(du_tia_pkg::du_tia_input_t) != 236)
      $fatal(1, "Package dimensions differ from the golden vector format");
    vector_path = "mlu_vectors.txt";
    if ($value$plusargs("VECTORS=%s", vector_path)) begin end
    if ($test$plusargs("VCD")) begin
      $dumpfile("mlu_wave.vcd");
      $dumpvars(0, tb_mlu);
    end
    fd = $fopen(vector_path, "r");
    if (fd == 0) $fatal(1, "Cannot open %s; run from the extracted mlu_sv folder", vector_path);
    while (!$feof(fd)) begin
      rc = $fscanf(fd, "%d %h %h %d %h %h\n", reset_word, stimulus,
                   expected_outputs, status_word, expected_info, expected_state);
      if (rc == 6) begin
        clk = 0;
        rst_n = (reset_word == 0);
        #5;
        if (observed !== expected_outputs) begin
          $display("  observed=%h", observed);
          $display("  expected=%h", expected_outputs);
          fail("pre-edge outputs differ from mlu_peek");
        end
        if (status !== io_status_t'(status_word)) fail("pre-edge status differs from mlu_tick");
        if (rst_n && output_held && (!out_valid || observed.out_frame !== held_frame))
          fail("out frame changed while stalled");
        if (rst_n && request_held && (!read_request_valid || read_addr !== held_addr || read_beats !== held_beats))
          fail("read request changed while stalled");
        output_held = rst_n && status == IO_OK && out_valid && !stimulus.out_ready;
        request_held = rst_n && status == IO_OK && read_request_valid && !stimulus.read_request_ready;
        held_frame = observed.out_frame; held_addr = read_addr; held_beats = read_beats;

        if (rst_n && stimulus.command_valid && !command_ready) full_cycles = full_cycles + 1;
        clk = 1;
        #5;
        if (tick_info !== expected_info) fail("registered handshake events differ from C");
        if (dut.state_q !== expected_state) begin
          for (int s = 0; s < 2; s = s + 1) begin
            if (dut.state_q.buffer[s].command !== expected_state.buffer[s].command)
              $display("  command differs in slot %0d", s);
            for (int b = 0; b < 160; b = b + 1)
              if (dut.state_q.buffer[s].image[b] !== expected_state.buffer[s].image[b])
                $display("  slot=%0d byte=%0d got=%h want=%h", s, b,
                    dut.state_q.buffer[s].image[b], expected_state.buffer[s].image[b]);
          end
          fail("post-edge FULL state differs from C (no hash comparison)");
        end
        if (reset_word != 0) resets = resets + 1;
        if (status_word != 0) rejected = rejected + 1;
        if (tick_info.command_accepted) commands = commands + 1;
        if (tick_info.packet_issued) packets = packets + 1;
        if (tick_info.tile_issued) tiles = tiles + 1;
        if (tick_info.command_accepted && tick_info.tile_issued)
          simultaneous_command_pop = simultaneous_command_pop + 1;
        if (tick_info.read_data_accepted && tick_info.packet_issued)
          simultaneous_data_out = simultaneous_data_out + 1;
        if (dut.state_q.buffer[0].phase == MLU_READY && dut.state_q.buffer[1].phase == MLU_READY)
          both_ready = both_ready + 1;
        record_count = record_count + 1;
      end else if (rc != -1) begin
        fail($sformatf("malformed vector record: %0d fields", rc));
      end
    end
    $fclose(fd);
    if (record_count == 0 || resets == 0 || rejected == 0 || packets == 0 ||
        simultaneous_command_pop == 0 || simultaneous_data_out == 0 ||
        full_cycles == 0 || both_ready == 0)
      $fatal(1, "Missing required coverage");
    $display("ALL PASS MLU unit C/SV: %0d records, %0d resets, %0d rejected edges", record_count, resets, rejected);
    $display("  commands=%0d packets=%0d retired=%0d", commands, packets, tiles);
    $display("  command+retire=%0d read+output=%0d full_stalls=%0d both_ready=%0d",
             simultaneous_command_pop, simultaneous_data_out, full_cycles, both_ready);
    $finish;
  end
endmodule
