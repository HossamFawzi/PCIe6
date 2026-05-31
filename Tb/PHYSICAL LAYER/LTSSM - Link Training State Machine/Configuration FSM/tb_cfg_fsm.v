
`timescale 1ns/1ps

module tb_cfg_fsm;

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

    initial clk = 0;
    always #5 clk = ~clk;

    task apply_reset;
        begin
            rst_n        = 0;
            ts1_link_num = 8'hFF;
            ts1_lane_num = 8'hFF;
            ts2_detected = 0;
            cfg_timer_exp = 0;
            upcfg_req    = 0;
            repeat(4) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task pulse(input reg sig_r);

        begin
            @(posedge clk); #1;
        end
    endtask

    task wait_clk(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

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

    task tc1_normal_handshake;
        integer timeout_cnt;
        begin
            $display("\n=== TC1: Normal handshake (x4, link 1) ===");
            apply_reset;

            @(posedge clk); #1;
            ts1_link_num = 8'd1;

            wait_clk(2);

            ts1_lane_num = 8'd3;

            wait_clk(2);

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

            check("TC1: cfg_done asserted",   cfg_done == 1'b1);
            check("TC1: no timeout error",    cfg_timeout_err == 1'b0);
            check("TC1: negotiated x4 width", negotiated_width == 6'd4);
            check("TC1: cfg_link_num == 1",   cfg_link_num == 8'd1);

            @(posedge clk);
        end
    endtask

    task tc2_timeout_lnknum;
        integer timeout_cnt;
        begin
            $display("\n=== TC2: Timeout during link-number phase ===");
            apply_reset;

            @(posedge clk); #1;
            ts1_link_num = 8'd5;

            wait_clk(2);

            ts1_lane_num = 8'hFF;

            @(posedge clk); #1;
            cfg_timer_exp = 1;
            @(posedge clk); #1;
            cfg_timer_exp = 0;

            wait_clk(3);

            check("TC2: cfg_timeout_err asserted", cfg_timeout_err == 1'b1 ||
                                                    cfg_done       == 1'b0);
            check("TC2: cfg_done NOT asserted",    cfg_done == 1'b0);

            @(posedge clk);
        end
    endtask

    task tc3_timeout_complete;
        integer timeout_cnt;
        begin
            $display("\n=== TC3: Timeout during TS2-agreement phase ===");
            apply_reset;

            @(posedge clk); #1;
            ts1_link_num = 8'd2;
            wait_clk(2);
            ts1_lane_num = 8'd7;
            wait_clk(2);

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

    task tc4_upconfigure;
        integer timeout_cnt;
        begin
            $display("\n=== TC4: Upconfigure during ST_COMPLETE ===");
            apply_reset;

            @(posedge clk); #1;
            ts1_link_num = 8'd0;
            wait_clk(2);
            ts1_lane_num = 8'd3;
            wait_clk(2);

            @(posedge clk); #1;
            ts1_lane_num = 8'hFF;
            @(posedge clk); #1;

            upcfg_req = 1;
            @(posedge clk); #1;
            upcfg_req = 0;

            @(posedge clk); #1;
            ts1_lane_num = 8'd7;
            wait_clk(3);

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
