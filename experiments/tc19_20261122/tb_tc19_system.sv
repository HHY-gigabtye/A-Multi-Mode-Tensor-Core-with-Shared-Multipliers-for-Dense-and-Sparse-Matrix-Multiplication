`timescale 1ns/1ps
// Additional power workload only. Existing verification sources are untouched.
// No DUT internals or forces: identical memory transactions for RTL and netlist.
module tb_tc19_system;
  localparam int TILES = 288;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0;
  logic command_valid = 0, command_ready, read_request_valid, read_request_ready = 0;
  logic read_data_valid = 0, read_data_ready, read_last = 0, write_valid, write_ready = 0;
  logic write_last, tile_done;
  logic [63:0] read_addr, write_addr;
  logic [2:0] read_beats;
  mlu_pkg::io_command_t command = '0;
  mlu_pkg::io_beat_t read_data = '0;
  msu_pkg::msu_beat_t write_data;
  msu_pkg::io_meta_t write_meta, completed;
  logic [2:0] mlu_status, bridge_status, tc_status, msu_status;
`ifdef POWER_NETLIST
  // Vivado expands packed struct/array ports in the generated timing netlist.
  sparse_tensor_core_top dut (
    .\command[mode] (command.mode),
    .\command[src_addr] (command.src_addr),
    .\command[meta][tile_id] (command.meta.tile_id),
    .\command[meta][dst_addr] (command.meta.dst_addr),
    .\read_data[0] (read_data[0]),
    .\read_data[1] (read_data[1]),
    .\read_data[2] (read_data[2]),
    .\read_data[3] (read_data[3]),
    .\read_data[4] (read_data[4]),
    .\read_data[5] (read_data[5]),
    .\read_data[6] (read_data[6]),
    .\read_data[7] (read_data[7]),
    .\read_data[8] (read_data[8]),
    .\read_data[9] (read_data[9]),
    .\read_data[10] (read_data[10]),
    .\read_data[11] (read_data[11]),
    .\read_data[12] (read_data[12]),
    .\read_data[13] (read_data[13]),
    .\read_data[14] (read_data[14]),
    .\read_data[15] (read_data[15]),
    .\read_data[16] (read_data[16]),
    .\read_data[17] (read_data[17]),
    .\read_data[18] (read_data[18]),
    .\read_data[19] (read_data[19]),
    .\read_data[20] (read_data[20]),
    .\read_data[21] (read_data[21]),
    .\read_data[22] (read_data[22]),
    .\read_data[23] (read_data[23]),
    .\read_data[24] (read_data[24]),
    .\read_data[25] (read_data[25]),
    .\read_data[26] (read_data[26]),
    .\read_data[27] (read_data[27]),
    .\read_data[28] (read_data[28]),
    .\read_data[29] (read_data[29]),
    .\read_data[30] (read_data[30]),
    .\read_data[31] (read_data[31]),
    .\write_meta[tile_id] (write_meta.tile_id),
    .\write_meta[dst_addr] (write_meta.dst_addr),
    .\completed[tile_id] (completed.tile_id),
    .\completed[dst_addr] (completed.dst_addr),
    .*
  );
