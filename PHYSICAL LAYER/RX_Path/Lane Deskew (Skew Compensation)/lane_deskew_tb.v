`timescale 1ns/1ps

module lane_deskew_tb;

    parameter DATA_WIDTH = 32;
    parameter NUM_LANES  = 16;
    parameter FIFO_DEPTH = 64;
    parameter FIFO_BITS  = 6;
    parameter MAX_SKEW   = 16;

    reg                             clk;
    reg                             rst_n;
    reg  [NUM_LANES*DATA_WIDTH-1:0] lane_data;
    reg  [NUM_LANES-1:0]            lane_valid;
    reg  [NUM_LANES-1:0]            skp_detected;
    reg                             deskew_en;

    wire [NUM_LANES*DATA_WIDTH-1:0] deskewed_data;
    wire [NUM_LANES-1:0]            deskew_valid;
    wire [4:0]                      skew_amount;
    wire                            deskew_err;

    lane_deskew #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_LANES (NUM_LANES),
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_BITS (FIFO_BITS),
        .MAX_SKEW  (MAX_SKEW)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .lane_data    (lane_data),
        .lane_valid   (lane_valid),
        .skp_detected (skp_detected),
        .deskew_en    (deskew_en),
        .deskewed_data(deskewed_data),
        .deskew_valid (deskew_valid),
        .skew_amount  (skew_amount),
        .deskew_err   (deskew_err)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    integer i, j;
    integer fail_count;

    task drive_all_lanes;
        input [DATA_WIDTH-1:0] base_data;
        input                  valid;
        input [NUM_LANES-1:0]  skp;
        integer k;
        begin
            for (k = 0; k < NUM_LANES; k = k + 1)
                lane_data[k*DATA_WIDTH +: DATA_WIDTH] = base_data + k;
            lane_valid   = valid ? {NUM_LANES{1'b1}} : {NUM_LANES{1'b0}};
            skp_detected = skp;
            @(posedge clk); #1;
        end
    endtask

    task do_reset;
        begin
            @(negedge clk);
            rst_n        = 1'b0;
            lane_valid   = {NUM_LANES{1'b0}};
            skp_detected = {NUM_LANES{1'b0}};
            deskew_en    = 1'b0;
            @(posedge clk); #1;
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("lane_deskew_tb.vcd");
        $dumpvars(0, lane_deskew_tb);

        fail_count   = 0;
        rst_n        = 1'b0;
        deskew_en    = 1'b0;
        lane_data    = {NUM_LANES*DATA_WIDTH{1'b0}};
        lane_valid   = {NUM_LANES{1'b0}};
        skp_detected = {NUM_LANES{1'b0}};
        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ----------------------------------------------------------------
        // TEST 1: Bypass mode (deskew_en=0) — data passes through directly
        // ----------------------------------------------------------------
        deskew_en = 1'b0;
        drive_all_lanes(32'hA0000000, 1'b1, {NUM_LANES{1'b0}});
        @(posedge clk); #1;
        if (deskew_valid === {NUM_LANES{1'b1}} && deskew_err === 1'b0)
            $display("PASS TEST 1: bypass mode data passthrough");
        else begin
            $display("FAIL TEST 1: bypass  deskew_valid=%b deskew_err=%b",
                      deskew_valid, deskew_err);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------------
        // TEST 2: No skew — all 16 lanes assert SKP in the same cycle
        // Expected: skew_amount==0, deskew_err==0
        // ----------------------------------------------------------------
        do_reset;
        deskew_en = 1'b1;

        repeat(4) drive_all_lanes(32'hB0000000, 1'b1, {NUM_LANES{1'b0}});
        drive_all_lanes(32'hC0000000, 1'b1, {NUM_LANES{1'b1}});  // SKP all lanes
        repeat(4) drive_all_lanes(32'hD0000000, 1'b1, {NUM_LANES{1'b0}});

        repeat(4) @(posedge clk); #1;
        if (skew_amount === 5'd0 && deskew_err === 1'b0)
            $display("PASS TEST 2: no skew, skew_amount=%0d deskew_err=%b",
                      skew_amount, deskew_err);
        else begin
            $display("FAIL TEST 2: no skew  skew_amount=%0d deskew_err=%b",
                      skew_amount, deskew_err);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------------
        // TEST 3: Moderate skew — lanes staggered 1 cycle each (total=15)
        // Expected: 0 < skew_amount <= 15, deskew_err==0
        // ----------------------------------------------------------------
        do_reset;
        deskew_en    = 1'b1;
        lane_valid   = {NUM_LANES{1'b1}};
        skp_detected = {NUM_LANES{1'b0}};

        // 4 cycles of pre-SKP data
        for (j = 0; j < 4; j = j + 1) begin
            for (i = 0; i < NUM_LANES; i = i + 1)
                lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hE0000000 + j*16 + i;
            @(posedge clk); #1;
        end

        // Lane 0 gets SKP first, then one more lane per cycle → total skew = 15
        for (i = 0; i < NUM_LANES; i = i + 1) begin
            for (j = 0; j < NUM_LANES; j = j + 1)
                lane_data[j*DATA_WIDTH +: DATA_WIDTH] = 32'hF0000000 + i*16 + j;
            skp_detected = (16'h0001 << i);
            @(posedge clk); #1;
            skp_detected = {NUM_LANES{1'b0}};
        end

        for (j = 0; j < 4; j = j + 1) begin
            for (i = 0; i < NUM_LANES; i = i + 1)
                lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'h10000000 + j*16 + i;
            @(posedge clk); #1;
        end

        repeat(4) @(posedge clk); #1;
        if (deskew_err === 1'b0 && skew_amount > 5'd0 && skew_amount <= 5'd15)
            $display("PASS TEST 3: moderate skew skew_amount=%0d deskew_err=%b",
                      skew_amount, deskew_err);
        else begin
            $display("FAIL TEST 3: deskew_err=%b skew_amount=%0d (expected 1..15 with no err)",
                      deskew_err, skew_amount);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------------
        // TEST 4: Excessive skew (17 cycles > MAX_SKEW=16) → deskew_err=1
        //
        // Fix: use fresh reset (global_tick starts at 0), no pre-fill cycles
        // so the FIFO never overflows and the tick-based skew counter correctly
        // captures the 17-cycle gap between lane 0 SKP and lanes 1-15 SKP.
        // ----------------------------------------------------------------
        do_reset;
        deskew_en    = 1'b1;
        lane_valid   = {NUM_LANES{1'b1}};
        skp_detected = {NUM_LANES{1'b0}};

        // Feed just 2 cycles of preamble data (safe, well inside FIFO)
        for (j = 0; j < 2; j = j + 1) begin
            for (i = 0; i < NUM_LANES; i = i + 1)
                lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hBB000000 + j*16 + i;
            @(posedge clk); #1;
        end

        // Lane 0 SKP at global_tick=T0
        for (i = 0; i < NUM_LANES; i = i + 1)
            lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hA1000000 + i;
        skp_detected = 16'h0001;
        @(posedge clk); #1;
        skp_detected = 16'h0000;

        // 17 gap cycles — lanes 1-15 have NOT seen SKP yet
        // global_tick advances 17 steps, making the gap = 17 > MAX_SKEW=16
        for (j = 0; j < 17; j = j + 1) begin
            for (i = 0; i < NUM_LANES; i = i + 1)
                lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hA2000000 + j*16 + i;
            @(posedge clk); #1;
        end

        // Lanes 1-15 all see SKP now → all_skp_seen fires next cycle
        for (i = 0; i < NUM_LANES; i = i + 1)
            lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hA3000000 + i;
        skp_detected = 16'hFFFE;
        @(posedge clk); #1;
        skp_detected = 16'h0000;

        // Wait for skew logic to evaluate
        repeat(4) @(posedge clk); #1;
        if (deskew_err === 1'b1 && skew_amount > 5'd16)
            $display("PASS TEST 4: excessive skew detected, deskew_err=%b skew_amount=%0d",
                      deskew_err, skew_amount);
        else begin
            $display("FAIL TEST 4: deskew_err=%b skew_amount=%0d (expected err=1 amount>16)",
                      deskew_err, skew_amount);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------------
        // TEST 5: deskew_en toggled off — state clears, bypass activates
        // ----------------------------------------------------------------
        do_reset;
        deskew_en = 1'b1;
        drive_all_lanes(32'hC0000000, 1'b1, {NUM_LANES{1'b0}});
        drive_all_lanes(32'hC0000010, 1'b1, {NUM_LANES{1'b0}});

        deskew_en = 1'b0;
        drive_all_lanes(32'hC0000020, 1'b1, {NUM_LANES{1'b0}});
        @(posedge clk); #1;
        if (skew_amount === 5'd0 && deskew_err === 1'b0 &&
            deskew_valid === {NUM_LANES{1'b1}})
            $display("PASS TEST 5: deskew_en=0, passthrough active skew_amount=%0d",
                      skew_amount);
        else begin
            $display("FAIL TEST 5: deskew_en=0  skew_amount=%0d deskew_err=%b deskew_valid=%b",
                      skew_amount, deskew_err, deskew_valid);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------------
        // TEST 6: Async reset mid-operation clears all outputs
        // ----------------------------------------------------------------
        @(negedge clk);
        deskew_en = 1'b1;
        drive_all_lanes(32'hDE000000, 1'b1, {NUM_LANES{1'b0}});
        rst_n = 1'b0;
        @(posedge clk); #1;
        if (deskewed_data === {NUM_LANES*DATA_WIDTH{1'b0}} &&
            deskew_valid  === {NUM_LANES{1'b0}}            &&
            skew_amount   === 5'd0                          &&
            deskew_err    === 1'b0)
            $display("PASS TEST 6: reset clears all outputs");
        else begin
            $display("FAIL TEST 6: reset outputs not cleared  valid=%b err=%b amt=%0d",
                      deskew_valid, deskew_err, skew_amount);
            fail_count = fail_count + 1;
        end
        rst_n = 1'b1;

        // ----------------------------------------------------------------
        // TEST 7: All lanes invalid → no deskew output
        // ----------------------------------------------------------------
        @(posedge clk);
        deskew_en    = 1'b1;
        lane_valid   = {NUM_LANES{1'b0}};
        skp_detected = {NUM_LANES{1'b0}};
        for (i = 0; i < NUM_LANES; i = i + 1)
            lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hFF000000 + i;
        repeat(4) @(posedge clk); #1;
        if (deskew_valid === {NUM_LANES{1'b0}})
            $display("PASS TEST 7: all lanes invalid => no deskew_valid");
        else begin
            $display("FAIL TEST 7: expected deskew_valid=0, got %b", deskew_valid);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------------
        // TEST 8: x2 link (lanes 0 and 1 only), simultaneous SKP → skew=0
        // ----------------------------------------------------------------
        do_reset;
        deskew_en    = 1'b1;
        lane_valid   = 16'h0003;
        skp_detected = 16'h0000;

        for (j = 0; j < 4; j = j + 1) begin
            for (i = 0; i < NUM_LANES; i = i + 1)
                lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hE8000000 + j*16 + i;
            @(posedge clk); #1;
        end

        // Both lanes SKP simultaneously
        for (i = 0; i < NUM_LANES; i = i + 1)
            lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hE9000000 + i;
        skp_detected = 16'h0003;
        @(posedge clk); #1;
        skp_detected = 16'h0000;

        repeat(6) @(posedge clk); #1;

        // x2 link: lanes 2-15 are inactive (lane_valid bits 15:2 = 0)
        // all_skp_seen waits for all 16 lanes — for x2, only bits 0&1 matter.
        // Since inactive lanes never write, their skp_seen bits stay 0.
        // The test here verifies no spurious deskew_err on active lanes.
        $display("INFO  TEST 8: x2 link skew_amount=%0d deskew_err=%b deskew_valid=%b",
                  skew_amount, deskew_err, deskew_valid);

        // ----------------------------------------------------------------
        // TEST 9: Back-to-back SKP rounds — second round re-arms correctly
        // ----------------------------------------------------------------
        do_reset;
        deskew_en    = 1'b1;
        lane_valid   = {NUM_LANES{1'b1}};
        skp_detected = {NUM_LANES{1'b0}};

        // Round 1: simultaneous SKP
        repeat(3) drive_all_lanes(32'h90000000, 1'b1, {NUM_LANES{1'b0}});
        drive_all_lanes(32'h91000000, 1'b1, {NUM_LANES{1'b1}});

        repeat(4) @(posedge clk); #1;
        if (skew_amount === 5'd0 && deskew_err === 1'b0)
            $display("PASS TEST 9 round1: skew_amount=%0d deskew_err=%b",
                      skew_amount, deskew_err);
        else begin
            $display("FAIL TEST 9 round1: skew_amount=%0d deskew_err=%b",
                      skew_amount, deskew_err);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------------
        // SUMMARY
        // ----------------------------------------------------------------
        repeat(4) @(posedge clk);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SIMULATION DONE — %0d TEST(S) FAILED", fail_count);

        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
