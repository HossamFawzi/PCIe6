// ============================================================
//  Testbench: flit_sync_hdr_gen_checker_tb
//  QuestaSim / ModelSim compatible (Verilog-2001)
// ============================================================
//
//  Test plan:
//    TC1  - Reset: all outputs zero
//    TC2  - TX data FLIT: sync_hdr_tx=01, payload intact
//    TC3  - TX ordered-set FLIT: sync_hdr_tx=10
//    TC4  - RX valid header 01: rx_ok=1, rx_err=0
//    TC5  - RX valid header 10: rx_ok=1, rx_err=0
//    TC6  - RX invalid header 00: rx_ok=0, rx_err=1
//    TC7  - RX invalid header 11: rx_ok=0, rx_err=1
//    TC8  - Lock acquisition: 8 consecutive valid -> flit_lock=1
//    TC9  - Lock retention: valid headers keep lock
//    TC10 - Lock loss: 4 consecutive bad -> flit_lock=0
//    TC11 - Lock counter resets on bad header before lock
//    TC12 - flit_tx_with_hdr payload integrity
// ============================================================

`timescale 1ns/1ps

module flit_sync_hdr_gen_checker_tb;

    // ----------------------------------------------------------
    // Clock
    // ----------------------------------------------------------
    localparam CLK_PERIOD = 10;

    reg clk;
    reg rst_n;

    // ----------------------------------------------------------
    // DUT ports
    // ----------------------------------------------------------
    reg  [2047:0] flit_tx;
    reg           flit_tx_valid;
    reg  [2047:0] flit_rx;
    reg  [1:0]    sync_hdr_rx;
    reg           flit_rx_valid;

    wire [2049:0] flit_tx_with_hdr;
    wire [1:0]    sync_hdr_tx;
    wire          sync_hdr_rx_ok;
    wire          sync_hdr_rx_err;
    wire          flit_lock;

    // ----------------------------------------------------------
    // Module-level variables (no declarations inside begin/end)
    // ----------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;
    integer k;              // general loop counter

    // ----------------------------------------------------------
    // DUT instance
    // ----------------------------------------------------------
    flit_sync_hdr_gen_checker dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .flit_tx          (flit_tx),
        .flit_tx_valid    (flit_tx_valid),
        .flit_rx          (flit_rx),
        .sync_hdr_rx      (sync_hdr_rx),
        .flit_rx_valid    (flit_rx_valid),
        .flit_tx_with_hdr (flit_tx_with_hdr),
        .sync_hdr_tx      (sync_hdr_tx),
        .sync_hdr_rx_ok   (sync_hdr_rx_ok),
        .sync_hdr_rx_err  (sync_hdr_rx_err),
        .flit_lock        (flit_lock)
    );

    // ----------------------------------------------------------
    // Clock generator
    // ----------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ----------------------------------------------------------
    // Task: wait_cycle
    // ----------------------------------------------------------
    task wait_cycle;
        begin
            @(posedge clk); #1;
        end
    endtask

    // ----------------------------------------------------------
    // Task: check_eq1 - compare 1-bit signal to expected
    // ----------------------------------------------------------
    task check_eq1;
        input        got;
        input        exp;
        input [95:0] label;    // 12-char ASCII
        begin
            if (got === exp) begin
                $display("  PASS  %0s: got=%b exp=%b", label, got, exp);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  %0s: got=%b exp=%b", label, got, exp);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ----------------------------------------------------------
    // Task: drive_rx - apply RX header for one cycle
    // ----------------------------------------------------------
    task drive_rx;
        input [1:0] hdr;
        input       valid;
        begin
            @(negedge clk);
            sync_hdr_rx   = hdr;
            flit_rx_valid = valid;
            @(posedge clk); #1;
        end
    endtask

    // ----------------------------------------------------------
    // Task: do_reset - apply reset then release
    // ----------------------------------------------------------
    task do_reset;
        begin
            @(negedge clk); rst_n = 1'b0;
            repeat(2) @(posedge clk); #1;
            @(negedge clk); rst_n = 1'b1;
            @(posedge clk); #1;
        end
    endtask

    // ----------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------
    initial begin
        $display("================================================");
        $display("  FLIT Sync Header Gen/Checker - TB Start");
        $display("================================================");

        pass_cnt      = 0;
        fail_cnt      = 0;
        flit_tx       = 2048'b0;
        flit_tx_valid = 1'b0;
        flit_rx       = 2048'b0;
        sync_hdr_rx   = 2'b00;
        flit_rx_valid = 1'b0;
        rst_n         = 1'b0;

        // ======================================================
        // TC1: Reset
        // ======================================================
        $display("\n[TC1] Reset: all outputs must be zero");
        repeat(4) @(posedge clk); #1;
        check_eq1(flit_lock,       1'b0, "flit_lock   ");
        check_eq1(sync_hdr_rx_ok,  1'b0, "rx_ok       ");
        check_eq1(sync_hdr_rx_err, 1'b0, "rx_err      ");
        check_eq1(sync_hdr_tx[1],  1'b0, "tx_hdr[1]   ");
        check_eq1(sync_hdr_tx[0],  1'b0, "tx_hdr[0]   ");

        @(negedge clk); rst_n = 1'b1;
        @(posedge clk); #1;

        // ======================================================
        // TC2: TX data FLIT -> sync_hdr_tx = 01, payload intact
        // ======================================================
        $display("\n[TC2] TX data FLIT: flit_tx_valid=1 -> sync_hdr_tx=01");
        @(negedge clk);
        flit_tx       = 2048'hA5A5;
        flit_tx_valid = 1'b1;
        @(posedge clk); #1;

        check_eq1(sync_hdr_tx == 2'b01, 1'b1, "tx_hdr==01  ");

        if (flit_tx_with_hdr[2047:0] === 2048'hA5A5 &&
            flit_tx_with_hdr[2049:2048] === 2'b01) begin
            $display("  PASS  flit_tx_with_hdr: header+payload correct");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  flit_tx_with_hdr mismatch");
            $display("        hdr=%b  payload_lo=%h",
                     flit_tx_with_hdr[2049:2048], flit_tx_with_hdr[15:0]);
            fail_cnt = fail_cnt + 1;
        end

        // ======================================================
        // TC3: TX ordered-set FLIT -> sync_hdr_tx = 10
        // ======================================================
        $display("\n[TC3] TX OS FLIT: flit_tx_valid=0 -> sync_hdr_tx=10");
        @(negedge clk);
        flit_tx_valid = 1'b0;
        @(posedge clk); #1;
        check_eq1(sync_hdr_tx == 2'b10, 1'b1, "tx_hdr==10  ");

        // ======================================================
        // TC4: RX valid header 01
        // ======================================================
        $display("\n[TC4] RX header=01 -> rx_ok=1 rx_err=0");
        drive_rx(2'b01, 1'b1);
        check_eq1(sync_hdr_rx_ok,  1'b1, "rx_ok       ");
        check_eq1(sync_hdr_rx_err, 1'b0, "rx_err      ");

        // ======================================================
        // TC5: RX valid header 10
        // ======================================================
        $display("\n[TC5] RX header=10 -> rx_ok=1 rx_err=0");
        drive_rx(2'b10, 1'b1);
        check_eq1(sync_hdr_rx_ok,  1'b1, "rx_ok       ");
        check_eq1(sync_hdr_rx_err, 1'b0, "rx_err      ");

        // ======================================================
        // TC6: RX invalid header 00
        // ======================================================
        $display("\n[TC6] RX header=00 -> rx_ok=0 rx_err=1");
        drive_rx(2'b00, 1'b1);
        check_eq1(sync_hdr_rx_ok,  1'b0, "rx_ok       ");
        check_eq1(sync_hdr_rx_err, 1'b1, "rx_err      ");

        // ======================================================
        // TC7: RX invalid header 11
        // ======================================================
        $display("\n[TC7] RX header=11 -> rx_ok=0 rx_err=1");
        drive_rx(2'b11, 1'b1);
        check_eq1(sync_hdr_rx_ok,  1'b0, "rx_ok       ");
        check_eq1(sync_hdr_rx_err, 1'b1, "rx_err      ");

        // ======================================================
        // TC8: Lock acquisition (LOCK_THR = 8)
        // ======================================================
        do_reset;
        $display("\n[TC8] Lock acquisition after 8 consecutive valid headers");

        // 7 valid -> must NOT be locked
        for (k = 0; k < 7; k = k + 1)
            drive_rx(2'b01, 1'b1);
        check_eq1(flit_lock, 1'b0, "lock after 7");

        // 8th valid -> locked
        drive_rx(2'b01, 1'b1);
        check_eq1(flit_lock, 1'b1, "lock after 8");

        // ======================================================
        // TC9: Lock retention
        // ======================================================
        $display("\n[TC9] Lock retained with continued valid headers");
        for (k = 0; k < 4; k = k + 1)
            drive_rx(2'b10, 1'b1);
        check_eq1(flit_lock, 1'b1, "lock retained");

        // ======================================================
        // TC10: Lock loss (UNLOCK_THR = 4)
        // ======================================================
        $display("\n[TC10] Lock loss after 4 consecutive bad headers");

        // 3 bad -> still locked
        for (k = 0; k < 3; k = k + 1)
            drive_rx(2'b00, 1'b1);
        check_eq1(flit_lock, 1'b1, "lock 3 bad  ");

        // 4th bad -> lock lost
        drive_rx(2'b11, 1'b1);
        check_eq1(flit_lock, 1'b0, "lock 4 bad  ");

        // ======================================================
        // TC11: Lock counter resets on bad header before lock
        // ======================================================
        do_reset;
        $display("\n[TC11] Lock counter resets on bad header before lock");

        // 4 valid
        for (k = 0; k < 4; k = k + 1)
            drive_rx(2'b01, 1'b1);

        // 1 bad -> resets lock_cnt
        drive_rx(2'b00, 1'b1);

        // 7 more valid -> still not locked (need 8 from restart)
        for (k = 0; k < 7; k = k + 1)
            drive_rx(2'b01, 1'b1);
        check_eq1(flit_lock, 1'b0, "lock 7 rst  ");

        // 8th valid after reset -> locked
        drive_rx(2'b01, 1'b1);
        check_eq1(flit_lock, 1'b1, "lock 8 rst  ");

        // ======================================================
        // TC12: flit_tx_with_hdr payload integrity
        // ======================================================
        $display("\n[TC12] flit_tx_with_hdr carries exact payload + header");
        @(negedge clk);
        flit_tx       = 2048'hDEAD_BEEF_1234_5678;
        flit_tx_valid = 1'b1;
        @(posedge clk); #1;

        if (flit_tx_with_hdr[2049:2048] === 2'b01 &&
            flit_tx_with_hdr[2047:0] === 2048'hDEAD_BEEF_1234_5678) begin
            $display("  PASS  Payload and header preserved correctly");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  Payload or header mismatch");
            $display("        hdr=%b  lo_bits=%h",
                     flit_tx_with_hdr[2049:2048],
                     flit_tx_with_hdr[63:0]);
            fail_cnt = fail_cnt + 1;
        end

        // ======================================================
        // Summary
        // ======================================================
        $display("\n================================================");
        $display("  Results: %0d PASS  |  %0d FAIL", pass_cnt, fail_cnt);
        $display("================================================");
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  *** FAILURES DETECTED ***");

        #20;
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("flit_sync_hdr_gen_checker_tb.vcd");
        $dumpvars(0, flit_sync_hdr_gen_checker_tb);
    end

endmodule
