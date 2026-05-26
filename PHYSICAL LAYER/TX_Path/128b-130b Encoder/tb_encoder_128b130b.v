`timescale 1ns/1ps
module tb_encoder_128b130b;

    reg         clk, rst_n;
    reg [127:0] data_in;
    reg         is_ordered_set, data_valid;
    wire [129:0] data_out;
    wire         data_out_valid, enc_err;

    integer pass=0, fail=0;

    encoder_128b130b dut(
        .clk(clk), .rst_n(rst_n),
        .data_in(data_in), .is_ordered_set(is_ordered_set),
        .data_valid(data_valid),
        .data_out(data_out), .data_out_valid(data_out_valid),
        .enc_err(enc_err)
    );

    always #5 clk = ~clk;

    // Send one word: output appears 1 clock AFTER the clocking edge
    // cy0: assert inputs + data_valid
    // cy1 (posedge): DFF captures => outputs appear after cy1 posedge
    // So sample AFTER cy1 posedge (#1)
    task send_check;
        input [127:0] d;
        input         is_os;
        input [1:0]   exp_sh;
        input [127:0] exp_payload;
        input [63*8:1] label;
        begin
            @(posedge clk); #1;
            data_in=d; is_ordered_set=is_os; data_valid=1;
            @(posedge clk); #1;   // posedge latches; output now valid
            data_valid=0;
            if (data_out_valid && data_out[129:128]==exp_sh && data_out[127:0]==exp_payload)
                begin $display("PASS: %s", label); pass=pass+1; end
            else
                begin $display("FAIL: %s | dov=%b sh=%b pay[127:96]=%h exp_sh=%b",
                    label, data_out_valid, data_out[129:128], data_out[127:96], exp_sh);
                    fail=fail+1; end
        end
    endtask

    initial begin
        clk=0; rst_n=0; data_in=0; is_ordered_set=0; data_valid=0;
        @(posedge clk); @(posedge clk); rst_n=1; @(posedge clk); #1;

        // Test 1: Data block → SH=01
        $display("Test 1: Data block SH=01");
        send_check(128'hDEADBEEFCAFEBABE_0123456789ABCDEF, 0, 2'b01,
                   128'hDEADBEEFCAFEBABE_0123456789ABCDEF, "Data block SH=01");

        // Test 2: Ordered set → SH=10
        $display("Test 2: Ordered set SH=10");
        send_check(128'hFFFF0000FFFF0000_AABBCCDD11223344, 1, 2'b10,
                   128'hFFFF0000FFFF0000_AABBCCDD11223344, "Ordered set SH=10");

        // Test 3: Another data block - different payload
        $display("Test 3: Data payload preserved");
        send_check(128'h1122334455667788_99AABBCCDDEEFF00, 0, 2'b01,
                   128'h1122334455667788_99AABBCCDDEEFF00, "Payload preserved");

        // Test 4: No output when idle
        $display("Test 4: No output when idle");
        data_valid=0; @(posedge clk); #1; @(posedge clk); #1;
        if (!data_out_valid) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: spurious output"); fail=fail+1; end

        // Test 5: Reset clears output
        $display("Test 5: Reset");
        @(posedge clk); #1; data_in=128'hFF; data_valid=1;
        rst_n=0; @(posedge clk); #1;
        if (!data_out_valid && data_out==130'h0) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL"); fail=fail+1; end
        rst_n=1; data_valid=0; @(posedge clk); #1;

        // Test 6: Back-to-back
        $display("Test 6: Back-to-back encoding");
        begin : bb
            integer i; integer ok; ok=1;
            for (i=0; i<4; i=i+1) begin
                @(posedge clk); #1;
                data_in=i*128'h1111+128'hABCD0000; is_ordered_set=i[0]; data_valid=1;
                @(posedge clk); #1; data_valid=0;
                if (!data_out_valid) ok=0;
                if (i[0]==0 && data_out[129:128]!=2'b01) ok=0;
                if (i[0]==1 && data_out[129:128]!=2'b10) ok=0;
            end
            if (ok) begin $display("PASS"); pass=pass+1; end
            else    begin $display("FAIL"); fail=fail+1; end
        end

        // Test 7: enc_err never set for data symbols
        $display("Test 7: enc_err clear for data");
        begin : t7
            integer i; integer ok; ok=1;
            for (i=0; i<8; i=i+1) begin
                @(posedge clk); #1; data_in=i; is_ordered_set=0; data_valid=1;
                @(posedge clk); #1; data_valid=0;
                if (enc_err) ok=0;
            end
            if (ok) begin $display("PASS"); pass=pass+1; end
            else    begin $display("FAIL: enc_err seen"); fail=fail+1; end
        end

        $display("\n=== encoder_128b130b: %0d PASSED, %0d FAILED ===", pass, fail);
        if (fail==0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial #10000 begin $display("TIMEOUT"); $finish; end
endmodule
