`timescale 1ns / 1ps

module tb_poisoned_tlp_handler;

    // -- Clock & Reset --
    reg clk;
    reg rst_n;
    parameter CLK_PERIOD = 4;

    // -- DUT Signals --
    reg        tlp_ep_bit;
    reg [4:0]  tlp_type;
    reg        tlp_ok;
    reg [1023:0] tlp_rx;

    wire       poisoned_detected;
    wire       poison_drop;
    wire [2:0] poison_to_aer;
    wire       tlp_fwd_valid;

    // -- Instantiate DUT --
    poisoned_tlp_handler dut (
        .clk(clk),
        .rst_n(rst_n),
        .tlp_ep_bit(tlp_ep_bit),
        .tlp_type(tlp_type),
        .tlp_ok(tlp_ok),
        .tlp_rx(tlp_rx),
        .poisoned_detected(poisoned_detected),
        .poison_drop(poison_drop),
        .poison_to_aer(poison_to_aer),
        .tlp_fwd_valid(tlp_fwd_valid)
    );

    // -- Clock Generation --
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // -- Test Procedure --
    initial begin
        // Initialize
        rst_n = 1'b0;
        tlp_ep_bit = 0;
        tlp_type = 0;
        tlp_ok = 0;
        tlp_rx = 0;
        
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        $display("========================================");
        $display("   TB: Poisoned TLP Handler");
        $display("========================================");

        // -------------------------------------------------
        // Test 1: Clean MRd (EP=0)
        // -------------------------------------------------
        tlp_ok = 1'b1;
        tlp_ep_bit = 1'b0;
        tlp_type = 5'b00000; // MRd
        
        @(posedge clk); // Cycle 1: RTL samples inputs
        #1;             // Small delay to let logic settle
        
        if (tlp_fwd_valid === 1'b1 && poisoned_detected === 1'b0) begin
            $display("Test 1: Clean MRd (EP=0) - PASS");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("Test 1: Clean MRd (EP=0) - FAIL (fwd=%b, det=%b)", tlp_fwd_valid, poisoned_detected);
            fail_cnt = fail_cnt + 1;
        end
        
        tlp_ok = 1'b0; // Deassert between tests
        @(posedge clk);

        // -------------------------------------------------
        // Test 2: Poisoned MWr (EP=1)
        // -------------------------------------------------
        tlp_ok = 1'b1;
        tlp_ep_bit = 1'b1;
        tlp_type = 5'b00001; // MWr
        
        @(posedge clk);
        #1;
        
        if (tlp_fwd_valid === 1'b0 && poisoned_detected === 1'b1 && poison_drop === 1'b1) begin
            $display("Test 2: Poisoned MWr (EP=1) - PASS");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("Test 2: Poisoned MWr (EP=1) - FAIL");
            fail_cnt = fail_cnt + 1;
        end
        
        tlp_ok = 1'b0;
        @(posedge clk);

        // -------------------------------------------------
        // Test 3: Poisoned CplD (EP=1) - Check AER
        // -------------------------------------------------
        tlp_ok = 1'b1;
        tlp_ep_bit = 1'b1;
        tlp_type = 5'b01010; // CplD
        
        @(posedge clk);
        #1;
        
        if (poison_to_aer === 3'b010) begin // AER_NON_FATAL
            $display("Test 3: Poisoned CplD (EP=1) - PASS: AER=non-fatal");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("Test 3: Poisoned CplD (EP=1) - FAIL (AER=%b)", poison_to_aer);
            fail_cnt = fail_cnt + 1;
        end
        
        tlp_ok = 1'b0;
        @(posedge clk);

        // -------------------------------------------------
        // Test 4: Malformed TLP (tlp_ok=0)
        // -------------------------------------------------
        tlp_ok = 1'b0;
        tlp_ep_bit = 1'b1; // Even if EP is set, tlp_ok=0 should block everything
        
        @(posedge clk);
        #1;
        
        if (tlp_fwd_valid === 1'b0 && poisoned_detected === 1'b0) begin
            $display("Test 4: Malformed (tlp_ok=0) - PASS");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("Test 4: Malformed (tlp_ok=0) - FAIL");
            fail_cnt = fail_cnt + 1;
        end

        // -------------------------------------------------
        // Summary
        // -------------------------------------------------
        $display("========================================");
        $display("   Results: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
        $display("========================================");
        #10;
        $finish;
    end

endmodule