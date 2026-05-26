// ============================================================
//  Testbench ? PCIe Gen6 Recovery FSM (RECV_FSM)
//  Verifies:
//    TC1 ? Normal recovery: lock ? cfg ? idle ? done
//    TC2 ? Recovery with speed change
//    TC3 ? Timeout in RcvrLock ? timeout error
//    TC4 ? Multiple timeouts ? retrain_req escalation
//
//  Compatible with: ModelSim, Questa, VCS, Xcelium, Icarus
//  Standard: Verilog-2001 (no SystemVerilog string type)
// ============================================================

`timescale 1ns/1ps

module tb_recv_fsm;

    // ?? DUT ports ?????????????????????????????????????????????
    reg  clk;
    reg  rst_n;
    reg  recv_req;
    reg  ts1_detected;
    reg  ts2_detected;
    reg  idle_detected;
    reg  speed_change_req;
    reg  eq_done;
    reg  recv_timer_exp;

    wire send_ts1;
    wire send_ts2;
    wire speed_change_en;
    wire eq_start;
    wire recv_done;
    wire recv_timeout_err;
    wire retrain_req;

    // ?? Instantiate DUT ???????????????????????????????????????
    recv_fsm DUT (
        .clk             (clk),
        .rst_n           (rst_n),
        .recv_req        (recv_req),
        .ts1_detected    (ts1_detected),
        .ts2_detected    (ts2_detected),
        .idle_detected   (idle_detected),
        .speed_change_req(speed_change_req),
        .eq_done         (eq_done),
        .recv_timer_exp  (recv_timer_exp),
        .send_ts1        (send_ts1),
        .send_ts2        (send_ts2),
        .speed_change_en (speed_change_en),
        .eq_start        (eq_start),
        .recv_done       (recv_done),
        .recv_timeout_err(recv_timeout_err),
        .retrain_req     (retrain_req)
    );

    // ?? Clock: 10 ns period (100 MHz) ?????????????????????????
    initial clk = 0;
    always #5 clk = ~clk;

    // ?? Pass/fail counters ????????????????????????????????????
    integer pass_cnt;
    integer fail_cnt;
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
    end

    // ?? check task ????????????????????????????????????????????
    //  msg is a 256-bit packed reg used as a fixed-width string.
    //  Assign string literals with left-justified ASCII encoding,
    //  e.g.  check("TC1: send_ts1 ok", condition);
    //  ModelSim/Questa accept string literals assigned to reg [N:0]
    //  via the standard Verilog string assignment rules.
    task check;
        input [255:0] msg;       // 32 characters max, ASCII packed
        input         condition;
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

    // ?? apply_reset task ??????????????????????????????????????
    task apply_reset;
        begin
            rst_n            = 0;
            recv_req         = 0;
            ts1_detected     = 0;
            ts2_detected     = 0;
            idle_detected    = 0;
            speed_change_req = 0;
            eq_done          = 0;
            recv_timer_exp   = 0;
            repeat(4) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    // ?? wait_clk task ?????????????????????????????????????????
    task wait_clk;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  TC1 ? Normal Recovery Path
    //  Flow: IDLE ? RCVR_LOCK ? RCVR_CFG ? RCVR_IDLE ? DONE
    // ?????????????????????????????????????????????????????????
    task tc1_normal_recovery;
        integer timeout_cnt;
        begin
            $display("\n=== TC1: Normal Recovery (RcvrLock->RcvrCfg->Idle->Done) ===");
            apply_reset;

            // Assert recv_req to enter Recovery
            @(posedge clk); #1;
            recv_req = 1;
            @(posedge clk); #1;
            recv_req = 0;

            // Registered outputs settle two cycles after state transition
            wait_clk(2);
            check("TC1: send_ts1 in RcvrLock     ", send_ts1 == 1'b1);

            // Partner responds with TS1 ? advance to RcvrCfg
            @(posedge clk); #1;
            ts1_detected = 1;
            @(posedge clk); #1;
            ts1_detected = 0;

            wait_clk(2);
            check("TC1: send_ts2 in RcvrCfg      ", send_ts2 == 1'b1);

            // Partner agrees with two TS2s to satisfy ts2_cnt == 2
            ts2_detected = 1;
            wait_clk(1);
            ts2_detected = 0;
            wait_clk(1);
            ts2_detected = 1;
            wait_clk(1);
            ts2_detected = 0;

            // In RCVR_IDLE ? assert electrical idle
            wait_clk(2);
            @(posedge clk); #1;
            idle_detected = 1;
            @(posedge clk); #1;
            idle_detected = 0;

            // Poll for recv_done (ST_DONE is a one-cycle pulse)
            timeout_cnt = 0;
            while (!recv_done && timeout_cnt < 20) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end

            check("TC1: recv_done asserted        ", recv_done       == 1'b1);
            check("TC1: no timeout error          ", recv_timeout_err == 1'b0);
            check("TC1: no retrain_req            ", retrain_req      == 1'b0);

            @(posedge clk);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  TC2 ? Recovery with Speed Change
    //  Flow: LOCK ? CFG ? SPEED ? LOCK ? CFG ? IDLE ? DONE
    // ?????????????????????????????????????????????????????????
    task tc2_speed_change;
        integer timeout_cnt;
        begin
            $display("\n=== TC2: Recovery with speed change in RcvrCfg ===");
            apply_reset;

            // Enter Recovery
            @(posedge clk); #1;
            recv_req = 1;
            @(posedge clk); #1;
            recv_req = 0;

            // Provide TS1 to advance to RcvrCfg
            wait_clk(1);
            ts1_detected = 1;
            wait_clk(1);
            ts1_detected = 0;

            // Trigger speed change instead of TS2 agreement
            wait_clk(2);
            speed_change_req = 1;
            @(posedge clk); #1;
            speed_change_req = 0;

            // Outputs are registered: need 2 cycles after state change
            wait_clk(2);
            check("TC2: speed_change_en asserted  ", speed_change_en == 1'b1);

            // FSM returns to RcvrLock after ST_SPEED ? provide TS1 again
            wait_clk(1);
            ts1_detected = 1;
            wait_clk(1);
            ts1_detected = 0;

            // RcvrCfg: provide 2 TS2s
            wait_clk(1);
            ts2_detected = 1;
            wait_clk(1);
            ts2_detected = 0;
            wait_clk(1);
            ts2_detected = 1;
            wait_clk(1);
            ts2_detected = 0;

            // RCVR_IDLE: assert electrical idle
            wait_clk(2);
            idle_detected = 1;
            wait_clk(1);
            idle_detected = 0;

            timeout_cnt = 0;
            while (!recv_done && timeout_cnt < 30) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end

            check("TC2: recv_done after spd change", recv_done == 1'b1);

            @(posedge clk);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  TC3 ? Timeout in ST_RCVR_LOCK
    // ?????????????????????????????????????????????????????????
    task tc3_timeout_lock;
        begin
            $display("\n=== TC3: Timeout in RcvrLock ===");
            apply_reset;

            @(posedge clk); #1;
            recv_req = 1;
            @(posedge clk); #1;
            recv_req = 0;

            // Do NOT drive ts1_detected ? let the timer fire instead
            wait_clk(3);
            recv_timer_exp = 1;
            @(posedge clk); #1;
            recv_timer_exp = 0;

            // Allow ST_TIMEOUT outputs to settle
            wait_clk(2);
            check("TC3: recv_timeout_err asserted ", recv_timeout_err == 1'b1);
            check("TC3: recv_done NOT asserted    ", recv_done        == 1'b0);

            @(posedge clk);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  TC4 ? Multiple Timeouts ? retrain_req Escalation
    //  retrain_cnt: 0?1 (1st timeout), 1?2 (2nd), 2?retrain (3rd)
    // ?????????????????????????????????????????????????????????
    task tc4_retrain_escalation;
        integer i;
        reg     got_retrain;
        begin
            $display("\n=== TC4: Three timeouts -> retrain_req escalation ===");
            apply_reset;
            got_retrain = 0;

            for (i = 0; i < 3; i = i + 1) begin
                @(posedge clk); #1;
                recv_req = 1;
                @(posedge clk); #1;
                recv_req = 0;

                wait_clk(3);
                recv_timer_exp = 1;
                @(posedge clk); #1;
                recv_timer_exp = 0;

                // Sample every cycle so single-cycle pulse is never missed
                wait_clk(2);
                if (retrain_req) got_retrain = 1;
            end

            check("TC4: retrain_req after 3 timeou", got_retrain == 1'b1);

            @(posedge clk);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  Top-level stimulus
    // ?????????????????????????????????????????????????????????
    initial begin
        $dumpfile("recv_fsm.vcd");
        $dumpvars(0, tb_recv_fsm);

        tc1_normal_recovery;
        tc2_speed_change;
        tc3_timeout_lock;
        tc4_retrain_escalation;

        $display("\n========================================");
        $display(" RESULTS: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("========================================\n");

        if (fail_cnt == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED -- review waveform");

        $finish;
    end

endmodule
