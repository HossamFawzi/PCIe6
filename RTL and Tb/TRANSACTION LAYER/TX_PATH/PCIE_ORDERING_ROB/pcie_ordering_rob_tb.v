// ============================================================================
// FILE        : pcie_ordering_rob_tb.v
// DESCRIPTION : Testbench for pcie_ordering_rob.v
//
// KEY TIMING INSIGHT (confirmed by manual simulation):
//
//   The DUT registered outputs capture the combinational result AT posedge N
//   (the same posedge that sees req_valid=1).  The output is valid immediately
//   after that posedge (#1 delay for flop settling), and becomes 0 again at
//   posedge N+1 because req_valid has been deasserted.
//
//   CORRECT sampling sequence:
//
//   negedge        posedge N      #1          negedge       posedge N+1
//      |               |           |              |               |
//   drive inputs    captured    READ HERE      deassert       outputs=0
//   req_valid=1    (ok/stall     <-- SAMPLE    req_valid=0   (too late)
//                   computed)
//
//   So: drive at negedge → wait posedge → wait #1 → READ → then deassert
//
// Compile:
//   iverilog -o sim pcie_ordering_rob.v pcie_ordering_rob_tb.v && vvp sim
// ============================================================================

`timescale 1ns/1ps

module pcie_ordering_rob_tb;

    // =========================================================================
    // Signals
    // =========================================================================
    reg        clk, rst_n;
    reg [15:0] req_id;
    reg [3:0]  req_type;
    reg [2:0]  req_tc;
    reg        req_attr_ro, req_valid;
    reg [15:0] cpl_id;
    reg        cpl_valid;

    wire ordering_ok, ordering_stall, ordering_err;

    // =========================================================================
    // DUT
    // =========================================================================
    pcie_ordering_rob #(
        .ROB_DEPTH     (32),
        .ROB_PTR_WIDTH (5),
        .NUM_TC        (8)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .req_id        (req_id),
        .req_type      (req_type),
        .req_tc        (req_tc),
        .req_attr_ro   (req_attr_ro),
        .req_valid     (req_valid),
        .cpl_id        (cpl_id),
        .cpl_valid     (cpl_valid),
        .ordering_ok   (ordering_ok),
        .ordering_stall(ordering_stall),
        .ordering_err  (ordering_err)
    );

    // =========================================================================
    // TLP type constants
    // =========================================================================
    localparam TYPE_MWR32  = 4'h0;
    localparam TYPE_MWR64  = 4'h1;
    localparam TYPE_MSG    = 4'h2;
    localparam TYPE_MRD32  = 4'h4;
    localparam TYPE_IORD   = 4'h6;
    localparam TYPE_IOWR   = 4'h7;
    localparam TYPE_CFGWR0 = 4'h9;
    localparam TYPE_CPLD   = 4'hD;
    localparam TYPE_RSVD   = 4'hF;

    // =========================================================================
    // Scoreboard (module-level — Verilog-2001)
    // =========================================================================
    integer pass_cnt, fail_cnt, b;

    // =========================================================================
    // Clock: 10 ns period
    // =========================================================================
    initial clk = 0;
    always  #5 clk = ~clk;

    // =========================================================================
    // TASK: send_and_check
    //
    //   Drives a request for one posedge, samples outputs at posedge+#1
    //   (SAME posedge that captured inputs), then deasserts.
    //
    //   Timeline:
    //     negedge : drive inputs + req_valid=1
    //     posedge : DUT captures; outputs update
    //     #1      : READ outputs here  <-- CORRECT SAMPLE POINT
    //     deassert req_valid
    // =========================================================================
    task send_and_check;
        input [15:0] id;
        input [3:0]  typ;
        input [2:0]  tc;
        input        ro;
        input [199:0] name;
        input         exp_ok, exp_stall, exp_err;
        begin
            @(negedge clk);
            req_id      = id;
            req_type    = typ;
            req_tc      = tc;
            req_attr_ro = ro;
            req_valid   = 1'b1;

            @(posedge clk); #1;   // outputs are valid here

            // --- check ---
            if (ordering_ok    === exp_ok    &&
                ordering_stall === exp_stall &&
                ordering_err   === exp_err) begin
                $display("  PASS | %-26s | ok=%b stall=%b err=%b",
                         name, ordering_ok, ordering_stall, ordering_err);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL | %-26s | got ok=%b stall=%b err=%b  exp ok=%b stall=%b err=%b",
                         name,
                         ordering_ok, ordering_stall, ordering_err,
                         exp_ok, exp_stall, exp_err);
                fail_cnt = fail_cnt + 1;
            end

            req_valid = 1'b0;   // deassert after reading
        end
    endtask

    // =========================================================================
    // TASK: send_cpl
    //   Drives cpl_valid for one posedge.
    // =========================================================================
    task send_cpl;
        input [15:0] id;
        begin
            @(negedge clk);
            cpl_id    = id;
            cpl_valid = 1'b1;
            @(posedge clk); #1;
            cpl_valid = 1'b0;
        end
    endtask

    // =========================================================================
    // TASK: idle
    // =========================================================================
    task idle;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
            #1;
        end
    endtask

    // =========================================================================
    // TASK: check_cpl_err
    //   For unexpected-CPL test: drives req_valid + cpl_valid together,
    //   samples at posedge+#1 (same cycle).
    // =========================================================================
    task check_cpl_err;
        input [15:0] cid;
        input [199:0] name;
        input exp_err;
        begin
            @(negedge clk);
            req_id=cid; req_type=TYPE_CPLD; req_tc=3'd0;
            req_attr_ro=0; req_valid=1;
            cpl_id=cid; cpl_valid=1;

            @(posedge clk); #1;

            if (ordering_err === exp_err) begin
                $display("  PASS | %-26s | err=%b (expected %b)", name, ordering_err, exp_err);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL | %-26s | got err=%b  exp err=%b", name, ordering_err, exp_err);
                fail_cnt = fail_cnt + 1;
            end

            req_valid = 0;
            cpl_valid = 0;
        end
    endtask

    // =========================================================================
    // STIMULUS
    // =========================================================================
    initial begin
        pass_cnt = 0; fail_cnt = 0;
        req_id=0; req_type=0; req_tc=0; req_attr_ro=0; req_valid=0;
        cpl_id=0; cpl_valid=0;

        // Reset
        rst_n = 0;
        repeat(4) @(posedge clk); #1;
        rst_n = 1;
        idle(2);

        $display("=========================================================");
        $display(" PCIe Ordering ROB Testbench  -  Table 2-38");
        $display("=========================================================");

        // =================================================================
        // TC1: Posted MWR32 on clean TC0 -> OK
        // =================================================================
        $display("\n--- TC1: Posted MWR32 on clean TC0 ---");
        send_and_check(16'hA001, TYPE_MWR32, 3'd0, 0,
                       "P_clean_TC0", 1,0,0);
        idle(2);

        // =================================================================
        // TC2: NP MRD32 on clean TC0 RO=0 -> OK
        // =================================================================
        $display("\n--- TC2: NP MRD32 on clean TC0 RO=0 ---");
        send_and_check(16'hA002, TYPE_MRD32, 3'd0, 0,
                       "NP_clean_TC0", 1,0,0);
        // A002 now in ROB — keep for TC3
        idle(1);

        // =================================================================
        // TC3: Posted behind in-flight NP on TC0 -> STALL
        // =================================================================
        $display("\n--- TC3: Posted behind in-flight NP on TC0 -> STALL ---");
        send_and_check(16'hA003, TYPE_MWR32, 3'd0, 0,
                       "P_behind_NP", 0,1,0);
        idle(1);

        // =================================================================
        // TC4: Retire NP A002
        // =================================================================
        $display("\n--- TC4: Complete NP A002 -> drain ROB ---");
        send_cpl(16'hA002);
        idle(2);
        $display("  (A002 retired)");

        // =================================================================
        // TC5: Retry Posted after NP retired -> OK
        // =================================================================
        $display("\n--- TC5: Retry Posted after NP retired -> OK ---");
        send_and_check(16'hA003, TYPE_MWR32, 3'd0, 0,
                       "P_after_cpl", 1,0,0);
        idle(2);

        // =================================================================
        // TC6: NP RO=0 behind Posted -> STALL
        //   Cycle N  : Posted captured  -> posted_pending[0] set
        //   Cycle N+1: NP RO=0 arrives  -> sees posted_pending[0]=1 -> stall
        //   Sample at cycle N+1 posedge+#1
        // =================================================================
        $display("\n--- TC6: NP RO=0 behind Posted on TC0 -> STALL ---");
        // Cycle N: send Posted (don't check, just clock it in)
        @(negedge clk);
        req_id=16'hA004; req_type=TYPE_MWR32; req_tc=3'd0;
        req_attr_ro=0; req_valid=1;
        @(posedge clk); #1;   // posted_pending[0] registered = 1
        req_valid = 0;

        // Cycle N+1: send NP RO=0 and CHECK
        @(negedge clk);
        req_id=16'hA005; req_type=TYPE_MRD32; req_tc=3'd0;
        req_attr_ro=0; req_valid=1;
        @(posedge clk); #1;   // stall should be 1 here
        if (ordering_stall===1 && ordering_ok===0 && ordering_err===0) begin
            $display("  PASS | %-26s | ok=%b stall=%b err=%b",
                     "NP_RO0_behind_P",ordering_ok,ordering_stall,ordering_err);
            pass_cnt=pass_cnt+1;
        end else begin
            $display("  FAIL | %-26s | got ok=%b stall=%b err=%b  exp ok=0 stall=1 err=0",
                     "NP_RO0_behind_P",ordering_ok,ordering_stall,ordering_err);
            fail_cnt=fail_cnt+1;
        end
        req_valid=0;
        idle(2);

        // =================================================================
        // TC7: NP RO=1 behind Posted -> OK
        // =================================================================
        $display("\n--- TC7: NP RO=1 behind Posted on TC0 -> OK ---");
        // Cycle N: Posted
        @(negedge clk);
        req_id=16'hA006; req_type=TYPE_MWR32; req_tc=3'd0;
        req_attr_ro=0; req_valid=1;
        @(posedge clk); #1;
        req_valid=0;

        // Cycle N+1: NP RO=1 and CHECK
        @(negedge clk);
        req_id=16'hA007; req_type=TYPE_MRD32; req_tc=3'd0;
        req_attr_ro=1; req_valid=1;   // RO=1
        @(posedge clk); #1;
        if (ordering_ok===1 && ordering_stall===0 && ordering_err===0) begin
            $display("  PASS | %-26s | ok=%b stall=%b err=%b",
                     "NP_RO1_behind_P",ordering_ok,ordering_stall,ordering_err);
            pass_cnt=pass_cnt+1;
        end else begin
            $display("  FAIL | %-26s | got ok=%b stall=%b err=%b  exp ok=1 stall=0 err=0",
                     "NP_RO1_behind_P",ordering_ok,ordering_stall,ordering_err);
            fail_cnt=fail_cnt+1;
        end
        req_valid=0;
        send_cpl(16'hA007);
        idle(2);

        // =================================================================
        // TC8: NP RO=1 behind in-flight NP -> OK (rule 5 relaxed)
        // =================================================================
        $display("\n--- TC8: NP RO=1 behind NP on TC0 -> OK ---");
        // First NP into ROB
        send_and_check(16'hA008, TYPE_MRD32, 3'd0, 0,
                       "NP1_into_ROB", 1,0,0);
        idle(1);
        // Second NP RO=1 — A008 in ROB but RO=1 so should pass
        send_and_check(16'hA009, TYPE_MRD32, 3'd0, 1,
                       "NP_RO1_behind_NP", 1,0,0);
        send_cpl(16'hA008); send_cpl(16'hA009);
        idle(2);

        // =================================================================
        // TC9: NP RO=0 behind in-flight NP -> STALL (rule 5)
        // =================================================================
        $display("\n--- TC9: NP RO=0 behind NP on TC0 -> STALL ---");
        send_and_check(16'hA00A, TYPE_MRD32, 3'd0, 0,
                       "NP1_into_ROB", 1,0,0);
        idle(1);
        send_and_check(16'hA00B, TYPE_MRD32, 3'd0, 0,
                       "NP_RO0_behind_NP", 0,1,0);
        send_cpl(16'hA00A);
        idle(2);

        // =================================================================
        // TC10: NP on TC3 while TC0 has in-flight NP -> OK (cross-TC)
        // =================================================================
        $display("\n--- TC10: NP TC3, in-flight NP on TC0 -> OK (cross-TC) ---");
        send_and_check(16'hA00C, TYPE_MRD32, 3'd0, 0,
                       "NP_TC0_into_ROB", 1,0,0);
        idle(1);
        send_and_check(16'hA00D, TYPE_MRD32, 3'd3, 0,
                       "NP_cross_TC", 1,0,0);
        send_cpl(16'hA00C); send_cpl(16'hA00D);
        idle(2);

        // =================================================================
        // TC11: CPLD req_type -> always passes (completions never stalled)
        // =================================================================
        $display("\n--- TC11: CPLD req_type -> OK ---");
        // First ensure ROB is empty
        idle(2);
        send_and_check(16'hA00F, TYPE_CPLD, 3'd0, 0,
                       "CPL_always_pass", 1,0,0);
        idle(2);

        // =================================================================
        // TC12: Unexpected CPL — NP in ROB but ID does NOT match -> ERR
        //   Condition: cpl_valid && !rob_empty && !cpl_found_np
        //   rob_empty must be 0, so insert NP 0xAAAA first.
        //   Then send CPL with wrong ID 0xDEAD -> cpl_found_np=0 -> ERR.
        // =================================================================
        $display("\n--- TC12: Unexpected CPL (wrong ID, NP in ROB) -> ERR ---");
        send_and_check(16'hAAAA, TYPE_MRD32, 3'd0, 0,
                       "NP_setup_TC12", 1,0,0);
        idle(1);
        check_cpl_err(16'hDEAD, "unexpected_cpl", 1);
        send_cpl(16'hAAAA);
        idle(2);

        // =================================================================
        // TC13: Invalid TLP type 0xF -> ERR
        // =================================================================
        $display("\n--- TC13: Invalid TLP type 0xF -> ERR ---");
        send_and_check(16'hA010, TYPE_RSVD, 3'd0, 0,
                       "invalid_type", 0,0,1);
        idle(2);

        // =================================================================
        // TC14: IOWR (NP) on clean TC0 -> OK
        // =================================================================
        $display("\n--- TC14: IOWR (NP) on clean TC0 -> OK ---");
        send_and_check(16'hA011, TYPE_IOWR, 3'd0, 0,
                       "IOWR_clean", 1,0,0);
        send_cpl(16'hA011);
        idle(2);

        // =================================================================
        // TC15: CFGWR0 (NP) on clean TC2 -> OK
        // =================================================================
        $display("\n--- TC15: CFGWR0 (NP) on clean TC2 -> OK ---");
        send_and_check(16'hA012, TYPE_CFGWR0, 3'd2, 0,
                       "CFGWR0_clean", 1,0,0);
        send_cpl(16'hA012);
        idle(2);

        // =================================================================
        // TC16: MSG (Posted) on clean TC0 -> OK
        // =================================================================
        $display("\n--- TC16: MSG (Posted) on clean TC0 -> OK ---");
        send_and_check(16'hA013, TYPE_MSG, 3'd0, 0,
                       "MSG_posted", 1,0,0);
        idle(2);

        // =================================================================
        // TC17: Burst 3x MWR64 on TC5 -> all OK (P behind P = must pass)
        // =================================================================
        $display("\n--- TC17: Burst 3x MWR64 on TC5 -> all OK ---");
        for (b = 0; b < 3; b = b + 1) begin
            send_and_check(16'hB000 + b, TYPE_MWR64, 3'd5, 0,
                           "burst_MWR64", 1,0,0);
            idle(1);
        end

        // =================================================================
        // FINAL REPORT
        // =================================================================
        $display("\n=========================================================");
        $display(" RESULTS:  PASS=%0d  FAIL=%0d  TOTAL=%0d",
                 pass_cnt, fail_cnt, pass_cnt+fail_cnt);
        if (fail_cnt == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" *** %0d TEST(S) FAILED ***", fail_cnt);
        $display("=========================================================");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("pcie_ordering_rob.vcd");
        $dumpvars(0, pcie_ordering_rob_tb);
    end

    // Watchdog
    initial begin
        #500_000;
        $display("TIMEOUT — simulation exceeded 500us");
        $finish;
    end

endmodule
