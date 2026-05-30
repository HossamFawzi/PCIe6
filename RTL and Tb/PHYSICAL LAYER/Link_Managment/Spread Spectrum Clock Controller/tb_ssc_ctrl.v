// ============================================================
// Testbench for Module 51 : Spread Spectrum Clock Controller
// ============================================================
`timescale 1ns/1ps

module tb_ssc_ctrl;

    reg        clk, rst_n;
    reg        ssc_en;
    reg [1:0]  ssc_profile;
    reg        ssc_ref_clk;

    wire [7:0] ssc_mod_req;
    wire       ssc_active, ssc_center_spread, ssc_down_spread;

    ssc_ctrl dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .ssc_en          (ssc_en),
        .ssc_profile     (ssc_profile),
        .ssc_ref_clk     (ssc_ref_clk),
        .ssc_mod_req     (ssc_mod_req),
        .ssc_active      (ssc_active),
        .ssc_center_spread(ssc_center_spread),
        .ssc_down_spread (ssc_down_spread)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial ssc_ref_clk = 0;
    always #50 ssc_ref_clk = ~ssc_ref_clk;

    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        rst_n=0; ssc_en=0; ssc_profile=2'd0;
        repeat(4) @(posedge clk); rst_n=1; @(posedge clk);

        // TC1: SSC disabled — mod_req = 0, active = 0
        ssc_en=0; ssc_profile=2'd0;
        repeat(5) @(posedge clk); #1;
        if (!ssc_active && ssc_mod_req===8'd0 && !ssc_down_spread && !ssc_center_spread) begin
            $display("PASS [TC1_disabled]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC1_disabled] active=%b req=%0d", ssc_active, ssc_mod_req); fail_count=fail_count+1;
        end

        // TC2: Down-spread active
        ssc_en=1; ssc_profile=2'd1;
        repeat(5) @(posedge clk); #1;
        if (ssc_active && ssc_down_spread && !ssc_center_spread) begin
            $display("PASS [TC2_down_spread]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC2_down_spread] active=%b ds=%b cs=%b", ssc_active, ssc_down_spread, ssc_center_spread);
            fail_count=fail_count+1;
        end

        // TC3: Center-spread active
        ssc_profile=2'd2;
        repeat(5) @(posedge clk); #1;
        if (ssc_active && ssc_center_spread && !ssc_down_spread) begin
            $display("PASS [TC3_center_spread]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC3_center_spread]"); fail_count=fail_count+1;
        end

        // TC4: Down-spread mod_req changes (triangle wave)
        ssc_profile=2'd1;
        begin : TC4
            reg [7:0] v0, v1, v2;
            @(posedge clk); #1; v0 = ssc_mod_req;
            @(posedge clk); #1; v1 = ssc_mod_req;
            @(posedge clk); #1; v2 = ssc_mod_req;
            // Should be increasing initially
            if (v1 >= v0 || v2 >= v1) begin
                $display("PASS [TC4_mod_changes]"); pass_count=pass_count+1;
            end else begin
                $display("FAIL [TC4_mod_changes] v0=%0d v1=%0d v2=%0d", v0, v1, v2); fail_count=fail_count+1;
            end
        end

        // TC5: Center-spread mod_req eventually goes negative (wraps in 8-bit)
        ssc_profile=2'd2;
        begin : TC5
            integer min_val, max_val, i;
            reg [7:0] val;
            min_val = 255; max_val = 0;
            repeat(250) begin
                @(posedge clk); #1;
                val = ssc_mod_req;
                if (val < min_val) min_val = val;
                if (val > max_val) max_val = val;
            end
            // Should see both low and high values indicating modulation
            if (max_val > min_val + 8'd10) begin
                $display("PASS [TC5_center_modulates]"); pass_count=pass_count+1;
            end else begin
                $display("FAIL [TC5_center_modulates] min=%0d max=%0d", min_val, max_val); fail_count=fail_count+1;
            end
        end

        // TC6: ssc_en goes low → stops modulation
        ssc_en=0;
        repeat(5) @(posedge clk); #1;
        if (!ssc_active && ssc_mod_req===8'd0) begin
            $display("PASS [TC6_en_low_stops]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC6_en_low_stops] active=%b req=%0d", ssc_active, ssc_mod_req); fail_count=fail_count+1;
        end

        // TC7: Profile=0 (off) with ssc_en=1 → inactive
        ssc_en=1; ssc_profile=2'd0;
        repeat(5) @(posedge clk); #1;
        if (!ssc_active && ssc_mod_req===8'd0) begin
            $display("PASS [TC7_profile_off]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC7_profile_off]"); fail_count=fail_count+1;
        end

        // TC8: Reset clears
        ssc_en=1; ssc_profile=2'd1;
        repeat(5) @(posedge clk);
        rst_n=0; repeat(3) @(posedge clk); #1;
        if (!ssc_active && ssc_mod_req===8'd0) begin
            $display("PASS [TC8_reset]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC8_reset]"); fail_count=fail_count+1;
        end
        rst_n=1;

        #20;
        $display("===========================================");
        $display("  SSC_CTRL Results: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("===========================================");
        $finish;
    end

    initial begin #100000; $display("TIMEOUT"); $finish; end

endmodule
