
`timescale 1ns/1ps

module tb_detect_fsm;

reg        clk;
reg        rst_n;
reg        detect_req;
reg        pipe_rx_elec_idle;
reg        detect_timer_exp;
reg [2:0]  pipe_status;

wire       detect_done;
wire       receiver_detected;
wire [15:0] lanes_detected;
wire       detect_timeout;

detect_fsm dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .detect_req        (detect_req),
    .pipe_rx_elec_idle (pipe_rx_elec_idle),
    .detect_timer_exp  (detect_timer_exp),
    .pipe_status       (pipe_status),
    .detect_done       (detect_done),
    .receiver_detected (receiver_detected),
    .lanes_detected    (lanes_detected),
    .detect_timeout    (detect_timeout)
);

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

integer pass_cnt;
integer fail_cnt;
integer tc_num;

initial begin
    $dumpfile("detect_fsm_waves.vcd");
    $dumpvars(0, tb_detect_fsm);
end

initial clk = 0;
always #5 clk = ~clk;

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
        detect_req        <= 1'b0;
        pipe_rx_elec_idle <= 1'b0;
        detect_timer_exp  <= 1'b0;
        pipe_status       <= PIPE_ST_IDLE;
        @(posedge clk); #1;
        rst_n      <= 1'b1;
        detect_req <= 1'b1;

        wait_clk(2);
    end
endtask

task fire_timer;
    begin
        detect_timer_exp <= 1'b1;
        @(posedge clk); #1;
        detect_timer_exp <= 1'b0;
    end
endtask

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
            @(posedge clk); #1;
        end

        @(posedge clk); #1;

    end
endtask

task check;
    input [63:0]  actual;
    input [63:0]  expected;
    input [511:0] sig;

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

task wait_for_done;
    input integer max_cycles;
    integer cnt;
    begin
        cnt = 0;

        if (detect_done === 1'b1) begin

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

task full_cycle_all_detected;
    begin

        pipe_rx_elec_idle <= 1'b1;
        fire_timer;

        drive_active_all_lanes(16'hFFFF);
        @(posedge clk); #1;
        wait_for_done(200);
    end
endtask

initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    tc_num   = 0;

    tc_num = 1;
    $display("\n=== TC01: Reset state and output check ===");
    rst_n             <= 1'b0;
    detect_req        <= 1'b0;
    pipe_rx_elec_idle <= 1'b0;
    detect_timer_exp  <= 1'b0;
    pipe_status       <= PIPE_ST_IDLE;
    @(posedge clk); #1;
    check(detect_done,       1'b0,  "detect_done at reset");
    check(receiver_detected, 1'b0,  "receiver_detected at reset");
    check(lanes_detected,    16'd0, "lanes_detected at reset");
    check(detect_timeout,    1'b0,  "detect_timeout at reset");
    rst_n      <= 1'b1;
    detect_req <= 1'b1;
    wait_clk(2);

    tc_num = 2;
    $display("\n=== TC02: Auto-start into Quiet after reset ===");

    check(detect_done,    1'b0, "detect_done = 0 in Quiet");
    check(detect_timeout, 1'b0, "detect_timeout = 0 in Quiet");

    tc_num = 3;
    $display("\n=== TC03: Quiet restarts when RX not idle at timer exp ===");
    pipe_rx_elec_idle <= 1'b0;
    fire_timer;
    wait_clk(2);

    check(detect_done,    1'b0, "detect_done = 0 after failed quiet");
    check(detect_timeout, 1'b0, "detect_timeout = 0 after failed quiet");

    tc_num = 4;
    $display("\n=== TC04: Quiet -> Active when RX idle + timer ===");
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    wait_clk(2);

    check(detect_done,    1'b0, "detect_done = 0 entering Active");
    check(detect_timeout, 1'b0, "detect_timeout = 0 entering Active");

    tc_num = 5;
    $display("\n=== TC05: All 16 lanes detected -> detect_done, receiver_detected ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'hFFFF);
    wait_for_done(200);
    check(detect_done,       1'b1,    "detect_done pulsed");
    check(receiver_detected, 1'b1,    "receiver_detected = 1");
    check(lanes_detected,    16'hFFFF,"lanes_detected = 0xFFFF");
    check(detect_timeout,    1'b0,    "detect_timeout = 0");
    wait_clk(1);

    tc_num = 6;
    $display("\n=== TC06: detect_done is one-cycle pulse only ===");
    wait_clk(2);
    check(detect_done, 1'b0, "detect_done deasserted after one cycle");

    tc_num = 7;
    $display("\n=== TC07: FSM returns to Quiet after done ===");

    wait_clk(5);
    check(detect_done,    1'b0, "detect_done = 0 after return to quiet");
    check(detect_timeout, 1'b0, "detect_timeout = 0 after return to quiet");

    tc_num = 8;
    $display("\n=== TC08: No receiver on any lane -> detect_timeout ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h0000);
    wait_for_timeout_sig(200);
    check(detect_timeout,    1'b1,   "detect_timeout pulsed");
    check(receiver_detected, 1'b0,   "receiver_detected = 0");
    check(lanes_detected,    16'd0,  "lanes_detected = 0");
    check(detect_done,       1'b0,   "detect_done = 0");
    wait_clk(1);

    tc_num = 9;
    $display("\n=== TC09: detect_timeout is one-cycle pulse ===");
    wait_clk(2);
    check(detect_timeout, 1'b0, "detect_timeout deasserted after one cycle");

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

    tc_num = 15;
    $display("\n=== TC15: Overall timer exp during Active -> timeout ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    wait_clk(5);
    fire_timer;
    wait_for_timeout_sig(50);
    check(detect_timeout,    1'b1, "detect_timeout on mid-active timer");
    check(detect_done,       1'b0, "detect_done = 0 on mid-active timer");
    wait_clk(1);

    tc_num = 16;
    $display("\n=== TC16: Multiple quiet restarts then success ===");
    apply_reset;

    pipe_rx_elec_idle <= 1'b0;
    fire_timer;
    wait_clk(2);
    check(detect_done,    1'b0, "no done after restart 1");
    check(detect_timeout, 1'b0, "no timeout after restart 1");

    fire_timer;
    wait_clk(2);
    check(detect_done,    1'b0, "no done after restart 2");

    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'hFFFF);
    wait_for_done(200);
    check(detect_done,       1'b1,    "detect_done after multi-restart");
    check(receiver_detected, 1'b1,    "receiver_detected after multi-restart");
    check(lanes_detected,    16'hFFFF,"lanes_detected after multi-restart");
    wait_clk(1);

    tc_num = 17;
    $display("\n=== TC17: Back-to-back detect cycles ===");
    apply_reset;

    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h000F);
    wait_for_done(200);
    check(detect_done,    1'b1,    "cycle1 detect_done");
    check(lanes_detected, 16'h000F,"cycle1 lanes_detected");
    wait_clk(2);

    fire_timer;
    drive_active_all_lanes(16'hF0F0);
    wait_for_done(200);
    check(detect_done,    1'b1,    "cycle2 detect_done");
    check(lanes_detected, 16'hF0F0,"cycle2 lanes_detected");
    wait_clk(1);

    tc_num = 18;
    $display("\n=== TC18: receiver_detected held after done pulse ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'hAAAA);
    wait_for_done(200);
    check(receiver_detected, 1'b1, "receiver_detected = 1 on done cycle");
    wait_clk(3);
    check(receiver_detected, 1'b1, "receiver_detected still held after done");
    wait_clk(1);

    tc_num = 19;
    $display("\n=== TC19: lanes_detected = 0 on timeout ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h0000);
    wait_for_timeout_sig(200);
    check(lanes_detected, 16'd0, "lanes_detected = 0 on timeout");
    wait_clk(1);

    tc_num = 20;
    $display("\n=== TC20: Reset during Active -> clean restart ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    wait_clk(10);

    rst_n <= 1'b0;
    @(posedge clk); #1;
    check(detect_done,       1'b0,  "detect_done = 0 at mid-active reset");
    check(detect_timeout,    1'b0,  "detect_timeout = 0 at mid-active reset");
    check(receiver_detected, 1'b0,  "receiver_detected = 0 at mid-active reset");
    check(lanes_detected,    16'd0, "lanes_detected = 0 at mid-active reset");
    rst_n      <= 1'b1;
    detect_req <= 1'b1;
    wait_clk(2);

    check(detect_done,    1'b0, "no spurious done after reset");
    check(detect_timeout, 1'b0, "no spurious timeout after reset");

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

    tc_num = 22;
    $display("\n=== TC22: All lanes return NO_RX -> timeout ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'h0000);
    wait_for_timeout_sig(200);
    check(detect_timeout,    1'b1, "detect_timeout on all NO_RX");
    check(receiver_detected, 1'b0, "receiver_detected = 0");
    wait_clk(1);

    tc_num = 23;
    $display("\n=== TC23: detect_done and detect_timeout never both 1 ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b1;
    fire_timer;
    drive_active_all_lanes(16'hFFFF);
    wait_for_done(200);

    check(detect_done,    1'b1, "detect_done = 1");
    check(detect_timeout, 1'b0, "detect_timeout = 0 (never both 1)");
    wait_clk(1);

    tc_num = 24;
    $display("\n=== TC24: RX idle only at timer_exp is sufficient ===");
    apply_reset;
    pipe_rx_elec_idle <= 1'b0;
    wait_clk(5);

    fire_timer;
    check(detect_done,    1'b0, "still in Active, no done yet");
    check(detect_timeout, 1'b0, "no timeout in transition");

    pipe_rx_elec_idle <= 1'b1;
    fire_timer;

    drive_active_all_lanes(16'hFFFF);
    wait_for_done(200);
    check(detect_done,       1'b1,    "detect_done after RX idle at exp");
    check(receiver_detected, 1'b1,    "receiver_detected");
    wait_clk(1);

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

initial begin
    #50_000_000;
    $display("ERROR: Simulation watchdog at %0t", $time);
    $finish;
end

endmodule
