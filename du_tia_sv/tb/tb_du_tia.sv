`timescale 1ns/1ps

module tb_du_tia;
  import du_tia_pkg::*;

  localparam time CLOCK_PERIOD = 10ns;
  localparam int unsigned RANDOM_PACKETS_PER_MODE = 1000;

  typedef logic [KEEP_PER_GROUP-1:0][DATA_W-1:0] packed_group_t;

  logic           clk;
  logic           rst_n;
  logic           in_valid;
  du_tia_input_t  in_packet;
  logic           out_valid;
  du_tia_output_t out_packet;

  du_tia_output_t expected_packet_queue[$];
  int unsigned    expected_id_queue[$];
  compiler_mode_e expected_mode_queue[$];
  du_tia_output_t monitor_expected;
  logic [31:0]    rng_state;
  int unsigned    sent_count;
  int unsigned    received_count;

  du_tia dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .in_valid   (in_valid),
    .in_packet  (in_packet),
    .out_valid  (out_valid),
    .out_packet (out_packet)
  );

  initial clk = 1'b0;
  always #(CLOCK_PERIOD/2) clk = ~clk;

  function automatic int unsigned tb_popcount8(input bitmap_t value);
    int unsigned result;
    result = 0;
    for (int unsigned bit_index = 0;
         bit_index < VECTOR_LANES; bit_index++) begin
      result += value[bit_index] ? 1 : 0;
    end
    return result;
  endfunction

  function automatic int unsigned tb_rank_before(
      input logic [GROUP_SIZE-1:0] mask,
      input group_position_t position
  );
    int unsigned result;
    result = 0;
    for (int unsigned bit_index = 0;
         bit_index < GROUP_SIZE; bit_index++) begin
      if ((bit_index < position) && mask[bit_index]) begin
        result++;
      end
    end
    return result;
  endfunction

  /* Independent model: it does not call the RTL's TIA helper functions. */
  function automatic du_tia_output_t tb_golden(
      input du_tia_input_t source
  );
    du_tia_output_t result;
    int unsigned a_count;
    int unsigned b_count;
    int unsigned source_rank;

    result  = '0;
    a_count = 0;
    b_count = 0;

    case (source.mode)
      MODE_DENSE_DENSE: begin
        result.is_sparse = 1'b0;
        result.payload.dense.dense_a =
            source.payload.dense.dense_a;
        result.payload.dense.dense_b =
            source.payload.dense.dense_b;
      end

      MODE_UNSTRUCTURED_2TO4: begin
        result.is_sparse = 1'b1;
        for (int unsigned logical_index = 0;
             logical_index < VECTOR_LANES; logical_index++) begin
          if (source.payload.hybrid.a_bitmap[logical_index]) begin
            result.payload.sparse.a.value[a_count] =
                source.payload.hybrid.a_packed[a_count];
            result.payload.sparse.a.index[a_count] =
                INDEX_W'(logical_index);
            a_count++;
          end
        end

        for (int unsigned column = 0; column < N_DIM; column++) begin
          if (source.payload.hybrid.b_2to4_mask[column]
                                                    [source.k_position]) begin
            source_rank = tb_rank_before(
                source.payload.hybrid.b_2to4_mask[column],
                source.k_position);
            result.payload.sparse.b.value[b_count] =
                source.payload.hybrid.b_2to4_packed[column][source_rank];
            result.payload.sparse.b.index[b_count] = INDEX_W'(column);
            b_count++;
          end
        end

        result.payload.sparse.a.count = COUNT_W'(a_count);
        result.payload.sparse.b.count = COUNT_W'(b_count);
      end

      MODE_UNSTRUCTURED_UNSTRUCTURED: begin
        result.is_sparse = 1'b1;
        for (int unsigned logical_index = 0;
             logical_index < VECTOR_LANES; logical_index++) begin
          if (source.payload.dual.a_bitmap[logical_index]) begin
            result.payload.sparse.a.value[a_count] =
                source.payload.dual.a_packed[a_count];
            result.payload.sparse.a.index[a_count] =
                INDEX_W'(logical_index);
            a_count++;
          end
          if (source.payload.dual.b_bitmap[logical_index]) begin
            result.payload.sparse.b.value[b_count] =
                source.payload.dual.b_packed[b_count];
            result.payload.sparse.b.index[b_count] =
                INDEX_W'(logical_index);
            b_count++;
          end
        end

        result.payload.sparse.a.count = COUNT_W'(a_count);
        result.payload.sparse.b.count = COUNT_W'(b_count);
      end

      default: result = 'x;
    endcase

    return result;
  endfunction

  function automatic data_t deterministic_nonzero(
      input int unsigned seed_value
  );
    int signed value;
    value = int'((seed_value * 5 + 3) % 15) - 7;
    if (value == 0) begin
      value = 7;
    end
    return data_t'(value);
  endfunction

  function automatic lane_data_t deterministic_packed(
      input bitmap_t bitmap,
      input int unsigned seed_value,
      input logic poison_padding
  );
    lane_data_t result;
    int unsigned rank;
    result = '0;
    rank   = 0;
    for (int unsigned logical_index = 0;
         logical_index < VECTOR_LANES; logical_index++) begin
      if (bitmap[logical_index]) begin
        result[rank] = deterministic_nonzero(
            seed_value + 17 * logical_index);
        rank++;
      end
    end
    if (poison_padding && (rank < VECTOR_LANES)) begin
      result[rank] = deterministic_nonzero(seed_value + 333);
    end
    return result;
  endfunction

  function automatic logic [GROUP_SIZE-1:0] valid_2to4_mask(
      input int unsigned selection
  );
    case (selection % 6)
      0: return 4'b0011;
      1: return 4'b0101;
      2: return 4'b0110;
      3: return 4'b1001;
      4: return 4'b1010;
      default: return 4'b1100;
    endcase
  endfunction

  function automatic packed_group_t deterministic_group(
      input logic [GROUP_SIZE-1:0] mask,
      input int unsigned seed_value
  );
    packed_group_t result;
    int unsigned rank;
    result = '0;
    rank   = 0;
    for (int unsigned position = 0;
         position < GROUP_SIZE; position++) begin
      if (mask[position]) begin
        result[rank] = deterministic_nonzero(
            seed_value + 13 * position);
        rank++;
      end
    end
    return result;
  endfunction

  function automatic bitmap_t directed_a_bitmap(input int unsigned slot);
    case (slot % 4)
      0: return 8'hA5;
      1: return 8'h00;
      2: return 8'hFF;
      default: return 8'h18;
    endcase
  endfunction

  function automatic bitmap_t directed_b_bitmap(input int unsigned slot);
    case (slot % 4)
      0: return 8'h3C;
      1: return 8'hFF;
      2: return 8'h00;
      default: return 8'h81;
    endcase
  endfunction

  function automatic du_tia_input_t make_directed_packet(
      input compiler_mode_e mode,
      input int unsigned test_id
  );
    du_tia_input_t result;
    int unsigned slot;
    logic [GROUP_SIZE-1:0] mask;

    result            = '0;
    slot              = test_id % 4;
    result.mode       = mode;
    result.k_position = GROUP_POS_W'(test_id % GROUP_SIZE);

    if (mode == MODE_DENSE_DENSE) begin
      for (int unsigned lane_index = 0;
           lane_index < VECTOR_LANES; lane_index++) begin
        result.payload.dense.dense_a[lane_index] = data_t'(
            int'(lane_index) - int'(slot) - 3);
        result.payload.dense.dense_b[lane_index] = data_t'(
            int'(2 * lane_index + slot) - 6);
      end
    end
    else if (mode == MODE_UNSTRUCTURED_2TO4) begin
      result.payload.hybrid.a_bitmap = directed_a_bitmap(slot);
      result.payload.hybrid.a_packed = deterministic_packed(
          result.payload.hybrid.a_bitmap, 30 + 19 * slot, 1'b0);

      for (int unsigned column = 0; column < N_DIM; column++) begin
        if ((slot == 0) || (slot == 1)) begin
          mask = 4'b0101;
        end
        else if (slot == 2) begin
          mask = ((column % 2) == 0) ? 4'b0110 : 4'b1001;
        end
        else begin
          mask = valid_2to4_mask(column);
        end
        result.payload.hybrid.b_2to4_mask[column] = mask;
        result.payload.hybrid.b_2to4_packed[column] =
            deterministic_group(mask, 120 + 23 * slot + 7 * column);
      end
    end
    else begin
      result.payload.dual.a_bitmap = directed_a_bitmap(slot);
      result.payload.dual.a_packed = deterministic_packed(
          result.payload.dual.a_bitmap, 30 + 19 * slot, 1'b0);
      result.payload.dual.b_bitmap = directed_b_bitmap(slot);
      result.payload.dual.b_packed = deterministic_packed(
          result.payload.dual.b_bitmap, 330 + 29 * slot, 1'b0);
    end

    return result;
  endfunction

  function automatic logic [31:0] next_random();
    logic [31:0] x;
    x = rng_state;
    if (x == 0) begin
      x = 32'h6D2B79F5;
    end
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    rng_state = x;
    return x;
  endfunction

  function automatic data_t random_nonzero();
    int signed value;
    value = int'(next_random() % 15) - 7;
    if (value == 0) begin
      value = 7;
    end
    return data_t'(value);
  endfunction

  function automatic lane_data_t random_packed(input bitmap_t bitmap);
    lane_data_t result;
    int unsigned count;
    result = '0;
    count  = tb_popcount8(bitmap);
    for (int unsigned rank = 0; rank < VECTOR_LANES; rank++) begin
      if (rank < count) begin
        result[rank] = random_nonzero();
      end
      else if ((next_random() % 4) == 0) begin
        /* Nonzero don't-care padding checks that count gates forwarding. */
        result[rank] = random_nonzero();
      end
    end
    return result;
  endfunction

  function automatic packed_group_t random_group();
    packed_group_t result;
    result[0] = random_nonzero();
    result[1] = random_nonzero();
    return result;
  endfunction

  task automatic make_random_packet(
      input compiler_mode_e mode,
      input int unsigned test_id,
      output du_tia_input_t result
  );
    logic [31:0] random_word;
    result            = '0;
    result.mode       = mode;
    result.k_position = GROUP_POS_W'(test_id % GROUP_SIZE);

    if (mode == MODE_DENSE_DENSE) begin
      for (int unsigned lane_index = 0;
           lane_index < VECTOR_LANES; lane_index++) begin
        random_word = next_random();
        result.payload.dense.dense_a[lane_index] = random_word[7:0];
        random_word = next_random();
        result.payload.dense.dense_b[lane_index] = random_word[7:0];
      end
    end
    else if (mode == MODE_UNSTRUCTURED_2TO4) begin
      random_word = next_random();
      result.payload.hybrid.a_bitmap = random_word[7:0];
      result.payload.hybrid.a_packed =
          random_packed(result.payload.hybrid.a_bitmap);
      for (int unsigned column = 0; column < N_DIM; column++) begin
        result.payload.hybrid.b_2to4_mask[column] =
            valid_2to4_mask(next_random());
        result.payload.hybrid.b_2to4_packed[column] = random_group();
      end
    end
    else begin
      random_word = next_random();
      result.payload.dual.a_bitmap = random_word[7:0];
      random_word = next_random();
      result.payload.dual.b_bitmap = random_word[7:0];
      result.payload.dual.a_packed =
          random_packed(result.payload.dual.a_bitmap);
      result.payload.dual.b_packed =
          random_packed(result.payload.dual.b_bitmap);
    end
  endtask

  task automatic issue_packet(
      input du_tia_input_t packet,
      input int unsigned test_id
  );
    @(negedge clk);
    in_valid  = 1'b1;
    in_packet = packet;
    expected_packet_queue.push_back(tb_golden(packet));
    expected_id_queue.push_back(test_id);
    expected_mode_queue.push_back(packet.mode);
    sent_count++;
  endtask

  task automatic issue_bubble();
    @(negedge clk);
    in_valid  = 1'b0;
    in_packet = '0;
  endtask

  always @(posedge clk) begin
    int unsigned test_id;
    compiler_mode_e source_mode;
    #1ns;
    if (rst_n && out_valid) begin
      if (expected_packet_queue.size() == 0) begin
        $fatal(1, "Scoreboard received an unexpected output");
      end

      monitor_expected = expected_packet_queue.pop_front();
      test_id           = expected_id_queue.pop_front();
      source_mode       = expected_mode_queue.pop_front();

      if (out_packet !== monitor_expected) begin
        $display("OUTPUT MISMATCH: local test_id=%0d source_mode=%0d",
                 test_id, source_mode);
        $display("actual packet: %h", out_packet);
        $display("expect packet: %h", monitor_expected);
        if (monitor_expected.is_sparse) begin
          $display("actual A count/value/index=%0d/%h/%h",
                   out_packet.payload.sparse.a.count,
                   out_packet.payload.sparse.a.value,
                   out_packet.payload.sparse.a.index);
          $display("expect A count/value/index=%0d/%h/%h",
                   monitor_expected.payload.sparse.a.count,
                   monitor_expected.payload.sparse.a.value,
                   monitor_expected.payload.sparse.a.index);
          $display("actual B count/value/index=%0d/%h/%h",
                   out_packet.payload.sparse.b.count,
                   out_packet.payload.sparse.b.value,
                   out_packet.payload.sparse.b.index);
          $display("expect B count/value/index=%0d/%h/%h",
                   monitor_expected.payload.sparse.b.count,
                   monitor_expected.payload.sparse.b.value,
                   monitor_expected.payload.sparse.b.index);
        end
        $fatal(1, "DU/TIA scoreboard mismatch");
      end
      received_count++;
    end
  end

  initial begin : stimulus
    du_tia_input_t packet;
    logic [GROUP_SIZE-1:0] mask;
    int unsigned test_id;

    rst_n          = 1'b0;
    in_valid       = 1'b0;
    in_packet      = '0;
    rng_state      = 32'h00C0FFEE;
    sent_count     = 0;
    received_count = 0;
    test_id        = 0;

    if ($bits(du_tia_input_t) != 236 ||
        $bits(du_tia_output_t) != 185 ||
        $bits(s0_reg_t) != 237 ||
        $bits(s1_reg_t) != 198 ||
        $bits(s2_reg_t) != 186 ||
        $bits(s3_reg_t) != 186) begin
      $fatal(1, "Unexpected packed interface or pipeline-register width");
    end

    if ($test$plusargs("VCD")) begin
      $dumpfile("build/du_tia.vcd");
      $dumpvars(0, tb_du_tia);
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    /* Four directed packets for each compiler mode. */
    for (int unsigned mode_number = 0; mode_number < 3; mode_number++) begin
      for (int unsigned packet_index = 0;
           packet_index < 4; packet_index++) begin
        packet = make_directed_packet(
            compiler_mode_e'(mode_number), packet_index);
        issue_packet(packet, test_id);
        test_id++;
      end
      issue_bubble();
    end

    /* Exhaust all four group positions and all six legal 2:4 masks. */
    for (int unsigned k_position = 0;
         k_position < GROUP_SIZE; k_position++) begin
      for (int unsigned pattern = 0; pattern < 6; pattern++) begin
        packet            = '0;
        packet.mode       = MODE_UNSTRUCTURED_2TO4;
        packet.k_position = GROUP_POS_W'(k_position);
        packet.payload.hybrid.a_bitmap =
            bitmap_t'(37 * pattern + 19 * k_position);
        packet.payload.hybrid.a_packed = deterministic_packed(
            packet.payload.hybrid.a_bitmap,
            500 + 6 * k_position + pattern,
            1'b0);
        for (int unsigned column = 0; column < N_DIM; column++) begin
          mask = valid_2to4_mask(pattern + column);
          packet.payload.hybrid.b_2to4_mask[column] = mask;
          packet.payload.hybrid.b_2to4_packed[column] =
              deterministic_group(
                  mask, 900 + 13 * (6 * k_position + pattern) + column);
        end
        issue_packet(packet, test_id);
        test_id++;
      end
    end
    issue_bubble();

    /* Exhaust all A bitmaps; B uses the complement. */
    for (int unsigned bitmap_value = 0;
         bitmap_value < 256; bitmap_value++) begin
      packet            = '0;
      packet.mode       = MODE_UNSTRUCTURED_UNSTRUCTURED;
      packet.k_position = GROUP_POS_W'(bitmap_value % GROUP_SIZE);
      packet.payload.dual.a_bitmap = bitmap_t'(bitmap_value);
      packet.payload.dual.b_bitmap = ~bitmap_t'(bitmap_value);
      packet.payload.dual.a_packed = deterministic_packed(
          packet.payload.dual.a_bitmap, 100 + bitmap_value, 1'b1);
      packet.payload.dual.b_packed = deterministic_packed(
          packet.payload.dual.b_bitmap, 600 + bitmap_value, 1'b1);
      issue_packet(packet, test_id);
      test_id++;
    end
    issue_bubble();

    /* Back-to-back randomized traffic with periodic bubbles. */
    for (int unsigned mode_number = 0; mode_number < 3; mode_number++) begin
      for (int unsigned packet_index = 0;
           packet_index < RANDOM_PACKETS_PER_MODE; packet_index++) begin
        make_random_packet(
            compiler_mode_e'(mode_number), test_id, packet);
        issue_packet(packet, test_id);
        test_id++;
        if ((packet_index % 97) == 96) begin
          issue_bubble();
        end
      end
    end

    issue_bubble();
    wait (expected_packet_queue.size() == 0);
    repeat (4) @(negedge clk);

    if (out_valid) begin
      $fatal(1, "out_valid remained asserted after the pipeline drained");
    end
    if ((expected_id_queue.size() != 0) ||
        (expected_mode_queue.size() != 0)) begin
      $fatal(1, "Local diagnostic queues did not drain");
    end
    if (received_count != sent_count) begin
      $fatal(1, "Packet accounting mismatch: sent=%0d received=%0d",
             sent_count, received_count);
    end

    $display("[PASS] DU/TIA compact RTL: %0d packets checked",
             received_count);
    $display("       directed=12 hybrid-exhaustive=24 bitmap-exhaustive=256 random=%0d",
             3 * RANDOM_PACKETS_PER_MODE);
    $finish;
  end

  initial begin : timeout_guard
    #(1ms);
    $fatal(1, "DU/TIA testbench timeout");
  end

endmodule
