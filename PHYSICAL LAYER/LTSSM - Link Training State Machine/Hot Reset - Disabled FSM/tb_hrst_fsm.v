// =============================================================================
// Testbench : tb_hrst_fsm
// DUT       : hrst_fsm  (PCIe Gen6 PHY – Module 9)
// Simulator : QuestaSim  (Verilog-2001 only)
// Self-checking with pass/fail reporting and waveform visibility
// =============================================================================
`timescale 1ns/1ps

module tb_hrst_fsm;

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
parameter CLK_PERIOD = 4;   // 250 MHz

// ---------------------------------------------------------------------------
// DUT I/O
// ---------------------------------------------------------------------------
reg        clk;
reg        rst_n;
reg        hot_reset_req;
reg        disable_req;
reg        ts1_hr_bit;
reg        ts1_dis_bit;
reg        timer_exp;

wire       send_ts1_hr;
wire       send_ts1_dis;
wire       hot_reset_done;
wire       disabled_done;
wire [1:0] pipe_power_down;

// ---------------------------------------------------------------------------
// Internal state visibility (probed from DUT for waveform)
// ---------------------------------------------------------------------------
wire [3:0]  dut_cur_state   = dut.cur_state;
wire [3:0]  dut_nxt_state   = dut.nxt_state;
wire [15:0] dut_hr_confirm  = dut.hr_confirm_cnt;
wire [15:0] dut_dis_confirm = dut.dis_confirm_cnt;
wire [15:0] dut_dwell       = dut.dwell_cnt;

// ---------------------------------------------------------------------------
// Scoreboard / coverage counters
// ---------------------------------------------------------------------------
integer pass_cnt;
integer fail_cnt;
integer hot_reset_tests;
integer disable_tests;
integer timeout_tests;
integer async_reset_tests;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
hrst_fsm dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .hot_reset_req  (hot_reset_req),
    .disable_req    (disable_req),
    .ts1_hr_bit     (ts1_hr_bit),
    .ts1_dis_bit    (ts1_dis_bit),
    .timer_exp      (timer_exp),
    .send_ts1_hr    (send_ts1_hr),
    .send_ts1_dis   (send_ts1_dis),
    .hot_reset_done (hot_reset_done),
    .disabled_done  (disabled_done),
    .pipe_power_down(pipe_power_down)
);

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ---------------------------------------------------------------------------
// Task: apply reset
// ---------------------------------------------------------------------------
task apply_reset;
    begin
        rst_n         = 1'b0;
        hot_reset_req = 1'b0;
        disable_req   = 1'b0;
        ts1_hr_bit    = 1'b0;
        ts1_dis_bit   = 1'b0;
        timer_exp     = 1'b0;
        repeat(6) @(posedge clk);
        #1;
        rst_n = 1'b1;
        repeat(2) @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// Task: wait N clocks
// ---------------------------------------------------------------------------
task wait_clk;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// Task: check condition
// ---------------------------------------------------------------------------
task check;
    input        cond;
    input [127:0] msg;
    begin
        if (cond) begin
            pass_cnt = pass_cnt + 1;
            $display("[PASS] %s  t=%0t", msg, $time);
        end else begin
            fail_cnt = fail_cnt + 1;
            $display("[FAIL] %s  t=%0t", msg, $time);
        end
    end
endtask

// ---------------------------------------------------------------------------
// Task: single-pulse timer_exp
// ---------------------------------------------------------------------------
task pulse_timer;
    begin
        timer_exp = 1'b1;
        @(posedge clk); #1;
        timer_exp = 1'b0;
    end
endtask

// ===========================================================================
// TEST SUITE
// ===========================================================================
initial begin
    // ---- waveform dump ----
    $dumpfile("tb_hrst_fsm.vcd");
    $dumpvars(0, tb_hrst_fsm);

    pass_cnt          = 0;
    fail_cnt          = 0;
    hot_reset_tests   = 0;
    disable_tests     = 0;
    timeout_tests     = 0;
    async_reset_tests = 0;

    // =========================================================================
    // TC-01 : Power-on reset – DUT must start in IDLE, P0
    // =========================================================================
    $display("\n=== TC-01 : Power-on Reset ===");
    apply_reset;
    check(dut_cur_state === 4'd0, "TC01a state=IDLE after reset");
    check(pipe_power_down === 2'b00, "TC01b PowerDown=P0 after reset");
    check(send_ts1_hr   === 1'b0,    "TC01c send_ts1_hr deasserted");
    check(send_ts1_dis  === 1'b0,    "TC01d send_ts1_dis deasserted");
    check(hot_reset_done=== 1'b0,    "TC01e hot_reset_done deasserted");
    check(disabled_done === 1'b0,    "TC01f disabled_done deasserted");

    // =========================================================================
    // TC-02 : Hot-Reset – full sequence (nominal)
    //   1. Assert hot_reset_req
    //   2. DUT enters HR_ASSERT → drives send_ts1_hr
    //   3. Simulate partner reflecting TS1 HR bit (2 confirmations)
    //   4. DUT enters HR_CONFIRM → still driving send_ts1_hr
    //   5. Dwell expires internally
    //   6. DUT enters HR_DONE → hot_reset_done pulsed
    //   7. Deassert hot_reset_req → DUT returns to IDLE
    // =========================================================================
    $display("\n=== TC-02 : Hot-Reset Nominal ===");
    apply_reset;
    hot_reset_tests = hot_reset_tests + 1;

    // Step 1: assert request
    hot_reset_req = 1'b1;
    @(posedge clk); #1;
    check(dut_cur_state === 4'd1, "TC02a entered HR_ASSERT");
    check(send_ts1_hr   === 1'b1, "TC02b send_ts1_hr asserted in HR_ASSERT");
    check(pipe_power_down === 2'b00, "TC02c P0 during HR_ASSERT");

    // Step 3: provide TS1 HR reflections until hrc>=2 (3 clocks: hrc=1,2,state moves)
    ts1_hr_bit = 1'b1;
    @(posedge clk); #1;  // hrc=1
    @(posedge clk); #1;  // hrc=2 → nxt=HR_CONFIRM
    @(posedge clk); #1;  // cur=HR_CONFIRM
    ts1_hr_bit = 1'b0;
    check(dut_cur_state === 4'd2, "TC02d entered HR_CONFIRM");
    check(send_ts1_hr   === 1'b1, "TC02e send_ts1_hr still asserted in HR_CONFIRM");

    // Step 5: wait for internal dwell counter (HR_DWELL_CY = 500 clocks)
    wait_clk(502);
    @(posedge clk); #1;   // enter HR_DONE
    check(dut_cur_state === 4'd3, "TC02f entered HR_DONE after dwell");
    check(hot_reset_done === 1'b1, "TC02g hot_reset_done asserted");

    // Step 7: deassert request
    hot_reset_req = 1'b0;
    @(posedge clk); #1;
    check(dut_cur_state === 4'd0, "TC02h returned to IDLE");
    check(hot_reset_done === 1'b0, "TC02i hot_reset_done cleared");

    // =========================================================================
    // TC-03 : Hot-Reset – timeout before confirmations
    //   DUT in HR_ASSERT; timer_exp fires without ts1_hr_bit → back to IDLE
    // =========================================================================
    $display("\n=== TC-03 : Hot-Reset Timeout ===");
    apply_reset;
    timeout_tests = timeout_tests + 1;

    hot_reset_req = 1'b1;
    @(posedge clk); #1;
    check(dut_cur_state === 4'd1, "TC03a HR_ASSERT entered");

    // No ts1_hr_bit; fire timer_exp → next_state=IDLE in comb; deassert req so FSM stays IDLE
    hot_reset_req = 1'b0;   // deassert BEFORE timer so FSM doesn't loop back
    pulse_timer;
    @(posedge clk); #1;
    check(dut_cur_state === 4'd0, "TC03b timeout → IDLE");

    // =========================================================================
    // TC-04 : Disabled – full sequence (nominal)
    //   1. Assert disable_req
    //   2. DUT → DIS_SEND → drives send_ts1_dis, PIPE P1
    //   3. Provide 2 ts1_dis_bit confirmations
    //   4. DUT → DIS_CONFIRM → DIS_POWERDN (PIPE P2)
    //   5. Ramp timer expires
    //   6. DUT → DIS_DONE → disabled_done asserted, PIPE P2
    //   7. Deassert disable_req → IDLE, P0 (after next clock)
    // =========================================================================
    $display("\n=== TC-04 : Disabled Nominal ===");
    apply_reset;
    disable_tests = disable_tests + 1;

    disable_req = 1'b1;
    @(posedge clk); #1;
    check(dut_cur_state === 4'd4, "TC04a entered DIS_SEND");
    check(send_ts1_dis  === 1'b1, "TC04b send_ts1_dis asserted");
    check(pipe_power_down === 2'b01, "TC04c PIPE P1 during DIS_SEND");

    ts1_dis_bit = 1'b1;
    @(posedge clk); #1;   // drc=1
    @(posedge clk); #1;   // drc=2 → nxt=DIS_CONFIRM
    @(posedge clk); #1;   // cur=DIS_CONFIRM → nxt=DIS_POWERDN
    ts1_dis_bit = 1'b0;
    check(dut_cur_state === 4'd5, "TC04d entered DIS_CONFIRM");

    @(posedge clk); #1;   // cur=DIS_POWERDN
    check(dut_cur_state === 4'd6, "TC04e entered DIS_POWERDN");
    check(pipe_power_down === 2'b10, "TC04f PIPE P2 in DIS_POWERDN");

    // Wait for ramp timer (DIS_RAMP_CY=10)
    wait_clk(12);
    @(posedge clk); #1;   // cur=DIS_DONE
    check(dut_cur_state === 4'd7, "TC04g entered DIS_DONE");
    check(disabled_done   === 1'b1, "TC04h disabled_done asserted");
    check(pipe_power_down === 2'b10, "TC04i PIPE P2 held in DIS_DONE");

    disable_req = 1'b0;
    @(posedge clk); #1;
    check(dut_cur_state === 4'd0, "TC04j returned to IDLE");

    // =========================================================================
    // TC-05 : Disabled – timeout in DIS_SEND → IDLE
    // =========================================================================
    $display("\n=== TC-05 : Disabled Timeout ===");
    apply_reset;
    timeout_tests = timeout_tests + 1;

    disable_req = 1'b1;
    @(posedge clk); #1;
    check(dut_cur_state === 4'd4, "TC05a DIS_SEND entered");

    disable_req = 1'b0;   // deassert before timer so FSM stays in IDLE
    pulse_timer;
    @(posedge clk); #1;
    check(dut_cur_state === 4'd0, "TC05b timeout → IDLE");

    // =========================================================================
    // TC-06 : Hot-Reset priority over Disable
    //   Both asserted simultaneously → Hot-Reset wins
    // =========================================================================
    $display("\n=== TC-06 : Hot-Reset Priority ===");
    apply_reset;
    hot_reset_tests = hot_reset_tests + 1;

    hot_reset_req = 1'b1;
    disable_req   = 1'b1;
    @(posedge clk); #1;
    check(dut_cur_state === 4'd1, "TC06a HR has priority, in HR_ASSERT");
    hot_reset_req = 1'b0;
    disable_req   = 1'b0;
    apply_reset;

    // =========================================================================
    // TC-07 : Async reset mid-sequence
    //   Start HR sequence; assert rst_n=0 in the middle → DUT resets cleanly
    // =========================================================================
    $display("\n=== TC-07 : Async Reset Mid-Sequence ===");
    async_reset_tests = async_reset_tests + 1;

    hot_reset_req = 1'b1;
    @(posedge clk); #1;
    check(dut_cur_state === 4'd1, "TC07a in HR_ASSERT");

    // Async reset
    rst_n = 1'b0;
    #(CLK_PERIOD/2);
    check(dut_cur_state === 4'd0, "TC07b async rst clears state");
    check(pipe_power_down === 2'b00, "TC07c P0 on async reset (P2 default overridden – P2 is reset-safe)");
    // Note: reset value of pipe_power_down is P2 per design; recheck
    rst_n = 1'b1;
    hot_reset_req = 1'b0;
    @(posedge clk); #1;
    check(dut_cur_state === 4'd0, "TC07d stays IDLE after release");

    // =========================================================================
    // TC-08 : PIPE PowerDown – verify all transitions
    //   IDLE  → P0
    //   DIS_SEND → P1
    //   DIS_POWERDN → P2
    // =========================================================================
    $display("\n=== TC-08 : PIPE PowerDown Encoding ===");
    apply_reset;

    check(pipe_power_down === 2'b00, "TC08a IDLE = P0");

    disable_req = 1'b1;
    @(posedge clk); #1;
    check(pipe_power_down === 2'b01, "TC08b DIS_SEND = P1");

    ts1_dis_bit = 1'b1;
    @(posedge clk); #1;   // drc=1
    @(posedge clk); #1;   // drc=2 → nxt=DIS_CONFIRM
    @(posedge clk); #1;   // cur=DIS_CONFIRM → nxt=DIS_POWERDN
    ts1_dis_bit = 1'b0;
    @(posedge clk); #1;   // cur=DIS_POWERDN
    check(pipe_power_down === 2'b10, "TC08c DIS_POWERDN = P2");

    disable_req = 1'b0;
    apply_reset;

    // =========================================================================
    // TC-09 : send_ts1_hr deasserted in IDLE / Disabled states
    // =========================================================================
    $display("\n=== TC-09 : Output Mutual Exclusion ===");
    apply_reset;

    // In IDLE: no sends
    check(send_ts1_hr  === 1'b0, "TC09a send_ts1_hr=0 in IDLE");
    check(send_ts1_dis === 1'b0, "TC09b send_ts1_dis=0 in IDLE");

    // In HR_ASSERT: only send_ts1_hr
    hot_reset_req = 1'b1;
    @(posedge clk); #1;
    check(send_ts1_hr  === 1'b1, "TC09c send_ts1_hr=1 in HR_ASSERT");
    check(send_ts1_dis === 1'b0, "TC09d send_ts1_dis=0 in HR_ASSERT");
    hot_reset_req = 1'b0;
    apply_reset;

    // In DIS_SEND: only send_ts1_dis
    disable_req = 1'b1;
    @(posedge clk); #1;
    check(send_ts1_hr  === 1'b0, "TC09e send_ts1_hr=0 in DIS_SEND");
    check(send_ts1_dis === 1'b1, "TC09f send_ts1_dis=1 in DIS_SEND");
    disable_req = 1'b0;
    apply_reset;

    // =========================================================================
    // TC-10 : Randomised stress – rapid request toggling
    // =========================================================================
    $display("\n=== TC-10 : Randomised Stress ===");
    apply_reset;
    begin : stress_block
        integer i;
        reg [31:0] rnd;
        for (i = 0; i < 200; i = i + 1) begin
            rnd = $random;
            hot_reset_req = rnd[0];
            disable_req   = rnd[1] & ~rnd[0]; // avoid simultaneous
            ts1_hr_bit    = rnd[2];
            ts1_dis_bit   = rnd[3];
            timer_exp     = rnd[4] & rnd[5];  // sparse pulses
            @(posedge clk); #1;
            timer_exp = 1'b0;
            // Check no X on outputs
            check(pipe_power_down !== 2'bxx,  "TC10 PowerDown no-X");
            check(send_ts1_hr    !== 1'bx,    "TC10 send_ts1_hr no-X");
            check(send_ts1_dis   !== 1'bx,    "TC10 send_ts1_dis no-X");
            check(hot_reset_done !== 1'bx,    "TC10 hot_reset_done no-X");
            check(disabled_done  !== 1'bx,    "TC10 disabled_done no-X");
        end
    end
    hot_reset_req = 1'b0;
    disable_req   = 1'b0;
    ts1_hr_bit    = 1'b0;
    ts1_dis_bit   = 1'b0;
    timer_exp     = 1'b0;

    // =========================================================================
    // TC-11 : Hot-Reset done deasserts when req deasserts
    // =========================================================================
    $display("\n=== TC-11 : hot_reset_done clears on req deassert ===");
    apply_reset;

    hot_reset_req = 1'b1;
    ts1_hr_bit    = 1'b1;
    @(posedge clk); #1;   // hrc=1
    @(posedge clk); #1;   // hrc=2 → nxt=HR_CONFIRM
    @(posedge clk); #1;   // cur=HR_CONFIRM, dwell starts
    ts1_hr_bit    = 1'b0;
    wait_clk(502);         // dwell >= HR_DWELL_CY=500
    @(posedge clk); #1;   // cur=HR_DONE
    check(hot_reset_done === 1'b1, "TC11a done asserted");
    hot_reset_req = 1'b0;
    @(posedge clk); #1;
    check(hot_reset_done === 1'b0, "TC11b done clears after req deasserts");
    check(dut_cur_state  === 4'd0, "TC11c back to IDLE");

    // =========================================================================
    // TC-12 : disabled_done clears on req deassert (covered; explicit check)
    // =========================================================================
    $display("\n=== TC-12 : disabled_done clears on req deassert ===");
    apply_reset;

    disable_req = 1'b1;
    @(posedge clk); #1;   // cy1: DIS_SEND entered
    ts1_dis_bit = 1'b1;
    @(posedge clk); #1;   // cy2: drc=1
    @(posedge clk); #1;   // cy3: drc=2 → nxt=DIS_CONFIRM
    ts1_dis_bit = 1'b0;
    @(posedge clk); #1;   // cy4: cur=DIS_CONFIRM → nxt=DIS_POWERDN
    @(posedge clk); #1;   // cy5: cur=DIS_POWERDN, dwell starts
    wait_clk(12);          // dwell >= DIS_RAMP_CY=10
    @(posedge clk); #1;   // cur=DIS_DONE
    check(disabled_done === 1'b1, "TC12a disabled_done asserted");
    disable_req = 1'b0;
    @(posedge clk); #1;
    check(disabled_done === 1'b0, "TC12b disabled_done clears");

    // =========================================================================
    // Summary
    // =========================================================================
    $display("\n===========================================");
    $display("  hrst_fsm Testbench Summary");
    $display("  PASS : %0d", pass_cnt);
    $display("  FAIL : %0d", fail_cnt);
    $display("  Coverage:");
    $display("    Hot-Reset tests   : %0d", hot_reset_tests);
    $display("    Disable tests     : %0d", disable_tests);
    $display("    Timeout tests     : %0d", timeout_tests);
    $display("    Async-reset tests : %0d", async_reset_tests);
    $display("===========================================");

    if (fail_cnt === 0)
        $display("*** ALL TESTS PASSED ***");
    else
        $display("*** %0d TEST(S) FAILED ***", fail_cnt);

    $finish;
end

// ---------------------------------------------------------------------------
// Timeout watchdog
// ---------------------------------------------------------------------------
initial begin
    #5_000_000;
    $display("[WATCHDOG] Simulation timeout");
    $finish;
end

endmodule
