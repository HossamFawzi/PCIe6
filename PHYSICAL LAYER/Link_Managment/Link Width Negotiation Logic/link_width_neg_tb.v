`timescale 1ns/1ps

module link_width_neg_tb;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg  [7:0] ts1_lane_num;
    reg  [5:0] local_width_cap;
    reg        upcfg_req;
    reg  [5:0] ltssm_state;

    wire [5:0]  negotiated_width;
    wire        width_neg_done;
    wire [15:0] active_lanes;
    wire        width_change_req;

    link_width_neg dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .ts1_lane_num    (ts1_lane_num),
        .local_width_cap (local_width_cap),
        .upcfg_req       (upcfg_req),
        .ltssm_state     (ltssm_state),
        .negotiated_width(negotiated_width),
        .width_neg_done  (width_neg_done),
        .active_lanes    (active_lanes),
        .width_change_req(width_change_req)
    );

    // -----------------------------------------------------------------------
    // Clock: 250 MHz
    // -----------------------------------------------------------------------
    initial clk = 1'b0;
    always #2 clk = ~clk;

    // -----------------------------------------------------------------------
    // LTSSM state encoding (mirrors DUT)
    // -----------------------------------------------------------------------
    localparam ST_DETECT   = 6'h00;
    localparam ST_POLLING  = 6'h01;
    localparam ST_CONFIG   = 6'h02;
    localparam ST_RECOVERY = 6'h03;
    localparam ST_L0       = 6'h04;

    // -----------------------------------------------------------------------
    // Capability bitmask helpers
    // ts1 / local bit[4:0] = x16/x8/x4/x2/x1
    // -----------------------------------------------------------------------
    localparam P_X1  = 8'h01;   // partner: x1 only
    localparam P_X2  = 8'h03;   // partner: x1+x2
    localparam P_X4  = 8'h07;   // partner: x1+x2+x4
    localparam P_X8  = 8'h0F;   // partner: x1..x8
    localparam P_X16 = 8'h1F;   // partner: x1..x16

    localparam L_X1  = 6'h01;   // local:   x1 only
    localparam L_X2  = 6'h03;
    localparam L_X4  = 6'h07;
    localparam L_X8  = 6'h0F;
    localparam L_X16 = 6'h1F;

    // -----------------------------------------------------------------------
    // Bookkeeping
    // -----------------------------------------------------------------------
    integer fail_count;

    // -----------------------------------------------------------------------
    // Task: apply stimulus and settle
    // -----------------------------------------------------------------------
    task apply_and_wait;
        input [7:0] ts1;
        input [5:0] lcap;
        input       ureq;
        input [5:0] state;
        begin
            @(negedge clk);
            ts1_lane_num    = ts1;
            local_width_cap = lcap;
            upcfg_req       = ureq;
            ltssm_state     = state;
            repeat(4) @(posedge clk); #0.5;
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: full reset
    // -----------------------------------------------------------------------
    task do_reset;
        begin
            @(negedge clk);
            rst_n           = 1'b0;
            ts1_lane_num    = 8'h00;
            local_width_cap = 6'h00;
            upcfg_req       = 1'b0;
            ltssm_state     = ST_DETECT;
            repeat(4) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // MAIN
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("link_width_neg_tb.vcd");
        $dumpvars(0, link_width_neg_tb);

        fail_count      = 0;
        rst_n           = 1'b0;
        ts1_lane_num    = 8'h00;
        local_width_cap = 6'h00;
        upcfg_req       = 1'b0;
        ltssm_state     = ST_DETECT;

        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ================================================================
        // TEST 1 — Reset defaults: x1, not done, lane[0] only
        // ================================================================
        @(posedge clk); #0.5;
        if (negotiated_width === 6'd1  &&
            width_neg_done   === 1'b0  &&
            active_lanes     === 16'h0001 &&
            width_change_req === 1'b0)
            $display("PASS TEST 1: reset defaults correct");
        else begin
            $display("FAIL TEST 1: width=%0d done=%b lanes=%h chgreq=%b",
                      negotiated_width, width_neg_done, active_lanes, width_change_req);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 2 — x16: both sides fully capable, in Config
        // Expected: negotiated=16, done=1, active=0xFFFF
        // ================================================================
        apply_and_wait(P_X16, L_X16, 1'b0, ST_CONFIG);
        if (negotiated_width === 6'd16 &&
            width_neg_done   === 1'b1  &&
            active_lanes     === 16'hFFFF)
            $display("PASS TEST 2: x16 negotiation, lanes=%h", active_lanes);
        else begin
            $display("FAIL TEST 2: width=%0d done=%b lanes=%h",
                      negotiated_width, width_neg_done, active_lanes);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 3 — x16 in Recovery state (same result as Config)
        // ================================================================
        apply_and_wait(P_X16, L_X16, 1'b0, ST_RECOVERY);
        if (negotiated_width === 6'd16 && width_neg_done === 1'b1)
            $display("PASS TEST 3: x16 in Recovery, width=%0d done=%b",
                      negotiated_width, width_neg_done);
        else begin
            $display("FAIL TEST 3: width=%0d done=%b", negotiated_width, width_neg_done);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 4 — Fallback x8: local only supports up to x8
        // ================================================================
        apply_and_wait(P_X16, L_X8, 1'b0, ST_CONFIG);
        if (negotiated_width === 6'd8  &&
            width_neg_done   === 1'b1  &&
            active_lanes     === 16'h00FF)
            $display("PASS TEST 4: fallback x8, width=%0d lanes=%h",
                      negotiated_width, active_lanes);
        else begin
            $display("FAIL TEST 4: width=%0d (exp 8) done=%b lanes=%h",
                      negotiated_width, width_neg_done, active_lanes);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 5 — Fallback x4: partner only supports up to x4
        // ================================================================
        apply_and_wait(P_X4, L_X16, 1'b0, ST_CONFIG);
        if (negotiated_width === 6'd4  &&
            width_neg_done   === 1'b1  &&
            active_lanes     === 16'h000F)
            $display("PASS TEST 5: fallback x4, width=%0d lanes=%h",
                      negotiated_width, active_lanes);
        else begin
            $display("FAIL TEST 5: width=%0d (exp 4) done=%b lanes=%h",
                      negotiated_width, width_neg_done, active_lanes);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 6 — Fallback x2
        // ================================================================
        apply_and_wait(P_X2, L_X16, 1'b0, ST_CONFIG);
        if (negotiated_width === 6'd2  &&
            width_neg_done   === 1'b1  &&
            active_lanes     === 16'h0003)
            $display("PASS TEST 6: fallback x2, width=%0d lanes=%h",
                      negotiated_width, active_lanes);
        else begin
            $display("FAIL TEST 6: width=%0d (exp 2) done=%b lanes=%h",
                      negotiated_width, width_neg_done, active_lanes);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 7 — x1 only: both sides support only x1
        // ================================================================
        apply_and_wait(P_X1, L_X1, 1'b0, ST_CONFIG);
        if (negotiated_width === 6'd1  &&
            width_neg_done   === 1'b1  &&
            active_lanes     === 16'h0001)
            $display("PASS TEST 7: x1 only, width=%0d lanes=%h",
                      negotiated_width, active_lanes);
        else begin
            $display("FAIL TEST 7: width=%0d done=%b lanes=%h",
                      negotiated_width, width_neg_done, active_lanes);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 8 — No common capability: ts1 x2-only, local x4-only
        //          Expected: width_neg_done=0, default x1
        // ================================================================
        apply_and_wait(8'h02, 6'h04, 1'b0, ST_CONFIG);
        if (width_neg_done === 1'b0)
            $display("PASS TEST 8: no common cap, neg_done=0 width=%0d",
                      negotiated_width);
        else begin
            $display("FAIL TEST 8: expected neg_done=0, got %b width=%0d",
                      width_neg_done, negotiated_width);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 9 — Outside Config/Recovery (L0): neg_done and change_req = 0
        // ================================================================
        apply_and_wait(P_X16, L_X16, 1'b1, ST_L0);
        if (width_neg_done === 1'b0 && width_change_req === 1'b0)
            $display("PASS TEST 9: L0 state, done=%b change_req=%b",
                      width_neg_done, width_change_req);
        else begin
            $display("FAIL TEST 9: done=%b change_req=%b (exp both 0)",
                      width_neg_done, width_change_req);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 10 — Detect state: neg_done and change_req = 0
        // ================================================================
        apply_and_wait(P_X16, L_X16, 1'b1, ST_DETECT);
        if (width_neg_done === 1'b0 && width_change_req === 1'b0)
            $display("PASS TEST 10: Detect state, done=%b change_req=%b",
                      width_neg_done, width_change_req);
        else begin
            $display("FAIL TEST 10: done=%b change_req=%b (exp both 0)",
                      width_neg_done, width_change_req);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 11 — width_change_req: upcfg_req=1, multi-lane capable
        //           in Recovery → change_req asserted
        // ================================================================
        apply_and_wait(P_X16, L_X16, 1'b1, ST_RECOVERY);
        if (width_change_req === 1'b1 && width_neg_done === 1'b1)
            $display("PASS TEST 11: upcfg change_req=%b in Recovery", width_change_req);
        else begin
            $display("FAIL TEST 11: change_req=%b done=%b (exp 1/1)",
                      width_change_req, width_neg_done);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 12 — width_change_req: upcfg_req=0 → change_req=0
        // ================================================================
        apply_and_wait(P_X16, L_X16, 1'b0, ST_RECOVERY);
        if (width_change_req === 1'b0)
            $display("PASS TEST 12: upcfg_req=0, change_req=%b", width_change_req);
        else begin
            $display("FAIL TEST 12: change_req=%b (exp 0)", width_change_req);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 13 — width_change_req: upcfg_req=1 but only x1 common
        //           → no upconfigure possible → change_req=0
        // ================================================================
        apply_and_wait(P_X1, L_X1, 1'b1, ST_RECOVERY);
        if (width_change_req === 1'b0)
            $display("PASS TEST 13: upcfg=1 x1-only, change_req=%b (no upgrade possible)",
                      width_change_req);
        else begin
            $display("FAIL TEST 13: change_req=%b (exp 0, x1 only)", width_change_req);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 14 — active_lanes bitmap for each width
        // ================================================================
        begin : test14
            integer ok;
            ok = 1;

            apply_and_wait(P_X16, L_X16, 1'b0, ST_CONFIG);
            if (active_lanes !== 16'hFFFF) begin
                $display("FAIL TEST 14a: x16 lanes=%h exp=FFFF", active_lanes);
                ok = 0; fail_count = fail_count + 1;
            end

            apply_and_wait(P_X8, L_X16, 1'b0, ST_CONFIG);
            if (active_lanes !== 16'h00FF) begin
                $display("FAIL TEST 14b: x8 lanes=%h exp=00FF", active_lanes);
                ok = 0; fail_count = fail_count + 1;
            end

            apply_and_wait(P_X4, L_X16, 1'b0, ST_CONFIG);
            if (active_lanes !== 16'h000F) begin
                $display("FAIL TEST 14c: x4 lanes=%h exp=000F", active_lanes);
                ok = 0; fail_count = fail_count + 1;
            end

            apply_and_wait(P_X2, L_X16, 1'b0, ST_CONFIG);
            if (active_lanes !== 16'h0003) begin
                $display("FAIL TEST 14d: x2 lanes=%h exp=0003", active_lanes);
                ok = 0; fail_count = fail_count + 1;
            end

            apply_and_wait(P_X1, L_X16, 1'b0, ST_CONFIG);
            if (active_lanes !== 16'h0001) begin
                $display("FAIL TEST 14e: x1 lanes=%h exp=0001", active_lanes);
                ok = 0; fail_count = fail_count + 1;
            end

            if (ok)
                $display("PASS TEST 14: all active_lanes bitmaps correct");
        end

        // ================================================================
        // TEST 15 — Asymmetric: partner x8, local x16 → x8 (partner limits)
        // ================================================================
        apply_and_wait(P_X8, L_X16, 1'b0, ST_CONFIG);
        if (negotiated_width === 6'd8 && active_lanes === 16'h00FF)
            $display("PASS TEST 15: asymmetric x8/x16 → x8, lanes=%h", active_lanes);
        else begin
            $display("FAIL TEST 15: width=%0d (exp 8) lanes=%h",
                      negotiated_width, active_lanes);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 16 — Async reset mid-operation clears outputs
        // ================================================================
        apply_and_wait(P_X16, L_X16, 1'b1, ST_RECOVERY);
        @(negedge clk);
        rst_n = 1'b0;
        repeat(3) @(posedge clk); #0.5;
        if (negotiated_width === 6'd1  &&
            width_neg_done   === 1'b0  &&
            active_lanes     === 16'h0001 &&
            width_change_req === 1'b0)
            $display("PASS TEST 16: reset mid-op clears outputs");
        else begin
            $display("FAIL TEST 16: width=%0d done=%b lanes=%h chgreq=%b",
                      negotiated_width, width_neg_done, active_lanes, width_change_req);
            fail_count = fail_count + 1;
        end
        rst_n = 1'b1;

        // ================================================================
        // TEST 17 — Config holds target after returning to L0
        //           (negotiated_width preserved, done de-asserted)
        // ================================================================
        apply_and_wait(P_X16, L_X16, 1'b0, ST_CONFIG);
        // transition to L0
        apply_and_wait(P_X16, L_X16, 1'b0, ST_L0);
        if (negotiated_width === 6'd16 && width_neg_done === 1'b0)
            $display("PASS TEST 17: L0 holds width=%0d, done=0 (inactive)",
                      negotiated_width);
        else begin
            $display("FAIL TEST 17: width=%0d (exp 16) done=%b (exp 0)",
                      negotiated_width, width_neg_done);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 18 — Polling state: neg_done=0, width_change_req=0
        // ================================================================
        apply_and_wait(P_X16, L_X16, 1'b1, 6'h01);
        if (width_neg_done === 1'b0 && width_change_req === 1'b0)
            $display("PASS TEST 18: Polling state done=%b chgreq=%b",
                      width_neg_done, width_change_req);
        else begin
            $display("FAIL TEST 18: done=%b chgreq=%b (exp both 0)",
                      width_neg_done, width_change_req);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // SUMMARY
        // ================================================================
        repeat(4) @(posedge clk);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SIMULATION DONE — %0d TEST(S) FAILED", fail_count);

        $finish;
    end

    initial begin
        #50000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
