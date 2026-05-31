
`timescale 1ns/1ps

module tb_eios;

    reg         clk, rst_n;
    reg         eios_send, eieos_send;
    reg [255:0] rx_data;
    reg         rx_valid;

    wire [255:0] eios_data;
    wire         eios_tx_valid;
    wire         eios_detected, eieos_detected;

    eios dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .eios_send     (eios_send),
        .eieos_send    (eieos_send),
        .rx_data       (rx_data),
        .rx_valid      (rx_valid),
        .eios_data     (eios_data),
        .eios_tx_valid (eios_tx_valid),
        .eios_detected (eios_detected),
        .eieos_detected(eieos_detected)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task trigger_eios;
        begin
            @(posedge clk); #1; eios_send=1;
            @(posedge clk); #1; eios_send=0;
            repeat(5) @(posedge clk); #1;
        end
    endtask

    task trigger_eieos;
        begin
            @(posedge clk); #1; eieos_send=1;
            @(posedge clk); #1; eieos_send=0;
            repeat(5) @(posedge clk); #1;
        end
    endtask

    reg [255:0] eios_rx_word, eieos_rx_word, mixed_word;
    integer i;

    initial begin
        eios_rx_word = 256'd0;
        eieos_rx_word = 256'd0;
        mixed_word    = 256'd0;

        for (i=0; i<8; i=i+1) begin
            eios_rx_word[i*32 +  0 +: 8] = 8'hBC;
            eios_rx_word[i*32 +  8 +: 8] = 8'h7C;
            eios_rx_word[i*32 + 16 +: 8] = 8'h7C;
            eios_rx_word[i*32 + 24 +: 8] = 8'h7C;
        end

        for (i=0; i<16; i=i+1) begin
            eieos_rx_word[i*16 + 0 +: 8] = 8'h00;
            eieos_rx_word[i*16 + 8 +: 8] = 8'hFF;
        end

        mixed_word[7:0]  = 8'hAA;
        mixed_word[15:8] = 8'h55;
    end

    initial begin
        rst_n=0; eios_send=0; eieos_send=0; rx_data=0; rx_valid=0;
        repeat(4) @(posedge clk); rst_n=1; @(posedge clk);

        trigger_eios;
        if (eios_tx_valid === 1'b0) begin
            $display("PASS [TC1_eios_tx_done]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC1_eios_tx_done]"); fail_count=fail_count+1;
        end

        @(posedge clk); #1; eios_send=1;
        @(posedge clk); #1; eios_send=0;
        @(posedge clk); #1;
        if (eios_data[7:0]==8'hBC && eios_data[15:8]==8'h7C) begin
            $display("PASS [TC2_eios_tx_pattern]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC2_eios_tx_pattern] byte0=0x%h byte1=0x%h", eios_data[7:0], eios_data[15:8]);
            fail_count=fail_count+1;
        end
        repeat(5) @(posedge clk);

        @(posedge clk); #1; eieos_send=1;
        @(posedge clk); #1; eieos_send=0;
        @(posedge clk); #1;
        if (eios_data[7:0]==8'h00 && eios_data[15:8]==8'hFF) begin
            $display("PASS [TC3_eieos_tx_pattern]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC3_eieos_tx_pattern] byte0=0x%h byte1=0x%h", eios_data[7:0], eios_data[15:8]);
            fail_count=fail_count+1;
        end
        repeat(5) @(posedge clk);

        rx_data = eios_rx_word;
        @(posedge clk); #1;
        rx_valid=1;
        @(posedge clk); #1;
        if (eios_detected && !eieos_detected) begin
            $display("PASS [TC4_rx_eios]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC4_rx_eios] eios=%b eieos=%b", eios_detected, eieos_detected);
            fail_count=fail_count+1;
        end
        rx_valid=0;

        rx_data = eieos_rx_word;
        @(posedge clk); #1;
        rx_valid=1;
        @(posedge clk); #1;
        if (eieos_detected && !eios_detected) begin
            $display("PASS [TC5_rx_eieos]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC5_rx_eieos] eios=%b eieos=%b", eios_detected, eieos_detected);
            fail_count=fail_count+1;
        end
        rx_valid=0;

        rx_data = mixed_word;
        @(posedge clk); #1; rx_valid=1;
        @(posedge clk); #1; rx_valid=0;
        @(posedge clk); #1;
        if (!eios_detected && !eieos_detected) begin
            $display("PASS [TC6_no_det_random]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC6_no_det_random]"); fail_count=fail_count+1;
        end

        rx_data = eios_rx_word; rx_valid=0;
        @(posedge clk); #1; @(posedge clk); #1;
        if (!eios_detected) begin
            $display("PASS [TC7_no_valid_no_det]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC7_no_valid_no_det]"); fail_count=fail_count+1;
        end

        @(posedge clk); #1; eios_send=1; eieos_send=1;
        @(posedge clk); #1; eios_send=0; eieos_send=0;
        @(posedge clk); #1;
        if (eios_data[7:0]==8'hBC) begin
            $display("PASS [TC8_eios_priority]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC8_eios_priority] byte0=0x%h", eios_data[7:0]); fail_count=fail_count+1;
        end
        repeat(5) @(posedge clk);

        rst_n=0; repeat(3) @(posedge clk); #1;
        if (!eios_tx_valid && !eios_detected && !eieos_detected) begin
            $display("PASS [TC9_reset]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC9_reset]"); fail_count=fail_count+1;
        end
        rst_n=1;

        #20;
        $display("===========================================");
        $display("  EIOS Results: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("===========================================");
        $finish;
    end

    initial begin #10000; $display("TIMEOUT"); $finish; end

endmodule
