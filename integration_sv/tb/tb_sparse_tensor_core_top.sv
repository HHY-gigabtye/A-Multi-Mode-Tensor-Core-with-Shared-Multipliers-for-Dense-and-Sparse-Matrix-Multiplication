`timescale 1ns/1ps

// SV-only end-to-end test: independent matrices -> memory image -> real RTL
// -> byte-level writeback scoreboard. No DPI, C build, or forced DUT signals.
module tb_sparse_tensor_core_top;
  localparam int MAX_TILES = 96;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0;
  logic command_valid, command_ready, read_request_valid, read_request_ready;
  logic read_data_valid, read_data_ready, read_last, write_valid, write_ready;
  logic write_last, tile_done;
  logic [63:0] read_addr, write_addr;
  logic [2:0] read_beats;
  mlu_pkg::io_command_t command;
  mlu_pkg::io_beat_t read_data;
  msu_pkg::msu_beat_t write_data;
  msu_pkg::io_meta_t write_meta, completed;
  mlu_pkg::io_status_t mlu_status;
  du_tc_bridge_pkg::io_status_t bridge_status;
  tensor_core_pkg::tc_status_t tc_status;
  msu_pkg::io_status_t msu_status;
  sparse_tensor_core_top dut (.*);

  int a[MAX_TILES][8][8], b[MAX_TILES][8][8];
  logic [7:0] keep_a[MAX_TILES][8], keep_b[MAX_TILES][8];
  logic [7:0] image_bytes[MAX_TILES][160];
  tensor_core_pkg::tc_matrix_t expected[MAX_TILES];
  mlu_pkg::io_command_t commands[MAX_TILES];
  int issue_cycle[MAX_TILES][8];
  int last_tc_cycle[MAX_TILES];
  int mode_seq[MAX_TILES];
  int epoch = 0, cycle, tile_limit;
  int submitted, requests, issued, arrived, accepted, produced, results, beats, dones;
  int total_tiles = 0, total_packets = 0, total_beats = 0, resets = 0;
  int active_tile, active_beat, active_beats, response_delay;
  bit memory_active;
  bit random_stalls;
  int hold_write_cycles;
  logic [31:0] rng = 32'h91e10da5;
  bit passed = 0;
  int cov_credit_full = 0, cov_fifo_full = 0, cov_inflight_full = 0;
  int cov_meta_full = 0, cov_msu_full = 0, cov_tc_full = 0;
  int cov_fifo_both = 0, cov_meta_both = 0, cov_fifo_wrap = 0, cov_meta_wrap = 0;
  int cov_write_stall = 0, cov_last_stall = 0, cov_mlu_stall = 0;
  int cov_read_stall = 0, cov_command_stall = 0, cov_mode_wait = 0;
  int cov_ii8 = 0, last_sparse_start;
  int cov_mode[3], cov_masks[16], cov_zero = 0, cov_full = 0, cov_stored_zero = 0;
  int cov_transition[3][3];
  bit [8:0] reset_fifo = 0;
  bit [4:0] reset_flight = 0;
  bit [2:0] reset_meta = 0, reset_msu = 0, reset_tc = 0, reset_mlu = 0;
  bit [7:0] reset_rows = 0;
  bit reset_read = 0, reset_last = 0;

  task automatic check(input bit condition, input string message);
    if (!condition) $fatal(1, "TOP FAIL epoch=%0d cycle=%0d: %s", epoch, cycle, message);
  endtask

  function automatic logic [31:0] random_word();
    rng = rng ^ (rng << 13);
    rng = rng ^ (rng >> 17);
    rng = rng ^ (rng << 5);
    return rng;
  endfunction

  function automatic int value_at(input int t, i, k, salt);
    case ((t + i + 3*k + salt) % 11)
      0: return -128;
      1: return 127;
      2: return 0;
      3: return -1;
      4: return 1;
      default: return ((t*43 + i*29 + k*17 + salt*7) % 256) - 128;
    endcase
  endfunction

  function automatic logic [7:0] bitmap_at(input int t, k, salt);
    case ((t+k+salt)%8)
      0: return 8'h00;
      1: return 8'hff;
      2: return 8'h01;
      3: return 8'h80;
      4: return 8'h55;
      5: return 8'haa;
      default: return 8'(t*37 + k*71 + salt*19);
    endcase
  endfunction

  function automatic logic [3:0] mask_at(input int n);
    case (n%6)
      0: return 4'h3;
      1: return 4'h5;
      2: return 4'h6;
      3: return 4'h9;
      4: return 4'ha;
      default: return 4'hc;
    endcase
  endfunction

  // pattern=0: hybrid/dual overlap; pattern=1: all nine mode transitions.
  task automatic prepare(input int count, pattern);
    int mode, rank_a, rank_b, off, sum;
    logic [3:0] mask;
    tile_limit = count;
    for (int t=0; t<count; t++) begin
      if (pattern == 0) mode = 1 + (t%2);
      else begin
        case (t%9)
          0,1,6: mode = 0;
          2,3,8: mode = 1;
          default: mode = 2;
        endcase
      end
      mode_seq[t] = mode;
      commands[t] = '0;
      commands[t].mode = mlu_pkg::io_mode_t'(mode);
      // Exercise full address and tile-ID widths, not only low bits.
      commands[t].src_addr = 64'h0000_0001_0000_0000 + 64'(t)*256;
      commands[t].meta.dst_addr = 64'h0000_0002_0000_0000 + 64'(t)*512;
      commands[t].meta.tile_id = 32'h8000_0000 + 32'(epoch*256+t);
      for (int n=0; n<160; n++) image_bytes[t][n] = 8'hd3;
      for (int k=0; k<8; k++) begin
        keep_a[t][k] = (mode == 0) ? 8'hff : bitmap_at(t,k,0);
        keep_b[t][k] = (mode == 0) ? 8'hff : bitmap_at(t,k,3);
        if (mode == 1)
          for (int j=0; j<8; j++) begin
            mask = mask_at(t+k/4+j);
            keep_b[t][k][j] = mask[k%4];
          end
        for (int i=0; i<8; i++) begin
          a[t][i][k] = keep_a[t][k][i] ? value_at(t,i,k,0) : 0;
          b[t][k][i] = keep_b[t][k][i] ? value_at(t,i,k,5) : 0;
        end
      end
      // Independently compute mathematical GEMM from the original matrices.
      for (int i=0; i<8; i++)
        for (int j=0; j<8; j++) begin
          sum = 0;
          for (int k=0; k<8; k++) sum += a[t][i][k]*b[t][k][j];
          expected[t][i][j] = 32'(sum);
        end
      // Encode the documented memory layout without calling RTL helpers.
      for (int k=0; k<8; k++) begin
        rank_a = 0; rank_b = 0;
        if (mode == 0) begin
          for (int i=0; i<8; i++) begin
            image_bytes[t][16*k+i] = 8'(a[t][i][k]);
            image_bytes[t][16*k+8+i] = 8'(b[t][k][i]);
          end
        end else begin
          off = (mode == 1) ? 9*k : 18*k;
          image_bytes[t][off] = keep_a[t][k];
          if (mode == 2) image_bytes[t][off+9] = keep_b[t][k];
          for (int i=0; i<8; i++) begin
            if (keep_a[t][k][i]) begin
              image_bytes[t][off+1+rank_a] = 8'(a[t][i][k]);
              rank_a++;
            end
            if (mode == 2 && keep_b[t][k][i]) begin
              image_bytes[t][off+10+rank_b] = 8'(b[t][k][i]);
              rank_b++;
            end
          end
        end
      end
      if (mode == 1)
        for (int g=0; g<2; g++)
          for (int j=0; j<8; j++) begin
            mask = mask_at(t+g+j);
            cov_masks[mask]++;
            off = 72+24*g+3*j;
            image_bytes[t][off] = {4'd0,mask};
            rank_b = 0;
            for (int p=0; p<4; p++)
              if (mask[p]) begin
                image_bytes[t][off+1+rank_b] = 8'(b[t][4*g+p][j]);
                rank_b++;
              end
          end
    end
  endtask

  function automatic tensor_core_pkg::tc_input_packet_t packet_for(input int t, k);
    tensor_core_pkg::tc_input_packet_t p;
    int na, nb;
    p = '0; na = 0; nb = 0;
    p.is_sparse = (mode_seq[t] != 0);
    for (int i=0; i<8; i++) begin
      if (!p.is_sparse) begin
        p.payload.dense.dense_a[i] = 8'(a[t][i][k]);
        p.payload.dense.dense_b[i] = 8'(b[t][k][i]);
      end else begin
        if (keep_a[t][k][i]) begin
          p.payload.sparse.a.value[na] = 8'(a[t][i][k]);
          p.payload.sparse.a.index[na] = 3'(i);
          na++;
        end
        if (keep_b[t][k][i]) begin
          p.payload.sparse.b.value[nb] = 8'(b[t][k][i]);
          p.payload.sparse.b.index[nb] = 3'(i);
          nb++;
        end
      end
    end
    if (p.is_sparse) begin
      p.payload.sparse.a.count = 4'(na);
      p.payload.sparse.b.count = 4'(nb);
    end
    return p;
  endfunction

  task automatic reset_system;
    @(negedge clk);
    // Record the actual occupancy that is being discarded by this reset.
    if (rst_n) begin
      reset_fifo[int'(dut.fifo_count)] = 1;
      reset_flight[int'(dut.inflight_count)] = 1;
      reset_meta[int'(dut.result_meta_count)] = 1;
      reset_msu[int'(dut.u_msu.buffer_count)] = 1;
      reset_tc[int'(dut.u_tensor_core.ctrl_q.result_count)] = 1;
      reset_mlu[int'(dut.u_mlu.state_q.count)] = 1;
      if (dut.u_msu.buffer_count != 0) reset_rows[int'(dut.u_msu.row_index)] = 1;
      if (memory_active) reset_read = 1;
      if (write_valid && write_last && !write_ready) reset_last = 1;
    end
    rst_n = 0;
    command_valid = 0; command = '0;
    read_request_ready = 0; read_data_valid = 0; read_data = '0; read_last = 0;
    write_ready = 0;
    memory_active = 0; active_tile = 0; active_beat = 0; active_beats = 0;
    response_delay = 0;
    cycle = 0; submitted = 0; requests = 0; issued = 0; arrived = 0;
    accepted = 0; produced = 0; results = 0; beats = 0; dones = 0; last_sparse_start = -100;
    repeat (2) @(posedge clk);
    #1;
    check(!command_ready && !read_request_valid && !read_data_ready &&
          !write_valid && !tile_done && !dut.issue && !dut.tc_accept &&
          !dut.result_accept, "external transfer visible in reset");
    check(dut.fifo_count == 0 && dut.inflight_count == 0 &&
          dut.result_meta_count == 0 && !dut.du_valid &&
          !dut.tc_result_valid && dut.u_msu.buffer_count == 0,
          "reset did not flush pipeline");
    @(negedge clk);
    rst_n = 1;
    epoch++; resets++;
  endtask

  // All inputs are driven at the falling edge; all handshakes below are read
  // before the rising-edge NBA updates. Only then are post-edge states checked.
  task automatic tick;
    bit command_fire, request_fire, read_fire, write_fire, issue_fire;
    bit du_fire, tc_fire, result_fire, meta_push, last_fire;
    bit stalled_write, stalled_mlu, stalled_request, stalled_command;
    bit stalled_result;
    tensor_core_pkg::tc_matrix_t old_result;
    du_tc_bridge_pkg::io_meta_t old_result_meta;
    msu_pkg::msu_beat_t old_write_data;
    msu_pkg::io_meta_t old_write_meta;
    logic [63:0] old_write_addr, old_read_addr;
    logic old_write_last;
    logic [2:0] old_read_beats, old_mlu_k;
    mlu_pkg::io_meta_t old_mlu_meta;
    mlu_pkg::io_command_t old_command;
    du_tia_pkg::du_tia_input_t old_mlu_packet;
    int old_fifo, old_flight, old_meta, t, k, row;
    tensor_core_pkg::tc_input_packet_t golden_packet;
    @(negedge clk);
    // Hold commands and response payload until their actual handshakes.
    if (!command_valid && submitted < tile_limit &&
        (!random_stalls || (random_word()%4 != 0))) begin
      command = commands[submitted];
      command_valid = 1;
    end
    read_request_ready = !random_stalls || (random_word()%4 != 0);
    if (!read_data_valid && memory_active) begin
      if (response_delay != 0) response_delay--;
      else if (!random_stalls || (random_word()%3 != 0)) begin
        read_data_valid = 1;
        for (int n=0; n<32; n++)
          read_data[n] = image_bytes[active_tile][32*active_beat+n];
        read_last = (active_beat == active_beats-1);
      end
    end
    write_ready = (cycle >= hold_write_cycles) &&
                  (!random_stalls || (random_word()%4 != 0));
    @(posedge clk);
    check(mlu_status === mlu_pkg::IO_OK &&
          bridge_status === du_tc_bridge_pkg::IO_OK &&
          tc_status === tensor_core_pkg::TC_OK && msu_status === msu_pkg::IO_OK,
          $sformatf("status MLU=%0d bridge=%0d TC=%0d MSU=%0d",
                    mlu_status, bridge_status, tc_status, msu_status));
    command_fire = command_valid && command_ready;
    request_fire = read_request_valid && read_request_ready;
    read_fire = read_data_valid && read_data_ready;
    write_fire = write_valid && write_ready;
    last_fire = write_fire && write_last;
    issue_fire = dut.issue; du_fire = dut.du_valid;
    tc_fire = dut.tc_accept; result_fire = dut.result_accept;
    meta_push = tc_fire && dut.head_entry.k == 0;
    old_fifo = int'(dut.fifo_count); old_flight = int'(dut.inflight_count);
    old_meta = int'(dut.result_meta_count);
    check(old_fifo+old_flight <= 8, "credit overflow");
    check(dut.can_issue === (old_fifo+old_flight < 8), "credit lookahead");
    check(dut.issue === (dut.mlu_out_valid && dut.can_issue), "MLU/DU transfer");
    check(dut.tc_accept === (dut.head_valid && dut.tc_in_ready), "TC strict valid");
    check(dut.result_accept === (dut.msu_result_valid && dut.msu_result_ready),
          "TC/MSU/metadata handshakes disagree");
    if (dut.tc_result_valid) check(dut.result_meta_valid, "result without metadata");
    if (old_fifo == 0) check(!tc_fire, "empty FIFO bypass");
    if (old_meta == 2 && dut.head_entry.k == 0) check(!tc_fire, "full metadata k=0");

    if (old_fifo+old_flight == 8) cov_credit_full++;
    if (old_fifo == 8) cov_fifo_full++;
    if (old_flight == 4) cov_inflight_full++;
    if (old_meta == 2) cov_meta_full++;
    if (dut.u_msu.buffer_count == 2) cov_msu_full++;
    if (dut.u_tensor_core.ctrl_q.result_count == 2) cov_tc_full++;
    if (du_fire && tc_fire) cov_fifo_both++;
    if (meta_push && result_fire) cov_meta_both++;
    if (tc_fire && dut.u_bridge.q.head == 7) cov_fifo_wrap++;
    if (result_fire && dut.u_bridge.q.meta_head == 1) cov_meta_wrap++;
    if (dut.head_valid && !dut.tc_in_ready && dut.u_tensor_core.input_ready)
      cov_mode_wait++;

    stalled_write = write_valid && !write_ready;
    old_write_data = write_data; old_write_addr = write_addr;
    old_write_meta = write_meta; old_write_last = write_last;
    stalled_mlu = dut.mlu_out_valid && !dut.can_issue;
    old_mlu_packet = dut.mlu_packet; old_mlu_meta = dut.mlu_meta; old_mlu_k = dut.mlu_k;
    stalled_request = read_request_valid && !read_request_ready;
    old_read_addr = read_addr; old_read_beats = read_beats;
    stalled_command = command_valid && !command_ready; old_command = command;
    stalled_result = dut.tc_result_valid && !dut.tc_result_ready;
    old_result = dut.tc_result; old_result_meta = dut.result_meta;
    if (stalled_write) cov_write_stall++;
    if (stalled_write && write_last) cov_last_stall++;
    if (stalled_mlu) cov_mlu_stall++;
    if (stalled_request) cov_read_stall++;
    if (stalled_command) cov_command_stall++;

    if (command_fire) begin
      check(command === commands[submitted], "command order/payload");
      submitted++;
    end
    if (request_fire) begin
      check(!memory_active && requests < submitted, "multiple/uncommanded reads");
      check(read_addr === commands[requests].src_addr, "read address/order");
      check(read_beats == ((mode_seq[requests] == 2) ? 5 : 4), "read burst length");
      active_tile = requests; active_beat = 0; active_beats = int'(read_beats);
      response_delay = random_stalls ? int'(random_word()%5) : 0;
      memory_active = 1; requests++;
    end
    if (read_fire) begin
      check(!request_fire && memory_active, "response bypass/no outstanding request");
      active_beat++;
      if (read_last) memory_active = 0;
    end
    if (issue_fire) begin
      t = issued/8; k = issued%8;
      check(t < submitted, "issue without command");
      check(dut.mlu_k == k && dut.mlu_meta === commands[t].meta &&
            dut.mlu_packet.mode == mode_seq[t] && dut.mlu_packet.k_position == k%4,
            "MLU issue k/mode/metadata order");
      issue_cycle[t][k] = cycle;
      issued++; total_packets++;
    end
    if (du_fire) begin
      t = arrived/8; k = arrived%8;
      check(arrived < issued && cycle == issue_cycle[t][k]+4, "DU arrival latency");
      check(dut.decoded_packet === packet_for(t,k), "decoded DU payload");
      arrived++;
    end
    if (tc_fire) begin
      t = accepted/8; k = accepted%8;
      check(accepted < arrived && cycle >= issue_cycle[t][k]+5, "FIFO timing/order");
      golden_packet = packet_for(t,k);
      check(dut.head_entry.packet === golden_packet && dut.head_entry.k == k &&
            dut.head_entry.meta === commands[t].meta, "TC payload/k/metadata");
      if (golden_packet.is_sparse) begin
        if (golden_packet.payload.sparse.a.count == 0 ||
            golden_packet.payload.sparse.b.count == 0) cov_zero++;
        if (golden_packet.payload.sparse.a.count == 8 ||
            golden_packet.payload.sparse.b.count == 8) cov_full++;
        for (int n=0; n<8; n++) begin
          if (n < golden_packet.payload.sparse.a.count &&
              golden_packet.payload.sparse.a.value[n] == 0) cov_stored_zero++;
          if (n < golden_packet.payload.sparse.b.count &&
              golden_packet.payload.sparse.b.value[n] == 0) cov_stored_zero++;
        end
      end
      if (k == 0) begin
        cov_mode[mode_seq[t]]++;
        if (t > 0) cov_transition[mode_seq[t-1]][mode_seq[t]]++;
        if (mode_seq[t] != 0) begin
          if (cycle-last_sparse_start == 8) cov_ii8++;
          if (epoch == 1 && t > 0)
            check(cycle-last_sparse_start == 8, "unstalled sparse stream must sustain II=8");
          last_sparse_start = cycle;
        end else last_sparse_start = -100;
      end
      if (k == 7) last_tc_cycle[t] = cycle;
      accepted++;
    end
    if (result_fire) begin
      check(results < accepted/8, "result before eight TC packets");
      check(dut.result_meta === commands[results].meta, "TC result metadata/order");
      check(dut.tc_result === expected[results], "TC GEMM result");
      results++;
    end
    if (write_fire) begin
      t = beats/8; row = beats%8;
      check(t < results, "write before MSU accepts result");
      check(write_meta === commands[t].meta, "write metadata/order");
      check(write_addr === commands[t].meta.dst_addr + 64'(32*row), "write address");
      check(write_last === (row == 7), "write_last");
      for (int j=0; j<8; j++)
        for (int byte_lane=0; byte_lane<4; byte_lane++)
          check(write_data[8*(4*j+byte_lane)+:8] === expected[t][row][j][8*byte_lane+:8],
                $sformatf("write byte tile=%0d row=%0d col=%0d byte=%0d",t,row,j,byte_lane));
      beats++; total_beats++;
    end
    #1;
    // Measured against the current SV pipeline: last input -> publication
    // is three edges for sparse and fifteen for dense (no new top latency).
    check(dut.u_tensor_core.tick_info.result_produced ===
          ((produced < accepted/8) &&
           (cycle == last_tc_cycle[produced] + ((mode_seq[produced] == 0) ? 15 : 3))),
          "TC result publication timing");
    if (dut.u_tensor_core.tick_info.result_produced) produced++;
    check(int'(dut.fifo_count) == old_fifo+int'(du_fire)-int'(tc_fire), "FIFO edge count");
    check(int'(dut.inflight_count) == old_flight+int'(issue_fire)-int'(du_fire),
          "inflight edge count");
    check(int'(dut.result_meta_count) == old_meta+int'(meta_push)-int'(result_fire),
          "metadata must pop at TC/MSU handshake");
    check(tile_done === last_fire, "tile_done must follow final accepted write edge");
    if (last_fire) begin
      check(completed === old_write_meta, "completion metadata");
      dones++; total_tiles++;
    end else check(completed === '0, "completion metadata without tile_done");
    if (stalled_write)
      check(write_valid && write_data === old_write_data && write_addr === old_write_addr &&
            write_meta === old_write_meta && write_last === old_write_last, "stalled write changed");
    if (stalled_mlu)
      check(dut.mlu_out_valid && dut.mlu_packet === old_mlu_packet &&
            dut.mlu_meta === old_mlu_meta && dut.mlu_k === old_mlu_k, "stalled MLU changed");
    if (stalled_request)
      check(read_request_valid && read_addr === old_read_addr && read_beats === old_read_beats,
            "stalled read request changed");
    if (stalled_command) check(command_valid && command === old_command, "stalled command changed");
    if (stalled_result)
      check(dut.tc_result_valid && dut.tc_result === old_result &&
            dut.result_meta === old_result_meta, "stalled TC result/metadata changed");
    // Update the TB producer only after every DUT block has sampled the edge.
    if (command_fire) command_valid = 0;
    if (read_fire) read_data_valid = 0;
    cycle++;
    check(cycle < 10000, "watchdog");
  endtask

  task automatic drain_and_check;
    while (dones < tile_limit) tick();
    repeat (12) tick();
    check(submitted == tile_limit && requests == tile_limit && issued == tile_limit*8 &&
          arrived == issued && accepted == issued && produced == tile_limit && results == tile_limit &&
          beats == tile_limit*8 && dones == tile_limit, "final packet/result accounting");
    check(!memory_active && !write_valid && !dut.tc_result_valid &&
          dut.fifo_count == 0 && dut.inflight_count == 0 && dut.result_meta_count == 0 &&
          dut.u_mlu.state_q.count == 0 && dut.u_msu.buffer_count == 0,
          "pipeline did not drain");
    $display("TOP PHASE PASS epoch=%0d tiles=%0d cycles=%0d stalls=%0d",
             epoch,tile_limit,cycle,random_stalls);
  endtask

  function automatic bit reached(input int kind, target);
    case (kind)
      0: return int'(dut.fifo_count) == target;
      1: return int'(dut.inflight_count) == target;
      2: return int'(dut.result_meta_count) == target;
      3: return int'(dut.u_msu.buffer_count) == target;
      4: return int'(dut.u_tensor_core.ctrl_q.result_count) == target;
      5: return int'(dut.u_mlu.state_q.count) == target;
      6: return dut.u_msu.buffer_count != 0 && int'(dut.u_msu.row_index) == target;
      7: return memory_active && active_beat > 0;
      default: return write_valid && write_last && !write_ready;
    endcase
  endfunction

  task automatic reset_at(input int kind, target);
    reset_system(); prepare(24,0);
    random_stalls = (kind == 8);
    hold_write_cycles = (kind < 6) ? 300 : 0;
    while (!reached(kind,target)) tick();
    $display("TOP RESET target_kind=%0d occupancy=%0d cycle=%0d",kind,target,cycle);
    reset_system(); prepare(3,1);
    random_stalls = 0; hold_write_cycles = 0;
    drain_and_check();
  endtask

  initial begin
    for (int n=0; n<3; n++) cov_mode[n] = 0;
    for (int i=0; i<3; i++)
      for (int j=0; j<3; j++) cov_transition[i][j] = 0;
    for (int n=0; n<16; n++) cov_masks[n] = 0;
    reset_system(); prepare(64,0);
    random_stalls = 0; hold_write_cycles = 0;
    drain_and_check();
    reset_system(); prepare(96,1);
    random_stalls = 1; hold_write_cycles = 320;
    drain_and_check();
    // Sparse-only saturation reaches both physical TC result slots.
    reset_system(); prepare(48,0);
    random_stalls = 1; hold_write_cycles = 320;
    drain_and_check();
    for (int n=0; n<=8; n++) reset_at(0,n);
    for (int n=0; n<=4; n++) reset_at(1,n);
    for (int kind=2; kind<=5; kind++)
      for (int n=0; n<=2; n++) reset_at(kind,n);
    for (int row=0; row<8; row++) reset_at(6,row);
    reset_at(7,0); reset_at(8,0);
    check(cov_credit_full>0 && cov_fifo_full>0 && cov_inflight_full>0 &&
          cov_meta_full>0 && cov_msu_full>0 && cov_tc_full>0, "missing full-buffer coverage");
    check(cov_fifo_both>0 && cov_meta_both>0 && cov_fifo_wrap>0 && cov_meta_wrap>0,
          "missing simultaneous/wrap coverage");
    check(cov_write_stall>0 && cov_last_stall>0 && cov_mlu_stall>0 &&
          cov_read_stall>0 && cov_command_stall>0 && cov_mode_wait>0,
          "missing backpressure/mode-switch coverage");
    check(cov_ii8>0 && cov_zero>0 && cov_full>0 && cov_stored_zero>0,
          "missing sparse overlap/data coverage");
    for (int n=0; n<3; n++) check(cov_mode[n]>0, "missing mode");
    for (int i=0; i<3; i++)
      for (int j=0; j<3; j++) check(cov_transition[i][j]>0, "missing mode transition");
    for (int n=0; n<6; n++) check(cov_masks[mask_at(n)]>0, "missing 2:4 mask");
    check((&reset_fifo) && (&reset_flight) && (&reset_meta) && (&reset_msu) &&
          (&reset_tc) && (&reset_mlu) && (&reset_rows) && reset_read && reset_last,
          "missing reset occupancy coverage");
    $display("TOP COVERAGE full_credit=%0d fifo_full=%0d inflight4=%0d meta_full=%0d msu_full=%0d tc_full=%0d",
             cov_credit_full,cov_fifo_full,cov_inflight_full,cov_meta_full,cov_msu_full,cov_tc_full);
    $display("TOP COVERAGE fifo_both=%0d meta_both=%0d fifo_wrap=%0d meta_wrap=%0d sparse_II8=%0d",
             cov_fifo_both,cov_meta_both,cov_fifo_wrap,cov_meta_wrap,cov_ii8);
    $display("TOP COVERAGE write_stall=%0d last_stall=%0d mlu_stall=%0d read_stall=%0d command_stall=%0d mode_wait=%0d",
             cov_write_stall,cov_last_stall,cov_mlu_stall,cov_read_stall,cov_command_stall,cov_mode_wait);
    $display("TOP COVERAGE modes=%0d/%0d/%0d zero_count=%0d full_count=%0d stored_zero=%0d",
             cov_mode[0],cov_mode[1],cov_mode[2],cov_zero,cov_full,cov_stored_zero);
    $display("TOP MODE TRANSITIONS 0->0/1/2=%0d/%0d/%0d 1->0/1/2=%0d/%0d/%0d 2->0/1/2=%0d/%0d/%0d",
             cov_transition[0][0],cov_transition[0][1],cov_transition[0][2],
             cov_transition[1][0],cov_transition[1][1],cov_transition[1][2],
             cov_transition[2][0],cov_transition[2][1],cov_transition[2][2]);
    $display("TOP RESET COVERAGE fifo=%h inflight=%h meta=%h msu=%h tc=%h mlu=%h rows=%h read=%b last=%b",
             reset_fifo,reset_flight,reset_meta,reset_msu,reset_tc,reset_mlu,reset_rows,reset_read,reset_last);
    passed = 1;
    $display("TOP INTEGRATION PASS: completed_tiles=%0d issued_packets=%0d write_beats=%0d resets=%0d seed=91e10da5",
             total_tiles,total_packets,total_beats,resets);
    
    $finish;
  end
  initial begin #10000000; $fatal(1,"Global timeout"); end
endmodule
