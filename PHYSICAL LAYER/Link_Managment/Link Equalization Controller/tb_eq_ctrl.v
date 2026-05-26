// =============================================================================
// Testbench : tb_eq_ctrl
// DUT       : eq_ctrl  --  Link Equalization Controller
//
// Verified cycle map (all outputs registered; sample 1 ns after posedge):
//   cyc 0 : eq_req sampled -> FSM: IDLE->PHASE0
//   cyc 1 : PHASE0 outputs (phase_out=0 still)
//   cyc 2 : PHASE1_REQ  -- phase_out=1, rxeqeval_out=1
//             assert pipe_rxeqeval this cycle (held into cyc3)
//   cyc 3 : still PHASE1_REQ (combinational rxeqeval captured next posedge)
//   cyc 4 : PHASE1_ACK  (rxeqeval_out drops)
//   cyc 5 : PHASE2_REQ  -- phase_out=2, rxeqeval_out=1, preset applied
//             assert pipe_rxeqeval this cycle
//   cyc 6 : still PHASE2_REQ
//   cyc 7 : PHASE2_ACK
//   cyc 8 : PHASE3  -- phase_out=3, clear ts1_eq_req_bit
//   cyc 9 : PHASE3 one more cycle
//   cyc10 : S_DONE  -- eq_done=1
//   cyc11 : IDLE    -- eq_done=0
// =============================================================================
`timescale 1ns/1ps

module tb_eq_ctrl;

// -- DUT ports ----------------------------------------------------------------
reg        clk;
reg        rst_n;
reg        eq_req;
reg  [1:0] eq_phase;
reg        ts1_eq_req_bit;
reg  [3:0] ts2_eq_preset;
reg        pipe_rxeqeval;
reg        eq_timer_exp;

wire [2:0] pipe_txdeemph;
wire [2:0] pipe_txmargin;
wire       pipe_rxeqeval_out;
wire       eq_done;
wire [1:0] eq_phase_out;
wire       eq_err;

// -- DUT instantiation --------------------------------------------------------
eq_ctrl dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .eq_req           (eq_req),
    .eq_phase         (eq_phase),
    .ts1_eq_req_bit   (ts1_eq_req_bit),
    .ts2_eq_preset    (ts2_eq_preset),
    .pipe_rxeqeval    (pipe_rxeqeval),
    .eq_timer_exp     (eq_timer_exp),
    .pipe_txdeemph    (pipe_txdeemph),
    .pipe_txmargin    (pipe_txmargin),
    .pipe_rxeqeval_out(pipe_rxeqeval_out),
    .eq_done          (eq_done),
    .eq_phase_out     (eq_phase_out),
    .eq_err           (eq_err)
);

// -- Clock (10 ns, 100 MHz) ---------------------------------------------------
initial clk = 0;
always  #5 clk = ~clk;

// -- Helper: advance one clock and sample (1 ns after edge) -------------------
task step;
begin
    @(posedge clk); #1;
end
endtask

// -- Reset task ---------------------------------------------------------------
task do_reset;
begin
    rst_n          = 1'b0;
    eq_req         = 1'b0;
    eq_phase       = 2'd0;
    ts1_eq_req_bit = 1'b0;
    ts2_eq_preset  = 4'd0;
    pipe_rxeqeval  = 1'b0;
    eq_timer_exp   = 1'b0;
    repeat(4) @(posedge clk);
    #1; rst_n = 1'b1;
    step;
end
endtask

// -- Checker ------------------------------------------------------------------
integer pass_cnt, fail_cnt;

task check;
    input [63:0] actual;
    input [63:0] expected;
    input [127:0] msg;
begin
    if (actual === expected) begin
        $display("  PASS | %0s  actual=%0h expected=%0h", msg, actual, expected);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("  FAIL | %0s  actual=%0h expected=%0h  MISMATCH",
                 msg, actual, expected);
        fail_cnt = fail_cnt + 1;
    end
end
endtask

// -- Main stimulus ------------------------------------------------------------
initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    $display("\n===================================================");
    $display(" TB: eq_ctrl -- Link Equalization Controller");
    $display("===================================================\n");

    // ---------------------------------------------------------------
    // TEST 1: Reset behaviour
    // ---------------------------------------------------------------
    $display("--- TEST 1: Reset state ---");
    do_reset;
    check(eq_done,       0, "eq_done  = 0 after reset");
    check(eq_err,        0, "eq_err   = 0 after reset");
    check(pipe_txdeemph, 0, "txdeemph = 0 after reset");
    check(pipe_txmargin, 0, "txmargin = 0 after reset");
    check(eq_phase_out,  0, "phase_out= 0 after reset");

    // ---------------------------------------------------------------
    // TEST 2: Full equalization from Phase 0 (happy path)
    // Exact timing per verified FSM trace above.
    // ---------------------------------------------------------------
    $display("\n--- TEST 2: Full equalization sequence (Phase 0 start) ---");
    do_reset;
    ts1_eq_req_bit = 1'b1;
    ts2_eq_preset  = 4'd5;
    eq_phase       = 2'd0;

    // cyc0: assert eq_req -> IDLE captures, next=PHASE0
    eq_req = 1'b1; step; eq_req = 1'b0;
    // cyc1: in PHASE0 (phase_out still 0)
    step;
    // cyc2: PHASE1_REQ outputs
    step;
    check(eq_phase_out,      1, "cyc2: phase_out = 1    ");
    check(pipe_rxeqeval_out, 1, "cyc2: rxeqeval_out = 1 ");

    // Assert pipe_rxeqeval (PHY ACK) - hold for two cycles
    pipe_rxeqeval = 1'b1;
    // cyc3: still PHASE1_REQ (rxeqeval captured at next posedge -> cyc4)
    step;
    pipe_rxeqeval = 1'b0;
    // cyc4: PHASE1_ACK - rxeqeval_out drops
    step;
    check(pipe_rxeqeval_out, 0, "cyc4: rxeqeval_out = 0 ");
    // cyc5: PHASE2_REQ outputs
    step;
    check(eq_phase_out,      2, "cyc5: phase_out = 2    ");
    check(pipe_rxeqeval_out, 1, "cyc5: rxeqeval_out = 1 ");

    // ACK phase 2
    pipe_rxeqeval = 1'b1;
    step;                           // cyc6: still PHASE2_REQ
    pipe_rxeqeval = 1'b0;
    step;                           // cyc7: PHASE2_ACK
    step;                           // cyc8: PHASE3 outputs
    check(eq_phase_out, 3, "cyc8: phase_out = 3    ");
    check(eq_done,      0, "cyc8: eq_done = 0      ");

    // Clear EQ request; FSM will see it next posedge
    ts1_eq_req_bit = 1'b0;
    step;                           // cyc9: PHASE3 (ts1 clear captured)
    step;                           // cyc10: S_DONE
    check(eq_done, 1, "cyc10: eq_done = 1     ");
    check(eq_err,  0, "cyc10: eq_err  = 0     ");

    step;                           // cyc11: back to IDLE
    check(eq_done, 0, "cyc11: eq_done = 0     ");

    // ---------------------------------------------------------------
    // TEST 3: Timeout error in Phase 1 (no PHY ACK)
    // ---------------------------------------------------------------
    $display("\n--- TEST 3: Timeout in Phase 1 ---");
    do_reset;
    ts1_eq_req_bit = 1'b1;
    eq_phase       = 2'd1;     // Jump directly to Phase 1

    eq_req = 1'b1; step; eq_req = 1'b0;   // -> PHASE1_REQ next
    step;                                   // in PHASE1_REQ (rxeqeval_out=1)
    check(pipe_rxeqeval_out, 1, "T3: rxeqeval_out asserted");
    // Fire timer (no PHY ack)
    eq_timer_exp = 1'b1; step; eq_timer_exp = 1'b0;
    step;                                   // S_ERROR outputs
    check(eq_err,  1, "T3: eq_err  = 1        ");
    check(eq_done, 0, "T3: eq_done = 0        ");
    step;                                   // back to IDLE
    check(eq_err, 0, "T3: eq_err de-asserted ");

    // ---------------------------------------------------------------
    // TEST 4: Preset P7 de-emphasis and margin values
    //   P7 -> {pipe_txdeemph=3'b111, pipe_txmargin=3'b011}
    // ---------------------------------------------------------------
    $display("\n--- TEST 4: Preset P7 coefficient check ---");
    do_reset;
    ts1_eq_req_bit = 1'b1;
    ts2_eq_preset  = 4'd7;
    eq_phase       = 2'd2;     // Start at Phase 2

    eq_req = 1'b1; step; eq_req = 1'b0;   // PHASE2_REQ next
    step;                                   // in PHASE2_REQ
    check(pipe_txdeemph, 3'b111, "P7: txdeemph = 3'b111 ");
    check(pipe_txmargin, 3'b011, "P7: txmargin = 3'b011 ");

    // ---------------------------------------------------------------
    // TEST 5: Phase 3 direct start, single EQ cycle
    // ---------------------------------------------------------------
    $display("\n--- TEST 5: Phase 3 direct start ---");
    do_reset;
    ts1_eq_req_bit = 1'b1;
    eq_phase       = 2'd3;

    eq_req = 1'b1; step; eq_req = 1'b0;
    step;                          // PHASE3 outputs
    check(eq_phase_out, 3, "T5: phase_out = 3      ");
    check(eq_done,      0, "T5: eq_done not yet    ");

    ts1_eq_req_bit = 1'b0;
    step;                          // ts1 cleared, FSM sees it
    step;                          // S_DONE
    check(eq_done, 1, "T5: eq_done = 1        ");
    step;
    check(eq_done, 0, "T5: eq_done = 0 next   ");

    // ---------------------------------------------------------------
    // Summary
    // ---------------------------------------------------------------
    $display("\n===================================================");
    $display(" Results: %0d PASS  %0d FAIL", pass_cnt, fail_cnt);
    $display("===================================================\n");
    $finish;
end

initial begin
    $dumpfile("eq_ctrl.vcd");
    $dumpvars(0, tb_eq_ctrl);
end

endmodule
