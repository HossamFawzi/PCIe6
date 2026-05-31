
`timescale 1ns/1ps

module tb_pam4_gray_enc;

    reg          clk;
    reg          rst_n;
    reg  [255:0] data_in;
    reg          data_valid;
    reg          pam4_en;

    wire [127:0] pam4_symbols;
    wire         pam4_valid;

    pam4_gray_enc DUT (
        .clk         (clk),
        .rst_n       (rst_n),
        .data_in     (data_in),
        .data_valid  (data_valid),
        .pam4_en     (pam4_en),
        .pam4_symbols(pam4_symbols),
        .pam4_valid  (pam4_valid)
    );

    initial clk = 0;
    always  #2 clk = ~clk;

    function [1:0] gray_ref;
        input [1:0] bin;
        begin
            gray_ref[1] = bin[1];
            gray_ref[0] = bin[1] ^ bin[0];
        end
    endfunction

    function [127:0] expected_gray;
        input [255:0] din;
        integer i;
        begin
            for (i = 0; i < 128; i = i + 1) begin
                expected_gray[2*i +: 2] = gray_ref(din[2*i +: 2]);
            end
        end
    endfunction

    integer pass_count;
    integer fail_count;

    task wait_clks;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    task check_bits;
        input [127:0] got;
        input [127:0] expected;
        input [127:0] label;
        begin
            if (got === expected) begin
                $display("  PASS  %s", label);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %s", label);
                $display("        got      = %h", got);
                $display("        expected = %h", expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check1;
        input got;
        input expected;
        input [127:0] label;
        begin
            if (got === expected) begin
                $display("  PASS  %-40s  got=%b", label, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %-40s  got=%b  expected=%b",
                         label, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    integer i;
    reg [255:0] test_vec;
    reg [127:0] exp_out;

    initial begin
        pass_count  = 0;
        fail_count  = 0;
        rst_n       = 0;
        data_in     = 256'b0;
        data_valid  = 0;
        pam4_en     = 1;

        $display("\n=== pam4_gray_enc Testbench ===\n");

        $display("--- Test 1: Reset State ---");
        wait_clks(4);
        @(posedge clk);
        #1;
        check_bits(pam4_symbols, 128'b0, "pam4_symbols = 0 in reset");
        check1(pam4_valid, 0,            "pam4_valid = 0 in reset");

        rst_n = 1;
        wait_clks(2);

        $display("\n--- Test 2: Gray Code Truth Table (per symbol) ---");

        data_in    = 256'b0;
        data_valid = 1;
        @(posedge clk); #1;
        @(posedge clk); #1;

        check_bits(pam4_symbols, 128'b0, "All-00 binary ? all-00 Gray");

        test_vec = 256'b0;
        for (i = 0; i < 128; i = i + 1)
            test_vec[2*i +: 2] = 2'b01;
        data_in = test_vec;
        @(posedge clk); #1;
        @(posedge clk); #1;

        exp_out = 128'b0;
        for (i = 0; i < 128; i = i + 1) exp_out[2*i +: 2] = 2'b01;
        check_bits(pam4_symbols, exp_out, "All-01 binary ? all-01 Gray");

        test_vec = 256'b0;
        for (i = 0; i < 128; i = i + 1)
            test_vec[2*i +: 2] = 2'b10;
        data_in = test_vec;
        @(posedge clk); #1;
        @(posedge clk); #1;

        exp_out = 128'b0;
        for (i = 0; i < 128; i = i + 1) exp_out[2*i +: 2] = 2'b11;
        check_bits(pam4_symbols, exp_out, "All-10 binary ? all-11 Gray");

        test_vec = 256'b0;
        for (i = 0; i < 128; i = i + 1)
            test_vec[2*i +: 2] = 2'b11;
        data_in = test_vec;
        @(posedge clk); #1;
        @(posedge clk); #1;

        exp_out = 128'b0;
        for (i = 0; i < 128; i = i + 1) exp_out[2*i +: 2] = 2'b10;
        check_bits(pam4_symbols, exp_out, "All-11 binary ? all-10 Gray");
        data_valid = 0;

        $display("\n--- Test 3: Mixed Pattern 256-bit Word ---");

        test_vec = 256'b0;
        for (i = 0; i < 128; i = i + 1)
            test_vec[2*i +: 2] = i[1:0];
        exp_out = expected_gray(test_vec);

        data_in    = test_vec;
        data_valid = 1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check_bits(pam4_symbols, exp_out, "Mixed 00/01/10/11 pattern");
        data_valid = 0;

        $display("\n--- Test 4: Bypass Mode (pam4_en = 0) ---");
        pam4_en   = 0;

        test_vec = 256'b0;
        for (i = 0; i < 128; i = i + 1)
            test_vec[2*i +: 2] = 2'b10;
        data_in    = test_vec;
        data_valid = 1;
        @(posedge clk); #1;
        @(posedge clk); #1;

        check_bits(pam4_symbols, test_vec[127:0], "Bypass: output = data_in[127:0]");
        data_valid = 0;
        pam4_en    = 1;

        $display("\n--- Test 5: pam4_valid follows data_valid (1-cycle latency) ---");
        data_valid = 0;
        wait_clks(3);
        check1(pam4_valid, 0, "pam4_valid = 0 when data_valid = 0");

        data_in    = {8{32'hDEAD_BEEF}};
        data_valid = 1;
        @(posedge clk); #1;
        check1(pam4_valid, 1, "pam4_valid HIGH one cycle after data_valid");

        data_valid = 0;
        @(posedge clk); #1;
        check1(pam4_valid, 0, "pam4_valid LOW one cycle after data_valid drops");

        $display("\n--- Test 6: Back-to-Back Valid Cycles ---");
        data_valid = 1;
        for (i = 0; i < 4; i = i + 1) begin

            data_in = {128{i[1:0], i[1:0]}};
            @(posedge clk); #1;
            check1(pam4_valid, 1, "pam4_valid HIGH each cycle");
        end
        data_valid = 0;
        @(posedge clk);

        $display("\n--- Test 7: Output Hold on data_valid De-assert ---");

        test_vec   = {32{8'hA5}};
        data_in    = test_vec;
        data_valid = 1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        exp_out    = expected_gray(test_vec);
        check_bits(pam4_symbols, exp_out, "Correct output after one valid cycle");

        data_in    = 256'b0;
        data_valid = 0;
        @(posedge clk); #1;
        check_bits(pam4_symbols, exp_out, "Output held after data_valid drops");

        $display("\n=== SUMMARY: %0d passed, %0d failed ===\n",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED\n");
        else
            $display("SOME TESTS FAILED\n");

        $finish;
    end

    initial begin
        #100_000;
        $display("TIMEOUT");
        $finish;
    end

    initial begin
        $dumpfile("pam4_gray_enc.vcd");
        $dumpvars(0, tb_pam4_gray_enc);
    end

endmodule
