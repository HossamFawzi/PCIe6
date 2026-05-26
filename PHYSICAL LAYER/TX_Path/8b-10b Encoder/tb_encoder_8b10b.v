`timescale 1ns/1ps
module tb_encoder_8b10b;

    reg        clk, rst_n;
    reg [7:0]  data_in;
    reg        k_char, data_valid;
    wire [9:0] data_out;
    wire       data_out_valid, rd_out, enc_err;

    integer pass=0, fail=0;

    encoder_8b10b dut(
        .clk(clk), .rst_n(rst_n),
        .data_in(data_in), .k_char(k_char), .data_valid(data_valid),
        .data_out(data_out), .data_out_valid(data_out_valid),
        .rd_out(rd_out), .enc_err(enc_err)
    );

    always #5 clk = ~clk;

    // Assert data_valid; output appears after the SAME posedge that latches it
    task send_byte;
        input [7:0] d; input k;
        begin
            @(posedge clk); #1; data_in=d; k_char=k; data_valid=1;
            @(posedge clk); #1; data_valid=0; // output available NOW
        end
    endtask

    function [3:0] count_ones10;
        input [9:0] v; integer i; reg [3:0] c;
        begin c=0; for(i=0;i<10;i=i+1) if(v[i]) c=c+1; count_ones10=c; end
    endfunction

    initial begin
        clk=0; rst_n=0; data_in=0; k_char=0; data_valid=0;
        @(posedge clk); @(posedge clk); rst_n=1; @(posedge clk); #1;

        // Test 1: D0.0
        $display("Test 1: D0.0 basic encoding");
        send_byte(8'h00, 0);
        if (data_out_valid && !enc_err) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: dov=%b err=%b", data_out_valid, enc_err); fail=fail+1; end

        // Test 2: K28.5 valid K-char
        $display("Test 2: K28.5 valid");
        send_byte(8'hBC, 1);
        if (data_out_valid && !enc_err) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: dov=%b err=%b", data_out_valid, enc_err); fail=fail+1; end

        // Test 3: Invalid K-char rejected
        $display("Test 3: Invalid K rejected");
        send_byte(8'h00, 1);
        if (enc_err && !data_out_valid) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: err=%b dov=%b", enc_err, data_out_valid); fail=fail+1; end

        // Test 4: DC balance
        $display("Test 4: DC balance");
        begin : dc
            integer i; integer ok; reg [3:0] ones;
            ok=1;
            for (i=0; i<8; i=i+1) begin
                send_byte(i*32, 0);
                if (data_out_valid) begin
                    ones=count_ones10(data_out);
                    if (ones<3 || ones>7) begin $display("  Bad balance d=%02h ones=%0d", i*32, ones); ok=0; end
                end
            end
            if (ok) begin $display("PASS"); pass=pass+1; end
            else    begin $display("FAIL"); fail=fail+1; end
        end

        // Test 5: Reset
        $display("Test 5: Reset");
        @(posedge clk); #1; rst_n=0; @(posedge clk); #1;
        if (!data_out_valid && data_out==10'h0) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL"); fail=fail+1; end
        rst_n=1;

        // Test 6: All valid K-chars
        $display("Test 6: All valid K-chars");
        begin : ktest
            reg [7:0] ks [0:11]; integer i; integer ok;
            ks[0]=8'hBC; ks[1]=8'hF7; ks[2]=8'hFB; ks[3]=8'hFD;
            ks[4]=8'hFE; ks[5]=8'h1C; ks[6]=8'h3C; ks[7]=8'h5C;
            ks[8]=8'h7C; ks[9]=8'h9C; ks[10]=8'hDC; ks[11]=8'hFC;
            ok=1;
            for (i=0; i<12; i=i+1) begin
                send_byte(ks[i], 1);
                if (enc_err) begin $display("  K %02h rejected", ks[i]); ok=0; end
            end
            if (ok) begin $display("PASS"); pass=pass+1; end
            else    begin $display("FAIL"); fail=fail+1; end
        end

        // Test 7: No output when idle
        $display("Test 7: No output when idle");
        @(posedge clk); #1; data_valid=0; @(posedge clk); #1;
        if (!data_out_valid) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL"); fail=fail+1; end

        // Test 8: rd_out is 0 or 1
        $display("Test 8: rd_out valid");
        send_byte(8'h55, 0);
        if (data_out_valid && (rd_out===1'b0 || rd_out===1'b1)) begin
            $display("PASS: rd_out=%b", rd_out); pass=pass+1;
        end else begin
            $display("FAIL: rd_out=%b dov=%b", rd_out, data_out_valid); fail=fail+1;
        end

        // Test 9: 10-bit output — verify port drives 10 distinct bits by checking
        // two different inputs produce different 10-bit symbols.
        $display("Test 9: 10-bit output width and encoding variety");
        begin : t9
            reg [9:0] out_a, out_b;
            send_byte(8'h00, 0); out_a = data_out;
            send_byte(8'hFF, 0); out_b = data_out;
            if (data_out_valid && out_a !== out_b) begin
                $display("PASS: 10-bit port active out_a=%b out_b=%b", out_a, out_b);
                pass=pass+1;
            end else begin
                $display("FAIL: dov=%b out_a=%b out_b=%b", data_out_valid, out_a, out_b);
                fail=fail+1;
            end
        end

        $display("\n=== encoder_8b10b: %0d PASSED, %0d FAILED ===", pass, fail);
        if (fail==0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial #20000 begin $display("TIMEOUT"); $finish; end
endmodule
