
`timescale 1ns / 1ps

module scrambler_tb;

    reg          clk;
    reg          rst_n;
    reg  [255:0] data_in;
    reg          data_valid_in;
    reg  [22:0]  lfsr_seed;
    reg          scramble_en;
    reg          link_reset;

    wire [255:0] data_out;
    wire         data_valid_out;
    wire [22:0]  lfsr_state;

    scrambler dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (data_in),
        .data_valid_in (data_valid_in),
        .lfsr_seed     (lfsr_seed),
        .scramble_en   (scramble_en),
        .link_reset    (link_reset),
        .data_out      (data_out),
        .data_valid_out(data_valid_out),
        .lfsr_state    (lfsr_state)
    );

    initial clk = 0;
    always #0.5 clk = ~clk;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check;
        input [7:0]   tid;
        input         cond;
        input [255:0] msg;
        begin
            if (cond) begin
                $display("[PASS] TC%0d: %0s", tid, msg);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] TC%0d: %0s  @time=%0t", tid, msg, $time);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task idle;
        begin
            data_in       = 256'h0;
            data_valid_in = 0;
            scramble_en   = 1;
            link_reset    = 0;
            lfsr_seed     = 23'h7FFFFF;
        end
    endtask

    task clk_n;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk); #0.1;
            end
        end
    endtask

    task ref_lfsr;
        inout  [22:0] state;
        output [255:0] word;
        integer b;
        reg    new_bit;
        begin
            word = 256'h0;
            for (b = 0; b < 256; b = b + 1) begin
                new_bit = state[22] ^ state[17];

                word[255 - b] = state[22];

                state = {state[21:0], new_bit};
            end
        end
    endtask

    reg [255:0] ref_word1, ref_word2, ref_word3, ref_word4;
    reg [22:0]  ref_state;
    reg [255:0] d_in1, d_in2;
    reg [255:0] scrambled1, scrambled2;
    reg [255:0] rescrambled;

    initial begin
        $dumpfile("scrambler_tb.vcd");
        $dumpvars(0, scrambler_tb);

        idle();
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #0.1;

        rst_n = 0;
        @(posedge clk); #0.1;
        check(1, data_out       === 256'h0,        "data_out=0 in reset");
        check(1, data_valid_out === 1'b0,           "data_valid_out=0 in reset");
        check(1, lfsr_state     === 23'h7FFFFF,     "lfsr_state=seed in reset");
        rst_n = 1;
        @(posedge clk); #0.1;

        idle();
        scramble_en   = 0;
        data_in       = 256'hDEAD_BEEF_CAFE_1234_5678_9ABC_DEF0_1111_2222_3333_4444_5555_6666_7777_8888_9999;
        data_valid_in = 1;
        @(posedge clk); #0.1;
        data_valid_in = 0;

        check(2, data_out       === data_in,  "Bypass: data_out=data_in");
        check(2, data_valid_out === 1'b1,     "Bypass: valid propagated");

        check(2, lfsr_state === 23'h7FFFFF,   "Bypass: LFSR frozen");

        @(posedge clk); #0.1;

        idle();

        rst_n = 0; @(posedge clk); #0.1; rst_n = 1; @(posedge clk); #0.1;

        ref_state = 23'h7FFFFF;
        ref_lfsr(ref_state, ref_word1);

        d_in1         = 256'hA5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5;
        data_in       = d_in1;
        data_valid_in = 1;
        scramble_en   = 1;
        @(posedge clk); #0.1;
        data_valid_in = 0;

        check(3, data_out === (d_in1 ^ ref_word1), "Single beat: data_out = D XOR LFSR");
        check(3, data_valid_out === 1'b1,           "Single beat: valid=1");

        @(posedge clk); #0.1;

        idle();
        rst_n = 0; @(posedge clk); #0.1; rst_n = 1; @(posedge clk); #0.1;

        d_in1 = 256'hFEEDFACE_DEADBEEF_12345678_9ABCDEF0_CAFEBABE_01020304_05060708_090A0B0C;

        data_in       = d_in1;
        data_valid_in = 1;
        @(posedge clk); #0.1;
        data_valid_in = 0;
        scrambled1 = data_out;

        rst_n = 0; @(posedge clk); #0.1; rst_n = 1; @(posedge clk); #0.1;

        data_in       = scrambled1;
        data_valid_in = 1;
        @(posedge clk); #0.1;
        data_valid_in = 0;
        rescrambled = data_out;

        check(4, rescrambled === d_in1, "Self-inverse: descramble recovers original");

        @(posedge clk); #0.1;

        idle();
        rst_n = 0; @(posedge clk); #0.1; rst_n = 1; @(posedge clk); #0.1;

        d_in1 = 256'h55555555_55555555_55555555_55555555_55555555_55555555_55555555_55555555;

        data_in       = d_in1;
        data_valid_in = 1;
        @(posedge clk); #0.1;
        data_valid_in = 0;
        scrambled1 = data_out;

        lfsr_seed  = 23'h3C3C3C;
        link_reset = 1;
        @(posedge clk); #0.1;
        link_reset = 0;
        @(posedge clk); #0.1;

        data_in       = d_in1;
        data_valid_in = 1;
        @(posedge clk); #0.1;
        data_valid_in = 0;
        scrambled2 = data_out;

        check(5, scrambled1 !== scrambled2, "Different seed → different scramble output");

        @(posedge clk); #0.1;

        idle();
        rst_n = 0; @(posedge clk); #0.1; rst_n = 1; @(posedge clk); #0.1;

        data_in       = 256'hAAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA;
        data_valid_in = 1;
        @(posedge clk); #0.1;
        @(posedge clk); #0.1;
        data_valid_in = 0;

        lfsr_seed  = 23'h1A2B3C;
        link_reset = 1;
        @(posedge clk); #0.1;
        link_reset = 0;

        check(6, lfsr_state === 23'h1A2B3C, "link_reset: LFSR reloads to new seed");

        @(posedge clk); #0.1;

        idle();
        rst_n = 0; @(posedge clk); #0.1; rst_n = 1; @(posedge clk); #0.1;

        ref_state = 23'h7FFFFF;
        ref_lfsr(ref_state, ref_word1);
        ref_lfsr(ref_state, ref_word2);
        ref_lfsr(ref_state, ref_word3);
        ref_lfsr(ref_state, ref_word4);

        data_in       = 256'h0;
        data_valid_in = 1;
        @(posedge clk); #0.1;
        check(7, data_out === ref_word1, "Stream beat0 scramble correct");

        data_in = 256'h0;
        @(posedge clk); #0.1;
        check(7, data_out === ref_word2, "Stream beat1 scramble correct");

        data_in = 256'h0;
        @(posedge clk); #0.1;
        check(7, data_out === ref_word3, "Stream beat2 scramble correct");

        data_in = 256'h0;
        @(posedge clk); #0.1;
        check(7, data_out === ref_word4, "Stream beat3 scramble correct");
        data_valid_in = 0;

        @(posedge clk); #0.1;

        idle();
        rst_n = 0; @(posedge clk); #0.1; rst_n = 1; @(posedge clk); #0.1;

        data_in       = 256'h0;
        data_valid_in = 1;
        scramble_en   = 1;
        @(posedge clk); #0.1;
        data_valid_in = 0;

        begin : tc8_block
            reg [22:0] state_after_beat1;
            state_after_beat1 = lfsr_state;

            repeat(5) @(posedge clk); #0.1;

            check(8, lfsr_state === state_after_beat1, "Idle: LFSR frozen when valid=0");
        end

        @(posedge clk); #0.1;

        idle();
        rst_n = 0; @(posedge clk); #0.1; rst_n = 1; @(posedge clk); #0.1;

        ref_state = 23'h7FFFFF;
        ref_lfsr(ref_state, ref_word1);

        data_in       = 256'h0;
        data_valid_in = 1;
        @(posedge clk); #0.1;
        data_valid_in = 0;

        check(9, data_out === ref_word1, "All-zeros in: out=scramble_word");

        @(posedge clk); #0.1;

        idle();
        rst_n = 0; @(posedge clk); #0.1; rst_n = 1; @(posedge clk); #0.1;

        ref_state = 23'h7FFFFF;
        ref_lfsr(ref_state, ref_word1);

        data_in       = 256'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
        data_valid_in = 1;
        @(posedge clk); #0.1;
        data_valid_in = 0;

        check(10, data_out === ~ref_word1, "All-ones in: out=~scramble_word");

        @(posedge clk); #0.1;

        idle();
        rst_n = 0; @(posedge clk); #0.1; rst_n = 1; @(posedge clk); #0.1;

        ref_state = 23'h7FFFFF;
        ref_lfsr(ref_state, ref_word1);

        data_in       = 256'h1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0;
        data_valid_in = 1;
        @(posedge clk); #0.1;
        data_valid_in = 0;

        check(11, lfsr_state === ref_state, "lfsr_state matches ref after 1 beat");

        @(posedge clk); #0.1;

        idle();
        rst_n = 0; @(posedge clk); #0.1; rst_n = 1; @(posedge clk); #0.1;

        scramble_en   = 0;
        data_in       = 256'h0;
        data_valid_in = 1;
        @(posedge clk); #0.1;
        @(posedge clk); #0.1;
        data_valid_in = 0;
        check(12, lfsr_state === 23'h7FFFFF, "Before enable: LFSR still at seed");

        scramble_en = 1;
        ref_state   = 23'h7FFFFF;
        ref_lfsr(ref_state, ref_word1);

        data_in       = 256'h0;
        data_valid_in = 1;
        @(posedge clk); #0.1;
        data_valid_in = 0;

        check(12, data_out   === ref_word1, "After enable: first scramble uses seed state");
        check(12, lfsr_state === ref_state, "After enable: LFSR advanced from seed");

        @(posedge clk); #0.1;

        $display("\n========================================");
        $display(" PCIe 6.0 Scrambler Testbench Summary");
        $display("========================================");
        $display(" PASS : %0d", pass_cnt);
        $display(" FAIL : %0d", fail_cnt);
        $display("========================================");
        if (fail_cnt == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> %0d TEST(S) FAILED <<<", fail_cnt);
        $display("");
        $finish;
    end

    initial begin
        #50000;
        $display("[WATCHDOG] Simulation timed out!");
        $finish;
    end

endmodule
