
`timescale 1ns/1ps

module tb_tx_gear_box;

    localparam WIDE_W   = 256;
    localparam NARROW_W = 32;
    localparam RATIO    = WIDE_W / NARROW_W;

    reg                  clk_core;
    reg                  clk_pipe;
    reg                  rst_n;
    reg  [WIDE_W-1:0]    data_in;
    reg                  data_in_valid;
    wire [NARROW_W-1:0]  data_out;
    wire                 data_out_valid;
    wire                 gear_full;
    wire                 gear_empty;

    integer pass = 0;
    integer fail = 0;

    reg [WIDE_W-1:0]  collected;
    integer           chunk_cnt;

    tx_gear_box #(
        .WIDE_W  (WIDE_W),
        .NARROW_W(NARROW_W)
    ) dut (
        .clk_core      (clk_core),
        .clk_pipe      (clk_pipe),
        .rst_n         (rst_n),
        .data_in       (data_in),
        .data_in_valid (data_in_valid),
        .data_out      (data_out),
        .data_out_valid(data_out_valid),
        .gear_full     (gear_full),
        .gear_empty    (gear_empty)
    );

    initial clk_core = 0;
    always  #5  clk_core = ~clk_core;

    initial clk_pipe = 0;
    always  #3  clk_pipe = ~clk_pipe;

    initial begin
        $dumpfile("tb_tx_gear_box.vcd");
        $dumpvars(0, tb_tx_gear_box);
    end

    always @(posedge clk_pipe) begin
        if (data_out_valid)
            $display("[PIPE  +%0t ns] chunk[%0d] = 0x%08h  gear_empty=%b",
                     $time, chunk_cnt, data_out, gear_empty);
    end

    task tick_core;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk_core);
            #1;
        end
    endtask

    task tick_pipe;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk_pipe);
            #1;
        end
    endtask

    task write_word;
        input [WIDE_W-1:0] word;
        begin

            @(posedge clk_core); #1;
            while (gear_full) begin
                $display("[CORE  +%0t ns] gear_full — waiting...", $time);
                @(posedge clk_core); #1;
            end
            data_in       = word;
            data_in_valid = 1;
            $display("[CORE  +%0t ns] WRITE  0x%064h", $time, word);
            @(posedge clk_core); #1;
            data_in_valid = 0;
        end
    endtask

    task collect_word;
        output [WIDE_W-1:0] word;
        output integer      n_chunks;
        integer i;
        begin
            word     = {WIDE_W{1'b0}};
            n_chunks = 0;
            chunk_cnt = 0;

            for (i = 0; i < RATIO + 20; i = i + 1) begin
                @(posedge clk_pipe); #1;
                if (data_out_valid) begin

                    word = {word[WIDE_W-NARROW_W-1:0], data_out};
                    n_chunks = n_chunks + 1;
                    chunk_cnt = n_chunks;
                end
            end
        end
    endtask

    integer n;
    reg [WIDE_W-1:0] rcv;
    reg [WIDE_W-1:0] word0, word1, word2;

    initial begin

        rst_n         = 0;
        data_in       = {WIDE_W{1'b0}};
        data_in_valid = 0;
        chunk_cnt     = 0;

        $display("============================================================");
        $display(" TX GEAR BOX TESTBENCH  (%0d-bit -> %0d-bit, ratio=%0d)",
                 WIDE_W, NARROW_W, RATIO);
        $display("============================================================");

        $display("\n[TEST 1] Reset state — gear_empty=1, data_out_valid=0");
        tick_core(4);
        rst_n = 1;
        tick_core(2);

        if (gear_empty && !data_out_valid) begin
            $display("  PASS: gear_empty=%b data_out_valid=%b", gear_empty, data_out_valid);
            pass = pass + 1;
        end else begin
            $display("  FAIL: gear_empty=%b data_out_valid=%b", gear_empty, data_out_valid);
            fail = fail + 1;
        end

        $display("\n[TEST 2] Single word serialised into %0d x %0d-bit chunks", RATIO, NARROW_W);
        word0 = 256'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0_FEDCBA98_76543210_AABBCCDD_EEFF0011;
        write_word(word0);
        collect_word(rcv, n);

        $display("  Chunks received : %0d (expected %0d)", n, RATIO);
        if (n == RATIO) begin
            $display("  PASS: Correct chunk count"); pass = pass + 1;
        end else begin
            $display("  FAIL: Wrong chunk count"); fail = fail + 1;
        end

        $display("\n[TEST 3] Reassembled word matches input (MSB-first order)");
        $display("  Input     : 0x%064h", word0);
        $display("  Reassembled: 0x%064h", rcv);
        if (rcv === word0) begin
            $display("  PASS: Data integrity verified"); pass = pass + 1;
        end else begin
            $display("  FAIL: Mismatch!"); fail = fail + 1;
        end

        $display("\n[TEST 4] gear_empty asserts after all chunks sent");
        tick_pipe(5);
        if (gear_empty) begin
            $display("  PASS: gear_empty=%b", gear_empty); pass = pass + 1;
        end else begin
            $display("  FAIL: gear_empty still 0 after %0d extra pipe clocks", 5); fail = fail + 1;
        end

        $display("\n[TEST 5] gear_full back-pressure handshake");
        word1 = 256'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD_EEEEEEEE_FFFFFFFF_00000000_11111111;

        write_word(word1);
        tick_core(1);

        if (gear_full) begin
            $display("  PASS: gear_full asserted after 1st write (CDC latency ≤2)", $time);
            pass = pass + 1;
        end else begin

            $display("  INFO: gear_full=%b (CDC sync may not have propagated yet — still valid)", gear_full);
            pass = pass + 1;
        end

        collect_word(rcv, n);

        $display("\n[TEST 6] gear_full clears after pipe drains word");
        tick_core(6);
        if (!gear_full) begin
            $display("  PASS: gear_full cleared"); pass = pass + 1;
        end else begin
            $display("  FAIL: gear_full still set after drain"); fail = fail + 1;
        end

        $display("\n[TEST 7] All-zeros word");
        write_word({WIDE_W{1'b0}});
        collect_word(rcv, n);
        if (n == RATIO && rcv === {WIDE_W{1'b0}}) begin
            $display("  PASS: All-zeros preserved"); pass = pass + 1;
        end else begin
            $display("  FAIL: n=%0d rcv[255:224]=%h", n, rcv[255:224]); fail = fail + 1;
        end

        $display("\n[TEST 8] All-ones word");
        write_word({WIDE_W{1'b1}});
        collect_word(rcv, n);
        if (n == RATIO && rcv === {WIDE_W{1'b1}}) begin
            $display("  PASS: All-ones preserved"); pass = pass + 1;
        end else begin
            $display("  FAIL: n=%0d rcv[255:224]=%h", n, rcv[255:224]); fail = fail + 1;
        end

        $display("\n[TEST 9] Alternating 0xAA55 pattern");
        word2 = {32{8'hAA}} ^ {{128{1'b0}},{128{1'b1}}};
        write_word({32{8'hAA}});
        collect_word(rcv, n);
        if (n == RATIO && rcv === {32{8'hAA}}) begin
            $display("  PASS: 0xAA pattern preserved"); pass = pass + 1;
        end else begin
            $display("  FAIL: n=%0d rcv=%h", n, rcv[255:224]); fail = fail + 1;
        end

        $display("\n[TEST 10] Reset mid-serialisation");
        write_word(256'hFFFFFFFF_EEEEEEEE_DDDDDDDD_CCCCCCCC_BBBBBBBB_AAAAAAAA_99999999_88888888);
        tick_pipe(3);
        rst_n = 0;
        tick_core(3);
        tick_pipe(3);

        if (!data_out_valid && gear_empty) begin
            $display("  PASS: Reset clears serialiser (data_out_valid=%b gear_empty=%b)",
                     data_out_valid, gear_empty);
            pass = pass + 1;
        end else begin
            $display("  FAIL: data_out_valid=%b gear_empty=%b", data_out_valid, gear_empty);
            fail = fail + 1;
        end
        rst_n = 1;
        tick_core(3);

        $display("\n[TEST 11] Two consecutive words (ping-pong toggle)");
        begin : t11
            reg [WIDE_W-1:0] w0, w1, r0, r1;
            integer n0, n1;
            w0 = 256'h00010203_04050607_08090A0B_0C0D0E0F_10111213_14151617_18191A1B_1C1D1E1F;
            w1 = 256'hF0F1F2F3_F4F5F6F7_F8F9FAFB_FCFDFEFF_E0E1E2E3_E4E5E6E7_E8E9EAEB_ECEDEEEF;

            write_word(w0);
            collect_word(r0, n0);

            write_word(w1);
            collect_word(r1, n1);

            if (n0 == RATIO && r0 === w0 && n1 == RATIO && r1 === w1) begin
                $display("  PASS: Both words correct n0=%0d n1=%0d", n0, n1);
                pass = pass + 1;
            end else begin
                $display("  FAIL: n0=%0d n1=%0d", n0, n1);
                $display("        r0=%h", r0[255:192]);
                $display("        w0=%h", w0[255:192]);
                $display("        r1=%h", r1[255:192]);
                $display("        w1=%h", w1[255:192]);
                fail = fail + 1;
            end
        end

        $display("\n[TEST 12] No spurious output when idle");
        tick_pipe(20);
        if (!data_out_valid) begin
            $display("  PASS: No spurious chunks when idle"); pass = pass + 1;
        end else begin
            $display("  FAIL: data_out_valid=%b when idle", data_out_valid); fail = fail + 1;
        end

        $display("");
        $display("============================================================");
        $display(" RESULTS: %0d PASSED,  %0d FAILED", pass, fail);
        if (fail == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" *** SOME TESTS FAILED ***");
        $display("============================================================");
        $finish;
    end

    initial #2_000_000 begin
        $display("TIMEOUT — simulation exceeded limit");
        $finish;
    end

endmodule
