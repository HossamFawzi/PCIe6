`timescale 1ns/1ps

module link_speed_neg_tb;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg  [7:0] ts1_speed_cap;
    reg  [7:0] ts2_speed_cap;
    reg  [7:0] local_speed_cap;
    reg        speed_change_req;
    reg  [5:0] ltssm_state;

    wire [3:0] target_speed;
    wire       speed_change_en;
    wire [7:0] adv_speed_cap;
    wire       speed_neg_done;

    link_speed_neg dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .ts1_speed_cap   (ts1_speed_cap),
        .ts2_speed_cap   (ts2_speed_cap),
        .local_speed_cap (local_speed_cap),
        .speed_change_req(speed_change_req),
        .ltssm_state     (ltssm_state),
        .target_speed    (target_speed),
        .speed_change_en (speed_change_en),
        .adv_speed_cap   (adv_speed_cap),
        .speed_neg_done  (speed_neg_done)
    );

    // -----------------------------------------------------------------------
    // Clock: 250 MHz
    // -----------------------------------------------------------------------
    initial clk = 1'b0;
    always #2 clk = ~clk;

    // -----------------------------------------------------------------------
    // LTSSM state encoding (mirrors DUT localparams)
    // -----------------------------------------------------------------------
    localparam ST_DETECT    = 6'h00;
    localparam ST_POLLING   = 6'h01;
    localparam ST_CONFIG    = 6'h02;
    localparam ST_RECOVERY  = 6'h03;
    localparam ST_L0        = 6'h04;

    // -----------------------------------------------------------------------
    // Speed capability bit masks
    // -----------------------------------------------------------------------
    localparam CAP_GEN1 = 8'h01;
    localparam CAP_GEN2 = 8'h03;
    localparam CAP_GEN3 = 8'h07;
    localparam CAP_GEN4 = 8'h0F;
    localparam CAP_GEN5 = 8'h1F;
    localparam CAP_GEN6 = 8'h3F;   // all Gen1-Gen6

    // Target speed expected values
    localparam SPD_GEN1 = 4'h1;
    localparam SPD_GEN2 = 4'h2;
    localparam SPD_GEN3 = 4'h3;
    localparam SPD_GEN4 = 4'h4;
    localparam SPD_GEN5 = 4'h5;
    localparam SPD_GEN6 = 4'h6;

    // -----------------------------------------------------------------------
    // Bookkeeping
    // -----------------------------------------------------------------------
    integer fail_count;

    // -----------------------------------------------------------------------
    // Task: apply inputs and wait 4 clock cycles for outputs to settle
    // -----------------------------------------------------------------------
    task apply_and_wait;
        input [7:0] ts1;
        input [7:0] ts2;
        input [7:0] local;
        input       req;
        input [5:0] state;
        begin
            @(negedge clk);
            ts1_speed_cap    = ts1;
            ts2_speed_cap    = ts2;
            local_speed_cap  = local;
            speed_change_req = req;
            ltssm_state      = state;
            repeat(4) @(posedge clk); #0.5;
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: full reset
    // -----------------------------------------------------------------------
    task do_reset;
        begin
            @(negedge clk);
            rst_n            = 1'b0;
            ts1_speed_cap    = 8'h00;
            ts2_speed_cap    = 8'h00;
            local_speed_cap  = 8'h00;
            speed_change_req = 1'b0;
            ltssm_state      = ST_DETECT;
            repeat(4) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // MAIN
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("link_speed_neg_tb.vcd");
        $dumpvars(0, link_speed_neg_tb);

        fail_count       = 0;
        rst_n            = 1'b0;
        ts1_speed_cap    = 8'h00;
        ts2_speed_cap    = 8'h00;
        local_speed_cap  = 8'h00;
        speed_change_req = 1'b0;
        ltssm_state      = ST_DETECT;

        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ================================================================
        // TEST 1 — Reset: outputs at safe defaults
        // Expected: target_speed=Gen1, speed_change_en=0,
        //           adv_speed_cap=0, speed_neg_done=0
        // ================================================================
        @(posedge clk); #0.5;
        if (target_speed    === SPD_GEN1 &&
            speed_change_en === 1'b0     &&
            adv_speed_cap   === 8'h00    &&
            speed_neg_done  === 1'b0)
            $display("PASS TEST 1: reset defaults correct");
        else begin
            $display("FAIL TEST 1: target=%h change_en=%b adv=%h neg_done=%b",
                      target_speed, speed_change_en, adv_speed_cap, speed_neg_done);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 2 — Gen6 negotiation: all three sides support Gen1-Gen6
        // Expected: target_speed=Gen6, speed_neg_done=1
        // ================================================================
        apply_and_wait(CAP_GEN6, CAP_GEN6, CAP_GEN6, 1'b0, ST_RECOVERY);
        if (target_speed  === SPD_GEN6 && speed_neg_done === 1'b1)
            $display("PASS TEST 2: Gen6 negotiation, target=%h neg_done=%b",
                      target_speed, speed_neg_done);
        else begin
            $display("FAIL TEST 2: target=%h (exp %h) neg_done=%b",
                      target_speed, SPD_GEN6, speed_neg_done);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 3 — adv_speed_cap equals local_speed_cap
        // ================================================================
        apply_and_wait(CAP_GEN6, CAP_GEN6, CAP_GEN5, 1'b0, ST_RECOVERY);
        if (adv_speed_cap === CAP_GEN5)
            $display("PASS TEST 3: adv_speed_cap=%h mirrors local_speed_cap", adv_speed_cap);
        else begin
            $display("FAIL TEST 3: adv_speed_cap=%h expected %h", adv_speed_cap, CAP_GEN5);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 4 — Fallback to Gen5: local does not support Gen6
        // TS1=Gen1-Gen6, TS2=Gen1-Gen6, local=Gen1-Gen5
        // Expected: target_speed=Gen5
        // ================================================================
        apply_and_wait(CAP_GEN6, CAP_GEN6, CAP_GEN5, 1'b0, ST_RECOVERY);
        if (target_speed === SPD_GEN5 && speed_neg_done === 1'b1)
            $display("PASS TEST 4: fallback Gen5, target=%h neg_done=%b",
                      target_speed, speed_neg_done);
        else begin
            $display("FAIL TEST 4: target=%h (exp %h) neg_done=%b",
                      target_speed, SPD_GEN5, speed_neg_done);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 5 — Fallback to Gen4: TS2 only supports Gen1-Gen4
        // ================================================================
        apply_and_wait(CAP_GEN6, CAP_GEN4, CAP_GEN6, 1'b0, ST_RECOVERY);
        if (target_speed === SPD_GEN4 && speed_neg_done === 1'b1)
            $display("PASS TEST 5: fallback Gen4, target=%h neg_done=%b",
                      target_speed, speed_neg_done);
        else begin
            $display("FAIL TEST 5: target=%h (exp %h) neg_done=%b",
                      target_speed, SPD_GEN4, speed_neg_done);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 6 — Fallback to Gen3
        // ================================================================
        apply_and_wait(CAP_GEN3, CAP_GEN6, CAP_GEN6, 1'b0, ST_RECOVERY);
        if (target_speed === SPD_GEN3 && speed_neg_done === 1'b1)
            $display("PASS TEST 6: fallback Gen3, target=%h", target_speed);
        else begin
            $display("FAIL TEST 6: target=%h (exp %h)", target_speed, SPD_GEN3);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 7 — Fallback to Gen2
        // ================================================================
        apply_and_wait(CAP_GEN2, CAP_GEN6, CAP_GEN6, 1'b0, ST_RECOVERY);
        if (target_speed === SPD_GEN2 && speed_neg_done === 1'b1)
            $display("PASS TEST 7: fallback Gen2, target=%h", target_speed);
        else begin
            $display("FAIL TEST 7: target=%h (exp %h)", target_speed, SPD_GEN2);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 8 — Fallback to Gen1: only Gen1 in common
        // ================================================================
        apply_and_wait(CAP_GEN1, CAP_GEN6, CAP_GEN6, 1'b0, ST_RECOVERY);
        if (target_speed === SPD_GEN1 && speed_neg_done === 1'b1)
            $display("PASS TEST 8: fallback Gen1, target=%h", target_speed);
        else begin
            $display("FAIL TEST 8: target=%h (exp %h) neg_done=%b",
                      target_speed, SPD_GEN1, speed_neg_done);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 9 — speed_change_en: asserted when req=1 in Recovery
        //          and negotiation is done
        // ================================================================
        apply_and_wait(CAP_GEN6, CAP_GEN6, CAP_GEN6, 1'b1, ST_RECOVERY);
        if (speed_change_en === 1'b1 && target_speed === SPD_GEN6)
            $display("PASS TEST 9: speed_change_en asserted in Recovery, target=%h",
                      target_speed);
        else begin
            $display("FAIL TEST 9: speed_change_en=%b target=%h (exp change_en=1 target=%h)",
                      speed_change_en, target_speed, SPD_GEN6);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 10 — speed_change_en: NOT asserted outside Recovery (L0)
        // ================================================================
        apply_and_wait(CAP_GEN6, CAP_GEN6, CAP_GEN6, 1'b1, ST_L0);
        if (speed_change_en === 1'b0)
            $display("PASS TEST 10: speed_change_en=0 when NOT in Recovery (L0)");
        else begin
            $display("FAIL TEST 10: speed_change_en=%b expected 0 in L0", speed_change_en);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 11 — speed_change_en: NOT asserted when req=0 in Recovery
        // ================================================================
        apply_and_wait(CAP_GEN6, CAP_GEN6, CAP_GEN6, 1'b0, ST_RECOVERY);
        if (speed_change_en === 1'b0)
            $display("PASS TEST 11: speed_change_en=0 when req=0 in Recovery");
        else begin
            $display("FAIL TEST 11: speed_change_en=%b expected 0 (req=0)", speed_change_en);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 12 — speed_neg_done=0 when no common capability
        //           (TS1 only Gen1, TS2 only Gen2, local only Gen3)
        // ================================================================
        apply_and_wait(8'h01, 8'h02, 8'h04, 1'b0, ST_RECOVERY);
        if (speed_neg_done === 1'b0)
            $display("PASS TEST 12: speed_neg_done=0 with no common capability, target=%h",
                      target_speed);
        else begin
            $display("FAIL TEST 12: speed_neg_done=%b (exp 0), target=%h",
                      speed_neg_done, target_speed);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 13 — Config state: target_speed updated, speed_change_en=0
        // ================================================================
        apply_and_wait(CAP_GEN6, CAP_GEN6, CAP_GEN6, 1'b1, ST_CONFIG);
        if (target_speed === SPD_GEN6 && speed_change_en === 1'b0)
            $display("PASS TEST 13: Config state target=%h change_en=%b",
                      target_speed, speed_change_en);
        else begin
            $display("FAIL TEST 13: target=%h change_en=%b (exp target=6 change_en=0)",
                      target_speed, speed_change_en);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 14 — Detect state: speed_change_en and speed_neg_done both 0
        // ================================================================
        apply_and_wait(CAP_GEN6, CAP_GEN6, CAP_GEN6, 1'b1, ST_DETECT);
        if (speed_change_en === 1'b0 && speed_neg_done === 1'b0)
            $display("PASS TEST 14: Detect state change_en=%b neg_done=%b",
                      speed_change_en, speed_neg_done);
        else begin
            $display("FAIL TEST 14: change_en=%b neg_done=%b (exp both 0)",
                      speed_change_en, speed_neg_done);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 15 — Async reset mid-negotiation clears outputs
        // ================================================================
        apply_and_wait(CAP_GEN6, CAP_GEN6, CAP_GEN6, 1'b1, ST_RECOVERY);
        @(negedge clk);
        rst_n = 1'b0;
        repeat(3) @(posedge clk); #0.5;
        if (target_speed    === SPD_GEN1 &&
            speed_change_en === 1'b0     &&
            speed_neg_done  === 1'b0)
            $display("PASS TEST 15: reset clears negotiation outputs");
        else begin
            $display("FAIL TEST 15: target=%h change_en=%b neg_done=%b (exp Gen1/0/0)",
                      target_speed, speed_change_en, speed_neg_done);
            fail_count = fail_count + 1;
        end
        rst_n = 1'b1;

        // ================================================================
        // TEST 16 — Asymmetric caps: TS1=Gen6, TS2=Gen5, local=Gen6
        //           Expected: Gen5 (limited by TS2)
        // ================================================================
        apply_and_wait(CAP_GEN6, CAP_GEN5, CAP_GEN6, 1'b1, ST_RECOVERY);
        if (target_speed === SPD_GEN5 && speed_change_en === 1'b1)
            $display("PASS TEST 16: asymmetric cap, target=%h change_en=%b",
                      target_speed, speed_change_en);
        else begin
            $display("FAIL TEST 16: target=%h (exp %h) change_en=%b",
                      target_speed, SPD_GEN5, speed_change_en);
            fail_count = fail_count + 1;
        end

        // ================================================================
        // TEST 17 — speed_change_req toggles: en follows req
        // ================================================================
        // req = 1 → change_en expected 1
        apply_and_wait(CAP_GEN6, CAP_GEN6, CAP_GEN6, 1'b1, ST_RECOVERY);
        if (speed_change_en === 1'b1)
            $display("PASS TEST 17a: req=1 → change_en=1");
        else begin
            $display("FAIL TEST 17a: req=1 change_en=%b expected 1", speed_change_en);
            fail_count = fail_count + 1;
        end
        // req = 0 → change_en expected 0
        apply_and_wait(CAP_GEN6, CAP_GEN6, CAP_GEN6, 1'b0, ST_RECOVERY);
        if (speed_change_en === 1'b0)
            $display("PASS TEST 17b: req=0 → change_en=0");
        else begin
            $display("FAIL TEST 17b: req=0 change_en=%b expected 0", speed_change_en);
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
