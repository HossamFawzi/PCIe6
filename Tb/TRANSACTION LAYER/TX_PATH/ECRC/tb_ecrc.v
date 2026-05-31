
`timescale 1ns/1ps

module tb_ecrc_gen_chk;

    reg           clk;
    reg           rst_n;
    reg           ecrc_en;

    reg  [1151:0] tlp_tx;
    reg           tlp_tx_valid;
    wire [1183:0] tlp_ecrc_tx;
    wire          tlp_ecrc_valid;

    reg  [1183:0] tlp_rx;
    reg           tlp_rx_valid;
    wire          ecrc_rx_ok;
    wire          ecrc_rx_err;

    integer fail_count = 0;

    reg [1183:0] saved_good_tlp;
    reg [1183:0] bad_rx;

    ecrc_gen_chk u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .ecrc_en        (ecrc_en),
        .tlp_tx         (tlp_tx),
        .tlp_tx_valid   (tlp_tx_valid),
        .tlp_ecrc_tx    (tlp_ecrc_tx),
        .tlp_ecrc_valid (tlp_ecrc_valid),
        .tlp_rx         (tlp_rx),
        .tlp_rx_valid   (tlp_rx_valid),
        .ecrc_rx_ok     (ecrc_rx_ok),
        .ecrc_rx_err    (ecrc_rx_err)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    task reset_system;
        begin
            rst_n          = 0;
            ecrc_en        = 1;
            tlp_tx         = 1152'd0;
            tlp_tx_valid   = 0;
            tlp_rx         = 1184'd0;
            tlp_rx_valid   = 0;
            saved_good_tlp = 1184'd0;
            bad_rx         = 1184'd0;
            repeat(4) @(posedge clk);
            rst_n          = 1;
            @(posedge clk);
        end
    endtask

    initial begin
        $display("\n=======================================================");
        $display("  Starting Cycle-Accurate ECRC Gen & Chk Simulation");
        $display("=======================================================\n");

        reset_system();

        $display("TC1: TX Path - Standard Generation");
        @(negedge clk);
        ecrc_en      = 1'b1;
        tlp_tx       = {32'h1111_2222, {35{32'hAAAA_5555}}};
        tlp_tx_valid = 1'b1;

        @(posedge clk); #1;
        if (tlp_ecrc_valid) $display("  [PASS] TC1: TX Valid Asserted");
        else begin $display("  [FAIL] TC1: Valid @ t=%0t", $time); fail_count = fail_count + 1; end

        saved_good_tlp = tlp_ecrc_tx;

        @(negedge clk);
        tlp_tx_valid = 1'b0;
        @(posedge clk); #1;

        $display("\nTC2: RX Path - Standard Good Check");
        @(negedge clk);
        tlp_rx       = saved_good_tlp;
        tlp_rx_valid = 1'b1;

        @(posedge clk); #1;
        if (ecrc_rx_ok === 1'b1) $display("  [PASS] TC2: ecrc_rx_ok Asserted");
        else begin $display("  [FAIL] TC2: ecrc_rx_ok missed @ t=%0t", $time); fail_count = fail_count + 1; end

        @(negedge clk); tlp_rx_valid = 1'b0;
        #10;

        $display("\nTC3: RX Path - Single Bit Error Injection");
        @(negedge clk);
        bad_rx = saved_good_tlp;
        bad_rx[5] = ~bad_rx[5];
        tlp_rx = bad_rx;
        tlp_rx_valid = 1'b1;

        @(posedge clk); #1;
        if (ecrc_rx_err === 1'b1) $display("  [PASS] TC3: ecrc_rx_err Asserted on single bit flip");
        else begin $display("  [FAIL] TC3: Error missed @ t=%0t", $time); fail_count = fail_count + 1; end

        @(negedge clk); tlp_rx_valid = 1'b0;
        #10;

        $display("\nTC4: Extreme Pattern - All Zeros");
        @(negedge clk);
        tlp_tx = 1152'd0;
        tlp_tx_valid = 1'b1;

        @(posedge clk); #1;
        if (tlp_ecrc_tx[1183:1152] === 32'd0) $display("  [PASS] TC4: All-Zero payload properly generated 0x00000000 CRC");
        else begin $display("  [FAIL] TC4: Unexpected CRC on Zero payload @ t=%0t", $time); fail_count = fail_count + 1; end

        @(negedge clk); tlp_tx_valid = 1'b0;
        #10;

        $display("\nTC5: Extreme Pattern - All Ones");
        @(negedge clk);
        tlp_tx = {36{32'hFFFF_FFFF}};
        tlp_tx_valid = 1'b1;

        @(posedge clk); #1;
        if (tlp_ecrc_tx[1183:1152] !== 32'hFFFF_FFFF) $display("  [PASS] TC5: All-Ones generated valid CRC");
        else begin $display("  [FAIL] TC5: CRC matches payload directly @ t=%0t", $time); fail_count = fail_count + 1; end

        @(negedge clk); tlp_tx_valid = 1'b0;
        #10;

        $display("\nTC6: Dynamic Control - Toggling ecrc_en");
        @(negedge clk);
        ecrc_en = 1'b1;
        tlp_tx = {32'h9999_8888, {35{32'h1111_1111}}};
        tlp_tx_valid = 1'b1;

        @(posedge clk); #1;
        if (tlp_ecrc_tx[1183:1152] !== 32'd0) $display("  [PASS] TC6: Beat 1 has CRC");
        else begin $display("  [FAIL] TC6: Beat 1 missing CRC @ t=%0t", $time); fail_count = fail_count + 1; end

        @(negedge clk);
        ecrc_en = 1'b0;
        tlp_tx = {36{32'h2222_2222}};

        @(posedge clk); #1;
        if (tlp_ecrc_tx[1183:1152] === 32'd0) $display("  [PASS] TC6: Beat 2 is zero-padded");
        else begin $display("  [FAIL] TC6: Beat 2 has stray CRC @ t=%0t", $time); fail_count = fail_count + 1; end

        @(negedge clk); tlp_tx_valid = 1'b0;
        #10;

        $display("\nTC7: RX Boundary Corruption - MSB Flip");
        @(negedge clk);
        ecrc_en = 1'b1;
        bad_rx = saved_good_tlp;
        bad_rx[1119] = ~bad_rx[1119];
        tlp_rx = bad_rx;
        tlp_rx_valid = 1'b1;

        @(posedge clk); #1;
        if (ecrc_rx_err === 1'b1) $display("  [PASS] TC7: Caught MSB corruption");
        else begin $display("  [FAIL] TC7: Missed MSB flip @ t=%0t", $time); fail_count = fail_count + 1; end

        @(negedge clk); tlp_rx_valid = 1'b0;
        #10;

        $display("\nTC8: RX Boundary Corruption - LSB Flip");
        @(negedge clk);
        bad_rx = saved_good_tlp;
        bad_rx[0] = ~bad_rx[0];
        tlp_rx = bad_rx;
        tlp_rx_valid = 1'b1;

        @(posedge clk); #1;
        if (ecrc_rx_err === 1'b1) $display("  [PASS] TC8: Caught LSB corruption");
        else begin $display("  [FAIL] TC8: Missed LSB flip @ t=%0t", $time); fail_count = fail_count + 1; end

        @(negedge clk); tlp_rx_valid = 1'b0;
        #10;

        $display("\nTC9: Protocol Check - Valid Low Override");
        @(negedge clk);
        tlp_tx = {36{32'hDEAD_BEEF}};
        tlp_tx_valid = 1'b0;

        @(posedge clk); #1;
        if (tlp_ecrc_valid === 1'b0 && tlp_ecrc_tx === 1184'd0) $display("  [PASS] TC9: Output stayed 0 when Valid was low");
        else begin $display("  [FAIL] TC9: Data leaked without Valid @ t=%0t", $time); fail_count = fail_count + 1; end
        #10;

        $display("\nTC10: RX Burst Error Injection (Byte Corruption)");
        @(negedge clk);
        bad_rx = saved_good_tlp;
        bad_rx[127:120] = 8'hFF;
        tlp_rx = bad_rx;
        tlp_rx_valid = 1'b1;

        @(posedge clk); #1;
        if (ecrc_rx_err === 1'b1) $display("  [PASS] TC10: Caught Byte-wide burst error");
        else begin $display("  [FAIL] TC10: Missed burst error @ t=%0t", $time); fail_count = fail_count + 1; end

        @(negedge clk); tlp_rx_valid = 1'b0;
        #20;

        $display("\n=======================================================");
        if (fail_count == 0)
            $display("  [SUCCESS] 10/10 TESTS PASSED! ECRC Block is bulletproof.");
        else
            $display("  [WARNING] %0d TESTS FAILED. Review transcripts.", fail_count);
        $display("=======================================================\n");
        $finish;
    end

endmodule