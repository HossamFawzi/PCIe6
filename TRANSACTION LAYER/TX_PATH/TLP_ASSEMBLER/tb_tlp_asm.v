// =============================================================================
// tb_tlp_asm.v
// Comprehensive Verification Testbench for TLP Assembler (Fixed TC7 Timing)
// =============================================================================

`timescale 1ns/1ps

module tb_tlp_asm;

    // ?? Signals ???????????????????????????????????????????????????????????????
    reg          clk;
    reg          rst_n;
    reg  [575:0] arb_tlp_in;
    reg          arb_tlp_valid;
    reg  [127:0] prefix_in;
    reg          prefix_valid;
    reg  [31:0]  ecrc_in;
    reg          credit_ok;
    reg  [2:0]   max_payload;

    wire [1023:0] tlp_out;
    wire          tlp_valid;
    wire          tlp_sop;
    wire          tlp_eop;
    wire [127:0]  tlp_hdr;
    wire [127:0]  tlp_be;

    integer fail_count = 0;

    // ?? DUT Instantiation ?????????????????????????????????????????????????????
    tlp_assembler u_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .arb_tlp_in    (arb_tlp_in),
        .arb_tlp_valid (arb_tlp_valid),
        .prefix_in     (prefix_in),
        .prefix_valid  (prefix_valid),
        .ecrc_in       (ecrc_in),
        .credit_ok     (credit_ok),
        .max_payload   (max_payload),
        .tlp_out       (tlp_out),
        .tlp_valid     (tlp_valid),
        .tlp_sop       (tlp_sop),
        .tlp_eop       (tlp_eop),
        .tlp_hdr       (tlp_hdr),
        .tlp_be        (tlp_be)
    );

    // ?? Clock Generation ??????????????????????????????????????????????????????
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz Clock
    end

    // ?? Helper Tasks ??????????????????????????????????????????????????????????
    task drive_tlp;
        input [63:0]  hdr_info;
        input [511:0] data;
        input [127:0] pfx;
        input         pfx_val;
        begin
            @(negedge clk);
            arb_tlp_in    = {hdr_info, data};
            prefix_in     = pfx;
            prefix_valid  = pfx_val;
            arb_tlp_valid = 1'b1;
            @(negedge clk);
            arb_tlp_valid = 1'b0;
            prefix_valid  = 1'b0;
        end
    endtask

    task reset_system;
        begin
            rst_n         = 0;
            arb_tlp_in    = 576'd0;
            arb_tlp_valid = 0;
            prefix_in     = 128'd0;
            prefix_valid  = 0;
            ecrc_in       = 32'hEC123456; 
            credit_ok     = 1;
            max_payload   = 3'd1; 
            repeat(4) @(posedge clk);
            rst_n         = 1;
            @(posedge clk);
        end
    endtask

    // ?? Main Simulation ???????????????????????????????????????????????????????
    initial begin
        $display("\n=======================================================");
        $display("  Starting Comprehensive TLP Assembler Simulation");
        $display("=======================================================\n");
        
        reset_system();

        // ---------------------------------------------------------
        // TC1: Standard 3DW Data TLP (MWr)
        // ---------------------------------------------------------
        $display("TC1: Standard 3DW Data TLP");
        drive_tlp({32'h0, 12'h0, 1'b0, 1'b1, 18'h0}, {16{32'hAAAA_BBBB}}, 128'h0, 1'b0);
        @(posedge clk); 
        
        if (tlp_valid === 1'b1) $display("  [PASS] TC1: Valid Asserted");
        else begin $display("  [FAIL] TC1: Valid Asserted @ t=%0t", $time); fail_count = fail_count + 1; end

        if (tlp_out[767:256] === {16{32'hAAAA_BBBB}}) $display("  [PASS] TC1: Data payload preserved");
        else begin $display("  [FAIL] TC1: Data payload preserved @ t=%0t", $time); fail_count = fail_count + 1; end
        #10;

        // ---------------------------------------------------------
        // TC2: 4DW Header Placeholder Verification
        // ---------------------------------------------------------
        $display("\nTC2: 4DW Header TLP");
        drive_tlp({32'h0, 12'h0, 1'b1, 1'b1, 18'h0}, 512'h0, 128'h0, 1'b0);
        @(posedge clk);
        
        if (tlp_hdr[127:96] === 32'hDEAD_C0DE) $display("  [PASS] TC2: 4DW DW3 Placeholder is 0xDEADC0DE");
        else begin $display("  [FAIL] TC2: 4DW DW3 Placeholder @ t=%0t", $time); fail_count = fail_count + 1; end
        #10;

        // ---------------------------------------------------------
        // TC3: Header-Only / No-Data TLP (MRd)
        // ---------------------------------------------------------
        $display("\nTC3: Header-Only TLP (Ignores Garbage Data)");
        drive_tlp({32'h0, 12'h0, 1'b0, 1'b0, 18'h0}, {16{32'hDEAD_DEAD}}, 128'h0, 1'b0);
        @(posedge clk);
        
        if (tlp_valid === 1'b1) $display("  [PASS] TC3: Valid Asserted");
        else begin $display("  [FAIL] TC3: Valid Asserted @ t=%0t", $time); fail_count = fail_count + 1; end

        if (tlp_out[767:256] === 512'd0) $display("  [PASS] TC3: Payload forced to zero because has_data=0");
        else begin $display("  [FAIL] TC3: Payload forced to zero @ t=%0t", $time); fail_count = fail_count + 1; end
        #10;

        // ---------------------------------------------------------
        // TC4: Prefix Insertion
        // ---------------------------------------------------------
        $display("\nTC4: TLP Prefix Insertion");
        drive_tlp({32'h0, 12'h0, 1'b0, 1'b1, 18'h0}, 512'h0, {4{32'hB0B0_C0C0}}, 1'b1);
        @(posedge clk);
        
        if (tlp_out[1023:896] === {4{32'hB0B0_C0C0}}) $display("  [PASS] TC4: Prefix injected correctly");
        else begin $display("  [FAIL] TC4: Prefix injected correctly @ t=%0t", $time); fail_count = fail_count + 1; end
        #10;

        // ---------------------------------------------------------
        // TC5: Byte Enable Masking
        // ---------------------------------------------------------
        $display("\nTC5: Byte Enable Masking");
        drive_tlp({32'h0, 14'h0, 4'hA, 14'h0}, 512'h0, 128'h0, 1'b0);
        @(posedge clk);
        
        if (tlp_be[127:124] === 4'hA) $display("  [PASS] TC5: tlp_be mask maps last_be correctly");
        else begin $display("  [FAIL] TC5: tlp_be mask maps @ t=%0t", $time); fail_count = fail_count + 1; end
        #10;

        // ---------------------------------------------------------
        // TC6: Credit Back-Pressure Stall & Release
        // ---------------------------------------------------------
        $display("\nTC6: Credit Back-pressure");
        @(negedge clk);
        credit_ok = 1'b0; // STALL
        arb_tlp_in = {64'h0, 512'hFFFF_FFFF};
        arb_tlp_valid = 1'b1;
        
        @(posedge clk); #1;
        if (tlp_valid === 1'b0) $display("  [PASS] TC6: Output strictly held while credit_ok=0");
        else begin $display("  [FAIL] TC6: Output strictly held @ t=%0t", $time); fail_count = fail_count + 1; end
        
        @(negedge clk);
        credit_ok = 1'b1; // RELEASE
        
        @(posedge clk); #1;
        if (tlp_valid === 1'b1) $display("  [PASS] TC6: Output released when credit_ok=1");
        else begin $display("  [FAIL] TC6: Output released @ t=%0t", $time); fail_count = fail_count + 1; end
        
        @(negedge clk); arb_tlp_valid = 1'b0;
        #10;

        // ---------------------------------------------------------
        // TC7: Back-to-Back Pipeline Burst (Fixed Timing & Header)
        // ---------------------------------------------------------
        $display("\nTC7: Back-to-Back Pipeline Burst");
        @(negedge clk);
        arb_tlp_valid = 1'b1;
        credit_ok     = 1'b1;
        
        // Drive Beat 1 (Setting bit 18 `has_data` = 1)
        arb_tlp_in = {{32'h0, 12'h0, 1'b0, 1'b1, 18'h0}, {16{32'h1111_1111}}};
        
        @(negedge clk);
        // Drive Beat 2
        arb_tlp_in = {{32'h0, 12'h0, 1'b0, 1'b1, 18'h0}, {16{32'h2222_2222}}};
        // Check Beat 1 synchronously
        if (tlp_valid && tlp_out[767:256] === {16{32'h1111_1111}}) $display("  [PASS] TC7: Beat 1 correct");
        else begin $display("  [FAIL] TC7: Beat 1 correct @ t=%0t", $time); fail_count = fail_count + 1; end

        @(negedge clk);
        // Drive Beat 3
        arb_tlp_in = {{32'h0, 12'h0, 1'b0, 1'b1, 18'h0}, {16{32'h3333_3333}}};
        // Check Beat 2 synchronously
        if (tlp_valid && tlp_out[767:256] === {16{32'h2222_2222}}) $display("  [PASS] TC7: Beat 2 correct");
        else begin $display("  [FAIL] TC7: Beat 2 correct @ t=%0t", $time); fail_count = fail_count + 1; end

        @(negedge clk);
        // End Burst
        arb_tlp_valid = 1'b0;
        // Check Beat 3 synchronously
        if (tlp_valid && tlp_out[767:256] === {16{32'h3333_3333}}) $display("  [PASS] TC7: Beat 3 correct");
        else begin $display("  [FAIL] TC7: Beat 3 correct @ t=%0t", $time); fail_count = fail_count + 1; end

        #30;

        // ---------------------------------------------------------
        // End of Simulation Summary
        // ---------------------------------------------------------
        $display("\n=======================================================");
        if (fail_count == 0)
            $display("  [SUCCESS] ALL TESTS PASSED! RTL is Solid.");
        else
            $display("  [WARNING] %0d TESTS FAILED. Review transcripts.", fail_count);
        $display("=======================================================\n");
        $finish;
    end

endmodule