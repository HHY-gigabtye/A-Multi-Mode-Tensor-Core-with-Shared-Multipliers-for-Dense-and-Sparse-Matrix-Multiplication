`timescale 1ns/1ps

// Independently feed the same tiles to both TC interfaces at their own ready
// rates. Always-ready sink, no memory traffic, and no gaps from the producer.
module tb_compare;
  import tensor_core_pkg::*;
  logic clk=0, rst_n=1;
  logic valid[2], ready[2], out_valid[2];
  tc_matrix_t matrix_out[2];
  tc_status_t status[2];
  tc_tick_info_t info[2];
  tc_input_packet_t legacy;
  tc_sparse_payload_t unified;
  bit passed=0;
  tensor_core original(.clk(clk),.rst_n(rst_n),.in_valid(valid[0]),.in_packet(legacy),
      .in_ready(ready[0]),.input_ready(),.result_ready(1'b1),.result_valid(out_valid[0]),
      .result(matrix_out[0]),.busy(),.status(status[0]),.tick_info(info[0]));
  outer_product_core candidate(.clk(clk),.rst_n(rst_n),.in_valid(valid[1]),.in_packet(unified),
      .in_ready(ready[1]),.result_ready(1'b1),.result_valid(out_valid[1]),
      .result(matrix_out[1]),.busy(),.status(status[1]),.tick_info(info[1]));

  localparam int TILES=24;
  function automatic bit indexed(input int pattern, tile);
    return (pattern == 1) || (pattern == 2 && tile%2 == 1);
  endfunction
  function automatic tc_input_packet_t stimulus(input bit sparse_format, input int tile);
    tc_input_packet_t p;
    p='0; p.is_sparse=sparse_format;
    if (sparse_format) begin
      p.payload.sparse.a.count=8; p.payload.sparse.b.count=8;
    end
    for (int n=0; n<8; n++) begin
      if (sparse_format) begin
        p.payload.sparse.a.index[n]=3'(n); p.payload.sparse.b.index[n]=3'(n);
        p.payload.sparse.a.value[n]=8'(tile-n); p.payload.sparse.b.value[n]=8'(n-4);
      end else begin
        p.payload.dense.dense_a[n]=8'(tile-n); p.payload.dense.dense_b[n]=8'(n-4);
      end
    end
    return p;
  endfunction

  task automatic compare_stream(input int pattern);
    int sent[2], done[2], first_cycle[2], previous[2], final_cycle[2], k7[2][TILES];
    int pubs[2], min_ii[2], max_ii[2], t, gap, delta;
    tc_input_packet_t packed_input;
    for (int n=0; n<2; n++) begin
      sent[n]=0; done[n]=0; pubs[n]=0; min_ii[n]=1000; max_ii[n]=0; valid[n]=0;
    end
    rst_n=0; #1; clk=1; #1; clk=0; rst_n=1;
    for (int cycle=0; done[0]<TILES || done[1]<TILES; cycle++) begin
      if (cycle > 1000) $fatal(1,"no progress");
      legacy=stimulus(indexed(pattern,sent[0]/8),sent[0]/8);
      packed_input=stimulus(1,sent[1]/8); unified=packed_input.payload.sparse;
      #1;
      for (int n=0; n<2; n++) valid[n]=(sent[n]<8*TILES) && ready[n];
      #1;
      for (int n=0; n<2; n++) begin
        if (status[n] !== TC_OK) $fatal(1,"contract");
        if (out_valid[n]) begin
          for (int i=0;i<8;i++) for (int j=0;j<8;j++)
            if ($signed(matrix_out[n][i][j]) !== 8*(done[n]-i)*(j-4))
              $fatal(1,"matrix/order");
          done[n]++; final_cycle[n]=cycle;
        end
        if (valid[n]) begin
          t=sent[n]/8;
          if (sent[n]%8 == 0) begin
            if (t == 0) first_cycle[n]=cycle;
            else begin
              gap=cycle-previous[n];
              if (gap<min_ii[n]) min_ii[n]=gap;
              if (gap>max_ii[n]) max_ii[n]=gap;
            end
            previous[n]=cycle;
          end
          if (sent[n]%8 == 7) k7[n][t]=cycle;
          sent[n]++;
        end
      end
      clk=1; #1;
      for (int n=0; n<2; n++) if (info[n].result_produced) begin
        delta=cycle-k7[n][pubs[n]];
        if (delta != ((n == 0 && !indexed(pattern,pubs[n])) ? 15 : 3))
          $fatal(1,"publication timing");
        pubs[n]++;
      end
      clk=0; #1;
    end
    for (int n=0;n<2;n++) begin
      if (pubs[n]!=TILES) $fatal(1,"publication count");
      $display("TC BENCH pattern=%0d core=%0d tiles=%0d cycles=%0d min_II=%0d max_II=%0d",
               pattern,n,TILES,final_cycle[n]-first_cycle[n]+1,min_ii[n],max_ii[n]);
    end
  endtask
  initial begin
    for (int pattern=0;pattern<3;pattern++) compare_stream(pattern);
    passed=1; $display("TC COMPARISON PASS"); $finish;
  end
endmodule
