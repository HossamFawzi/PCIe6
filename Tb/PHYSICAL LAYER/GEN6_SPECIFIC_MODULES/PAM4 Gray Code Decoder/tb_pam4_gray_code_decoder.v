
`timescale 1ns/1ps

module pam4_gray_code_decoder_tb;

    localparam CLK_PERIOD = 10;

    reg clk;
    reg rst_n;

    reg  [127:0] pam4_symbols_in;
    reg          pam4_valid;
    reg          pam4_en;

    wire [255:0] data_out;
    wire         data_valid;
    wire         decode_err;

    integer pass_cnt;
    integer fail_cnt;
    integer tc;
    integer k;
    integer j;

    reg [255:0] got_data;
    reg         got_valid;
    reg         got_err;

    reg [127:0] mixed_gray;
    reg [255:0] mixed_bin_exp;

    reg [127:0] s0;
    reg [127:0] s1;

    reg [127:0] fill_result_128;
    reg [255:0] fill_result_256;

    pam4_gray_code_decoder dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .pam4_symbols_in (pam4_symbols_in),
        .pam4_valid      (pam4_valid),
        .pam4_en         (pam4_en),
        .data_out        (data_out),
        .data_valid      (data_valid),
        .decode_err      (decode_err)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task wait_cycle;
        begin
            @(posedge clk); #1;
        end
    endtask

    task apply_and_check;
        input [127:0] symbols;
        input         valid;
        input         en;
        input [255:0] exp_data;
        input         exp_valid;
        input         exp_err;
        input [103:0] label;
        begin
            @(negedge clk);
            pam4_symbols_in = symbols;
            pam4_valid      = valid;
            pam4_en         = en;

            @(posedge clk); #1;
            @(posedge clk); #1;

            got_data  = data_out;
            got_valid = data_valid;
            got_err   = decode_err;

            if ((got_data  === exp_data)  &&
                (got_valid === exp_valid) &&
                (got_err   === exp_err)) begin
                $display("  PASS  %0s", label);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  %0s", label);
                $display("    data_out   got=%0h", got_data);
                $display("    data_out   exp=%0h", exp_data);
                $display("    data_valid got=%b exp=%b", got_valid, exp_valid);
                $display("    decode_err got=%b exp=%b", got_err,   exp_err);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task fill_gray_128;
        input [1:0] gray_sym;
        begin
            fill_result_128 = 128'b0;
            for (k = 0; k < 64; k = k + 1)
                fill_result_128[k*2 +: 2] = gray_sym;
        end
    endtask

    task fill_bin_256;
        input [1:0] bin_sym;
        begin
            fill_result_256 = 256'b0;
            for (k = 0; k < 64; k = k + 1)
                fill_result_256[k*2 +: 2] = bin_sym;
        end
    endtask

    initial begin
        $display("==============================================");
        $display(" PAM4 Gray Code Decoder - Testbench Start");
        $display("==============================================");

        pass_cnt        = 0;
        fail_cnt        = 0;
        tc              = 0;
        pam4_symbols_in = 128'b0;
        pam4_valid      = 1'b0;
        pam4_en         = 1'b1;
        rst_n           = 1'b0;

        tc = 1;
        $display("\n[TC%0d] Reset: all outputs must be zero", tc);
        repeat(4) @(posedge clk); #1;
        if (data_out === 256'b0 && data_valid === 1'b0 && decode_err === 1'b0) begin
            $display("  PASS  outputs zero during reset");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  outputs not zero during reset");
            $display("    data_out=%h data_valid=%b decode_err=%b",
                     data_out, data_valid, decode_err);
            fail_cnt = fail_cnt + 1;
        end

        @(negedge clk);
        rst_n = 1'b1;
        wait_cycle;

        tc = 2;
        $display("\n[TC%0d] Bypass mode (pam4_en=0)", tc);
        @(negedge clk);
        pam4_symbols_in = 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0;
        pam4_valid      = 1'b1;
        pam4_en         = 1'b0;

        @(posedge clk); #1;
        @(posedge clk); #1;

        if (data_valid === 1'b1 &&
            data_out[127:0] === 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0 &&
            data_out[255:128] === 128'b0 &&
            decode_err === 1'b0) begin
            $display("  PASS  Bypass: symbols forwarded unchanged");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  Bypass check");
            $display("    data_out=%h valid=%b err=%b",
                     data_out, data_valid, decode_err);
            fail_cnt = fail_cnt + 1;
        end

        @(negedge clk);
        pam4_en = 1'b1;

        tc = 3;
        $display("\n[TC%0d] All Gray-00 -> binary 00", tc);
        fill_gray_128(2'b00);
        begin : tc3_blk
            reg [127:0] g;
            reg [255:0] b;
            g = fill_result_128;
            fill_bin_256(2'b00);
            b = fill_result_256;
            apply_and_check(g, 1'b1, 1'b1, b, 1'b1, 1'b0, "Gray00->Bin00");
        end

        tc = 4;
        $display("\n[TC%0d] All Gray-01 -> binary 01", tc);
        fill_gray_128(2'b01);
        begin : tc4_blk
            reg [127:0] g;
            reg [255:0] b;
            g = fill_result_128;
            fill_bin_256(2'b01);
            b = fill_result_256;
            apply_and_check(g, 1'b1, 1'b1, b, 1'b1, 1'b0, "Gray01->Bin01");
        end

        tc = 5;
        $display("\n[TC%0d] All Gray-11 -> binary 10", tc);
        fill_gray_128(2'b11);
        begin : tc5_blk
            reg [127:0] g;
            reg [255:0] b;
            g = fill_result_128;
            fill_bin_256(2'b10);
            b = fill_result_256;
            apply_and_check(g, 1'b1, 1'b1, b, 1'b1, 1'b0, "Gray11->Bin10");
        end

        tc = 6;
        $display("\n[TC%0d] All Gray-10 -> binary 11", tc);
        fill_gray_128(2'b10);
        begin : tc6_blk
            reg [127:0] g;
            reg [255:0] b;
            g = fill_result_128;
            fill_bin_256(2'b11);
            b = fill_result_256;
            apply_and_check(g, 1'b1, 1'b1, b, 1'b1, 1'b0, "Gray10->Bin11");
        end

        tc = 7;
        $display("\n[TC%0d] Mixed pattern (00,01,11,10 repeating)", tc);
        mixed_gray    = 128'b0;
        mixed_bin_exp = 256'b0;
        for (j = 0; j < 64; j = j + 4) begin
            mixed_gray[j*2     +: 2] = 2'b00;
            mixed_gray[(j+1)*2 +: 2] = 2'b01;
            mixed_gray[(j+2)*2 +: 2] = 2'b11;
            mixed_gray[(j+3)*2 +: 2] = 2'b10;

            mixed_bin_exp[j*2     +: 2] = 2'b00;
            mixed_bin_exp[(j+1)*2 +: 2] = 2'b01;
            mixed_bin_exp[(j+2)*2 +: 2] = 2'b10;
            mixed_bin_exp[(j+3)*2 +: 2] = 2'b11;
        end
        apply_and_check(mixed_gray, 1'b1, 1'b1,
                        mixed_bin_exp, 1'b1, 1'b0, "MixedPattern ");

        tc = 8;
        $display("\n[TC%0d] valid de-asserted: data_valid must follow", tc);
        @(negedge clk);
        pam4_valid      = 1'b0;
        pam4_symbols_in = 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
        @(posedge clk); #1;
        @(posedge clk); #1;
        if (data_valid === 1'b0) begin
            $display("  PASS  data_valid=0 when pam4_valid=0");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  data_valid should be 0, got %b", data_valid);
            fail_cnt = fail_cnt + 1;
        end

        tc = 9;
        $display("\n[TC%0d] Back-to-back cycles: pipeline continuity", tc);

        fill_gray_128(2'b01); s0 = fill_result_128;
        fill_gray_128(2'b11); s1 = fill_result_128;

        @(negedge clk);
        pam4_symbols_in = s0;
        pam4_valid      = 1'b1;
        pam4_en         = 1'b1;
        @(posedge clk); #1;
        fill_bin_256(2'b01);
        if (data_out[127:0] === fill_result_256[127:0] &&
            data_out[255:128] === 128'b0 &&
            data_valid === 1'b1) begin
            $display("  PASS  Pipeline Cycle A output correct");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  Pipeline Cycle A: got data_out[127:0]=%h",
                     data_out[127:0]);
            fail_cnt = fail_cnt + 1;
        end

        @(negedge clk);
        pam4_symbols_in = s1;
        @(posedge clk); #1;
        fill_bin_256(2'b10);
        if (data_out[127:0] === fill_result_256[127:0] &&
            data_valid === 1'b1) begin
            $display("  PASS  Pipeline Cycle B output correct");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  Pipeline Cycle B: got data_out[127:0]=%h",
                     data_out[127:0]);
            fail_cnt = fail_cnt + 1;
        end

        $display("\n==============================================");
        $display(" Results: %0d PASS  |  %0d FAIL", pass_cnt, fail_cnt);
        $display("==============================================");
        if (fail_cnt == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" *** FAILURES DETECTED ***");

        #20;
        $finish;
    end

    initial begin
        $dumpfile("pam4_gray_code_decoder_tb.vcd");
        $dumpvars(0, pam4_gray_code_decoder_tb);
    end

endmodule
