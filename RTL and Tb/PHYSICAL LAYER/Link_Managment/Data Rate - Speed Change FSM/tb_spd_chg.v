// =============================================================================
// Testbench : tb_spd_chg
// DUT       : spd_chg  --  Data Rate / Speed Change FSM
//
// Timing proven by exhaustive per-cycle trace (TIMEOUT_VAL=15):
//
//  Happy-path cycle map (label = cycles after speed_change_en posedge):
//    p0  speed_change_en captured; pout=old, retrain=0  (still IDLE outputs)
//    p1  S_RETRAIN outputs: retrain_req=1, pipe_rate_out=target
//    p2  recovery_done pulsed HERE -> S_RATE_SET captures it; retrain=0
//    p3  pipe_rate=target driven HERE -> S_VERIFY captures it
//    p4  S_DONE: speed_change_done=1
//    p5  S_IDLE: speed_change_done=0
//
//  Timeout cycle map (no recovery_done):
//    t1  S_RETRAIN (retrain=1)
//    t2  S_RATE_SET entered; timeout counter starts
//    t18 S_ERROR outputs: speed_change_err=1, pipe_rate_out=Gen1
//    t19 S_IDLE: speed_change_err=0
// =============================================================================
`timescale 1ns/1ps

module tb_spd_chg;

// -- DUT ports ----------------------------------------------------------------
reg        clk;
reg        rst_n;
reg        speed_change_en;
reg  [3:0] target_speed;
reg        recovery_done;
reg  [3:0] pipe_rate;

wire [3:0] pipe_rate_out;
wire       speed_change_done;
wire       speed_change_err;
wire       retrain_req;

// -- DUT (TIMEOUT_VAL=15 for fast simulation) ---------------------------------
spd_chg #(.TIMEOUT_VAL(14'd15)) dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .speed_change_en  (speed_change_en),
    .target_speed     (target_speed),
    .recovery_done    (recovery_done),
    .pipe_rate        (pipe_rate),
    .pipe_rate_out    (pipe_rate_out),
    .speed_change_done(speed_change_done),
    .speed_change_err (speed_change_err),
    .retrain_req      (retrain_req)
);

// -- Clock (10 ns period) -----------------------------------------------------
initial clk = 0;
always #5 clk = ~clk;

// -- Step: advance one clock, sample outputs 1 ns after edge -----------------
task step;
begin
    @(posedge clk); #1;
end
endtask

// -- Reset task ---------------------------------------------------------------
task do_reset;
begin
    rst_n           = 1'b0;
    speed_change_en = 1'b0;
    target_speed    = 4'd0;
    recovery_done   = 1'b0;
    pipe_rate       = 4'd1;
    repeat(4) @(posedge clk);
    #1; rst_n = 1'b1;
    step;           // one settled cycle post-reset
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
        $display("  PASS | %0s  actual=%0h  expected=%0h", msg, actual, expected);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("  FAIL | %0s  actual=%0h  expected=%0h  MISMATCH",
                 msg, actual, expected);
        fail_cnt = fail_cnt + 1;
    end
end
endtask

// -- Happy-path task: verified 4-step sequence --------------------------------
task do_speed_change;
    input [3:0] tgt;
begin
    target_speed    = tgt;
    pipe_rate       = 4'd1;        // PHY starts at Gen1

    // p0: trigger; sample shows IDLE outputs (old values)
    speed_change_en = 1'b1; step; speed_change_en = 1'b0;

    // p1: S_RETRAIN outputs
    step;
    check(retrain_req,   1,   "p1: retrain_req=1        ");
    check(pipe_rate_out, tgt, "p1: pipe_rate_out=target ");

    // p2: assert recovery_done (captured at p2 posedge -> moves to VERIFY)
    recovery_done = 1'b1; step; recovery_done = 1'b0;

    // p3: drive correct pipe_rate echo (captured at p3 posedge)
    pipe_rate = tgt; step;

    // p4: S_DONE -- speed_change_done pulses here
    step;
    check(speed_change_done, 1, "p4: speed_change_done=1  ");
    check(speed_change_err,  0, "p4: speed_change_err=0   ");

    // p5: back to IDLE
    step;
    check(speed_change_done, 0, "p5: speed_change_done=0  ");
end
endtask

// -- Main stimulus ------------------------------------------------------------
initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    $display("\n===================================================");
    $display(" TB: spd_chg -- Data Rate / Speed Change FSM");
    $display("===================================================\n");

    // ---------------------------------------------------------------
    // TEST 1: Reset state
    // ---------------------------------------------------------------
    $display("--- TEST 1: Reset state ---");
    do_reset;
    check(speed_change_done, 0,    "speed_change_done=0 rst  ");
    check(speed_change_err,  0,    "speed_change_err =0 rst  ");
    check(retrain_req,       0,    "retrain_req      =0 rst  ");
    check(pipe_rate_out,     4'd1, "pipe_rate_out=Gen1 rst   ");

    // ---------------------------------------------------------------
    // TEST 2: Gen1 -> Gen3  (8 GT/s)
    // ---------------------------------------------------------------
    $display("\n--- TEST 2: Speed change Gen1->Gen3 ---");
    do_reset;
    do_speed_change(4'b0011);

    // ---------------------------------------------------------------
    // TEST 3: Gen1 -> Gen6  (64 GT/s, PCIe 6.0)
    // ---------------------------------------------------------------
    $display("\n--- TEST 3: Speed change Gen1->Gen6 ---");
    do_reset;
    do_speed_change(4'b0110);

    // ---------------------------------------------------------------
    // TEST 4: Gen1 -> Gen5  (32 GT/s)
    // ---------------------------------------------------------------
    $display("\n--- TEST 4: Speed change Gen1->Gen5 ---");
    do_reset;
    do_speed_change(4'b0101);

    // ---------------------------------------------------------------
    // TEST 5: Gen1 -> Gen2  (5 GT/s)
    // ---------------------------------------------------------------
    $display("\n--- TEST 5: Speed change Gen1->Gen2 ---");
    do_reset;
    do_speed_change(4'b0010);

    // ---------------------------------------------------------------
    // TEST 6: Timeout -- recovery_done never arrives
    //   Timeout fires at t18 from trace (TIMEOUT_VAL=15)
    // ---------------------------------------------------------------
    $display("\n--- TEST 6: Timeout (no recovery_done) ---");
    do_reset;
    target_speed    = 4'b0100;    // Gen4
    pipe_rate       = 4'b0001;

    // p0: trigger
    speed_change_en = 1'b1; step; speed_change_en = 1'b0;
    // p1: RETRAIN; now wait 18 more cycles for timeout (from trace: err at t18)
    repeat(18) step;
    check(speed_change_err,  1, "T6: speed_change_err=1   ");
    check(speed_change_done, 0, "T6: speed_change_done=0  ");
    check(pipe_rate_out,  4'd1, "T6: rate reverted Gen1   ");
    step;
    check(speed_change_err,  0, "T6: err de-asserted      ");

    // ---------------------------------------------------------------
    // TEST 7: PHY rate echo mismatch -> VERIFY times out
    // ---------------------------------------------------------------
    $display("\n--- TEST 7: PHY rate echo mismatch -> timeout ---");
    do_reset;
    target_speed = 4'b0101;    // Gen5
    pipe_rate    = 4'b0001;    // PHY stays at Gen1 (wrong echo)

    // p0: trigger
    speed_change_en = 1'b1; step; speed_change_en = 1'b0;
    // p1: RETRAIN
    step;
    // p2: assert recovery_done so we move to VERIFY
    recovery_done = 1'b1; step; recovery_done = 1'b0;
    // p3 onward: pipe_rate stays wrong; VERIFY times out at p18 from trigger
    repeat(16) step;
    check(speed_change_err,  1, "T7: speed_change_err=1   ");
    check(speed_change_done, 0, "T7: speed_change_done=0  ");

    // ---------------------------------------------------------------
    // Summary
    // ---------------------------------------------------------------
    $display("\n===================================================");
    $display(" Results: %0d PASS  %0d FAIL", pass_cnt, fail_cnt);
    $display("===================================================\n");
    $finish;
end

initial begin
    $dumpfile("spd_chg.vcd");
    $dumpvars(0, tb_spd_chg);
end

endmodule
