// ============================================================
// Testbench for Module 50 : Compliance Pattern Generator
// ============================================================
`timescale 1ns/1ps

module tb_compl_gen;

    reg        clk, rst_n;
    reg        compliance_req;
    reg [3:0]  compliance_pattern;
    reg [2:0]  deemph_req;

    wire [255:0] compl_data;
    wire         compl_valid, compl_active;

    compl_gen dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .compliance_req    (compliance_req),
        .compliance_pattern(compliance_pattern),
        .deemph_req        (deemph_req),
        .compl_data        (compl_data),
        .compl_valid       (compl_valid),
        .compl_active      (compl_active)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    initial begin
        rst_n=0; compliance_req=0; compliance_pattern=0; deemph_req=0;
        repeat(4) @(posedge clk); rst_n=1; @(posedge clk);

        // TC1: Pattern 0 — alternating 0xAA
        compliance_req=1; compliance_pattern=4'd0; deemph_req=3'd0;
        @(posedge clk); #1;
        if (compl_active && compl_valid &&
            compl_data === 256'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA) begin
            $display("PASS [TC1_pattern0_AA]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC1_pattern0_AA] data=%h", compl_data); fail_count=fail_count+1;
        end

        // TC2: Pattern 1 — alternating 0x55
        compliance_pattern=4'd1;
        @(posedge clk); #1;
        if (compl_valid &&
            compl_data === 256'h5555555555555555555555555555555555555555555555555555555555555555) begin
            $display("PASS [TC2_pattern1_55]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC2_pattern1_55] data=%h", compl_data); fail_count=fail_count+1;
        end

        // TC3: Pattern 3 — COM repeating (0xBC)
        compliance_pattern=4'd3;
        @(posedge clk); #1;
        begin : TC3
            integer ok; ok=1;
            for (i=0; i<32; i=i+1)
                if (compl_data[i*8 +: 8] !== 8'hBC) ok=0;
            if (ok) begin $display("PASS [TC3_pattern3_BC]"); pass_count=pass_count+1; end
            else    begin $display("FAIL [TC3_pattern3_BC] data=%h", compl_data); fail_count=fail_count+1; end
        end

        // TC4: Pattern 4 — 0xFF
        compliance_pattern=4'd4;
        @(posedge clk); #1;
        begin : TC4
            integer ok; ok=1;
            for (i=0; i<32; i=i+1)
                if (compl_data[i*8 +: 8] !== 8'hFF) ok=0;
            if (ok) begin $display("PASS [TC4_pattern4_FF]"); pass_count=pass_count+1; end
            else    begin $display("FAIL [TC4_pattern4_FF]"); fail_count=fail_count+1; end
        end

        // TC5: Pattern 7 — all zeros
        compliance_pattern=4'd7;
        @(posedge clk); #1;
        if (compl_data === 256'd0) begin
            $display("PASS [TC5_pattern7_zero]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC5_pattern7_zero] data=%h", compl_data); fail_count=fail_count+1;
        end

        // TC6: compliance_req=0 → valid and active deassert
        compliance_req=0;
        @(posedge clk); #1;
        if (!compl_valid && !compl_active && compl_data===256'd0) begin
            $display("PASS [TC6_req_low]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC6_req_low] valid=%b active=%b", compl_valid, compl_active);
            fail_count=fail_count+1;
        end

        // TC7: Continuous output when req=1
        compliance_req=1; compliance_pattern=4'd0;
        begin : TC7
            integer valid_cnt; valid_cnt=0;
            repeat(10) begin @(posedge clk); #1; if(compl_valid) valid_cnt=valid_cnt+1; end
            if (valid_cnt===10) begin $display("PASS [TC7_continuous]"); pass_count=pass_count+1; end
            else                begin $display("FAIL [TC7_continuous] cnt=%0d",valid_cnt); fail_count=fail_count+1; end
        end
        compliance_req=0;

        // TC8: Reset clears
        rst_n=0; repeat(3) @(posedge clk); #1;
        if (!compl_valid && !compl_active) begin
            $display("PASS [TC8_reset]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC8_reset]"); fail_count=fail_count+1;
        end
        rst_n=1;

        // TC9: Pattern 5 — checkerboard
        compliance_req=1; compliance_pattern=4'd5;
        @(posedge clk); #1;
        begin : TC9
            integer ok; ok=1;
            for (i=0; i<16; i=i+1) begin
                if (compl_data[i*16 +  0 +: 8] !== 8'h33) ok=0;
                if (compl_data[i*16 +  8 +: 8] !== 8'hCC) ok=0;
            end
            if (ok) begin $display("PASS [TC9_pattern5_checker]"); pass_count=pass_count+1; end
            else    begin $display("FAIL [TC9_pattern5_checker] data=%h", compl_data); fail_count=fail_count+1; end
        end
        compliance_req=0;

        #20;
        $display("===========================================");
        $display("  COMPL_GEN Results: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("===========================================");
        $finish;
    end

    initial begin #10000; $display("TIMEOUT"); $finish; end

endmodule
