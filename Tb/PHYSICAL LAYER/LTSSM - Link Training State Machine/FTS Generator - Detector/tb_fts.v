
`timescale 1ns/1ps

module tb_fts;

    reg         clk, rst_n;
    reg         fts_send;
    reg [7:0]   fts_count;
    reg [255:0] rx_data;
    reg         rx_valid;

    wire [255:0] fts_data;
    wire         fts_tx_valid;
    wire         fts_detected;
    wire [7:0]   fts_count_rx;

    fts dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .fts_send     (fts_send),
        .fts_count    (fts_count),
        .rx_data      (rx_data),
        .rx_valid     (rx_valid),
        .fts_data     (fts_data),
        .fts_tx_valid (fts_tx_valid),
        .fts_detected (fts_detected),
        .fts_count_rx (fts_count_rx)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    reg [255:0] all_fts_word;
    reg [255:0] mixed_word;
    integer i;

    initial begin
        all_fts_word = 256'd0;
        mixed_word   = 256'd0;
        for (i = 0; i < 32; i = i+1)
            all_fts_word[i*8 +: 8] = 8'h3C;

        mixed_word[7:0] = 8'hBC;
        for (i = 1; i < 32; i = i+1)
            mixed_word[i*8 +: 8] = 8'h3C;
    end

    initial begin
        rst_n=0; fts_send=0; fts_count=0; rx_data=0; rx_valid=0;
        repeat(4) @(posedge clk); rst_n=1; @(posedge clk);

        fts_count = 8'h04;
        @(posedge clk); #1; fts_send=1;
        @(posedge clk); #1; fts_send=0;
        begin : TC1
            integer valid_cyc; valid_cyc=0;
            repeat(20) begin
                @(posedge clk); #1;
                if (fts_tx_valid) valid_cyc=valid_cyc+1;
            end
            if (valid_cyc >= 4) begin
                $display("PASS [TC1_tx_fts_4]"); pass_count=pass_count+1;
            end else begin
                $display("FAIL [TC1_tx_fts_4] valid_cyc=%0d", valid_cyc); fail_count=fail_count+1;
            end
        end

        fts_count = 8'h01;
        @(posedge clk); #1; fts_send=1;
        @(posedge clk); #1; fts_send=0;
        @(posedge clk); #1; @(posedge clk); #1;
        begin : TC2
            integer ok; ok=1;
            for (i=0; i<32; i=i+1)
                if (fts_data[i*8 +: 8] !== 8'h3C) ok=0;
            if (ok) begin $display("PASS [TC2_tx_data_fts_symbols]"); pass_count=pass_count+1; end
            else    begin $display("FAIL [TC2_tx_data_fts_symbols]"); fail_count=fail_count+1; end
        end
        repeat(5) @(posedge clk);

        fts_count = 8'h00;
        @(posedge clk); #1; fts_send=1;
        @(posedge clk); #1; fts_send=0;
        repeat(5) @(posedge clk);
        if (!fts_tx_valid) begin
            $display("PASS [TC3_count0_no_tx]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC3_count0_no_tx]"); fail_count=fail_count+1;
        end

        rx_data = all_fts_word;
        @(posedge clk); #1;
        rx_valid=1;
        @(posedge clk); #1;
        if (fts_detected) begin
            $display("PASS [TC4_rx_fts_detect]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC4_rx_fts_detect]"); fail_count=fail_count+1;
        end
        rx_valid=0;

        begin : TC5
            integer cnt_before, cnt_after;
            cnt_before = fts_count_rx;
            repeat(5) begin
                rx_data = all_fts_word;
                @(posedge clk); #1; rx_valid=1;
                @(posedge clk); #1; rx_valid=0;
                @(posedge clk); #1;
            end
            cnt_after = fts_count_rx;
            if (cnt_after > cnt_before) begin
                $display("PASS [TC5_rx_count_inc]"); pass_count=pass_count+1;
            end else begin
                $display("FAIL [TC5_rx_count_inc] before=%0d after=%0d", cnt_before, cnt_after); fail_count=fail_count+1;
            end
        end

        rx_data = mixed_word;
        @(posedge clk); #1; rx_valid=1;
        @(posedge clk); #1; rx_valid=0;
        @(posedge clk); #1;
        if (!fts_detected) begin
            $display("PASS [TC6_mixed_no_det]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC6_mixed_no_det]"); fail_count=fail_count+1;
        end

        if (fts_count_rx === 8'd0) begin
            $display("PASS [TC7_rx_count_reset]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC7_rx_count_reset] got=%0d", fts_count_rx); fail_count=fail_count+1;
        end

        rst_n=0; repeat(3) @(posedge clk); #1;
        if (!fts_tx_valid && !fts_detected && fts_count_rx===8'd0) begin
            $display("PASS [TC8_reset]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC8_reset]"); fail_count=fail_count+1;
        end
        rst_n=1;

        fts_count = 8'hFF;
        @(posedge clk); #1; fts_send=1;
        @(posedge clk); #1; fts_send=0;
        begin : TC9
            integer valid_cyc; valid_cyc=0;
            repeat(300) begin
                @(posedge clk); #1;
                if (fts_tx_valid) valid_cyc=valid_cyc+1;
            end
            if (valid_cyc >= 255) begin
                $display("PASS [TC9_large_count]"); pass_count=pass_count+1;
            end else begin
                $display("FAIL [TC9_large_count] got=%0d", valid_cyc); fail_count=fail_count+1;
            end
        end

        #20;
        $display("===========================================");
        $display("  FTS Results: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("===========================================");
        $finish;
    end

    initial begin #200000; $display("TIMEOUT"); $finish; end

endmodule
