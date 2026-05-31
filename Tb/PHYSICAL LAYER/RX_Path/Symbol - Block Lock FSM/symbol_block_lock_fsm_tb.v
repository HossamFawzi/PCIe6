`timescale 1ns/1ps

module symbol_block_lock_fsm_tb;

    reg         clk, rst_n;
    reg [255:0] rx_data;
    reg         rx_valid;
    reg [1:0]   sync_hdr;
    reg         com_detect;
    reg         lock_timer_exp;

    wire        symbol_lock, block_lock, lock_err, lock_lost;

    integer pass_cnt, fail_cnt;

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

    initial clk = 1'b0;
    always  #5 clk = ~clk;

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

    task drive_com;
        begin
            #1 rx_valid = 1'b1; com_detect = 1'b1;
               sync_hdr = 2'b00;
            @(posedge clk); #1;
        end
    endtask

    task drive_no_com;
        begin
            #1 rx_valid = 1'b1; com_detect = 1'b0;
               sync_hdr = 2'b00;
            @(posedge clk); #1;
        end
    endtask

    task drive_sync;
        input [1:0] hdr;
        begin
            #1 rx_valid = 1'b1; sync_hdr = hdr; com_detect = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task drive_bad_sync;
        begin
            #1 rx_valid = 1'b1; sync_hdr = 2'b11; com_detect = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        pass_cnt = 0; fail_cnt = 0;
        rst_n = 0; rx_valid = 0; rx_data = 0;
        sync_hdr = 0; com_detect = 0; lock_timer_exp = 0;

        $display("========================================================");
        $display(" PCIe 6.0 PHY - Symbol / Block Lock FSM Testbench");
        $display("========================================================");

        $display("\n--- Group 1: Reset Check ---");
        do_reset;
        check_out(1, "RESET_ALL_ZERO", 0, 0, 0, 0);

        $display("\n--- Group 2: Symbol Lock Acquisition ---");
        do_reset;

        drive_com;
        check_out(2, "SYM_HUNT_cnt1", 0, 0, 0, 0);

        drive_com;
        check_out(3, "SYM_HUNT_cnt2", 0, 0, 0, 0);

        drive_com;
        check_out(4, "SYM_HUNT_cnt3", 0, 0, 0, 0);

        drive_com;
        check_out(5, "SYM_LOCKED", 1, 0, 0, 0);

        $display("\n--- Group 3: Symbol Lock Maintained With Single Miss ---");

        drive_com;
        check_out(6, "SYM_LOCK_GOOD", 1, 0, 0, 0);

        drive_no_com;
        check_out(7, "SYM_LOCK_MISS1", 1, 0, 0, 0);

        drive_com;
        check_out(8, "SYM_LOCK_RECOVER", 1, 0, 0, 0);

        $display("\n--- Group 4: Symbol Lock Lost ---");

        drive_no_com; check_out(9,  "SYM_MISS1", 1, 0, 0, 0);
        drive_no_com; check_out(10, "SYM_MISS2", 1, 0, 0, 0);
        drive_no_com; check_out(11, "SYM_MISS3", 1, 0, 0, 0);
        drive_no_com;
        check_out(12, "SYM_LOCK_LOST", 0, 0, 0, 1);

        @(posedge clk); #1;
        check_out(13, "SYM_LOCK_IDLE", 0, 0, 0, 0);

        $display("\n--- Group 5: Block Lock Acquisition ---");
        do_reset;

        drive_sync(2'b01); check_out(14, "BLK_HUNT_cnt1", 0, 0, 0, 0);
        drive_sync(2'b10); check_out(15, "BLK_HUNT_cnt2", 0, 0, 0, 0);
        drive_sync(2'b01); check_out(16, "BLK_HUNT_cnt3", 0, 0, 0, 0);
        drive_sync(2'b10); check_out(17, "BLK_LOCKED",    0, 1, 0, 0);

        $display("\n--- Group 6: Block Lock Lost ---");

        drive_bad_sync; check_out(18, "BLK_MISS1", 0, 1, 0, 0);
        drive_bad_sync; check_out(19, "BLK_MISS2", 0, 1, 0, 0);
        drive_bad_sync; check_out(20, "BLK_MISS3", 0, 1, 0, 0);
        drive_bad_sync;
        check_out(21, "BLK_LOCK_LOST", 0, 0, 0, 1);

        @(posedge clk); #1;
        check_out(22, "BLK_LOCK_IDLE", 0, 0, 0, 0);

        $display("\n--- Group 7: Lock Timer Expiry During SYM_HUNT ---");
        do_reset;

        drive_com;
        drive_com;
        check_out(23, "SYM_HUNT_PRE_TMR", 0, 0, 0, 0);

        #1 lock_timer_exp = 1'b1;
        @(posedge clk); #1;
        check_out(24, "SYM_HUNT_TMR_ERR", 0, 0, 1, 0);

        #1 lock_timer_exp = 1'b0;
        @(posedge clk); #1;
        check_out(25, "SYM_ERR_CLEARED", 0, 0, 0, 0);

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

        $display("\n--- Group 9: rx_valid=0 Freezes Counter ---");
        do_reset;

        drive_com;
        drive_com;
        check_out(29, "SYM_HUNT_CNT2_PRE", 0, 0, 0, 0);

        #1 rx_valid = 1'b0; com_detect = 1'b0;
        @(posedge clk); #1;
        check_out(30, "SYM_HUNT_VALID0", 0, 0, 0, 0);

        @(posedge clk); #1;
        check_out(31, "SYM_HUNT_VALID0_2", 0, 0, 0, 0);

        drive_com;
        drive_com;
        check_out(32, "SYM_LOCKED_RESUMED", 1, 0, 0, 0);

        $display("\n--- Group 10: Bad Sync Hdr Resets BLK_HUNT Count ---");
        do_reset;

        drive_sync(2'b01);
        drive_sync(2'b10);
        check_out(33, "BLK_HUNT_CNT2", 0, 0, 0, 0);

        drive_bad_sync;
        check_out(34, "BLK_HUNT_BAD_RST", 0, 0, 0, 0);

        drive_sync(2'b01);
        drive_sync(2'b10);
        drive_sync(2'b01);
        drive_sync(2'b10);
        check_out(35, "BLK_LOCKED_AGAIN", 0, 1, 0, 0);

        #1 rx_valid = 0; com_detect = 0; sync_hdr = 0; lock_timer_exp = 0;
        repeat(3) @(posedge clk);

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
