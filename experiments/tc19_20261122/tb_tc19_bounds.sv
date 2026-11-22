`timescale 1ns/1ps
// Additional unit test: all 256x256 signed operand pairs, each accumulated
// eight times. Independent integer arithmetic checks every INT32 output.
module tb_tc19_bounds;
  import tensor_core_pkg::*;
  logic clk=0, rst_n=0, in_valid=0, result_ready=1;
  tc_sparse_payload_t in_packet='0;
  logic ref_ready, dut_ready, ref_valid, dut_valid, ref_busy, dut_busy;
  tc_matrix_t ref_result, dut_result;
  tc_status_t ref_status, dut_status;
  tc_tick_info_t ref_info, dut_info;
  bit passed=0;
  outer_product_core_baseline reference_core (
    .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .result_ready(result_ready),
    .in_packet(in_packet), .in_ready(ref_ready), .result_valid(ref_valid),
    .busy(ref_busy), .result(ref_result), .status(ref_status), .tick_info(ref_info));
  outer_product_core candidate_core (
    .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .result_ready(result_ready),
    .in_packet(in_packet), .in_ready(dut_ready), .result_valid(dut_valid),
    .busy(dut_busy), .result(dut_result), .status(dut_status), .tick_info(dut_info));
  tc_matrix_t expected_queue[$], tile_expected, retired;
  int due_queue[$];
  int edge_number=0, input_k=0, last_start=-1, completed=0, published=0;
  int max_hits=0, min_hits=0, intervals=0;

  task automatic compare;
    if ({dut_ready,dut_valid,dut_busy,dut_status,dut_result,dut_info} !==
        {ref_ready,ref_valid,ref_busy,ref_status,ref_result,ref_info} ||
        candidate_core.acc !== reference_core.acc ||
        candidate_core.tail !== reference_core.tail)
      $fatal(1,"19-bit baseline mismatch at edge %0d",edge_number);
  endtask

  task automatic step;
    bit publication;
    #1; compare(); publication=0;
    if (rst_n) begin
      if (ref_status != TC_OK) $fatal(1,"Unexpected rejected legal edge");
      if (due_queue.size() && due_queue[0] == edge_number) begin
        publication=1; void'(due_queue.pop_front());
      end
      if (ref_valid && result_ready) begin
        if (!expected_queue.size()) $fatal(1,"Unexpected output");
        retired=expected_queue.pop_front();
        if (dut_result !== retired) $fatal(1,"INT32 GEMM mismatch");
        for (int i=0;i<8;i++) for (int j=0;j<8;j++) begin
          if ($signed(dut_result[i][j]) == 131072) max_hits++;
          if ($signed(dut_result[i][j]) == -130048) min_hits++;
        end
        completed++;
      end
      if (in_valid) begin
        if (input_k == 0) begin
          if (last_start >= 0) begin
            if (edge_number-last_start != 8) $fatal(1,"Unstalled II changed");
            intervals++;
          end
          last_start=edge_number;
        end
        if (input_k == 7) begin
          expected_queue.push_back(tile_expected);
          due_queue.push_back(edge_number+3);
        end
        input_k=(input_k+1)%8;
      end
    end
    clk=1; #1; compare();
    if (dut_info.result_produced !== publication) $fatal(1,"k=7+3 latency changed");
    if (publication) published++;
    clk=0; #1; edge_number++;
  endtask

  initial begin
    int av,bv;
    step(); rst_n=1;
    for (int ab=0;ab<32;ab++) for (int bb=0;bb<32;bb++) begin
      in_packet='0;
      in_packet.a.count=8; in_packet.b.count=8;
      for (int i=0;i<8;i++) begin
        in_packet.a.index[i]=3'(i); in_packet.b.index[i]=3'(i);
        in_packet.a.value[i]=8'(ab*8+i-128);
        in_packet.b.value[i]=8'(bb*8+i-128);
        for (int j=0;j<8;j++) begin
          av=ab*8+i-128; bv=bb*8+j-128;
          tile_expected[i][j]=32'(8*av*bv);
        end
      end
      in_valid=1;
      repeat(8) step();
    end
    in_valid=0; repeat(16) step();
    if (completed!=1024 || published!=1024 || intervals!=1023 ||
        max_hits!=1 || min_hits!=2 || expected_queue.size()!=0 ||
        due_queue.size()!=0 || dut_busy)
      $fatal(1,"Incomplete bound/throughput coverage");
    $display("TC19 BOUNDS PASS tiles=%0d operand_pairs=65536 max=%0d min=%0d II=8 intervals=%0d last_k_to_publish=3 max_hits=%0d min_hits=%0d",completed,131072,-130048,intervals,max_hits,min_hits);
    passed=1; $finish;
  end
endmodule
