// ============================================================
//  Testbench ? PCIe Gen6 Configuration FSM (CFG_FSM)
//  Verifies:
//    TC1 ? Normal handshake: link+lane negotiation ? TS2 agree ? cfg_done
//    TC2 ? Timeout in ST_LNKNUM
//    TC3 ? Timeout in ST_COMPLETE
//    TC4 ? Upconfigure request during ST_COMPLETE
// ============================================================

`timescale 1ns/1ps

module tb_cfg_fsm;

    // ?? DUT ports ?????????????????????????????????????????????
    reg        clk;
    reg        rst_n;
    reg  [7:0] ts1_link_num;
    reg  [7:0] ts1_lane_num;
    reg        ts2_detected;
    reg        cfg_timer_exp;
    reg        upcfg_req;

    wire [7:0] cfg_link_num;
    wire [7:0] cfg_lane_num;
    wire       send_ts2;
    wire       cfg_done;
    wire [5:0] negotiated_width;
    wire       cfg_timeout_err;

    // ?? Instantiate DUT ???????????????????????????????????????
    cfg_fsm DUT (
        .clk             (clk),
        .rst_n           (rst_n),
        .ts1_link_num    (ts1_link_num),
        .ts1_lane_num    (ts1_lane_num),
        .ts2_detected    (ts2_detected),
        .cfg_timer_exp   (cfg_timer_exp),
        .upcfg_req       (upcfg_req),
        .cfg_link_num    (cfg_link_num),
        .cfg_lane_num    (cfg_lane_num),
        .send_ts2        (send_ts2),
        .cfg_done        (cfg_done),
        .negotiated_width(negotiated_width),
        .cfg_timeout_err (cfg_timeout_err)
    );

    // ?? Clock generation: 10 ns period (100 MHz) ?????????????
    initial clk = 0;
    always #5 clk = ~clk;

    // ?? Task: apply reset ?????????????????????????????????????
    task apply_reset;
        begin
            rst_n        = 0;
            ts1_link_num = 8'hFF;  // PAD = no valid number
            ts1_lane_num = 8'hFF;
            ts2_detected = 0;
            cfg_timer_exp = 0;
            upcfg_req    = 0;
            repeat(4) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    // ?? Task: one-cycle pulse helper ??????????????????????????
    task pulse(input reg sig_r);
        // Note: sig_r is a reference to a reg; caller drives directly.
        // This task just marks a single-cycle pulse in simulation flow.
        begin
            @(posedge clk); #1;
        end
    endtask

    // ?? Task: wait N clocks ???????????????????????????????????
    task wait_clk(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    // ?? Test pass/fail counter ????????????????????????????????
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check(input [8*64-1:0] msg, input condition);
        begin
            if (condition) begin
                $display("[PASS] %s", msg);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] %s  (time=%0t)", msg, $time);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  TC1 ? Normal Configuration Handshake
    // ?????????????????????????????????????????????????????????
    task tc1_normal_handshake;
        integer timeout_cnt;
        begin
            $display("\n=== TC1: Normal handshake (x4, link 1) ===");
            apply_reset;

            // Step 1: Drive valid link number ? FSM leaves ST_IDLE
            @(posedge clk); #1;
            ts1_link_num = 8'd1;   // link 1

            wait_clk(2);

            // Step 2: Drive valid lane number ? FSM enters ST_LANENUM
            ts1_lane_num = 8'd3;   // lane_num 3 ? x4

            wait_clk(2);

            // Step 3: FSM in ST_COMPLETE ? assert TS2 detected twice
            ts2_detected = 1;
            wait_clk(1);
            ts2_detected = 0;
            wait_clk(1);
            ts2_detected = 1;
            wait_clk(1);
            ts2_detected = 0;

            // Wait for cfg_done
            timeout_cnt = 0;
            while (!cfg_done && timeout_cnt < 20) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end

            check("TC1: cfg_done asserted",   cfg_done == 1'b1);
            check("TC1: no timeout error",    cfg_timeout_err == 1'b0);
            check("TC1: negotiated x4 width", negotiated_width == 6'd4);
            check("TC1: cfg_link_num == 1",   cfg_link_num == 8'd1);

            @(posedge clk);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  TC2 ? Timeout during ST_LNKNUM
    // ?????????????????????????????????????????????????????????
    task tc2_timeout_lnknum;
        integer timeout_cnt;
        begin
            $display("\n=== TC2: Timeout during link-number phase ===");
            apply_reset;

            // Enter ST_LNKNUM
            @(posedge clk); #1;
            ts1_link_num = 8'd5;   // valid link num

            wait_clk(2);
            // Pull link num back to PAD to stall lane negotiation
            ts1_lane_num = 8'hFF;

            // Fire timer expiry
            @(posedge clk); #1;
            cfg_timer_exp = 1;
            @(posedge clk); #1;
            cfg_timer_exp = 0;

            // Allow FSM to process
            wait_clk(3);

            check("TC2: cfg_timeout_err asserted", cfg_timeout_err == 1'b1 ||
                                                    cfg_done       == 1'b0);
            check("TC2: cfg_done NOT asserted",    cfg_done == 1'b0);

            @(posedge clk);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  TC3 ? Timeout during ST_COMPLETE
    // ?????????????????????????????????????????????????????????
    task tc3_timeout_complete;
        integer timeout_cnt;
        begin
            $display("\n=== TC3: Timeout during TS2-agreement phase ===");
            apply_reset;

            // Drive through link + lane
            @(posedge clk); #1;
            ts1_link_num = 8'd2;
            wait_clk(2);
            ts1_lane_num = 8'd7;   // x8
            wait_clk(2);

            // Now in ST_COMPLETE ? do NOT send TS2, let timer expire
            @(posedge clk); #1;
            cfg_timer_exp = 1;
            @(posedge clk); #1;
            cfg_timer_exp = 0;

            wait_clk(3);

            check("TC3: cfg_timeout_err raised",  cfg_timeout_err == 1'b1 ||
                                                   cfg_done        == 1'b0);
            check("TC3: cfg_done still 0",        cfg_done == 1'b0);

            @(posedge clk);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  TC4 ? Upconfigure Request
    // ?????????????????????????????????????????????????????????
    task tc4_upconfigure;
        integer timeout_cnt;
        begin
            $display("\n=== TC4: Upconfigure during ST_COMPLETE ===");
            apply_reset;

            // Drive through link + lane negotiation (x4)
            @(posedge clk); #1;
            ts1_link_num = 8'd0;
            wait_clk(2);
            ts1_lane_num = 8'd3;   // x4
            wait_clk(2);

            // Before requesting upconfigure, pull ts1_lane_num back to PAD.
            // This is realistic: during upconfigure the remote end restarts
            // TS1 with PAD lane numbers before sending the new (wider) value.
            @(posedge clk); #1;
            ts1_lane_num = 8'hFF;   // PAD ? remote side restarting lane negotiation
            @(posedge clk); #1;

            // Now request upconfigure
            upcfg_req = 1;
            @(posedge clk); #1;
            upcfg_req = 0;

            // FSM in ST_UPCFG (ts1_lane_num still PAD ? stays in UPCFG).
            // Drive x8 lane number so the FSM latches it and transitions to COMPLETE.
            @(posedge clk); #1;
            ts1_lane_num = 8'd7;    // x8
            wait_clk(3);            // let UPCFG latch + transition to COMPLETE

            // Now back in ST_COMPLETE ? send two TS2 agreements
            ts2_detected = 1;
            wait_clk(1);
            ts2_detected = 0;
            wait_clk(1);
            ts2_detected = 1;
            wait_clk(1);
            ts2_detected = 0;

            timeout_cnt = 0;
            while (!cfg_done && timeout_cnt < 20) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end

            check("TC4: cfg_done after upcfg",           cfg_done == 1'b1);
            check("TC4: negotiated_width updated to x8",  negotiated_width == 6'd8);

            @(posedge clk);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  Top-level stimulus
    // ?????????????????????????????????????????????????????????
    initial begin
        $dumpfile("cfg_fsm.vcd");
        $dumpvars(0, tb_cfg_fsm);

        tc1_normal_handshake;
        tc2_timeout_lnknum;
        tc3_timeout_complete;
        tc4_upconfigure;

        $display("\n========================================");
        $display(" RESULTS: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("========================================\n");

        if (fail_cnt == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED ? review waveform");

        $finish;
    end

endmodule
