`timescale 1ns/1ps
// ============================================================
//  PCIe 6.0 PHY - Symbol / Block Lock FSM Testbench
//  30 directed tests across 10 groups
//  LOCK_THRESH = MISS_THRESH = 4 (default parameters)
// ============================================================
module symbol_block_lock_fsm_tb;

    // --------------------------------------------------------
    //  DUT signals
    // --------------------------------------------------------
    reg         clk, rst_n;
    reg [255:0] rx_data;
    reg         rx_valid;
    reg [1:0]   sync_hdr;
    reg         com_detect;
    reg         lock_timer_exp;

    wire        symbol_lock, block_lock, lock_err, lock_lost;

    integer pass_cnt, fail_cnt;

    // --------------------------------------------------------
    //  DUT instantiation (LOCK_THRESH = MISS_THRESH = 4)
    // --------------------------------------------------------
    symbol_block_lock_fsm #(
        .LOCK_THRESH(4'd4),
        .MISS_THRESH(4'd4)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .rx_data       (rx_data),
        .rx_valid      (rx_valid),
        .sync_hdr      (sync_hdr),
        .com_detect    (com_detect),
        .lock_timer_exp(lock_timer_exp),
        .symbol_lock   (symbol_lock),
        .block_lock    (block_lock),
        .lock_err      (lock_err),
        .lock_lost     (lock_lost)
    );

    // 10 ns period
    initial clk = 1'b0;
    always  #5 clk = ~clk;

    // --------------------------------------------------------
    //  Task: check_out
    //    Call after @(posedge clk); #1
    // --------------------------------------------------------
    task check_out;
        input integer    tnum;
        input [8*24-1:0] tname;
        input            exp_sym, exp_blk, exp_err, exp_lost;
        begin
            if (symbol_lock !== exp_sym  ||
                block_lock  !== exp_blk  ||
                lock_err    !== exp_err  ||
                lock_lost   !== exp_lost) begin
                $display("[FAIL] Test %0d (%s)", tnum, tname);
                $display("  Exp: symbol_lock=%b block_lock=%b lock_err=%b lock_lost=%b",
                         exp_sym, exp_blk, exp_err, exp_lost);
                $display("  Got: symbol_lock=%b block_lock=%b lock_err=%b lock_lost=%b",
                         symbol_lock, block_lock, lock_err, lock_lost);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("[PASS] Test %0d (%s)", tnum, tname);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    // --------------------------------------------------------
    //  Task: do_reset
    // --------------------------------------------------------
    task do_reset;
        begin
            rst_n          = 1'b0;
            rx_valid       = 1'b0;
            rx_data        = 256'h0;
            sync_hdr       = 2'b00;
            com_detect     = 1'b0;
            lock_timer_exp = 1'b0;
            repeat(2) @(posedge clk);
            #1 rst_n = 1'b1;
            @(posedge clk); #1;
        end
    endtask

    // --------------------------------------------------------
    //  Task: drive_com  – one clock with com_detect
    // --------------------------------------------------------
    task drive_com;
        begin
            #1 rx_valid = 1'b1; com_detect = 1'b1;
               sync_hdr = 2'b00;
            @(posedge clk); #1;
        end
    endtask

    // --------------------------------------------------------
    //  Task: drive_no_com  – one clock without com_detect
    // --------------------------------------------------------
    task drive_no_com;
        begin
            #1 rx_valid = 1'b1; com_detect = 1'b0;
               sync_hdr = 2'b00;
            @(posedge clk); #1;
        end
    endtask

    // --------------------------------------------------------
    //  Task: drive_sync  – one clock with valid sync header
    // --------------------------------------------------------
    task drive_sync;
        input [1:0] hdr;
        begin
            #1 rx_valid = 1'b1; sync_hdr = hdr; com_detect = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    // --------------------------------------------------------
    //  Task: drive_bad_sync  – one clock with invalid sync hdr
    // --------------------------------------------------------
    task drive_bad_sync;
        begin
            #1 rx_valid = 1'b1; sync_hdr = 2'b11; com_detect = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    // --------------------------------------------------------
    //  Main test body
    // --------------------------------------------------------
    initial begin
        pass_cnt = 0; fail_cnt = 0;
        rst_n = 0; rx_valid = 0; rx_data = 0;
        sync_hdr = 0; com_detect = 0; lock_timer_exp = 0;

        $display("========================================================");
        $display(" PCIe 6.0 PHY - Symbol / Block Lock FSM Testbench");
        $display("========================================================");

        // ====================================================
        //  Group 1 : Reset – all outputs 0
        // ====================================================
        $display("\n--- Group 1: Reset Check ---");
        do_reset;
        check_out(1, "RESET_ALL_ZERO", 0, 0, 0, 0);

        // ====================================================
        //  Group 2 : Symbol lock acquisition (LOCK_THRESH=4)
        //  Need 4 consecutive com_detect events to lock
        // ====================================================
        $display("\n--- Group 2: Symbol Lock Acquisition ---");
        do_reset;

        // Event 1: IDLE -> SYM_HUNT, cnt=1
        drive_com;
        check_out(2, "SYM_HUNT_cnt1", 0, 0, 0, 0);

        // Event 2: cnt=2
        drive_com;
        check_out(3, "SYM_HUNT_cnt2", 0, 0, 0, 0);

        // Event 3: cnt=3 (== LOCK_THRESH-1=3 → lock next)
        drive_com;
        check_out(4, "SYM_HUNT_cnt3", 0, 0, 0, 0);

        // Event 4: cnt==LOCK_THRESH-1, transition → SYM_LOCK
        drive_com;
        check_out(5, "SYM_LOCKED", 1, 0, 0, 0);

        // ====================================================
        //  Group 3 : Symbol lock maintained; single miss < MISS_THRESH
        // ====================================================
        $display("\n--- Group 3: Symbol Lock Maintained With Single Miss ---");
        // Already in SYM_LOCK from Group 2

        // Good comma: stays locked, cnt stays 0
        drive_com;
        check_out(6, "SYM_LOCK_GOOD", 1, 0, 0, 0);

        // One miss: cnt=1, still locked
        drive_no_com;
        check_out(7, "SYM_LOCK_MISS1", 1, 0, 0, 0);

        // Comma recovers miss counter → cnt=0
        drive_com;
        check_out(8, "SYM_LOCK_RECOVER", 1, 0, 0, 0);

        // ====================================================
        //  Group 4 : Symbol lock lost (MISS_THRESH=4 misses)
        // ====================================================
        $display("\n--- Group 4: Symbol Lock Lost ---");
        // Still in SYM_LOCK, cnt=0

        drive_no_com; check_out(9,  "SYM_MISS1", 1, 0, 0, 0); // cnt=1
        drive_no_com; check_out(10, "SYM_MISS2", 1, 0, 0, 0); // cnt=2
        drive_no_com; check_out(11, "SYM_MISS3", 1, 0, 0, 0); // cnt=3
        drive_no_com;                                           // cnt=3==MISS_THRESH-1 → LOCK_LOST
        check_out(12, "SYM_LOCK_LOST", 0, 0, 0, 1);

        // LOCK_LOST → IDLE next cycle
        @(posedge clk); #1;
        check_out(13, "SYM_LOCK_IDLE", 0, 0, 0, 0);

        // ====================================================
        //  Group 5 : Block lock acquisition (LOCK_THRESH=4)
        // ====================================================
        $display("\n--- Group 5: Block Lock Acquisition ---");
        do_reset;

        drive_sync(2'b01); check_out(14, "BLK_HUNT_cnt1", 0, 0, 0, 0);
        drive_sync(2'b10); check_out(15, "BLK_HUNT_cnt2", 0, 0, 0, 0);
        drive_sync(2'b01); check_out(16, "BLK_HUNT_cnt3", 0, 0, 0, 0);
        drive_sync(2'b10); check_out(17, "BLK_LOCKED",    0, 1, 0, 0);

        // ====================================================
        //  Group 6 : Block lock lost (MISS_THRESH=4 bad hdrs)
        // ====================================================
        $display("\n--- Group 6: Block Lock Lost ---");
        // Still in BLK_LOCK, cnt=0

        drive_bad_sync; check_out(18, "BLK_MISS1", 0, 1, 0, 0); // cnt=1
        drive_bad_sync; check_out(19, "BLK_MISS2", 0, 1, 0, 0); // cnt=2
        drive_bad_sync; check_out(20, "BLK_MISS3", 0, 1, 0, 0); // cnt=3
        drive_bad_sync;                                          // cnt=3==MISS_THRESH-1 → LOCK_LOST
        check_out(21, "BLK_LOCK_LOST", 0, 0, 0, 1);

        @(posedge clk); #1;
        check_out(22, "BLK_LOCK_IDLE", 0, 0, 0, 0);

        // ====================================================
        //  Group 7 : Lock timer expiry during SYM_HUNT
        // ====================================================
        $display("\n--- Group 7: Lock Timer Expiry During SYM_HUNT ---");
        do_reset;

        // Enter SYM_HUNT
        drive_com;
        drive_com;
        check_out(23, "SYM_HUNT_PRE_TMR", 0, 0, 0, 0);

        // Timer fires
        #1 lock_timer_exp = 1'b1;
        @(posedge clk); #1;    // → IDLE, lock_err=1
        check_out(24, "SYM_HUNT_TMR_ERR", 0, 0, 1, 0);

        // lock_err clears next cycle (IDLE clears it)
        #1 lock_timer_exp = 1'b0;
        @(posedge clk); #1;
        check_out(25, "SYM_ERR_CLEARED", 0, 0, 0, 0);

        // ====================================================
        //  Group 8 : Lock timer expiry during BLK_HUNT
        // ====================================================
        $display("\n--- Group 8: Lock Timer Expiry During BLK_HUNT ---");
        do_reset;

        drive_sync(2'b01);
        drive_sync(2'b10);
        check_out(26, "BLK_HUNT_PRE_TMR", 0, 0, 0, 0);

        #1 lock_timer_exp = 1'b1;
        @(posedge clk); #1;
        check_out(27, "BLK_HUNT_TMR_ERR", 0, 0, 1, 0);

        #1 lock_timer_exp = 1'b0;
        @(posedge clk); #1;
        check_out(28, "BLK_ERR_CLEARED", 0, 0, 0, 0);

        // ====================================================
        //  Group 9 : rx_valid=0 freezes counter (no state change)
        // ====================================================
        $display("\n--- Group 9: rx_valid=0 Freezes Counter ---");
        do_reset;

        // Get to SYM_HUNT with cnt=2
        drive_com;
        drive_com;
        check_out(29, "SYM_HUNT_CNT2_PRE", 0, 0, 0, 0);

        // rx_valid=0: counter must not change, state stays SYM_HUNT
        #1 rx_valid = 1'b0; com_detect = 1'b0;
        @(posedge clk); #1;
        check_out(30, "SYM_HUNT_VALID0", 0, 0, 0, 0);

        // rx_valid=0 again – still hunting
        @(posedge clk); #1;
        check_out(31, "SYM_HUNT_VALID0_2", 0, 0, 0, 0);

        // Resume: cnt=2 after freeze; need 2 more coms to lock
        drive_com;                              // cnt: 2->3, still SYM_HUNT
        drive_com;                              // cnt=3==LOCK_THRESH-1 → SYM_LOCK
        check_out(32, "SYM_LOCKED_RESUMED", 1, 0, 0, 0);

        // ====================================================
        //  Group 10 : Invalid sync header in BLK_HUNT resets cnt
        // ====================================================
        $display("\n--- Group 10: Bad Sync Hdr Resets BLK_HUNT Count ---");
        do_reset;

        drive_sync(2'b01); // cnt=1
        drive_sync(2'b10); // cnt=2
        check_out(33, "BLK_HUNT_CNT2", 0, 0, 0, 0);

        // Bad header (11) resets count
        drive_bad_sync;
        check_out(34, "BLK_HUNT_BAD_RST", 0, 0, 0, 0);

        // Rebuild – cnt reset to 0 on bad hdr; need 4 syncs to lock
        drive_sync(2'b01); // cnt=0->1
        drive_sync(2'b10); // cnt=1->2
        drive_sync(2'b01); // cnt=2->3
        drive_sync(2'b10); // cnt=3==LOCK_THRESH-1 → BLK_LOCK
        check_out(35, "BLK_LOCKED_AGAIN", 0, 1, 0, 0);

        // ====================================================
        //  Cleanup
        // ====================================================
        #1 rx_valid = 0; com_detect = 0; sync_hdr = 0; lock_timer_exp = 0;
        repeat(3) @(posedge clk);

        // ====================================================
        //  Summary
        // ====================================================
        $display("\n========================================================");
        $display(" SIMULATION COMPLETE");
        $display(" Total Tests : %0d", pass_cnt + fail_cnt);
        $display(" PASSED      : %0d", pass_cnt);
        $display(" FAILED      : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display(" STATUS      : ALL TESTS PASSED");
        else
            $display(" STATUS      : SOME TESTS FAILED");
        $display("========================================================");

        $finish;
    end

endmodule
