
`timescale 1ns/1ps

module tb_lane_pol;

reg          clk;
reg          rst_n;
reg  [255:0] rx_data;
reg  [15:0]  polarity_det;

wire [255:0] rx_data_pol;
wire [15:0]  polarity_inv;

lane_pol dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .rx_data      (rx_data),
    .polarity_det (polarity_det),
    .rx_data_pol  (rx_data_pol),
    .polarity_inv (polarity_inv)
);

initial clk = 0;
always #5 clk = ~clk;

integer pass_cnt, fail_cnt;

task check16;
    input [15:0] actual;
    input [15:0] expected;
    input [255:0] msg;
begin
    if (actual === expected) begin
        $display("  PASS | %s  actual=%04h  expected=%04h", msg, actual, expected);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("  FAIL | %s  actual=%04h  expected=%04h  *** MISMATCH ***",
                 msg, actual, expected);
        fail_cnt = fail_cnt + 1;
    end
end
endtask

task check1;
    input actual;
    input expected;
    input [255:0] msg;
begin
    if (actual === expected) begin
        $display("  PASS | %s  actual=%0b  expected=%0b", msg, actual, expected);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("  FAIL | %s  actual=%0b  expected=%0b  *** MISMATCH ***",
                 msg, actual, expected);
        fail_cnt = fail_cnt + 1;
    end
end
endtask

task do_reset;
begin
    rst_n        = 1'b0;
    rx_data      = 256'h0;
    polarity_det = 16'h0000;
    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
end
endtask

function [15:0] lane_slice;
    input [255:0] data;
    input integer lane_idx;
    lane_slice = data[16*lane_idx +: 16];
endfunction

initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    $display("\n===================================================");
    $display(" TB: lane_pol ? Lane Polarity Inversion Logic");
    $display("===================================================\n");

    $display("--- TEST 1: Reset state ---");
    do_reset;
    check16(polarity_inv, 16'h0000, "polarity_inv cleared after reset");

    rx_data = 256'hDEAD_BEEF_CAFE_BABE_0123_4567_89AB_CDEF_DEAD_BEEF_CAFE_BABE_0123_4567_89AB_CDEF;
    @(posedge clk); #1;

    check16(lane_slice(rx_data_pol, 0), lane_slice(rx_data, 0), "lane0 pass-through");
    check16(lane_slice(rx_data_pol, 7), lane_slice(rx_data, 7), "lane7 pass-through");

    $display("\n--- TEST 2: Single lane polarity swap (lane 0) ---");
    do_reset;

    rx_data = {16{16'hAAAA}};

    polarity_det = 16'h0001;
    @(posedge clk); #1;
    polarity_det = 16'h0000;
    @(posedge clk); #1;

    check16(polarity_inv, 16'h0001, "polarity_inv bit 0 set");

    check16(lane_slice(rx_data_pol, 0), 16'h5555, "lane0 inverted 0xAAAA?0x5555");

    check16(lane_slice(rx_data_pol, 1), 16'hAAAA, "lane1 unchanged");

    $display("\n--- TEST 3: Multiple lane inversion (lanes 3 and 7) ---");
    do_reset;
    rx_data = {16{16'hFF00}};

    polarity_det = 16'h0088;
    @(posedge clk); #1;
    polarity_det = 16'h0000;
    @(posedge clk); #1;

    check16(polarity_inv, 16'h0088, "polarity_inv bits 3,7 set");

    check16(lane_slice(rx_data_pol, 3), 16'h00FF, "lane3 inverted FF00?00FF");

    check16(lane_slice(rx_data_pol, 7), 16'h00FF, "lane7 inverted FF00?00FF");

    check16(lane_slice(rx_data_pol, 0), 16'hFF00, "lane0 unchanged");

    $display("\n--- TEST 4: Sticky behaviour ---");
    do_reset;
    rx_data = {16{16'hF0F0}};

    polarity_det = 16'h0004;
    @(posedge clk); #1;
    polarity_det = 16'h0000;
    @(posedge clk); #1;

    check16(polarity_inv, 16'h0004, "polarity_inv=0x0004 after first det");

    polarity_det = 16'h0020;
    @(posedge clk); #1;
    polarity_det = 16'h0000;
    @(posedge clk); #1;

    check16(polarity_inv, 16'h0024, "polarity_inv=0x0024 (sticky OR)");

    check16(lane_slice(rx_data_pol, 2), 16'h0F0F, "lane2 inverted F0F0?0F0F");

    check16(lane_slice(rx_data_pol, 5), 16'h0F0F, "lane5 inverted F0F0?0F0F");

    $display("\n--- TEST 5: Reset clears polarity_inv ---");
    do_reset;
    check16(polarity_inv, 16'h0000, "polarity_inv cleared after reset");

    rx_data = {16{16'hAAAA}};
    @(posedge clk); #1;
    check16(lane_slice(rx_data_pol, 0), 16'hAAAA, "lane0 normal after reset");

    $display("\n--- TEST 6: All 16 lanes inverted ---");
    do_reset;
    rx_data = {16{16'h1234}};

    polarity_det = 16'hFFFF;
    @(posedge clk); #1;
    polarity_det = 16'h0000;
    @(posedge clk); #1;

    check16(polarity_inv, 16'hFFFF, "polarity_inv all lanes");
    begin : test6
        integer lane;
        for (lane = 0; lane < 16; lane = lane + 1) begin
            check16(lane_slice(rx_data_pol, lane), 16'hEDCB,
                    "all lanes: 0x1234 inverted?0xEDCB");
        end
    end

    $display("\n--- TEST 7: Dynamic data with fixed inversion on lane 1 ---");
    do_reset;
    polarity_det = 16'h0002;
    @(posedge clk); #1;
    polarity_det = 16'h0000;

    rx_data = {16{16'h0001}};
    @(posedge clk); #1;
    check16(lane_slice(rx_data_pol, 1), 16'hFFFE, "lane1 inverted 0x0001?0xFFFE");
    check16(lane_slice(rx_data_pol, 0), 16'h0001, "lane0 unchanged 0x0001");

    rx_data = {16{16'hBEEF}};
    @(posedge clk); #1;
    check16(lane_slice(rx_data_pol, 1), 16'h4110, "lane1 inverted 0xBEEF?0x4110");
    check16(lane_slice(rx_data_pol, 0), 16'hBEEF, "lane0 unchanged 0xBEEF");

    $display("\n===================================================");
    $display(" Results: %0d PASS  %0d FAIL", pass_cnt, fail_cnt);
    $display("===================================================\n");
    $finish;
end

initial begin
    $dumpfile("lane_pol.vcd");
    $dumpvars(0, tb_lane_pol);
end

endmodule
