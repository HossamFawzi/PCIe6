// ============================================================
// Testbench for Module 43 (44) : TS1/TS2 Ordered Set Detector
// ============================================================
`timescale 1ns/1ps

module tb_ts_det;

    reg         clk, rst_n;
    reg [255:0] rx_data;
    reg         rx_valid, block_lock;

    wire        ts1_detected, ts2_detected;
    wire [7:0]  ts1_link_num, ts1_lane_num, ts2_speed_cap;
    wire        ts_decode_err;

    ts_det dut (
        .clk           (clk),  .rst_n      (rst_n),
        .rx_data       (rx_data), .rx_valid (rx_valid),
        .block_lock    (block_lock),
        .ts1_detected  (ts1_detected), .ts2_detected  (ts2_detected),
        .ts1_link_num  (ts1_link_num), .ts1_lane_num  (ts1_lane_num),
        .ts2_speed_cap (ts2_speed_cap),.ts_decode_err (ts_decode_err)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    function [255:0] make_ts;
        input [7:0] com,link,lane,fts,speed,ctrl,id;
        reg [255:0] d; integer i;
        begin
            d=256'd0;
            d[7:0]=com; d[15:8]=link; d[23:16]=lane;
            d[31:24]=fts; d[39:32]=speed; d[47:40]=ctrl; d[55:48]=id;
            for(i=7;i<32;i=i+1) d[i*8+:8]=8'hF7;
            make_ts=d;
        end
    endfunction

    // Apply one word and sample on the SAME clock edge that rx_valid is high
    task apply_word;
        input [255:0] word;
        begin
            @(posedge clk); #1;
            rx_data  = word;
            rx_valid = 1;
            @(posedge clk); #1;   // clock captures data with valid=1 → outputs register
            rx_valid = 0;
            // outputs are now stable (registered from last posedge)
        end
    endtask

    initial begin
        rst_n=0; rx_data=0; rx_valid=0; block_lock=0;
        repeat(4) @(posedge clk); rst_n=1; @(posedge clk);

        // TC1: Detect TS1
        block_lock=1;
        apply_word(make_ts(8'hBC,8'h01,8'h00,8'h30,8'h3F,8'h00,8'h4A));
        if(ts1_detected && !ts2_detected && ts1_link_num==8'h01 && ts1_lane_num==8'h00) begin
            $display("PASS [TC1_TS1_detect]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC1_TS1_detect] det=%b lnk=%h ln=%h",ts1_detected,ts1_link_num,ts1_lane_num);
            fail_count=fail_count+1;
        end

        // TC2: Detect TS2
        apply_word(make_ts(8'hBC,8'h02,8'h01,8'h30,8'h40,8'h00,8'h45));
        if(ts2_detected && !ts1_detected && ts2_speed_cap==8'h40) begin
            $display("PASS [TC2_TS2_detect]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC2_TS2_detect] det=%b speed=%h",ts2_detected,ts2_speed_cap);
            fail_count=fail_count+1;
        end

        // TC3: No detection without block_lock
        block_lock=0;
        apply_word(make_ts(8'hBC,8'h01,8'h00,8'h30,8'h3F,8'h00,8'h4A));
        if(!ts1_detected && !ts2_detected) begin
            $display("PASS [TC3_no_lock_no_det]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC3_no_lock_no_det]"); fail_count=fail_count+1;
        end
        block_lock=1;

        // TC4: No detection when rx_valid=0
        rx_data=make_ts(8'hBC,8'h01,8'h00,8'h30,8'h3F,8'h00,8'h4A);
        rx_valid=0;
        @(posedge clk); #1; @(posedge clk); #1;
        if(!ts1_detected && !ts2_detected) begin
            $display("PASS [TC4_no_valid_no_det]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC4_no_valid_no_det]"); fail_count=fail_count+1;
        end

        // TC5: Unknown OS ID → decode error
        apply_word(make_ts(8'hBC,8'h01,8'h00,8'h30,8'h3F,8'h00,8'hAA));
        if(ts_decode_err && !ts1_detected && !ts2_detected) begin
            $display("PASS [TC5_decode_err]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC5_decode_err] err=%b",ts_decode_err); fail_count=fail_count+1;
        end

        // TC6: Non-COM first byte → no detection, no error
        apply_word(make_ts(8'hAA,8'h01,8'h00,8'h30,8'h3F,8'h00,8'h4A));
        if(!ts1_detected && !ts2_detected && !ts_decode_err) begin
            $display("PASS [TC6_no_COM_ignored]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC6_no_COM_ignored]"); fail_count=fail_count+1;
        end

        // TC7: TS1 with PAD link/lane
        apply_word(make_ts(8'hBC,8'hFF,8'hFF,8'h00,8'h01,8'h00,8'h4A));
        if(ts1_detected && ts1_link_num==8'hFF && ts1_lane_num==8'hFF) begin
            $display("PASS [TC7_PAD_link_lane]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC7_PAD_link_lane] det=%b lnk=%h ln=%h",ts1_detected,ts1_link_num,ts1_lane_num);
            fail_count=fail_count+1;
        end

        // TC8: Reset clears outputs
        rst_n=0; repeat(3) @(posedge clk); #1;
        if(!ts1_detected && !ts2_detected && !ts_decode_err) begin
            $display("PASS [TC8_reset]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC8_reset]"); fail_count=fail_count+1;
        end
        rst_n=1;

        #20;
        $display("===========================================");
        $display("  TS_DET Results: PASS=%0d  FAIL=%0d",pass_count,fail_count);
        $display("===========================================");
        $finish;
    end
    initial begin #10000; $display("TIMEOUT"); $finish; end
endmodule