`else
  sparse_tensor_core_top dut (.*);
`endif

  int a[TILES][8][8], b[TILES][8][8];
  logic [7:0] keep_a[TILES][8], keep_b[TILES][8];
  logic [3:0] masks[TILES][2][8];
  logic [7:0] image_bytes[TILES][160];
  tensor_core_pkg::tc_matrix_t expected[TILES];
  mlu_pkg::io_command_t commands[TILES];
  logic [31:0] rng = 32'h51a7c0de;
  int mode = 0, cycle = 0, submitted = 0, requests = 0, beats = 0, dones = 0;
  int active_tile = 0, active_beat = 0, active_beats = 0, last_done_cycle = -1;
  int present_a = 0, present_b = 0, nonzero_a = 0, nonzero_b = 0;
  bit memory_active = 0, passed = 0, previous_last = 0;
  msu_pkg::io_meta_t previous_meta = '0;
  integer trace_fd;

  function automatic logic [31:0] random_word();
    rng = rng ^ (rng << 13);
    rng = rng ^ (rng >> 17);
    rng = rng ^ (rng << 5);
    return rng;
  endfunction
  function automatic logic [3:0] mask_at(input int n);
    case (n%6)
      0: return 4'h3; 1: return 4'h5; 2: return 4'h6;
      3: return 4'h9; 4: return 4'ha; default: return 4'hc;
    endcase
  endfunction
  task automatic check(input bit condition, input string message);
    if (!condition) $fatal(1,"POWER WORKLOAD FAIL mode=%0d cycle=%0d: %s",mode,cycle,message);
  endtask
  task automatic prepare;
    int off, rank_a, rank_b, sum;
    logic [31:0] sample;
    for (int t=0; t<TILES; t++) begin
      commands[t] = '0;
      commands[t].mode = mlu_pkg::io_mode_t'(mode);
      commands[t].src_addr = 64'h0000_0001_0000_0000 + 64'(t)*256;
      commands[t].meta.dst_addr = 64'h0000_0002_0000_0000 + 64'(t)*512;
      commands[t].meta.tile_id = 32'h8000_0000 + 32'(t);
      for (int n=0; n<160; n++) image_bytes[t][n] = 0;
      for (int g=0; g<2; g++)
        for (int j=0; j<8; j++) begin
          sample = random_word();
          masks[t][g][j] = mask_at(int'(sample % 6));
        end
      for (int k=0; k<8; k++) begin
        sample = random_word(); keep_a[t][k] = mode == 0 ? 8'hff : sample[7:0];
        sample = random_word(); keep_b[t][k] = mode == 0 ? 8'hff : sample[7:0];
        if (mode == 1)
          for (int j=0; j<8; j++) keep_b[t][k][j] = masks[t][k/4][j][k%4];
        if ($test$plusargs("BOUNDS")) begin
          keep_a[t][k]=8'hff;
          if (mode != 1) keep_b[t][k]=8'hff;
        end
        for (int i=0; i<8; i++) begin
          sample = random_word(); a[t][i][k] = keep_a[t][k][i] ? int'($signed(sample[7:0])) : 0;
          sample = random_word(); b[t][k][i] = keep_b[t][k][i] ? int'($signed(sample[7:0])) : 0;
          if ($test$plusargs("BOUNDS")) begin
            a[t][i][k] = -128;
            case (t%4)
              0: b[t][k][i] = keep_b[t][k][i] ? -128 : 0;
              1: b[t][k][i] = keep_b[t][k][i] ? 127 : 0;
              2: b[t][k][i] = keep_b[t][k][i] ? (k<4 ? -128 : 127) : 0;
              3: begin
                a[t][i][k] = i%2 ? -128 : 127;
                b[t][k][i] = keep_b[t][k][i] ? (i%2 ? 127 : -128) : 0;
              end
            endcase
          end
          present_a += int'(keep_a[t][k][i]); present_b += int'(keep_b[t][k][i]);
          if (a[t][i][k] != 0) nonzero_a++;
          if (b[t][k][i] != 0) nonzero_b++;
        end
      end
      for (int i=0; i<8; i++)
        for (int j=0; j<8; j++) begin
          sum = 0;
          for (int k=0; k<8; k++) sum += a[t][i][k]*b[t][k][j];
          expected[t][i][j] = 32'(sum);
        end
      // Independent encoder of the documented dense/hybrid/dual memory layout.
      for (int k=0; k<8; k++) begin
        rank_a = 0; rank_b = 0;
        if (mode == 0) begin
          for (int i=0; i<8; i++) begin
            image_bytes[t][16*k+i] = 8'(a[t][i][k]);
            image_bytes[t][16*k+8+i] = 8'(b[t][k][i]);
          end
        end else begin
          off = mode == 1 ? 9*k : 18*k;
          image_bytes[t][off] = keep_a[t][k];
          if (mode == 2) image_bytes[t][off+9] = keep_b[t][k];
          for (int i=0; i<8; i++) begin
            if (keep_a[t][k][i]) begin
              image_bytes[t][off+1+rank_a] = 8'(a[t][i][k]); rank_a++;
            end
            if (mode == 2 && keep_b[t][k][i]) begin
              image_bytes[t][off+10+rank_b] = 8'(b[t][k][i]); rank_b++;
            end
          end
        end
      end
      if (mode == 1)
        for (int g=0; g<2; g++)
          for (int j=0; j<8; j++) begin
            off = 72+24*g+3*j;
            image_bytes[t][off] = {4'd0,masks[t][g][j]}; rank_b = 0;
            for (int p=0; p<4; p++)
              if (masks[t][g][j][p]) begin
                image_bytes[t][off+1+rank_b] = 8'(b[t][4*g+p][j]); rank_b++;
              end
          end
    end
  endtask

  task automatic tick;
    bit cf, rf, df, wf;
    int t, row;
    @(negedge clk);
    if (!command_valid && submitted < TILES) begin
      command = commands[submitted]; command_valid = 1;
    end
    read_request_ready = 1; write_ready = 1;
    if (!read_data_valid && memory_active) begin
      for (int n=0; n<32; n++) read_data[n] = image_bytes[active_tile][32*active_beat+n];
      read_last = active_beat == active_beats-1; read_data_valid = 1;
    end
    @(posedge clk);
    check(mlu_status === mlu_pkg::IO_OK && bridge_status === du_tc_bridge_pkg::IO_OK &&
          tc_status === tensor_core_pkg::TC_OK && msu_status === msu_pkg::IO_OK,"status");
    cf = command_valid && command_ready; rf = read_request_valid && read_request_ready;
    df = read_data_valid && read_data_ready; wf = write_valid && write_ready;
    check(tile_done === previous_last, "completion timing");
    if (previous_last) check(completed === previous_meta,"completion metadata");
    $fdisplay(trace_fd,"%0d %h %b %h %b%b %h %b %b %b%b%b%b %h %h %h %b",cycle,
      command,command_valid,read_data,read_data_valid,read_last,read_request_ready,
      write_ready,rst_n,cf,rf,df,wf,read_addr,write_addr,write_data,write_last);
    if (cf) submitted++;
    if (rf) begin
      check(!memory_active && requests < submitted,"single read burst");
      check(read_addr === commands[requests].src_addr,"read order/address");
      check(read_beats == (mode == 2 ? 5 : 4),"read length");
      active_tile = requests; active_beat = 0; active_beats = int'(read_beats);
      memory_active = 1; requests++;
    end
    if (df) begin
      check(memory_active && !rf,"response follows request"); active_beat++;
      if (read_last) memory_active = 0;
    end
    previous_last = wf && write_last; previous_meta = write_meta;
    if (wf) begin
      t = beats/8; row = beats%8;
      check(t < TILES,"extra result");
      check(write_meta === commands[t].meta,"write order/metadata");
      check(write_addr === commands[t].meta.dst_addr + 64'(32*row),"write address");
      check(write_last === (row == 7),"last beat");
      for (int j=0; j<8; j++)
        check(write_data[32*j+:32] === expected[t][row][j],"independent signed GEMM");
      beats++;
      if (write_last) begin
        if (last_done_cycle >= 0) check(cycle-last_done_cycle == 8,"sustained II=8");
        last_done_cycle = cycle; dones++;
      end
    end
    // Inputs remain stable through the DUT sampling edge and routed clock delay.
    #3;
    if (cf) command_valid = 0;
    if (df) read_data_valid = 0;
    cycle++; check(cycle < 4000,"watchdog");
  endtask

  initial begin
    if ($test$plusargs("HYBRID")) mode = 1;
    else if ($test$plusargs("DUAL")) mode = 2;
    else mode = 0;
    check(mode >= 0 && mode <= 2,"legal workload mode"); prepare();
    trace_fd = $fopen($sformatf("transactions_%0d.trace",mode),"w"); check(trace_fd != 0,"trace file");
    // Let the vendor's 100 ns global startup reset finish before external reset.
    #200; @(negedge clk); rst_n = 1;
    while (dones < TILES) tick();
    repeat (16) tick();
    check(submitted == TILES && requests == TILES && beats == TILES*8,"accounting");
    check(!memory_active && !write_valid,"drained");
    $fclose(trace_fd); passed = 1;
    $display("POWER WORKLOAD PASS mode=%0d seed=51a7c0de tiles=%0d cycles=%0d beats=%0d present_a=%0d present_b=%0d nonzero_a=%0d nonzero_b=%0d II=8",mode,TILES,cycle,beats,present_a,present_b,nonzero_a,nonzero_b);
    $finish;
  end
  initial begin #50000; $fatal(1,"Power workload timeout"); end
endmodule
