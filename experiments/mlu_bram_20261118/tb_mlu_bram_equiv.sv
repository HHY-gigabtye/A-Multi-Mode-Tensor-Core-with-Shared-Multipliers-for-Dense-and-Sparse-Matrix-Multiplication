`timescale 1ns/1ps
// Supplemental verification: original C vectors and directed bank/head edges.
// The reference is a byte-identical baseline with only its module name changed.
module tb_mlu_bram_equiv;
  import mlu_pkg::*;
  logic clk = 0, rst_n = 0;
  mlu_inputs_t stimulus = '0;
  mlu_outputs_t observed, reference_out, golden_out;
  io_status_t status, reference_status;
  mlu_tick_info_t events, reference_events, golden_events;
  mlu_state_t golden_state;
  integer steps = 0, vector_records = 0, transitions = 0;
  integer collisions = 0, stalls = 0, reset_edges = 0;
  integer transition_coverage [0:2][0:2];
  bit checking_vectors = 0;
  integer golden_status;
`ifdef NETLIST
  mlu_netlist_wrapper dut (
`else
  mlu dut (
`endif
    .clk(clk), .rst_n(rst_n), .command_valid(stimulus.command_valid),
    .command(stimulus.command), .command_ready(observed.command_ready),
    .read_request_valid(observed.read_request_valid),
    .read_request_ready(stimulus.read_request_ready), .read_addr(observed.read_addr),
    .read_beats(observed.read_beats), .read_data_valid(stimulus.read_data_valid),
    .read_data_ready(observed.read_data_ready), .read_data(stimulus.read_data),
    .read_last(stimulus.read_last), .out_valid(observed.out_valid),
    .out_ready(stimulus.out_ready), .out_packet(observed.out_frame.packet),
    .out_meta(observed.out_frame.meta), .out_k(observed.out_frame.k),
    .status(status), .tick_info(events)
  );
  mlu_reference reference_dut (
    .clk(clk), .rst_n(rst_n), .command_valid(stimulus.command_valid),
    .command(stimulus.command), .command_ready(reference_out.command_ready),
    .read_request_valid(reference_out.read_request_valid),
    .read_request_ready(stimulus.read_request_ready), .read_addr(reference_out.read_addr),
    .read_beats(reference_out.read_beats), .read_data_valid(stimulus.read_data_valid),
    .read_data_ready(reference_out.read_data_ready), .read_data(stimulus.read_data),
    .read_last(stimulus.read_last), .out_valid(reference_out.out_valid),
    .out_ready(stimulus.out_ready), .out_packet(reference_out.out_frame.packet),
    .out_meta(reference_out.out_frame.meta), .out_k(reference_out.out_frame.k),
    .status(reference_status), .tick_info(reference_events)
  );
  task automatic step(input mlu_inputs_t inputs, input bit reset_now = 0);
    clk = 0;
    stimulus = inputs;
    rst_n = !reset_now;
    #5;
    if (observed !== reference_out || status !== reference_status) begin
      $display("step=%0d observed=%h reference=%h status=%0d/%0d", steps, observed, reference_out, status, reference_status);
      $fatal(1, "MLU pre-edge pin equivalence failed");
    end
    if (checking_vectors && (observed !== golden_out || status !== io_status_t'(golden_status)))
      $fatal(1, "C vector pin comparison failed at record %0d", vector_records);
    if (reset_now) reset_edges++;
    if (observed.out_valid && !inputs.out_ready) stalls++;
    if (!reset_now && status == IO_OK && observed.out_valid && inputs.out_ready &&
        observed.out_frame.k == 7 && observed.read_data_ready && inputs.read_data_valid && inputs.read_last)
      collisions++;
    clk = 1;
    #5;
    if (events !== reference_events) $fatal(1, "MLU event equivalence failed step=%0d", steps);
`ifndef NETLIST
    if (dut.state_q !== reference_dut.state_q)
      $fatal(1, "MLU logical RAM/control state equivalence failed step=%0d", steps);
`endif
    if (checking_vectors && (events !== golden_events || reference_dut.state_q !== golden_state))
      $fatal(1, "C vector event/reference state mismatch record=%0d", vector_records);
    steps++;
  endtask
  function automatic io_image_t make_image(input int id);
    io_image_t image_data;
    for (int b = 0; b < 160; b++) image_data[b] = 8'(37*b + 11*id);
    for (int g = 0; g < 2; g++)
      for (int j = 0; j < 8; j++)
        case ((id+g+j)%6)
          0: image_data[72+24*g+3*j] = 8'h03;
          1: image_data[72+24*g+3*j] = 8'h05;
          2: image_data[72+24*g+3*j] = 8'h06;
          3: image_data[72+24*g+3*j] = 8'h09;
          4: image_data[72+24*g+3*j] = 8'h0a;
          5: image_data[72+24*g+3*j] = 8'h0c;
        endcase
    return image_data;
  endfunction
  task automatic command_and_request(input int mode, input int id);
    mlu_inputs_t in_data;
    in_data = '0;
    in_data.command_valid = 1;
    in_data.command.mode = io_mode_t'(mode);
    in_data.command.src_addr = 64'(id*256);
    in_data.command.meta.tile_id = 32'(id);
    in_data.command.meta.dst_addr = 64'h100000 + 64'(id*512);
    step(in_data);
    if (!events.command_accepted) $fatal(1, "Directed command was not accepted");
    in_data = '0;
    in_data.read_request_ready = 1;
    step(in_data);
    if (!events.read_request_accepted) $fatal(1, "Directed request was not accepted");
  endtask
  task automatic initial_load(input int mode, input int id);
    mlu_inputs_t in_data;
    io_image_t bytes;
    int beats;
    command_and_request(mode, id);
    bytes = make_image(id);
    beats = (mode == 2) ? 5 : 4;
    for (int b = 0; b < beats; b++) begin
      in_data = '0;
      in_data.read_data_valid = 1;
      in_data.read_data = bytes[32*b +: 32];
      in_data.read_last = (b == beats-1);
      step(in_data);
    end
  endtask
  initial begin : run
    int fd, rc, reset_word, id, current_mode, next_mode, beats;
    string vectors;
    mlu_inputs_t in_data, vector_input;
    io_image_t bytes;
    for (int a = 0; a < 3; a++)
      for (int b = 0; b < 3; b++) transition_coverage[a][b] = 0;
    // Allow the vendor netlist's global startup reset to finish.
    #200;
    step('0, 1);
    if (!$value$plusargs("VECTORS=%s", vectors)) $fatal(1, "Missing VECTORS path");
    fd = $fopen(vectors, "r");
    if (!fd) $fatal(1, "Cannot open immutable vectors");
    checking_vectors = 1;
    while (!$feof(fd)) begin
      rc = $fscanf(fd, "%d %h %h %d %h %h\n", reset_word, vector_input,
                    golden_out, golden_status, golden_events, golden_state);
      if (rc == 6) begin
        vector_records++;
        step(vector_input, reset_word != 0);
      end else if (rc != -1) $fatal(1, "Malformed immutable vector record");
    end
    $fclose(fd);
    checking_vectors = 0;
    id = 2000;
    for (int first_mode = 0; first_mode < 3; first_mode++) begin
      for (int second_mode = 0; second_mode < 3; second_mode++) begin
        step('0, 1);
        initial_load(first_mode, id++);
        current_mode = first_mode;
        // Two transitions exercise both physical slot directions, 0->1->0.
        for (int turn = 0; turn < 2; turn++) begin
          next_mode = (turn == 0) ? second_mode : first_mode;
          bytes = make_image(id);
          command_and_request(next_mode, id++);
          beats = (next_mode == 2) ? 5 : 4;
          for (int k = 0; k < 8; k++) begin
            step('0); // Stall every outgoing packet before accepting it.
            in_data = '0;
            in_data.out_ready = 1;
            if (k < beats-1 || k == 7) begin
              in_data.read_data_valid = 1;
              in_data.read_data = bytes[32*((k == 7) ? beats-1 : k) +: 32];
              in_data.read_last = (k == 7);
            end
            step(in_data);
            if (!events.packet_issued || events.k != 3'(k))
              $fatal(1, "Directed packet timing changed k=%0d", k);
          end
          if (!observed.out_valid || observed.out_frame.k != 0)
            $fatal(1, "Added bubble on simultaneous last-beat/head transition");
          transition_coverage[current_mode][next_mode]++;
          transitions++;
          current_mode = next_mode;
        end
        for (int k = 0; k < 8; k++) begin
          in_data = '0;
          in_data.out_ready = 1;
          step(in_data);
        end
      end
    end
    if (vector_records != 16708 || transitions != 18 || collisions < 18 || stalls == 0)
      $fatal(1, "Missing required supplemental coverage");
    for (int a = 0; a < 3; a++)
      for (int b = 0; b < 3; b++)
        if (transition_coverage[a][b] == 0) $fatal(1, "Missing mode transition %0d->%0d", a, b);
    $display("MLU BRAM EQUIVALENCE PASS vectors=%0d steps=%0d directed_transitions=%0d simultaneous_last=%0d stalls=%0d resets=%0d",
             vector_records, steps, transitions, collisions, stalls, reset_edges);
    $finish;
  end
endmodule
