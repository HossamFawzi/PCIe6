`timescale 1ns/1ps
module tb_fec_encoder_rs;

    reg          clk, rst_n;
    reg [2047:0] flit_in;
    reg          flit_valid, fec_en;
    wire [2347:0] flit_fec_out;
    wire [299:0]  fec_parity;
    wire          fec_valid;

    integer pass=0, fail=0;

    fec_encoder_rs dut(
        .clk(clk), .rst_n(rst_n),
        .flit_in(flit_in), .flit_valid(flit_valid), .fec_en(fec_en),
        .flit_fec_out(flit_fec_out), .fec_parity(fec_parity), .fec_valid(fec_valid)
    );

    always #5 clk = ~clk;
    task tick; input integer n; integer i; begin for(i=0;i<n;i=i+1) @(posedge clk); #1; end endtask

    // Kick off encoding and wait for fec_valid, up to 300 cycles
    // Returns 1 if fec_valid seen, 0 on timeout
    task do_encode;
        input  [2047:0] flit;
        output reg      got;
        integer i;
        begin
            @(posedge clk); #1;
            flit_in=flit; flit_valid=1; fec_en=1;
            @(posedge clk); #1; flit_valid=0;
            got=0;
            for (i=0; i<300; i=i+1) begin
                @(posedge clk); #1;
                if (fec_valid) begin got=1; i=300; end
            end
        end
    endtask

    reg         got;
    reg [299:0] p1, p2;
    reg [2047:0] saved_flit;
    integer     cycles;

    initial begin
        clk=0; rst_n=0;
        flit_in=0; flit_valid=0; fec_en=0;
        tick(4); rst_n=1; tick(2);

        // Test 1: Reset state - fec_valid=0
        $display("Test 1: Reset state");
        if (!fec_valid) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: fec_valid after reset"); fail=fail+1; end

        // Test 2: Encoding zero FLIT completes
        $display("Test 2: Encode zero FLIT completes");
        do_encode(2048'h0, got);
        if (got) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: No fec_valid"); fail=fail+1; end

        // Test 3: FLIT preserved in output (upper 2048b of 2348b output)
        $display("Test 3: Zero FLIT preserved in output");
        if (flit_fec_out[2347:300] == 2048'h0) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: FLIT portion wrong"); fail=fail+1; end

        // Test 4: Non-zero parity for all-ones FLIT
        $display("Test 4: Non-zero parity for non-zero data");
        do_encode({2048{1'b1}}, got);
        if (got && fec_parity != 300'h0) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: parity=%h valid=%b", fec_parity[29:0], got); fail=fail+1; end

        // Test 5: Non-trivial FLIT preserved in flit_fec_out
        $display("Test 5: FLIT preserved in output");
        saved_flit = 2048'hDEAD_BEEF_CAFE_BABE_1234_5678_ABCD_EF01;
        do_encode(saved_flit, got);
        if (got && flit_fec_out[2347:300]==saved_flit) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: FLIT mismatch got=%b", got); fail=fail+1; end

        // Test 6: fec_en=0 blocks encoding
        $display("Test 6: fec_en=0 blocks encoding");
        @(posedge clk); #1; flit_in={2048{1'b1}}; flit_valid=1; fec_en=0;
        @(posedge clk); #1; flit_valid=0;
        tick(250);
        if (!fec_valid) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: encoded without fec_en"); fail=fail+1; end

        // Test 7: Deterministic - same input => same parity
        $display("Test 7: Deterministic encoding");
        do_encode(2048'hABCDEF_123456, got); p1=fec_parity;
        do_encode(2048'hABCDEF_123456, got); p2=fec_parity;
        if (got && p1==p2) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: p1=%h p2=%h", p1[29:0], p2[29:0]); fail=fail+1; end

        // Test 8: Different inputs => different parity
        $display("Test 8: Different inputs differ");
        do_encode(2048'h11223344, got); p1=fec_parity;
        do_encode(2048'h55667788, got); p2=fec_parity;
        if (got && p1!=p2) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: Same parity for different inputs"); fail=fail+1; end

        // Test 9: Reset mid-encoding clears state
        $display("Test 9: Reset mid-encoding");
        @(posedge clk); #1; flit_in=2048'hFFFF; flit_valid=1; fec_en=1;
        @(posedge clk); #1; flit_valid=0;
        tick(10); rst_n=0; tick(3);
        if (!fec_valid) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: fec_valid after reset"); fail=fail+1; end
        rst_n=1; tick(2);

        // Test 10: Encoding latency <= 210 cycles
        $display("Test 10: Encoding latency");
        fec_en=1;
        @(posedge clk); #1; flit_in=2048'hABCD; flit_valid=1;
        @(posedge clk); #1; flit_valid=0;
        cycles=0;
        begin : lat
            integer i;
            for (i=0; i<220; i=i+1) begin
                @(posedge clk); #1; cycles=cycles+1;
                if (fec_valid) i=220;
            end
        end
        if (fec_valid && cycles<=210) begin $display("PASS: %0d cycles", cycles); pass=pass+1; end
        else begin $display("FAIL: cycles=%0d valid=%b", cycles, fec_valid); fail=fail+1; end

        $display("\n=== fec_encoder_rs: %0d PASSED, %0d FAILED ===", pass, fail);
        if (fail==0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial #2000000 begin $display("TIMEOUT"); $finish; end
endmodule
