
`timescale 1ns/1ps

module tb_skp;

    reg         clk, rst_n;
    reg         skp_send_req;
    reg [11:0]  skp_interval;
    reg [255:0] rx_data;
    reg         rx_valid;

    wire [255:0] skp_data;
    wire         skp_tx_valid, skp_detected, skp_removed, skp_err;

    skp dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .skp_send_req (skp_send_req),
        .skp_interval (skp_interval),
        .rx_data      (rx_data),
        .rx_valid     (rx_valid),
        .skp_data     (skp_data),
        .skp_tx_valid (skp_tx_valid),
        .skp_detected (skp_detected),
        .skp_removed  (skp_removed),
        .skp_err      (skp_err)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    reg [255:0] skp_rx_word;
    reg [255:0] normal_data;
    integer i;

    initial begin
        skp_rx_word = 256'd0;
        normal_data = 256'hA5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5;

        for (i=0; i<8; i=i+1) begin
            skp_rx_word[i*32 +  0 +: 8] = 8'hBC;
            skp_rx_word[i*32 +  8 +: 8] = 8'h1C;
            skp_rx_word[i*32 + 16 +: 8] = 8'h1C;
            skp_rx_word[i*32 + 24 +: 8] = 8'h1C;
        end
    end

    initial begin
        rst_n=0; skp_send_req=0; skp_interval=12'd0;
        rx_data=0; rx_valid=0;
        repeat(4) @(posedge clk); rst_n=1; @(posedge clk);

        skp_interval = 12'd0;
        @(posedge clk); #1; skp_send_req=1;
        @(posedge clk); #1; skp_send_req=0;
        repeat(5) @(posedge clk);

        if (!skp_tx_valid) begin
            $display("PASS [TC1_manual_send]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC1_manual_send]"); fail_count=fail_count+1;
        end

        @(posedge clk); #1; skp_send_req=1;
        @(posedge clk); #1; skp_send_req=0;
        @(posedge clk); #1;
        if (skp_data[7:0]==8'hBC && skp_data[15:8]==8'h1C) begin
            $display("PASS [TC2_skp_tx_pattern]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC2_skp_tx_pattern] 0x%h 0x%h", skp_data[7:0], skp_data[15:8]);
            fail_count=fail_count+1;
        end
        repeat(5) @(posedge clk);

        skp_interval = 12'd8;
        begin : TC3
            integer valid_seen; valid_seen=0;
            repeat(30) begin
                @(posedge clk); #1;
                if (skp_tx_valid) valid_seen=valid_seen+1;
            end
            if (valid_seen >= 2) begin
                $display("PASS [TC3_auto_interval]"); pass_count=pass_count+1;
            end else begin
                $display("FAIL [TC3_auto_interval] valid_seen=%0d", valid_seen); fail_count=fail_count+1;
            end
        end
        skp_interval = 12'd0;

        rx_data = skp_rx_word;
        @(posedge clk); #1;
        rx_valid=1;
        @(posedge clk); #1;
        if (skp_detected && skp_removed) begin
            $display("PASS [TC4_rx_skp_det]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC4_rx_skp_det] det=%b rem=%b", skp_detected, skp_removed);
            fail_count=fail_count+1;
        end
        rx_valid=0;

        rx_data = normal_data;
        @(posedge clk); #1; rx_valid=1;
        @(posedge clk); #1; rx_valid=0;
        @(posedge clk); #1;
        if (!skp_detected && !skp_removed) begin
            $display("PASS [TC5_normal_no_det]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC5_normal_no_det]"); fail_count=fail_count+1;
        end

        rx_data = skp_rx_word; rx_valid=0;
        @(posedge clk); #1; @(posedge clk); #1;
        if (!skp_detected) begin
            $display("PASS [TC6_no_valid_no_det]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC6_no_valid_no_det]"); fail_count=fail_count+1;
        end

        rst_n=0; repeat(3) @(posedge clk); #1;
        if (!skp_tx_valid && !skp_detected && !skp_removed && !skp_err) begin
            $display("PASS [TC7_reset]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC7_reset]"); fail_count=fail_count+1;
        end
        rst_n=1;

        begin : TC8
            integer cnt; cnt=0;
            rx_data = skp_rx_word;
            @(posedge clk); #1;
            rx_valid=1;
            @(posedge clk); #1;
            if(skp_removed) cnt=cnt+1;
            rx_valid=0;
            repeat(4) begin @(posedge clk); #1; if(skp_removed) cnt=cnt+1; end
            if (cnt===1) begin $display("PASS [TC8_removed_pulse]"); pass_count=pass_count+1; end
            else         begin $display("FAIL [TC8_removed_pulse] cnt=%0d",cnt); fail_count=fail_count+1; end
        end

        #20;
        $display("===========================================");
        $display("  SKP Results: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("===========================================");
        $finish;
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule
