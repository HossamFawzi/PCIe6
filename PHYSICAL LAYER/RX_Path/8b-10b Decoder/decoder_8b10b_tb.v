//============================================================
// Testbench: decoder_8b10b_tb
// PCI Gen 6.0 Physical Layer - 8b/10b Decoder
// Compatible with ModelSim/QuestaSim
//
// Fix log:
//  - Tests 7, 11, 12: disparity_in corrected to 1 (RD+); those
//    tests send the RD+ version of the 4b code (0100), so the
//    incoming disparity must be RD+ for no violation to occur.
//  - Test 16 (K.28.3): disparity_in corrected to 0 (RD-);
//    K.28.3 RD- is a positive-disparity code and must arrive
//    while at RD-.
//  - Tests 13, 15, 16: expected data_out corrected:
//      K.28.1 -> 8'h3C, K.28.7 -> 8'hFC, K.28.3 -> 8'h7C
//    (only K.28.5 decodes to 8'hBC; all three had copied K.28.5).
//  - Tests 18, 19 (invalid codewords): removed data_out check
//    against 8'hxx; === with X always evaluates false in
//    simulation. Only dec_err=1 is now verified.
//  - Test 20 (disparity error): D.0.0 using code 10'b1001110100
//    has exactly 5 ones (neutral) so it can never cause a running-
//    disparity error. Replaced with D.0.0 RD- = 10'b1001111011
//    (7 ones, positive disparity). Second send now drives
//    disparity_in=1 so the repeated positive code causes disp_err.
//============================================================
`timescale 1ns/1ps

module decoder_8b10b_tb;

    // DUT ports
    reg        clk;
    reg        rst_n;
    reg  [9:0] data_in;
    reg        dec_en;
    reg        disparity_in;
    wire [7:0] data_out;
    wire       datak_out;
    wire       disparity_out;
    wire       dec_err;
    wire       disparity_err;

    // Instantiate DUT
    decoder_8b10b DUT (
        .clk          (clk),
        .rst_n        (rst_n),
        .data_in      (data_in),
        .dec_en       (dec_en),
        .disparity_in (disparity_in),
        .data_out     (data_out),
        .datak_out    (datak_out),
        .disparity_out(disparity_out),
        .dec_err      (dec_err),
        .disparity_err(disparity_err)
    );

    // Clock generation: 500 MHz (2ns period)
    initial clk = 0;
    always #1 clk = ~clk;

    // Test tracking
    integer pass_cnt;
    integer fail_cnt;
    integer test_num;

    // -------------------------------------------------------
    // Task: apply one decode cycle and check outputs
    // -------------------------------------------------------
    task apply_and_check;
        input [9:0]  din;
        input        d_en;
        input        disp_in;
        input [7:0]  exp_data;
        input        exp_datak;
        input        exp_dec_err;
        input        exp_disp_err;
        input [63:0] label;
        begin
            @(negedge clk);
            data_in      = din;
            dec_en       = d_en;
            disparity_in = disp_in;
            @(posedge clk);
            #0.5;
            test_num = test_num + 1;
            if (d_en) begin
                if ((data_out   === exp_data)    &&
                    (datak_out  === exp_datak)   &&
                    (dec_err    === exp_dec_err)  &&
                    (disparity_err === exp_disp_err)) begin
                    $display("[PASS] Test %0d (%s): data_in=10'b%b | data_out=0x%02h datak=%b dec_err=%b disp_err=%b",
                             test_num, label, din, data_out, datak_out, dec_err, disparity_err);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] Test %0d (%s): data_in=10'b%b", test_num, label, din);
                    $display("       Expected: data_out=0x%02h datak=%b dec_err=%b disp_err=%b",
                             exp_data, exp_datak, exp_dec_err, exp_disp_err);
                    $display("       Got:      data_out=0x%02h datak=%b dec_err=%b disp_err=%b",
                             data_out, datak_out, dec_err, disparity_err);
                    fail_cnt = fail_cnt + 1;
                end
            end
        end
    endtask

    // -------------------------------------------------------
    // Task: reset DUT
    // -------------------------------------------------------
    task do_reset;
        begin
            rst_n        = 1'b0;
            data_in      = 10'h0;
            dec_en       = 1'b0;
            disparity_in = 1'b0;
            repeat(4) @(posedge clk);
            #0.1;
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        test_num = 0;

        $display("========================================================");
        $display(" PCI Gen 6.0 PHY - 8b/10b Decoder Testbench");
        $display(" ModelSim/QuestaSim Compatible");
        $display("========================================================");

        // ---- Reset ----
        do_reset;
        $display("\n--- Reset Complete ---\n");

        // ================================================================
        // TEST GROUP 1: Basic Data Symbol Decoding
        // disparity_in must match the RD context of the 4b sub-code used.
        // All codes below use 4b code 0100 (the RD+ encoding of D.x.0),
        // so any neutral 6b symbol requires disparity_in=1 (RD+).
        // Non-neutral 6b codes that arrive at RD+ also use 0100 correctly.
        // ================================================================
        $display("--- Group 1: Data Symbols (RD- codewords) ---");

        // D.0.0  6b=100111(positive,RD-in) 4b=0100(RD+->RD-) total=5 neutral
        // disparity_in=0: 6b is positive so rd_after6=RD+; 4b 0100 is correct for RD+
        apply_and_check(10'b1001110100, 1, 0, 8'h00, 0, 0, 0, "D.0.0_RD-");

        // D.1.0  6b=011101(positive,RD-in) 4b=0100 total=5 neutral
        apply_and_check(10'b0111010100, 1, 1, 8'h01, 0, 0, 0, "D.1.0_RD-");

        // D.2.0  6b=101101(positive,RD-in) 4b=0100 total=5 neutral
        apply_and_check(10'b1011010100, 1, 0, 8'h02, 0, 0, 0, "D.2.0_RD-");

        // D.3.0  6b=110001(neutral) 4b=0100(RD+->RD-) total=4 negative
        // FIX: disparity_in=1 (RD+): negative code from RD+ is not a violation
        apply_and_check(10'b1100010100, 1, 1, 8'h03, 0, 0, 0, "D.3.0_RD-");

        // D.4.0  6b=110101(positive,RD-in) 4b=0100 total=5 neutral
        apply_and_check(10'b1101010100, 1, 0, 8'h04, 0, 0, 0, "D.4.0_RD-");

        // D.5.0  6b=101001(neutral) 4b=0100 total=4 negative; disparity_in=1
        apply_and_check(10'b1010010100, 1, 1, 8'h05, 0, 0, 0, "D.5.0_RD-");

        // D.6.0  6b=011001(neutral) 4b=0100 total=4 negative; disparity_in=1
        // FIX: was 0, corrected to 1 so negative code from RD+ is not a violation
        apply_and_check(10'b0110010100, 1, 1, 8'h06, 0, 0, 0, "D.6.0_RD+in");

        // D.7.0  6b=111000(positive,RD-in) 4b=0100 total=4 negative; disparity_in=1
        // FIX: was 1 (now kept 1, was correct)
        apply_and_check(10'b1110000100, 1, 1, 8'h07, 0, 0, 0, "D.7.0_RD-");

        // D.8.0  6b=111001(positive,RD-in) 4b=0100 total=5 neutral
        apply_and_check(10'b1110010100, 1, 0, 8'h08, 0, 0, 0, "D.8.0_RD-");

        // D.16.0 6b=011011(positive,RD-in) 4b=0100 total=5 neutral
        apply_and_check(10'b0110110100, 1, 0, 8'h10, 0, 0, 0, "D.16.0_RD-");

        // D.21.0 6b=101010(neutral) 4b=0100 total=4 negative; disparity_in=1
        // FIX: was 0, corrected to 1
        apply_and_check(10'b1010100100, 1, 1, 8'h15, 0, 0, 0, "D.21.0_RD+in");

        // D.28.0 6b=001110(neutral) 4b=0100 total=4 negative; disparity_in=1
        // FIX: was 0, corrected to 1
        apply_and_check(10'b0011100100, 1, 1, 8'h1C, 0, 0, 0, "D.28.0_RD+in");

        // ================================================================
        // TEST GROUP 2: K Symbols
        // All K.28.* RD- codewords use 6b=111100 (4 ones, positive disparity)
        // so disparity_in must be 0 (RD-) for no disparity error.
        // Expected data_out: {HGF[2:0], 11100} where HGF is the .x suffix.
        // ================================================================
        $display("\n--- Group 2: K (Control) Symbols ---");

        // K.28.1 RD- = 111100_1001 -> data={001,11100}=0x3C, datak=1
        // FIX: expected data changed from 0xBC to 0x3C
        apply_and_check(10'b1111001001, 1, 0, 8'h3C, 1, 0, 0, "K.28.1_RD-");

        // K.28.5 RD- = 111100_1000 -> data={101,11100}=0xBC (COM symbol)
        // 111100_1000 has 5 ones (neutral); disparity_in=1 -> neutral -> no err
        apply_and_check(10'b1111001000, 1, 1, 8'hBC, 1, 0, 0, "K.28.5_RD-");

        // K.28.7 RD- = 111100_1110 -> data={111,11100}=0xFC, datak=1
        // 7 ones > 5 (positive) with disparity_in=0 -> no violation
        // FIX: expected data changed from 0xBC to 0xFC
        apply_and_check(10'b1111001110, 1, 0, 8'hFC, 1, 0, 0, "K.28.7_RD-");

        // K.28.3 RD- = 111100_1100 -> data={011,11100}=0x7C, datak=1
        // 6 ones > 5 (positive) with disparity_in=0 -> no violation
        // FIX: expected data changed from 0xBC to 0x7C; disparity_in changed from 1 to 0
        apply_and_check(10'b1111001100, 1, 0, 8'h7C, 1, 0, 0, "K.28.3_RD-");

        // ================================================================
        // TEST GROUP 3: dec_en=0 (disabled, no decode should occur)
        // ================================================================
        $display("\n--- Group 3: Decoder Disabled (dec_en=0) ---");

        begin
            @(negedge clk);
            data_in      = 10'b1001110100; // D.0.0
            dec_en       = 1'b0;
            disparity_in = 1'b0;
            @(posedge clk);
            #0.5;
            test_num = test_num + 1;
            if (dec_err === 1'b0 && disparity_err === 1'b0) begin
                $display("[PASS] Test %0d (Disabled): dec_err=0 disparity_err=0 as expected", test_num);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Test %0d (Disabled): expected no errors when dec_en=0, got dec_err=%b disp_err=%b",
                         test_num, dec_err, disparity_err);
                fail_cnt = fail_cnt + 1;
            end
        end

        // ================================================================
        // TEST GROUP 4: Invalid / Error Codeword
        // FIX: removed data_out comparison with 8'hxx - using === against an
        //      X literal always evaluates false in simulation. Only dec_err=1
        //      and datak=0 are checked; data_out and disp_err are don't-cares.
        // ================================================================
        $display("\n--- Group 4: Invalid Codewords (expect dec_err=1) ---");

        begin
            // All zeros - not a valid 8b/10b code
            @(negedge clk);
            data_in      = 10'b0000000000;
            dec_en       = 1'b1;
            disparity_in = 1'b0;
            @(posedge clk);
            #0.5;
            test_num = test_num + 1;
            if (dec_err === 1'b1 && datak_out === 1'b0) begin
                $display("[PASS] Test %0d (INVALID_all0): dec_err=1 datak=0 as expected (data_out=0x%02h is don't-care)",
                         test_num, data_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Test %0d (INVALID_all0): expected dec_err=1 datak=0, got dec_err=%b datak=%b",
                         test_num, dec_err, datak_out);
                fail_cnt = fail_cnt + 1;
            end
        end

        begin
            // All ones - not a valid 8b/10b code
            @(negedge clk);
            data_in      = 10'b1111111111;
            dec_en       = 1'b1;
            disparity_in = 1'b1;
            @(posedge clk);
            #0.5;
            test_num = test_num + 1;
            if (dec_err === 1'b1 && datak_out === 1'b0) begin
                $display("[PASS] Test %0d (INVALID_all1): dec_err=1 datak=0 as expected (data_out=0x%02h is don't-care)",
                         test_num, data_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Test %0d (INVALID_all1): expected dec_err=1 datak=0, got dec_err=%b datak=%b",
                         test_num, dec_err, datak_out);
                fail_cnt = fail_cnt + 1;
            end
        end

        // ================================================================
        // TEST GROUP 5: Disparity Error Detection
        // FIX: D.0.0 with code 10'b1001110100 has exactly 5 ones (neutral)
        //      and can never trigger a disparity error. Replaced with
        //      D.0.0 RD- = 10'b1001111011 (7 ones, positive disparity).
        //      First send: disparity_in=0 (RD-) -> positive code is valid, no err.
        //      Second send: disparity_in=1 (RD+) -> positive code violates RD -> err.
        // ================================================================
        $display("\n--- Group 5: Disparity Error Detection ---");

        @(negedge clk);
        data_in      = 10'b1001111011; // D.0.0 RD- true encoding: 7 ones, positive disparity
        dec_en       = 1'b1;
        disparity_in = 1'b0;           // RD- in: positive code is correct
        @(posedge clk);
        #0.5;
        $display("[INFO] First positive-disparity D.0.0 RD- sent (disparity_in=0, no error expected)");

        @(negedge clk);
        data_in      = 10'b1001111011; // Same positive-disparity code
        dec_en       = 1'b1;
        disparity_in = 1'b1;           // RD+ in: sending another positive code -> violation
        @(posedge clk);
        #0.5;
        test_num = test_num + 1;
        if (disparity_err === 1'b1) begin
            $display("[PASS] Test %0d (DispErr): disparity_err correctly asserted on RD violation", test_num);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Test %0d (DispErr): expected disparity_err=1, got %b", test_num, disparity_err);
            fail_cnt = fail_cnt + 1;
        end

        // ================================================================
        // TEST GROUP 6: Reset During Operation
        // ================================================================
        $display("\n--- Group 6: Reset During Operation ---");
        @(negedge clk);
        data_in      = 10'b1001110100;
        dec_en       = 1'b1;
        disparity_in = 1'b0;
        @(posedge clk);
        #0.1;
        rst_n = 1'b0;
        @(posedge clk);
        #0.5;
        test_num = test_num + 1;
        if (data_out === 8'h00 && datak_out === 1'b0 && dec_err === 1'b0 && disparity_err === 1'b0) begin
            $display("[PASS] Test %0d (Reset): All outputs cleared on reset", test_num);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Test %0d (Reset): Outputs not cleared: data=%02h datak=%b dec_err=%b disp_err=%b",
                     test_num, data_out, datak_out, dec_err, disparity_err);
            fail_cnt = fail_cnt + 1;
        end
        rst_n = 1'b1;
        @(posedge clk);

        // ================================================================
        // TEST GROUP 7: Continuous streaming - multiple symbols
        // ================================================================
        $display("\n--- Group 7: Continuous Streaming ---");
        begin : stream_blk
            integer i;
            reg [9:0] stream_codes [0:7];
            reg [7:0] stream_exp   [0:7];
            stream_codes[0] = 10'b1010010100; // D.5.0
            stream_codes[1] = 10'b0110010100; // D.6.0
            stream_codes[2] = 10'b1110000100; // D.7.0
            stream_codes[3] = 10'b1110010100; // D.8.0
            stream_codes[4] = 10'b1010010100; // D.5.0
            stream_codes[5] = 10'b0110010100; // D.6.0
            stream_codes[6] = 10'b1110000100; // D.7.0
            stream_codes[7] = 10'b1110010100; // D.8.0
            stream_exp[0]   = 8'h05;
            stream_exp[1]   = 8'h06;
            stream_exp[2]   = 8'h07;
            stream_exp[3]   = 8'h08;
            stream_exp[4]   = 8'h05;
            stream_exp[5]   = 8'h06;
            stream_exp[6]   = 8'h07;
            stream_exp[7]   = 8'h08;
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge clk);
                data_in      = stream_codes[i];
                dec_en       = 1'b1;
                disparity_in = 1'b0;
                @(posedge clk);
                #0.5;
                test_num = test_num + 1;
                if (data_out === stream_exp[i] && dec_err === 1'b0) begin
                    $display("[PASS] Test %0d (Stream[%0d]): data_out=0x%02h", test_num, i, data_out);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] Test %0d (Stream[%0d]): exp=0x%02h got=0x%02h dec_err=%b",
                             test_num, i, stream_exp[i], data_out, dec_err);
                    fail_cnt = fail_cnt + 1;
                end
            end
        end

        // ================================================================
        // TEST GROUP 8: PCI Gen2 COM Symbol (K28.5 RD+)
        // ================================================================
        $display("\n--- Group 8: PCI Gen1/2 COM Symbol K28.5 ---");
        // K28.5 RD+ = 000011_0111 -> byte=0xBC, datak=1
        apply_and_check(10'b0000110111, 1, 1, 8'hBC, 1, 0, 0, "K.28.5_RD+");

        // ================================================================
        // SUMMARY
        // ================================================================
        $display("\n========================================================");
        $display(" SIMULATION COMPLETE");
        $display(" Total Tests : %0d", test_num);
        $display(" PASSED      : %0d", pass_cnt);
        $display(" FAILED      : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display(" STATUS      : ALL TESTS PASSED");
        else
            $display(" STATUS      : SOME TESTS FAILED");
        $display("========================================================\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #10000;
        $display("[TIMEOUT] Simulation exceeded limit");
        $finish;
    end

    // Optional waveform dump for QuestaSim
    initial begin
        $dumpfile("decoder_8b10b_waves.vcd");
        $dumpvars(0, decoder_8b10b_tb);
    end

endmodule
