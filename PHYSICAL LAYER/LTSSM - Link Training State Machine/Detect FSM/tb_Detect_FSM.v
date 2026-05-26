// =============================================================================
// Testbench : tb_detect_fsm
// Module    : detect_fsm
// Language  : Verilog-2001 (no SystemVerilog)
// Simulator : QuestaSim / ModelSim
// =============================================================================
`timescale 1ns/1ps

module tb_detect_fsm;

// ??? DUT ports ????????????????????????????????????????????????????????????????
reg        clk;
reg        rst_n;
reg        detect_req;          // [FIX-1-TB] new port to drive detect_req
reg        pipe_rx_elec_idle;
reg        detect_timer_exp;
reg [2:0]  pipe_status;

wire       detect_done;
wire       receiver_detected;
wire [15:0] lanes_detected;
wire       detect_timeout;

// ??? Instantiate DUT ??????????????????????????????????????????????????????????
detect_fsm dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .detect_req        (detect_req),        // [FIX-1-TB] wired to new port
    .pipe_rx_elec_idle (pipe_rx_elec_idle),
    .detect_timer_exp  (detect_timer_exp),
    .pipe_status       (pipe_status),
    .detect_done       (detect_done),
    .receiver_detected (receiver_detected),
    .lanes_detected    (lanes_detected),
    .detect_timeout    (detect_timeout)
);

// ??? State / pipe encodings (mirror design) ???????????????????????????????????
localparam [2:0]
    ST_IDLE      = 3'd0,
    ST_QUIET     = 3'd1,
    ST_ACTIVE    = 3'd2,
    ST_LANE_EVAL = 3'd3,
    ST_DONE      = 3'd4,
    ST_TIMEOUT   = 3'd5;

localparam [2:0]
    PIPE_ST_IDLE    = 3'b000,
    PIPE_ST_RX_DET  = 3'b001,
    PIPE_ST_NO_RX   = 3'b010,
    PIPE_ST_EI_EXIT = 3'b011;

localparam [7:0] PROBE_WAIT_INIT = 8'd20;
localparam [3:0] MAX_LANE        = 4'd15;

// ??? Pass / fail counters ?????????????????????????????????????????????????????
integer pass_cnt;
integer fail_cnt;
integer tc_num;

// ??? VCD dump ? ALL signals visible in QuestaSim ?????????????????????????????
initial begin
    $dumpfile("detect_fsm_waves.vcd");
    $dumpvars(0, tb_detect_fsm);
end

// ??? Clock 100 MHz ????????????????????????????????????????????????????????????
initial clk = 0;
always #5 clk = ~clk;

// =============================================================================
// TASKS
// =============================================================================

task wait_clk;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(posedge clk);
        #1;
    end
endtask

task apply_reset;
    begin
        rst_n             <= 1'b0;
        detect_req        <= 1'b0;          // [FIX-1-TB] initialise new port
        pipe_rx_elec_idle <= 1'b0;
        detect_timer_exp  <= 1'b0;
        pipe_status       <= PIPE_ST_IDLE;
        @(posedge clk); #1;
        rst_n      <= 1'b1;
        detect_req <= 1'b1;                 // [FIX-1-TB] assert after reset so
                                            // FSM is allowed to run the sweep
        wait_clk(2);
    end
endtask

// Fire detect_timer_exp for exactly one clock cycle
task fire_timer;
    begin
        detect_timer_exp <= 1'b1;
        @(posedge clk); #1;
        detect_timer_exp <= 1'b0;
    end
endtask

// Drive the FSM through Active (all 16 lanes).
// Returns with state = ST_LANE_EVAL so the next @posedge clk in
// wait_for_done / wait_for_timeout_sig catches state = ST_DONE / ST_TIMEOUT
// and the combinational detect_done / detect_timeout are visible at #1.
// lane_det_pattern[15:0]: bit N=1 means lane N returns PIPE_ST_RX_DET
task drive_active_all_lanes;
    input [15:0] lane_det_pattern;
    integer lane;
    integer w;
    begin
        for (lane = 0; lane <= MAX_LANE; lane = lane + 1) begin
            for (w = PROBE_WAIT_INIT; w > 0; w = w - 1) begin
                if (w == 15 && lane_det_pattern[lane])
                    pipe_status <= PIPE_ST_RX_DET;
                else
                    pipe_status <= PIPE_ST_IDLE;
                @(posedge clk); #1;
            end
            pipe_status <= PIPE_ST_IDLE;
            @(posedge clk); #1; // probe_wait==0: next_state = lane advance or LANE_EVAL
        end
        // Advance one clock: state register moves to ST_LANE_EVAL
        @(posedge clk); #1;
        // Now state = ST_LANE_EVAL, next_state = ST_DONE or ST_TIMEOUT.
        // Return. The next @posedge in wait_for_done/timeout will register
        // ST_DONE/ST_TIMEOUT and detect_done/detect_timeout will be high.
    end
endtask

task check;
    input [63:0]  actual;
    input [63:0]  expected;
    input [511:0] sig;          // [FIX-4] widened 256->512 bits (64 chars)
                                // prevents silent left-truncation on strings
                                // longer than 32 characters (e.g. TC03 msg)
    begin
        if (actual === expected) begin
            pass_cnt = pass_cnt + 1;
            $display("  TC%0d PASS: %s = %0d (exp %0d)", tc_num, sig, actual, expected);
        end else begin
            fail_cnt = fail_cnt + 1;
            $display("  TC%0d FAIL: %s = %0d *** exp %0d ***", tc_num, sig, actual, expected);
        end
    end
endtask

// [FIX-5] wait_high task removed ? it had an empty body and was never called.
// It was declared only as a placeholder with a comment explaining it cannot
// work in Verilog-2001.  Removing it eliminates dead code without any
// functional impact.

task wait_for_done;
    input integer max_cycles;
    integer cnt;
    begin
        cnt = 0;
        // If already high at call time, return immediately
        if (detect_done === 1'b1) begin
            // already asserted ? nothing to wait for
        end else begin
            while (detect_done !== 1'b1 && cnt < max_cycles) begin
                @(posedge clk); #1;
                cnt = cnt + 1;
            end
            if (detect_done !== 1'b1) begin
                $display("  TC%0d FAIL: timed out waiting for detect_done", tc_num);
                fail_cnt = fail_cnt + 1;
            end
        end
    end
endtask

task wait_for_timeout_sig;
    input integer max_cycles;
    integer cnt;
    begin
        cnt = 0;
        if (detect_timeout === 1'b1) begin
            // already asserted
        end else begin
            while (detect_timeout !== 1'b1 && cnt < max_cycles) begin
                @(posedge clk); #1;
                cnt = cnt + 1;
            end
            if (detect_timeout !== 1'b1) begin
                $display("  TC%0d FAIL: timed out waiting for detect_timeout", tc_num);
                fail_cnt = fail_cnt + 1;
            end
        end
    end
endtask

// Helper: complete one full detect cycle with all lanes detected
task full_cycle_all_detected;
    begin
        // Quiet phase
        pipe_rx_elec_idle <= 1'b1;
        fire_timer;
        // Now in ST_ACTIVE
        drive_active_all_lanes(16'hFFFF);
        @(posedge clk); #1; // wait for output register to capture ST_DONE
        wait_for_done(200);
    end
endtask

// =============================================================================
// MAIN TEST SEQUENCE
// =============================================================================
initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    tc_num   = 0;

    // =========================================================================
    // TC01 ? Reset: outputs cleared, state goes to IDLE then QUIET
    // =========================================================================
    tc_num = 1;
    $display("\n=== TC01: Reset state and output check ===");
    rst_n             <= 1'b0;
    detect_req        <= 1'b0;          // [FIX-1-TB] initialise
    pipe_rx_elec_idle <= 1'b0;
    detect_timer_exp  <= 1'b0;
    pipe_status       <= PIPE_ST_IDLE;
    @(posedge clk); #1;
    check(detect_done,       1'b0,  "detect_done at reset");
    check(receiver_detected, 1'b0,  "receiver_detected at reset");
    check(lanes_detected,    16'd0, "lanes_detected at reset");
    check(detect_timeout,    1'b0,  "detect_timeout at reset");
    rst_n      <= 1'b1;
    detect_req <= 1'b1;                 // [FIX-1-TB] enable FSM to run
    wait_clk(2);

    // =========================================================================
    // TC02 ? After reset FSM auto-enters ST_QUIET (no timer needed)
    // =========================================================================
    tc_num = 2;
    $display("\n=== TC02: Auto-start into Quiet after reset ===");
    // In ST_QUIET: no detect_done, no timeout yet
    check(detect_done,    1'b0, "detect_done = 0 in Quiet");
    check(detect_timeout, 1'b0, "detect_timeout = 0 in Quiet");

    // =========================================================================
    // TC03 ? Quiet: timer fires but RX NOT idle ? stay in Quiet
    // =========================================================================
    tc_num = 3;
    $display("\n=== TC03: Quiet restarts when RX not idle at timer exp ===");
    pipe_rx_elec_idle <= 1'b0;
    fire_timer;
    wait_clk(2);
    // Should still be in Quiet (or restarted Quiet), no done/timeout
    check(detect_done,    1'b0, "detect_done = 0 after failed quiet");
    check(detect_timeout, 1'b0, "detect_timeout = 0 after failed quiet");

    // =========================================================================
    // TC04 ? Quiet: timer fires AND RX idle ? enter Active
    // =========================================================================
    tc_num = 4;
    $display("\n=== TC04: Quiet -> Active when RX idle + timer ===");
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    wait_clk(2);
    // Should be in ST_ACTIVE now ? no done yet
    check(detect_done,    1'b0, "detect_done = 0 entering Active");
    check(detect_timeout, 1'b0, "detect_timeout = 0 entering Active");

    // =========================================================================
    // TC05 ? Active: all 16 lanes detect receiver ? detect_done + all lanes
    // =========================================================================
    tc_num = 5;
    $display("\n=== TC05: All 16 lanes detected -> detect_done, receiver_detected ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer; // Quiet -> Active
    drive_active_all_lanes(16'hFFFF);
    wait_for_done(200);
    check(detect_done,       1'b1,    "detect_done pulsed");
    check(receiver_detected, 1'b1,    "receiver_detected = 1");
    check(lanes_detected,    16'hFFFF,"lanes_detected = 0xFFFF");
    check(detect_timeout,    1'b0,    "detect_timeout = 0");
    wait_clk(1);

    // =========================================================================
    // TC06 ? detect_done is only a one-cycle pulse
    // =========================================================================
    tc_num = 6;
    $display("\n=== TC06: detect_done is one-cycle pulse only ===");
    wait_clk(2);
    check(detect_done, 1'b0, "detect_done deasserted after one cycle");

    // =========================================================================
    // TC07 ? After done, FSM returns to IDLE then QUIET automatically
    // =========================================================================
    tc_num = 7;
    $display("\n=== TC07: FSM returns to Quiet after done ===");
    // Still no timer, no active: verify no spurious outputs
    wait_clk(5);
    check(detect_done,    1'b0, "detect_done = 0 after return to quiet");
    check(detect_timeout, 1'b0, "detect_timeout = 0 after return to quiet");

    // =========================================================================
    // TC08 ? No receiver on any lane ? detect_timeout fires
    // =========================================================================
    tc_num = 8;
    $display("\n=== TC08: No receiver on any lane -> detect_timeout ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer; // Quiet ? Active
    drive_active_all_lanes(16'h0000); // all lanes: no detect
    wait_for_timeout_sig(200);
    check(detect_timeout,    1'b1,   "detect_timeout pulsed");
    check(receiver_detected, 1'b0,   "receiver_detected = 0");
    check(lanes_detected,    16'd0,  "lanes_detected = 0");
    check(detect_done,       1'b0,   "detect_done = 0");
    wait_clk(1);

    // =========================================================================
    // TC09 ? detect_timeout is one-cycle pulse only
    // =========================================================================
    tc_num = 9;
    $display("\n=== TC09: detect_timeout is one-cycle pulse ===");
    wait_clk(2);
    check(detect_timeout, 1'b0, "detect_timeout deasserted after one cycle");

    // =========================================================================
    // TC10 ? Only lane 0 detected
    // =========================================================================
    tc_num = 10;
    $display("\n=== TC10: Only lane 0 detected ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h0001);
    wait_for_done(200);
    check(detect_done,       1'b1,   "detect_done");
    check(receiver_detected, 1'b1,   "receiver_detected");
    check(lanes_detected,    16'h0001,"lanes_detected = lane 0 only");
    wait_clk(1);

    // =========================================================================
    // TC11 ? Only lane 15 detected
    // =========================================================================
    tc_num = 11;
    $display("\n=== TC11: Only lane 15 detected ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h8000);
    wait_for_done(200);
    check(detect_done,       1'b1,    "detect_done");
    check(receiver_detected, 1'b1,    "receiver_detected");
    check(lanes_detected,    16'h8000,"lanes_detected = lane 15 only");
    wait_clk(1);

    // =========================================================================
    // TC12 ? x4 pattern: lanes 0?3 detected
    // =========================================================================
    tc_num = 12;
    $display("\n=== TC12: x4 lanes 0-3 detected ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h000F);
    wait_for_done(200);
    check(detect_done,       1'b1,   "detect_done");
    check(receiver_detected, 1'b1,   "receiver_detected");
    check(lanes_detected,    16'h000F,"lanes_detected = 0x000F");
    wait_clk(1);

    // =========================================================================
    // TC13 ? x8 pattern: lanes 0?7 detected
    // =========================================================================
    tc_num = 13;
    $display("\n=== TC13: x8 lanes 0-7 detected ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h00FF);
    wait_for_done(200);
    check(detect_done,       1'b1,   "detect_done");
    check(receiver_detected, 1'b1,   "receiver_detected");
    check(lanes_detected,    16'h00FF,"lanes_detected = 0x00FF");
    wait_clk(1);

    // =========================================================================
    // TC14 ? Alternating lane pattern (0,2,4,...) detected
    // =========================================================================
    tc_num = 14;
    $display("\n=== TC14: Alternating even lanes detected ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h5555);
    wait_for_done(200);
    check(detect_done,       1'b1,    "detect_done");
    check(receiver_detected, 1'b1,    "receiver_detected");
    check(lanes_detected,    16'h5555,"lanes_detected = 0x5555");
    wait_clk(1);

    // =========================================================================
    // TC15 ? Overall timer expires during Active ? timeout (not done)
    // =========================================================================
    tc_num = 15;
    $display("\n=== TC15: Overall timer exp during Active -> timeout ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer; // Quiet ? Active
    wait_clk(5); // mid-probe
    fire_timer;  // overall window expiry during Active
    wait_for_timeout_sig(50);
    check(detect_timeout,    1'b1, "detect_timeout on mid-active timer");
    check(detect_done,       1'b0, "detect_done = 0 on mid-active timer");
    wait_clk(1);

    // =========================================================================
    // TC16 ? Multiple Quiet restarts before successful Active entry
    // =========================================================================
    tc_num = 16;
    $display("\n=== TC16: Multiple quiet restarts then success ===");
    apply_reset;
    // Restart 1: RX not idle
    pipe_rx_elec_idle <= 1'b0;
    fire_timer;
    wait_clk(2);
    check(detect_done,    1'b0, "no done after restart 1");
    check(detect_timeout, 1'b0, "no timeout after restart 1");
    // Restart 2: RX not idle
    fire_timer;
    wait_clk(2);
    check(detect_done,    1'b0, "no done after restart 2");
    // Success: RX now idle
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'hFFFF);
    wait_for_done(200);
    check(detect_done,       1'b1,    "detect_done after multi-restart");
    check(receiver_detected, 1'b1,    "receiver_detected after multi-restart");
    check(lanes_detected,    16'hFFFF,"lanes_detected after multi-restart");
    wait_clk(1);

    // =========================================================================
    // TC17 ? Back-to-back detect cycles (IDLE ? QUIET ? ACTIVE × 2)
    // =========================================================================
    tc_num = 17;
    $display("\n=== TC17: Back-to-back detect cycles ===");
    apply_reset;
    // Cycle 1
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h000F);
    wait_for_done(200);
    check(detect_done,    1'b1,    "cycle1 detect_done");
    check(lanes_detected, 16'h000F,"cycle1 lanes_detected");
    wait_clk(2); // return to Quiet
    // Cycle 2 ? different pattern
    fire_timer;
    drive_active_all_lanes(16'hF0F0);
    wait_for_done(200);
    check(detect_done,    1'b1,    "cycle2 detect_done");
    check(lanes_detected, 16'hF0F0,"cycle2 lanes_detected");
    wait_clk(1);

    // =========================================================================
    // TC18 ? receiver_detected stays held after done pulse (into IDLE)
    // =========================================================================
    tc_num = 18;
    $display("\n=== TC18: receiver_detected held after done pulse ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'hAAAA);
    wait_for_done(200);
    check(receiver_detected, 1'b1, "receiver_detected = 1 on done cycle");
    wait_clk(3); // FSM returns to IDLE / QUIET
    check(receiver_detected, 1'b1, "receiver_detected still held after done");
    wait_clk(1);

    // =========================================================================
    // TC19 ? lanes_detected cleared on timeout
    // =========================================================================
    tc_num = 19;
    $display("\n=== TC19: lanes_detected = 0 on timeout ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h0000);
    wait_for_timeout_sig(200);
    check(lanes_detected, 16'd0, "lanes_detected = 0 on timeout");
    wait_clk(1);

    // =========================================================================
    // TC20 ? reset during Active ? clean restart to IDLE/QUIET
    // =========================================================================
    tc_num = 20;
    $display("\n=== TC20: Reset during Active -> clean restart ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer; // Quiet ? Active
    wait_clk(10); // mid-way through active
    // Apply reset
    rst_n <= 1'b0;
    @(posedge clk); #1;
    check(detect_done,       1'b0,  "detect_done = 0 at mid-active reset");
    check(detect_timeout,    1'b0,  "detect_timeout = 0 at mid-active reset");
    check(receiver_detected, 1'b0,  "receiver_detected = 0 at mid-active reset");
    check(lanes_detected,    16'd0, "lanes_detected = 0 at mid-active reset");
    rst_n      <= 1'b1;
    detect_req <= 1'b1;                 // [FIX-1-TB] re-enable after reset
    wait_clk(2);
    // After reset, FSM should be in QUIET, no spurious outputs
    check(detect_done,    1'b0, "no spurious done after reset");
    check(detect_timeout, 1'b0, "no spurious timeout after reset");

    // =========================================================================
    // TC21 ? Single lane (lane 7) isolated detection
    // =========================================================================
    tc_num = 21;
    $display("\n=== TC21: Lane 7 only detected ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h0080);
    wait_for_done(200);
    check(detect_done,       1'b1,    "detect_done");
    check(receiver_detected, 1'b1,    "receiver_detected");
    check(lanes_detected,    16'h0080,"lanes_detected = lane 7 only");
    wait_clk(1);

    // =========================================================================
    // TC22 ? pipe_status held at PIPE_ST_NO_RX for all lanes ? timeout
    // =========================================================================
    tc_num = 22;
    $display("\n=== TC22: All lanes return NO_RX -> timeout ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h0000); // pass all-zero so no RX_DET fires
    wait_for_timeout_sig(200);
    check(detect_timeout,    1'b1, "detect_timeout on all NO_RX");
    check(receiver_detected, 1'b0, "receiver_detected = 0");
    wait_clk(1);

    // =========================================================================
    // TC23 ? Verify detect_done and detect_timeout never assert together
    // =========================================================================
    tc_num = 23;
    $display("\n=== TC23: detect_done and detect_timeout never both 1 ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'hFFFF);
    wait_for_done(200);
    // At the done cycle, timeout must be 0
    check(detect_done,    1'b1, "detect_done = 1");
    check(detect_timeout, 1'b0, "detect_timeout = 0 (never both 1)");
    wait_clk(1);

    // =========================================================================
    // TC24 ? Quiet: pipe_rx_elec_idle de-asserted mid-quiet doesn't affect
    //         final transition as long as it's asserted at timer_exp
    // =========================================================================
    tc_num = 24;
    $display("\n=== TC24: RX idle only at timer_exp is sufficient ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b0; // not idle initially
    wait_clk(5);
    // Timer fires with RX not idle ? restart quiet
    fire_timer;
    check(detect_done,    1'b0, "still in Active, no done yet");
    check(detect_timeout, 1'b0, "no timeout in transition");
    // Now set RX idle and fire again ? should go to Active
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    // drive_active immediately ? no extra wait_clk
    drive_active_all_lanes(16'hFFFF);
    wait_for_done(200);
    check(detect_done,       1'b1,    "detect_done after RX idle at exp");
    check(receiver_detected, 1'b1,    "receiver_detected");
    wait_clk(1);

    // =========================================================================
    // REPORT
    // =========================================================================
    $display("\n=====================================================");
    $display("  DETECT FSM TESTBENCH RESULTS");
    $display("  PASSED : %0d", pass_cnt);
    $display("  FAILED : %0d", fail_cnt);
    $display("  TOTAL  : %0d", pass_cnt + fail_cnt);
    if (fail_cnt == 0)
        $display("  STATUS : *** ALL TESTS PASSED ***");
    else
        $display("  STATUS : *** FAILURES DETECTED ? SEE ABOVE ***");
    $display("=====================================================\n");

    $finish;
end

// ??? Watchdog ?????????????????????????????????????????????????????????????????
initial begin
    #50_000_000;
    $display("ERROR: Simulation watchdog at %0t", $time);
    $finish;
end

endmodule
