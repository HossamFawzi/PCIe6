
`timescale 1ns/1ps

module tb_dllp_crc_chk;

    reg         clk;
    reg         rst_n;
    reg  [63:0] dllp_raw;
    reg         dllp_rx_valid;

    wire [47:0] dllp_body;
    wire        dllp_crc_ok;
    wire        dllp_crc_err;
    wire        dllp_valid_out;

    integer pass_count;
    integer fail_count;
    integer test_num;

    reg [47:0]  body_tc2;
    reg [15:0]  crc_tc2;
    reg [47:0]  body_tc3;
    reg [15:0]  crc_tc3;
    reg [15:0]  crc_tc9;
    reg [47:0]  body_tc11;
    reg [47:0]  body_tc12;
    reg [15:0]  crc_orig;
    reg [47:0]  body_tc13;
    reg [15:0]  crc_correct;
    reg [15:0]  crc_corrupted;
    reg [47:0]  burst_body;
    reg [15:0]  burst_crc;
    integer     burst_pass;
    integer     i;
    reg [47:0]  b1, b3;
    reg [15:0]  c1, c3, c_bad;
    integer     valid_count;
    integer     err_count;

    dllp_crc_chk u_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .dllp_raw      (dllp_raw),
        .dllp_rx_valid (dllp_rx_valid),
        .dllp_body     (dllp_body),
        .dllp_crc_ok   (dllp_crc_ok),
        .dllp_crc_err  (dllp_crc_err),
        .dllp_valid_out(dllp_valid_out)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("dllp_crc_chk.vcd");
        $dumpvars(0, tb_dllp_crc_chk);
    end

    function [15:0] ref_crc16;
        input [47:0] data;
        integer      byte_idx;
        integer      bit_idx;
        reg [15:0]   crc;
        reg          data_bit;
        reg          xor_flag;
        reg [7:0]    cur_byte;
        begin
            crc = 16'hFFFF;
            for (byte_idx = 5; byte_idx >= 0; byte_idx = byte_idx - 1) begin
                cur_byte = data[(byte_idx * 8) +: 8];
                for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                    data_bit = cur_byte[bit_idx];
                    xor_flag = crc[15] ^ data_bit;
                    crc      = crc << 1;
                    if (xor_flag) crc = crc ^ 16'h1021;
                end
            end
            ref_crc16 = crc;
        end
    endfunction

    task check;
        input        condition;
        input [255:0] label;
        begin
            test_num = test_num + 1;
            if (condition) begin
                $display("  [PASS] TC%0d: %s  (t=%0t)", test_num, label, $time);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] TC%0d: %s  (t=%0t) *** FAIL ***",
                         test_num, label, $time);
                $display("         dllp_body=%h  ok=%b  err=%b  valid=%b",
                         dllp_body, dllp_crc_ok, dllp_crc_err, dllp_valid_out);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task idle;
        input integer n;
        begin repeat(n) @(posedge clk); end
    endtask

    initial begin

        pass_count    = 0;
        fail_count    = 0;
        test_num      = 0;
        burst_pass    = 0;
        valid_count   = 0;
        err_count     = 0;
        i             = 0;
        rst_n         = 1'b0;
        dllp_raw      = 64'd0;
        dllp_rx_valid = 1'b0;
        body_tc2      = 48'd0;
        crc_tc2       = 16'd0;
        body_tc3      = 48'd0;
        crc_tc3       = 16'd0;
        crc_tc9       = 16'd0;
        body_tc11     = 48'd0;
        body_tc12     = 48'd0;
        crc_orig      = 16'd0;
        body_tc13     = 48'd0;
        crc_correct   = 16'd0;
        crc_corrupted = 16'd0;
        burst_body    = 48'd0;
        burst_crc     = 16'd0;
        b1 = 48'd0; b3 = 48'd0;
        c1 = 16'd0; c3 = 16'd0; c_bad = 16'd0;

        $display("\n================================================================");
        $display("  PCIe Gen6 DLL RX - Module 15: DLLP CRC Checker Testbench");
        $display("================================================================\n");

        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("[RESET] Released. Starting test cases.\n");

        $display("--- TC1: Basic correct DLLP ---");
        @(negedge clk);
        dllp_raw      = {ref_crc16(48'h40_12_34_56_78_9A), 48'h40_12_34_56_78_9A};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_ok    === 1'b1,                  "dllp_crc_ok on correct DLLP");
        check(dllp_valid_out === 1'b1,                  "dllp_valid_out on correct DLLP");
        check(dllp_crc_err   === 1'b0,                  "no dllp_crc_err on correct DLLP");
        check(dllp_body      === 48'h40_12_34_56_78_9A, "dllp_body matches input");
        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        idle(2);

        $display("\n--- TC2: Single bit flip in body ---");
        body_tc2    = 48'h50_AA_BB_CC_DD_EE;
        crc_tc2     = ref_crc16(body_tc2);
        body_tc2[7] = ~body_tc2[7];
        @(negedge clk);
        dllp_raw      = {crc_tc2, body_tc2};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_err   === 1'b1,  "dllp_crc_err on bit flip");
        check(dllp_crc_ok    === 1'b0,  "no dllp_crc_ok on bit flip");
        check(dllp_valid_out === 1'b0,  "no dllp_valid_out on error");
        check(dllp_body      === 48'd0, "dllp_body=0 on error (no leak)");
        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        idle(2);

        $display("\n--- TC3: Correct body, wrong CRC field ---");
        body_tc3 = 48'h60_11_22_33_44_55;
        crc_tc3  = ref_crc16(body_tc3) ^ 16'h0001;
        @(negedge clk);
        dllp_raw      = {crc_tc3, body_tc3};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_err   === 1'b1,  "dllp_crc_err on corrupted CRC field");
        check(dllp_valid_out === 1'b0,  "no valid_out when CRC field wrong");
        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        idle(2);

        $display("\n--- TC4: dllp_rx_valid=0 ---");
        @(negedge clk);
        dllp_raw      = 64'hDEAD_BEEF_CAFE_1234;
        dllp_rx_valid = 1'b0;
        @(posedge clk); #1;
        check(dllp_crc_ok    === 1'b0,  "no crc_ok when valid=0");
        check(dllp_crc_err   === 1'b0,  "no crc_err when valid=0");
        check(dllp_valid_out === 1'b0,  "no valid_out when valid=0");
        check(dllp_body      === 48'd0, "body=0 when valid=0");
        @(negedge clk);
        dllp_raw = 64'd0;
        idle(2);

        $display("\n--- TC5: Back-to-back two correct DLLPs ---");

        @(negedge clk);
        dllp_raw      = {ref_crc16(48'hC0_00_10_00_00_00), 48'hC0_00_10_00_00_00};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_ok    === 1'b1, "TC5 first DLLP: crc_ok");
        check(dllp_valid_out === 1'b1, "TC5 first DLLP: valid_out");

        @(negedge clk);
        dllp_raw      = {ref_crc16(48'hD0_00_20_00_00_00), 48'hD0_00_20_00_00_00};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_ok    === 1'b1, "TC5 second DLLP: crc_ok");
        check(dllp_valid_out === 1'b1, "TC5 second DLLP: valid_out");
        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        idle(2);

        $display("\n--- TC6: Alternating pass/fail/pass ---");

        @(negedge clk);
        dllp_raw      = {ref_crc16(48'h40_01_02_03_04_05), 48'h40_01_02_03_04_05};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_ok  === 1'b1, "TC6 pass1: crc_ok");
        check(dllp_crc_err === 1'b0, "TC6 pass1: no err");

        @(negedge clk);
        dllp_raw      = {ref_crc16(48'h50_06_07_08_09_0A) ^ 16'hDEAD,
                         48'h50_06_07_08_09_0A};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_err === 1'b1, "TC6 fail: crc_err");
        check(dllp_crc_ok  === 1'b0, "TC6 fail: no ok");

        @(negedge clk);
        dllp_raw      = {ref_crc16(48'h60_0B_0C_0D_0E_0F), 48'h60_0B_0C_0D_0E_0F};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_ok  === 1'b1, "TC6 pass2: crc_ok after fail");
        check(dllp_crc_err === 1'b0, "TC6 pass2: err cleared");
        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        idle(2);

        $display("\n--- TC7: All-zero body ---");
        @(negedge clk);
        dllp_raw      = {ref_crc16(48'h00_00_00_00_00_00), 48'h00_00_00_00_00_00};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_ok    === 1'b1,  "TC7: all-zero body passes");
        check(dllp_body      === 48'd0, "TC7: body is zero");
        check(dllp_valid_out === 1'b1,  "TC7: valid_out asserted");
        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        idle(2);

        $display("\n--- TC8: All-ones body ---");
        @(negedge clk);
        dllp_raw      = {ref_crc16(48'hFF_FF_FF_FF_FF_FF), 48'hFF_FF_FF_FF_FF_FF};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_ok    === 1'b1,                  "TC8: all-ones body passes");
        check(dllp_body      === 48'hFF_FF_FF_FF_FF_FF, "TC8: all-ones forwarded");
        check(dllp_valid_out === 1'b1,                  "TC8: valid_out asserted");
        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        idle(2);

        $display("\n--- TC9: Reset during operation ---");
        crc_tc9 = ref_crc16(48'h40_AA_BB_CC_DD_EE);
        @(negedge clk);
        dllp_raw      = {crc_tc9, 48'h40_AA_BB_CC_DD_EE};
        dllp_rx_valid = 1'b1;
        @(negedge clk);
        rst_n         = 1'b0;
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        @(posedge clk); #1;
        check(dllp_crc_ok    === 1'b0,  "TC9: crc_ok=0 during reset");
        check(dllp_crc_err   === 1'b0,  "TC9: crc_err=0 during reset");
        check(dllp_valid_out === 1'b0,  "TC9: valid_out=0 during reset");
        check(dllp_body      === 48'd0, "TC9: body=0 during reset");
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("[INFO] Reset released.");
        idle(2);

        $display("\n--- TC10: 1-cycle pulse check ---");
        @(negedge clk);
        dllp_raw      = {ref_crc16(48'h40_11_22_33_44_55), 48'h40_11_22_33_44_55};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_ok    === 1'b1, "TC10: crc_ok HIGH at N+1");
        check(dllp_valid_out === 1'b1, "TC10: valid_out HIGH at N+1");

        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        @(posedge clk); #1;
        check(dllp_crc_ok    === 1'b0, "TC10: crc_ok cleared N+2 (pulse)");
        check(dllp_valid_out === 1'b0, "TC10: valid_out cleared N+2 (pulse)");
        idle(2);

        $display("\n--- TC11: MSB of body flipped ---");
        body_tc11      = 48'h40_00_00_00_00_00;
        crc_orig       = ref_crc16(body_tc11);
        body_tc11[47]  = ~body_tc11[47];
        @(negedge clk);
        dllp_raw      = {crc_orig, body_tc11};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_err   === 1'b1,  "TC11: MSB flip caught");
        check(dllp_valid_out === 1'b0,  "TC11: no valid on MSB flip");
        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        idle(2);

        $display("\n--- TC12: LSB of body flipped ---");
        body_tc12     = 48'hFF_FF_FF_FF_FF_FE;
        crc_orig      = ref_crc16(body_tc12);
        body_tc12[0]  = ~body_tc12[0];
        @(negedge clk);
        dllp_raw      = {crc_orig, body_tc12};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_err   === 1'b1, "TC12: LSB flip caught");
        check(dllp_valid_out === 1'b0, "TC12: no valid on LSB flip");
        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        idle(2);

        $display("\n--- TC13: Only CRC field corrupted ---");
        body_tc13     = 48'h40_DE_AD_BE_EF_CA;
        crc_correct   = ref_crc16(body_tc13);
        crc_corrupted = crc_correct ^ 16'h8000;
        @(negedge clk);
        dllp_raw      = {crc_corrupted, body_tc13};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(dllp_crc_err   === 1'b1,  "TC13: CRC field MSB flip caught");
        check(dllp_body      === 48'd0, "TC13: body=0 when CRC corrupted");
        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        idle(2);

        $display("\n--- TC14: Burst of 8 correct DLLPs ---");
        burst_pass = 0;
        for (i = 0; i < 8; i = i + 1) begin
            burst_body = {8'h40, 8'h00, 8'h00, 16'd0, i[7:0]};
            burst_crc  = ref_crc16(burst_body);
            @(negedge clk);
            dllp_raw      = {burst_crc, burst_body};
            dllp_rx_valid = 1'b1;
            @(posedge clk); #1;
            if (dllp_crc_ok && dllp_valid_out) burst_pass = burst_pass + 1;
        end
        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        check(burst_pass === 8, "TC14: all 8 DLLPs in burst passed");
        idle(3);

        $display("\n--- TC15: correct/wrong/correct burst ---");
        valid_count = 0;
        err_count   = 0;
        b1    = 48'h40_01_02_03_04_05;
        b3    = 48'h60_06_07_08_09_0A;
        c1    = ref_crc16(b1);
        c3    = ref_crc16(b3);
        c_bad = ref_crc16(48'h50_FF_FF_FF_FF_FF) ^ 16'hBEEF;

        @(negedge clk);
        dllp_raw      = {c1, b1};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        if (dllp_valid_out) valid_count = valid_count + 1;

        @(negedge clk);
        dllp_raw      = {c_bad, 48'h50_FF_FF_FF_FF_FF};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        if (dllp_crc_err) err_count = err_count + 1;

        @(negedge clk);
        dllp_raw      = {c3, b3};
        dllp_rx_valid = 1'b1;
        @(posedge clk); #1;
        if (dllp_valid_out) valid_count = valid_count + 1;

        @(negedge clk);
        dllp_rx_valid = 1'b0;
        dllp_raw      = 64'd0;
        check(valid_count === 2, "TC15: exactly 2 valid_outs");
        check(err_count   === 1, "TC15: exactly 1 crc_err");
        idle(3);

        $display("\n================================================================");
        $display("  DLLP CRC Checker - Final Result");
        $display("  PASS = %0d  |  FAIL = %0d  |  TOTAL = %0d",
                 pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d TESTS FAILED ***", fail_count);
        $display("================================================================\n");
        $finish;
    end

    initial begin
        #100000;
        $display("[WATCHDOG] 100us — force finish.");
        $finish;
    end

endmodule
