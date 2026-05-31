
`timescale 1ns/1ps

module tb_recv_fsm;

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

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt;
    integer fail_cnt;
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
    end

    task check;
        input [255:0] msg;
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

    task wait_clk;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    task tc1_normal_recovery;
        integer timeout_cnt;
        begin
            $display("\n=== TC1: Normal Recovery (RcvrLock->RcvrCfg->Idle->Done) ===");
            apply_reset;

            @(posedge clk); #1;
            recv_req = 1;
            @(posedge clk); #1;
            recv_req = 0;

            wait_clk(2);
            check("TC1: send_ts1 in RcvrLock     ", send_ts1 == 1'b1);

            @(posedge clk); #1;
            ts1_detected = 1;
            @(posedge clk); #1;
            ts1_detected = 0;

            wait_clk(2);
            check("TC1: send_ts2 in RcvrCfg      ", send_ts2 == 1'b1);

            ts2_detected = 1;
            wait_clk(1);
            ts2_detected = 0;
            wait_clk(1);
            ts2_detected = 1;
            wait_clk(1);
            ts2_detected = 0;

            wait_clk(2);
            @(posedge clk); #1;
            idle_detected = 1;
            @(posedge clk); #1;
            idle_detected = 0;

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

    task tc2_speed_change;
        integer timeout_cnt;
        begin
            $display("\n=== TC2: Recovery with speed change in RcvrCfg ===");
            apply_reset;

            @(posedge clk); #1;
            recv_req = 1;
            @(posedge clk); #1;
            recv_req = 0;

            wait_clk(1);
            ts1_detected = 1;
            wait_clk(1);
            ts1_detected = 0;

            wait_clk(2);
            speed_change_req = 1;
            @(posedge clk); #1;
            speed_change_req = 0;

            wait_clk(2);
            check("TC2: speed_change_en asserted  ", speed_change_en == 1'b1);

            wait_clk(1);
            ts1_detected = 1;
            wait_clk(1);
            ts1_detected = 0;

            wait_clk(1);
            ts2_detected = 1;
            wait_clk(1);
            ts2_detected = 0;
            wait_clk(1);
            ts2_detected = 1;
            wait_clk(1);
            ts2_detected = 0;

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

    task tc3_timeout_lock;
        begin
            $display("\n=== TC3: Timeout in RcvrLock ===");
            apply_reset;

            @(posedge clk); #1;
            recv_req = 1;
            @(posedge clk); #1;
            recv_req = 0;

            wait_clk(3);
            recv_timer_exp = 1;
            @(posedge clk); #1;
            recv_timer_exp = 0;

            wait_clk(2);
            check("TC3: recv_timeout_err asserted ", recv_timeout_err == 1'b1);
            check("TC3: recv_done NOT asserted    ", recv_done        == 1'b0);

            @(posedge clk);
        end
    endtask

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

                wait_clk(2);
                if (retrain_req) got_retrain = 1;
            end

            check("TC4: retrain_req after 3 timeou", got_retrain == 1'b1);

            @(posedge clk);
        end
    endtask

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
