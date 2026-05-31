
`timescale 1ns/1ps

module decoder_8b10b_tb;

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

    initial clk = 0;
    always #1 clk = ~clk;

    integer pass_cnt;
    integer fail_cnt;
    integer test_num;

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

        do_reset;
        $display("\n--- Reset Complete ---\n");

        $display("--- Group 1: Data Symbols (RD- codewords) ---");

        apply_and_check(10'b1001110100, 1, 0, 8'h00, 0, 0, 0, "D.0.0_RD-");

        apply_and_check(10'b0111010100, 1, 1, 8'h01, 0, 0, 0, "D.1.0_RD-");

        apply_and_check(10'b1011010100, 1, 0, 8'h02, 0, 0, 0, "D.2.0_RD-");

        apply_and_check(10'b1100010100, 1, 1, 8'h03, 0, 0, 0, "D.3.0_RD-");

        apply_and_check(10'b1101010100, 1, 0, 8'h04, 0, 0, 0, "D.4.0_RD-");

        apply_and_check(10'b1010010100, 1, 1, 8'h05, 0, 0, 0, "D.5.0_RD-");

        apply_and_check(10'b0110010100, 1, 1, 8'h06, 0, 0, 0, "D.6.0_RD+in");

        apply_and_check(10'b1110000100, 1, 1, 8'h07, 0, 0, 0, "D.7.0_RD-");

        apply_and_check(10'b1110010100, 1, 0, 8'h08, 0, 0, 0, "D.8.0_RD-");

        apply_and_check(10'b0110110100, 1, 0, 8'h10, 0, 0, 0, "D.16.0_RD-");

        apply_and_check(10'b1010100100, 1, 1, 8'h15, 0, 0, 0, "D.21.0_RD+in");

        apply_and_check(10'b0011100100, 1, 1, 8'h1C, 0, 0, 0, "D.28.0_RD+in");

        $display("\n--- Group 2: K (Control) Symbols ---");

        apply_and_check(10'b1111001001, 1, 0, 8'h3C, 1, 0, 0, "K.28.1_RD-");

        apply_and_check(10'b1111001000, 1, 1, 8'hBC, 1, 0, 0, "K.28.5_RD-");

        apply_and_check(10'b1111001110, 1, 0, 8'hFC, 1, 0, 0, "K.28.7_RD-");

        apply_and_check(10'b1111001100, 1, 0, 8'h7C, 1, 0, 0, "K.28.3_RD-");

        $display("\n--- Group 3: Decoder Disabled (dec_en=0) ---");

        begin
            @(negedge clk);
            data_in      = 10'b1001110100;
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

        $display("\n--- Group 4: Invalid Codewords (expect dec_err=1) ---");

        begin

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

        $display("\n--- Group 5: Disparity Error Detection ---");

        @(negedge clk);
        data_in      = 10'b1001111011;
        dec_en       = 1'b1;
        disparity_in = 1'b0;
        @(posedge clk);
        #0.5;
        $display("[INFO] First positive-disparity D.0.0 RD- sent (disparity_in=0, no error expected)");

        @(negedge clk);
        data_in      = 10'b1001111011;
        dec_en       = 1'b1;
        disparity_in = 1'b1;
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

        $display("\n--- Group 7: Continuous Streaming ---");
        begin : stream_blk
            integer i;
            reg [9:0] stream_codes [0:7];
            reg [7:0] stream_exp   [0:7];
            stream_codes[0] = 10'b1010010100;
            stream_codes[1] = 10'b0110010100;
            stream_codes[2] = 10'b1110000100;
            stream_codes[3] = 10'b1110010100;
            stream_codes[4] = 10'b1010010100;
            stream_codes[5] = 10'b0110010100;
            stream_codes[6] = 10'b1110000100;
            stream_codes[7] = 10'b1110010100;
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

        $display("\n--- Group 8: PCI Gen1/2 COM Symbol K28.5 ---");

        apply_and_check(10'b0000110111, 1, 1, 8'hBC, 1, 0, 0, "K.28.5_RD+");

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

    initial begin
        #10000;
        $display("[TIMEOUT] Simulation exceeded limit");
        $finish;
    end

    initial begin
        $dumpfile("decoder_8b10b_waves.vcd");
        $dumpvars(0, decoder_8b10b_tb);
    end

endmodule
