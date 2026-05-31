`timescale 1ns/1ps

module fec_rs_decoder_tb;

    reg           clk;
    reg           rst_n;
    reg  [2347:0] flit_fec_in;
    reg           flit_valid;
    reg           fec_en;

    wire [2047:0] flit_corrected;
    wire          fec_corrected;
    wire [299:0]  fec_syndrome;
    wire          fec_uncorrectable;
    wire [7:0]    fec_err_count;

    fec_rs_decoder dut (
        .clk(clk),
        .rst_n(rst_n),
        .flit_fec_in(flit_fec_in),
        .flit_valid(flit_valid),
        .fec_en(fec_en),
        .flit_corrected(flit_corrected),
        .fec_corrected(fec_corrected),
        .fec_syndrome(fec_syndrome),
        .fec_uncorrectable(fec_uncorrectable),
        .fec_err_count(fec_err_count)
    );

    initial clk = 0;
    always #0.5 clk = ~clk;

    integer fail_count = 0;
    integer i;

    task send_flit(input [2347:0] data, input enable_fec);
    begin
        @(negedge clk);
        flit_fec_in = data;
        flit_valid  = 1;
        fec_en      = enable_fec;
        @(posedge clk); #0.1;
        flit_valid  = 0;
    end
    endtask

    task wait_done;
    begin
        repeat(600) @(posedge clk);
    end
    endtask

    initial begin
        $dumpfile("fec_rs_decoder_tb.vcd");
        $dumpvars(0, fec_rs_decoder_tb);

        rst_n = 0;
        flit_fec_in = 0;
        flit_valid  = 0;
        fec_en      = 0;

        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        $display("===============================================================");
        $display("   STARTING PCIe GEN6 RS(235, 205) FEC DECODER VERIFICATION    ");
        $display("===============================================================\n");

        $display("[TEST 1] Clean All-Zeros Codeword...");
        send_flit(2348'd0, 1'b1);
        wait_done();
        if (!fec_uncorrectable && !fec_corrected && fec_err_count == 0 && flit_corrected == 2048'd0)
            $display("   --> PASS: No errors detected.");
        else begin
            $display("   --> FAIL: Unexpected behavior on clean data."); fail_count = fail_count + 1;
        end

        $display("[TEST 2] Single Error in Data Payload...");
        flit_fec_in = 2348'd0;

        flit_fec_in[308 + 10*20 +: 10] = 10'h3FF;
        send_flit(flit_fec_in, 1'b1);
        wait_done();
        if (fec_corrected && fec_err_count == 1 && flit_corrected == 2048'd0)
            $display("   --> PASS: Single data error successfully corrected.");
        else begin
            $display("   --> FAIL: Could not correct single data error. count=%0d", fec_err_count); fail_count = fail_count + 1;
        end

        $display("[TEST 3] Single Error in Parity Region...");
        flit_fec_in = 2348'd0;
        flit_fec_in[50 +: 10] = 10'h15A;
        send_flit(flit_fec_in, 1'b1);
        wait_done();
        if (fec_corrected && fec_err_count == 1 && flit_corrected == 2048'd0)
            $display("   --> PASS: Single parity error correctly handled.");
        else begin
            $display("   --> FAIL: Parity error disrupted decoder."); fail_count = fail_count + 1;
        end

        $display("[TEST 4] Burst Error (4 consecutive symbols)...");
        flit_fec_in = 2348'd0;

        flit_fec_in[308 + 10*60 +: 40] = 40'hFF_FFFF_FFFF;
        send_flit(flit_fec_in, 1'b1);
        wait_done();
        if (fec_corrected && fec_err_count == 4 && !fec_uncorrectable && flit_corrected == 2048'd0)
            $display("   --> PASS: Burst error successfully corrected.");
        else begin
            $display("   --> FAIL: Failed to correct burst error. count=%0d", fec_err_count); fail_count = fail_count + 1;
        end

        $display("[TEST 5] Maximum Correctable Errors (T=15)...");
        flit_fec_in = 2348'd0;
        for (i = 0; i < 15; i = i + 1) begin

            flit_fec_in[308 + i*10*5 +: 10] = 10'h2AA;
        end
        send_flit(flit_fec_in, 1'b1);
        wait_done();
        if (fec_corrected && fec_err_count == 15 && !fec_uncorrectable && flit_corrected == 2048'd0)
            $display("   --> PASS: 15 errors corrected perfectly (T-Limit reached).");
        else begin
            $display("   --> FAIL: Failed to correct 15 errors. count=%0d", fec_err_count); fail_count = fail_count + 1;
        end

        $display("[TEST 6] Uncorrectable Errors (16 errors)...");
        flit_fec_in[308 + 15*10*5 +: 10] = 10'h111;
        send_flit(flit_fec_in, 1'b1);
        wait_done();
        if (fec_uncorrectable && !fec_corrected)
            $display("   --> PASS: Flagged as uncorrectable.");
        else begin
            $display("   --> FAIL: Did not flag 16 errors as uncorrectable."); fail_count = fail_count + 1;
        end

        $display("[TEST 7] Bypass Mode (fec_en = 0)...");
        flit_fec_in = {2348{1'b1}};
        send_flit(flit_fec_in, 1'b0);
        repeat(5) @(posedge clk);
        if (flit_corrected == {2048{1'b1}} && !fec_corrected && !fec_uncorrectable)
            $display("   --> PASS: Data bypassed FEC intact.");
        else begin
            $display("   --> FAIL: Bypass mode corrupted data."); fail_count = fail_count + 1;
        end

        $display("[TEST 8] Mid-Decode Reset...");
        flit_fec_in = 2348'd0;
        flit_fec_in[308 + 10*20 +: 10] = 10'h123;
        send_flit(flit_fec_in, 1'b1);

        repeat(100) @(posedge clk);
        @(negedge clk) rst_n = 0;
        repeat(5) @(posedge clk);

        if (flit_corrected == 2048'd0 && !fec_corrected && !fec_uncorrectable)
            $display("   --> PASS: Reset cleared all outputs successfully.");
        else begin
            $display("   --> FAIL: Reset failed to clear state."); fail_count = fail_count + 1;
        end
        rst_n = 1;
        repeat(10) @(posedge clk);

        $display("[TEST 9] Back-to-Back Decoding...");

        flit_fec_in = 2348'd0;
        flit_fec_in[308 + 10*10 +: 10] = 10'h111;
        send_flit(flit_fec_in, 1'b1);
        wait_done();

        flit_fec_in = 2348'd0;
        flit_fec_in[308 + 10*20 +: 10] = 10'h222;
        flit_fec_in[308 + 10*30 +: 10] = 10'h333;
        send_flit(flit_fec_in, 1'b1);
        wait_done();

        if (fec_corrected && fec_err_count == 2)
            $display("   --> PASS: Back-to-back decode successful.");
        else begin
            $display("   --> FAIL: Pipeline collision in back-to-back decode. count=%0d", fec_err_count); fail_count = fail_count + 1;
        end

        $display("\n===============================================================");
        if (fail_count == 0)
            $display("  [SUCCESS] ALL 9 ADVANCED TESTS PASSED PERFECTLY!");
        else
            $display("  [WARNING] %0d TESTS FAILED. CHECK VCD WAVEFORMS.", fail_count);
        $display("===============================================================\n");

        $finish;
    end
endmodule