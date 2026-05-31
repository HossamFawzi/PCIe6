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

        do_reset;
        deskew_en = 1'b1;

        repeat(4) drive_all_lanes(32'hB0000000, 1'b1, {NUM_LANES{1'b0}});
        drive_all_lanes(32'hC0000000, 1'b1, {NUM_LANES{1'b1}});
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

        do_reset;
        deskew_en    = 1'b1;
        lane_valid   = {NUM_LANES{1'b1}};
        skp_detected = {NUM_LANES{1'b0}};

        for (j = 0; j < 4; j = j + 1) begin
            for (i = 0; i < NUM_LANES; i = i + 1)
                lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hE0000000 + j*16 + i;
            @(posedge clk); #1;
        end

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

        do_reset;
        deskew_en    = 1'b1;
        lane_valid   = {NUM_LANES{1'b1}};
        skp_detected = {NUM_LANES{1'b0}};

        for (j = 0; j < 2; j = j + 1) begin
            for (i = 0; i < NUM_LANES; i = i + 1)
                lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hBB000000 + j*16 + i;
            @(posedge clk); #1;
        end

        for (i = 0; i < NUM_LANES; i = i + 1)
            lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hA1000000 + i;
        skp_detected = 16'h0001;
        @(posedge clk); #1;
        skp_detected = 16'h0000;

        for (j = 0; j < 17; j = j + 1) begin
            for (i = 0; i < NUM_LANES; i = i + 1)
                lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hA2000000 + j*16 + i;
            @(posedge clk); #1;
        end

        for (i = 0; i < NUM_LANES; i = i + 1)
            lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hA3000000 + i;
        skp_detected = 16'hFFFE;
        @(posedge clk); #1;
        skp_detected = 16'h0000;

        repeat(4) @(posedge clk); #1;
        if (deskew_err === 1'b1 && skew_amount > 5'd16)
            $display("PASS TEST 4: excessive skew detected, deskew_err=%b skew_amount=%0d",
                      deskew_err, skew_amount);
        else begin
            $display("FAIL TEST 4: deskew_err=%b skew_amount=%0d (expected err=1 amount>16)",
                      deskew_err, skew_amount);
            fail_count = fail_count + 1;
        end

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

        do_reset;
        deskew_en    = 1'b1;
        lane_valid   = 16'h0003;
        skp_detected = 16'h0000;

        for (j = 0; j < 4; j = j + 1) begin
            for (i = 0; i < NUM_LANES; i = i + 1)
                lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hE8000000 + j*16 + i;
            @(posedge clk); #1;
        end

        for (i = 0; i < NUM_LANES; i = i + 1)
            lane_data[i*DATA_WIDTH +: DATA_WIDTH] = 32'hE9000000 + i;
        skp_detected = 16'h0003;
        @(posedge clk); #1;
        skp_detected = 16'h0000;

        repeat(6) @(posedge clk); #1;

        $display("INFO  TEST 8: x2 link skew_amount=%0d deskew_err=%b deskew_valid=%b",
                  skew_amount, deskew_err, deskew_valid);

        do_reset;
        deskew_en    = 1'b1;
        lane_valid   = {NUM_LANES{1'b1}};
        skp_detected = {NUM_LANES{1'b0}};

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
