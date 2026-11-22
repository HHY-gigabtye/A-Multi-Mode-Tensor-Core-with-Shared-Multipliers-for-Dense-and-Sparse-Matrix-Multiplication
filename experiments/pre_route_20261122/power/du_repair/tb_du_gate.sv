`timescale 1ns/1ps
module tb_du_gate;
  import du_tia_pkg::*;
  logic clk=0, rst_n=0, in_valid=0, out_valid;
  always #5 clk=~clk;
  du_tia_input_t input_bits='0;
  du_tia_output_t output_bits;
  du_gate dut(.*);
  du_tia_output_t expected[0:3];
  bit valid_pipe[0:3];
  int sent=0, checked=0, resets=0;
  bit passed=0;
  logic [31:0] rng=32'h9412c731;
  function automatic logic [31:0] randword();
    rng=rng^(rng<<13); rng=rng^(rng>>17); rng=rng^(rng<<5);
    return rng;
  endfunction
  function automatic logic [3:0] mask(input int n);
    case(n%6)
      0:return 4'h3; 1:return 4'h5; 2:return 4'h6;
      3:return 4'h9; 4:return 4'ha; default:return 4'hc;
    endcase
  endfunction
  // Independent ascending-coordinate reference, no DUT decode helper calls.
  function automatic du_tia_output_t golden(input du_tia_input_t p);
    du_tia_output_t e;
    int ac,bc,rank;
    bit ahit,bhit;
    e='0; ac=0; bc=0;
    if(p.mode==MODE_DENSE_DENSE) begin
      e.payload.dense.dense_a=p.payload.dense.dense_a;
      e.payload.dense.dense_b=p.payload.dense.dense_b;
    end else begin
      e.is_sparse=1;
      for(int j=0;j<8;j++) begin
        ahit=(p.mode==MODE_UNSTRUCTURED_2TO4)?p.payload.hybrid.a_bitmap[j]:p.payload.dual.a_bitmap[j];
        bhit=(p.mode==MODE_UNSTRUCTURED_2TO4)?p.payload.hybrid.b_2to4_mask[j][p.k_position]:p.payload.dual.b_bitmap[j];
        if(ahit) begin
          e.payload.sparse.a.index[ac]=3'(j);
          e.payload.sparse.a.value[ac]=(p.mode==MODE_UNSTRUCTURED_2TO4)?p.payload.hybrid.a_packed[ac]:p.payload.dual.a_packed[ac];
          ac++;
        end
        if(bhit) begin
          e.payload.sparse.b.index[bc]=3'(j);
          if(p.mode==MODE_UNSTRUCTURED_2TO4) begin
            rank=0;
            for(int k=0;k<p.k_position;k++) rank+=int'(p.payload.hybrid.b_2to4_mask[j][k]);
            e.payload.sparse.b.value[bc]=p.payload.hybrid.b_2to4_packed[j][rank];
          end else e.payload.sparse.b.value[bc]=p.payload.dual.b_packed[bc];
          bc++;
        end
      end
      e.payload.sparse.a.count=4'(ac);
      e.payload.sparse.b.count=4'(bc);
    end
    return e;
  endfunction
  always @(posedge clk) begin
    if(!rst_n) begin
      for(int i=0;i<4;i++) begin valid_pipe[i]=0; expected[i]='0; end
    end else begin
      for(int i=3;i>0;i--) begin valid_pipe[i]=valid_pipe[i-1]; expected[i]=expected[i-1]; end
      valid_pipe[0]=in_valid;
      expected[0]=in_valid?golden(input_bits):'0;
      if(in_valid) sent++;
    end
    #2;
    if(out_valid!==valid_pipe[3]) $fatal(1,"DU VALID FAIL sent=%0d",sent);
    if(output_bits!==expected[3])
      $fatal(1,"DU PAYLOAD FAIL sent=%0d checked=%0d actual=%h expected=%h",sent,checked,output_bits,expected[3]);
    if(out_valid) checked++;
  end
  task automatic offer(input du_tia_input_t p,input bit v);
    @(negedge clk); input_bits=p; in_valid=v;
  endtask
  initial begin : stimulus
    du_tia_input_t p;
    logic [31:0] sample;
    #210; @(negedge clk); rst_n=1;
    // First reproduce the failing A bitmap with unambiguous packed values.
    p='0; p.mode=MODE_UNSTRUCTURED_UNSTRUCTURED;
    p.payload.dual.a_bitmap=8'hf2; p.payload.dual.b_bitmap=8'ha8;
    p.payload.dual.a_packed=64'h0807060504030201;
    p.payload.dual.b_packed=64'h1817161514131211;
    offer(p,1);
    repeat(5) offer('0,0);
    // Exhaust all A/B bitmap pairs; values include zero, extrema, and padding.
    for(int a=0;a<256;a++) for(int b=0;b<256;b++) begin
      p='0; p.mode=MODE_UNSTRUCTURED_UNSTRUCTURED;
      p.payload.dual.a_bitmap=8'(a); p.payload.dual.b_bitmap=8'(b);
      p.payload.dual.a_packed=64'h817f00ff0180fe42;
      p.payload.dual.b_packed=64'h80ff7f0001aa5581;
      offer(p,1);
    end
    // All A bitmaps, positions, and legal masks, plus independently mixed masks.
    for(int a=0;a<256;a++) for(int k=0;k<4;k++) for(int m=0;m<6;m++) begin
      p='0; p.mode=MODE_UNSTRUCTURED_2TO4; p.k_position=2'(k);
      p.payload.hybrid.a_bitmap=8'(a);
      p.payload.hybrid.a_packed=64'h807f00ff0181fe42;
      for(int j=0;j<8;j++) begin
        p.payload.hybrid.b_2to4_mask[j]=mask(m+j);
        p.payload.hybrid.b_2to4_packed[j]={8'(j+64),8'(j)};
      end
      offer(p,1);
    end
    for(int t=0;t<4096;t++) begin
      p='0;
      case(t%3)
        0: begin
          p.mode=MODE_DENSE_DENSE;
          for(int j=0;j<8;j++) begin
            p.payload.dense.dense_a[j]=8'(randword());
            p.payload.dense.dense_b[j]=8'(randword());
          end
        end
        1: begin
          p.mode=MODE_UNSTRUCTURED_2TO4; p.k_position=2'(randword());
          p.payload.hybrid.a_bitmap=8'(randword());
          for(int j=0;j<8;j++) begin
            p.payload.hybrid.a_packed[j]=8'(randword());
            p.payload.hybrid.b_2to4_mask[j]=mask(int'(randword()>>1));
            p.payload.hybrid.b_2to4_packed[j]=16'(randword());
          end
        end
        2: begin
          p.mode=MODE_UNSTRUCTURED_UNSTRUCTURED;
          p.payload.dual.a_bitmap=8'(randword()); p.payload.dual.b_bitmap=8'(randword());
          for(int j=0;j<8;j++) begin
            p.payload.dual.a_packed[j]=8'(randword()); p.payload.dual.b_packed[j]=8'(randword());
          end
        end
      endcase
      sample=randword(); offer(p,sample[0]||sample[1]);
      if(t%257==0) begin
        @(negedge clk); rst_n=0; in_valid=0; resets++;
        @(negedge clk); rst_n=1;
      end
    end
    repeat(6) offer('0,0);
    passed=1;
    $display("DU GATE PASS sent=%0d checked=%0d resets=%0d bitmap_pairs=65536 hybrid_cases=6144",sent,checked,resets);
    $finish;
  end
endmodule
