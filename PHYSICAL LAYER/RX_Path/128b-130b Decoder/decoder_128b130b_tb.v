//============================================================
// Testbench: decoder_128b130b_tb
// PCIe 6.0 Physical Link Layer - 128b/130b Decoder
// Compatible with ModelSim / QuestaSim / Icarus Verilog
//============================================================
`timescale 1ns/1ps

module decoder_128b130b_tb;

    // -------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------
    reg          clk;
    reg          rst_n;
    reg  [129:0] data_in;
    reg  [1:0]   sync_hdr;
    reg          dec_en;

    wire [127:0] data_out;
    wire         block_type;
    wire         dec_err;
    wire         sync_hdr_err;

    // -------------------------------------------------------
    // Instantiate DUT - Gen6 (sync_hdr_err bypassed)
    // -------------------------------------------------------
    decoder_128b130b #(.PCIE_GEN(6)) DUT_GEN6 (
        .clk         (clk),
        .rst_n       (rst_n),
        .data_in     (data_in),
        .sync_hdr    (sync_hdr),
        .dec_en      (dec_en),
        .data_out    (data_out),
        .block_type  (block_type),
        .dec_err     (dec_err),
        .sync_hdr_err(sync_hdr_err)
    );

    // -------------------------------------------------------
    // Instantiate second DUT - Gen5 (sync_hdr_err active)
    // -------------------------------------------------------
    wire [127:0] data_out_g5;
    wire         block_type_g5;
    wire         dec_err_g5;
    wire         sync_hdr_err_g5;

    decoder_128b130b #(.PCIE_GEN(5)) DUT_GEN5 (
        .clk         (clk),
        .rst_n       (rst_n),
        .data_in     (data_in),
        .sync_hdr    (sync_hdr),
        .dec_en      (dec_en),
        .data_out    (data_out_g5),
        .block_type  (block_type_g5),
        .dec_err     (dec_err_g5),
        .sync_hdr_err(sync_hdr_err_g5)
    );

    // -------------------------------------------------------
    // Clock: 500 MHz (2 ns period)
    // -------------------------------------------------------
    initial clk = 0;
    always  #1 clk = ~clk;

    // -------------------------------------------------------
    // Test counters
    // -------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;
    integer test_num;

    // -------------------------------------------------------
    // Task: apply one cycle and check GEN6 DUT outputs
    // -------------------------------------------------------
    task apply_and_check_g6;
        input [129:0] din;
        input [1:0]   sh;
        input         en;
        input [127:0] exp_data;
        input         exp_btype;
        input         exp_dec_err;
        input         exp_sh_err;
        input [127:0] label;
        begin
            @(negedge clk);
            data_in  = din;
            sync_hdr = sh;
            dec_en   = en;
            @(posedge clk);
            #0.5;
            test_num = test_num + 1;
            if (en) begin
                if ((data_out    === exp_data)    &&
                    (block_type  === exp_btype)   &&
                    (dec_err     === exp_dec_err) &&
                    (sync_hdr_err=== exp_sh_err)) begin
                    $display("[PASS] Test %0d (GEN6|%s): data_out=0x%032h block=%b dec_err=%b sh_err=%b",
                             test_num, label, data_out, block_type, dec_err, sync_hdr_err);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] Test %0d (GEN6|%s):", test_num, label);
                    $display("       Expected: data=0x%032h btype=%b dec_err=%b sh_err=%b",
                             exp_data, exp_btype, exp_dec_err, exp_sh_err);
                    $display("       Got:      data=0x%032h btype=%b dec_err=%b sh_err=%b",
                             data_out, block_type, dec_err, sync_hdr_err);
                    fail_cnt = fail_cnt + 1;
                end
            end
        end
    endtask

    // -------------------------------------------------------
    // Task: apply one cycle and check GEN5 DUT outputs
    // -------------------------------------------------------
    task apply_and_check_g5;
        input [129:0] din;
        input [1:0]   sh;
        input         en;
        input [127:0] exp_data;
        input         exp_btype;
        input         exp_dec_err;
        input         exp_sh_err;
        input [127:0] label;
        begin
            @(negedge clk);
            data_in  = din;
            sync_hdr = sh;
            dec_en   = en;
            @(posedge clk);
            #0.5;
            test_num = test_num + 1;
            if (en) begin
                if ((data_out_g5    === exp_data)    &&
                    (block_type_g5  === exp_btype)   &&
                    (dec_err_g5     === exp_dec_err) &&
                    (sync_hdr_err_g5=== exp_sh_err)) begin
                    $display("[PASS] Test %0d (GEN5|%s): data_out=0x%032h block=%b dec_err=%b sh_err=%b",
                             test_num, label, data_out_g5, block_type_g5, dec_err_g5, sync_hdr_err_g5);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] Test %0d (GEN5|%s):", test_num, label);
                    $display("       Expected: data=0x%032h btype=%b dec_err=%b sh_err=%b",
                             exp_data, exp_btype, exp_dec_err, exp_sh_err);
                    $display("       Got:      data=0x%032h btype=%b dec_err=%b sh_err=%b",
                             data_out_g5, block_type_g5, dec_err_g5, sync_hdr_err_g5);
                    fail_cnt = fail_cnt + 1;
                end
            end
        end
    endtask

    // -------------------------------------------------------
    // Task: reset both DUTs
    // -------------------------------------------------------
    task do_reset;
        begin
            rst_n    = 1'b0;
            data_in  = 130'h0;
            sync_hdr = 2'b01;
            dec_en   = 1'b0;
            repeat(4) @(posedge clk);
            #0.1;
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------
    // Helper: build 130-bit block {sh[1:0], payload[127:0]}
    // -------------------------------------------------------
    function [129:0] make_block;
        input [1:0]   sh;
        input [127:0] payload;
        begin
            make_block = {sh, payload};
        end
    endfunction

    // -------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        test_num = 0;

        $display("========================================================");
        $display(" PCIe 6.0 PHY - 128b/130b Decoder Testbench");
        $display(" ModelSim / QuestaSim / Icarus Compatible");
        $display("========================================================");

        do_reset;
        $display("\n--- Reset Complete ---\n");

        // ============================================================
        // GROUP 1: Valid Data Blocks (sync_hdr = 2'b01)
        //          GEN6 DUT: no sh_err, no dec_err, block_type=0
        // ============================================================
        $display("--- Group 1: Valid Data Blocks (SH=01, GEN6) ---");

        // All-zero payload
        apply_and_check_g6(
            make_block(2'b01, 128'h0),
            2'b01, 1,
            128'h0, 0, 0, 0,
            "DATA_all0");

        // All-ones payload
        apply_and_check_g6(
            make_block(2'b01, 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF),
            2'b01, 1,
            128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, 0, 0, 0,
            "DATA_allF");

        // Walking-one payload
        apply_and_check_g6(
            make_block(2'b01, 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0),
            2'b01, 1,
            128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0, 0, 0, 0,
            "DATA_pattern");

        // Alternating 0x55/0xAA
        apply_and_check_g6(
            make_block(2'b01, 128'h5555_5555_5555_5555_AAAA_AAAA_AAAA_AAAA),
            2'b01, 1,
            128'h5555_5555_5555_5555_AAAA_AAAA_AAAA_AAAA, 0, 0, 0,
            "DATA_55AA");

        // ============================================================
        // GROUP 2: Valid Ordered Set Blocks (sync_hdr = 2'b10)
        //          GEN6 DUT: no sh_err, no dec_err, block_type=1
        // ============================================================
        $display("\n--- Group 2: Valid Ordered Set Blocks (SH=10, GEN6) ---");

        // SKP ordered set pattern
        apply_and_check_g6(
            make_block(2'b10, 128'hAA55_AA55_AA55_AA55_AA55_AA55_AA55_AA55),
            2'b10, 1,
            128'hAA55_AA55_AA55_AA55_AA55_AA55_AA55_AA55, 1, 0, 0,
            "OS_SKP_pattern");

        // All-zero ordered set
        apply_and_check_g6(
            make_block(2'b10, 128'h0),
            2'b10, 1,
            128'h0, 1, 0, 0,
            "OS_all0");

        // EIEOS pattern (all 0xFF bytes alternating)
        apply_and_check_g6(
            make_block(2'b10, 128'hFF00_FF00_FF00_FF00_FF00_FF00_FF00_FF00),
            2'b10, 1,
            128'hFF00_FF00_FF00_FF00_FF00_FF00_FF00_FF00, 1, 0, 0,
            "OS_EIEOS");

        // ============================================================
        // GROUP 3: sync_hdr Mismatch (port vs embedded in data_in)
        //          data_in[129:128] != sync_hdr port -> dec_err=1
        //          GEN6: sync_hdr_err still=0, dec_err=1 (mismatch)
        // ============================================================
        $display("\n--- Group 3: Sync Header Mismatch (GEN6) ---");

        // sync_hdr port says 01 but data_in[129:128]=10
        apply_and_check_g6(
            {2'b10, 128'hABCD_EF01_2345_6789_ABCD_EF01_2345_6789},
            2'b01, 1,
            128'hABCD_EF01_2345_6789_ABCD_EF01_2345_6789, 0, 1, 0,
            "MISMATCH_10vs01");

        // sync_hdr port says 10 but data_in[129:128]=01
        apply_and_check_g6(
            {2'b01, 128'h1111_2222_3333_4444_5555_6666_7777_8888},
            2'b10, 1,
            128'h1111_2222_3333_4444_5555_6666_7777_8888, 1, 1, 0,
            "MISMATCH_01vs10");

        // ============================================================
        // GROUP 4: Invalid Sync Headers - GEN6 (error bypassed)
        //          sync_hdr=00 or 11 -> GEN6: sh_err=0, dec_err=0
        //          (only mismatch check active)
        // ============================================================
        $display("\n--- Group 4: Invalid Sync Header - GEN6 (bypassed) ---");

        // SH=00 consistent (data_in[129:128]=00): no mismatch, sh bypassed -> dec_err=0
        apply_and_check_g6(
            {2'b00, 128'h1234_5678_9ABC_DEF0_FEDC_BA98_7654_3210},
            2'b00, 1,
            128'h1234_5678_9ABC_DEF0_FEDC_BA98_7654_3210, 0, 0, 0,
            "INV_SH00_G6");

        // SH=11 consistent: no mismatch, sh bypassed -> dec_err=0
        apply_and_check_g6(
            {2'b11, 128'hFFFF_0000_FFFF_0000_FFFF_0000_FFFF_0000},
            2'b11, 1,
            128'hFFFF_0000_FFFF_0000_FFFF_0000_FFFF_0000, 0, 0, 0,
            "INV_SH11_G6");

        // ============================================================
        // GROUP 5: Invalid Sync Headers - GEN5 (error active)
        //          sync_hdr=00 -> sh_err=1, dec_err=1
        //          sync_hdr=11 -> sh_err=1, dec_err=1
        // ============================================================
        $display("\n--- Group 5: Invalid Sync Header - GEN5 (error active) ---");

        // SH=00 consistent: sh_err=1, dec_err=1
        apply_and_check_g5(
            {2'b00, 128'h1234_5678_9ABC_DEF0_FEDC_BA98_7654_3210},
            2'b00, 1,
            128'h1234_5678_9ABC_DEF0_FEDC_BA98_7654_3210, 0, 1, 1,
            "INV_SH00_G5");

        // SH=11 consistent: sh_err=1, dec_err=1
        apply_and_check_g5(
            {2'b11, 128'hFFFF_0000_FFFF_0000_FFFF_0000_FFFF_0000},
            2'b11, 1,
            128'hFFFF_0000_FFFF_0000_FFFF_0000_FFFF_0000, 0, 1, 1,
            "INV_SH11_G5");

        // Valid SH=01 in GEN5: no errors
        apply_and_check_g5(
            make_block(2'b01, 128'hABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD),
            2'b01, 1,
            128'hABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD, 0, 0, 0,
            "VALID_SH01_G5");

        // Valid SH=10 in GEN5: no errors
        apply_and_check_g5(
            make_block(2'b10, 128'hDEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD),
            2'b10, 1,
            128'hDEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD, 1, 0, 0,
            "VALID_SH10_G5");

        // ============================================================
        // GROUP 6: dec_en = 0 (decoder disabled)
        //          dec_err and sync_hdr_err must be 0
        // ============================================================
        $display("\n--- Group 6: Decoder Disabled (dec_en=0) ---");

        begin
            @(negedge clk);
            data_in  = {2'b11, 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0};
            sync_hdr = 2'b11;
            dec_en   = 1'b0;
            @(posedge clk);
            #0.5;
            test_num = test_num + 1;
            if (dec_err === 1'b0 && sync_hdr_err === 1'b0) begin
                $display("[PASS] Test %0d (GEN6|DISABLED): dec_err=0 sh_err=0 as expected", test_num);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Test %0d (GEN6|DISABLED): expected no errors when dec_en=0, got dec_err=%b sh_err=%b",
                         test_num, dec_err, sync_hdr_err);
                fail_cnt = fail_cnt + 1;
            end
        end

        begin
            @(negedge clk);
            data_in  = {2'b00, 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0};
            sync_hdr = 2'b00;
            dec_en   = 1'b0;
            @(posedge clk);
            #0.5;
            test_num = test_num + 1;
            if (dec_err_g5 === 1'b0 && sync_hdr_err_g5 === 1'b0) begin
                $display("[PASS] Test %0d (GEN5|DISABLED): dec_err=0 sh_err=0 as expected", test_num);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Test %0d (GEN5|DISABLED): expected no errors when dec_en=0, got dec_err=%b sh_err=%b",
                         test_num, dec_err_g5, sync_hdr_err_g5);
                fail_cnt = fail_cnt + 1;
            end
        end

        // ============================================================
        // GROUP 7: Reset during operation
        // ============================================================
        $display("\n--- Group 7: Reset During Operation ---");

        @(negedge clk);
        data_in  = make_block(2'b01, 128'hDEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF);
        sync_hdr = 2'b01;
        dec_en   = 1'b1;
        @(posedge clk);
        #0.1;
        rst_n = 1'b0;
        @(posedge clk);
        #0.5;
        test_num = test_num + 1;
        if (data_out      === 128'h0 &&
            block_type    === 1'b0   &&
            dec_err       === 1'b0   &&
            sync_hdr_err  === 1'b0) begin
            $display("[PASS] Test %0d (GEN6|RESET): All outputs cleared on reset", test_num);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Test %0d (GEN6|RESET): data=0x%032h btype=%b dec_err=%b sh_err=%b",
                     test_num, data_out, block_type, dec_err, sync_hdr_err);
            fail_cnt = fail_cnt + 1;
        end
        rst_n = 1'b1;
        @(posedge clk);

        // ============================================================
        // GROUP 8: Continuous streaming - interleaved data and OS blocks
        // ============================================================
        $display("\n--- Group 8: Continuous Streaming (GEN6) ---");

        begin : stream_blk
            integer i;
            reg [129:0] scodes [0:7];
            reg [127:0] sexp   [0:7];
            reg         sbtype [0:7];

            scodes[0] = make_block(2'b01, 128'h0000_0000_0000_0000_0000_0000_0000_0001);
            scodes[1] = make_block(2'b10, 128'hFF00_FF00_FF00_FF00_FF00_FF00_FF00_FF00);
            scodes[2] = make_block(2'b01, 128'h0000_0000_0000_0000_0000_0000_0000_0002);
            scodes[3] = make_block(2'b10, 128'hAA55_AA55_AA55_AA55_AA55_AA55_AA55_AA55);
            scodes[4] = make_block(2'b01, 128'hDEAD_BEEF_CAFE_BABE_0000_0000_0000_0004);
            scodes[5] = make_block(2'b01, 128'h1234_5678_9ABC_DEF0_FEDC_BA98_7654_3210);
            scodes[6] = make_block(2'b10, 128'h0000_0000_FFFF_FFFF_0000_0000_FFFF_FFFF);
            scodes[7] = make_block(2'b01, 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFE);

            sexp[0]   = 128'h0000_0000_0000_0000_0000_0000_0000_0001;
            sexp[1]   = 128'hFF00_FF00_FF00_FF00_FF00_FF00_FF00_FF00;
            sexp[2]   = 128'h0000_0000_0000_0000_0000_0000_0000_0002;
            sexp[3]   = 128'hAA55_AA55_AA55_AA55_AA55_AA55_AA55_AA55;
            sexp[4]   = 128'hDEAD_BEEF_CAFE_BABE_0000_0000_0000_0004;
            sexp[5]   = 128'h1234_5678_9ABC_DEF0_FEDC_BA98_7654_3210;
            sexp[6]   = 128'h0000_0000_FFFF_FFFF_0000_0000_FFFF_FFFF;
            sexp[7]   = 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFE;

            sbtype[0] = 0; sbtype[1] = 1; sbtype[2] = 0; sbtype[3] = 1;
            sbtype[4] = 0; sbtype[5] = 0; sbtype[6] = 1; sbtype[7] = 0;

            for (i = 0; i < 8; i = i + 1) begin
                @(negedge clk);
                data_in  = scodes[i];
                sync_hdr = scodes[i][129:128];
                dec_en   = 1'b1;
                @(posedge clk);
                #0.5;
                test_num = test_num + 1;
                if (data_out  === sexp[i]   &&
                    block_type=== sbtype[i] &&
                    dec_err   === 1'b0      &&
                    sync_hdr_err === 1'b0) begin
                    $display("[PASS] Test %0d (GEN6|Stream[%0d]): data_out=0x%032h btype=%b",
                             test_num, i, data_out, block_type);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] Test %0d (GEN6|Stream[%0d]): exp=0x%032h btype=%b dec_err=%b sh_err=%b",
                             test_num, i, sexp[i], sbtype[i], dec_err, sync_hdr_err);
                    $display("                                     got=0x%032h btype=%b dec_err=%b sh_err=%b",
                             data_out, block_type, dec_err, sync_hdr_err);
                    fail_cnt = fail_cnt + 1;
                end
            end
        end

        // ============================================================
        // GROUP 9: Back-to-back invalid SH in GEN5 (consecutive errors)
        // ============================================================
        $display("\n--- Group 9: Back-to-Back Invalid SH in GEN5 ---");

        begin : bb_blk
            integer j;
            reg [1:0] bad_sh [0:3];
            bad_sh[0] = 2'b00;
            bad_sh[1] = 2'b11;
            bad_sh[2] = 2'b00;
            bad_sh[3] = 2'b11;
            for (j = 0; j < 4; j = j + 1) begin
                @(negedge clk);
                sync_hdr = bad_sh[j];
                data_in  = {bad_sh[j], 128'hBAAD_F00D_BAADF00D_BAADF00D_BAADF00D};
                dec_en   = 1'b1;
                @(posedge clk);
                #0.5;
                test_num = test_num + 1;
                if (dec_err_g5 === 1'b1 && sync_hdr_err_g5 === 1'b1) begin
                    $display("[PASS] Test %0d (GEN5|BadSH[%0d]=2'b%02b): dec_err=1 sh_err=1",
                             test_num, j, bad_sh[j]);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] Test %0d (GEN5|BadSH[%0d]=2'b%02b): expected dec_err=1 sh_err=1, got dec_err=%b sh_err=%b",
                             test_num, j, bad_sh[j], dec_err_g5, sync_hdr_err_g5);
                    fail_cnt = fail_cnt + 1;
                end
            end
        end

        // ============================================================
        // SUMMARY
        // ============================================================
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
        #50000;
        $display("[TIMEOUT] Simulation exceeded limit");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("decoder_128b130b_waves.vcd");
        $dumpvars(0, decoder_128b130b_tb);
    end

endmodule
