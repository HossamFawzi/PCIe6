// =============================================================================
// Testbench : tb_lane_rev
// DUT       : lane_rev  ?  Lane Reversal Logic
// =============================================================================
`timescale 1ns/1ps

module tb_lane_rev;

// ?? DUT ports ??????????????????????????????????????????????????????????????
reg        clk;
reg        rst_n;
reg  [7:0] ts1_lane_num;
reg  [7:0] local_lane_id;
reg        reversal_det;

wire [3:0] lane_map;
wire       reversal_active;

// ?? DUT instantiation ??????????????????????????????????????????????????????
lane_rev dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .ts1_lane_num   (ts1_lane_num),
    .local_lane_id  (local_lane_id),
    .reversal_det   (reversal_det),
    .lane_map       (lane_map),
    .reversal_active(reversal_active)
);

// ?? Clock ??????????????????????????????????????????????????????????????????
initial clk = 0;
always #5 clk = ~clk;

// ?? Checker ????????????????????????????????????????????????????????????????
integer pass_cnt, fail_cnt;

task check;
    input [63:0] actual;
    input [63:0] expected;
    input [255:0] msg;
begin
    if (actual === expected) begin
        $display("  PASS | %s  actual=%0d  expected=%0d", msg, actual, expected);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("  FAIL | %s  actual=%0d  expected=%0d  *** MISMATCH ***",
                 msg, actual, expected);
        fail_cnt = fail_cnt + 1;
    end
end
endtask

// ?? Reset task ?????????????????????????????????????????????????????????????
task do_reset;
begin
    rst_n        = 1'b0;
    ts1_lane_num = 8'd0;
    local_lane_id = 8'd0;
    reversal_det  = 1'b0;
    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
end
endtask

// ?? Main stimulus ???????????????????????????????????????????????????????????
initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    $display("\n===================================================");
    $display(" TB: lane_rev ? Lane Reversal Logic");
    $display("===================================================\n");

    // ------------------------------------------------------------------
    // TEST 1: Reset state ? no reversal, lane_map = 0
    // ------------------------------------------------------------------
    $display("--- TEST 1: Reset state ---");
    do_reset;
    local_lane_id = 8'd0;
    ts1_lane_num  = 8'd0;
    @(posedge clk); #1;
    check(reversal_active, 0, "reversal_active after reset");
    check(lane_map,        0, "lane_map = local_lane_id after reset");

    // ------------------------------------------------------------------
    // TEST 2: Normal (no reversal) ? lane_map tracks local_lane_id
    // ------------------------------------------------------------------
    $display("\n--- TEST 2: Normal mode, x16 link ---");
    do_reset;
    begin : test2
        integer i;
        for (i = 0; i < 16; i = i + 1) begin
            local_lane_id = i[7:0];
            ts1_lane_num  = i[7:0];  // TS1 matches local ? no reversal
            reversal_det  = 1'b0;
            @(posedge clk); #1;
            check(reversal_active, 0, "reversal_active=0 normal mode");
            check(lane_map, i[3:0], "lane_map = local_lane_id");
        end
    end

    // ------------------------------------------------------------------
    // TEST 3: reversal_det from external block
    // ------------------------------------------------------------------
    $display("\n--- TEST 3: Reversal via external reversal_det signal ---");
    do_reset;
    local_lane_id = 8'd0;
    ts1_lane_num  = 8'd0;
    reversal_det  = 1'b1;  // External detection
    @(posedge clk); #1;
    reversal_det  = 1'b0;

    @(posedge clk); #1;
    check(reversal_active, 1, "reversal_active after reversal_det");
    // Lane 0 reversed in x16: map = 15 - 0 = 15
    check(lane_map, 4'd15, "lane_map[0] reversed = 15");

    // Lane 7 reversed: map = 15 - 7 = 8
    local_lane_id = 8'd7;
    @(posedge clk); #1;
    check(lane_map, 4'd8, "lane_map[7] reversed = 8");

    // Lane 15 reversed: map = 15 - 15 = 0
    local_lane_id = 8'd15;
    @(posedge clk); #1;
    check(lane_map, 4'd0, "lane_map[15] reversed = 0");

    // ------------------------------------------------------------------
    // TEST 4: Auto-detect via TS1 lane number mismatch
    //   Physical lane 3 receives TS1 lane_num = 12 (mirror of 15-3=12)
    // ------------------------------------------------------------------
    $display("\n--- TEST 4: Auto-detect via TS1 lane num mismatch ---");
    do_reset;
    local_lane_id = 8'd3;
    ts1_lane_num  = 8'd12;   // 15 - 3 = 12 ? reversed
    reversal_det  = 1'b0;
    @(posedge clk); #1;

    @(posedge clk); #1;
    check(reversal_active, 1, "reversal_active auto-detected");
    check(lane_map, 4'd12, "lane_map = 15-3 = 12");

    // ------------------------------------------------------------------
    // TEST 5: Reversal is sticky after detection event clears
    // ------------------------------------------------------------------
    $display("\n--- TEST 5: Reversal sticky after signal clears ---");
    // (continued from Test 4 ? reversed_r still set)
    ts1_lane_num = 8'd3;   // Now TS1 matches local (would be normal)
    @(posedge clk); #1;
    check(reversal_active, 1, "reversal_active remains sticky");

    // ------------------------------------------------------------------
    // TEST 6: Reset clears reversal state
    // ------------------------------------------------------------------
    $display("\n--- TEST 6: Reset clears reversal ---");
    do_reset;
    local_lane_id = 8'd5;
    @(posedge clk); #1;
    check(reversal_active, 0, "reversal_active cleared after reset");
    check(lane_map, 4'd5, "lane_map normal after reset");

    // ------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------
    $display("\n===================================================");
    $display(" Results: %0d PASS  %0d FAIL", pass_cnt, fail_cnt);
    $display("===================================================\n");
    $finish;
end

initial begin
    $dumpfile("lane_rev.vcd");
    $dumpvars(0, tb_lane_rev);
end

endmodule
